#!/usr/bin/env bash
# Health checks for `archfrican doctor`. CRITICAL: these run WITHOUT errexit — many of
# these commands exit non-zero on the HEALTHY path (`checkupdates`=2 when up to date;
# arch-audit / pacman -Dk / -Qkk / fwupdmgr all non-zero when there's nothing to report).
# The caller (bin/archfrican-doctor) relaxes `set -e`/`-u`/pipefail before invoking these.
# Nothing here mutates the system; root-needing probes use `sudo -n` and skip if unavailable.

H_AMBER=0; H_RED=0
_h_ok()    { printf '  \e[32m●\e[0m %-20s %s\n' "$1" "${2:-OK}"; }
_h_amber() { printf '  \e[33m●\e[0m %-20s %s\n' "$1" "$2"; H_AMBER=$((H_AMBER+1)); }
_h_red()   { printf '  \e[31m●\e[0m %-20s %s\n' "$1" "$2"; H_RED=$((H_RED+1)); }
_h_skip()  { printf '  \e[2m○ %-20s %s\e[0m\n' "$1" "${2:-n/a}"; }
_h_have()  { command -v "$1" >/dev/null 2>&1; }

check_failed_units() {
  _h_have systemctl || { _h_skip "services"; return; }
  local n nu
  n="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
  nu="$(systemctl --user --failed --no-legend 2>/dev/null | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ] && [ "${nu:-0}" -eq 0 ]; then _h_ok "services" "no failed units"
  else _h_amber "services" "${n} system + ${nu} user unit(s) failed (systemctl --failed)"; fi
}

check_journal() {
  _h_have journalctl || { _h_skip "journal errors"; return; }
  local n; n="$(journalctl -p 3 -b -q --no-pager 2>/dev/null | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then _h_ok "journal errors" "none since boot"
  else _h_amber "journal errors" "${n} error line(s) since boot (journalctl -p3 -b)"; fi
}

check_disk() {
  _h_have df || { _h_skip "disk space"; return; }
  local avail pct
  avail="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"
  pct="$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')"
  [ -n "$avail" ] || { _h_skip "disk space"; return; }
  if [ "${pct:-0}" -ge 90 ] || [ "${avail:-99}" -lt 5 ]; then _h_red "disk space" "${avail}G free (${pct}% used)"
  elif [ "${pct:-0}" -ge 80 ]; then _h_amber "disk space" "${avail}G free (${pct}% used)"
  else _h_ok "disk space" "${avail}G free (${pct}% used)"; fi
}

check_snapshots() {
  _h_have snapper || { _h_skip "snapshots"; return; }
  local n; n="$(sudo -n snapper -c root list --columns number 2>/dev/null | grep -c '^[0-9]' || true)"
  if [ -z "$n" ] || [ "$n" -le 0 ]; then _h_skip "snapshots" "needs sudo"; return; fi
  if [ "$n" -gt 50 ]; then _h_amber "snapshots" "${n} snapshots (cleanup may be due)"
  else _h_ok "snapshots" "${n} snapshots"; fi
}

check_scrub() {
  [ "$(findmnt -no FSTYPE / 2>/dev/null)" = btrfs ] || { _h_skip "btrfs scrub" "not btrfs"; return; }
  local out; out="$(sudo -n btrfs scrub status / 2>/dev/null)" || { _h_skip "btrfs scrub" "needs sudo"; return; }
  if printf '%s' "$out" | grep -qiE 'no stats|never'; then _h_amber "btrfs scrub" "never scrubbed — schedule one"
  else _h_ok "btrfs scrub" "ran (btrfs scrub status /)"; fi
}

