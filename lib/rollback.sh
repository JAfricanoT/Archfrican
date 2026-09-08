#!/usr/bin/env bash
# lib/rollback.sh — restore a Btrfs snapshot on a root that is PINNED BY PATH.
#
# `snapper rollback` restores by flipping the filesystem's default subvolume (btrfs subvolume
# set-default). That only reaches the boot when nothing names the root subvolume explicitly.
# Archfrican names it twice: lib/base-install.sh bakes `rootflags=subvol=@` into the kernel cmdline
# and genfstab writes `subvol=/@` into /etc/fstab. A pinned mount resolves the path at boot and
# never consults the default subvolume — so on our own layout `snapper rollback` printed success and
# the next boot landed in the same broken @. The safety net looked armed and was not.
#
# What does work here is a PATH SWAP: mount the filesystem top, rename the live root subvolume
# aside, and recreate it as a writable snapshot of the target. The next boot resolves `subvol=@` to
# the restored copy. Sourced by bin/archfrican-update and ~/.local/bin/archfrican-rollback.
#
# The old root is renamed, never deleted, so a rollback is itself reversible until you clean up.

# The two places a boot can pin the root subvolume. Overridable so tests can supply fixtures.
ARCHFRICAN_PROC_CMDLINE="${ARCHFRICAN_PROC_CMDLINE:-/proc/cmdline}"
ARCHFRICAN_FSTAB="${ARCHFRICAN_FSTAB:-/etc/fstab}"

# root_subvol_pinned — true when the root subvolume is selected BY PATH, making set-default (and so
# `snapper rollback`) a no-op for what actually boots.
#
# Read the two pin sites as FILES. `findmnt -no OPTIONS /` is not a usable signal: btrfs reports a
# resolved `subvol=` in the mount options unconditionally, including when the mount came from the
# default subvolume — so asking findmnt answers "yes" on every Btrfs root and hides the one layout
# where snapper's own rollback is the right call.
root_subvol_pinned() {
  # One cmdline parameter per line: only rootflags= governs the root mount, so a `subvol=` belonging
  # to some other parameter must not count.
  tr ' ' '\n' < "$ARCHFRICAN_PROC_CMDLINE" 2>/dev/null \
    | grep -qE '^rootflags=.*subvol(id)?=' && return 0
  awk '$1 !~ /^#/ && $2 == "/" { print $4 }' "$ARCHFRICAN_FSTAB" 2>/dev/null \
    | grep -qE '(^|,)subvol(id)?=' && return 0
  return 1
}

# _rollback_subvol_of <mountpoint> — that mount's subvolume path relative to the filesystem top
# ("@", "@.snapshots"), or empty if it is not a Btrfs subvolume mount. Here findmnt's always-present
# `subvol=` is exactly what we want: we are reading the resolved path, not inferring intent.
_rollback_subvol_of() {
  local sv
  sv="$(findmnt -no OPTIONS -- "$1" 2>/dev/null | tr ',' '\n' | sed -n 's/^subvol=//p' | head -1)"
  printf '%s' "${sv#/}"
}

# _rollback_release <top> <we-made-it> — always unmount; only remove the directory we created.
_rollback_release() {
  sudo umount "$1" 2>/dev/null
  [ "$2" = 1 ] && rmdir "$1" 2>/dev/null
  return 0
}

# archfrican_rollback_to <snapshot-number> — make that snapshot the root the next boot lands on.
# Returns 0 when the machine is staged to boot restored, 2 on a bad argument, 1 on failure — and on
# failure the root subvolume is always left exactly as it was found.
archfrican_rollback_to() {
  local num="${1:-}"
  case "$num" in ''|*[!0-9]*) return 2 ;; esac

  # Unpinned layout: set-default reaches the boot, so snapper's own rollback is correct and also
  # records the pre-rollback state as a snapshot. Nothing to do by hand.
  if ! root_subvol_pinned; then
    sudo snapper -c root rollback "$num"
    return $?
  fi

  local dev rootsub snapsub snap top made_top=0 backup rc=0
  dev="$(findmnt -no SOURCE -- / 2>/dev/null)"; dev="${dev%%\[*}"   # strip findmnt's [/@] suffix
  rootsub="$(_rollback_subvol_of /)"
  [ -n "$dev" ] && [ -n "$rootsub" ] || return 1

  # @.snapshots is its own top-level subvolume (lib/base-install.sh), so the snapshot's path relative
  # to the top is not under the root subvolume. Fall back to a nested .snapshots for layouts that
  # never split it out.
  snapsub="$(_rollback_subvol_of /.snapshots)"
  [ -n "$snapsub" ] || snapsub="$rootsub/.snapshots"
  snap="$snapsub/$num/snapshot"

  # subvolid=5 is the filesystem top — the only view from which @ is a renameable directory entry
  # rather than the mounted root. Renaming a mounted subvolume is legal: the live mount tracks the
  # subvolid, so this machine keeps running off the old root until it reboots.
  top="${ARCHFRICAN_ROLLBACK_TOP:-}"
  if [ -z "$top" ]; then top="$(mktemp -d)" || return 1; made_top=1; fi
  sudo mount -o subvolid=5 "$dev" "$top" || { [ "$made_top" = 1 ] && rmdir "$top" 2>/dev/null; return 1; }

  if [ ! -d "$top/$snap" ] || [ ! -d "$top/$rootsub" ]; then
    _rollback_release "$top" "$made_top"; return 1
  fi

  backup="$rootsub.rollback-$(date +%Y%m%d-%H%M%S)"
  if ! sudo mv "$top/$rootsub" "$top/$backup"; then
    _rollback_release "$top" "$made_top"; return 1
  fi

  # Past this point there is briefly NO subvolume at the pinned path. If the snapshot fails we must
  # put the old one back: leaving the rename standing would hand the user an unbootable machine,
  # which is a far worse outcome than the failed rollback they asked for.
  if ! sudo btrfs subvolume snapshot "$top/$snap" "$top/$rootsub"; then
    sudo mv "$top/$backup" "$top/$rootsub"
    rc=1
  fi

  _rollback_release "$top" "$made_top"
  return "$rc"
}
