#!/usr/bin/env bash
# One-liner entry point for a freshly-installed (phase 1) Arch system:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOU/archfrican/main/bootstrap.sh)
# Pin to a release once you cut one:   ARCHFRICAN_REF=v0.1 bash <(curl -fsSL …)
set -euo pipefail

REPO="${ARCHFRICAN_REPO:-https://github.com/YOU/archfrican.git}"
REF="${ARCHFRICAN_REF:-main}"          # tag/branch/commit; pin to a signed tag for production
DEST="$HOME/.archfrican"

sudo pacman -S --needed --noconfirm git

# Fetch the pinned ref explicitly — no blind `pull` of whatever upstream now has, and don't hide
# the real cause of a clone failure (network / wrong URL / placeholder owner).
if [ -d "$DEST/.git" ]; then
  echo "archfrican: updating $DEST to '$REF'"
  git -C "$DEST" fetch --depth 1 origin "$REF"
  git -C "$DEST" reset --hard FETCH_HEAD
else
  git clone --depth 1 --branch "$REF" "$REPO" "$DEST"
fi

# Invoke via the interpreter so a missing +x bit on a fresh clone can't break the entry point.
exec bash "$DEST/install.sh"
