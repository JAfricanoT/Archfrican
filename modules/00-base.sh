#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"

substep "adding the CachyOS repository (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp" || die "could not enter temp dir $tmp"
  substep "downloading the CachyOS repo bootstrap (HTTPS, verified)"
  # HTTPS-only, fail on HTTP errors (so an error page is never saved as the tarball).
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  # FAIL-CLOSED integrity check: we are about to run this tarball's script as ROOT, so a pinned
  # sha256 is REQUIRED unless explicitly overridden. Precedence: committed pin file → env pin →
  # explicit accept-unverified → die. (See packages/cachyos-repo.sha256.)
  pin="$(grep -oE '^[0-9a-f]{64}$' "$REPO_ROOT/packages/cachyos-repo.sha256" 2>/dev/null | head -1 || true)"
  if [ -n "$pin" ]; then
    echo "$pin  repo.tar.xz" | sha256sum -c - \
      || die "CachyOS tarball sha256 mismatch vs packages/cachyos-repo.sha256 — refusing to run it as root"
    ok "CachyOS tarball verified against the committed pin"
  elif [ -n "${ARCHFRICAN_CACHYOS_SHA256:-}" ]; then
    echo "${ARCHFRICAN_CACHYOS_SHA256}  repo.tar.xz" | sha256sum -c - \
      || die "CachyOS tarball sha256 mismatch vs ARCHFRICAN_CACHYOS_SHA256 — refusing to run it as root"
    ok "CachyOS tarball verified against ARCHFRICAN_CACHYOS_SHA256"
  elif [ "${ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS:-0}" = 1 ]; then
    warn "CachyOS tarball UNVERIFIED (ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1) — running its script as root anyway"
  else
    die "CachyOS tarball is not pinned — refusing to run an unverified script as root.
  Pin its sha256 in packages/cachyos-repo.sha256 (instructions in that file), or pass
  ARCHFRICAN_CACHYOS_SHA256=<digest>, or ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1 to accept the risk."
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
  elif [ "${ARCHFRICAN_ALLOW_AUR_PARU:-0}" != 1 ]; then
    die "paru is not in a binary repo and ARCHFRICAN_ALLOW_AUR_PARU is unset — refusing to build an
  UNPINNED paru-bin from the AUR. Normally the CachyOS repo (enabled above) ships paru as a signed
  binary; if you reached here the repo add likely failed. Re-run, or set ARCHFRICAN_ALLOW_AUR_PARU=1."
  else
    warn "building paru-bin from the AUR (ARCHFRICAN_ALLOW_AUR_PARU=1) — review the PKGBUILD"
    tmp="$(mktemp -d)"; git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp"
    substep "building paru from the AUR (makepkg)"
    ( cd "$tmp" && makepkg -si --noconfirm ); rm -rf "$tmp"
  fi
fi
ok "base module done"
