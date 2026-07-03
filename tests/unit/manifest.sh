#!/usr/bin/env bash
# Unit test for lib/manifest.sh (write_manifest + prune_candidates). Fixture-based — stubs sudo/pacman
# and points ARCHFRICAN_STATE_DIR/REPO_ROOT at temp dirs, so it needs NO root and runs in CI. Covers two
# real, live-reproduced bugs:
#   1. write_manifest must NOT crash the first time managed.txt doesn't exist yet — `sudo cat` failing
#      inside the `{ }` group (the pipe's left side, a subshell under set -e) used to abort before
#      cat "$tmp" ever ran, so managed.txt was never written on a fresh machine.
#   2. prune_candidates' `comm` call must run under LC_ALL=C like its inputs — otherwise `comm` applies
#      the ambient locale's collation to C-sorted input and mispairs lines, wrongly keeping a package
#      that's actually in both sets (reproduced live under en_US.UTF-8: "comm: input is not in sorted
#      order" plus a wrong result).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"

WORK="$(mktemp -d)"
export ARCHFRICAN_STATE_DIR="$WORK/state"

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/manifest.sh"
set +e   # common.sh enabled set -e; we capture rc ourselves below.

# sudo stub: run the inner command directly (no privilege needed against temp paths).
sudo(){ "$@"; }

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

# ---- fixture: a minimal package list so write_manifest has something to write --------------------
mkdir -p "$WORK/repo/packages"
printf 'git\nvim\n' > "$WORK/repo/packages/base.txt"
REPO_ROOT="$WORK/repo"

# ---- 1. write_manifest must not crash when managed.txt doesn't exist yet -------------------------
rm -rf "$ARCHFRICAN_STATE_DIR"
write_manifest no >/dev/null 2>&1
rc=$?
if [ "$rc" = 0 ]; then _ok "write_manifest exits 0 on a fresh state dir (no managed.txt yet)"; else _no "write_manifest crashed on a fresh state dir (rc=$rc)"; fi
if [ -r "$ARCHFRICAN_STATE_DIR/managed.txt" ]; then _ok "managed.txt created on first run"; else _no "managed.txt NOT created on first run"; fi
if [ -r "$ARCHFRICAN_STATE_DIR/manifest.txt" ]; then _ok "manifest.txt created on first run"; else _no "manifest.txt NOT created on first run"; fi

# ---- 2. write_manifest merges into an EXISTING managed.txt (cumulative, not overwritten) ----------
printf 'old-package\n' >> "$ARCHFRICAN_STATE_DIR/managed.txt"
write_manifest no >/dev/null 2>&1
if grep -qxF 'old-package' "$ARCHFRICAN_STATE_DIR/managed.txt"; then _ok "managed.txt stays cumulative (old entry preserved)"; else _no "managed.txt lost a previously-managed package"; fi
if grep -qxF 'git' "$ARCHFRICAN_STATE_DIR/managed.txt"; then _ok "managed.txt includes the current manifest's packages"; else _no "managed.txt missing a current package"; fi

# ---- 3. write_manifest's 2nd (plasma) param: opt-in package list included only when yes -----------
printf 'plasma-desktop\ndolphin\n' > "$WORK/repo/packages/plasma-desktop.txt"
rm -rf "$ARCHFRICAN_STATE_DIR"
write_manifest no >/dev/null 2>&1                 # 1-arg call (as tests above + the pre-2nd-param
                                                   # call site used) must still default plasma to "no"
if grep -qxF 'plasma-desktop' "$ARCHFRICAN_STATE_DIR/manifest.txt"; then
  _no "1-arg write_manifest wrongly included plasma-desktop (2nd param should default to no)"
else
  _ok "1-arg write_manifest omits plasma-desktop (backward-compatible default)"
fi
write_manifest no yes >/dev/null 2>&1
if grep -qxF 'plasma-desktop' "$ARCHFRICAN_STATE_DIR/manifest.txt" && grep -qxF 'dolphin' "$ARCHFRICAN_STATE_DIR/manifest.txt"; then
  _ok "write_manifest no yes includes plasma-desktop's packages in manifest.txt"
else
  _no "write_manifest no yes did NOT include plasma-desktop's packages"
fi

# ---- 4. prune_candidates: comm must run under LC_ALL=C, not just its inputs -----------------------
# Fixture proven to actually flip order between C (byte value: 'Z' < 'a') and en_US.UTF-8 (case-folded:
# 'a' < 'Z') collation — under the bug this makes comm misparse the stream and WRONGLY include "apple"
# (a package that's still desired) as a prune candidate, i.e. a false candidate for removal.
printf 'Alpha\napple\n' > "$ARCHFRICAN_STATE_DIR/manifest.txt"              # desired: keep both
printf 'Alpha\napple\nZebra\nzebra-utils\n' > "$ARCHFRICAN_STATE_DIR/managed.txt"  # ever-managed: + 2 true orphans
pacman(){
  case "$1" in
    -Qeq) printf 'Zebra\napple\nAlpha\nzebra-utils\n' ;;                    # explicitly installed: all four
    -Qi)  printf 'Required By     : None\n' ;;                            # nothing depends on any of them
  esac
}
export LANG=en_US.UTF-8 LC_ALL=  # simulate the real machine's ambient (non-C) locale
mapfile -t cand < <(prune_candidates 2>/tmp/prune-stderr.$$)
sorted_cand="$(printf '%s\n' "${cand[@]:-}" | LC_ALL=C sort)"
if [ "$sorted_cand" = "$(printf 'Zebra\nzebra-utils')" ]; then
  _ok "prune_candidates returns exactly the true orphans (Zebra, zebra-utils) under a non-C locale"
else
  _no "prune_candidates returned wrong candidates under a non-C locale: [${cand[*]:-<empty>}]"
fi
if grep -qi 'not in sorted order' /tmp/prune-stderr.$$ 2>/dev/null; then
  _no "comm emitted a 'not in sorted order' warning — LC_ALL=C is missing on the comm call"
else
  _ok "no 'not in sorted order' warning from comm"
fi
rm -f "/tmp/prune-stderr.$$"

rm -rf "$WORK"
printf '\nmanifest unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
