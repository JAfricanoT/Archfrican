#!/usr/bin/env bash
# Bedrock Arch base installer — replaces the archinstall dependency. Drives the install
# directly with the stable Arch CLIs (sgdisk, cryptsetup, mkfs.*, pacstrap, genfstab,
# arch-chroot, grub-install, mkinitcpio), so there is NO version-unstable JSON schema to
# track and NO creds file ever lands on disk. Sourced after lib/common.sh + lib/disk.sh.
#
# ┌─ SAFETY ────────────────────────────────────────────────────────────────────┐
# │ Every destructive op goes through run()/run_pipe(), which PRINT the exact     │
# │ command and execute NOTHING unless AF_GO=1. AF_GO=1 is set only when ALL of:  │
# │   ARCHFRICAN_ISO_ARMED=1  AND  ARCHFRICAN_ISO_GO=1  AND  confirm_wipe passes.  │
# │ Arming is a RUNTIME opt-in — set the env vars, or answer the interactive "REAL │
# │ install?" prompt; never committed as 1. No env + non-interactive ⇒ dry-run.   │
# └──────────────────────────────────────────────────────────────────────────────┘

# Defaults to 0; env-overridable so a real install needs NO file edit (CI asserts the safe default —
# see .github/workflows/ci.yml iso-safety-gate). AF_INSTALLED is set here and READ by lib/phase1.sh
# (cross-file global) — hence the file waiver.
# shellcheck disable=SC2034
ARCHFRICAN_ISO_ARMED="${ARCHFRICAN_ISO_ARMED:-0}"
AF_GO=0            # 1 = execute destructive ops; 0 = print only (dry-run)
AF_INSTALLED=0    # set by run_base_install: 1 = a real install happened, 0 = dry-run

# ---- dry-run wrappers -------------------------------------------------------
run() {            # run <argv…>  — a single command that MUST succeed
  if [ "$AF_GO" = 1 ]; then substep "$*"; "$@"
  else printf '  \e[2m[dry-run]\e[0m %s\n' "$(printf '%q ' "$@")" >&2; fi
}
run_pipe() {       # run_pipe '<pipeline>' — pipes/redirs/|| true (single string)
  if [ "$AF_GO" = 1 ]; then substep "$1"; bash -c "set -euo pipefail; $1"
  else printf '  \e[2m[dry-run]\e[0m %s\n' "$1" >&2; fi
}
probe() {          # probe '<placeholder>' <real-cmd…> — placeholder in dry-run, real output armed
  if [ "$AF_GO" = 1 ]; then shift; "$@"; else printf '%s' "$1"; fi
}

# /dev/nvme0n1 -> p1/p2 ; /dev/sda|/dev/vda -> 1/2 ; /dev/mmcblk0 -> p1/p2
part_dev() { case "$1" in *[0-9]) printf '%sp%s' "$1" "$2";; *) printf '%s%s' "$1" "$2";; esac; }

cpu_ucode() {      # echoes intel-ucode / amd-ucode / nothing (unknown)
  case "$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo 2>/dev/null)" in
    GenuineIntel) printf 'intel-ucode';; AuthenticAMD) printf 'amd-ucode';;
  esac
}
xkb_to_vconsole() { # xkb layout -> tty keymap; fall back to 'us' if it isn't a valid console keymap
  local xkb="$1"     # (us/latam/es ARE valid keymaps; many xkb names aren't, e.g. gb's keymap is 'uk')
  if localectl --no-convert list-keymaps 2>/dev/null | grep -qx "$xkb"; then printf '%s' "$xkb"
  else warn "xkb layout '$xkb' is not a console keymap — using 'us' for the TTY + LUKS prompt (X11 layout is unaffected)"; printf 'us'; fi
}

# ---- steps ------------------------------------------------------------------
base_stale_guard() {   # a prior aborted run can leave the target busy -> release, tolerantly
  run_pipe 'umount -R /mnt 2>/dev/null || true'
  run_pipe 'swapoff -a 2>/dev/null || true'
  run_pipe 'cryptsetup close root 2>/dev/null || true'
  run udevadm settle     # let the unmounts + LUKS close release the disk before we wipe/repartition it
}

