#!/usr/bin/env bash
# Idempotent, verify-or-die edits to /etc/default/grub. Centralizes what used to be
# raw sed in modules/10-gpu.sh (the audit flagged it as fragile). Built on
# write_system_file, so the .archfrican.bak backup + skip-if-unchanged come for free.
# Sourced after lib/common.sh.
#
# GRUB_DEFAULT is overridable (tests/CI point it at a fixture). GRUB_CHANGED (set in
# append_grub_cmdline) is read by modules/10-gpu.sh to gate the initramfs/GRUB rebuild —
# a cross-file global, hence the file-scoped SC2034 waiver.
# shellcheck disable=SC2034
GRUB_DEFAULT="${GRUB_DEFAULT:-/etc/default/grub}"
GRUB_CHANGED=0

# Regenerate the on-disk GRUB menu — the ONE home for the mkconfig invocation (6 modules use
# it). timeout: os-prober (if installed via opt-in multi-boot) scans every disk/partition and
# can hang on a bad device — the 300 s cap turns that into a visible failure. Returns the raw
# exit code (124 = cap hit) so modules/55-multiboot.sh can distinguish a timeout from a real
# error; grub-mkconfig writes atomically, so the old menu survives a failed/killed run.
regen_grub() { timeout 300 sudo grub-mkconfig -o /boot/grub/grub.cfg; }

# Append a token to GRUB_CMDLINE_LINUX_DEFAULT (idempotent, word-boundary). The value
# MUST be present and double-quoted on one line, else die (the single-quoted/absent case
# the old nvidia sed also refused). Sets GRUB_CHANGED=1 only on a real edit.
append_grub_cmdline() {            # append_grub_cmdline TOKEN
  local token="$1" line value out=() found=0 hit=0
  local re='^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"[[:space:]]*$'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$found" = 0 ] && [[ "$line" =~ $re ]]; then
      found=1; value="${BASH_REMATCH[1]}"
      if [[ " $value " == *" $token "* ]]; then
        out+=("$line")                                   # already present -> unchanged
      else
        out+=("GRUB_CMDLINE_LINUX_DEFAULT=\"${value:+$value }$token\""); hit=1
      fi
    else
      out+=("$line")
    fi
  done < "$GRUB_DEFAULT"
  [ "$found" = 1 ] \
    || die "append_grub_cmdline: GRUB_CMDLINE_LINUX_DEFAULT not found or not double-quoted in $GRUB_DEFAULT — edit by hand"
  [ "$hit" = 1 ] || return 0                             # nothing to do, no write
  printf '%s\n' "${out[@]}" | write_system_file "$GRUB_DEFAULT" 0644
  # Verify by re-reading the written value + a fixed-string membership test (regex-metachar
  # safe, unlike a token-in-regex), so a failed write can't slip through.
  local check=""
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ $re ]] && { check="${BASH_REMATCH[1]}"; break; }
  done < "$GRUB_DEFAULT"
  [[ " $check " == *" $token "* ]] \
    || die "append_grub_cmdline: failed to add '$token' to $GRUB_DEFAULT — edit by hand"
  GRUB_CHANGED=1
}

# Set KEY=VALUE (creating it, or uncommenting/overwriting an existing/commented line).
# Idempotent (write_system_file skips an identical file); verify-or-die.
set_grub_key() {                   # set_grub_key KEY VALUE
  local key="$1" val="$2" line out=() found=0
  local want="$key=$val" re="^[#[:space:]]*${key}="
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $re ]]; then
      [ "$found" = 1 ] && continue                       # drop duplicate/commented assignments
      found=1; out+=("$want")                            # first match -> our canonical line
    else
      out+=("$line")
    fi
  done < "$GRUB_DEFAULT"
  [ "$found" = 1 ] || out+=("$want")                     # absent -> append
  # NB: collapsing ALL matches to ONE line is deliberate — GRUB sources the LAST assignment,
  # so leaving a later duplicate/stale value would silently win over ours.
  printf '%s\n' "${out[@]}" | write_system_file "$GRUB_DEFAULT" 0644
  grep -qxF "$want" "$GRUB_DEFAULT" \
    || die "set_grub_key: failed to set $key=$val in $GRUB_DEFAULT — edit by hand"
}
