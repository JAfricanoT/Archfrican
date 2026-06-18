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
  grep -qE "GRUB_CMDLINE_LINUX_DEFAULT=\"([^\"]* )?${token//./\\.}( [^\"]*)?\"" "$GRUB_DEFAULT" \
    || die "append_grub_cmdline: failed to add '$token' to $GRUB_DEFAULT — edit by hand"
  GRUB_CHANGED=1
}

# Set KEY=VALUE (creating it, or uncommenting/overwriting an existing/commented line).
# Idempotent (write_system_file skips an identical file); verify-or-die.
set_grub_key() {                   # set_grub_key KEY VALUE
  local key="$1" val="$2" line out=() found=0
  local want="$key=$val" re="^[#[:space:]]*${key}="
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$found" = 0 ] && [[ "$line" =~ $re ]]; then
      found=1; out+=("$want")                            # replace/uncomment first match
    else
      out+=("$line")
    fi
  done < "$GRUB_DEFAULT"
  [ "$found" = 1 ] || out+=("$want")                     # absent -> append
  printf '%s\n' "${out[@]}" | write_system_file "$GRUB_DEFAULT" 0644
  grep -qxF "$want" "$GRUB_DEFAULT" \
    || die "set_grub_key: failed to set $key=$val in $GRUB_DEFAULT — edit by hand"
}