check_smart() {
  _h_have smartctl || { _h_skip "disk SMART"; return; }
  local src base h; src="$(findmnt -no SOURCE / 2>/dev/null)"
  case "$src" in /dev/mapper/*) _h_skip "disk SMART" "encrypted root — check backing disk by hand"; return;; esac
  base="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
  [ -n "$base" ] || { _h_skip "disk SMART"; return; }
  h="$(sudo -n smartctl -H "/dev/$base" 2>/dev/null | grep -iE 'overall-health|SMART Health')"
  if printf '%s' "$h" | grep -qiE 'PASSED|OK'; then _h_ok "disk SMART" "PASSED"
  elif [ -n "$h" ]; then _h_red "disk SMART" "$h"
  else _h_skip "disk SMART" "needs sudo / unsupported"; fi
}

check_orphans() {
  _h_have pacman || { _h_skip "orphan packages"; return; }
  local n; n="$(pacman -Qtdq 2>/dev/null | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then _h_ok "orphan packages" "none"
  else _h_amber "orphan packages" "${n} orphan(s) — review: pacman -Qtdq"; fi
}

check_pacnew() {
  _h_have pacdiff || { _h_skip ".pacnew configs"; return; }
  local n; n="$(sudo -n pacdiff -o 2>/dev/null | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then _h_ok ".pacnew configs" "none pending"
  else _h_amber ".pacnew configs" "${n} config(s) to review (pacdiff)"; fi
}

check_updates() {
  _h_have checkupdates || { _h_skip "updates"; return; }
  local n; n="$(checkupdates 2>/dev/null | grep -c . || true)"   # checkupdates exits 2 when none
  if [ "${n:-0}" -eq 0 ]; then _h_ok "updates" "system up to date"
  else _h_amber "updates" "${n} update(s) available — run: sudo pacman -Syu"; fi
}

check_cve() {
  _h_have arch-audit || { _h_skip "CVE audit"; return; }
  local n; n="$(arch-audit --quiet --upgradable 2>/dev/null | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then _h_ok "CVE audit" "no fixable vulnerabilities"
  else _h_red "CVE audit" "${n} package(s) with fixable CVEs (arch-audit)"; fi
}

check_firmware() {
  _h_have fwupdmgr || { _h_skip "firmware"; return; }
  local out; out="$(fwupdmgr get-updates 2>/dev/null)"
  if printf '%s' "$out" | grep -qiE 'No updates|no updatable|No releases|No detected devices'; then
    _h_skip "firmware" "no capsule-updatable device"
  elif printf '%s' "$out" | grep -qiE 'Devices? with|→|Upgrade'; then
    _h_amber "firmware" "update(s) available — run: fwupdmgr update"
  else _h_ok "firmware" "up to date"; fi
}

check_reboot() {
  [ -d /usr/lib/modules ] || { _h_skip "kernel"; return; }   # not a modules-based (Linux) system
  # Kernel-name-agnostic: if the running kernel's modules dir is gone, a kernel was
  # updated since boot. That's AMBER ("reboot to apply"), never RED — nothing is broken NOW.
  if [ -d "/usr/lib/modules/$(uname -r)" ]; then _h_ok "kernel" "running kernel matches installed modules"
  else _h_amber "kernel" "running kernel updated — reboot to apply"; fi
}

check_foreign() {
  _h_have pacman || { _h_skip "foreign/AUR pkgs"; return; }
  local n; n="$(pacman -Qmq 2>/dev/null | grep -c . || true)"
  _h_ok "foreign/AUR pkgs" "${n:-0} installed (informational)"
}

check_timers() {
  _h_have systemctl || { _h_skip "maintenance timers"; return; }
  local want="paccache.timer fstrim.timer btrfs-scrub@-.timer archfrican-health.timer" t off=""
  for t in $want; do
    systemctl list-unit-files --no-legend "$t" 2>/dev/null | grep -q . || continue   # unit absent -> skip
    systemctl is-enabled "$t" >/dev/null 2>&1 || off="$off $t"
  done
  if [ -z "$off" ]; then _h_ok "maintenance timers" "enabled (or n/a)"
  else _h_amber "maintenance timers" "present but disabled:$off"; fi
}

# Applied state vs the on-disk repo: which modules changed (content-hash, lib/converge.sh) + any
# pending migrations. Purely local + no sudo, so the weekly notify can flag "you're behind the repo
# — run archfrican-update" without touching the network or auto-applying anything. Skips cleanly if
# converge.sh/the repo aren't reachable (so health.sh stays usable on its own).
check_drift() {
  command -v drift_modules >/dev/null 2>&1 || { _h_skip "config drift" "converge.sh not loaded"; return; }
  [ -n "${REPO_ROOT:-}" ] && [ -d "$REPO_ROOT/modules" ] || { _h_skip "config drift" "repo not found"; return; }
  local d pm
  d="$(drift_modules 2>/dev/null | grep -c . || true)"
  pm="$(pending_migrations 2>/dev/null || echo 0)"
  if [ "${d:-0}" -eq 0 ] && [ "${pm:-0}" -eq 0 ]; then _h_ok "config drift" "matches the repo"
  else _h_amber "config drift" "${d} module(s) + ${pm} migration(s) behind — run: archfrican-update"; fi
}
