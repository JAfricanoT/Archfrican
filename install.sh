#!/usr/bin/env bash
# ============================================================================
#  Archfrican — one-command installer.
#    sh -c "$(curl -fsSL https://raw.githubusercontent.com/JAfricanoT/Archfrican/refs/heads/main/install.sh)"
#  Self-clones the public repo, verifies the environment, then installs in ONE
#  command. SMART: detects the Arch live ISO (full install — coming soon) vs an
#  already-booted base Arch (the desktop/dev layer + a comfortable wizard).
#  In-repo usage:  ./install.sh            # full run (skips completed modules)
#                  ./install.sh 30-dev     # re-run a single module
#                  FORCE=1 ./install.sh    # redo everything
#  Env: ARCHFRICAN_REF=v0.1   ARCHFRICAN_REPO=<url>
#       ARCHFRICAN_SKIP_PREFLIGHT=1 / ARCHFRICAN_STRICT_PREFLIGHT=1 (package preflight)
# ============================================================================
set -euo pipefail

ARCHFRICAN_REPO="${ARCHFRICAN_REPO:-https://github.com/JAfricanoT/Archfrican.git}"
ARCHFRICAN_REF="${ARCHFRICAN_REF:-main}"

# --- self-locate (works even when piped: BASH_SOURCE/$0 are sh/-/bash) -------
src="${BASH_SOURCE:-$0}"
if [ -f "$src" ]; then here="$(CDPATH='' cd -- "$(dirname -- "$src")" && pwd)"; else here=""; fi
in_repo() { [ -n "$here" ] && [ -r "$here/lib/common.sh" ]; }

# --- minimal bootstrap-time helpers (lib/ isn't on disk yet when piped) ------
_is_iso()     { [ -d /run/archiso ]; }
_clone_dest() { if _is_iso; then echo /root/.archfrican; else echo "$HOME/.archfrican"; fi; }
_ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  if [ "$EUID" -eq 0 ]; then pacman -Sy --needed --noconfirm git
  else sudo pacman -Sy --needed --noconfirm git; fi
}

bootstrap() {                       # self-clone the public repo, then re-exec
  [ -n "${ARCHFRICAN_REEXEC:-}" ] && { echo "archfrican: re-exec loop guard tripped (no lib/ in clone?)" >&2; exit 1; }
  local dest; dest="$(_clone_dest)"
  echo "archfrican: fetching the installer into $dest (ref: $ARCHFRICAN_REF) ..." >&2
  _ensure_git
  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --depth 1 origin "$ARCHFRICAN_REF"   # explicit ref, no blind pull
    git -C "$dest" reset --hard FETCH_HEAD
  else
    git clone --depth 1 --branch "$ARCHFRICAN_REF" "$ARCHFRICAN_REPO" "$dest"
  fi
  # bash explicitly: the pipe interpreter may be plain sh, and a missing +x can't bite us.
  ARCHFRICAN_REEXEC=1 exec bash "$dest/install.sh" "$@"
}

# Not running from a clone (piped or stray) -> fetch the repo and re-exec.
in_repo || bootstrap "$@"

# --- in the repo: load helpers, detect environment, dispatch ----------------
cd "$here"
source lib/common.sh           # log/ok/warn/die/have/pac_install/preflight_pkgs/verify_spawns/REPO_ROOT…
source lib/converge.sh         # module_hash/drift_modules — content-addressed module skip (resume + update)
source lib/manifest.sh         # write_manifest/prune_candidates — desired-state ledger (drives --prune)
source lib/migrate.sh          # mig_mark_latest — stamp a fresh install current (so it skips old migrations)
source lib/detect-gpu.sh
source lib/env.sh              # is_iso (canonical)
source lib/ui.sh              # gum||plain wizard primitives
source lib/preflight.sh       # environment preflight
source lib/host-config.sh     # apply hostname/user/timezone/locale
source lib/security.sh       # fw_allow + faillock recovery (shared with 60-security)
source lib/fido2.sh          # FIDO2 enroll/PAM helpers (wizard enroll step)
source lib/disk.sh            # pick_disk + confirm_wipe (read-only, ISO path)
source lib/base-install.sh   # run_base_install (bedrock installer) + the ARCHFRICAN_ISO_ARMED gate
source lib/phase2.sh          # run_phase2 (the booted experience)
source lib/phase1.sh          # run_phase1 (the ISO full install; ships dry-run gated)

if is_iso; then
  [ "$EUID" -eq 0 ] || die "On the Arch ISO this must run as root (it drives the bedrock base install)."
  # Full install from the live USB. SAFE by default: ships dry-run gated
  # (ARCHFRICAN_ISO_ARMED=0) so no disk is touched until VM-validated. See
  # docs/STAGE2-VALIDATION.md.
  run_phase1
else
  [ "$EUID" -eq 0 ] && die "Run as your normal user, not root (sudo is called when needed)."
  case "${1:-}" in
    --update)                                # desired-state converge (invoked by archfrican-update):
      export ARCHFRICAN_UPDATE=1 ARCHFRICAN_NONINTERACTIVE=1   # no wizard, no identity re-apply,
      run_phase2 ;;                                            # only changed modules + dotfiles re-run
    "")  preflight base; run_phase2 ;;
    *)   run_phase2 "$@" ;;                   # single-module shortcut: ./install.sh 30-dev
  esac
fi
