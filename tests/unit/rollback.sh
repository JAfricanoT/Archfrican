#!/usr/bin/env bash
# Unit test for lib/rollback.sh — the Btrfs rollback that ACTUALLY restores on Archfrican's layout.
#
# The bug this pins down: `snapper rollback` restores by flipping the filesystem's DEFAULT SUBVOLUME
# (btrfs subvolume set-default). Archfrican's base install pins the root subvolume BY PATH in two
# places — lib/base-install.sh writes `rootflags=subvol=@` into the kernel cmdline (line 147) and
# genfstab writes `subvol=/@` into /etc/fstab (line 240). A pinned mount resolves the path at boot
# and never consults the default subvolume, so `snapper rollback` reported success and the machine
# rebooted straight back into the same broken @. Silent, and discovered only when someone actually
# needed it.
#
# On such a layout the only thing that restores is a PATH SWAP: rename the live root subvolume aside
# and recreate it as a writable snapshot of the target. That is what these tests specify.
#
# Fixture-based: PATH stubs for `sudo` (which fronts every privileged call) and `findmnt`, plus
# ARCHFRICAN_PROC_CMDLINE/ARCHFRICAN_FSTAB pointing at fixture files. No disks, no root, runs in CI.
#
# Invariants under test:
#   1. root_subvol_pinned is true when the kernel cmdline pins the root subvolume by path.
#   2. root_subvol_pinned is true when /etc/fstab pins it, even with a clean cmdline.
#   3. root_subvol_pinned is FALSE when neither pins it — and is not fooled by findmnt, which always
#      reports a resolved `subvol=` whether or not anyone asked for one (the trap that makes the
#      obvious implementation wrong).
#   4. On a pinned layout, rolling back performs the swap and never calls `snapper rollback`.
#   5. On an unpinned layout, rolling back defers to `snapper rollback` (set-default works there).
#   6. The old root is RENAMED, never deleted — the rollback stays reversible.
#   7. If the snapshot step fails after the rename, the old root is renamed BACK. Anything else
#      leaves the machine with no root subvolume at `@` — an unbootable brick.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

# ---- fixtures --------------------------------------------------------------
# stub_dir — a PATH dir with `sudo` and `findmnt`.
#
# `sudo` fronts every privileged call the lib makes, so one stub records the whole transcript into
# $CALLS *and* simulates the filesystem effects, letting the lib's own existence checks run for real:
#   mount   -> lays down the top-level tree (@, @.snapshots/42/snapshot) under the mountpoint
#   mv      -> really renames, so "did the old root survive?" is observable
#   btrfs subvolume snapshot -> really creates the destination, unless STUB_SNAPSHOT_RC says it fails
#
# `findmnt` reports what a real Btrfs root reports — including the `subvol=` that btrfs adds to the
# mount options unconditionally. Invariant 3 depends on that being present.
stub_dir(){
  local d; d="$(mktemp -d)"
  cat > "$d/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
cmd="$1"; shift
case "$cmd" in
  mount)
    for a in "$@"; do mp="$a"; done
    mkdir -p "$mp/@" "$mp/@.snapshots/42/snapshot" || exit 1
    exit 0 ;;
  umount) exit 0 ;;
  mv)     exec mv "$@" ;;
  btrfs)
    case "$*" in
      "subvolume snapshot "*)
        [ "${STUB_SNAPSHOT_RC:-0}" = 0 ] || exit "${STUB_SNAPSHOT_RC}"
        for a in "$@"; do dest="$a"; done
        mkdir -p "$dest" || exit 1
        exit 0 ;;
    esac
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
  cat > "$d/findmnt" <<'EOF'
#!/bin/sh
for a in "$@"; do target="$a"; done
case "$*" in
  *SOURCE*) printf '/dev/mapper/root[/@]\n' ;;
  *OPTIONS*)
    case "$target" in
      /.snapshots) printf 'rw,noatime,compress=zstd:3,subvolid=259,subvol=/@.snapshots\n' ;;
      *)           printf 'rw,noatime,compress=zstd:3,subvolid=256,subvol=/@\n' ;;
    esac ;;
esac
exit 0
EOF
  chmod +x "$d/sudo" "$d/findmnt"
  printf '%s' "$d"
}

# fixture_dir <cmdline> <fstab-root-options> — files for the two pin sites.
fixture_dir(){
  local d; d="$(mktemp -d)"
  printf '%s\n' "$1" > "$d/cmdline"
  printf 'UUID=dead-beef\t/\tbtrfs\t%s\t0 0\n' "$2" > "$d/fstab"
  printf '%s' "$d"
}

