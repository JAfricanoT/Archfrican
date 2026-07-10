#!/usr/bin/env bash
# Read-only dual-boot detector: find ANOTHER installed OS on a DIFFERENT disk so the installer can
# offer to add it to the GRUB menu (os-prober, modules/55-multiboot.sh).
#
# Detection is by ESP-file inspection, NOT os-prober. Why: an EFI System Partition is plain FAT that
# the firmware must read, so it is never BitLocker-encrypted nor locked by a hibernated/fast-startup
# Windows — exactly the cases where os-prober (which grub-mounts the NTFS root) fails to name it. We
# only read a few well-known loader paths off a read-only mount, so the "is there another OS?" answer
# is independent of that OS's runtime/encryption state. NEVER mutates a disk; mounts ESPs read-only
# and unmounts every one before returning.
#
# Self-contained (only coreutils + lsblk/mount). is_iso()/live_disk() (lib/env.sh, lib/disk.sh) are
# used opportunistically via `declare -F`, so this also sources cleanly into bin/archfrican-doctor.

# Stable GPT type GUID for an EFI System Partition (vendor-independent).
_AF_ESP_GUID='c12a7328-f81f-11d2-ba4b-00a0c93ec93b'

# _af_root_disk -> bare name of the disk backing the running root ('' if undetectable / encrypted /
# on the ISO). Mirrors lib/health.sh::check_smart so we never report OURSELVES as "another OS".
_af_root_disk() {
  local src base
  src="$(findmnt -no SOURCE / 2>/dev/null)" || return 0
  case "$src" in /dev/mapper/*|"") return 0;; esac
  base="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
  printf '%s' "$base"
}

# Mount/umount helpers: plain when root (the ISO), sudo -n when booted (never prompt — degrade to
# "couldn't read" instead of blocking a wizard/health run).
_af_mount_ro() { if [ "$(id -u)" -eq 0 ]; then mount -o ro "$1" "$2" 2>/dev/null
                 else sudo -n mount -o ro "$1" "$2" 2>/dev/null; fi; }
_af_umount()   { if [ "$(id -u)" -eq 0 ]; then umount "$1" 2>/dev/null
                 else sudo -n umount "$1" 2>/dev/null; fi; }

# _af_esp_os <mounted-esp-dir> -> echoes "Windows" / "Linux (GRUB)" by which loader is present, rc 0;
# rc 1 (no echo) if none. Skips our OWN loader (EFI/Archfrican). Subshell body so the case-insensitive
# globbing (ESPs are FAT) can't leak `shopt` state to the caller.
_af_esp_os() (
  d="$1"
  shopt -s nocaseglob nullglob
  if [ -e "$d/EFI/Microsoft/Boot/bootmgfw.efi" ] || [ -e "$d/EFI/Microsoft/Boot/bootmgr.efi" ]; then
    printf 'Windows'; exit 0
  fi
  for g in "$d"/EFI/*/grub*.efi "$d"/EFI/*/shim*.efi "$d"/EFI/systemd/systemd-boot*.efi; do
    case "$g" in */EFI/[Aa]rchfrican/*) continue;; esac
    [ -e "$g" ] && { printf 'Linux (GRUB)'; exit 0; }
  done
  exit 1
)

# detect_other_os [exclude_disk]
#   Prints one line per OTHER OS found:  "Windows on /dev/sda" / "Linux (GRUB) on /dev/sdb".
#   rc 0 = >=1 found · rc 1 = none · rc 2 = cannot probe (no UEFI / no lsblk). Read-only.
detect_other_os() {
  [ -d /sys/firmware/efi ] || return 2
  command -v lsblk >/dev/null 2>&1 || return 2

  local target="${1:-}" x
  # exclude-set (space-padded for substring match): caller's target + our root + the live USB.
  local excl=" "
  for x in "${target#/dev/}" "$(_af_root_disk)"; do [ -n "$x" ] && excl+="$x "; done
  if declare -F is_iso >/dev/null 2>&1 && is_iso && declare -F live_disk >/dev/null 2>&1; then
    x="$(live_disk)"; [ -n "$x" ] && excl+="$x "
  fi

  local line NAME PKNAME FSTYPE PARTTYPE MOUNTPOINT d os m
  local ntfs_disks=" " esp_unread=" " found=0
  local -a mounts=() hits=()
  # Captures NAME/PKNAME/FSTYPE/PARTTYPE from one `lsblk -P` line — all four are kernel/filesystem-
  # derived (a device basename, an fs-type string, a GPT type GUID), never attacker-influenced text,
  # so a plain regex capture (never `eval`) is safe. Pattern lives in a variable, not inline after
  # `=~` — bash's own backslash handling on an inline regex literal is a well-known footgun.
  local field_pattern='^NAME="([^"]*)" PKNAME="([^"]*)" FSTYPE="([^"]*)" PARTTYPE="([^"]*)"'

  # lsblk -P = key="value" pairs (robust to empty fields, unlike space-split raw output). MOUNTPOINT
  # is deliberately NOT requested here and never parsed from this line: it is the one field a
  # malicious removable-drive LABEL can influence (via gvfs/udisks2 automount, e.g.
  # /run/media/$USER/<LABEL>), so it used to reach `eval "$line"` unsanitized — a command-injection
  # primitive in root context, triggerable just by plugging in a crafted USB drive. It's now fetched
  # by itself, per-device, via a plain `lsblk -no MOUNTPOINT` call whose output is only ever read
  # into a variable (`read`/command substitution), never evaluated as code.
  while IFS= read -r line; do
    NAME=""; PKNAME=""; FSTYPE=""; PARTTYPE=""
    [[ $line =~ $field_pattern ]] || continue
    NAME="${BASH_REMATCH[1]}"; PKNAME="${BASH_REMATCH[2]}"; FSTYPE="${BASH_REMATCH[3]}"; PARTTYPE="${BASH_REMATCH[4]}"
    [ -n "$PKNAME" ] || continue                         # partitions only (whole disks have empty PKNAME)
    case "$excl" in *" $PKNAME "*) continue;; esac        # skip excluded disks
    [ "$FSTYPE" = ntfs ] && ntfs_disks+="$PKNAME "        # remember NTFS for the BitLocker soft-hint
    [ "$PARTTYPE" = "$_AF_ESP_GUID" ] || continue         # only ESPs past here (lsblk emits the GUID lowercase)
    MOUNTPOINT="$(lsblk -no MOUNTPOINT "/dev/$NAME" 2>/dev/null)"
    case "$MOUNTPOINT" in /boot|/boot/*|/mnt/boot|/mnt/boot/*) continue;; esac  # our own ESP
    d="$(mktemp -d 2>/dev/null)" || continue
    if ! _af_mount_ro "/dev/$NAME" "$d"; then rmdir "$d" 2>/dev/null; esp_unread+="$PKNAME "; continue; fi
    mounts+=("$d")
    os="$(_af_esp_os "$d")" || os=""
    [ -n "$os" ] || continue
    case " ${hits[*]} " in *" $os@$PKNAME "*) continue;; esac  # dedupe per (disk, kind)
    hits+=("$os@$PKNAME")
    printf '%s on /dev/%s\n' "$os" "$PKNAME"
    found=1
  done < <(lsblk -Pno NAME,PKNAME,FSTYPE,PARTTYPE 2>/dev/null)

  # Soft hint: a disk with NTFS whose ESP we could NOT read (e.g. an oddly-laid-out / locked ESP) and
  # that we did not already name as Windows. Narrow on purpose — a bare NTFS data disk has no ESP, so
  # it never lands here (no false "Windows" on data drives). Never used to auto-enable on headless.
  for x in $esp_unread; do
    case " ${hits[*]} " in *"Windows@$x"*) continue;; esac
    case "$ntfs_disks" in *" $x "*) printf 'Windows (likely) on /dev/%s\n' "$x"; found=1;; esac
  done

  for m in "${mounts[@]}"; do _af_umount "$m"; rmdir "$m" 2>/dev/null; done
  [ "$found" = 1 ]
}

# other_os_summary [exclude_disk] -> compact, deduped label ("Windows, Linux (GRUB)") on stdout.
#   rc 0 if any OS found, 1 otherwise. Thin wrapper for callers that only need a yes/no + a name.
other_os_summary() {
  local out; out="$(detect_other_os "${1:-}")" || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out" | sed 's# on /dev/.*$##' \
    | awk '!seen[$0]++{ list = list (n++ ? ", " : "") $0 } END{ printf "%s", list }'
}
