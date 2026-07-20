#!/usr/bin/env bash
# Unit test for lib/resume-guard.sh's counter + fail-closed marker logic. Fixture-based — points
# ARCHFRICAN_STATE_DIR at a temp dir and stubs sudo, so it needs NO root and runs in CI. Covers the
# bug this script exists to prevent: the "stop retrying" decision must NEVER depend on sudo
# succeeding, or a machine whose NOPASSWD grant is already gone retries (and fails) forever.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

run_guard() {                     # run_guard <fresh-state-dir> -> sets RC to resume-guard.sh's exit code
  (
    export ARCHFRICAN_STATE_DIR="$1"
    sudo(){ return 1; }            # stub: sudo always FAILS (simulates the exact broken-grant scenario)
    export -f sudo
    bash "$ROOT/lib/resume-guard.sh"
  )
  RC=$?
}

# ---- 1. counter increments across repeated calls, no sudo needed ---------------------------------
state1="$(mktemp -d)"
for i in 1 2 3; do run_guard "$state1"; done
n="$(cat "$state1/resume-attempts" 2>/dev/null || echo MISSING)"
if [ "$n" = 3 ]; then _ok "counter reaches 3 after 3 calls, written without sudo"; else _no "counter=$n, expected 3"; fi
[ -e "$state1/resume-stopped" ] && _no "marker created too early (n=3, MAX defaults to 5)" || _ok "no marker yet at n=3"

# ---- 2. exceeding MAX creates the marker BEFORE any sudo cleanup, and exits 1 ---------------------
state2="$(mktemp -d)"
for i in 1 2 3 4 5 6; do run_guard "$state2"; done
[ "$RC" -eq 1 ] && _ok "6th call (n=6 > MAX=5) exits 1" || _no "6th call exit code = $RC, expected 1"
[ -e "$state2/resume-stopped" ] && _ok "marker exists after exceeding MAX, with sudo fully stubbed out" \
                                 || _no "marker MISSING — the fail-closed path still silently depends on sudo"

# ---- 3. a fresh call after the marker exists still increments harmlessly (systemd's own Condition,
#         not this script, is what actually stops future runs — this only proves the script itself
#         never re-derives "should I run" from anything requiring privilege) --------------------------
run_guard "$state2"
[ -e "$state2/resume-stopped" ] && _ok "marker persists across a subsequent call" || _no "marker disappeared"

rm -rf "$state1" "$state2"
printf '\nresume-guard unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
