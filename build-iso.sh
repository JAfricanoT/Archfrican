#!/usr/bin/env bash
# Build the Archfrican installer ISO.
#
# Strategy: use archiso's upstream 'releng' profile as the base (gets GRUB/syslinux/EFI
# boot infrastructure for free, stays in sync with archiso updates), then layer our minimal
# customizations on top: metadata overrides, extra packages (gum), our airootfs overlay
# (motd, hostname, .zlogin with auto-launch), and the pre-bundled installer repo.
#
# Requires:  archiso (pacman -S archiso), root privileges for mkarchiso.
# Usage:
#   sudo bash build-iso.sh
#   SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) sudo bash build-iso.sh  # reproducible
#   sudo ARCHFRICAN_ISO_WORKDIR=/var/tmp/archfrican-iso-work bash build-iso.sh  # /tmp is tmpfs
#                                                                                # and too small/RAM-tight? use disk
#
# Output:  out/archfrican-YYYY.MM.DD-x86_64.iso
# ============================================================================
set -euo pipefail

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
RELENG="/usr/share/archiso/configs/releng"
OUT_DIR="$HERE/out"
WORK_DIR="${ARCHFRICAN_ISO_WORKDIR:-/tmp/archfrican-iso-work}"

# ---- preflight ---------------------------------------------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root:  sudo bash build-iso.sh" >&2; exit 1; }
command -v mkarchiso >/dev/null 2>&1 || {
  echo "archiso not installed.  Run: pacman -S archiso" >&2; exit 1; }
[ -d "$RELENG" ] || {
  echo "releng profile not found at $RELENG (archiso installed?)" >&2; exit 1; }

# ---- temp profile dir (cleaned up on exit) -----------------------------------
PROFILE_DIR="$(mktemp -d /tmp/archfrican-profile.XXXXXX)"
cleanup() { rm -rf "$PROFILE_DIR"; }
trap cleanup EXIT

# ---- 1. copy releng as the base (inherits all boot infrastructure) -----------
echo "==> Copying releng profile..."
cp -a "$RELENG/." "$PROFILE_DIR/"

# ---- 2. override ISO metadata (append wins in bash — last assignment takes) --
cat >> "$PROFILE_DIR/profiledef.sh" <<'META'

# ---- Archfrican overrides (last assignment wins) ----------------------------
iso_name="archfrican"
iso_label="ARCHFRICAN_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
iso_publisher="Archfrican <https://github.com/JAfricanoT/Archfrican>"
iso_application="Archfrican Installer"
META

# ---- 3. add our extra packages (gum, rsync) to releng's list ----------------
echo "==> Adding extra packages..."
# Strip comment lines from our list before appending (releng's list has no comments)
grep -v '^[[:space:]]*#' "$HERE/iso/packages.extra.x86_64" | grep -v '^[[:space:]]*$' \
  >> "$PROFILE_DIR/packages.x86_64"

# ---- 4. overlay our airootfs additions (motd, hostname, .zlogin) ------------
echo "==> Overlaying airootfs customizations..."
cp -a "$HERE/iso/airootfs/." "$PROFILE_DIR/airootfs/"

# ---- 5. pre-bundle the installer repo into the live environment --------------
echo "==> Syncing installer repo into live env (/root/.archfrican)..."
# Bundle ONLY tracked content: `git archive` cannot leak anything .gitignore protects —
# tests/e2e/answers.env (test LUKS/user passwords), *.log, editor/session state, worktrees —
# which a plain rsync of the checkout would bake world-readable into airootfs.sfs.
REPO_DEST="$PROFILE_DIR/airootfs/root/.archfrican"
rm -rf "$REPO_DEST"; mkdir -p "$REPO_DEST"
if git -C "$HERE" rev-parse --verify HEAD >/dev/null 2>&1; then
  [ -z "$(git -C "$HERE" status --porcelain 2>/dev/null)" ] \
    || echo "==> NOTE: working tree is dirty — the ISO bundles HEAD (tracked content only)"
  git -C "$HERE" archive HEAD | tar -x -C "$REPO_DEST"
  rm -rf "$REPO_DEST/iso" "$REPO_DEST/out"   # tracked, but no place inside the live env
else
  # tarball checkout (no .git): rsync honoring .gitignore + the known secret/state holders
  rsync -a --delete \
    --filter=':- .gitignore' \
    --exclude='.git' --exclude='iso/' --exclude='out/' --exclude='.DS_Store' \
    --exclude='.claude' --exclude='.superpowers' --exclude='.remember' \
    --exclude='tests/e2e/answers.env' \
    "$HERE/" "$REPO_DEST/"
fi

# ---- 6. build ----------------------------------------------------------------
rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

echo "==> Running mkarchiso (this takes ~8-15 minutes)..."
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

ISO="$(find "$OUT_DIR" -maxdepth 1 -name 'archfrican-*.iso' 2>/dev/null | sort | tail -1 || true)"
echo ""
echo "==> Build complete: ${ISO:-$OUT_DIR/archfrican-*.iso}"
echo ""
echo "    Test in QEMU (preview mode — no disk is touched):"
echo "    qemu-system-x86_64 -enable-kvm -m 4G -cdrom \"$ISO\" \\"
echo "      -drive file=/tmp/test-disk.img,format=raw,if=virtio \\"
echo "      -bios /usr/share/edk2/x64/OVMF.fd"
