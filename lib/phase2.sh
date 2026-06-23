#!/usr/bin/env bash
# Phase 2 — the booted-base experience: wizard -> apply host/user -> stage
# theme/keyboard -> the module orchestration (extracted from the old install.sh
# body, verbatim) -> reboot modal. Sourced after common.sh + ui.sh + host-config.sh.

PHASE2_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
current_module=""

on_err() {
  local rc=$?
  [ -n "$current_module" ] && {
    warn "step '$current_module' FAILED (exit $rc)"
    warn "re-run the installer to resume (completed modules are skipped; FORCE=1 redoes all,"
    warn "or run a single module: ./install.sh $current_module)."
  }
  exit "$rc"
}

module_label() { case "$1" in
  00-base) echo "Base system";; 10-gpu) echo "GPU drivers";; 20-niri-desktop) echo "Desktop (niri)";;
  30-dev) echo "Dev toolchains";; 35-apps) echo "Apps & Flatpak";; 40-theming) echo "Theming";;
  45-print) echo "Printing & scanning";; 50-snapshots) echo "Snapshots";;
  55-multiboot) echo "Multi-boot";; 60-security) echo "Security";; 65-gaming) echo "Gaming";; 70-hygiene) echo "Hygiene";;
  *) echo "$1";; esac; }
module_desc() { case "$1" in
  00-base) echo "CachyOS repos, dual kernel (cachyos + lts), paru";;
  10-gpu) echo "vendor-agnostic drivers for the detected GPU";;
  20-niri-desktop) echo "compositor, SDDM login, keyd, audio";;
  30-dev) echo "editors, language servers, version managers, docker";;
  35-apps) echo "Flatpak + Flathub, software center, cloud/SMB";;
  40-theming) echo "fonts, macOS GTK theme, hot-swap switcher";;
  45-print) echo "CUPS + SANE, driverless printer/scanner discovery";;
  50-snapshots) echo "snapper + grub-btrfs rollback";;
  55-multiboot) echo "os-prober: detect another installed OS (GRUB)";;
  65-gaming) echo "Steam, gamescope, gamemode, Proton-GE, MangoHud (opt-in)";;
  60-security) echo "firewall, dev-safe hardening, screen lock, FIDO2";;
  70-hygiene) echo "maintenance timers + weekly health check (notify, never auto-change)";;
  *) echo "";; esac; }

