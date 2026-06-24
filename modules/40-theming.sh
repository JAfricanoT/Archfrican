#!/usr/bin/env bash
# Phase 2, step 4: fonts, GTK macOS theme, and the multi-theme switcher.
source "$(dirname "$0")/../lib/common.sh"

substep "installing fonts + GTK theme (from packages/theming.txt)"
pac_install_file "$REPO_ROOT/packages/theming.txt"
substep "installing AUR theme/icons/cursors/SF fonts/nwg-dock (from packages/aur.txt)"
aur_install_file "$REPO_ROOT/packages/aur.txt"

substep "applying the macOS GTK look (WhiteSur + McMojave + SF fonts)"
# gsettings needs a session D-Bus; on a TTY phase-2 run it may legitimately
# no-op — attempt() makes that visible (warn) instead of silently masking it.
attempt "gtk-theme"     gsettings set org.gnome.desktop.interface gtk-theme            "WhiteSur-Dark"
attempt "icon-theme"    gsettings set org.gnome.desktop.interface icon-theme           "WhiteSur-dark"
attempt "cursor-theme"  gsettings set org.gnome.desktop.interface cursor-theme         "McMojave-cursors"
attempt "font"          gsettings set org.gnome.desktop.interface font-name            "SF Pro Display 11"
attempt "mono-font"     gsettings set org.gnome.desktop.interface monospace-font-name  "SF Mono 11"
attempt "color-scheme"  gsettings set org.gnome.desktop.interface color-scheme         "prefer-dark"

# Apply the user's chosen theme — read the staged pick (phase 2 / inject_resume wrote it; chezmoi
# run_after re-applies it after dotfiles), NOT a hardcoded macos-dark. Hardcoding here silently
# overrode the wizard choice on install and reset a long-standing theme on every converge.
substep "applying the saved theme (the wizard pick, or adl-dark if none)"
theme="$(cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo adl-dark)"
attempt "default theme" env ARCHFRICAN_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/theme-switch" "$theme"
ok "theming module done"
