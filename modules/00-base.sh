#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"

substep "adding the CachyOS repository (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp" || die "could not enter temp dir $tmp"
  substep "downloading the CachyOS repo bootstrap (HTTPS)"
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  # TRUST MODEL: CachyOS publishes NO detached signature for the bootstrap tarball — that .sig URL serves
  # an HTML page, and CachyOS's own installer doesn't verify one. Instead we PIN CachyOS's signing-key
  # FINGERPRINT and import + locally-sign it into pacman's keyring FIRST, so every CachyOS package the
  # script then installs (cachyos-keyring, cachyos-mirrorlist, later linux-cachyos, …) is pacman-signature-
  # verified against the trusted key. The full fingerprint is the stable anchor (a keyserver cannot
  # substitute another key for a full-fp request); confirmed against wiki.cachyos.org + keyserver.ubuntu.com
  # (rsa3072, "CachyOS <admin@cachyos.org>", created 2021-08-10).
  CACHYOS_KEY_FPR="882DCFE48E2051D48E2562ABF3B607488DB35A47"
  if { sudo pacman-key --recv-keys "$CACHYOS_KEY_FPR" --keyserver hkps://keyserver.ubuntu.com \
       || sudo pacman-key --recv-keys "$CACHYOS_KEY_FPR" --keyserver hkps://keys.openpgp.org; } \
     && sudo pacman-key --finger "$CACHYOS_KEY_FPR" 2>/dev/null | tr -dc 'A-F0-9\n' | grep -qx "$CACHYOS_KEY_FPR"; then
    sudo pacman-key --lsign-key "$CACHYOS_KEY_FPR"
    ok "CachyOS signing key pinned + trusted ($CACHYOS_KEY_FPR) — its packages are signature-verified"
  elif [ "${ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS:-0}" = 1 ]; then
    warn "could NOT pin the CachyOS key (keyserver unreachable?) — proceeding UNVERIFIED (ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1)"
  else
    die "could not import + pin the CachyOS signing key $CACHYOS_KEY_FPR (need a reachable keyserver).
  Its packages would be unverifiable. Retry with network up, or ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1 to accept the risk."
  fi
  tar xf repo.tar.xz; cd cachyos-repo || die "CachyOS tarball missing the cachyos-repo/ dir"
  substep "running the CachyOS repo setup (adds the repo; package installs are signature-verified)"
  # The script's internal `pacman -U`/`pacman -Syu` have NO --noconfirm, so a headless resume hangs on
  # their [Y/n]. `yes |` answers them (the key is already pinned+lsigned, so those installs are verified).
  yes | sudo ./cachyos-repo.sh
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
