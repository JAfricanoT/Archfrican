#!/usr/bin/env bash
# Unit test for the disk-health probes in lib/health.sh. Fixture-based — builds a throwaway sysfs
# tree and mocks findmnt, so it needs NO real disk, no sudo, and runs in CI.
#
# It pins the two faults that actually shipped:
#   1. check_smart skipped OUTRIGHT on /dev/mapper/* — i.e. on Archfrican's own default layout, the
#      disk health of an encrypted root was never once checked. `lsblk -no PKNAME /dev/mapper/root`
#      returns an EMPTY string, which read as "undiscoverable"; the mapping is right there in
#      /sys/block/<dm>/slaves/. The skip was a missing traversal, not a hardware limitation.
#   2. On btrfs, `findmnt -no SOURCE /` answers "/dev/mapper/root[/@]" — that "[/@]" is the
#      SUBVOLUME, not part of a device node. Feeding it to readlink/sysfs silently yields nothing and
#      degrades every caller back to a SKIP. The first cut of the fix had exactly this bug; without
#      a test it would have shipped looking green.
# And check_trim itself is a regression test for the biggest one: an encrypted root without
# :allow-discards makes `fstrim /` a silent no-op forever while fstrim.timer reports success.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/health.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
eq(){ # eq <expected> <got> <desc>
  if [ "$1" = "$2" ]; then _ok "$3 -> ${2:-<empty>}"; else _no "$3 (want '${1:-<empty>}', got '${2:-<empty>}')"; fi
}

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export ARCHFRICAN_SYSFS_BLOCK="$FIX/sys/block"
B="$ARCHFRICAN_SYSFS_BLOCK"

# ── fixture: a plain disk with two partitions, plus the LUKS mapper Archfrican installs by default
mkdir -p "$B/sda/sda1" "$B/sda/sda2" "$B/sda/queue"
mkdir -p "$B/dm-0/slaves" "$B/dm-0/queue"; ln -s "../../sda/sda2" "$B/dm-0/slaves/sda2"
# a second mapper layer (the LVM-on-LUKS shape) must resolve just as far down
mkdir -p "$B/dm-1/slaves" "$B/dm-1/queue"; ln -s "../../dm-0" "$B/dm-1/slaves/dm-0"
# an NVMe whole-disk, to prove a device that is ALREADY a disk needs no walking
mkdir -p "$B/nvme0n1/queue"

printf '\n\033[1m_h_backing_disk — resolve the physical disk\033[0m\n'
eq sda     "$(_h_backing_disk /dev/dm-0)"    "encrypted root (dm-0 -> sda2 -> sda) — the case that used to SKIP"
eq sda     "$(_h_backing_disk dm-1)"         "stacked mapper (LVM on LUKS) walks all the way down"
eq sda     "$(_h_backing_disk /dev/sda2)"    "bare partition climbs to its disk"
eq sda     "$(_h_backing_disk sda)"          "a whole disk resolves to itself"
eq nvme0n1 "$(_h_backing_disk /dev/nvme0n1)" "nvme whole-disk resolves to itself"
eq ""      "$(_h_backing_disk /dev/nope)"    "unknown device resolves to empty, never a wrong disk"

# A circular slaves graph must TERMINATE (the hop cap). Assert it returns at all rather than
# asserting which node it lands on — the contract is "the doctor cannot hang", not a value.
mkdir -p "$B/loopa/slaves" "$B/loopb/slaves"
ln -s "../../loopb" "$B/loopa/slaves/loopb"; ln -s "../../loopa" "$B/loopb/slaves/loopa"
if timeout 5 bash -c 'source "$1"; ARCHFRICAN_SYSFS_BLOCK="$2" _h_backing_disk loopa >/dev/null' _ "$ROOT/lib/health.sh" "$B"; then
  _ok "circular slaves graph terminates (bounded walk)"
else
  _no "circular slaves graph hung or errored — the hop cap is not holding"
fi

printf '\n\033[1m_h_root_device — strip the btrfs subvolume suffix\033[0m\n'
# findmnt --nofsroot is the real mechanism; mock the NO-flag form too, to prove the ${src%%[*}
# fallback catches a findmnt too old (or too odd) to honour --nofsroot.
findmnt(){ case "$*" in *--nofsroot*) printf '/dev/mapper/root\n';; *SOURCE*) printf '/dev/mapper/root[/@]\n';; esac; }
eq /dev/mapper/root "$(_h_root_device)" "uses --nofsroot when available"
findmnt(){ case "$*" in *--nofsroot*) return 1;; *SOURCE*) printf '/dev/mapper/root[/@]\n';; esac; }
eq /dev/mapper/root "$(_h_root_device)" "strips '[/@]' when --nofsroot is unavailable"

printf '\n\033[1mcheck_trim — did discard actually reach the disk?\033[0m\n'
# check_trim resolves via readlink -f, whose final component need not exist, so a fixture name
# indexes the fake sysfs directly. No readlink mock needed.
mkdir -p "$B/fixroot/queue"
trim_verdict(){ # trim_verdict <source> <discard_max_bytes> -> first word of the check's output
  printf '%s' "$2" > "$B/fixroot/queue/discard_max_bytes"
  findmnt(){ case "$*" in *FSTYPE*) printf 'btrfs\n';; *) printf '%s\n' "$SRC";; esac; }
  SRC="$1" check_trim 2>&1 | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/^ *//' | awk '{print $1}'
}
eq "●" "$(SRC=/dev/mapper/fixroot trim_verdict /dev/mapper/fixroot 0)" "mapper + discard 0 reports (amber marker)"
# The distinction that matters: dm-crypt BLOCKING discard is a fixable fault (amber, with the
# remedy); hardware that simply has no discard is not a fault at all (skip). Same 0, different verdict.
out_mapper="$(SRC=/dev/mapper/fixroot; findmnt(){ case "$*" in *FSTYPE*) printf 'btrfs\n';; *) printf '/dev/mapper/fixroot\n';; esac; }; printf 0 > "$B/fixroot/queue/discard_max_bytes"; check_trim 2>&1)"
out_plain="$(findmnt(){ case "$*" in *FSTYPE*) printf 'btrfs\n';; *) printf '/dev/fixroot\n';; esac; }; printf 0 > "$B/fixroot/queue/discard_max_bytes"; check_trim 2>&1)"
case "$out_mapper" in *"NEVER trimmed"*) _ok "encrypted root blocking discard -> names the fault and the remedy";; *) _no "encrypted root blocking discard was not flagged: $out_mapper";; esac
case "$out_plain"  in *"no discard support"*) _ok "plain device without discard -> skip, not a false alarm";; *) _no "plain no-discard device mis-reported: $out_plain";; esac
out_ok="$(findmnt(){ case "$*" in *FSTYPE*) printf 'btrfs\n';; *) printf '/dev/mapper/fixroot\n';; esac; }; printf 2147483648 > "$B/fixroot/queue/discard_max_bytes"; check_trim 2>&1)"
case "$out_ok" in *"passes through"*) _ok "discard reaching the disk -> green";; *) _no "healthy discard not reported green: $out_ok";; esac

printf '\n%s\n' "-------------------------------------------"
printf 'passed %d, failed %d\n' "$P" "$F"
[ "$F" -eq 0 ]
