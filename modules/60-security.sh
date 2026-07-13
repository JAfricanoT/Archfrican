#!/usr/bin/env bash
# Phase 2, step 6: workstation hardening + FIDO2 PAM. Dev-safe controls are always-on
# (cannot break gdb/strace/perf/eBPF/Docker/podman/local servers); anything riskier is
# env-gated and fails open. FIDO2 PAM is wired only if a key was enrolled in the wizard.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/security.sh"
source "$REPO_ROOT/lib/fido2.sh"

substep "installing the security backbone (nftables, pam-u2f, libfido2, bubblewrap)"
pac_install_file "$REPO_ROOT/packages/security.txt"

# ---- firewall: nftables, deny-inbound, Docker/podman-safe -------------------
# The include file for user `fw-allow` rules must exist before nftables.conf loads it.
[ -f "$ARCHFRICAN_FW_ALLOWS" ] || printf '%s\n' \
  '# Managed by fw-allow. One "add rule inet filter input ... accept" per line.' \
  | write_system_file "$ARCHFRICAN_FW_ALLOWS" 0644
substep "writing the nftables firewall (replaces ONLY our table — never flushes Docker's)"
write_system_file /etc/nftables.conf 0644 <<'NFT'
#!/usr/bin/nft -f
# Archfrican firewall. Re-loading replaces ONLY this table (create/delete/recreate); it
# never wipes the WHOLE nftables state, so Docker/podman/libvirt tables are left intact.
# Open a port with:  fw-allow <port>/<tcp|udp>
# Published container ports keep working: Docker's prerouting DNAT bypasses this input hook.
table inet filter
delete table inet filter
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        ct state established,related accept
        ct state invalid drop
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        udp sport 67 udp dport 68 accept
        udp sport 547 udp dport 546 accept
        udp dport 5353 accept
    }
    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        # Docker/podman/libvirt route container/VM traffic through this hook — a container's first
        # outbound packet is ct state "new", not yet "established", so without this a strict drop
        # policy breaks basic outbound networking for every container/VM. Scoped to known bridge
        # interfaces only (not "accept everything new"), verified live: Docker's default bridge
        # (docker0) plus this scoping still let a container reach the internet.
        ct state new iifname "docker0" accept
        ct state new iifname "br-*" accept
        ct state new iifname "podman0" accept
        ct state new iifname "podman1" accept
        ct state new iifname "virbr*" accept
        # The other direction: a published port (docker run -p / podman run -p) is reached from
        # OUTSIDE via Docker's own prerouting DNAT, which rewrites the destination to the container
        # BEFORE this hook runs — the packet arrives here with oifname = the bridge, not iifname. Without
        # this, "policy drop" would silently break every published port reachable from the LAN/another
        # host (loopback-only access from the same machine isn't affected — that never reaches forward).
        # Safe to scope the same way: DNAT already decided this connection is a container/VM Docker or
        # podman explicitly exposed, nothing reaches these bridges' subnets without it.
        ct state new oifname "docker0" accept
        ct state new oifname "br-*" accept
        ct state new oifname "podman0" accept
        ct state new oifname "podman1" accept
        ct state new oifname "virbr*" accept
    }
    chain output  { type filter hook output  priority filter; policy accept; }
}
include "/etc/nftables.d/archfrican-allows.nft"
NFT
substep "overriding nftables ExecStop so a stop never flushes other tables"
write_system_file /etc/systemd/system/nftables.service.d/10-archfrican.conf 0644 <<'UNIT'
[Service]
# The upstream unit is Type=oneshot with no RemainAfterExit — it settles "inactive" the instant
# ExecStart returns, so systemd never has a reliable "this is currently active" window to key a
# later `stop`/`restart` off. In practice that made `systemctl restart nftables` non-deterministic:
# our ExecStop (below) could run AFTER the following ExecStart in the same restart cycle instead of
# before it, deleting the table we'd just (re)created and leaving the firewall unloaded until reboot.
# RemainAfterExit=yes keeps the unit "active (exited)" once ExecStart succeeds, so restart/stop are
# ordinary stop-then-start again — verified live: a stale nftables.conf load could look like "the
# fix isn't live" purely because of this, even though the file on disk was already correct.
RemainAfterExit=yes
# Tear down ONLY our table on stop (never the whole ruleset). Leading '-' tolerates the
# table being absent (stop after a failed start, or a double-stop) so the unit isn't marked failed.
ExecStop=
ExecStop=-/usr/bin/nft delete table inet filter
UNIT
sudo systemctl daemon-reload
resilient_enable nftables.service
ok "firewall staged (active next boot). Open a port with:  fw-allow <port>/<tcp|udp>"

