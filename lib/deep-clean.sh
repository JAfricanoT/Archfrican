#!/usr/bin/env bash
# Deep clean (factory reset preserving /home) — Fase 0: dry-run scaffolding. The full
# wipe/pacstrap/chroot-config/atomic-swap sequence lives here already, but every destructive
# step goes through dc_run()/dc_run_pipe()/dc_probe(), so NOTHING real happens unless armed.
# Nothing in this file is sourced by install.sh yet, nor reachable from any menu or trigger —
# that wiring is later phases' job (Fase 1 connects a real entrypoint; Fase 5 adds an
# attestation gate). Sourced after lib/common.sh (uses die/warn/substep from there).
#
# ┌─ SAFETY ────────────────────────────────────────────────────────────────────┐
# │ Every destructive op goes through dc_run()/dc_run_pipe(), which PRINT the     │
# │ exact command and execute NOTHING unless DC_GO=1. DC_GO=1 is set only when    │
# │ ARCHFRICAN_DEEPCLEAN_ARMED=1 (see run_deep_clean). Arming is a RUNTIME         │
# │ opt-in — set the env var; never committed as 1. No env ⇒ dry-run.             │
# │                                                                                │
# │ Deliberately NAMESPACED away from lib/base-install.sh's run()/run_pipe()/     │
# │ probe()/AF_GO: once a later phase wires this file into install.sh's           │
# │ helper-loading block, it will share a shell with every other lib/*.sh file    │
# │ install.sh sources — so reusing those generic names would mean an ISO         │
# │ install's AF_GO=1 (armed via ARCHFRICAN_ISO_ARMED)                            │
# │ would ALSO arm deep-clean's destructive subvolume ops — two independent       │
# │ gates would silently collapse into one. dc_run/dc_run_pipe/dc_probe/DC_GO/    │
# │ ARCHFRICAN_DEEPCLEAN_ARMED share no name with base-install.sh's equivalents,  │
# │ by design — not an oversight to "clean up" later.                            │
# │                                                                                │
# │ Deep-clean only ever operates at the btrfs-subvolume level on a filesystem    │
# │ that ALREADY exists — it must never call a full-disk reformat verb. CI's      │
# │ deepclean-safety-gate job greps this file for those verbs.                   │
# └──────────────────────────────────────────────────────────────────────────────┘

# Defaults to 0; env-overridable so a real deep-clean needs NO file edit (CI asserts the safe
# default — see .github/workflows/ci.yml deepclean-safety-gate).
# shellcheck disable=SC2034
ARCHFRICAN_DEEPCLEAN_ARMED="${ARCHFRICAN_DEEPCLEAN_ARMED:-0}"
DC_GO=0   # 1 = execute destructive ops; 0 = print only (dry-run)

# ---- dry-run wrappers (namespaced — see SAFETY box above) --------------------
dc_run() {            # dc_run <argv…>  — a single command that MUST succeed
  if [ "$DC_GO" = 1 ]; then substep "$*"; "$@"
  else printf '  \e[2m[dry-run]\e[0m %s\n' "$(printf '%q ' "$@")" >&2; fi
}
dc_run_pipe() {       # dc_run_pipe '<pipeline>' — pipes/redirs/|| true (single string)
  if [ "$DC_GO" = 1 ]; then substep "$1"; bash -c "set -euo pipefail; $1"
  else printf '  \e[2m[dry-run]\e[0m %s\n' "$1" >&2; fi
}
dc_probe() {          # dc_probe '<placeholder>' <real-cmd…> — placeholder in dry-run, real output armed
  if [ "$DC_GO" = 1 ]; then shift; "$@"; else printf '%s' "$1"; fi
}

# ---- fixed allowlist -----------------------------------------------------------
# ALWAYS a literal, NEVER computed from a live `btrfs subvolume list` or any other runtime
# enumeration. @home must NEVER appear here. dc_guard_allowlist (below) is the second,
# independent layer of defense — both layers are intentional, not redundant.
DEEPCLEAN_DELETE_SUBVOLS=(@ @log @pkg @.snapshots)

