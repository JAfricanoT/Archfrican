#!/usr/bin/env bash
# Phase 1 — the Arch live-USB full install. Flow: preflight -> wizard (disk, encryption,
# host/user/locale/keyboard/theme/GPU) -> run_base_install (lib/base-install.sh: sgdisk +
# cryptsetup + mkfs.btrfs + pacstrap + arch-chroot + GRUB, all behind the dry-run gate) ->
# inject the self-cleaning first-boot resume -> reboot. The new system finishes the
# desktop/dev layer automatically (lib/phase2.sh + templates/archfrican-resume.service).
# Sourced after common.sh + ui.sh + env.sh + detect-gpu.sh + preflight.sh + host-config.sh +
# phase2.sh (on_err) + disk.sh + base-install.sh (the ARCHFRICAN_ISO_ARMED gate + run_base_install).

# The non-secret wizard answers the first-boot resume needs (no password — that was set in the
# chroot config; the resume re-applies everything else idempotently).
gen_answers() {                     # gen_answers <host> <user> <tz> <locale> <xkb> <theme> <gpu> <multiboot>
  printf 'ARCHFRICAN_HOST=%q\nARCHFRICAN_USER=%q\nARCHFRICAN_TZ=%q\nARCHFRICAN_LOCALE=%q\nARCHFRICAN_XKB=%q\nARCHFRICAN_THEME=%q\nARCHFRICAN_GPU=%q\nARCHFRICAN_MULTIBOOT=%q\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}

# Install the self-cleaning first-boot resume into the freshly-installed target. Runs ONLY on
# the armed path, after run_base_install. The base install leaves /mnt mounted and the wheel
# user created, so the precondition below holds by construction.
inject_resume() {                   # inject_resume <user> <host> <tz> <locale> <xkb> <theme> <gpu> <multiboot>
  local user="$1" host="$2" tz="$3" loc="$4" xkb="$5" theme="$6" gpu="$7" multiboot="${8:-no}"
  local src; src="$(clone_dest)"    # the ISO self-clone, e.g. /root/.archfrican
  mountpoint -q /mnt || die "target not mounted at /mnt — cannot wire the resume"
  local home="/mnt/home/$user"
  [ -d "$home" ] || die "expected $home (base-install should have created user '$user')"

  substep "copying the installer into the new system ($home/.archfrican)"
  rm -rf "$home/.archfrican"; cp -a "$src" "$home/.archfrican"

  substep "staging the wizard answers + theme/keyboard for the headless resume"
  gen_answers "$host" "$user" "$tz" "$loc" "$xkb" "$theme" "$gpu" "$multiboot" > "$home/.archfrican-answers"
  install -d -m 0700 "$home/.config"
  printf '%s\n' "$theme" > "$home/.config/.archfrican-theme"
  printf '%s\n' "$xkb"   > "$home/.config/.archfrican-kbd"
  arch-chroot /mnt chown -R "$user:$user" "/home/$user/.archfrican" \
    "/home/$user/.archfrican-answers" "/home/$user/.config"
  chmod 0600 "$home/.archfrican-answers"

  substep "writing the temporary NOPASSWD sudoers drop-in (removed after resume)"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > /mnt/etc/sudoers.d/00-archfrican-resume
  chmod 0440 /mnt/etc/sudoers.d/00-archfrican-resume
  arch-chroot /mnt visudo -cf /etc/sudoers.d/00-archfrican-resume >/dev/null \
    || die "resume sudoers drop-in invalid — refusing to leave a broken sudo"

  substep "installing + enabling archfrican-resume.service (runs once on first boot)"
  sed "s/@USER@/$user/g" "$REPO_ROOT/templates/archfrican-resume.service" \
    > /mnt/etc/systemd/system/archfrican-resume.service
  arch-chroot /mnt systemctl enable archfrican-resume.service
  ok "first-boot resume wired — the desktop/dev layer installs itself after reboot"
}

run_phase1() {
  set -E; trap on_err ERR
  step_total 5

  step "Preflight" "verifying this live environment can install Archfrican"
  preflight iso

  # ---- wizard ---------------------------------------------------------------
  step "Setup wizard" "disk · encryption · hostname · user · locale · keyboard · theme · GPU"
  ui_install_gum
  local DETECTED_GPU; DETECTED_GPU="$(detect_gpu)"

  local DISK ENCRYPT HOST USER_NAME TZ LOCALE XKB THEME GPU
  DISK="$(pick_disk)"
  if ui_confirm "¿Cifrar el disco $DISK? (recomendado)"; then ENCRYPT=yes; else ENCRYPT=no; fi
  HOST="$(ui_input 'Hostname' archfrican)"
  USER_NAME="$(ui_input 'Primary user' archfrican)"
  TZ="$(timedatectl list-timezones 2>/dev/null | ui_filter 'Timezone' America/New_York)"
  LOCALE="$(ui_input 'Locale (LANG)' en_US.UTF-8)"
  XKB="$(ui_input 'Keyboard layout (xkb: us, latam, es, ...)' us)"
  THEME="$(ui_choose 'Initial theme' macos-dark macos-light catppuccin-mocha tokyo-night)"
  GPU="$(ui_choose "GPU profile (detected: $DETECTED_GPU)" \
         "$DETECTED_GPU" amd intel nvidia hybrid-intel-nvidia hybrid-amd-nvidia hybrid-amd-intel)"
  # Passwords last, never echoed. The user password is HASHED ($6$ SHA-512, via stdin so it
  # never hits argv) and handed to the installer on fd 4; the LUKS passphrase on fd 3.
  local USER_PW DISK_PW="" USER_ENC
  USER_PW="$(ui_password "Password for $USER_NAME")"
  [ "$ENCRYPT" = yes ] && DISK_PW="$(ui_password 'Disk passphrase')"
  USER_ENC="$(printf '%s' "$USER_PW" | openssl passwd -6 -stdin)"; USER_PW=""

  # ---- base install (lib/base-install.sh) -----------------------------------
  step "Installing the base system" "sgdisk · cryptsetup · mkfs.btrfs · pacstrap · arch-chroot · GRUB on $DISK"
  # run_base_install prints the whole destructive plan and touches NOTHING unless armed; it sets
  # the global AF_INSTALLED. Secrets: LUKS passphrase on fd 3 (read only when encrypting), the
  # user's $6$ hash on fd 4 — never argv/env/file.
  run_base_install "$DISK" "$ENCRYPT" "$HOST" "$USER_NAME" "$TZ" "$LOCALE" "$XKB" 3<<<"$DISK_PW" 4<<<"$USER_ENC"
  DISK_PW=""; USER_ENC=""

  if [ "$AF_INSTALLED" != 1 ]; then
    ok "Dry-run complete — the full plan printed above; NOTHING was touched."
    ok "To install for real: VM-validate, set ARCHFRICAN_ISO_ARMED=1 in lib/base-install.sh, re-run with ARCHFRICAN_ISO_GO=1."
    ok "Procedure: docs/STAGE2-VALIDATION.md"
    return 0
  fi

  # ---- wire the post-reboot finish + reboot ---------------------------------
  step "Wiring the post-reboot finish" "first-boot service that adds the niri desktop + dev layer"
  # Multi-boot is NOT offered on the ISO path (it wipes $DISK); use the booted-path toggle after.
  inject_resume "$USER_NAME" "$HOST" "$TZ" "$LOCALE" "$XKB" "$THEME" "$GPU" no

  step "Reboot" "into your new system; the rest installs automatically on first boot"
  ok "Base install complete. Hostname $HOST · user $USER_NAME (sudo) · GPU $GPU · theme $THEME."
  if ui_confirm 'Reboot now?'; then
    ok "rebooting"; systemctl reboot
  else
    warn "Reboot when ready: systemctl reboot. After you unlock the disk once, the install finishes on its own."
  fi
}
