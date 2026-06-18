#!/usr/bin/env bash
# ============================================================================
#  Archfrican — phase 2 installer (run AFTER the base Arch install + first reboot)
#  Orchestrates the modules in order. Idempotent: safe to re-run any time.
#  Usage:  ./install.sh                 # run everything (skips completed modules)
#          ./install.sh 30-dev          # run a single module (always re-runs it)
#          FORCE=1 ./install.sh         # re-run every module from scratch
#  Env:    ARCHFRICAN_SKIP_PREFLIGHT=1       # skip the package-resolution preflight
#          ARCHFRICAN_STRICT_PREFLIGHT=1     # make a failed preflight fatal
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh
source lib/detect-gpu.sh

[ "$EUID" -eq 0 ] && die "Run as your normal user, not root (sudo is called when needed)."

# ---- failure observability + resumable checkpoints ------------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
mkdir -p "$STATE_DIR"
current_module=""
on_err() {
  local rc=$?
  [ -n "$current_module" ] && {
    warn "step '$current_module' FAILED (exit $rc)"
    warn "fix the cause, then re-run ./install.sh to resume (completed modules are"
    warn "skipped; use FORCE=1 ./install.sh to redo everything, or ./install.sh $current_module)."
  }
  exit "$rc"
}
trap on_err ERR

run_module() {                # run_module <name> [arg]
  local name="$1" stamp="$STATE_DIR/$1.done"
  if [ -f "$stamp" ] && [ -z "${FORCE:-}" ]; then ok "skip $name (already done)"; return 0; fi
  current_module="$name"
  log "── module: $name ──"
  bash "modules/$name.sh" "${2:-}"
  touch "$stamp"; current_module=""
}

# Single-module run: always re-execute the requested module.
if [ $# -gt 0 ]; then FORCE=1 run_module "$1"; exit 0; fi

log "Archfrican install starting on $(hostname)"

# lspci is required by GPU detection, which runs BEFORE 00-base installs base.txt.
pac_install pciutils
GPU="$(detect_gpu)"; log "GPU profile: $GPU"

# Fail fast if any pacman-list entry won't resolve (catches a misfiled AUR pkg
# or a typo) before a single package is installed.
preflight_pkgs

run_module 00-base
run_module 10-gpu "$GPU"
run_module 20-niri-desktop
run_module 30-dev
run_module 40-theming
run_module 50-snapshots

current_module="dotfiles (chezmoi)"
log "Applying dotfiles with chezmoi"
if ! command -v chezmoi &>/dev/null; then sudo pacman -S --needed --noconfirm chezmoi; fi
chezmoi init --apply --source "$PWD/home" \
  || die "chezmoi failed — packages installed but dotfiles NOT deployed. Re-run: chezmoi init --apply --source $PWD/home"
current_module=""

# Every binary niri is told to spawn must now resolve to an installed package.
current_module="verify-spawns"
verify_spawns "$REPO_ROOT/home/dot_config/niri/config.kdl"
current_module=""

ok "Done. Reboot, pick your session in tuigreet, and enjoy."
echo
echo "  Default kernel : linux-cachyos   (fallback: linux-lts in GRUB)"
echo "  Compositor     : niri            (swap = edit modules/20 + packages/niri-desktop.txt)"
echo "  GPU            : $GPU            (auto, supports amd/intel/nvidia/hybrid)"
echo "  Theme switcher : theme-switch <name>   (macos-dark macos-light catppuccin-mocha tokyo-night)"
