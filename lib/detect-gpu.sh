#!/usr/bin/env bash
# GPU auto-detection. Echoes one of: nvidia | amd | intel | hybrid-intel-nvidia
#   | hybrid-amd-nvidia | hybrid-amd-intel | unknown
# This is the ONLY place that knows about GPU vendors. Everything else is generic.
# Failure-tolerant: a missing lspci or a no-match must resolve to "unknown",
# never abort the caller (it runs under `set -euo pipefail`).
detect_gpu() {
  command -v lspci >/dev/null 2>&1 || { echo "unknown"; return 0; }
  local vga
  vga="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
  local has_nvidia=0 has_amd=0 has_intel=0
  grep -qi nvidia        <<<"$vga" && has_nvidia=1
  grep -qiE 'amd|ati'    <<<"$vga" && has_amd=1
  grep -qi intel         <<<"$vga" && has_intel=1

  if   [ $has_nvidia -eq 1 ] && [ $has_intel -eq 1 ]; then echo "hybrid-intel-nvidia"
  elif [ $has_nvidia -eq 1 ] && [ $has_amd   -eq 1 ]; then echo "hybrid-amd-nvidia"
  elif [ $has_amd    -eq 1 ] && [ $has_intel -eq 1 ]; then echo "hybrid-amd-intel"
  elif [ $has_nvidia -eq 1 ]; then echo "nvidia"
  elif [ $has_amd    -eq 1 ]; then echo "amd"
  elif [ $has_intel  -eq 1 ]; then echo "intel"
  else echo "unknown"; fi
}