run_module() {                # run_module <name> [arg]
  local name="$1" stamp="$PHASE2_STATE/$1.done" want
  # Content-addressed skip (lib/converge.sh): the stamp stores the hash of the module's inputs
  # (script + package list(s) + shared libs). Equal hash = nothing changed -> skip. This drives
  # install-resume AND update-converge with one mechanism; a bumped package list re-runs ONLY that
  # module. (Legacy empty stamps mismatch once and re-converge harmlessly, then store the hash.)
  want="$(module_hash "$name")"
  if [ -z "${FORCE:-}" ] && [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then
    step "$(module_label "$name") — skipped" "unchanged (FORCE=1 to redo)"; return 0
  fi
  step "$(module_label "$name")" "$(module_desc "$name")"
  current_module="$name"
  local rc=0
  bash "$REPO_ROOT/modules/$name.sh" "${2:-}" || rc=$?
  # rc 3 = the module opted itself out (e.g. multi-boot not selected): don't stamp .done,
  # so a later opt-in isn't masked. Any other nonzero is a real failure -> propagate to on_err.
  if [ "$rc" = 3 ]; then current_module=""; ok "$(module_label "$name") — not selected"; return 0; fi
  [ "$rc" = 0 ] || return "$rc"
  printf '%s\n' "$want" > "$stamp"; ok "$(module_label "$name") complete"; current_module=""
}

run_phase2() {                # run_phase2 [single-module]
  set -E; trap on_err ERR     # errtrace: fire on_err for failures inside run_module too
  mkdir -p "$PHASE2_STATE"

  # Single-module shortcut: ./install.sh 30-dev   (or ./install.sh 55-multiboot yes — the 2nd
  # arg is forwarded to the module). Always re-runs it (FORCE), no wizard.
  if [ $# -gt 0 ]; then FORCE=1 run_module "$1" "${2:-}"; ok "module '$1' done"; return 0; fi

  pac_install pciutils
  local DETECTED_GPU; DETECTED_GPU="$(detect_gpu)"

  # ---- defaults from live system (also the non-interactive fallback) --------
  local HOST USER_NAME USER_PW TZ LOCALE XKB THEME GPU MULTIBOOT=no SSH_ENABLE=no GAMING=no
  HOST="$(hostnamectl --static 2>/dev/null || echo archfrican)"
  USER_NAME="$USER"; USER_PW=""
  TZ="$(timedatectl show -p Timezone --value 2>/dev/null || echo America/New_York)"
  LOCALE="en_US.UTF-8"; XKB="us"
  THEME="$(cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo macos-dark)"
  GPU="$DETECTED_GPU"

  # ---- comfortable wizard (only with a real terminal) -----------------------
  # ARCHFRICAN_NONINTERACTIVE=1 forces the headless path even when /dev/tty exists
  # (the ISO first-boot resume service sets it — see templates/archfrican-resume.service).
  if [ "${ARCHFRICAN_NONINTERACTIVE:-0}" != 1 ] && ui_interactive; then
    ui_install_gum
    ui_header "Archfrican setup"
    HOST="$(ui_input 'Hostname' "$HOST")"
    USER_NAME="$(ui_input 'Primary user' "$USER_NAME")"
    if ui_confirm "Set/change a password for $USER_NAME?"; then USER_PW="$(ui_password 'Password')"; fi
    TZ="$(timedatectl list-timezones 2>/dev/null | ui_filter 'Timezone' "$TZ")"
    LOCALE="$(ui_input 'Locale (LANG)' "$LOCALE")"
    XKB="$(ui_input 'Keyboard layout (xkb: us, latam, es, ...)' "$XKB")"
    THEME="$(ui_choose 'Initial theme' macos-dark macos-light catppuccin-mocha tokyo-night)"
    GPU="${ARCHFRICAN_GPU:-$DETECTED_GPU}"   # auto-detected; the installer picks the driver (no mis-pick)
    ui_note "GPU: $GPU (auto-detectada — el instalador elige el driver. Override: ARCHFRICAN_GPU=vm|nvidia|amd|intel)"
    # Multi-boot (opt-in, default NO): enable os-prober so an already-installed OS shows up
    # in the GRUB menu. Keeps the snapshot rollback submenu. Detects, never repartitions.
    if ui_confirm_default_no "Share this machine with another OS already installed (multi-boot)?"; then
      MULTIBOOT=yes
    fi
    # SSH server (opt-in, default NO): a hardened sshd + an nftables allow for 22/tcp (remote access).
    if ui_confirm_default_no "Enable the SSH server (remote access, hardened)?"; then
      SSH_ENABLE=yes
    fi
    # Gaming stack (opt-in, default NO): [multilib] + Steam/gamescope/gamemode/MangoHud/Proton-GE.
    if ui_confirm_default_no "Install the gaming stack (Steam, gamescope, Proton-GE)?"; then
      GAMING=yes
    fi
    # FIDO2 physical-key mode (opt-in; needs a plugged key). Enroll the touch(es) now;
    # modules/60-security.sh wires PAM. Non-exclusive: your password ALWAYS still works.
    if ui_confirm "Enable a hardware security key? (touch = sudo/login; password still works)"; then
      best_effort pac_install pam-u2f libfido2
      if have pamu2fcfg && fido2_enroll "$USER_NAME"; then
        mkdir -p "$HOME/.config"; printf 'pam\n' > "$HOME/.config/.archfrican-fido2"
        ok "FIDO2 key registered — PAM is wired in the security step (password stays a fallback)"
      else
        warn "FIDO2 not enabled (no key registered) — continuing with password auth"
      fi
    fi
  elif [ -r "$HOME/.archfrican-answers" ]; then
    # ISO resume: the Stage-1 wizard's picks, staged by lib/phase1.sh::inject_resume.
    # shellcheck source=/dev/null
    . "$HOME/.archfrican-answers"
    HOST="${ARCHFRICAN_HOST:-$HOST}";   USER_NAME="${ARCHFRICAN_USER:-$USER_NAME}"
    TZ="${ARCHFRICAN_TZ:-$TZ}";         LOCALE="${ARCHFRICAN_LOCALE:-$LOCALE}"
    XKB="${ARCHFRICAN_XKB:-$XKB}";      THEME="${ARCHFRICAN_THEME:-$THEME}"
    GPU="${ARCHFRICAN_GPU:-$GPU}";       MULTIBOOT="${ARCHFRICAN_MULTIBOOT:-no}"
    SSH_ENABLE="${ARCHFRICAN_SSH:-$SSH_ENABLE}"
    GAMING="${ARCHFRICAN_GAMING:-$GAMING}"
    log "resume: loaded wizard answers (host=$HOST user=$USER_NAME gpu=$GPU theme=$THEME)"
  else
    warn "non-interactive — using detected defaults (host=$HOST user=$USER_NAME gpu=$GPU theme=$THEME)"
  fi

  # Update/converge mode (ARCHFRICAN_UPDATE=1, set by `install.sh --update`): preserve the earlier
  # opt-ins by reading the LIVE system, so re-converging never silently disables SSH/multi-boot the
  # user turned on (identity itself — host/user/tz/locale/theme — is left untouched; see below).
  local UPDATE="${ARCHFRICAN_UPDATE:-0}"
  if [ "$UPDATE" = 1 ]; then
    systemctl is-enabled --quiet sshd.service 2>/dev/null && SSH_ENABLE=yes
    grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub 2>/dev/null && MULTIBOOT=yes
    pacman -Q steam &>/dev/null && GAMING=yes
  fi
  log "GPU profile: $GPU"

  if [ "$UPDATE" = 1 ]; then ui_header "Converging Archfrican (update)"; else ui_header "Installing Archfrican"; fi
  step_total 15

  # ---- apply host/user BEFORE the modules (idempotent) ----------------------
  # Update/converge skips identity: hostname/user/tz/locale/theme are set ONCE at install, and
  # re-applying them could clobber a value the user changed by hand. An update re-converges only the
  # software/config layer (the modules) + dotfiles — exactly what makes it "the repo, applied".
  if [ "$UPDATE" != 1 ]; then
    step "Applying your choices" "hostname · user · timezone · locale · keyboard"
    apply_hostname        "$HOST"
    apply_user            "$USER_NAME" "$USER_PW"
    apply_timezone        "$TZ"
    apply_locale_keyboard "$LOCALE" "$XKB" "$XKB"
    mkdir -p "$HOME/.config"
    printf '%s\n' "$THEME" > "$HOME/.config/.archfrican-theme"   # chezmoi run_after applies it last
    printf '%s\n' "$XKB"   > "$HOME/.config/.archfrican-kbd"     # niri config.kdl template reads it
    ok "staged theme=$THEME, niri keyboard=$XKB"
  fi

  # ---- the existing phase-2 orchestration (resumable via .done checkpoints) --
  substep "verifying every listed package resolves in a repo"
  preflight_pkgs
  run_module 00-base
  ensure_login_shell "$USER_NAME"   # zsh exists now (base.txt) — make the resume's pre-created bash user use it
  run_module 10-gpu "$GPU"
  run_module 20-niri-desktop
  run_module 30-dev
  run_module 35-apps
  run_module 40-theming
  run_module 45-print
  run_module 50-snapshots
  run_module 55-multiboot "$MULTIBOOT"
  run_module 60-security "$SSH_ENABLE"
  run_module 65-gaming "$GAMING"
  run_module 70-hygiene

  step "Dotfiles" "deploying your config (niri, zsh, waybar, …) with chezmoi"
  current_module="dotfiles (chezmoi)"
  have chezmoi || sudo pacman -S --needed --noconfirm chezmoi
  chezmoi init --apply --source "$REPO_ROOT/home" \
    || die "chezmoi failed — packages installed but dotfiles NOT deployed. Re-run: chezmoi init --apply --source $REPO_ROOT/home"
  current_module=""

  step "Final checks" "verifying every app launcher resolves to a package"
  current_module="verify-spawns"
  # Check the chezmoi-RENDERED config (templates + absolute paths resolved), not the source.
  verify_spawns "$HOME/.config/niri/config.kdl"
  current_module=""

  ok "Done. Kernel linux-cachyos (fallback linux-lts in GRUB) · compositor niri · GPU $GPU · theme $THEME."

  # Record the desired-state manifest (drives drift detection + safe `--prune`). Done on every run so
  # a fresh install also has a baseline; opt-ins (multiboot) are reflected so prune respects them.
  write_manifest "$MULTIBOOT"
  # Fresh install (incl. the ISO first-boot resume): stamp the migration version current so the new
  # machine never re-runs historical migrations. In update mode archfrican-update already ran them.
  [ "$UPDATE" = 1 ] || mig_mark_latest

  # Update/converge ends here: no first-boot broadcast, no reboot modal — the user is on a running
  # desktop and just brought it level with the repo. (archfrican-update prints the reboot hint.)
  if [ "$UPDATE" = 1 ]; then
    ok "Converge complete — config + dotfiles now match the repo."
    return 0
  fi

  # First-boot resume (headless): the user is on a bare console with no session, so the install ran
  # invisibly in the journal. Tell them ON-SCREEN that it finished + to reboot. `wall` reaches any logged-in
  # tty the instant we finish; the marker flips the /etc/profile.d notice to "reboot"; the banner is cleared.
  if [ "${ARCHFRICAN_NONINTERACTIVE:-0}" = 1 ]; then
    best_effort sudo install -d /var/lib/archfrican
    best_effort sudo touch /var/lib/archfrican/firstboot-done
    best_effort sudo rm -f /etc/issue.d/10-archfrican.issue
    best_effort sudo wall "Archfrican: desktop ready -- reboot to enter it:  sudo systemctl reboot"
  fi

  # ---- reboot modal ---------------------------------------------------------
  # Skip on the headless ISO resume — the resume service self-cleans and the login
  # manager is already enabled; the user reboots/logs in on their own terms.
  if [ "${ARCHFRICAN_NONINTERACTIVE:-0}" != 1 ] && ui_interactive \
     && ui_confirm 'Reboot now to enter your new session?'; then
    ok "rebooting"; sudo systemctl reboot
  else
    warn "Reboot when ready: sudo systemctl reboot  (NVIDIA needs it before the first niri session)."
  fi
}
