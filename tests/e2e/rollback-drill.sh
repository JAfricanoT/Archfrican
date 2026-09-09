#!/usr/bin/env bash
# ============================================================================
#  Rollback drill — prove lib/rollback.sh would work on THIS machine.
#
#  tests/unit/rollback.sh pins the logic with stubbed sudo/btrfs/findmnt: it can
#  prove the decisions and the brick guard, but it cannot prove that the paths
#  archfrican_rollback_to computes actually exist on real hardware. A rollback
#  that gets those wrong is discovered at the worst possible moment. This closes
#  that gap without performing one.
#
#  SAFETY: read-only by construction. It mounts the filesystem top with `ro`,
#  reads, and unmounts. It never renames a subvolume, never snapshots, never
#  deletes — the three verbs a real rollback uses are absent from this file on
#  purpose. Safe to run on your daily driver.
#
#  Needs sudo for the mount (it will prompt). Run it after any change to
#  lib/rollback.sh, and as step 3 of the recovery drills in docs/VALIDATION.md.
# ============================================================================
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/rollback.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
_info(){ printf '       \033[2m%s\033[0m\n' "$1"; }

TOP=""
cleanup(){
  [ -n "$TOP" ] || return 0
  mountpoint -q "$TOP" && sudo umount "$TOP"
  rmdir "$TOP" 2>/dev/null
  return 0
}
trap cleanup EXIT

printf '\n\033[1mRollback drill — %s\033[0m\n\n' "$(hostname 2>/dev/null || echo this machine)"

# ---- 1. does this machine need the swap at all? ----------------------------
printf '1. layout\n'
if root_subvol_pinned; then
  _ok "root is pinned by path — the swap is the only thing that restores here"
else
  _info "root is NOT pinned — archfrican_rollback_to defers to 'snapper rollback',"
  _info "which is correct on this layout. The rest of this drill does not apply."
  printf '\nrollback drill: not applicable to this layout\n'
  exit 0
fi

# ---- 2. the paths a rollback would compute ---------------------------------
printf '\n2. paths\n'
dev="$(findmnt -no SOURCE -- / 2>/dev/null)"; dev="${dev%%\[*}"
rootsub="$(_rollback_subvol_of /)"
snapsub="$(_rollback_subvol_of /.snapshots)"
[ -n "$snapsub" ] || snapsub="$rootsub/.snapshots"
_info "device=$dev  root=$rootsub  snapshots=$snapsub"
[ -n "$dev" ]     && _ok "device resolved"        || _no "device came back empty"
[ -n "$rootsub" ] && _ok "root subvolume resolved" || _no "root subvolume came back empty"

# ---- 3. the filesystem top, read-only --------------------------------------
printf '\n3. filesystem top (mounted ro)\n'
TOP="$(mktemp -d)"
if ! sudo mount -o subvolid=5,ro "$dev" "$TOP"; then
  _no "could not mount the filesystem top — a real rollback would fail here too"
  printf '\nrollback drill: %d passed, %d failed\n' "$P" "$F"
  exit 1
fi
_ok "mounted the top at $TOP"
_info "subvolumes: $(find "$TOP" -maxdepth 1 -mindepth 1 -printf '%f ' 2>/dev/null)"

[ -d "$TOP/$rootsub" ] && _ok "\$top/$rootsub exists (what the swap would rename aside)" \
                       || _no "\$top/$rootsub is MISSING — the swap would abort"

# ---- 4. the newest snapshot would restore ----------------------------------
printf '\n4. restore source\n'
n="$(find "$TOP/$snapsub" -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null \
     | grep -xE '[0-9]+' | sort -n | tail -1)"
if [ -z "$n" ]; then
  _no "no numbered snapshots under \$top/$snapsub — there is nothing to roll back to"
else
  _ok "newest snapshot: #$n"
  if [ -d "$TOP/$snapsub/$n/snapshot" ]; then
    _ok "\$top/$snapsub/$n/snapshot exists (the swap's source)"
    if [ -d "$TOP/$snapsub/$n/snapshot/usr" ] && [ -d "$TOP/$snapsub/$n/snapshot/etc" ]; then
      _ok "it holds a complete root (/usr and /etc present)"
    else
      _no "it does NOT look like a complete root — restoring it would not boot"
    fi
    roflag="$(btrfs property get "$TOP/$snapsub/$n/snapshot" ro 2>/dev/null)"
    _info "${roflag:-ro=?} — this is why booting a snapshot from GRUB crawls"
  else
    _no "\$top/$snapsub/$n/snapshot is MISSING"
  fi
fi

# ---- 5. leftovers from past rollbacks --------------------------------------
printf '\n5. leftovers\n'
leftovers="$(find "$TOP" -maxdepth 1 -mindepth 1 -name "$rootsub.rollback-*" -printf '%f\n' 2>/dev/null)"
if [ -z "$leftovers" ]; then
  _ok "no $rootsub.rollback-* (matches a green 'rollback backups' in archfrican-doctor)"
else
  _info "$(printf '%s' "$leftovers" | tr '\n' ' ')"
  _info "each is a full root subvolume; archfrican-doctor reports them — see docs/RECOVERY.md §7"
fi

printf '\nrollback drill: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
