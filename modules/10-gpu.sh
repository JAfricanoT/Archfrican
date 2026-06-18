#!/usr/bin/env bash
# Phase 2, step 1: GPU drivers, auto-detected. Vendor-agnostic by design.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/detect-gpu.sh"

gpu="${1:-$(detect_gpu)}"
log "Detected GPU profile: $gpu"

case "$gpu" in
  amd)
    pac_install mesa vulkan-radeon libva-mesa-driver vulkan-icd-loader
    ok "AMD: open stack, zero extra config — the most reliable path."
    ;;
  intel)
    pac_install mesa vulkan-intel intel-media-driver vulkan-icd-loader
    ok "Intel: open stack, zero extra config."
    ;;
  nvidia|hybrid-intel-nvidia|hybrid-amd-nvidia)
    pac_install nvidia-open-dkms nvidia-utils egl-wayland \
                vulkan-icd-loader libva-nvidia-driver
    [[ "$gpu" == hybrid-intel-nvidia ]] && pac_install mesa vulkan-intel
    [[ "$gpu" == hybrid-amd-nvidia   ]] && pac_install mesa vulkan-radeon
    # Kernel params + early KMS so Wayland behaves and resume-from-suspend works
    if ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
      sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /etc/default/grub
      sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
    if ! grep -q 'nvidia' /etc/mkinitcpio.conf; then
      sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
      sudo mkinitcpio -P
    fi
    best_effort sudo systemctl enable nvidia-suspend.service nvidia-resume.service
    warn "NVIDIA configured. Reboot before first niri launch."
    ;;
  *) warn "Unknown GPU — installing generic mesa + software Vulkan." ; pac_install mesa vulkan-swrast vulkan-icd-loader ;;
esac
ok "gpu module done"