base_partition() {     # base_partition <disk>
  local disk="$1"
  run wipefs --all "$disk"
  run sgdisk --zap-all "$disk"
  run sgdisk --new=1:0:+1GiB --typecode=1:ef00 --change-name=1:ARCHFRICAN_ESP  "$disk"  # ESP (fat32)
  run sgdisk --new=2:0:0     --typecode=2:8304 --change-name=2:ARCHFRICAN_ROOT "$disk"  # x86-64 root
  run partprobe "$disk"
  run udevadm settle     # partprobe re-reads but doesn't wait for udev; fast NVMe nodes may be absent
}

base_luks() {          # base_luks <rootpart> — single passphrase read from fd 3 (ONCE)
  local rootpart="$1"
  if [ "$AF_GO" = 1 ]; then
    local pass; IFS= read -r -u 3 pass || true
    substep "creating the LUKS2 container on $rootpart (single passphrase)"
    printf '%s' "$pass" | cryptsetup luksFormat --type luks2 --batch-mode "$rootpart" -
    printf '%s' "$pass" | cryptsetup open "$rootpart" root -
    pass=""
  else
    printf '  \e[2m[dry-run]\e[0m %s\n' "printf <luks-pass> | cryptsetup luksFormat --type luks2 --batch-mode $rootpart -" >&2
    printf '  \e[2m[dry-run]\e[0m %s\n' "printf <luks-pass> | cryptsetup open $rootpart root -" >&2
  fi
}

base_format_mount() {  # base_format_mount <esp> <rootfs>
  local esp="$1" rootfs="$2" o="noatime,compress=zstd:3,ssd,space_cache=v2" sv
  run mkfs.fat -F32 -n ESP "$esp"
  run mkfs.btrfs -f -L archfrican "$rootfs"
  run mount "$rootfs" /mnt
  for sv in @ @home @log @pkg @.snapshots; do run btrfs subvolume create "/mnt/$sv"; done
  run umount /mnt
  run mount -o "$o,subvol=@" "$rootfs" /mnt
  run mkdir -p /mnt/home /mnt/var/log /mnt/var/cache/pacman/pkg /mnt/.snapshots /mnt/boot
  run mount -o "$o,subvol=@home"       "$rootfs" /mnt/home
  run mount -o "$o,subvol=@log"        "$rootfs" /mnt/var/log
  run mount -o "$o,subvol=@pkg"        "$rootfs" /mnt/var/cache/pacman/pkg
  run mount -o "$o,subvol=@.snapshots" "$rootfs" /mnt/.snapshots   # module 50 adopts this
  run mount "$esp" /mnt/boot                                       # plaintext ESP = /boot
}

base_pacstrap() {      # base_pacstrap <ucode-or-empty> <encrypt(yes|no)>
  local ucode="$1" enc="$2"
  local -a pkgs=(base linux-lts linux-firmware btrfs-progs grub efibootmgr sudo networkmanager git zram-generator)
  # The initramfs `encrypt` HOOK needs the cryptsetup binary IN THE TARGET at mkinitcpio time (and at
  # every later regen, e.g. linux-cachyos/nvidia). It is NOT in `base`, so it must be pacstrapped.
  [ "$enc" = yes ] && pkgs+=(cryptsetup)
  [ -n "$ucode" ] && pkgs+=("$ucode")
  run pacman -Sy --noconfirm archlinux-keyring   # refresh the LIVE keyring first (avoids sig failures)
  run pacstrap -K /mnt "${pkgs[@]}"              # -K = fresh keyring in the target
}

