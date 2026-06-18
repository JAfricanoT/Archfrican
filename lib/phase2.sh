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
  30-dev) echo "Dev toolchains";; 40-theming) echo "Theming";; 50-snapshots) echo "Snapshots";;
  55-multiboot) echo "Multi-boot";; 60-security) echo "Security";; 70-hygiene) echo "Hygiene";;
  *) echo "$1";; esac; }
module_desc() { case "$1" in
  00-base) echo "CachyOS repos, dual kernel (cachyos + lts), paru";;
  10-gpu) echo "vendor-agnostic drivers for the detected GPU";;
  20-niri-desktop) echo "compositor, greetd login, keyd, audio";;
  30-dev) echo "editors, language servers, version managers, docker";;
  40-theming) echo "fonts, macOS GTK theme, hot-swap switcher";;
  50-snapshots) echo "snapper + grub-btrfs rollback";;
  55-multiboot) echo "os-prober: detect another installed OS (GRUB)";;
  60-security) echo "firewall, dev-safe hardening, screen lock, FIDO2";;
  70-hygiene) echo "maintenance timers + weekly health check (notify, never auto-change)";;
  *) echo "";; esac; }

run_module() {                # run_module <name> [arg]
  local name="$1" stamp="$PHASE2_STATE/$1.done"
  if [ -f "$stamp" ] && [ -z "${FORCE:-}" ]; then
    step "$(module_label "$name") — skipped" "already done (FORCE=1 to redo)"; return 0
  fi
  step "$(module_label "$name")" "$(module_desc "$name")"
  current_module="$name"
  local rc=0
  bash "$REPO_ROOT/modules/$name.sh" "${2:-}" || rc=$?
  # rc 3 = the module opted itself out (e.g. multi-boot not selected): don't stamp .done,
  # so a later opt-in isn't masked. Any other nonzero is a real failure -> propagate to on_err.
  if [ "$rc" = 3 ]; then current_module=""; ok "$(module_label "$name") — not selected"; return 0; fi
  [ "$rc" = 0 ] || return "$rc"
  touch "$stamp"; ok "$(module_label "$name") complete"; current_module=""
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
  local HOST USER_NAME USER_PW TZ LOCALE XKB THEME GPU MULTIBOOT=no
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
    TZ="$(ui_input 'Timezone' "$TZ")"
    LOCALE="$(ui_input 'Locale (LANG)' "$LOCALE")"
    XKB="$(ui_input 'Keyboard layout (xkb: us, latam, es, ...)' "$XKB")"
    THEME="$(ui_choose 'Initial theme' macos-dark macos-light catppuccin-mocha tokyo-night)"
    GPU="$(ui_choose "GPU profile (detected: $DETECTED_GPU)" \
           "$DETECTED_GPU" amd intel nvidia hybrid-intel-nvidia hybrid-amd-nvidia hybrid-amd-intel)"
    # Multi-boot (opt-in, default NO): enable os-prober so an already-installed OS shows up
    # in the GRUB menu. Keeps the snapshot rollback submenu. Detects, never repartitions.
    if ui_confirm_default_no "Share this machine with another OS already installed (multi-boot)?"; then
      MULTIBOOT=yes
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
    log "resume: loaded wizard answers (host=$HOST user=$USER_NAME gpu=$GPU theme=$THEME)"
  else
    warn "non-interactive — using detected defaults (host=$HOST user=$USER_NAME gpu=$GPU theme=$THEME)"
  fi
  log "GPU profile: $GPU"

  ui_header "Installing Archfrican"
  step_total 12

  # ---- apply host/user BEFORE the modules (idempotent) ----------------------
  step "Applying your choices" "hostname · user · timezone · locale · keyboard"
  apply_hostname        "$HOST"
  apply_user            "$USER_NAME" "$USER_PW"
  apply_timezone        "$TZ"
  apply_locale_keyboard "$LOCALE" "$XKB" "$XKB"
  mkdir -p "$HOME/.config"
  printf '%s\n' "$THEME" > "$HOME/.config/.archfrican-theme"   # chezmoi run_after applies it last
  printf '%s\n' "$XKB"   > "$HOME/.config/.archfrican-kbd"     # niri config.kdl template reads it
  ok "staged theme=$THEME, niri keyboard=$XKB"

  # ---- the existing phase-2 orchestration (resumable via .done checkpoints) --
  substep "verifying every listed package resolves in a repo"
  preflight_pkgs
  run_module 00-base
  run_module 10-gpu "$GPU"
  run_module 20-niri-desktop
  run_module 30-dev
  run_module 40-theming
  run_module 50-snapshots
  run_module 55-multiboot "$MULTIBOOT"
  run_module 60-security
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
