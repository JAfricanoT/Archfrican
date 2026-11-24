#!/usr/bin/env bash
# Phase 2, step 1: GPU drivers, auto-detected. Vendor-agnostic by design.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/detect-gpu.sh"
source "$REPO_ROOT/lib/grub.sh"
source "$REPO_ROOT/lib/gpu-niri.sh"

gpu="${1:-$(detect_gpu)}"
substep "GPU profile: $gpu"

NIRI_GPU_DROPIN=/etc/systemd/user/niri.service.d/10-archfrican-gpu.conf
NIRI_GPU_SIDECAR="${XDG_CONFIG_HOME:-$HOME/.config}/archfrican/gpu-niri.kdl"

# Live-confirmed on NVIDIA Kepler (GeForce GT 730 / GK208B) under nouveau + niri:
# Smithay's atomic KMS + hardware cursor plane + direct scanout + unawaited frame queueing trigger
# blue/colored screen flashes on every keypress or mouse move. Forcing legacy DRM KMS via the niri
# user-service drop-in AND splicing niri's DRM debug flags eliminates the flicker while keeping GPU
# acceleration intact. Both survive `chezmoi apply` (the drop-in is in /etc; the sidecar is
# re-spliced into config.kdl by home/run_after_99-apply-theme.sh.tmpl).
apply_nouveau_niri_workarounds() {
  substep "configuring niri DRM/KMS stability workarounds for nouveau (legacy KMS + debug flags)"
  write_system_file "$NIRI_GPU_DROPIN" 0644 <<'DROPIN'
# Archfrican (modules/10-gpu.sh): NVIDIA legacy on nouveau (Fermi/Kepler).
# Smithay's atomic KMS triggers blue/colored screen flashes on input repaints on Kepler;
# legacy DRM KMS keeps GPU acceleration while eliminating the page-flip/plane corruption.
[Service]
Environment=SMITHAY_USE_LEGACY=1
DROPIN
  best_effort systemctl --user daemon-reload
  mkdir -p "$(dirname "$NIRI_GPU_SIDECAR")"
  cat > "$NIRI_GPU_SIDECAR" <<'KDL'
debug {
    disable-cursor-plane
    disable-direct-scanout
    wait-for-frame-completion-before-queueing
}
KDL
  best_effort splice_niri_gpu_block
}

clear_nouveau_niri_workarounds() {
  if [ -e "$NIRI_GPU_DROPIN" ]; then
    sudo rm -f "$NIRI_GPU_DROPIN"
    best_effort systemctl --user daemon-reload
    ok "removed stale nouveau niri drop-in ($NIRI_GPU_DROPIN)"
  fi
  if [ -e "$NIRI_GPU_SIDECAR" ]; then
    rm -f "$NIRI_GPU_SIDECAR"
    best_effort splice_niri_gpu_block
  fi
}

