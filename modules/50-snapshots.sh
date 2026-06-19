#!/usr/bin/env bash
# Phase 2, step 5: make Btrfs snapshots actually save you.
source "$(dirname "$0")/../lib/common.sh"

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
    # archinstall (snapshot_config: Snapper) already created @.snapshots mounted
    # at /.snapshots (in fstab). `snapper create-config` would try to create its
    # OWN /.snapshots subvolume and fail "already exists". ArchWiki procedure:
    # free the mount, let snapper write the config, drop its throwaway subvol,
    # then mount -a restores archinstall's @.snapshots from fstab.
    log "/.snapshots is a pre-existing mount (archinstall) — using ArchWiki procedure"
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

# Non-root reads of snapshots (snapper list, grub-btrfs) need wheel access.
if [ -d /.snapshots ]; then sudo chmod 750 /.snapshots; sudo chown :wheel /.snapshots; fi

# snap-pac snapshots every pacman transaction; grub-btrfsd (the inotify daemon,
# NOT the obsolete grub-btrfs.path) regenerates the boot menu on snapshot changes.
# resilient_enable: one missing/renamed unit can't abort the whole safety net.
substep "enabling grub-btrfsd (boot-menu rollback entries) + snapper timers"
resilient_enable grub-btrfsd.service
resilient_enable snapper-timeline.timer
resilient_enable snapper-cleanup.timer
substep "regenerating the GRUB config (adds the snapshots submenu)"
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Post-condition: claim success only if the config is real and usable.
if sudo snapper -c root list &>/dev/null; then
  ok "Snapshots active. A broken update is now one reboot away from a rollback."
else
  die "snapper 'root' config missing/unusable — rollback is NOT set up. See warnings above."
fi
