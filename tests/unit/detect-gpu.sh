#!/usr/bin/env bash
# Unit test for GPU detection (lib/detect-gpu.sh). Fixture-based — mocks `lspci` so it needs NO real
# hardware and runs in CI. Covers the two correctness traps the function was written to avoid:
#   1. A VIRTUAL adapter (virtio/QXL/VMware/…) MUST be classified "vm" (software/llvmpipe path), and
#      detected BEFORE any vendor match so a passthrough-less VM never gets amd/nvidia/intel drivers.
#   2. Vendor matching is by PCI vendor-id, never the bare string "ati" — "Intel CorporATIon" must NOT
#      be mis-flagged as AMD. Hybrid combos and the no-lspci fallback are covered too.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/detect-gpu.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
# assert_gpu <expected> <desc> <lspci-text>
assert_gpu(){
  local exp="$1" desc="$2" txt="$3" got
  # mock lspci in a subshell (a function shadows the PATH binary); detect_gpu calls `lspci -nn`.
  # shellcheck disable=SC2329  # invoked indirectly by detect_gpu, not in this function's body
  got="$( lspci(){ printf '%s\n' "$txt"; }; detect_gpu )"
  if [ "$got" = "$exp" ]; then _ok "$desc -> $got"; else _no "$desc (want $exp, got $got)"; fi
}

assert_gpu nvidia "single NVIDIA (vendor 10de)" \
  "00:02.0 VGA compatible controller [0300]: NVIDIA Corporation GA104 [GeForce RTX 3070] [10de:2484]"
# The "43d2" trap: a non-GPU device (here a SATA controller) whose hex device-id happens to contain
# the substring "3d" must NOT be mis-read as a second (Intel) GPU next to a real single NVIDIA card.
assert_gpu nvidia "single NVIDIA + SATA controller whose hex ID contains '3d' -> not hybrid" \
  "$(printf '00:17.0 SATA controller [0106]: Intel Corporation 500 Series Chipset Family SATA Controller (AHCI) [8086:43d2] (rev 11)\n01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 730] [10de:1287] (rev a1)')"
assert_gpu amd "single AMD (vendor 1002)" \
  "00:02.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [1002:73df]"
assert_gpu intel "single Intel (vendor 8086)" \
  "00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics [8086:9bc4]"
assert_gpu hybrid-intel-nvidia "hybrid Intel + NVIDIA" \
  "$(printf 'VGA [0300]: Intel Corporation UHD [8086:9bc4]\n3D [0302]: NVIDIA Corporation GA107M [10de:25a2]')"
assert_gpu hybrid-amd-nvidia "hybrid AMD + NVIDIA" \
  "$(printf 'VGA [0300]: Advanced Micro Devices [1002:1638]\n3D [0302]: NVIDIA Corp [10de:25a2]')"
assert_gpu hybrid-amd-intel "hybrid AMD + Intel" \
  "$(printf 'VGA [0300]: Intel Corporation [8086:9bc4]\nDisplay [0380]: AMD [1002:1638]')"
assert_gpu vm "virtio-gpu -> vm (software path)" \
  "00:02.0 VGA compatible controller [0300]: Red Hat, Inc. Virtio GPU [1af4:1050]"
assert_gpu vm "QXL paravirtual -> vm" \
  "00:02.0 VGA compatible controller [0300]: Red Hat, Inc. QXL paravirtual graphic card"
assert_gpu vm "VMware SVGA -> vm" \
  "00:0f.0 VGA compatible controller [0300]: VMware SVGA II Adapter"
# The "Corporation" trap: a bare-"ati" substring match would mis-flag this Intel-only box as AMD.
assert_gpu intel "Intel-only is NOT mis-flagged AMD via 'CorporATIon'" \
  "00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics [8086:0416]"
assert_gpu unknown "unrecognised vendor -> unknown" \
  "00:02.0 VGA compatible controller: Some Obscure Vendor [abcd:1234]"

# no lspci available -> unknown (never errors). Empty PATH in a subshell makes `command -v lspci` fail;
# detect_gpu is already a function (no PATH needed to call it) and returns before it would need grep.
# shellcheck disable=SC2123  # intentional: clearing PATH is exactly how we simulate a missing lspci
got="$( PATH=''; detect_gpu )"
if [ "$got" = unknown ]; then _ok "no lspci available -> unknown"; else _no "no-lspci (want unknown, got '$got')"; fi

# ---- nvidia_tier + lib32_nvidia_pkg ------------------------------------------------------------
# The regression these lock down (live-confirmed on a GeForce GT 730 / GK208B): 65-gaming.sh picked
# the 32-bit driver from detect_gpu's VENDOR alone, so any NVIDIA card got lib32-nvidia-utils. That
# pulls in nvidia-utils, whose modprobe drop-in blacklists nouveau — and on the Fermi/Kepler tier
# 10-gpu.sh installs NO nvidia kernel module to take over. The box then boots with no GPU driver at
# all (simple-framebuffer, no /dev/dri/renderD* node): niri starts, opens its Wayland socket, and
# renders nothing. Black screen after login, TTYs perfectly fine. lib32_nvidia_pkg MUST stay empty
# on the nouveau tier — lib32-mesa already covers 32-bit GL there.
# assert_tier <expected-tier> <expected-lib32-pkg ('' = install nothing)> <desc> <lspci-text>
assert_tier(){
  local exp="$1" exppkg="$2" desc="$3" txt="$4" got gotpkg
  # shellcheck disable=SC2329  # invoked indirectly by nvidia_tier / lib32_nvidia_pkg, not here
  got="$(    lspci(){ printf '%s\n' "$txt"; }; nvidia_tier )"
  # shellcheck disable=SC2329
  gotpkg="$( lspci(){ printf '%s\n' "$txt"; }; lib32_nvidia_pkg )"
  if [ "$got" = "$exp" ]; then _ok "tier: $desc -> $got"
  else _no "tier: $desc (want $exp, got $got)"; fi
  if [ "$gotpkg" = "$exppkg" ]; then _ok "lib32: $desc -> ${gotpkg:-<none, correct>}"
  else _no "lib32: $desc (want '${exppkg:-<none>}', got '${gotpkg:-<none>}')"; fi
}

assert_tier nouveau "" "Kepler GT 730 (the card that went black)" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 730] [10de:1287] (rev a1)"
assert_tier nouveau "" "Fermi GF119" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF119 [GeForce GT 610] [10de:104a]"
assert_tier nvidia "lib32-nvidia-utils" "Maxwell GM206" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM206 [GeForce GTX 960] [10de:1401]"
assert_tier nvidia "lib32-nvidia-utils" "Pascal GP106" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060] [10de:1c03]"
assert_tier nvidia-open "lib32-nvidia-utils" "Turing TU106" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106 [GeForce RTX 2070] [10de:1f02]"
assert_tier nvidia-open "lib32-nvidia-utils" "Ampere GA104" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA104 [GeForce RTX 3070] [10de:2484]"
# Unreadable codename must fall to nouveau AND install nothing — the safe end of both decisions.
assert_tier nouveau "" "unreadable codename -> safe default" \
  "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:ffff]"

printf '\ndetect-gpu unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
