#!/usr/bin/env bash
# Phase 2, optional step: the gaming stack. OPT-IN (exit 3 when not selected) — like multi-boot — so
# non-gamers carry none of it. Enables [multilib], installs Steam + gamescope + gamemode + MangoHud +
# 32-bit Vulkan/Mesa (+ the GPU-matched 32-bit driver), Proton-GE (AUR), and ananicy-cpp (auto-nice).
# Re-selectable later:  ~/.archfrican/install.sh 65-gaming yes
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/detect-gpu.sh"

# Opt-in gate: the wizard arg ("yes"/"no") or ARCHFRICAN_ENABLE_GAMING=1. Exit 3 = not selected (no
# .done stamp, so a later opt-in isn't masked) — exactly the 55-multiboot pattern.
if [ "${1:-no}" != yes ] && [ "${ARCHFRICAN_ENABLE_GAMING:-0}" != 1 ]; then
  ok "gaming stack not selected (opt-in: the wizard, ARCHFRICAN_ENABLE_GAMING=1, or install.sh 65-gaming yes)"
  exit 3
fi

# ---- enable [multilib] (32-bit game libraries) — idempotent + verify-or-restore -----------------
if grep -q '^\[multilib\]' /etc/pacman.conf; then
  ok "multilib already enabled"
else
  substep "enabling the [multilib] repo (32-bit libraries for Steam/Proton)"
  sudo cp /etc/pacman.conf /etc/pacman.conf.archfrican.bak
  sudo sed -i '/^#\[multilib\]/,/^#Include = .*mirrorlist/ s/^#//' /etc/pacman.conf
  if grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo pacman -Sy
  else
    sudo mv -f /etc/pacman.conf.archfrican.bak /etc/pacman.conf
    die "could not enable [multilib] (unexpected /etc/pacman.conf format) — restored the backup"
  fi
fi

substep "installing the gaming stack (Steam, gamescope, gamemode, MangoHud, 32-bit Vulkan/Mesa)"
pac_install_file "$REPO_ROOT/gaming/packages.txt"

# GPU-matched 32-bit Vulkan driver (lib32-mesa above covers GL on AMD/Intel). NON-FATAL: detection
# is best-effort and some drivers may be absent on a given box.
case "$(detect_gpu 2>/dev/null || echo unknown)" in
  *hybrid*) attempt "lib32 intel"  pac_install lib32-vulkan-intel
            attempt "lib32 nvidia" pac_install lib32-nvidia-utils ;;
  *nvidia*) attempt "lib32 nvidia" pac_install lib32-nvidia-utils ;;
  *amd*)    attempt "lib32 radeon" pac_install lib32-vulkan-radeon ;;
  *intel*)  attempt "lib32 intel"  pac_install lib32-vulkan-intel ;;
  *)        ok "GPU not matched for a 32-bit Vulkan driver — lib32-mesa covers AMD/Intel GL" ;;
esac

# ananicy-cpp: auto-renice (keeps the desktop + games responsive under load). CachyOS-aligned.
substep "enabling ananicy-cpp (auto-nice scheduler assist)"
resilient_enable ananicy-cpp.service

# Proton-GE (community Proton fork; better game compatibility). AUR, prebuilt -bin, NON-FATAL.
substep "installing Proton-GE (AUR, best-effort)"
aur_install proton-ge-custom-bin

ok "gaming module done — launch Steam; toggle MangoHud with Shift+F12; gamescope + gamemode are ready"
