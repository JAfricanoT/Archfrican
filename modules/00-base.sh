#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"

substep "adding the CachyOS repository (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp" || die "could not enter temp dir $tmp"
  substep "downloading the CachyOS repo bootstrap (HTTPS, verified)"
  # HTTPS-only, fail on HTTP errors (so an error page is never saved as the tarball).
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  # Optional integrity pin: export ARCHFRICAN_CACHYOS_SHA256=<hash> to fail-closed on mismatch.
  if [ -n "${ARCHFRICAN_CACHYOS_SHA256:-}" ]; then
    echo "${ARCHFRICAN_CACHYOS_SHA256}  repo.tar.xz" | sha256sum -c - \
      || die "CachyOS tarball sha256 mismatch — refusing to run it as root"
    ok "CachyOS tarball sha256 verified"
  else
    warn "CachyOS tarball unverified (set ARCHFRICAN_CACHYOS_SHA256 to pin it); running upstream repo script as root"
  fi
  tar xf repo.tar.xz; cd cachyos-repo || die "CachyOS tarball missing the cachyos-repo/ dir"
  substep "running the CachyOS repo setup (adds the repo + imports its signing key)"
  sudo ./cachyos-repo.sh
  cd /; rm -rf "$tmp"
  ok "CachyOS repo enabled"
else
  ok "CachyOS repo already present"
fi

# Refresh the keyring before any --noconfirm bulk install, so new/rotated signing keys are current.
substep "refreshing archlinux-keyring + populating the pacman keyring"
sudo pacman -Sy --needed --noconfirm archlinux-keyring
sudo pacman-key --populate archlinux

substep "installing base packages (from packages/base.txt)"
pac_install_file "$REPO_ROOT/packages/base.txt"

substep "installing the dual kernel: linux-cachyos (primary) + linux-lts (safety net)"
pac_install linux-cachyos linux-cachyos-headers linux-lts linux-lts-headers
substep "regenerating the GRUB config"
sudo grub-mkconfig -o /boot/grub/grub.cfg
warn "linux-lts stays in the GRUB menu. If a Cachy kernel ever misbehaves with"
warn "your GPU, just boot LTS and keep working — nothing explodes."

substep "installing the AUR helper (paru)"
if ! command -v paru &>/dev/null; then
  if pacman -Si paru &>/dev/null; then
    pac_install paru            # from the CachyOS repo enabled above — no unreviewed AUR build
  else
    warn "paru not in a binary repo; building paru-bin from the AUR — review the PKGBUILD first"
    tmp="$(mktemp -d)"; git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp"
    substep "building paru from the AUR (makepkg)"
    ( cd "$tmp" && makepkg -si --noconfirm ); rm -rf "$tmp"
  fi
fi
ok "base module done"
