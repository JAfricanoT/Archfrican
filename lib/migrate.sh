#!/usr/bin/env bash
# Versioned one-shot migrations — the ONE place an UPDATE legitimately differs from a fresh
# install: undoing OLD state (a renamed config, a retired service, a moved drop-in) that a clean
# install never had. Each migrations/NNNN-slug.sh is idempotent and runs at most once; the applied
# version lives in $ARCHFRICAN_STATE_DIR/state-version (world-readable, so the drift check needs no
# sudo). KEY SEMANTIC: a FRESH install stamps the version to the latest at install time (it's already
# at the target state — historical migrations are for upgrading OLD machines only); a system with NO
# state-version is therefore an OLD/pre-migrations install and is treated as v0 (it runs the full
# delta). Sourced (never executed) by install.sh, bin/archfrican-update, bin/archfrican-doctor.
# Needs REPO_ROOT (exported by lib/common.sh).

ARCHFRICAN_STATE_DIR="${ARCHFRICAN_STATE_DIR:-/var/lib/archfrican}"
ARCHFRICAN_VERSION_FILE="$ARCHFRICAN_STATE_DIR/state-version"

_mig_latest() {                   # highest NNNN present in migrations/ (0 if none)
  local f n max=0
  for f in "$REPO_ROOT"/migrations/[0-9]*.sh; do
    [ -e "$f" ] || continue
    n="$(basename "$f")"; n="${n%%-*}"; n=$((10#$n))
    [ "$n" -gt "$max" ] && max="$n"
  done
  printf '%s' "$max"
}
_mig_current() {                  # applied version (empty string if never recorded)
  local v; v="$(cat "$ARCHFRICAN_VERSION_FILE" 2>/dev/null || true)"; printf '%s' "${v:-}"
}
_mig_set() { printf '%s\n' "$1" | sudo tee "$ARCHFRICAN_VERSION_FILE" >/dev/null; }

# Run every migration newer than the recorded version, in order; record progress after each so a
# crash resumes cleanly. An absent state-version means a pre-migrations (old) install -> v0 -> the
# full delta runs. Uses ok/substep/die from common.sh (run inside a common.sh context).
run_migrations() {
  sudo install -d -m 0755 "$ARCHFRICAN_STATE_DIR"
  local latest cur; latest="$(_mig_latest)"; cur="$(_mig_current)"; cur="${cur:-0}"
  [ "$cur" -ge "$latest" ] && { ok "migrations: up to date (v$cur)"; return 0; }
  local f n ran=0
  for f in "$REPO_ROOT"/migrations/[0-9]*.sh; do
    [ -e "$f" ] || continue
    n="$(basename "$f")"; n="${n%%-*}"; n=$((10#$n))
    [ "$n" -gt "$cur" ] || continue
    substep "migration $(basename "$f")"
    bash "$f" || die "migration failed: $(basename "$f") — fix it, then re-run archfrican-update"
    _mig_set "$n"; ran=$((ran + 1))
  done
  ok "migrations: applied $ran (now at v$latest)"
}

# Stamp the current repo's migration level as already-applied WITHOUT running anything — called at the
# end of a FRESH install (a clean system is already at the target state). This is exactly what keeps a
# fresh install from being mistaken for an old one: with a state-version present it's "current", while
# a pre-migrations install (no state-version) is treated as v0 and runs the delta.
mig_mark_latest() {
  sudo install -d -m 0755 "$ARCHFRICAN_STATE_DIR"
  _mig_set "$(_mig_latest)"
}

# Count of unrun migrations (for the drift report). An absent state-version counts as v0 (an old
# install that still owes the full delta); a fresh install stamped its version, so it returns 0. No sudo.
pending_migrations() {
  local latest cur; latest="$(_mig_latest)"; cur="$(_mig_current)"; cur="${cur:-0}"
  [ "$cur" -ge "$latest" ] && { printf 0; return; }
  printf '%s' "$((latest - cur))"
}
