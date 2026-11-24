#!/usr/bin/env bash
# Shared helper: splice per-GPU niri workarounds (sidecar ~/.config/archfrican/gpu-niri.kdl) into
# ~/.config/niri/config.kdl between managed markers, with validate-or-revert safety.
#
# Why a separate helper (sourced by BOTH modules/10-gpu.sh and home/run_after_99-apply-theme.sh.tmpl):
#   • On a fresh install, 10-gpu runs BEFORE chezmoi writes config.kdl — it writes the sidecar and
#     calls splice_niri_gpu_block (a safe no-op while config.kdl is absent); run_after_99 then
#     splices the sidecar into the freshly-rendered config.kdl.
#   • On `archfrican-update --converge`, chezmoi overwrites config.kdl from config.kdl.tmpl and
#     run_after_99 immediately re-splices the sidecar so the GPU workarounds survive every update.
#   • On a direct `./install.sh 10-gpu`, config.kdl already exists, so 10-gpu splices it live.
#
# Non-nouveau GPUs (AMD/Intel/VM/NVIDIA proprietary) leave the sidecar absent: splicing clears the
# managed region back to empty markers, so switching GPUs never leaves stale debug workarounds.

splice_niri_gpu_block() {         # splice_niri_gpu_block [config.kdl] [sidecar.kdl]
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local kdl="${1:-$cfg/niri/config.kdl}"
  local side="${2:-$cfg/archfrican/gpu-niri.kdl}"
  local bak="${kdl}.archfrican-gpu.bak"
  local start="// ARCHFRICAN-GPU-START (managed by 10-gpu)"
  local end="// ARCHFRICAN-GPU-END"

  [ -f "$kdl" ] || return 0       # fresh install before chezmoi: run_after_99 will splice later

  local block tmp
  block="$(mktemp)"
  tmp="$(mktemp)"

  if [ -s "$side" ]; then
    { printf '%s\n' "$start"; cat "$side"; printf '%s\n' "$end"; } > "$block"
  else
    printf '%s\n%s\n' "$start" "$end" > "$block"
  fi

  cp -f "$kdl" "$bak"
  if grep -qF 'ARCHFRICAN-GPU-START' "$kdl" && grep -qF 'ARCHFRICAN-GPU-END' "$kdl"; then
    # Same balance-guard as theme-switch and archfrican-displays: unbalanced markers exit 1 and
    # leave config.kdl untouched instead of truncating the file.
    if ! awk 'NR==FNR{blk=blk $0 ORS; next}
              /ARCHFRICAN-GPU-START/{printf "%s", blk; skip=1; next}
              /ARCHFRICAN-GPU-END/{skip=0; next}
              !skip{print}
              END{ exit (skip ? 1 : 0) }' "$block" "$kdl" > "$tmp"; then
      rm -f "$block" "$tmp"
      return 1
    fi
  elif [ -s "$side" ]; then
    { cat "$kdl"; printf '\n'; cat "$block"; } > "$tmp"
  else
    # No markers and nothing to inject: keep config.kdl untouched.
    rm -f "$block" "$tmp" "$bak"
    return 0
  fi

  mv -f "$tmp" "$kdl"
  rm -f "$block"

  # Verify-or-revert: a malformed KDL block would make niri fall back to stock defaults.
  if command -v niri >/dev/null 2>&1 && ! niri validate -c "$kdl" >/dev/null 2>&1; then
    cp -f "$bak" "$kdl"
    return 1
  fi
  return 0
}
