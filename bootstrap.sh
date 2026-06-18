#!/usr/bin/env bash
# One-liner entry point for a freshly-installed (phase 1) Arch system:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOU/archfrican/main/bootstrap.sh)
set -euo pipefail
sudo pacman -S --needed --noconfirm git
git clone https://github.com/YOU/archfrican.git "$HOME/.archfrican" 2>/dev/null || git -C "$HOME/.archfrican" pull
exec "$HOME/.archfrican/install.sh"
