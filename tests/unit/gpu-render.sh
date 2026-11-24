#!/usr/bin/env bash
# Unit test for check_gpu_render() in lib/health.sh.
# Fixture-based: builds fake sysfs DRM + modules trees and shadows `systemd-detect-virt` / `modprobe`
# so it runs with zero hardware or root in CI. Covers all 5 diagnostic paths:
#   1. Healthy card with sibling renderD128 -> OK (0 amber, 0 red)
#   2. Virtualized / emulated adapter without renderD* -> AMBER (not a broken host)
#   3. Upgraded kernel (missing modules.dep) without renderD* -> AMBER (reboot needed)
#   4. Blacklisted driver (modprobe -R resolves, modprobe -b -R empty) -> RED with repair hint
#   5. No driver bound at all -> RED
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/health.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

KVER="$(uname -r)"
MOD_OK="$WORK/mods-ok"
MOD_EMPTY="$WORK/mods-empty"
mkdir -p "$MOD_OK/$KVER" "$MOD_EMPTY"
: > "$MOD_OK/$KVER/modules.dep"

# Build a minimal sysfs DRM fixture for card0.
# make_drm <dir> <has_render(0|1)> [modalias]
make_drm() {
  local d="$1" has_r="$2" ma="${3:-}"
  rm -rf "$d"
  mkdir -p "$d/card0/device/drm" "$WORK/fake-drv/nouveau"
  printf '1\n' > "$d/card0/device/boot_vga"
  ln -s "$WORK/fake-drv/nouveau" "$d/card0/device/driver"
  [ "$has_r" = 1 ] && mkdir -p "$d/card0/device/drm/renderD128"
  [ -n "$ma" ] && printf '%s\n' "$ma" > "$d/card0/device/modalias"
}

# ---- 1. healthy GPU with renderD128 -> OK --------------------------------------------------------
make_drm "$WORK/drm1" 1
H_AMBER=0; H_RED=0
out="$(ARCHFRICAN_SYSFS_DRM="$WORK/drm1" check_gpu_render; printf 'A=%d R=%d\n' "$H_AMBER" "$H_RED")"
if grep -q 'renderD128 on card0 via nouveau' <<< "$out" && grep -q 'A=0 R=0' <<< "$out"; then
  _ok "healthy card0 with renderD128 -> OK"
else
  _no "healthy card0 expected OK, got: $out"
fi

# ---- 2. VM emulated adapter (no renderD*) -> AMBER -----------------------------------------------
make_drm "$WORK/drm2" 0
out="$(
  # shellcheck disable=SC2329
  systemd-detect-virt() { echo kvm; }
  H_AMBER=0; H_RED=0
  ARCHFRICAN_SYSFS_DRM="$WORK/drm2" ARCHFRICAN_MODULES_DIR="$MOD_OK" check_gpu_render
  printf 'A=%d R=%d\n' "$H_AMBER" "$H_RED"
)"
if grep -q 'emulated adapter under kvm' <<< "$out" && grep -q 'A=1 R=0' <<< "$out"; then
  _ok "emulated VM adapter without renderD* -> AMBER"
else
  _no "VM adapter expected AMBER, got: $out"
fi

# ---- 3. upgraded kernel (missing modules.dep) -> AMBER -------------------------------------------
make_drm "$WORK/drm3" 0
out="$(
  # shellcheck disable=SC2329
  systemd-detect-virt() { echo none; return 1; }
  H_AMBER=0; H_RED=0
  ARCHFRICAN_SYSFS_DRM="$WORK/drm3" ARCHFRICAN_MODULES_DIR="$MOD_EMPTY" check_gpu_render
  printf 'A=%d R=%d\n' "$H_AMBER" "$H_RED"
)"
if grep -q 'no module tree for the running kernel' <<< "$out" && grep -q 'A=1 R=0' <<< "$out"; then
  _ok "missing kernel module tree -> AMBER"
else
  _no "missing module tree expected AMBER, got: $out"
fi

# ---- 4. blacklisted driver -> RED with repair hint -----------------------------------------------
make_drm "$WORK/drm4" 0 "pci:v000010DEd00001287sv000019DAsd0000730Bbc03sc00i00"
out="$(
  # shellcheck disable=SC2329
  systemd-detect-virt() { echo none; return 1; }
  # shellcheck disable=SC2329
  modprobe() { [ "$1" = "-R" ] && echo nouveau; return 0; }
  H_AMBER=0; H_RED=0
  ARCHFRICAN_SYSFS_DRM="$WORK/drm4" ARCHFRICAN_MODULES_DIR="$MOD_OK" check_gpu_render
  printf 'A=%d R=%d\n' "$H_AMBER" "$H_RED"
)"
if grep -q 'nouveau is blacklisted' <<< "$out" && grep -q 'install.sh 10-gpu' <<< "$out" && grep -q 'A=0 R=1' <<< "$out"; then
  _ok "blacklisted driver without replacement -> RED with 10-gpu repair hint"
else
  _no "blacklisted driver expected RED, got: $out"
fi

# ---- 5. no driver bound at all -> RED ------------------------------------------------------------
make_drm "$WORK/drm5" 0
rm -f "$WORK/drm5/card0/device/driver"
out="$(
  # shellcheck disable=SC2329
  systemd-detect-virt() { echo none; return 1; }
  H_AMBER=0; H_RED=0
  ARCHFRICAN_SYSFS_DRM="$WORK/drm5" ARCHFRICAN_MODULES_DIR="$MOD_OK" check_gpu_render
  printf 'A=%d R=%d\n' "$H_AMBER" "$H_RED"
)"
if grep -q 'no driver bound' <<< "$out" && grep -q 'A=0 R=1' <<< "$out"; then
  _ok "unbound GPU without renderD* -> RED"
else
  _no "unbound GPU expected RED, got: $out"
fi

printf '\ngpu-render unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
