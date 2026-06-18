#!/usr/bin/env bash
# Security helpers shared by modules/60-security.sh + bin/fw-allow. Sourced after
# lib/common.sh. No side effects on source.

ARCHFRICAN_FW_ALLOWS=/etc/nftables.d/archfrican-allows.nft

# Add an inbound allow rule (live + persistent) WITHOUT ever flushing other tables.
# Persisted in an include file the firewall re-reads on every reload.
fw_allow() {                       # fw_allow <port>[/tcp|/udp]
  local spec="${1:-}" port proto rule; local rule_args
  [ -n "$spec" ] || { echo "usage: fw-allow <port>[/tcp|udp]   e.g. fw-allow 3000/tcp" >&2; return 2; }
  port="${spec%%/*}"; proto="${spec#*/}"; [ "$proto" = "$spec" ] && proto=tcp
  case "$port" in ''|*[!0-9]*) echo "fw-allow: port must be numeric" >&2; return 2;; esac
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

# Print the corrected faillock recovery procedure for THIS box. root is DISABLED
# (sudo-only), so the usual "log in as root on a VT" does not apply.
faillock_recover_doc() {
  cat <<'DOC'
If sudo/login is locked after too many failures (faillock):
  • The lock auto-clears after the unlock_time window (default 600s) — just wait.
  • To clear immediately you need a root shell, but root login is DISABLED. Get one by:
      1. Reboot, pick "linux-lts" (or a Snapper snapshot) in the GRUB menu.
      2. At the boot prompt add  rd.break  OR  boot a snapshot to a root shell.
      3. Run:  faillock --user <youruser> --reset
  • Prevention: faillock here is deny=5 / unlock_time=600 and never locks "root".
DOC
}
