#!/usr/bin/env bash
# Environment preflight — verify the machine BEFORE anything is installed, so a
# bad environment fails fast (max performance / min error). Complementary to
# common.sh::preflight_pkgs (which checks package-LIST resolution); this checks
# the ENVIRONMENT. Sourced after lib/common.sh.
#
# preflight base|iso   — cheap checks first; net + `pacman -Sy` cached on resume.

PF_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
PF_WARNINGS=()

pf_fatal() { local m="$1"; shift; "$@" >/dev/null 2>&1 || die "PREFLIGHT FAIL: $m"; ok "$m"; }
pf_warn()  { local m="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$m"; else warn "PREFLIGHT WARN: $m"; PF_WARNINGS+=("$m"); fi; }

pf_is_arch()    { [ -e /etc/arch-release ] || grep -q '^ID=arch' /etc/os-release; }
pf_x86_64()     { [ "$(uname -m)" = x86_64 ]; }
pf_uefi()       { [ -d /sys/firmware/efi ]; }
pf_keyring()    { pacman -Q archlinux-keyring; }
pf_net()        { curl -fsS --max-time 8 https://github.com >/dev/null \
                    || curl -fsS --max-time 8 https://geo.mirror.pkgbuild.com/lastsync >/dev/null; }
pf_sync()       { sudo pacman -Sy >/dev/null; }
# BOOTED-base only: free space on the installed root. (KiB, as `df --output=avail` reports.)
pf_disk()       { local need="$1" avail; avail="$(df --output=avail / | tail -1)"; [ "$avail" -ge "$need" ]; }
# ISO only: is an installable whole DISK (>= bytes) present? On the live ISO `/` is a tiny RAM
# overlay (airootfs cowspace), so checking `df /` is meaningless — measure the target device instead.
# `-d` = whole disks (no partitions), `-b` = bytes, TYPE=="disk" drops the ISO's rom/loop.
pf_disk_target() { local need="$1" max
  max="$(lsblk -dnb -o SIZE,TYPE 2>/dev/null | awk '$2=="disk"{ if ($1+0 > m) m=$1 } END{ print m+0 }')"
  [ "${max:-0}" -ge "$need" ]; }
pf_btrfs_snap() { [ "$(findmnt -no FSTYPE /)" = btrfs ] && [ -d /.snapshots ]; }
# Secure Boot state — the installer ships an UNSIGNED GRUB, so SB must be OFF at install time or the
# firmware silently refuses it. The SecureBoot efivar's last byte is 1 when enabled. Re-enable later
# with `archfrican-secureboot` (signs GRUB via sbctl). Returns 0 when SB is off / not enforced.
pf_sb_off()     { local f; f="$(echo /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null)"
  [ -e "$f" ] || return 0
  [ "$(od -An -t u1 "$f" 2>/dev/null | awk '{print $NF}')" != 1 ]; }

preflight() {                      # preflight base|iso
  local mode="$1"; mkdir -p "$PF_STATE"
  log "Preflight ($mode): verifying environment before any changes"
  pf_fatal "running on Arch Linux"  pf_is_arch
  pf_fatal "x86_64 architecture"    pf_x86_64

  if [ "$mode" = iso ]; then
    pf_fatal "UEFI firmware (Must use OVMF/UEFI, not BIOS)" pf_uefi
    if pf_sb_off; then ok "Secure Boot off (GRUB ships unsigned)"
    else
      warn "PREFLIGHT WARN: Secure Boot is ENABLED — the installed GRUB is unsigned, so the firmware will refuse it."
      warn "  Disable Secure Boot in firmware before installing; re-enable later with 'archfrican-secureboot' (signs GRUB via sbctl)."
      PF_WARNINGS+=("Secure Boot enabled — unsigned GRUB won't boot until you disable it (or run archfrican-secureboot)")
    fi
  else
    pf_warn "UEFI firmware (BIOS layout/rollback may differ)" pf_uefi
    [ "$EUID" -ne 0 ] || die "PREFLIGHT FAIL: run phase 2 as your user, not root"
  fi

  # keyring: auto-fixable on a booted base; must already exist on the live medium.
  if pf_keyring >/dev/null 2>&1; then ok "archlinux-keyring present"
  elif [ "$mode" = base ]; then best_effort pac_install archlinux-keyring
  else die "PREFLIGHT FAIL: archlinux-keyring missing on the live medium"; fi

  # expensive (net + sync) — cached so a resumed run skips them.
  if [ -f "$PF_STATE/preflight-net.done" ]; then ok "internet + pacman sync (cached)"
  else
    pf_fatal "internet reachable"                 pf_net
    pf_fatal "pacman -Sy (current rolling base)"   pf_sync
    touch "$PF_STATE/preflight-net.done"
  fi

  if [ "$mode" = iso ]; then
    pf_fatal "an installable disk ≥20G is present" pf_disk_target 21474836480   # 20 GiB, in bytes
  else
    pf_fatal "≥10G free on /" pf_disk 10485760
    pf_warn "root is Btrfs with /.snapshots (rollback feature)" pf_btrfs_snap
  fi

  if [ "${#PF_WARNINGS[@]}" -gt 0 ]; then
    warn "Preflight passed with ${#PF_WARNINGS[@]} warning(s):"
    printf '   - %s\n' "${PF_WARNINGS[@]}" >&2
  else
    ok "Preflight: all checks passed"
  fi
}
