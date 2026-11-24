#!/usr/bin/env bash
# Phase 2, step 0: base system, CachyOS repos, dual kernel, AUR helper.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/grub.sh"

substep "adding the CachyOS repository (optimized packages + linux-cachyos)"
if ! grep -q '\[cachyos\]' /etc/pacman.conf; then
  tmp="$(mktemp -d)"; cd "$tmp" || die "could not enter temp dir $tmp"
  substep "downloading the CachyOS repo bootstrap (HTTPS)"
  # --connect-timeout/--max-time: curl has NO default timeout, so a stalled connection here hangs
  # the headless first-boot resume indefinitely (TimeoutStartSec=infinity on that unit) — same class
  # of bug already fixed for gsettings/grub-mkconfig elsewhere in this repo.
  curl -fL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 120 \
    https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
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
  # The script's internal `pacman -U`/`pacman -Syu` have NO --noconfirm, so a headless resume hangs on their
  # [Y/n]. Feed `yes`, but in a pipefail-OFF subshell so the pipeline's status is the SCRIPT's: otherwise
  # `yes`'s SIGPIPE ("broken pipe", once the script stops reading) trips `set -o pipefail` and fails the module
  # AFTER a successful run. (The key is already pinned+lsigned, so these installs are signature-verified.)
  ( set +o pipefail; yes 2>/dev/null | sudo ./cachyos-repo.sh )
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
# Pin linux-cachyos as the top-level default under a clean "Archfrican Linux" entry (vista limpia):
#   • GRUB_DISTRIBUTOR="Archfrican" -> menu reads "Archfrican Linux" instead of stock "Arch Linux".
#   • GRUB_TOP_LEVEL=/boot/vmlinuz-linux-cachyos -> overrides GRUB's reverse-alpha sort ('l' > 'c')
#     that otherwise silently booted linux-lts as default.
#   • GRUB_DISABLE_SUBMENU=false -> keeps the top screen clean ("Archfrican Linux" auto-boots
#     linux-cachyos; linux-lts stays tucked in "Advanced options for Archfrican Linux").
#   • GRUB_DISABLE_BOOTNEXT=true -> hides GRUB 2.16's noisy "(EFI BootNext)" firmware entries so
#     Btrfs snapshots remain visible without scrolling.
substep "configuring clean GRUB menu (Archfrican Linux -> linux-cachyos default, linux-lts in Advanced)"
set_grub_key GRUB_DISTRIBUTOR '"Archfrican"'
set_grub_key GRUB_TOP_LEVEL '"/boot/vmlinuz-linux-cachyos"'
set_grub_key GRUB_DISABLE_SUBMENU false
set_grub_key GRUB_DISABLE_BOOTNEXT true
substep "regenerating the GRUB config"
regen_grub
warn "linux-lts stays in GRUB under 'Advanced options for Archfrican Linux'. If a Cachy kernel ever"
warn "misbehaves with your GPU, pick LTS and keep working — nothing explodes."

# ---- memory + responsiveness backbone (zram VM tuning, earlyoom, ananicy-cpp) ----
# zram is compressed RAM, not spinning disk: Arch Wiki / CachyOS tuning compresses cold anonymous
# pages eagerly (swappiness=180), disables 8-page HDD readahead (page-cluster=0), and reclaims
# smoothly before hitting OOM stalls.
substep "tuning zram + kernel VM for compressed RAM (99-archfrican-vm.conf)"
write_system_file /etc/systemd/zram-generator.conf 0644 <<'ZRAM'
[zram0]
zram-size = min(ram * 1.5, 16384)
compression-algorithm = zstd
ZRAM
write_system_file /etc/sysctl.d/99-archfrican-vm.conf 0644 <<'VMSYSCTL'
# Archfrican VM tuning for zram (Arch Wiki / CachyOS):
# zram is compressed RAM, not spinning disk — compress cold anonymous pages eagerly,
# disable HDD swap readahead (page-cluster=0), and reclaim smoothly before OOM stalls.
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
VMSYSCTL
best_effort sudo sysctl --system >/dev/null

# earlyoom: intervene BEFORE the kernel OOM killer freezes the desktop or kills the Wayland session.
# Protects compositor/audio/login/input daemons and targets heavy browser tabs or runaway workers first.
substep "configuring earlyoom (protects the desktop session under memory pressure)"
write_system_file /etc/default/earlyoom 0644 <<'EARLYOOM'
# Archfrican: act BEFORE the kernel OOM killer freezes or kills the graphical session.
# Triggers when available RAM < 5% AND free swap < 5%.
EARLYOOM_ARGS="-r 0 -m 5 -s 5 --avoid '^(niri|systemd|dbus-broker|pipewire|wireplumber|waybar|sddm|sshd|keyd)$' --prefer '^(vivaldi-bin|chromium|brave|firefox|Web Content|Isolated Web Co|electron|node|claude)$'"
EARLYOOM
resilient_enable earlyoom.service
if systemctl is-active --quiet earlyoom.service 2>/dev/null; then
  best_effort sudo systemctl restart earlyoom.service
else
  best_effort sudo systemctl start earlyoom.service
fi

# ananicy-cpp: auto-renice interactive apps/compositor above heavy background builds and agents.
# cachyos-ananicy-rules lives in [cachyos] (enabled above), so install it conditionally.
substep "enabling ananicy-cpp (keeps UI responsive under heavy agent/build load)"
if pacman -Si cachyos-ananicy-rules &>/dev/null; then
  best_effort pac_install cachyos-ananicy-rules
fi
resilient_enable ananicy-cpp.service
best_effort sudo systemctl start ananicy-cpp.service

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
