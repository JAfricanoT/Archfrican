#!/usr/bin/env bash
# GPU auto-detection. Echoes one of: vm | nvidia | amd | intel | hybrid-intel-nvidia
#   | hybrid-amd-nvidia | hybrid-amd-intel | unknown
# This is the ONLY place that knows about GPU vendors. Everything else is generic.
# Failure-tolerant: a missing lspci or a no-match must resolve to a safe value,
# never abort the caller (it runs under `set -euo pipefail`).
detect_gpu() {
  command -v lspci >/dev/null 2>&1 || { echo "unknown"; return 0; }
  local vga
  # Match the PCI CLASS ID bracket (0300 VGA / 0301 XGA / 0302 3D / 0380 Other display), not loose
  # text — a plain 'vga|3d|display' text grep false-positives on any device whose hex ID happens to
  # contain "3d" (e.g. an Intel SATA controller [8086:43d2] reads as a second GPU, live-confirmed).
  vga="$(lspci -nn 2>/dev/null | grep -Ei '\[03[0-9a-f]{2}\]' || true)"

  # A VIRTUAL GPU (emulated adapter) needs the software/llvmpipe path, not vendor drivers — niri can't
  # drive virtio-gpu/QXL/std-VGA with amd/nvidia/intel userspace. Detect it FIRST so it is never
  # mis-overridden. A GPU-passthrough VM shows the REAL vendor (matched below), so this only catches the
  # emulated adapters: virtio-gpu, QXL, Bochs/std-VGA, VMware SVGA, Cirrus, Hyper-V.
  if grep -qiE 'virtio|qxl|bochs|vmware|cirrus|red hat|microsoft.*basic|hyper-?v' <<<"$vga"; then
    echo "vm"; return 0
  fi

  local has_nvidia=0 has_amd=0 has_intel=0
  # Match by PCI vendor id (always present in `lspci -nn`) + a safe name — NEVER bare "ati", which
  # matches "CorporATIon" and would flag every GPU as AMD (the wizard's manual pick used to mask this).
  grep -qiE '\[10de:|nvidia'                <<<"$vga" && has_nvidia=1   # NVIDIA
  grep -qiE '\[1002:|radeon|advanced micro' <<<"$vga" && has_amd=1      # AMD/ATI
  grep -qiE '\[8086:|intel'                 <<<"$vga" && has_intel=1    # Intel

  if   [ $has_nvidia -eq 1 ] && [ $has_intel -eq 1 ]; then echo "hybrid-intel-nvidia"
  elif [ $has_nvidia -eq 1 ] && [ $has_amd   -eq 1 ]; then echo "hybrid-amd-nvidia"
  elif [ $has_amd    -eq 1 ] && [ $has_intel -eq 1 ]; then echo "hybrid-amd-intel"
  elif [ $has_nvidia -eq 1 ]; then echo "nvidia"
  elif [ $has_amd    -eq 1 ]; then echo "amd"
  elif [ $has_intel  -eq 1 ]; then echo "intel"
  else echo "unknown"; fi
}

# Pick the NVIDIA driver tier from the chip codename (read fresh from lspci on the target). Echoes:
#   nouveau     — Fermi/Kepler (GF/GK) or unknown: open, in-kernel; reliable on CachyOS's new kernels
#                 (the proprietary 390xx/470xx legacy DKMS branches break on bleeding-edge kernels). GT 730.
#   nvidia      — Maxwell/Pascal/Volta (GM/GP/GV): proprietary nvidia-dkms (nvidia-open is Turing+ only).
#   nvidia-open — Turing+ (TU/GA/AD/GB…): nvidia-open-dkms.
# Defaults to nouveau (never a black screen) when the codename can't be read.
nvidia_tier() {
  local name
  name="$(lspci -d 10de:: 2>/dev/null | grep -Ei 'vga|3d|display' | head -1)"
  case "$name" in
    *G[FK][0-9]*)                              echo nouveau ;;     # Fermi / Kepler
    *G[MPV][0-9]*)                             echo nvidia ;;      # Maxwell / Pascal / Volta
    *TU[0-9]*|*GA[0-9]*|*AD[0-9]*|*GB[0-9]*)   echo nvidia-open ;; # Turing / Ampere / Ada / Blackwell+
    *)                                         echo nouveau ;;     # unknown -> safe default
  esac
}
