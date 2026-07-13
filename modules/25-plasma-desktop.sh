#!/usr/bin/env bash
# Phase 2, optional step: KDE Plasma as a second, opt-in desktop session — selectable at SDDM login
# alongside niri. OPT-IN (exit 3 when not selected), same pattern as 55-multiboot — non-Plasma users
# carry none of it. MINIMAL shell only: no Konsole/Kate/Discover (ghostty + gnome-software are reused).
# Never touches niri/waybar/swaync/keyd in ANY way.
# Re-selectable later:  ~/.archfrican/install.sh 25-plasma-desktop yes
source "$(dirname "$0")/../lib/common.sh"

# Gate: only when explicitly asked. Exit 3 = "not selected" — no .done stamp, so a later opt-in still
# runs. Mirrors 55-multiboot's single-flag gate (no multilib/GPU-matching complexity — see
# modules/65-gaming.sh for that heavier pattern, which does not apply here).
[ "${1:-no}" = yes ] || exit 3

substep "installing the KDE Plasma desktop (minimal Wayland shell)"
pac_install_file "$REPO_ROOT/packages/plasma-desktop.txt"

# SDDM auto-discovers the new Wayland session the same way it already does for niri
# (/usr/share/wayland-sessions/*.desktop, owned by the package — see modules/20-niri-desktop.sh's
# comment + `pacman -Qo /usr/share/wayland-sessions/niri.desktop`). This is a smoke test for that
# inference (not directly confirmed on a machine without Plasma installed — verify for real here).
if ls /usr/share/wayland-sessions/plasma*.desktop &>/dev/null; then
  ok "Plasma Wayland session file present — will appear in the SDDM session picker"
else
  warn "no /usr/share/wayland-sessions/plasma*.desktop found — check 'pacman -Ql plasma-workspace | grep wayland-sessions'"
fi

# TODO(empirical, do not guess): default terminal = ghostty (not Konsole). The kdeglobals key that
# Dolphin/Kickoff read for "open terminal here" is UNVERIFIED. Confirm before wiring:
#   1. log into Plasma once, System Settings -> Applications -> Default Applications ->
#      Terminal Emulator -> select Ghostty
#   2. kreadconfig6 --file kdeglobals --group General --dump   (diff before/after to find the real key)
#   3. replace this comment with a kwriteconfig6 call using the CONFIRMED key
# Left undone on purpose — a guessed key (TerminalApplication/TerminalService are plausible from
# general KDE knowledge) could silently no-op or collide with an unrelated key.

# One initial paint so Plasma matches the theme ALREADY active in niri, the first time it's entered.
# bin/theme-switch keeps it converged after this. Best-effort: theming never fails the module.
THEME_NOW="$(current_theme)"
best_effort apply_plasma_theme "$THEME_NOW"

ok "Plasma desktop module done — pick 'Plasma' at the SDDM login screen to try it. niri is untouched."
