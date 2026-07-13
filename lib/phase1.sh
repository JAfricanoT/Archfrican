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
gen_answers() {                     # gen_answers <host> <user> <tz> <locale> <xkb> <theme> <gpu> <multiboot> <ssh>
  printf 'ARCHFRICAN_HOST=%q\nARCHFRICAN_USER=%q\nARCHFRICAN_TZ=%q\nARCHFRICAN_LOCALE=%q\nARCHFRICAN_XKB=%q\nARCHFRICAN_THEME=%q\nARCHFRICAN_GPU=%q\nARCHFRICAN_MULTIBOOT=%q\nARCHFRICAN_SSH=%q\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

# Install the self-cleaning first-boot resume into the freshly-installed target. Runs ONLY on
# the armed path, after run_base_install. The base install leaves /mnt mounted and the wheel
# user created, so the precondition below holds by construction.
inject_resume() {                   # inject_resume <user> <host> <tz> <locale> <xkb> <theme> <gpu> <multiboot> <ssh>
  local user="$1" host="$2" tz="$3" loc="$4" xkb="$5" theme="$6" gpu="$7" multiboot="${8:-no}" ssh="${9:-no}"
  local src; src="$(clone_dest)"    # the ISO self-clone, e.g. /root/.archfrican
  mountpoint -q /mnt || die "target not mounted at /mnt — cannot wire the resume"
  local home="/mnt/home/$user"
  [ -d "$home" ] || die "expected $home (base-install should have created user '$user')"

  substep "copying the installer into the new system ($home/.archfrican)"
  rm -rf "$home/.archfrican"; cp -a "$src" "$home/.archfrican"

  substep "staging the wizard answers + theme/keyboard for the headless resume"
  gen_answers "$host" "$user" "$tz" "$loc" "$xkb" "$theme" "$gpu" "$multiboot" "$ssh" > "$home/.archfrican-answers"
  install -d -m 0700 "$home/.config"
  printf '%s\n' "$theme" > "$home/.config/.archfrican-theme"
  printf '%s\n' "$xkb"   > "$home/.config/.archfrican-kbd"
  arch-chroot /mnt chown -R "$user:$user" "/home/$user/.archfrican" \
    "/home/$user/.archfrican-answers" "/home/$user/.config"
  chmod 0600 "$home/.archfrican-answers"

  substep "writing the temporary NOPASSWD sudoers drop-in (removed after resume)"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > /mnt/etc/sudoers.d/99-archfrican-resume
  chmod 0440 /mnt/etc/sudoers.d/99-archfrican-resume
  arch-chroot /mnt visudo -cf /etc/sudoers.d/99-archfrican-resume >/dev/null \
    || die "resume sudoers drop-in invalid — refusing to leave a broken sudo"

  substep "carrying the live medium's network profiles into the target (resume connectivity)"
  # The headless resume runs `preflight base` (a fatal net check) and needs the network. A wired box
  # auto-gets DHCP, but a WiFi-only laptop has no profile unless we copy what the operator connected
  # with on the ISO. Two stores, depending on the tool used: `nmtui` writes NetworkManager keyfiles to
  # /etc/NetworkManager/system-connections; the Arch ISO's standard `iwctl` is iwd and stores PSKs in
  # /var/lib/iwd. Carry BOTH so a WiFi-only install doesn't boot-loop on the fatal net check (audit H2).
  local carried=0
  if compgen -G '/etc/NetworkManager/system-connections/*' >/dev/null 2>&1; then
    install -d -m 0755 /mnt/etc/NetworkManager/system-connections
    cp -a /etc/NetworkManager/system-connections/. /mnt/etc/NetworkManager/system-connections/
    chmod 600 /mnt/etc/NetworkManager/system-connections/* 2>/dev/null || true
    ok "copied live NetworkManager profiles → target"; carried=1
  fi
  if compgen -G '/var/lib/iwd/*' >/dev/null 2>&1; then
    install -d -m 0700 /mnt/var/lib/iwd
    cp -a /var/lib/iwd/. /mnt/var/lib/iwd/
    chmod 600 /mnt/var/lib/iwd/* 2>/dev/null || true
    # point the target's NetworkManager at the iwd backend so the carried PSKs provide connectivity
    install -d -m 0755 /mnt/etc/NetworkManager/conf.d
    printf '[device]\nwifi.backend=iwd\n' > /mnt/etc/NetworkManager/conf.d/wifi-backend.conf
    arch-chroot /mnt systemctl enable iwd.service >/dev/null 2>&1 || true
    ok "copied live iwd (iwctl) WiFi credentials → target + set NetworkManager wifi.backend=iwd"; carried=1
  fi
  [ "$carried" = 1 ] || warn "no live WiFi/NetworkManager profiles to copy — the resume relies on auto wired DHCP (fine for a wired/VM target)"

  substep "installing + enabling archfrican-resume.service (runs once on first boot)"
  sed "s/@USER@/$user/g" "$REPO_ROOT/templates/archfrican-resume.service" \
    > /mnt/etc/systemd/system/archfrican-resume.service
  # CachyOS is verified by GPG signature against a pinned key fingerprint (modules/00-base.sh), so the
  # headless resume verifies itself unattended — there is no per-release pin to forward. Only carry the
  # rare accept-unverified escape hatch through, if the operator set it for this run.
  if [ "${ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS:-0}" = 1 ]; then
    sed -i '/^Environment=ARCHFRICAN_NONINTERACTIVE=1/a Environment=ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1' \
      /mnt/etc/systemd/system/archfrican-resume.service
    substep "forwarded ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1 to the resume"
  fi
  arch-chroot /mnt systemctl enable archfrican-resume.service

  substep "first-boot console feedback (login banner + status notice) — so the headless install is visible"
  install -m 0644 "$REPO_ROOT/templates/firstboot-notice.sh" /mnt/etc/profile.d/zz-archfrican-firstboot.sh
  install -d -m 0755 /mnt/etc/issue.d
  printf '%s\n' '' \
    '  ==> Archfrican is finishing your install (desktop + dev layer) in the background.' \
    '      Log in, then watch:  journalctl -u archfrican-resume -f' \
    '' > /mnt/etc/issue.d/10-archfrican.issue

  ok "first-boot resume wired — the desktop/dev layer installs itself after reboot"
}

# Non-interactive install answers for automated VM testing (tests/e2e/selftest.sh). Reads AF_AP_* from the
# environment instead of prompting, and assigns run_phase1's locals via bash dynamic scope. Secrets come
# from env (visible only inside the throwaway test VM) and still reach the installer on fd 3/4, never argv.
p1_autopilot() {
  warn "AUTOPILOT — non-interactive install from AF_AP_* env (no wizard). Automated VM testing only."
  DISK="${AF_AP_DISK:?autopilot: AF_AP_DISK is required}"
  ENCRYPT="${AF_AP_ENCRYPT:-yes}"
  HOST="${AF_AP_HOST:-archfrican}"
  USER_NAME="${AF_AP_USER:-archfrican}"
  TZ="${AF_AP_TZ:-UTC}"
  LOCALE="${AF_AP_LOCALE:-en_US.UTF-8}"
  XKB="${AF_AP_XKB:-us}"
  THEME="${AF_AP_THEME:-$ARCHFRICAN_DEFAULT_THEME}"
  GPU="${AF_AP_GPU:-$(detect_gpu)}"
  SSH_ENABLE="${AF_AP_SSH:-no}"
  MULTIBOOT="${AF_AP_MULTIBOOT:-no}"   # tests stay single-boot; the detector never runs in autopilot
  [ -n "${AF_AP_USER_PASSWORD:-}" ] || die "autopilot: AF_AP_USER_PASSWORD is required"
  USER_ENC="$(printf '%s' "$AF_AP_USER_PASSWORD" | openssl passwd -6 -stdin)"
  [ "$ENCRYPT" != yes ] || DISK_PW="${AF_AP_LUKS_PASSPHRASE:?autopilot: AF_AP_LUKS_PASSPHRASE required when AF_AP_ENCRYPT=yes}"
  ok "autopilot: disk=$DISK encrypt=$ENCRYPT host=$HOST user=$USER_NAME tz=$TZ locale=$LOCALE xkb=$XKB gpu=$GPU theme=$THEME"
}

run_phase1() {
  set -E; trap on_err ERR
  step_total 5

  step "Preflight" "verifying this live environment can install Archfrican"
  preflight iso

  # ---- wizard (or autopilot for automated VM testing) -----------------------
  step "Setup wizard" "disk · encryption · hostname · user · locale · keyboard · theme · GPU"
  local DISK ENCRYPT HOST USER_NAME TZ LOCALE XKB THEME GPU SSH_ENABLE=no MULTIBOOT=no
  # Passwords never echoed. The user password is HASHED ($6$ SHA-512, via stdin so it never hits argv)
  # and handed to the installer on fd 4; the LUKS passphrase on fd 3.
  local USER_PW DISK_PW="" USER_ENC
  if [ "${ARCHFRICAN_AUTOPILOT:-0}" = 1 ]; then
    p1_autopilot                       # non-interactive answers from AF_AP_* env (tests/e2e/selftest.sh)
  else
    ui_install_gum
    local DETECTED_GPU; DETECTED_GPU="$(detect_gpu)"
    DISK="$(pick_disk)"
    if ui_confirm "¿Cifrar el disco $DISK? (recomendado)"; then ENCRYPT=yes; else ENCRYPT=no; fi
    HOST="$(ui_input 'Hostname' archfrican)"
    USER_NAME="$(ui_input 'Primary user' archfrican)"
    TZ="$(timedatectl list-timezones 2>/dev/null | ui_filter 'Timezone' America/New_York)"
    LOCALE="$(ui_input 'Locale (LANG)' en_US.UTF-8)"
    XKB="$(ui_input 'Keyboard layout (xkb: us, latam, es, ...)' us)"
    # shellcheck disable=SC2046  # word-split intentional: theme names are bare dir names (no spaces)
    THEME="$(ui_choose 'Initial theme' $(list_themes))"
    GPU="${ARCHFRICAN_GPU:-$DETECTED_GPU}"   # auto-detected; the installer picks the driver (no mis-pick)
    ui_note "GPU: $GPU (auto-detectada — el instalador elige el driver. Override: ARCHFRICAN_GPU=vm|nvidia|amd|intel)"
    # Multi-boot: detect another OS on a DIFFERENT disk and offer to add it to the GRUB menu (os-prober,
    # module 55). Default YES when found (and auto-yes on a headless tty-less run). The detector excludes
    # $DISK + the live USB. Override for scripted installs: ARCHFRICAN_MULTIBOOT=1|yes / 0|no.
    case "${ARCHFRICAN_MULTIBOOT:-auto}" in
      1|yes) MULTIBOOT=yes ;;
      0|no)  MULTIBOOT=no ;;
      *)     local _other; _other="$(other_os_summary "$DISK" || true)"
             if [ -n "$_other" ]; then
               ui_note "Detectado otro sistema operativo ($_other) en otro disco."
               ui_confirm "¿Mostrar $_other en el menú de arranque (multi-boot)?" && MULTIBOOT=yes
             fi ;;
    esac
    if ui_confirm "¿Habilitar el servidor SSH (acceso remoto, endurecido)?" no; then SSH_ENABLE=yes; fi
    USER_PW="$(ui_password "Password for $USER_NAME")"
    [ "$ENCRYPT" = yes ] && DISK_PW="$(ui_password 'Disk passphrase')"
    USER_ENC="$(printf '%s' "$USER_PW" | openssl passwd -6 -stdin)"; USER_PW=""
  fi

  # ---- real install vs preview ----------------------------------------------
  # Headless env-arm (ARCHFRICAN_ISO_ARMED=1 + ARCHFRICAN_ISO_GO=1) still works. Interactively — and not
  # autopilot, not forced-preview — offer a REAL install, defaulting to PREVIEW so a casual run never wipes
  # without an explicit yes. Either way run_base_install + confirm_wipe (retype the device) are the final gate.
  if [ "${ARCHFRICAN_AUTOPILOT:-0}" != 1 ] && [ "${ARCHFRICAN_DRY_RUN:-0}" != 1 ] \
     && ! { [ "$ARCHFRICAN_ISO_ARMED" = 1 ] && [ "${ARCHFRICAN_ISO_GO:-0}" = 1 ]; } \
     && ui_interactive; then
    ui_note "Una instalación REAL BORRARÁ todo en $DISK. Preview = imprime el plan, no toca el disco."
    if ui_confirm "¿Hacer la instalación REAL ahora en $DISK?" no; then
      ARCHFRICAN_ISO_ARMED=1; ARCHFRICAN_ISO_GO=1   # interactive arm; confirm_wipe still gates the wipe
    else
      ok "Preview (dry-run) — se imprime el plan, nada se toca. (ARCHFRICAN_DRY_RUN=1 lo fuerza siempre.)"
    fi
  fi

  # ---- base install (lib/base-install.sh) -----------------------------------
  step "Installing the base system" "sgdisk · cryptsetup · mkfs.btrfs · pacstrap · arch-chroot · GRUB on $DISK"
  # run_base_install prints the whole destructive plan and touches NOTHING unless armed; it sets
  # the global AF_INSTALLED. Secrets: LUKS passphrase on fd 3 (read only when encrypting), the
  # user's $6$ hash on fd 4 — never argv/env/file.
  run_base_install "$DISK" "$ENCRYPT" "$HOST" "$USER_NAME" "$TZ" "$LOCALE" "$XKB" 3<<<"$DISK_PW" 4<<<"$USER_ENC"
  DISK_PW=""; USER_ENC=""

  if [ "$AF_INSTALLED" != 1 ]; then
    ok "Preview (dry-run) — the full plan printed above; NOTHING was touched."
    ok "For a REAL install: re-run interactively and answer 'REAL install?' yes, or set ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1."
    ok "Procedure / VM validation: docs/STAGE2-VALIDATION.md"
    return 0
  fi

  # ---- wire the post-reboot finish + reboot ---------------------------------
  step "Wiring the post-reboot finish" "first-boot service that adds the niri desktop + dev layer"
  # Multi-boot is auto-enabled when another OS is detected on a DIFFERENT disk (only $DISK is wiped;
  # other disks are untouched). os-prober runs at first boot via module 55 with this staged answer.
  inject_resume "$USER_NAME" "$HOST" "$TZ" "$LOCALE" "$XKB" "$THEME" "$GPU" "$MULTIBOOT" "$SSH_ENABLE"

  step "Reboot" "into your new system; the rest installs automatically on first boot"
  ok "Base install complete. Hostname $HOST · user $USER_NAME (sudo) · GPU $GPU · theme $THEME."
  if [ "${ARCHFRICAN_AUTOPILOT:-0}" = 1 ]; then
    ok "autopilot: install complete — NOT rebooting (the harness asserts first). /mnt left mounted."
    return 0
  fi
  local _usb; _usb="$(live_disk)"
  warn "IMPORTANT: remove the installer USB NOW, before rebooting${_usb:+ (detected: /dev/$_usb)}."
  warn "  If you leave it in, the firmware may boot it again or reshuffle the boot order, and the"
  warn "  internal disk will look 'not bootable' even though the install is fine."
  if ui_confirm 'Reboot now?'; then
    ok "rebooting"; systemctl reboot
  else
    warn "Reboot when ready: systemctl reboot. After you unlock the disk once, the install finishes on its own."
  fi
}
