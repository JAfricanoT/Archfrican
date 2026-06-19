#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"

substep "adding the CachyOS repository (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp" || die "could not enter temp dir $tmp"
  substep "downloading the CachyOS repo bootstrap (HTTPS, verified)"
  # HTTPS-only, fail on HTTP errors (so an error page is never saved as the tarball).
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz     -o repo.tar.xz
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz.sig -o repo.tar.xz.sig || true
  # FAIL-CLOSED integrity check: we run this tarball's bootstrap AS ROOT, so verify it
  # cryptographically first. The STABLE trust anchor is CachyOS's signing-key FINGERPRINT — it does
  # NOT rotate when the tarball is rebuilt (a content sha256 would, breaking every install over time),
  # so anyone can install with no per-release pin to maintain. Fingerprint confirmed against
  # wiki.cachyos.org + keyserver.ubuntu.com (rsa3072, "CachyOS <admin@cachyos.org>", created 2021-08-10).
  CACHYOS_KEY_FPR="882DCFE48E2051D48E2562ABF3B607488DB35A47"
  verified=0
  if command -v gpg >/dev/null && [ -s repo.tar.xz.sig ]; then
    gpgdir="$(mktemp -d)"
    # --recv-keys with the FULL fingerprint: a keyserver cannot substitute a different key for it.
    # Re-assert the fingerprint (--with-colons fpr record), then verify the detached signature of the
    # exact tarball we downloaded. Any failure leaves verified=0 → die below (unless explicitly overridden).
    if { gpg --homedir "$gpgdir" --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$CACHYOS_KEY_FPR" \
         || gpg --homedir "$gpgdir" --batch --keyserver hkps://keys.openpgp.org   --recv-keys "$CACHYOS_KEY_FPR"; } \
       && gpg --homedir "$gpgdir" --with-colons --fingerprint "$CACHYOS_KEY_FPR" 2>/dev/null \
            | grep -q "^fpr:::::::::${CACHYOS_KEY_FPR}:" \
       && gpg --homedir "$gpgdir" --verify repo.tar.xz.sig repo.tar.xz 2>/dev/null; then
      verified=1
    fi
    rm -rf "$gpgdir"
  fi
  if [ "$verified" = 1 ]; then
    ok "CachyOS tarball verified — signed by the pinned CachyOS key $CACHYOS_KEY_FPR"
  elif [ "${ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS:-0}" = 1 ]; then
    warn "CachyOS tarball NOT cryptographically verified (ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1) — running its script as root anyway"
  else
    die "CachyOS tarball did not verify against the pinned key $CACHYOS_KEY_FPR — refusing to run an
  unverified script as root. Needs gpg + a reachable keyserver (network). To override at your own
  risk: ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1."
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
