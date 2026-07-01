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

check_boot() {
  [ -d /sys/firmware/efi ] || { _h_skip "boot fallback" "not UEFI"; return; }
  local main=/boot/EFI/Archfrican/grubx64.efi fb=/boot/EFI/BOOT/BOOTX64.EFI
  if [ ! -f "$main" ]; then _h_red "boot fallback" "GRUB missing in ESP ($main) — boot may fail"; return; fi
  if [ ! -f "$fb" ]; then
    _h_amber "boot fallback" "no EFI/BOOT/BOOTX64.EFI — add it: sudo grub-install --efi-directory=/boot --bootloader-id=Archfrican --removable"
  elif _h_have efibootmgr && ! efibootmgr 2>/dev/null | grep -qi 'Archfrican'; then
    _h_amber "boot fallback" "fallback present but no NVRAM 'Archfrican' entry — booting via the fallback path"
  else
    _h_ok "boot fallback" "EFI/Archfrican + EFI/BOOT fallback present"
  fi
}

check_multiboot() {
  [ -d /sys/firmware/efi ] || { _h_skip "dual-boot" "not UEFI"; return; }
  declare -F detect_other_os >/dev/null 2>&1 || { _h_skip "dual-boot" "detector n/a"; return; }
  # detector mounts foreign ESPs read-only — needs root; never prompt.
  [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null || { _h_skip "dual-boot" "needs sudo"; return; }
  local other; other="$(detect_other_os 2>/dev/null)"
  [ -n "$other" ] || { _h_ok "dual-boot" "no other OS detected"; return; }
  local label; label="$(printf '%s' "$other" | head -1)"
  # os-prober tags foreign entries "... (on /dev/sdXN)"; that suffix is the in-menu signal.
  if grep -qsE "menuentry .*\(on /dev/" /boot/grub/grub.cfg; then
    _h_ok "dual-boot" "other OS present and in the GRUB menu"
  elif grep -qsxF 'GRUB_DISABLE_OS_PROBER=false' /etc/default/grub; then
    _h_amber "dual-boot" "$label present, os-prober ON but unnamed (BitLocker/hibernated? shut it down, then: ./install.sh 55-multiboot yes)"
  else
    _h_amber "dual-boot" "$label present but not in GRUB — run: ./install.sh 55-multiboot yes"
  fi
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
  if [ -z "${REPO_ROOT:-}" ] || [ ! -d "$REPO_ROOT/modules" ]; then _h_skip "config drift" "repo not found"; return; fi
  local d pm
  d="$(drift_modules 2>/dev/null | grep -c . || true)"
  pm="$(pending_migrations 2>/dev/null || echo 0)"
  if [ "${d:-0}" -eq 0 ] && [ "${pm:-0}" -eq 0 ]; then _h_ok "config drift" "matches the repo"
  else _h_amber "config drift" "${d} module(s) + ${pm} migration(s) behind — run: archfrican-update"; fi
}

# ── Archfrican SURFACE health — the configs + tools WE ship. The generic system checks above can't
# see these, yet a single broken config takes down the WHOLE desktop silently: an invalid niri config
# makes niri fall back to its defaults — no Archfrican keybinds, no bar, no dock, no wallpaper. These
# checks turn that class of failure from an hours-long mystery into one red line. ───────────────────

# The single most important check: if the niri config does not parse, niri silently runs its built-in
# defaults and nothing of Archfrican is active. RED.
check_niri_config() {   # WM-coupled (niri) — one of the few niri touchpoints; see docs/WM-INTEGRATION.md
  _h_have niri || { _h_skip "niri config"; return; }
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
  [ -r "$cfg" ] || { _h_red "niri config" "missing ($cfg) — niri is running its defaults"; return; }
  local out first
  if out="$(niri validate 2>&1)"; then
    _h_ok "niri config" "valid"
  else
    first="$(printf '%s\n' "$out" | grep -m1 -iE 'error|expected|unexpected|found' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    _h_red "niri config" "INVALID — niri fell back to defaults (no binds/bar/dock). Run: niri validate${first:+ — $first}"
  fi
}

# The core desktop components must be installed; a missing one explains "nothing happens" (e.g. no
# ghostty -> the terminal bind does nothing). RED.
check_desktop_stack() {
  local need="niri waybar swaync fuzzel ghostty nwg-dock keyd awww-daemon" b missing=""
  for b in $need; do _h_have "$b" || missing="$missing $b"; done
  if [ -z "$missing" ]; then _h_ok "desktop stack" "all core components installed"
  else _h_red "desktop stack" "missing:$missing — complete the install: archfrican-update --run"; fi
}

# Archfrican's own CLI must resolve by name (it's documented that way). Catches the PATH gap that made
# 'archfrican-update' a command-not-found in a fresh shell. AMBER (workaround: ~/.archfrican/bin/<tool>).
check_archfrican_cli() {
  local need="archfrican-update archfrican-doctor theme-switch archfrican-spotlight archfrican-wallpaper" t missing=""
  for t in $need; do _h_have "$t" || missing="$missing $t"; done
  if [ -z "$missing" ]; then _h_ok "archfrican CLI" "all tools on PATH"
  else _h_amber "archfrican CLI" "not on PATH:$missing — open a new shell, or add ~/.archfrican/bin to PATH"; fi
}

# theme-switch is the single writer of every generated colour/CSS file; an unrendered ${TOKEN} means a
# broken render (and an ugly/odd surface). AMBER — re-render fixes it.
check_theme_render() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" f stray=""
  for f in waybar/colors.css swaync/colors.css swaync/style.css fuzzel/colors.ini fuzzel/fuzzel.ini \
           walker/themes/archfrican/style.css \
           ghostty/colors gtk-3.0/gtk.css gtk-4.0/gtk.css nwg-dock/style.css qt6ct/qt6ct.conf; do
    [ -r "$cfg/$f" ] || continue
    grep -qE '\$\{[A-Za-z_]+\}' "$cfg/$f" 2>/dev/null && stray="$stray $f"
  done
  if [ -z "$stray" ]; then _h_ok "theme render" "no unrendered tokens"
  else _h_amber "theme render" "unrendered \${...} in:$stray — run: theme-switch \"\$(cat ~/.config/.archfrican-theme 2>/dev/null || echo archfrican-dark)\""; fi
}

# keyd is the ⌘→Ctrl macOS-shortcut layer; installed-but-inactive means copy/paste muscle memory is
# dead. AMBER. (Note: keyd never touches plain Super+<non-letter>, so it can't break niri's Mod binds.)
check_keyd() {
  _h_have keyd || { _h_skip "keyd"; return; }
  if systemctl is-active --quiet keyd 2>/dev/null; then _h_ok "keyd" "active (⌘→Ctrl layer)"
  else _h_amber "keyd" "installed but not active — sudo systemctl enable --now keyd"; fi
}