# ---- SSH server (OPT-IN: the wizard toggle arg, or ARCHFRICAN_ENABLE_SSH=1) --
# Off by default — a workstation is deny-inbound. When enabled, ssh_enable_hardened writes a hardened
# sshd drop-in, enables/starts sshd, and opens 22/tcp via fw_allow. openssh itself is always installed
# (packages/security.txt), so a later opt-in needs no reinstall.
if [ "${1:-no}" = yes ] || [ "${ARCHFRICAN_ENABLE_SSH:-0}" = 1 ]; then
  ssh_enable_hardened
else
  ok "SSH server left OFF (opt-in: the wizard toggle, or ARCHFRICAN_ENABLE_SSH=1)"
fi

# ---- ssh-agent (ALWAYS ON — outbound: YOUR key, for git/GitHub/GitLab, unrelated to the
# inbound server above). A passphrase-protected key (archfrican-git invites you to set one) is
# useless without a running agent to hold the decrypted key: without this, every git/ssh over
# SSH silently fails with "Permission denied (publickey)" and no clue why. systemd ships this
# socket ready to go; it just needs enabling. SSH_AUTH_SOCK itself is exported session-wide by
# home/dot_config/environment.d/20-ssh-agent.conf (takes effect next login, same caveat as
# PATH's 10-path.conf in that same directory).
substep "enabling ssh-agent.socket (outbound: your own SSH key for git/GitHub/GitLab)"
resilient_enable_user ssh-agent.socket

# ---- sysctl: dev-safe hardening ---------------------------------------------
substep "writing dev-safe sysctl hardening (gdb/strace/perf/eBPF/containers preserved)"
write_system_file /etc/sysctl.d/99-archfrican-hardening.conf 0644 <<'SYSCTL'
# Archfrican kernel hardening — DEV-SAFE subset (applied at boot by systemd-sysctl).
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 1
kernel.sysrq = 176
net.core.bpf_jit_harden = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1

# LEFT OFF on purpose — each breaks a real workflow on a dev box:
#   kernel.yama.ptrace_scope (>0)    -> breaks gdb -p / strace -p
#   kernel.kptr_restrict = 2         -> hides kernel symbols from perf/profilers
#   kernel.unprivileged_bpf_disabled -> breaks eBPF observability
#   kernel.kexec_load_disabled = 1   -> breaks kexec fast-reboot/crash tooling
#   kernel.perf_event_paranoid (>2)  -> breaks perf for non-root
#   user.max_user_namespaces = 0     -> breaks rootless podman / browser sandboxes
SYSCTL
best_effort sudo sysctl --system >/dev/null

# ---- coredump: don't spill memory (which may hold secrets) to disk ----------
substep "disabling on-disk coredumps"
write_system_file /etc/systemd/coredump.conf.d/10-archfrican.conf 0644 <<'CORE'
[Coredump]
Storage=none
ProcessSizeMax=0
CORE

# ---- lid handling (the idle TIMEOUT itself is driven by ~/.local/bin/archfrican-idle) ----
substep "configuring lid-close handling (screen lock is owned here)"
write_system_file /etc/systemd/logind.conf.d/10-archfrican.conf 0644 <<'LOGIND'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
LOGIND

# ---- faillock: lock an account after repeated failures (tuned; never locks root) ----
# pam_faillock already ships in Arch's system-auth — this just tunes its policy file.
substep "tuning PAM faillock (deny=5, auto-unlock after 10 min)"
write_system_file /etc/security/faillock.conf 0644 <<'FAILLOCK'
# Archfrican faillock policy. No even_deny_root (root is disabled here anyway). If you ever
# lock yourself out: the lock auto-clears after unlock_time (600 s) — or, to clear it NOW,
# boot linux-lts / a Snapper snapshot to a root shell, then
#   faillock --user <youruser> --reset
deny = 5
fail_interval = 900
unlock_time = 600
FAILLOCK

