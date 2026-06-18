#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"

log "Adding CachyOS repositories (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp"
  # HTTPS-only, fail on HTTP errors (so an error page is never saved as the tarball).
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  # Optional integrity pin: export ARCHFRICAN_CACHYOS_SHA256=<hash> to fail-closed on mismatch.
  # The upstream tarball is rolling (no stable published hash), so this is opt-in rather than
  # hard-coded — a hard pin would break every install when CachyOS rolls the file.
  if [ -n "${ARCHFRICAN_CACHYOS_SHA256:-}" ]; then
    echo "${ARCHFRICAN_CACHYOS_SHA256}  repo.tar.xz" | sha256sum -c - \
      || die "CachyOS tarball sha256 mismatch — refusing to run it as root"
    ok "CachyOS tarball sha256 verified"
  else
    warn "CachyOS tarball unverified (set ARCHFRICAN_CACHYOS_SHA256 to pin it); running upstream repo script as root"
  fi
  tar xf repo.tar.xz && cd cachyos-repo
  sudo ./cachyos-repo.sh        # adds the repo to /etc/pacman.conf + imports the CachyOS signing key
  cd /; rm -rf "$tmp"
  ok "CachyOS repo enabled"
else
  ok "CachyOS repo already present"
fi

# Refresh the keyring before any --noconfirm bulk install, so new/rotated signing keys are current
# and not silently mistrusted. Targeted keyring sync (safe right after a fresh base install).
log "Refreshing pacman keyring"
sudo pacman -Sy --needed --noconfirm archlinux-keyring
sudo pacman-key --populate archlinux

log "Installing base packages"
pac_install_file "$REPO_ROOT/packages/base.txt"

log "Dual kernel: linux-cachyos (primary) + linux-lts (safety net)"
pac_install linux-cachyos linux-cachyos-headers linux-lts linux-lts-headers
sudo grub-mkconfig -o /boot/grub/grub.cfg
warn "linux-lts stays in the GRUB menu. If a Cachy kernel ever misbehaves with"
warn "your GPU, just boot LTS and keep working — nothing explodes."

log "Installing paru (AUR helper)"
if ! command -v paru &>/dev/null; then
  if pacman -Si paru &>/dev/null; then
    pac_install paru            # from the CachyOS repo enabled above — no unreviewed AUR build
  else
    warn "paru not in a binary repo; building paru-bin from the AUR — review the PKGBUILD first"
    tmp="$(mktemp -d)"; git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp"
    ( cd "$tmp" && makepkg -si --noconfirm ); rm -rf "$tmp"
  fi
fi
ok "base module done"
