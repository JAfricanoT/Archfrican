#!/usr/bin/env bash
# Unit test for the firewall allow-helper (lib/security.sh::fw_allow). Fixture-based — points
# ARCHFRICAN_FW_ALLOWS at a temp file and stubs sudo/nft, so it needs NO root and NO nftables and runs
# in CI. Covers the validation that keeps the firewall from ever coming up fail-OPEN:
#   1. A port out of 1-65535, a non-numeric port, or a non-tcp/udp proto is REJECTED (rc 2) and never
#      persisted — an out-of-range port appended to the include would fail the whole `nft -f` reload.
#   2. A valid allow is persisted as a well-formed rule, proto defaults to tcp, and a repeat is deduped.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"
# Point the persist-file at a temp path BEFORE sourcing (the var is now `${ARCHFRICAN_FW_ALLOWS:-…}`).
export ARCHFRICAN_FW_ALLOWS; ARCHFRICAN_FW_ALLOWS="$(mktemp)"; : > "$ARCHFRICAN_FW_ALLOWS"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/security.sh"
set +e                            # common.sh enabled `set -e`; we capture rc ourselves (a rejected
                                  # fw_allow returns 2 by design and must not abort the test).
# Stubs: run the inner command without privilege (grep/tee act on the temp file); nft is a no-op log.
sudo(){ "$@"; }
NFT_LOG="$(mktemp)"; : > "$NFT_LOG"
nft(){ printf '%s\n' "$*" >> "$NFT_LOG"; }

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
assert_rc(){ if [ "$2" = "$1" ]; then _ok "$3 (rc=$2)"; else _no "$3 (want rc=$1, got $2)"; fi; }
has_line(){ if grep -qF "$1" "$ARCHFRICAN_FW_ALLOWS"; then _ok "$2"; else _no "$2 (line not in allows file)"; fi; }

# ---- 1. rejects (must NOT persist anything) ------------------------------------------------------
: > "$ARCHFRICAN_FW_ALLOWS"
fw_allow ""        >/dev/null 2>&1; assert_rc 2 $? "REJECTS empty spec"
fw_allow abc/tcp   >/dev/null 2>&1; assert_rc 2 $? "REJECTS non-numeric port"
fw_allow 0/tcp     >/dev/null 2>&1; assert_rc 2 $? "REJECTS port 0 (out of 1-65535)"
fw_allow 70000/tcp >/dev/null 2>&1; assert_rc 2 $? "REJECTS port 70000 (out of 1-65535)"
fw_allow 3000/sctp >/dev/null 2>&1; assert_rc 2 $? "REJECTS proto other than tcp/udp"
if [ -s "$ARCHFRICAN_FW_ALLOWS" ]; then _no "a rejected spec persisted a rule (fail-open risk!)"; else _ok "no rejected spec ever persisted a rule"; fi

# ---- 2. valid allows: well-formed rule, proto default, dedup -------------------------------------
: > "$ARCHFRICAN_FW_ALLOWS"
fw_allow 3000/tcp >/dev/null 2>&1; assert_rc 0 $? "ACCEPTS 3000/tcp"
has_line 'add rule inet filter input tcp dport 3000 accept' "persists a well-formed nftables rule"
fw_allow 8080 >/dev/null 2>&1;     assert_rc 0 $? "ACCEPTS bare 8080"
has_line 'tcp dport 8080 accept' "bare port defaults to proto tcp"
fw_allow 53/udp >/dev/null 2>&1;   assert_rc 0 $? "ACCEPTS 53/udp"
has_line 'udp dport 53 accept' "persists udp rule"
fw_allow 3000/tcp >/dev/null 2>&1; assert_rc 0 $? "re-adding 3000/tcp is a no-op success"
n="$(grep -cF 'tcp dport 3000 accept' "$ARCHFRICAN_FW_ALLOWS")"
if [ "$n" = 1 ]; then _ok "dedup: exactly one 3000/tcp line"; else _no "dedup failed ($n lines for 3000/tcp)"; fi

rm -f "$ARCHFRICAN_FW_ALLOWS" "$NFT_LOG"
printf '\nfw_allow unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
