#!/usr/bin/env bash
# Unit test for the Btrfs capability gate (lib/common.sh::is_btrfs) and the rc-3 opt-out it drives in
# modules/50-snapshots.sh. Snapshots/rollback are a BTRFS feature, but phase 2 also runs on an
# ALREADY-BOOTED Arch whose root may be ext4/xfs. There every snapper call fails and the module's
# post-condition used to `die` — aborting the whole install at step 5, so security/gaming/virt/hygiene
# never ran. lib/preflight.sh classifies btrfs as an optional WARN-level feature (pf_warn, not
# pf_fatal), so no module may make it fatal: 50-snapshots must OPT OUT with rc 3 (run_module's "not
# selected", which deliberately does NOT stamp .done, so converting the root to Btrfs later re-runs it).
#
# Fixture-based: a stub `findmnt` on PATH dictates the reported root fstype, and a stub `sudo` exits 99
# while announcing itself — so "opted out BEFORE touching the system" is an assertion, not a hope.
# Needs no disks, no mounts, no root; runs in CI.
# Invariants under test:
#   1. is_btrfs is true ONLY for a btrfs fstype (ext4/xfs/unknown -> false).
#   2. A findmnt failure is false, never a fail-open "assume btrfs" (that resurrects the abort).
#   3. On a non-btrfs root, modules/50-snapshots.sh exits 3 without reaching a single sudo call.
#   4. On a btrfs root the gate does NOT fire — the module proceeds past it (rc != 3).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

# stub_path <fstype|FAIL> -> temp dir holding a fake `findmnt` (reports that fstype, or exits 1) and a
# fake `sudo` that refuses loudly. Prepended to PATH, it makes both the fs probe and "did we touch the
# system?" fully observable.
stub_path(){
  local fs="$1" d; d="$(mktemp -d)"
  if [ "$fs" = FAIL ]; then printf '#!/bin/sh\nexit 1\n' > "$d/findmnt"
  else printf '#!/bin/sh\necho %s\n' "$fs" > "$d/findmnt"; fi
  printf '#!/bin/sh\necho "STUB-SUDO-CALLED: $*" >&2\nexit 99\n' > "$d/sudo"
  chmod +x "$d/findmnt" "$d/sudo"
  printf '%s' "$d"
}

# ---- 1 & 2: the predicate --------------------------------------------------
assert_is_btrfs(){        # assert_is_btrfs <fstype|FAIL> <yes|no> <desc>
  local fs="$1" want="$2" desc="$3" d got
  d="$(stub_path "$fs")"
  got="$(PATH="$d:$PATH" bash -c \
    'source "$1/lib/common.sh"; set +e; if is_btrfs /; then echo yes; else echo no; fi' \
    _ "$ROOT" 2>/dev/null)"
  if [ "$got" = "$want" ]; then _ok "$desc"; else _no "$desc (want $want, got '${got:-<none>}')"; fi
  rm -rf "$d"
}
assert_is_btrfs btrfs yes "is_btrfs: btrfs root -> true"
assert_is_btrfs ext4  no  "is_btrfs: ext4 root -> false"
assert_is_btrfs xfs   no  "is_btrfs: xfs root -> false"
assert_is_btrfs FAIL  no  "is_btrfs: findmnt failure -> false (fails CLOSED, never assumes btrfs)"

# ---- 3 & 4: the module's opt-out -------------------------------------------
assert_module_rc(){       # assert_module_rc <fstype> <yes|no: expect rc 3> <desc>
  local fs="$1" want="$2" desc="$3" d out rc=0
  d="$(stub_path "$fs")"
  out="$(PATH="$d:$PATH" bash "$ROOT/modules/50-snapshots.sh" 2>&1)" || rc=$?
  if [ "$want" = yes ]; then
    if [ "$rc" != 3 ]; then _no "$desc (want rc 3, got rc $rc)"
    elif printf '%s' "$out" | grep -q 'STUB-SUDO-CALLED'; then
      _no "$desc (exited 3, but only AFTER calling sudo)"
    else _ok "$desc"; fi
  else
    if [ "$rc" != 3 ]; then _ok "$desc"; else _no "$desc (gate wrongly fired on a btrfs root)"; fi
  fi
  rm -rf "$d"
}
assert_module_rc ext4  yes "50-snapshots: ext4 root  -> rc 3 (opt out), no sudo reached"
assert_module_rc xfs   yes "50-snapshots: xfs root   -> rc 3 (opt out), no sudo reached"
assert_module_rc btrfs no  "50-snapshots: btrfs root -> gate does not fire"

printf '\nsnapshots-gate unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