dc_guard_allowlist() {   # defense in depth: die if @home ever sneaks into the fixed list
  local sv
  for sv in "${DEEPCLEAN_DELETE_SUBVOLS[@]}"; do
    [ "$sv" = "@home" ] && die "SAFETY: @home appeared in DEEPCLEAN_DELETE_SUBVOLS — refusing to run deep-clean"
  done
  return 0
}

# ---- working paths (Fase 1 will point these at the real managed layout) ------
DC_ROOT_MNT="${DC_ROOT_MNT:-/mnt/deepclean}"       # top-level (subvol-less) mount of the existing btrfs fs
DC_NEW_MNT="${DC_NEW_MNT:-/mnt/deepclean-new}"     # @.new, mounted for pacstrap + chroot
DC_ROOT_DEV="${DC_ROOT_DEV:-}"                     # set by real layout detection in Fase 1; empty in Fase 0

# ---- steps ---------------------------------------------------------------------
dc_stale_guard() {   # a prior aborted run can leave mounts busy -> release, tolerantly (like base_stale_guard)
  dc_run_pipe "umount -R $DC_NEW_MNT 2>/dev/null || true"
  dc_run_pipe "umount -R $DC_ROOT_MNT 2>/dev/null || true"
  dc_run udevadm settle   # let the unmounts settle before touching subvolumes
}

dc_detect_managed_layout() {   # Fase 0: READ-ONLY placeholder (dc_probe); Fase 1 parses the real layout
  dc_probe '<managed-layout: @ @home @log @pkg @.snapshots>' btrfs subvolume list "$DC_ROOT_MNT"
}

dc_wipe_subvolumes() {   # delete only what's in the fixed allowlist — never @home
  dc_guard_allowlist    # defense in depth: re-checked here, not just once at run_deep_clean's top
  local sv
  for sv in "${DEEPCLEAN_DELETE_SUBVOLS[@]}"; do
    dc_run btrfs subvolume delete "$DC_ROOT_MNT/$sv"
  done
}

dc_pacstrap_new() {   # build the replacement system in a fresh @.new — NEVER touches @ directly
  dc_run btrfs subvolume create "$DC_ROOT_MNT/@.new"
  dc_run mkdir -p "$DC_NEW_MNT"
  dc_run mount -o subvol=@.new "$DC_ROOT_DEV" "$DC_NEW_MNT"
  # Same AF_BEDROCK_PKGS (lib/common.sh) as base_pacstrap — the rebuilt base can't drift from a
  # fresh install's. Fase 1 must also mirror its conditional extras (cryptsetup via the encrypt
  # probe, cpu_ucode()) when it wires the real chroot config.
  dc_run pacstrap -K "$DC_NEW_MNT" "${AF_BEDROCK_PKGS[@]}"
}

dc_chroot_config_new() {   # arch-chroot into @.new to configure the replacement system
  dc_run_pipe "genfstab -U $DC_NEW_MNT >> $DC_NEW_MNT/etc/fstab"
  # Fase 1 supplies the real chroot config script (locale/user/GRUB/initramfs, mirroring
  # lib/base-install.sh's _chroot_script); Fase 0 only proves the entrypoint is dry-run-safe.
  dc_run arch-chroot "$DC_NEW_MNT" true
}

dc_atomic_swap() {   # @ -> @.old, @.new -> @, delete @.old — the LAST op, minimal-window rename
  dc_run mv "$DC_ROOT_MNT/@" "$DC_ROOT_MNT/@.old"
  dc_run mv "$DC_ROOT_MNT/@.new" "$DC_ROOT_MNT/@"
  dc_run btrfs subvolume delete "$DC_ROOT_MNT/@.old"
}

# Orchestrator. Fase 0: wired end-to-end but dry-run by default — see the SAFETY box up top.
run_deep_clean() {
  dc_guard_allowlist
  if [ "$ARCHFRICAN_DEEPCLEAN_ARMED" = 1 ]; then DC_GO=1; fi
  dc_stale_guard
  dc_detect_managed_layout
  dc_wipe_subvolumes
  dc_pacstrap_new
  dc_chroot_config_new
  dc_atomic_swap
}
