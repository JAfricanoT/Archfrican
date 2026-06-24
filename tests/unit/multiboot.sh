#!/usr/bin/env bash
# Unit test for the dual-boot ESP classifier (lib/multiboot.sh::_af_esp_os). Fixture-based — builds
# fake mounted-ESP directory trees, so it needs NO disks, NO mounts, and runs in CI. _af_esp_os is the
# read-only core of detect_other_os: it names the OS on an ESP by which loader file is present.
# Invariants under test:
#   1. A Windows loader -> "Windows"; a GRUB/shim/systemd-boot loader -> "Linux (GRUB)".
#   2. OUR OWN loader (EFI/Archfrican) is skipped so the installer never reports itself as "another OS".
#   3. An empty ESP -> none (rc 1); matching is case-insensitive (ESPs are FAT).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/multiboot.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
# mkesp <relative-dir> [loader-file] -> prints a temp ESP root containing that (empty) loader file.
mkesp(){ local d; d="$(mktemp -d)"; mkdir -p "$d/$1"; [ -n "${2:-}" ] && : > "$d/$1/$2"; printf '%s' "$d"; }
# assert_os <expected> <desc> <esp-dir>   (expected "" means: must return rc 1 with no output)
assert_os(){
  local exp="$1" desc="$2" d="$3" out rc
  out="$(_af_esp_os "$d")"; rc=$?
  if [ -z "$exp" ]; then
    if [ "$rc" = 1 ] && [ -z "$out" ]; then _ok "$desc (none, rc1)"
    else _no "$desc (want none/rc1, got rc=$rc out='$out')"; fi
  else
    if [ "$rc" = 0 ] && [ "$out" = "$exp" ]; then _ok "$desc -> $out"
    else _no "$desc (want $exp, got rc=$rc out='$out')"; fi
  fi
  rm -rf "$d"
}

assert_os "Windows"      "Microsoft bootmgfw.efi -> Windows"          "$(mkesp EFI/Microsoft/Boot bootmgfw.efi)"
assert_os "Linux (GRUB)" "fedora grubx64.efi -> Linux (GRUB)"         "$(mkesp EFI/fedora grubx64.efi)"
assert_os "Linux (GRUB)" "ubuntu shimx64.efi -> Linux (GRUB)"         "$(mkesp EFI/ubuntu shimx64.efi)"
assert_os "Linux (GRUB)" "systemd-bootx64.efi -> Linux (GRUB)"        "$(mkesp EFI/systemd systemd-bootx64.efi)"
assert_os ""             "our own EFI/Archfrican loader is SKIPPED"   "$(mkesp EFI/Archfrican grubx64.efi)"
assert_os ""             "empty ESP -> none"                          "$(mktemp -d)"

# nocaseglob (set in _af_esp_os) makes the loader-FILENAME glob case-insensitive, FS-independently:
# `grub*.efi` matches an uppercase GRUBX64.EFI because bash pattern-matches directory entries, not the
# filesystem. (It does NOT help the literal directory components — `$d/EFI` is a plain lookup, so the
# EFI dir must exist in that case; on a real ESP the FAT mount is case-insensitive, so it always does.
# Hence we keep EFI/ exact-case here and only vary the loader filename's case — the part the function
# actually normalises. A lowercase efi/ dir would only resolve on a case-insensitive mount/FS.)
d="$(mktemp -d)"; mkdir -p "$d/EFI/fedora"; : > "$d/EFI/fedora/GRUBX64.EFI"
assert_os "Linux (GRUB)" "case-insensitive loader filename (uppercase GRUBX64.EFI via nocaseglob)" "$d"

printf '\nmultiboot unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
