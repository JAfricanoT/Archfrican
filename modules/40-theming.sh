#!/usr/bin/env bash
# Phase 2, step 4: fonts, GTK macOS theme, and the multi-theme switcher.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/grub.sh"    # set_grub_key (idempotent /etc/default/grub) for the boot-menu theme

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
substep "applying the saved theme (the wizard pick, or archfrican-dark if none)"
theme="$(cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo archfrican-dark)"

# Tier-B app cohesion (VS Code + web-apps) is ON by default — the homogeneity is the point;
# `archfrican-cohesion off` disables it and is remembered across converge re-runs. Seed the flag only
# on a first install (neither marker present), BEFORE theme-switch so its best-effort apply hook fires.
if [ ! -e "$HOME/.config/archfrican/cohesion-on" ] && [ ! -e "$HOME/.config/archfrican/cohesion-off-chosen" ]; then
  mkdir -p "$HOME/.config/archfrican"; : > "$HOME/.config/archfrican/cohesion-on"
fi

attempt "default theme" env ARCHFRICAN_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/theme-switch" "$theme"

# GRUB boot menu — the one surface that still wore the stock look. Dress it in the ADL identity too
# (solid graphite ${BG} + ${ACCENT} selection + Inter), fully tokenised from $theme. Cosmetic + low-risk:
# a bad theme.txt just falls back to GRUB's text menu (still bootable), so the whole block is best-effort
# — the subshell contains a set_grub_key die, and it skips cleanly when GRUB isn't the bootloader.
if command -v grub-mkconfig >/dev/null 2>&1 && [ -d /boot/grub ]; then
  substep "theming the GRUB boot menu to match the OS ($theme)"
  (
    render_grub_theme "$theme"
    # rasterise Inter -> the .pf2 the theme.txt names ("Inter Regular 20"). Best-effort: without it GRUB
    # uses its built-in font and the ADL colours/background still show. Prefer a static Regular, else any Inter.
    if command -v grub-mkfont >/dev/null 2>&1; then
      inter="$(find /usr/share/fonts -type f \( -iname 'Inter*Regular*.ttf' -o -iname 'Inter*Regular*.otf' \) 2>/dev/null | head -n1 || true)"
      [ -n "$inter" ] || inter="$(find /usr/share/fonts -type f \( -iname 'Inter*.ttf' -o -iname 'Inter*.otf' \) 2>/dev/null | head -n1 || true)"
      if [ -n "$inter" ]; then
        sudo grub-mkfont --name "Inter Regular 20" -s 20 -o /boot/grub/themes/archfrican/inter.pf2 "$inter" \
          || warn "grub-mkfont failed — GRUB falls back to its built-in font (ADL colours still apply)"
      else
        warn "Inter font not found under /usr/share/fonts — GRUB uses its built-in font (colours still apply)"
      fi
    fi
    set_grub_key GRUB_THEME /boot/grub/themes/archfrican/theme.txt
    set_grub_key GRUB_GFXMODE auto
    sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 \
      || warn "grub-mkconfig failed — the current grub.cfg still boots; the theme applies on the next successful regen"
  ) || warn "GRUB theming skipped (non-fatal — the boot menu still works)"
fi
ok "theming module done"