case "$gpu" in
  vm)
    clear_nouveau_niri_workarounds
    substep "virtual GPU (VM) — software rendering: mesa + llvmpipe/swrast"
    pac_install mesa vulkan-swrast vulkan-icd-loader
    ok "VM: software rendering. niri still needs a DRM device — enable virtio-gpu / 3D accel in the hypervisor."
    ;;
  amd)
    clear_nouveau_niri_workarounds
    substep "installing the AMD open stack (mesa + vulkan-radeon; mesa provides libva/VA-API)"
    pac_install mesa vulkan-radeon vulkan-icd-loader
    ok "AMD: open stack, zero extra config — the most reliable path."
    ;;
  intel)
    clear_nouveau_niri_workarounds
    substep "installing the Intel open stack (mesa + vulkan-intel)"
    pac_install mesa vulkan-intel intel-media-driver vulkan-icd-loader
    ok "Intel: open stack, zero extra config."
    ;;
  hybrid-amd-intel)
    clear_nouveau_niri_workarounds
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
      apply_nouveau_niri_workarounds
      # Early KMS for nouveau: loads the in-kernel driver BEFORE Plymouth takes over from GRUB's
      # EFI framebuffer, eliminating the black-and-white VRAM scanout artifacts between GRUB and
      # the LUKS disk-unlock screen (live-confirmed on GK208B / GT 730). Gated on a sentinel so
      # mkinitcpio only rebuilds once.
      NOUVEAU_SENTINEL=/var/lib/archfrican/nouveau-kms.done
      nouveau_need_build=0; [ -f "$NOUVEAU_SENTINEL" ] || nouveau_need_build=1
      if ! grep -qE '^MODULES=\(.*\bnouveau\b' /etc/mkinitcpio.conf; then
        substep "adding nouveau to initramfs MODULES for clean GRUB → Plymouth handoff"
        sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nouveau)/' /etc/mkinitcpio.conf
        sudo sed -i 's/^MODULES=( /MODULES=(/' /etc/mkinitcpio.conf
        grep -qE '^MODULES=\(.*\bnouveau\b' /etc/mkinitcpio.conf \
          || die "could not add nouveau to MODULES in /etc/mkinitcpio.conf — edit by hand"
        nouveau_need_build=1
      fi
      if [ "$nouveau_need_build" = 1 ]; then
        substep "regenerating initramfs with early nouveau KMS"
        sudo mkinitcpio -P
        sudo install -d "$(dirname "$NOUVEAU_SENTINEL")"; sudo touch "$NOUVEAU_SENTINEL"
      fi
      ok "NVIDIA on nouveau — early KMS enabled (no DKMS; proprietary 390xx/470xx breaks on CachyOS kernels)."
      warn "If already in a niri session, log out and back in (Mod+Shift+E) for the DRM/KMS workaround to apply."
    else
      clear_nouveau_niri_workarounds
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
      # Preserve VRAM allocations across suspend/hibernate — required for nvidia-suspend/resume.service
      # below; without it, waking from sleep leaves corrupted/blank/flashing Wayland surfaces.
      NV_MODPROBE=/etc/modprobe.d/archfrican-nvidia.conf
      _nv_modprobe_before="$(sudo sha256sum "$NV_MODPROBE" 2>/dev/null | awk '{print $1}' || true)"
      substep "configuring NVIDIA VRAM preservation for suspend/resume ($NV_MODPROBE)"
      write_system_file "$NV_MODPROBE" 0644 <<'MODPROBE'
# Archfrican (modules/10-gpu.sh): preserve VRAM across suspend/hibernate (required by nvidia-suspend/resume).
options nvidia NVreg_PreserveVideoMemoryAllocations=1
MODPROBE
      _nv_modprobe_after="$(sudo sha256sum "$NV_MODPROBE" 2>/dev/null | awk '{print $1}' || true)"
      [ "$_nv_modprobe_before" != "$_nv_modprobe_after" ] && need_build=1
      # Official niri NVIDIA workaround (R565+): without GLVidHeapReuseRatio=0, the proprietary
      # driver fails to recycle freed OpenGL buffers for niri and leaks gigabytes of VRAM.
      substep "installing NVIDIA application profile for niri (prevents R565+ VRAM bloat)"
      write_system_file /etc/nvidia/nvidia-application-profiles-rc.d/50-archfrican-niri.json 0644 <<'NVPROF'
{
  "rules": [
    {
      "pattern": {
        "feature": "procname",
        "matches": "niri"
      },
      "profile": "Limit Free Buffer Pool On Wayland Compositors"
    }
  ],
  "profiles": [
    {
      "name": "Limit Free Buffer Pool On Wayland Compositors",
      "settings": [
        {
          "key": "GLVidHeapReuseRatio",
          "value": 0
        }
      ]
    }
  ]
}
NVPROF
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
        regen_grub
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
    clear_nouveau_niri_workarounds
    substep "unknown GPU — installing generic mesa + software Vulkan (VM-safe)"
    pac_install mesa vulkan-swrast vulkan-icd-loader
    ;;
esac
ok "gpu module done"
