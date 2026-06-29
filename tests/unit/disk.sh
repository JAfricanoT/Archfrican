#!/usr/bin/env bash
# Unit test for the ISO disk picker (lib/disk.sh::live_disk + list_disks). Fixture-based — mocks
# findmnt/lsblk so it needs NO disks and runs in CI. Guards the regression that shipped a false
# "no installable disk found" on real hardware:
#   1. live_disk must NEVER abort under `set -e` when /run/archiso/bootmnt is not mounted (findmnt
#      exits non-zero); it falls back to the disk carrying the iso9660 archiso fs.
#   2. list_disks must list every type=disk EXCEPT the live USB, preserve space-containing MODELs,
#      and skip loop/rom — and must keep working (not silently empty) when findmnt fails.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/disk.sh"
set +e                              # we capture rc ourselves
is_iso(){ return 0; }               # pretend we are on the ISO (no /run/archiso needed)

# Mock state: FINDMNT_RC=1 means /run/archiso/bootmnt is NOT mounted (the failing case).
FINDMNT_RC=1; FINDMNT_OUT=""
findmnt(){ [ -n "$FINDMNT_OUT" ] && printf '%s\n' "$FINDMNT_OUT"; return "$FINDMNT_RC"; }
DISKS=""                            # newline list of "NAME SIZE disk MODEL" for lsblk -dbno
lsblk(){
  case "$*" in
    *"-dbno NAME,SIZE,TYPE,MODEL"*) [ -n "$DISKS" ] && printf '%s\n' "$DISKS" ;;
    *"-rno PKNAME,FSTYPE"*)         printf 'sdc iso9660\nsdc vfat\n' ;;   # USB carries archiso
    *"-no PKNAME"*)                 printf 'sdc\n' ;;                      # parent of a boot src
    *)                              : ;;
  esac
}

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

DISKS=$'sda 240057409536 disk KINGSTON SA400S37240G\nsdb 1000204886016 disk WDC WD10EZEX-60WN4A1\nsdc 8053063680 disk OnlyDisk\nnvme0n1 512110190592 disk SK hynix BC511 HFM512GDJTNI-82A0A\nloop0 1034000000 loop'

# ---- 1. live_disk never aborts under set -e and finds the USB via the iso9660 fallback ------------
out="$( set -euo pipefail; live_disk )"; rc=$?
if [ "$rc" = 0 ] && [ "$out" = sdc ]; then _ok "live_disk: findmnt-fails path returns the iso9660 USB (sdc), no set -e abort"
else _no "live_disk fallback (want rc0/sdc, got rc=$rc out='$out')"; fi

FINDMNT_RC=0; FINDMNT_OUT="/dev/sdc1"
out="$(live_disk)"
if [ "$out" = sdc ]; then _ok "live_disk: bootmnt-mounted path resolves the boot disk (sdc)"; else _no "live_disk mounted path (got '$out')"; fi
FINDMNT_RC=1; FINDMNT_OUT=""

# ---- 2. list_disks lists the 3 internal disks, excludes the USB, keeps spaced MODELs -------------
out="$( set -euo pipefail; list_disks )"; rc=$?
n="$(printf '%s' "$out" | grep -c .)"
if [ "$rc" = 0 ] && [ "$n" = 3 ]; then _ok "list_disks: 3 candidates (USB + loop excluded), no abort"
else _no "list_disks count (want rc0/3, got rc=$rc n=$n)"; fi
if printf '%s\n' "$out" | grep -q "^sdc"$'\t'; then _no "list_disks did NOT exclude the live USB sdc"; else _ok "list_disks excludes the live USB (sdc)"; fi
if printf '%s\n' "$out" | grep -q $'^nvme0n1\t512110190592\tSK hynix BC511 HFM512GDJTNI-82A0A$'; then _ok "list_disks preserves a space-containing MODEL"; else _no "list_disks mangled the spaced MODEL"; fi
if printf '%s\n' "$out" | grep -q '^loop0'; then _no "list_disks leaked a loop device"; else _ok "list_disks skips loop/non-disk types"; fi

# ---- 3. truly no disks -> empty (the picker then prints diagnostics + dies) -----------------------
DISKS='loop0 1034000000 loop'
out="$( set -euo pipefail; list_disks )"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then _ok "list_disks: only loop present -> empty (no false candidate)"; else _no "list_disks empty-case (rc=$rc out='$out')"; fi

printf '\ndisk unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