# The chroot config script is STATIC: config comes via positional args (non-secret), and the
# user's $6$ password hash comes on stdin ($(cat)) — never argv/env/file.
_chroot_script() {
cat <<'CHROOT'
#!/usr/bin/env bash
# args: 1=TZ 2=LOCALE 3=HOST 4=USER 5=VCONSOLE 6=ENCRYPT(yes|no) 7=LUKS_UUID ; stdin: $6$ hash
set -euo pipefail
TZ="$1"; LOCALE="$2"; HOST="$3"; U="$4"; VK="$5"; ENC="$6"; LUKS_UUID="${7:-}"

ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
hwclock --systohc

# LOCALE is interpolated into the sed/grep regex below; reject anything outside a locale's real
# charset so a stray '/' or regex metacharacter can't corrupt /etc/locale.gen (and abort the install).
case "$LOCALE" in *[!A-Za-z0-9._@-]*) echo "FATAL: invalid locale '$LOCALE'"; exit 1;; esac
if grep -qE "^#\s*${LOCALE} " /etc/locale.gen; then sed -i "s/^#\s*\(${LOCALE} .*\)/\1/" /etc/locale.gen
elif ! grep -qE "^${LOCALE} " /etc/locale.gen; then printf '%s UTF-8\n' "$LOCALE" >> /etc/locale.gen; fi
locale-gen
printf 'LANG=%s\n'   "$LOCALE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "$VK"     > /etc/vconsole.conf

printf '%s\n' "$HOST" > /etc/hostname
{ printf '127.0.0.1\tlocalhost\n'; printf '::1\t\tlocalhost\n'; printf '127.0.1.1\t%s\n' "$HOST"; } > /etc/hosts

useradd -m -G wheel -s /bin/bash "$U"            # bash now; the resume installs zsh + chsh
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel >/dev/null
passwd -l root >/dev/null                        # root LOCKED — sudo-only
chpasswd -e <<< "${U}:$(cat)"                    # the ONLY stdin consumer: the $6$ hash

if [ "$ENC" = yes ]; then
  HOOKS='base udev autodetect microcode modconf kms keyboard keymap block encrypt filesystems fsck'
else
  HOOKS='base udev autodetect microcode modconf kms keyboard keymap block filesystems fsck'
fi
sed -i "s/^HOOKS=.*/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf
mkinitcpio -P

if [ "$ENC" = yes ]; then
  CMDLINE="cryptdevice=UUID=${LUKS_UUID}:root root=/dev/mapper/root rootflags=subvol=@"
else
  CMDLINE="rootflags=subvol=@"
fi
# Use GRUB_CMDLINE_LINUX (module 10-gpu edits _DEFAULT -> no collision with the cryptdevice line)
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$CMDLINE\"|" /etc/default/grub
if [ "$ENC" = yes ]; then
  grep -q 'cryptdevice=UUID=' /etc/default/grub || { echo 'FATAL: cryptdevice did not land in /etc/default/grub'; exit 1; }
fi
# GRUB: install to the ESP, then ALSO write the firmware-default removable path so the disk stays
# bootable even if the NVRAM "Archfrican" entry is dropped (firmware reset, install USB left in,
# BootOrder reshuffle, …). Without this fallback the firmware has nothing to auto-discover on the
# disk and it "disappears" from the boot menu though the system is fully installed.
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Archfrican --recheck
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Archfrican --removable --recheck
grub-mkconfig -o /boot/grub/grub.cfg
# Guard (same style as the cryptdevice FATAL above): abort if neither EFI binary actually landed.
[ -f /boot/EFI/Archfrican/grubx64.efi ] || { echo 'FATAL: GRUB missing in ESP (EFI/Archfrican/grubx64.efi)'; exit 1; }
[ -f /boot/EFI/BOOT/BOOTX64.EFI ]       || { echo 'FATAL: removable-fallback GRUB missing (EFI/BOOT/BOOTX64.EFI)'; exit 1; }
# Make the firmware boot Archfrican FIRST. On a MULTI-DISK install with an existing OS, the firmware
# BootOrder may still lead with that OS's entry, so the machine would boot the OLD OS on the first
# reboot even though Arch is fully installed. Move our entry to the front of BootOrder (keeping every
# other entry). Best-effort + safe: any uncertainty just warns and leaves BootOrder untouched, and the
# EFI/BOOT/BOOTX64.EFI removable fallback still guarantees the disk itself is bootable.
af_num="$(efibootmgr 2>/dev/null | sed -nE 's/^Boot([0-9A-Fa-f]{4})\*?[[:space:]]+Archfrican$/\1/p' | head -1)"
cur="$(efibootmgr 2>/dev/null | sed -nE 's/^BootOrder:[[:space:]]*//p' | head -1)"
if [ -n "$af_num" ] && [ -n "$cur" ]; then
  rest="$(printf '%s' "$cur" | tr ',' '\n' | grep -vix "$af_num" | paste -sd, -)"
  if efibootmgr --bootorder "${af_num}${rest:+,$rest}" >/dev/null 2>&1; then
    echo "UEFI BootOrder set: Archfrican (Boot$af_num) boots first"
  else
    echo 'WARN: could not set BootOrder — if it boots another OS first, pick "Archfrican" in the firmware boot menu'
  fi
