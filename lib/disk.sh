#!/usr/bin/env bash
# Disk selection for the ISO full install (Stage 2). READ-ONLY by construction:
# nothing here writes to a disk. pick_disk only *lists* devices (lsblk) and
# confirm_wipe only *gates* on typed confirmation. The actual format happens
# later, inside archinstall, and only when lib/phase1.sh is armed. Sourced after
# lib/common.sh + lib/ui.sh.

# Human-readable size from bytes — no external `numfmt` (not on the Arch ISO).
_hsize() {                          # _hsize <bytes>
  awk -v b="$1" 'BEGIN{
    split("B K M G T P", u, " "); s=b+0; i=1;
    while (s>=1024 && i<6){ s/=1024; i++ }
    printf (i==1 ? "%d%s" : "%.1f%s"), s, u[i]
  }'
}

# List candidate install disks (type=disk; skips ROM/loop/partitions). Emits one
# line per disk:  <name>\t<size-bytes>\t<model>
list_disks() {
  lsblk -dn -b -o NAME,SIZE,TYPE,MODEL 2>/dev/null | awk '$3=="disk"{
    name=$1; size=$2; $1=$2=$3=""; sub(/^[ \t]+/,""); model=$0;
    print name "\t" size "\t" (model=="" ? "(unknown model)" : model)
  }'
}

# pick_disk -> echoes the chosen /dev/NAME to stdout (all prompts go to stderr,
# so `d="$(pick_disk)"` stays clean). Dies if no installable disk exists.
pick_disk() {
  local name size model labels=()
  while IFS=$'\t' read -r name size model; do
    labels+=("$(printf '/dev/%s  (%s, %s)' "$name" "$(_hsize "$size")" "$model")")
  done < <(list_disks)
  [ "${#labels[@]}" -gt 0 ] || die "no installable disk found (lsblk saw no type=disk device)"

  ui_header "Select the install disk"
  ui_note "EVERYTHING on the chosen disk will be erased."
  local choice; choice="$(ui_choose 'Install disk' "${labels[@]}")"
  printf '%s' "${choice%% *}"       # the label's first token is exactly /dev/NAME
}

# confirm_wipe <dev> -> rc 0 only if the user retypes the bare device name.
# The second, independent destructive gate (the first is ARCHFRICAN_ISO_ARMED).
confirm_wipe() {                    # confirm_wipe /dev/sdX
  local dev="$1" bare typed
  bare="${dev#/dev/}"
  # Automated VM testing (tests/e2e): the non-interactive analogue of typing the device name. Bypasses the
  # prompt ONLY when autopilot is on AND the operator echoed the EXACT device — so it can never fire from the
  # normal wizard on a real machine. (A wipe still also needs ARCHFRICAN_ISO_ARMED=1 + ARCHFRICAN_ISO_GO=1.)
  if [ "${ARCHFRICAN_AUTOPILOT:-0}" = 1 ]; then
    [ "${ARCHFRICAN_AUTOPILOT_CONFIRM_WIPE:-}" = "$dev" ] && return 0
    die "autopilot: refusing to wipe $dev — set ARCHFRICAN_AUTOPILOT_CONFIRM_WIPE=$dev to confirm"
  fi
  ui_header "Confirm disk erase"
  ui_note "About to ERASE and repartition $dev — this is not reversible."
  if [ "${UI_BACKEND:-plain}" = gum ]; then
    typed="$(gum input --prompt "type '$bare' to confirm: ")"
  else
    read -rp "type '$bare' to confirm: " typed </dev/tty >&2 || true
  fi
  [ "$typed" = "$bare" ] || { warn "confirmation text did not match — aborting (nothing was erased)"; return 1; }
  return 0
}
