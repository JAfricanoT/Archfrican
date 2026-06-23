#!/usr/bin/env bash
# Unit test for the FIDO2 no-lockout PAM stack (lib/fido2.sh). Fixture-based — needs NO security key
# and NO real PAM stack, so it runs in CI. Covers the two safety-critical invariants the audit flagged
# as having zero automated test reach:
#   1. fido2_pam_selfcheck refuses a key-only stack (no password include) and a missing u2f-sufficient
#      line — i.e. it enforces "password always works / no lockout".
#   2. fido2_assert_version refuses pam-u2f < 1.3.1 (CVE-2025-23013) and accepts >= 1.3.1.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"     # warn/die/ok/have (and set -euo pipefail)
# shellcheck source=/dev/null
source "$ROOT/lib/fido2.sh"
set +e                            # we drive assertions ourselves; die() in a tested fn is caught via a subshell

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
assert_rc(){ if [ "$2" = "$1" ]; then _ok "$3 (rc=$2)"; else _no "$3 (want rc=$1, got $2)"; fi; }

# ---- 1. fido2_pam_selfcheck against fixture /etc/pam.d files --------------------------------------
D="$(mktemp -d)"; export FIDO2_PAM_DIR="$D"
printf 'auth\tsufficient\tpam_u2f.so cue nouserok\nauth\tinclude\tsystem-auth\naccount\tinclude\tsystem-auth\n' > "$D/good"
fido2_pam_selfcheck good >/dev/null 2>&1; assert_rc 0 $? "selfcheck ACCEPTS u2f-sufficient above an intact password include"
printf 'auth\tsufficient\tpam_u2f.so cue nouserok\n' > "$D/keyonly"
fido2_pam_selfcheck keyonly >/dev/null 2>&1; assert_rc 1 $? "selfcheck REJECTS a key-only stack (no password include = lockout risk)"
printf 'auth\tinclude\tsystem-auth\n' > "$D/nou2f"
fido2_pam_selfcheck nou2f >/dev/null 2>&1; assert_rc 1 $? "selfcheck REJECTS a stack with no u2f-sufficient line"

# ---- 2. fido2_assert_version (CVE-2025-23013 guard): fake pamu2fcfg + pacman on PATH --------------
BIN="$(mktemp -d)"; printf '#!/bin/sh\n:\n' > "$BIN/pamu2fcfg"; chmod +x "$BIN/pamu2fcfg"
_setver(){ printf '#!/bin/sh\necho "pam-u2f %s-1"\n' "$1" > "$BIN/pacman"; chmod +x "$BIN/pacman"; }
export PATH="$BIN:$PATH"
_setver 1.2.0; ( fido2_assert_version ) >/dev/null 2>&1; assert_rc 1 $? "assert_version REFUSES pam-u2f 1.2.0 (< 1.3.1, CVE-2025-23013)"
_setver 1.3.0; ( fido2_assert_version ) >/dev/null 2>&1; assert_rc 1 $? "assert_version REFUSES pam-u2f 1.3.0 (< 1.3.1)"
_setver 1.3.1; ( fido2_assert_version ) >/dev/null 2>&1; assert_rc 0 $? "assert_version ACCEPTS pam-u2f 1.3.1"
_setver 1.4.0; ( fido2_assert_version ) >/dev/null 2>&1; assert_rc 0 $? "assert_version ACCEPTS pam-u2f 1.4.0"

rm -rf "$D" "$BIN"
printf '\nfido2 unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
