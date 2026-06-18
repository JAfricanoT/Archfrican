#!/usr/bin/env bash
# Phase 2, step 5b: multi-boot. Enables GRUB's os-prober so an ALREADY-INSTALLED OS
# (Windows / another Linux, usually on another disk) appears in the GRUB menu — WITHOUT
# losing the grub-btrfs snapshot submenu (both are independent grub.d scripts on the same
# regen). Off unless the wizard toggle passes 'yes'. Re-run: ./install.sh 55-multiboot.
# NOT install-alongside / repartitioning — it only DETECTS an OS that is already there.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/grub.sh"

# Gate 1: only when explicitly asked. Empty/anything-but-'yes' (incl. the headless default) = no-op.
[ "${1:-no}" = yes ] || exit 0

# Gate 2: GRUB only (os-prober + grub-btrfs are GRUB features). Belt-and-suspenders today
# (GRUB is hardcoded); future-proof if a non-GRUB bootloader is ever added.
if [ ! -f /etc/default/grub ] || ! have grub-mkconfig; then
  warn "multi-boot needs GRUB (/etc/default/grub + grub-mkconfig) — skipping os-prober"
  exit 0
fi

substep "installing os-prober (detects other installed operating systems)"
pac_install_file "$REPO_ROOT/packages/multiboot.txt"

substep "enabling os-prober in /etc/default/grub"
set_grub_key GRUB_DISABLE_OS_PROBER false

substep "probing other disks for operating systems — this can be slow"
# os-prober grub-mounts every partition as root; a locked/huge NTFS can crawl. Cap it so a
# slow probe can never wedge the install — grub.cfg is (re)written either way.
timeout 300 sudo grub-mkconfig -o /boot/grub/grub.cfg \
  || warn "grub-mkconfig hit the 5-min cap or errored — the menu was still written; re-run if an OS is missing"

ok "Multi-boot enabled. Other operating systems (if detected) now appear in the GRUB menu."
warn "A BitLocker-locked or hibernated/fast-startup Windows may NOT be detected. Fully shut it"
warn "down (or decrypt) and re-run:  ./install.sh 55-multiboot"