PINNED_CMDLINE='BOOT_IMAGE=/vmlinuz-linux-lts root=/dev/mapper/root rw rootflags=subvol=@ quiet'
CLEAN_CMDLINE='BOOT_IMAGE=/vmlinuz-linux-lts root=/dev/mapper/root rw quiet'

# ---- 1, 2 & 3: the pin detector -------------------------------------------
assert_pinned(){   # assert_pinned <cmdline> <fstab-opts> <yes|no> <desc>
  local cl="$1" fo="$2" want="$3" desc="$4" s f got
  s="$(stub_dir)"; f="$(fixture_dir "$cl" "$fo")"
  got="$(PATH="$s:$PATH" ARCHFRICAN_PROC_CMDLINE="$f/cmdline" ARCHFRICAN_FSTAB="$f/fstab" \
    bash -c 'source "$1/lib/rollback.sh"; set +e; if root_subvol_pinned; then echo yes; else echo no; fi' \
    _ "$ROOT" 2>/dev/null)"
  [ "$got" = "$want" ] && _ok "$desc" || _no "$desc (want $want, got '${got:-<none>}')"
  rm -rf "$s" "$f"
}
assert_pinned "$PINNED_CMDLINE" 'rw,noatime,subvol=/@' yes \
  "pinned: cmdline rootflags=subvol=@ -> true"
assert_pinned "$CLEAN_CMDLINE"  'rw,noatime,subvol=/@' yes \
  "pinned: fstab subvol=/@ alone -> true"
assert_pinned "$CLEAN_CMDLINE"  'rw,noatime,compress=zstd:3' no \
  "unpinned: neither pin site -> false (findmnt's own subvol= must not fool it)"

# ---- 4 through 7: the rollback itself --------------------------------------
# run_rollback <cmdline> <fstab-opts> <snapshot-rc> -> prints "<rc>" and leaves $CALLS/$TOP populated
CALLS=""; TOP=""
run_rollback(){    # run_rollback <cmdline> <fstab-opts> <snapshot-rc>; sets CALLS, TOP, RC
  local s f; s="$(stub_dir)"; f="$(fixture_dir "$1" "$2")"
  CALLS="$f/calls"; TOP="$f/top"; : > "$CALLS"
  mkdir -p "$TOP"
  PATH="$s:$PATH" CALLS="$CALLS" STUB_SNAPSHOT_RC="$3" \
    ARCHFRICAN_PROC_CMDLINE="$f/cmdline" ARCHFRICAN_FSTAB="$f/fstab" ARCHFRICAN_ROLLBACK_TOP="$TOP" \
    bash -c 'source "$1/lib/rollback.sh"; set +e; archfrican_rollback_to 42' _ "$ROOT" >/dev/null 2>&1
  RC=$?
  STUBDIR="$s"; FIXDIR="$f"
}

# 4 — pinned layout swaps, and must NOT lean on snapper rollback
run_rollback "$PINNED_CMDLINE" 'rw,noatime,subvol=/@' 0
if grep -q 'snapper .*rollback' "$CALLS"; then
  _no "pinned: does not call 'snapper rollback' (it is a no-op on this layout)"
else
  _ok "pinned: does not call 'snapper rollback' (it is a no-op on this layout)"
fi
if grep -q 'btrfs subvolume snapshot .*@.snapshots/42/snapshot .*/@$' "$CALLS"; then
  _ok "pinned: recreates @ as a writable snapshot of the target"
else
  _no "pinned: recreates @ as a writable snapshot of the target"
fi
[ "$RC" -eq 0 ] && _ok "pinned: reports success" || _no "pinned: reports success (rc $RC)"

# 6 — the old root is renamed aside, never deleted
if grep -qE 'btrfs subvolume delete' "$CALLS"; then
  _no "pinned: never deletes the old root (rollback stays reversible)"
elif compgen -G "$TOP/@.rollback-*" >/dev/null; then
  _ok "pinned: never deletes the old root (rollback stays reversible)"
else
  _no "pinned: never deletes the old root (rollback stays reversible) — no @.rollback-* found"
fi
rm -rf "$STUBDIR" "$FIXDIR"

# 5 — unpinned layout defers to snapper, which works there
run_rollback "$CLEAN_CMDLINE" 'rw,noatime,compress=zstd:3' 0
if grep -q 'snapper .*rollback 42' "$CALLS"; then
  _ok "unpinned: defers to 'snapper rollback 42'"
