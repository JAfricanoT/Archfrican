#!/usr/bin/env bash
# Phase 2, step 5b: multi-boot. Enables GRUB's os-prober so an ALREADY-INSTALLED OS
# (Windows / another Linux, usually on another disk) appears in the GRUB menu — WITHOUT
# losing the grub-btrfs snapshot submenu (both are independent grub.d scripts on the same
# regen). Off unless the wizard toggle passes 'yes'. Re-run: ./install.sh 55-multiboot yes.
# NOT install-alongside / repartitioning — it only DETECTS an OS that is already there.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/grub.sh"

# Gate 1: only when explicitly asked. Empty/anything-but-'yes' (incl. the headless default) opts
# out with rc 3 — run_module treats that as "not selected" and does NOT stamp .done, so a later
# opt-in ('./install.sh 55-multiboot yes') still runs.
[ "${1:-no}" = yes ] || exit 3

# Gate 2: GRUB only (os-prober + grub-btrfs are GRUB features). Belt-and-suspenders today
# (GRUB is hardcoded); future-proof if a non-GRUB bootloader is ever added.
if [ ! -f /etc/default/grub ] || ! have grub-mkconfig; then
  warn "multi-boot needs GRUB (/etc/default/grub + grub-mkconfig) — skipping os-prober"
  exit 3
fi

substep "installing os-prober (detects other installed operating systems)"
pac_install_file "$REPO_ROOT/packages/multiboot.txt"

substep "enabling os-prober in /etc/default/grub"
set_grub_key GRUB_DISABLE_OS_PROBER false

substep "probing other disks for operating systems — this can be slow"
# os-prober grub-mounts every partition as root; a locked/huge NTFS can crawl. Cap the probe and
# distinguish the cap (124 — menu may be incomplete) from a REAL error: on a real failure revert the
# key and die, so /etc/default/grub stays coherent with the (unchanged) on-disk grub.cfg — grub-mkconfig
# writes atomically, so the old, working menu survives a failed/killed run.
rc=0; regen_grub || rc=$?
if [ "$rc" = 124 ]; then
  warn "grub-mkconfig hit the 5-min cap (a locked/huge NTFS?) — the menu may be incomplete; re-run: ./install.sh 55-multiboot yes"
elif [ "$rc" != 0 ]; then
  set_grub_key GRUB_DISABLE_OS_PROBER true     # revert so the key matches the unchanged menu
  die "grub-mkconfig failed (rc=$rc) — reverted os-prober; fix the error above and re-run"
fi
grep -q menuentry /boot/grub/grub.cfg 2>/dev/null || warn "grub.cfg has no menuentry — inspect /boot/grub/grub.cfg"

ok "Multi-boot enabled. Other operating systems (if detected) now appear in the GRUB menu."
warn "A BitLocker-locked or hibernated/fast-startup Windows may NOT be detected. Fully shut it"
warn "down (or decrypt) and re-run:  ./install.sh 55-multiboot yes"