# ---- CPU microcode (security/stability fixes, loaded early by the initramfs) --
ucode_pkg=""
case "$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo 2>/dev/null)" in
  GenuineIntel) ucode_pkg=intel-ucode;;
  AuthenticAMD) ucode_pkg=amd-ucode;;
esac
if [ -n "$ucode_pkg" ] && ! pacman -Q "$ucode_pkg" &>/dev/null; then
  substep "installing $ucode_pkg (CPU microcode) + regenerating GRUB"
  pac_install "$ucode_pkg"
  # timeout: os-prober (if installed via opt-in multi-boot) scans every disk/partition and can hang
  # on a bad device — same cap modules/55-multiboot.sh already uses.
  best_effort timeout 300 sudo grub-mkconfig -o /boot/grub/grub.cfg   # GRUB auto-detects the ucode image
else
  ok "CPU microcode present (or unknown vendor) — skipping"
fi

# ---- screen-lock PAM (guarantee an INSTALLED locker can ALWAYS authenticate) -
# A missing/empty /etc/pam.d/<locker> makes PAM fall through to 'other' (deny) → the lock then rejects
# EVERY password and traps you at a gray screen. The gtklock/swaylock packages each ship one; we backfill
# ONLY when the locker is installed but its file went missing (a bad update / removed pacsave).
# CRUCIAL: never pre-create it for a NOT-yet-installed locker — pacman then refuses to install the package
# ("conflicting files: /etc/pam.d/<locker> exists in filesystem"). Never clobber a valid one (no .pacnew).
substep "ensuring the screen-lock PAM (installed lockers can always authenticate)"
for _lock in gtklock swaylock; do
  command -v "$_lock" >/dev/null 2>&1 || continue    # only for an INSTALLED locker (else we'd block its install)
  _f="/etc/pam.d/$_lock"
  if [ -s "$_f" ] && grep -qE '^[[:space:]]*auth' "$_f" 2>/dev/null; then
    ok "$_f present"
  else
    printf 'auth include login\n' | sudo tee "$_f" >/dev/null
    sudo chmod 0644 "$_f"
    ok "wrote a known-good $_f (auth include login)"
  fi
done

# ---- FIDO2 PAM (only when a key was enrolled in the wizard) -----------------
# Marker written by run_phase2's enroll step; absent on a normal/headless run.
if [ -f "$HOME/.config/.archfrican-fido2" ]; then
  substep "wiring FIDO2 PAM for sudo + login (non-exclusive — password still works)"
  fido2_write_pam
  # Self-check EVERY service fido2_write_pam touched (incl. sddm, the graphical login). Skip a service
  # whose PAM file is absent — fido2_pam_insert skipped it too, so there's nothing to verify/rollback
  # (keeps a single-module run on a box without sddm from failing). The graphical-login stack now gets
  # the same lockout-proof selfcheck (key 'sufficient' + an untouched password include) as sudo/TTY.
  # shellcheck disable=SC2086  # FIDO2_PAM_SERVICES is a deliberate space-separated service list
  for svc in $FIDO2_PAM_SERVICES; do
    [ -e "/etc/pam.d/$svc" ] || continue
    fido2_pam_selfcheck "$svc" || {
      [ -e "/etc/pam.d/$svc.archfrican.bak" ] && sudo mv -f "/etc/pam.d/$svc.archfrican.bak" "/etc/pam.d/$svc"
      die "FIDO2 PAM selfcheck failed for $svc — restored the backup, no changes left on disk"
    }
  done
else
  ok "FIDO2 key mode not enabled — skipping PAM wiring"
fi

# ---- expose the user-facing commands on PATH --------------------------------
substep "installing the fw-allow + doctor commands to /usr/local/bin"
chmod +x "$REPO_ROOT/bin/fw-allow" "$REPO_ROOT/bin/archfrican-doctor"   # belt: ensure +x even if the mode was lost
sudo ln -sf "$REPO_ROOT/bin/fw-allow"         /usr/local/bin/fw-allow
sudo ln -sf "$REPO_ROOT/bin/archfrican-doctor" /usr/local/bin/archfrican-doctor

ok "security module done"