else
  _no "unpinned: defers to 'snapper rollback 42'"
fi
if grep -q 'btrfs subvolume snapshot' "$CALLS"; then
  _no "unpinned: does not swap subvolumes behind snapper's back"
else
  _ok "unpinned: does not swap subvolumes behind snapper's back"
fi
rm -rf "$STUBDIR" "$FIXDIR"

# 7 — the brick guard: snapshot fails after the rename, so @ must come back
run_rollback "$PINNED_CMDLINE" 'rw,noatime,subvol=/@' 1
if [ -d "$TOP/@" ]; then
  _ok "snapshot failure: the old root is restored to @ (machine still boots)"
else
  _no "snapshot failure: the old root is restored to @ (machine still boots) — @ is GONE"
fi
if compgen -G "$TOP/@.rollback-*" >/dev/null; then
  _no "snapshot failure: no orphaned @.rollback-* left behind"
else
  _ok "snapshot failure: no orphaned @.rollback-* left behind"
fi
[ "$RC" -ne 0 ] && _ok "snapshot failure: reports failure" || _no "snapshot failure: reports failure (rc 0)"
rm -rf "$STUBDIR" "$FIXDIR"

# ---- 8: the leftovers nobody prunes ---------------------------------------
# archfrican_rollback_to renames the replaced root to @.rollback-<timestamp> instead of deleting it,
# so a bad rollback is itself reversible. Nothing ever cleans those up and each pins a full root's
# worth of COW blocks, so `archfrican-doctor` has to be the thing that notices. It must NEVER delete
# one — that copy is the user's way back — and must never report health it could not actually probe.
health_stub(){    # health_stub <fstype> <subvolume-list-output|SUDOFAIL>
  local d; d="$(mktemp -d)"
  printf '#!/bin/sh\necho %s\n' "$1" > "$d/findmnt"
  if [ "$2" = SUDOFAIL ]; then
    printf '#!/bin/sh\nexit 1\n' > "$d/sudo"
  else
    { printf '#!/bin/sh\ncat <<'\''SVL'\''\n'; printf '%s\n' "$2"; printf 'SVL\n'; } > "$d/sudo"
  fi
  chmod +x "$d/findmnt" "$d/sudo"
  printf '%s' "$d"
}
assert_check(){   # assert_check <fstype> <list|SUDOFAIL> <ok|amber|skip> <desc>
  local d out want="$3" desc="$4" got
  d="$(health_stub "$1" "$2")"
  out="$(PATH="$d:$PATH" bash -c \
    'source "$1/lib/health.sh"; set +e; check_rollback_backups; echo "AMBER=$H_AMBER RED=$H_RED"' \
    _ "$ROOT" 2>/dev/null)"
  case "$out" in
    *"RED=1"*)                     got=red ;;
    *"AMBER=1"*)                   got=amber ;;
    *"○ "*)                        got=skip ;;
    *"rollback backups"*)          got=ok ;;
    *)                             got="none:${out}" ;;
  esac
  [ "$got" = "$want" ] && _ok "$desc" || _no "$desc (want $want, got '$got')"
  rm -rf "$d"
}
ONE='ID 260 gen 1 top level 5 path @.rollback-20260908-140233'
THREE="$ONE
ID 261 gen 2 top level 5 path @.rollback-20260901-091500
ID 262 gen 3 top level 5 path @.rollback-20260825-183000"
CLEAN='ID 256 gen 1 top level 5 path @
ID 257 gen 1 top level 5 path @home'

assert_check btrfs "$CLEAN"   ok    "doctor: no @.rollback-* -> green"
assert_check btrfs "$ONE"     ok    "doctor: one backup (a recent rollback) -> green, not a nag"
assert_check btrfs "$THREE"   amber "doctor: backups piling up -> amber"
assert_check btrfs SUDOFAIL   skip  "doctor: no sudo -> skip, never a green it could not verify"
assert_check ext4  "$CLEAN"   skip  "doctor: non-btrfs root -> skip"

d="$(health_stub btrfs "$THREE")"
if PATH="$d:$PATH" bash -c 'source "$1/lib/health.sh"; check_rollback_backups' _ "$ROOT" 2>&1 \
   | grep -qiE 'subvolume delete|rm -rf'; then
  _no "doctor: reports the leftovers without handing over a delete command it might run"
else
  _ok "doctor: reports the leftovers without handing over a delete command it might run"
fi
rm -rf "$d"

printf '\nrollback unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
