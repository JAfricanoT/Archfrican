#!/usr/bin/env bash
# Unit test for Archfrican's memory/OOM protection, zram VM tuning, and dual-kernel GRUB ordering.
# Locks down the fixes for two live-confirmed workstation failure modes:
#   1. Session kicked back to SDDM under memory pressure (11x `niri.service: Failed with result 'oom-kill'`):
#      niri.service had OOMPolicy=stop, no earlyoom, and HDD swap defaults on zram.
#   2. Dual-kernel GRUB silently booting linux-lts instead of linux-cachyos ('l' > 'c' in reverse sort)
#      while burying linux-cachyos inside "Advanced options".
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
has(){ if grep -qF -- "$2" "$1"; then _ok "$3"; else _no "$3"; fi; }

# ---- 1. packages/base.txt owns earlyoom + ananicy-cpp, with zero duplicate list owners -----------
has "$ROOT/packages/base.txt" "earlyoom"    "packages/base.txt includes earlyoom"
has "$ROOT/packages/base.txt" "ananicy-cpp" "packages/base.txt includes ananicy-cpp"
dups="$(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$ROOT"/packages/*.txt "$ROOT/gaming/packages.txt" | grep . | sort | uniq -d)"
if [ -z "$dups" ]; then _ok "no duplicate package owners across packages/*.txt + gaming/packages.txt"
else _no "duplicate package owners found: $dups"; fi

# ---- 2. modules/00-base.sh configures GRUB_TOP_LEVEL, zram VM tuning, earlyoom, ananicy-cpp ------
has "$ROOT/modules/00-base.sh" 'GRUB_DISTRIBUTOR '\''"Archfrican"'\''' \
  "00-base.sh brands GRUB entries as Archfrican"
has "$ROOT/modules/00-base.sh" 'GRUB_TOP_LEVEL '\''"/boot/vmlinuz-linux-cachyos"'\''' \
  "00-base.sh pins GRUB_TOP_LEVEL to linux-cachyos"
has "$ROOT/modules/00-base.sh" 'set_grub_key GRUB_DISABLE_SUBMENU false' \
  "00-base.sh keeps clean top-level menu (linux-lts in Advanced options)"
has "$ROOT/modules/00-base.sh" 'set_grub_key GRUB_DISABLE_BOOTNEXT true' \
  "00-base.sh hides noisy (EFI BootNext) entries so snapshots stay visible"
has "$ROOT/modules/40-theming.sh" "! -iname '*italic*'" \
  "40-theming.sh excludes Inter italic face from GRUB font rasterisation"
has "$ROOT/modules/00-base.sh" 'vm.swappiness = 180' \
  "00-base.sh tunes vm.swappiness=180 for zram"
has "$ROOT/modules/00-base.sh" 'vm.page-cluster = 0' \
  "00-base.sh disables HDD swap readahead (vm.page-cluster=0)"
has "$ROOT/modules/00-base.sh" 'zram-size = min(ram * 1.5, 16384)' \
  "00-base.sh configures zram0 at 1.5x RAM (capped at 16 GiB)"
has "$ROOT/lib/base-install.sh" 'zram-size = min(ram * 1.5, 16384)' \
  "base-install.sh matches 00-base.sh zram0 size"
has "$ROOT/modules/00-base.sh" '--avoid '\''^(niri|' \
  "00-base.sh configures earlyoom to protect niri"
has "$ROOT/modules/00-base.sh" 'resilient_enable ananicy-cpp.service' \
  "00-base.sh enables ananicy-cpp for all workstations"

# ---- 3. modules/20-niri-desktop.sh protects niri.service from helper OOM-kills -------------------
has "$ROOT/modules/20-niri-desktop.sh" 'OOMPolicy=continue' \
  "20-niri-desktop.sh sets OOMPolicy=continue on niri.service"
has "$ROOT/modules/20-niri-desktop.sh" 'localsearch-3.service' \
  "20-niri-desktop.sh masks GNOME Tracker (localsearch-3)"

# ---- 4. idle opt-in autostarts are silenced in home/dot_config/autostart/ ------------------------
for f in org.kde.kdeconnect.daemon.desktop geoclue-demo-agent.desktop print-applet.desktop; do
  p="$ROOT/home/dot_config/autostart/$f"
  if [ -r "$p" ] && grep -qx 'Hidden=true' "$p"; then
    _ok "autostart silenced: $f"
  else
    _no "autostart missing or not Hidden=true: $f"
  fi
done

# ---- 5. set_grub_key sets clean Archfrican GRUB keys idempotently on a fixture -------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FIX="$WORK/grub"
cat > "$FIX" <<'GRUB'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT="splash loglevel=3 quiet"
#GRUB_DISABLE_SUBMENU=y
GRUB
(
  # shellcheck source=/dev/null
  source "$ROOT/lib/common.sh"
  write_system_file() { cat > "$1"; }
  GRUB_DEFAULT="$FIX"
  # shellcheck source=/dev/null
  source "$ROOT/lib/grub.sh"
  GRUB_DEFAULT="$FIX"
  set_grub_key GRUB_DISTRIBUTOR '"Archfrican"'
  set_grub_key GRUB_TOP_LEVEL '"/boot/vmlinuz-linux-cachyos"'
  set_grub_key GRUB_DISABLE_SUBMENU false
  set_grub_key GRUB_DISABLE_BOOTNEXT true
  a="$(cat "$FIX")"
  set_grub_key GRUB_DISTRIBUTOR '"Archfrican"'
  set_grub_key GRUB_TOP_LEVEL '"/boot/vmlinuz-linux-cachyos"'
  set_grub_key GRUB_DISABLE_SUBMENU false
  set_grub_key GRUB_DISABLE_BOOTNEXT true
  b="$(cat "$FIX")"
  [ "$a" = "$b" ] || exit 1
)
if [ $? -eq 0 ] \
   && grep -qxF 'GRUB_DISTRIBUTOR="Archfrican"' "$FIX" \
   && grep -qxF 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' "$FIX" \
   && grep -qxF 'GRUB_DISABLE_SUBMENU=false' "$FIX" \
   && grep -qxF 'GRUB_DISABLE_BOOTNEXT=true' "$FIX" \
   && [ "$(grep -c 'GRUB_DISABLE_SUBMENU' "$FIX")" -eq 1 ]; then
  _ok "set_grub_key sets Archfrican GRUB keys idempotently (single canonical lines)"
else
  _no "set_grub_key failed to set Archfrican GRUB keys cleanly"
fi

printf '\nperf-oom unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
