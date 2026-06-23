#!/usr/bin/env bash
# Content-addressed convergence — the heart of "updating an old Archfrican == a fresh install".
# A module re-runs only when the FILES that define its desired state change (its script + its
# package list(s) + the shared libs it leans on). That hash is recorded in the module's .done
# stamp; an equal hash means skip. The same mechanism serves BOTH:
#   • install-resume — a completed module skips on the next boot (the crashed one re-runs), and
#   • update/converge — only the modules whose inputs changed re-converge (the rest are no-ops),
# and it lets the health check report "drift" (applied state vs the on-disk repo) with NO sudo.
# Sourced (never executed) by install.sh, bin/archfrican-update and bin/archfrican-doctor.
# Needs REPO_ROOT (exported by lib/common.sh).

# Where run_module writes the per-module stamps (matches lib/phase2.sh::PHASE2_STATE).
ARCHFRICAN_PHASE2_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
# Every module the orchestrator knows, in order (for drift scanning).
ARCHFRICAN_MODULES="00-base 10-gpu 20-niri-desktop 30-dev 40-theming 50-snapshots 55-multiboot 60-security 70-hygiene"

# Repo-relative files whose content defines <name>'s desired state. lib/common.sh is shared by
# all (a change to it can affect any module); the script + its package list(s) are module-specific.
module_inputs() {                 # module_inputs <name>
  printf 'lib/common.sh modules/%s.sh' "$1"
  case "$1" in
    00-base)         printf ' packages/base.txt' ;;
    10-gpu)          printf ' lib/detect-gpu.sh lib/grub.sh' ;;
    20-niri-desktop) printf ' packages/niri-desktop.txt templates/sddm.theme.conf assets/sddm/archfrican' ;;
    30-dev)          printf ' packages/dev.txt' ;;
    40-theming)      printf ' packages/theming.txt packages/aur.txt' ;;
    55-multiboot)    printf ' packages/multiboot.txt lib/grub.sh' ;;
    60-security)     printf ' packages/security.txt lib/security.sh lib/fido2.sh' ;;
    70-hygiene)      printf ' bin/archfrican-update bin/archfrican-doctor lib/health.sh' ;;
  esac
}

# sha256 of <name>'s input files (order-stable; missing files are simply skipped). The module
# ARG is deliberately NOT hashed: in update mode the args are inferred from the live system so
# they already match, and an explicit arg change is handled by `./install.sh <module> <arg>`
# (FORCE). Leaving the arg out keeps drift detection free of false positives.
module_hash() {                   # module_hash <name>
  local name="$1" f p inputs
  read -ra inputs <<< "$(module_inputs "$name")"
  { for f in "${inputs[@]}"; do
      p="$REPO_ROOT/$f"
      if [ -d "$p" ]; then find "$p" -type f -exec sha256sum {} + 2>/dev/null | sort
      elif [ -r "$p" ]; then sha256sum "$p" 2>/dev/null
      fi
    done; } | sha256sum | awk '{print $1}'
}

# Names of already-applied modules whose repo inputs no longer match the recorded stamp — i.e.
# the on-disk repo is ahead of what's installed. Never-run modules (e.g. opt-in 55-multiboot
# with no stamp) are NOT drift. Reads only the world-readable stamps: no sudo, no network.
drift_modules() {
  local m stamp
  for m in $ARCHFRICAN_MODULES; do
    stamp="$ARCHFRICAN_PHASE2_STATE/$m.done"
    [ -f "$stamp" ] || continue
    [ "$(cat "$stamp" 2>/dev/null)" = "$(module_hash "$m")" ] || printf '%s\n' "$m"
  done
}
