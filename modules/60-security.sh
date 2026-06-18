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
    chain forward { type filter hook forward priority filter; policy accept; }
    chain output  { type filter hook output  priority filter; policy accept; }
}
include "/etc/nftables.d/archfrican-allows.nft"
NFT
substep "overriding nftables ExecStop so a stop never flushes other tables"
write_system_file /etc/systemd/system/nftables.service.d/10-archfrican.conf 0644 <<'UNIT'
[Service]
# Tear down ONLY our table on stop (never the whole ruleset). Leading '-' tolerates the
# table being absent (stop after a failed start, or a double-stop) so the unit isn't marked failed.
ExecStop=
ExecStop=-/usr/bin/nft delete table inet filter
UNIT
sudo systemctl daemon-reload
resilient_enable nftables.service
ok "firewall staged (active next boot). Open a port with:  fw-allow <port>/<tcp|udp>"

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

# ---- FIDO2 PAM (only when a key was enrolled in the wizard) -----------------
# Marker written by run_phase2's enroll step; absent on a normal/headless run.
if [ -f "$HOME/.config/.archfrican-fido2" ]; then
  substep "wiring FIDO2 PAM for sudo + login (non-exclusive — password still works)"
  fido2_write_pam
  for svc in sudo system-local-login; do
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
