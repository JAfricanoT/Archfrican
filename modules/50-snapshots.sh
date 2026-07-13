#!/usr/bin/env bash
# Phase 2, step 5: make Btrfs snapshots actually save you.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/grub.sh"

substep "creating the snapper root config (Btrfs snapshots)"

# Exact-field, format-stable check (snapper list-configs is a bordered table, so
# a '^root' anchor neither matches the padded data row nor avoids matching
# 'root-*'). --csvout has no borders; fall back to awk for very old snapper.
have_root_config() {
  { sudo snapper --csvout list-configs --columns config 2>/dev/null | tail -n +2 \
    || sudo snapper list-configs 2>/dev/null | awk 'NR>2{print $1}'; } | grep -qx root
}

if ! have_root_config; then
  if mountpoint -q /.snapshots; then
    # The base install (lib/base-install.sh) already created @.snapshots mounted at
    # /.snapshots (in fstab). `snapper create-config` would try to create its OWN
    # /.snapshots subvolume and fail "already exists". ArchWiki procedure: free the
    # mount, let snapper write the config, drop its throwaway subvol, then mount -a
    # restores the pre-existing @.snapshots from fstab.
    log "/.snapshots is a pre-existing mount (from the base install) — using ArchWiki procedure"
    if sudo umount /.snapshots \
       && sudo rm -rf /.snapshots \
       && sudo snapper -c root create-config / \
       && { sudo btrfs subvolume delete /.snapshots 2>/dev/null; true; } \
       && sudo mount -a; then
      ok "root config created over existing @.snapshots"
    else
      sudo mount -a || true   # never leave /.snapshots unmounted
      warn "snapper create-config hit a snag — verifying below"
    fi
    mountpoint -q /.snapshots || warn "/.snapshots is NOT mounted — snapshots may land in @ (check fstab)"
  else
    sudo snapper -c root create-config / || warn "create-config failed — verifying below"
  fi
fi

# Non-root reads of snapshots (snapper list, grub-btrfs) need wheel access. Directory permissions
# alone are NOT enough: `snapper list` goes through snapper's own D-Bus-backed authorization, which
# checks the config's ALLOW_USERS/ALLOW_GROUPS, not just Unix perms on /.snapshots (a wheel user with
# only the chmod/chown below still gets "No permissions." from a bare `snapper -c root list`).
if [ -d /.snapshots ]; then sudo chmod 750 /.snapshots; sudo chown :wheel /.snapshots; fi
sudo snapper -c root set-config "ALLOW_GROUPS=wheel" || warn "couldn't grant snapper wheel access — non-root 'snapper list' will need sudo"

# ---- home config: file-level Time Machine over /home (archfrican-timemachine) ----------------------
# @home is a SEPARATE subvolume, so the root snapshots never contain user files. A dedicated 'home'
# config snapshots /home so a user can recover a previous version of their own file. Retention is
# deliberately conservative (a few hourly + a few daily, no weekly/monthly): btrfs snapshots are COW,
# but home churn (node_modules, build dirs, caches) pins deleted blocks until cleanup — a tight window
# keeps that bounded. ALLOW_GROUPS=wheel + SYNC_ACL let the user browse/restore without sudo.
have_home_config() {
  { sudo snapper --csvout list-configs --columns config 2>/dev/null | tail -n +2 \
    || sudo snapper list-configs 2>/dev/null | awk 'NR>2{print $1}'; } | grep -qx home
}
if mountpoint -q /home && ! have_home_config; then
  substep "creating the snapper 'home' config (file-level Time Machine over /home)"
  sudo snapper -c home create-config /home || warn "snapper home create-config failed — home Time Machine not set up"
fi
if have_home_config; then
  sudo snapper -c home set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=5 \
    TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
    NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 \
    ALLOW_GROUPS=wheel SYNC_ACL=yes \
    || warn "couldn't tune the home snapper config"
  [ -d /home/.snapshots ] && { sudo chmod 750 /home/.snapshots; sudo chown :wheel /home/.snapshots; }
  # A baseline snapshot NOW, so there's immediately a version to recover from (before the first timer tick).
  sudo snapper -c home list 2>/dev/null | awk -F'|' 'NR>2{print $1}' | grep -qE '[0-9]' \
    || best_effort sudo snapper -c home create -d "baseline (archfrican)"
  ok "home Time Machine active — archfrican-timemachine recovers file versions from /home"
fi

# snap-pac snapshots every pacman transaction; grub-btrfsd (the inotify daemon,
# NOT the obsolete grub-btrfs.path) regenerates the boot menu on snapshot changes.
# resilient_enable: one missing/renamed unit can't abort the whole safety net.
substep "enabling grub-btrfsd (boot-menu rollback entries) + snapper timers"
resilient_enable grub-btrfsd.service
resilient_enable snapper-timeline.timer
resilient_enable snapper-cleanup.timer
substep "regenerating the GRUB config (adds the snapshots submenu)"
regen_grub

# Post-condition: claim success only if the config is real and usable.
if sudo snapper -c root list &>/dev/null; then
  ok "Snapshots active. A broken update is now one reboot away from a rollback."
else
  die "snapper 'root' config missing/unusable — rollback is NOT set up. See warnings above."
fi
