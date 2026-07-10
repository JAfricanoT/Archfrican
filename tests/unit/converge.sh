#!/usr/bin/env bash
# Unit test for lib/converge.sh (module_hash / module_inputs / drift_modules) — the content-addressed
# engine that decides which modules re-run on install-resume, on `archfrican-update --run`/--converge,
# and what archfrican-doctor reports as config drift. Fixture-based: builds a throwaway REPO_ROOT with
# a couple of real modules/packages files, so it needs no root and runs in CI. Zero prior coverage
# (audit finding: this engine had no test at all, despite branching on per-module inputs, dir-vs-file
# hashing, and stamp comparison).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

WORK="$(mktemp -d)"
mkdir -p "$WORK/repo/lib" "$WORK/repo/modules" "$WORK/repo/packages" "$WORK/repo/themes/archfrican-dark"
printf 'echo common\n' > "$WORK/repo/lib/common.sh"
printf 'echo base v1\n' > "$WORK/repo/modules/00-base.sh"
printf 'echo hygiene v1\n' > "$WORK/repo/modules/70-hygiene.sh"
printf 'echo niri v1\n' > "$WORK/repo/modules/20-niri-desktop.sh"
printf 'git\nvim\n' > "$WORK/repo/packages/base.txt"
printf '#!/usr/bin/env bash\nACCENT=#0a84ff\n' > "$WORK/repo/themes/archfrican-dark/colors.sh"

export REPO_ROOT="$WORK/repo"
export XDG_STATE_HOME="$WORK/state"
# shellcheck source=/dev/null
source "$ROOT/lib/converge.sh"
set +e   # we capture rc/output ourselves below

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

# ---- 1. module_hash changes when the module's own script changes ----------------------------------
h1="$(module_hash 00-base)"
printf 'echo base v2\n' > "$WORK/repo/modules/00-base.sh"
h2="$(module_hash 00-base)"
if [ "$h1" != "$h2" ]; then _ok "module_hash changes when modules/00-base.sh changes"; else _no "module_hash did NOT react to a change in the module's own script"; fi

# ---- 2. module_hash changes when the module's package list changes --------------------------------
h1="$(module_hash 00-base)"
printf 'git\nvim\nextra-pkg\n' > "$WORK/repo/packages/base.txt"
h2="$(module_hash 00-base)"
if [ "$h1" != "$h2" ]; then _ok "module_hash changes when packages/base.txt changes"; else _no "module_hash did NOT react to a change in its package list"; fi

# ---- 3. module_hash does NOT change when an UNRELATED module's script changes ----------------------
h1="$(module_hash 00-base)"
printf 'echo hygiene v2\n' > "$WORK/repo/modules/70-hygiene.sh"
h2="$(module_hash 00-base)"
if [ "$h1" = "$h2" ]; then _ok "module_hash for 00-base is unaffected by an unrelated module's script changing"; else _no "module_hash for 00-base changed due to an unrelated module (70-hygiene) — false-positive drift"; fi

# ---- 4. a missing input file is skipped, not a crash -----------------------------------------------
rm -f "$WORK/repo/packages/base.txt"
h="$(module_hash 00-base 2>/tmp/converge-test-stderr.$$)"
rc=$?
if [ "$rc" -eq 0 ] && [ -n "$h" ]; then _ok "module_hash tolerates a missing input file (no crash, still returns a hash)"; else _no "module_hash crashed or returned empty on a missing input file (rc=$rc)"; fi
if [ -s /tmp/converge-test-stderr.$$ ]; then _no "module_hash printed to stderr on a missing input file: $(cat /tmp/converge-test-stderr.$$)"; else _ok "module_hash stayed silent on a missing input file"; fi
rm -f "/tmp/converge-test-stderr.$$"
printf 'git\nvim\n' > "$WORK/repo/packages/base.txt"   # restore for later tests

# ---- 5. directory inputs are tree-hashed: a file INSIDE a dir input changes the hash ---------------
h1="$(module_hash 20-niri-desktop)"
printf '#!/usr/bin/env bash\nACCENT=#ff0000\n' > "$WORK/repo/themes/archfrican-dark/colors.sh"
h2="$(module_hash 20-niri-desktop)"
if [ "$h1" != "$h2" ]; then _ok "module_hash reacts to a file changing inside a directory input (themes/)"; else _no "module_hash did NOT react to a change inside a directory input"; fi

# ---- 6. drift_modules: a matching stamp is NOT drift ------------------------------------------------
mkdir -p "$ARCHFRICAN_PHASE2_STATE"
module_hash 00-base > "$ARCHFRICAN_PHASE2_STATE/00-base.done"
drift="$(drift_modules)"
if ! printf '%s\n' "$drift" | grep -qx '00-base'; then _ok "drift_modules: a stamp matching the current hash is NOT reported as drift"; else _no "drift_modules wrongly reported 00-base as drift with a matching stamp"; fi

# ---- 7. drift_modules: a STALE stamp IS drift -------------------------------------------------------
printf 'deliberately-wrong-hash\n' > "$ARCHFRICAN_PHASE2_STATE/00-base.done"
drift="$(drift_modules)"
if printf '%s\n' "$drift" | grep -qx '00-base'; then _ok "drift_modules: a stale stamp IS reported as drift"; else _no "drift_modules did NOT flag a stale stamp as drift"; fi

# ---- 8. drift_modules: a module with NO stamp (never installed) is NOT drift ------------------------
rm -f "$ARCHFRICAN_PHASE2_STATE/55-multiboot.done"
drift="$(drift_modules)"
if ! printf '%s\n' "$drift" | grep -qx '55-multiboot'; then _ok "drift_modules: a never-installed (no-stamp) module is NOT reported as drift"; else _no "drift_modules wrongly reported a never-installed module as drift"; fi

rm -rf "$WORK"
printf '\nconverge unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
