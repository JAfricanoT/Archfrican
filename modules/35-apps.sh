#!/usr/bin/env bash
# Phase 2, step: the app ecosystem (the "App Store" mental model). Flatpak + Flathub for sandboxed
# GUI apps that can never break the base system; pacman/AUR stays the SYSTEM layer. A curated,
# DECLARATIVE Flatpak catalog (flatpak/apps.txt) makes the app set part of "the system = the repo,
# applied". Also installs cloud/SMB connectivity (rclone + gvfs-smb). No browser — that's an opt-in
# choice (`archfrican-browser`).
source "$(dirname "$0")/../lib/common.sh"

substep "installing Flatpak + a software center + cloud/SMB connectivity"
pac_install_file "$REPO_ROOT/packages/apps.txt"

# Flathub, system-wide + idempotent. System scope = available to every user and kept on persistent
# storage (/var), so installed apps survive package upgrades and snapshot rollbacks.
substep "adding the Flathub remote (system-wide)"
best_effort timeout 60 sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Curated catalog: install each declared app-id if missing. NON-FATAL (network/runtime download), like
# the AUR layer — a Flatpak that fails to install must never abort the desktop install.
catalog="$REPO_ROOT/flatpak/apps.txt"
if [ -r "$catalog" ]; then
  substep "installing the curated Flatpak catalog (flatpak/apps.txt)"
  while IFS= read -r line || [ -n "$line" ]; do
    app="${line%%#*}"; app="$(printf '%s' "$app" | tr -d '[:space:]')"
    [ -n "$app" ] || continue
    if flatpak info "$app" >/dev/null 2>&1; then ok "flatpak present: $app"; continue; fi
    substep "flatpak install: $app"
    best_effort timeout 900 sudo flatpak install --system -y --noninteractive flathub "$app"
  done < "$catalog"
fi

ok "apps module done — Flatpak/Flathub ready; pick a browser with archfrican-browser; permissions via Flatseal"
