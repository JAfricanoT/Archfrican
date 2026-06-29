#!/usr/bin/env bash
# Disk selection for the ISO full install (Stage 2). READ-ONLY by construction:
# nothing here writes to a disk. pick_disk only *lists* devices (lsblk) and
# confirm_wipe only *gates* on typed confirmation. The actual format happens later in
# lib/base-install.sh (the bedrock installer that replaced archinstall), and only when
# lib/phase1.sh is armed. Sourced after lib/common.sh + lib/ui.sh.

# Human-readable size from bytes — no external `numfmt` (not on the Arch ISO).
_hsize() {                          # _hsize <bytes>
  awk -v b="$1" 'BEGIN{
    split("B K M G T P", u, " "); s=b+0; i=1;
    while (s>=1024 && i<6){ s/=1024; i++ }
    printf (i==1 ? "%d%s" : "%.1f%s"), s, u[i]
  }'
}

# live_disk -> bare name of the disk we booted the installer from (empty when not on the ISO
# or undetectable). The install USB is NEVER a valid target while we're running from it, so it's
# dropped from the picker. confirm_wipe stays as the backstop. is_iso() comes from lib/env.sh.
live_disk() {
  is_iso || return 0
  local src parent
  # Guard EVERY substitution with `|| true`: on a copytoram / odd-layout boot `/run/archiso/bootmnt`
  # is not a mountpoint, so `findmnt` exits non-zero. Without the guard that failure can abort the
  # caller — and the whole disk list — under `set -e`, surfacing as a false "no installable disk found".
  src="$(findmnt -fno SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  if [ -n "$src" ]; then
    parent="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1 || true)"
    printf '%s' "${parent:-${src#/dev/}}"
    return 0
  fi
  # Fallback when bootmnt is not mounted: the disk that carries the iso9660 archiso filesystem.
  lsblk -rno PKNAME,FSTYPE 2>/dev/null | awk '$2=="iso9660"{print $1; exit}' || true
}

# List candidate install disks (type=disk; skips ROM/loop/partitions AND the live install medium).
# Emits one line per disk:  <name>\t<size-bytes>\t<model>
# `read -r NAME SIZE TYPE MODEL` keeps NAME/SIZE/TYPE as the first three tokens and lets a
# space-containing MODEL ("SK hynix BC511 …") fall into the last field — no fragile column math.
list_disks() {
  local live; live="$(live_disk)"
  local NAME SIZE TYPE MODEL
  while read -r NAME SIZE TYPE MODEL; do
    [ "$TYPE" = disk ] || continue
    { [ -n "$NAME" ] && [ "$NAME" != "$live" ]; } || continue
    printf '%s\t%s\t%s\n' "$NAME" "$SIZE" "${MODEL:-(unknown model)}"
  done < <(lsblk -dbno NAME,SIZE,TYPE,MODEL 2>/dev/null)
}

# pick_disk -> echoes the chosen /dev/NAME to stdout (all prompts go to stderr,
# so `d="$(pick_disk)"` stays clean). Dies if no installable disk exists.
pick_disk() {
  local name size model tran labels=()
  while IFS=$'\t' read -r name size model; do
    # transport (nvme/sata/usb) disambiguates similarly-sized disks on multi-disk machines.
    tran="$(lsblk -dno TRAN "/dev/$name" 2>/dev/null | tr -d '[:space:]')"
    labels+=("$(printf '/dev/%s  (%s, %s%s)' "$name" "$(_hsize "$size")" "${tran:+$tran · }" "$model")")
  done < <(list_disks)
  if [ "${#labels[@]}" -eq 0 ]; then
    # Instrumented failure: dump exactly what lsblk reports, so an otherwise-unreproducible "no disk"
    # can be diagnosed from the error alone — which block devices exist, their TYPE/SIZE, and what we
    # excluded as the live USB. All to stderr (stdout must stay clean for `d="$(pick_disk)"`).
    { echo "  [disk-detect] is_iso=$(is_iso && echo yes || echo no)  live_disk(excluded)=[$(live_disk)]"
      echo "  [disk-detect] lsblk -dno NAME,TYPE,SIZE,TRAN,MODEL:"
      lsblk -dno NAME,TYPE,SIZE,TRAN,MODEL 2>&1 | sed 's/^/    /' || true
    } >&2
    die "no installable disk found (lsblk saw no type=disk device) — diagnostics above"
  fi

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
