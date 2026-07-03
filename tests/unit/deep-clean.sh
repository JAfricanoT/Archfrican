#!/usr/bin/env bash
# Unit test for lib/deep-clean.sh (Fase 0 dry-run scaffolding). Fixture-based — mocks every
# external command deep-clean would ever invoke, so it needs NO real disk/btrfs and runs in CI.
# Guards the 4 invariants Fase 0 exists to protect:
#   1. DEEPCLEAN_DELETE_SUBVOLS is a fixed literal — never derived from a live
#      `btrfs subvolume list`, no matter what that command returns.
#   2. dc_guard_allowlist dies if @home ever appears in the delete list (defense in depth).
#   3. With ARCHFRICAN_DEEPCLEAN_ARMED at its default (0, same as unset — lib/deep-clean.sh's own
#      top-of-file `"${ARCHFRICAN_DEEPCLEAN_ARMED:-0}"` treats the two identically), run_deep_clean
#      touches NOTHING real. (We assert =0 rather than literally unsetting it: this test script
#      inherits `set -u` from lib/common.sh, and run_deep_clean references the var unguarded.)
#   4. ARCHFRICAN_DEEPCLEAN_ARMED=1 flips DC_GO to 1 inside run_deep_clean.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
export REPO_ROOT="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/deep-clean.sh"
set +e                              # we capture rc ourselves (common.sh's `set -e` would otherwise abort us)

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

# ---- shared mocks: every external command deep-clean's full chain can ever reach -----------------
# CNT increments if any of these is EVER really invoked. dc_run_pipe spawns its own `bash -c`, so
# the ones it can reach (umount, genfstab) must be exported for that child shell to see them too.
# btrfs additionally answers `subvolume list` with a hostile fixture for test 1 below: reordered,
# a lookalike @home2, and a subvol that should not exist — DEEPCLEAN_DELETE_SUBVOLS must ignore it.
CNT=0
_hit(){ CNT=$((CNT + 1)); }
BTRFS_LIST_OUTPUT=$'ID 257 gen 9 top level 5 path @home2\nID 260 gen 9 top level 5 path @unexpected\nID 256 gen 9 top level 5 path @\nID 259 gen 9 top level 5 path @.snapshots'
btrfs() {
  _hit
  case "$*" in
    *"subvolume list"*) printf '%s\n' "$BTRFS_LIST_OUTPUT" ;;
  esac
}
mount()       { _hit; }
umount()      { _hit; }
mkdir()       { _hit; }
pacstrap()    { _hit; }
genfstab()    { _hit; }
arch-chroot() { _hit; }
mv()          { _hit; }
udevadm()     { _hit; }
export -f _hit btrfs mount umount mkdir pacstrap genfstab arch-chroot mv udevadm

# ---- 1. the allowlist is ALWAYS the fixed literal, never derived from `btrfs subvolume list` ----
DC_GO=1                             # arm dc_probe so it actually calls the (mocked) btrfs this once
CNT=0
dc_detect_managed_layout >/dev/null 2>&1
DC_GO=0
want='@ @log @pkg @.snapshots'
got="${DEEPCLEAN_DELETE_SUBVOLS[*]}"
if [ "$got" = "$want" ]; then _ok "DEEPCLEAN_DELETE_SUBVOLS stays fixed regardless of a hostile btrfs mock"
else _no "allowlist was derived/mutated (want '$want', got '$got')"; fi

# ---- 2. dc_guard_allowlist dies if @home appears in the list -------------------------------------
out="$( DEEPCLEAN_DELETE_SUBVOLS=(@ @home); dc_guard_allowlist )"; rc=$?
if [ "$rc" -ne 0 ]; then _ok "dc_guard_allowlist dies (rc=$rc) when @home is in DEEPCLEAN_DELETE_SUBVOLS"
else _no "dc_guard_allowlist did NOT die with @home present (rc=$rc out='$out')"; fi

out="$( dc_guard_allowlist )"; rc=$?
if [ "$rc" -eq 0 ]; then _ok "dc_guard_allowlist passes on the real fixed allowlist"
else _no "dc_guard_allowlist unexpectedly died on the real allowlist (rc=$rc)"; fi

# ---- 3. dry-run by default (ARCHFRICAN_DEEPCLEAN_ARMED=0) executes NOTHING real ------------------
ARCHFRICAN_DEEPCLEAN_ARMED=0
DC_GO=0
CNT=0
run_deep_clean >/dev/null 2>&1
if [ "$CNT" -eq 0 ]; then _ok "run_deep_clean (unarmed) called zero real commands"
else _no "run_deep_clean (unarmed) invoked $CNT real command(s) — dry-run leaked"; fi

# ---- 4. ARCHFRICAN_DEEPCLEAN_ARMED=1 flips DC_GO to 1 inside run_deep_clean ------------------------
# dc_chroot_config_new's genfstab step is `dc_run_pipe "genfstab -U $DC_NEW_MNT >> .../fstab"` — the
# `>>` is a shell-level redirect baked into dc_run_pipe's string arg, resolved by dc_run_pipe's own
# `bash -c` BEFORE genfstab (mocked above) ever runs, so the mock can't intercept it: this is real,
# unmockable filesystem I/O against whatever DC_NEW_MNT points at. Retarget DC_NEW_MNT/DC_ROOT_MNT at
# a throwaway scratch dir (etc/ pre-created, since genfstab's append needs it to exist) instead of the
# real-looking default /mnt/deepclean* paths, so this step lands somewhere harmless either way.
# `command mkdir` bypasses the mkdir() mock above (a plain shell function in THIS shell too) so the
# scratch dir is actually created for real.
scratch="$(mktemp -d)"
command mkdir -p "$scratch/etc"
# shellcheck disable=SC2034  # read by dc_* steps in the sourced (source=/dev/null) lib/deep-clean.sh
DC_NEW_MNT="$scratch"
# shellcheck disable=SC2034  # read by dc_* steps in the sourced (source=/dev/null) lib/deep-clean.sh
DC_ROOT_MNT="$scratch"
# shellcheck disable=SC2034  # read by run_deep_clean in the sourced (source=/dev/null) lib/deep-clean.sh
ARCHFRICAN_DEEPCLEAN_ARMED=1
DC_GO=0
run_deep_clean >/dev/null 2>&1
if [ "$DC_GO" -eq 1 ]; then _ok "ARCHFRICAN_DEEPCLEAN_ARMED=1 flips DC_GO to 1 inside run_deep_clean"
else _no "DC_GO did not flip to 1 when ARCHFRICAN_DEEPCLEAN_ARMED=1 (DC_GO=$DC_GO)"; fi
rm -rf -- "$scratch"

printf '\ndeep-clean unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
