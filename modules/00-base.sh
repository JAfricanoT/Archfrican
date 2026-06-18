#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"

log "Adding CachyOS repositories (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp"
  curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  tar xf repo.tar.xz && cd cachyos-repo
  sudo ./cachyos-repo.sh        # auto-detects x86-64-v3/v4 and wires the repo
  cd /; rm -rf "$tmp"
  ok "CachyOS repo enabled"
else
  ok "CachyOS repo already present"
fi

log "Installing base packages"
pac_install_file "$REPO_ROOT/packages/base.txt"

log "Dual kernel: linux-cachyos (primary) + linux-lts (safety net)"
pac_install linux-cachyos linux-cachyos-headers linux-lts linux-lts-headers
sudo grub-mkconfig -o /boot/grub/grub.cfg
warn "linux-lts stays in the GRUB menu. If a Cachy kernel ever misbehaves with"
warn "your GPU, just boot LTS and keep working — nothing explodes."

log "Installing paru (AUR helper)"
if ! command -v paru &>/dev/null; then
  tmp="$(mktemp -d)"; git clone https://aur.archlinux.org/paru-bin.git "$tmp"
  ( cd "$tmp" && makepkg -si --noconfirm ); rm -rf "$tmp"
fi
ok "base module done"
