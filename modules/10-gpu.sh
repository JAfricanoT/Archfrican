#!/usr/bin/env bash
# Phase 2, step 1: GPU drivers, auto-detected. Vendor-agnostic by design.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/detect-gpu.sh"
source "$REPO_ROOT/lib/grub.sh"

gpu="${1:-$(detect_gpu)}"
substep "GPU profile: $gpu"

case "$gpu" in
  vm)
    substep "virtual GPU (VM) — software rendering: mesa + llvmpipe/swrast"
    pac_install mesa vulkan-swrast vulkan-icd-loader
    ok "VM: software rendering. niri still needs a DRM device — enable virtio-gpu / 3D accel in the hypervisor."
    ;;
  amd)
    substep "installing the AMD open stack (mesa + vulkan-radeon; mesa provides libva/VA-API)"
    pac_install mesa vulkan-radeon vulkan-icd-loader
    ok "AMD: open stack, zero extra config — the most reliable path."
    ;;
  intel)
    substep "installing the Intel open stack (mesa + vulkan-intel)"
    pac_install mesa vulkan-intel intel-media-driver vulkan-icd-loader
    ok "Intel: open stack, zero extra config."
    ;;
  hybrid-amd-intel)
    substep "installing both open stacks (AMD dGPU + Intel iGPU; mesa provides libva/VA-API)"
    pac_install mesa vulkan-radeon vulkan-intel intel-media-driver vulkan-icd-loader
    ok "AMD + Intel: both open stacks installed."
    ;;
  nvidia|hybrid-intel-nvidia|hybrid-amd-nvidia)
    tier="$(nvidia_tier)"   # nouveau (Fermi/Kepler) | nvidia (Maxwell-Volta) | nvidia-open (Turing+)
    if [ "$tier" = nouveau ]; then
      substep "NVIDIA legacy (Fermi/Kepler) — using nouveau (open, in-kernel; reliable on new kernels)"
      pac_install mesa vulkan-swrast vulkan-icd-loader
      [[ "$gpu" == hybrid-intel-nvidia ]] && pac_install vulkan-intel
      [[ "$gpu" == hybrid-amd-nvidia   ]] && pac_install vulkan-radeon
      ok "NVIDIA on nouveau — no DKMS / no early-KMS (the proprietary 390xx/470xx legacy breaks on CachyOS kernels)."
    else
      nvpkg=nvidia-dkms; [ "$tier" = nvidia-open ] && nvpkg=nvidia-open-dkms
      substep "installing NVIDIA proprietary ($nvpkg + utils + egl-wayland)"
      pac_install "$nvpkg" nvidia-utils egl-wayland vulkan-icd-loader libva-nvidia-driver
      [[ "$gpu" == hybrid-intel-nvidia ]] && pac_install mesa vulkan-intel
      [[ "$gpu" == hybrid-amd-nvidia   ]] && pac_install mesa vulkan-radeon
      # Early KMS so Wayland behaves and resume-from-suspend works. Edit grub + mkinitcpio,
      # VERIFY each edit took, then rebuild BOTH together — gated on a success sentinel so a
      # failed mkinitcpio is retried on re-run (the two must never diverge into a black screen).
      SENTINEL=/var/lib/archfrican/nvidia-kms.done
      need_build=0; [ -f "$SENTINEL" ] || need_build=1
      substep "ensuring NVIDIA early-KMS kernel params in /etc/default/grub"
      GRUB_CHANGED=0
      append_grub_cmdline nvidia_drm.modeset=1   # idempotent + verify-or-die (lib/grub.sh)
      append_grub_cmdline nvidia_drm.fbdev=1
      if [ "$GRUB_CHANGED" = 1 ]; then need_build=1; fi
      if ! grep -qE '^MODULES=\(.*\bnvidia_drm\b' /etc/mkinitcpio.conf; then
        substep "adding the nvidia modules to the initramfs (/etc/mkinitcpio.conf)"
        sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        grep -qE '^MODULES=\(.*\bnvidia_drm\b' /etc/mkinitcpio.conf \
          || die "could not add nvidia modules to MODULES in /etc/mkinitcpio.conf (multi-line MODULES?) — edit by hand"
        need_build=1
      fi
      if [ "$need_build" = 1 ]; then
        substep "regenerating GRUB + initramfs (this takes a moment)"
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        sudo mkinitcpio -P
        sudo install -d "$(dirname "$SENTINEL")"; sudo touch "$SENTINEL"
      fi
      substep "enabling suspend/resume/hibernate services"
      resilient_enable nvidia-suspend.service
      resilient_enable nvidia-resume.service
      resilient_enable nvidia-hibernate.service
      warn "NVIDIA configured. Reboot before first niri launch."
    fi
    ;;
  *)
    substep "unknown GPU — installing generic mesa + software Vulkan (VM-safe)"
    pac_install mesa vulkan-swrast vulkan-icd-loader
    ;;
esac
ok "gpu module done"