else
  echo 'WARN: no "Archfrican" UEFI boot entry / BootOrder to reorder — relying on the EFI/BOOT/BOOTX64.EFI fallback'
fi

systemctl enable NetworkManager.service               # the first-boot resume needs the network
systemctl enable NetworkManager-wait-online.service   # so network-online.target actually waits for connectivity

cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
ZRAM
CHROOT
}

base_chroot_config() {  # <tz> <locale> <host> <user> <vconsole> <encrypt> <luks_uuid> ; hash on fd 4
  local tz="$1" loc="$2" host="$3" user="$4" vc="$5" enc="$6" uuid="$7"
  if [ "$AF_GO" = 1 ]; then
    substep "configuring the installed system (locale · user · GRUB · initramfs) via arch-chroot"
    _chroot_script > /mnt/root/archfrican-chroot.sh
    local hash; IFS= read -r -u 4 hash || true
    printf '%s' "$hash" | arch-chroot /mnt bash /root/archfrican-chroot.sh "$tz" "$loc" "$host" "$user" "$vc" "$enc" "$uuid"
    hash=""
    rm -f /mnt/root/archfrican-chroot.sh
  else
    printf '  \e[2m[dry-run] would arch-chroot /mnt with:\e[0m tz=%s locale=%s host=%s user=%s vconsole=%s encrypt=%s luks_uuid=%s\n' \
      "$tz" "$loc" "$host" "$user" "$vc" "$enc" "$uuid" >&2
    printf '  \e[2m[dry-run] chroot config script:\e[0m\n' >&2
    _chroot_script | sed 's/^/      | /' >&2
  fi
}

# Orchestrator. Args (non-secret) + LUKS passphrase on fd 3 + user $6$ hash on fd 4.
# Sets AF_INSTALLED (NOT a return code — a return-in-condition would disable errexit inside).
run_base_install() {   # run_base_install <disk> <encrypt> <host> <user> <tz> <locale> <xkb>
  local disk="$1" enc="$2" host="$3" user="$4" tz="$5" loc="$6" xkb="$7"
  local esp rootpart rootfs uuid="" ucode vc
  esp="$(part_dev "$disk" 1)"; rootpart="$(part_dev "$disk" 2)"
  vc="$(xkb_to_vconsole "$xkb")"; ucode="$(cpu_ucode)"
  [ -n "$ucode" ] || warn "unknown CPU vendor — no microcode package added"

  if [ "$ARCHFRICAN_ISO_ARMED" = 1 ] && [ "${ARCHFRICAN_ISO_GO:-0}" = 1 ]; then
    confirm_wipe "$disk" || die "aborted at the disk-erase confirmation (nothing was changed)"
    AF_GO=1; AF_INSTALLED=1
    warn "ARMED — ERASING $disk and installing the base system."
  else
    AF_GO=0; AF_INSTALLED=0
    warn "SAFE MODE (ARCHFRICAN_ISO_ARMED=$ARCHFRICAN_ISO_ARMED, GO=${ARCHFRICAN_ISO_GO:-0}) — printing the full plan, touching NOTHING:"
  fi

  if [ "$enc" = yes ]; then rootfs="/dev/mapper/root"; else rootfs="$rootpart"; fi
  base_stale_guard
  base_partition "$disk"
  [ "$enc" = yes ] && base_luks "$rootpart"
  base_format_mount "$esp" "$rootfs"
  base_pacstrap "$ucode" "$enc"
  run_pipe 'genfstab -U /mnt >> /mnt/etc/fstab'
  [ "$enc" = yes ] && uuid="$(probe '<LUKS-UUID>' cryptsetup luksUUID "$rootpart")"
  base_chroot_config "$tz" "$loc" "$host" "$user" "$vc" "$enc" "$uuid"
}
