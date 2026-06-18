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

run_module() {                # run_module <name> [arg]
  local name="$1" stamp="$PHASE2_STATE/$1.done"
  if [ -f "$stamp" ] && [ -z "${FORCE:-}" ]; then ok "skip $name (already done)"; return 0; fi
  current_module="$name"
  log "── module: $name ──"
  bash "$REPO_ROOT/modules/$name.sh" "${2:-}"
  touch "$stamp"; current_module=""
}

run_phase2() {                # run_phase2 [single-module]
  set -E; trap on_err ERR     # errtrace: fire on_err for failures inside run_module too
  mkdir -p "$PHASE2_STATE"

  # Single-module shortcut: ./install.sh 30-dev  (always re-runs it, no wizard)
  if [ $# -gt 0 ]; then FORCE=1 run_module "$1"; ok "module '$1' done"; return 0; fi

  pac_install pciutils
  local DETECTED_GPU; DETECTED_GPU="$(detect_gpu)"

  # ---- defaults from live system (also the non-interactive fallback) --------
  local HOST USER_NAME USER_PW TZ LOCALE XKB THEME GPU
  HOST="$(hostnamectl --static 2>/dev/null || echo archfrican)"
  USER_NAME="$USER"; USER_PW=""
  TZ="$(timedatectl show -p Timezone --value 2>/dev/null || echo America/New_York)"
  LOCALE="en_US.UTF-8"; XKB="us"
  THEME="$(cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo macos-dark)"
  GPU="$DETECTED_GPU"

  # ---- comfortable wizard (only with a real terminal) -----------------------
  if ui_interactive; then
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
  else
    warn "non-interactive — using detected defaults (host=$HOST user=$USER_NAME gpu=$GPU theme=$THEME)"
  fi
  log "GPU profile: $GPU"

  # ---- apply host/user BEFORE the modules (idempotent) ----------------------
  apply_hostname        "$HOST"
  apply_user            "$USER_NAME" "$USER_PW"
  apply_timezone        "$TZ"
  apply_locale_keyboard "$LOCALE" "$XKB" "$XKB"
  mkdir -p "$HOME/.config"
  printf '%s\n' "$THEME" > "$HOME/.config/.archfrican-theme"   # chezmoi run_after applies it last
  printf '%s\n' "$XKB"   > "$HOME/.config/.archfrican-kbd"     # niri config.kdl template reads it
  ok "staged theme=$THEME, niri keyboard=$XKB"

  # ---- the existing phase-2 orchestration (resumable via .done checkpoints) --
  preflight_pkgs
  run_module 00-base
  run_module 10-gpu "$GPU"
  run_module 20-niri-desktop
  run_module 30-dev
  run_module 40-theming
  run_module 50-snapshots

  current_module="dotfiles (chezmoi)"
  log "Applying dotfiles with chezmoi"
  have chezmoi || sudo pacman -S --needed --noconfirm chezmoi
  chezmoi init --apply --source "$REPO_ROOT/home" \
    || die "chezmoi failed — packages installed but dotfiles NOT deployed. Re-run: chezmoi init --apply --source $REPO_ROOT/home"
  current_module=""

  current_module="verify-spawns"
  verify_spawns "$REPO_ROOT/home/dot_config/niri/config.kdl"
  current_module=""

  ok "Done. Kernel linux-cachyos (fallback linux-lts in GRUB) · compositor niri · GPU $GPU · theme $THEME."

  # ---- reboot modal ---------------------------------------------------------
  if ui_interactive && ui_confirm 'Reboot now to enter your new session?'; then
    ok "rebooting"; sudo systemctl reboot
  else
    warn "Reboot when ready: sudo systemctl reboot  (NVIDIA needs it before the first niri session)."
  fi
}
