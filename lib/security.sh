#!/usr/bin/env bash
# Security helpers shared by modules/60-security.sh + bin/fw-allow. Sourced after
# lib/common.sh. No side effects on source.

# Overridable for unit tests (mirrors lib/fido2.sh::FIDO2_PAM_DIR). Production value is fixed.
ARCHFRICAN_FW_ALLOWS="${ARCHFRICAN_FW_ALLOWS:-/etc/nftables.d/archfrican-allows.nft}"

# Add an inbound allow rule (live + persistent) WITHOUT ever flushing other tables.
# Persisted in an include file the firewall re-reads on every reload.
fw_allow() {                       # fw_allow <port>[/tcp|/udp]
  local spec="${1:-}" port proto rule; local rule_args
  [ -n "$spec" ] || { echo "usage: fw-allow <port>[/tcp|udp]   e.g. fw-allow 3000/tcp" >&2; return 2; }
  port="${spec%%/*}"; proto="${spec#*/}"; [ "$proto" = "$spec" ] && proto=tcp
  case "$port" in ''|*[!0-9]*) echo "fw-allow: port must be numeric" >&2; return 2;; esac
  # Range-check BEFORE persisting: an out-of-range port (e.g. 70000) would pass the digits-only test,
  # get appended to the nftables include, and then fail the whole `nft -f` reload on next boot —
  # silently bringing the firewall up fail-OPEN. Reject it here instead.
  { [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; } || { echo "fw-allow: port must be 1-65535" >&2; return 2; }
  case "$proto" in tcp|udp) ;; *) echo "fw-allow: proto must be tcp or udp" >&2; return 2;; esac
  rule_args=(add rule inet filter input "$proto" dport "$port" accept)
  rule="${rule_args[*]}"
  if sudo grep -qF "$proto dport $port accept" "$ARCHFRICAN_FW_ALLOWS" 2>/dev/null; then
    echo "already allowed: inbound $proto/$port"; return 0
  fi
  printf '%s\n' "$rule" | sudo tee -a "$ARCHFRICAN_FW_ALLOWS" >/dev/null
  sudo nft "${rule_args[@]}" 2>/dev/null || true   # live add, only on first allow (no dup rules)
  echo "allowed inbound $proto/$port (persisted; active now if the firewall is running)"
}

# Enable a HARDENED sshd + open the firewall for it. Opt-in only (modules/60-security.sh gates this).
# root is already locked here, so PermitRootLogin no is belt-and-suspenders; password auth stays on so a
# fresh box is reachable (switch to keys-only by uncommenting the line below + adding an authorized_keys).
ssh_enable_hardened() {
  substep "hardening + enabling sshd (remote access) and opening 22/tcp"
  write_system_file /etc/ssh/sshd_config.d/10-archfrican.conf 0644 <<'SSHD'
# Archfrican sshd hardening (drop-in overrides /etc/ssh/sshd_config).
PermitRootLogin no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
# Keys-only (more secure) — uncomment AFTER adding your key to ~/.ssh/authorized_keys:
#PasswordAuthentication no
SSHD
  best_effort sudo sshd -t                          # validate the merged config (never abort on it)
  resilient_enable sshd.service
  best_effort sudo systemctl start sshd.service     # reachable now, not only next boot
  fw_allow 22/tcp
  ok "SSH enabled (hardened) + 22/tcp opened. Connect: ssh $USER@<host-ip>"
}
