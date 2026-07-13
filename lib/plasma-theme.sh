#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/token vars (BG, FG, ACCENT, FONT_UI, …) are sourced by the caller
# The Plasma paint, shared by lib/common.sh (apply_plasma_theme) and bin/theme-switch.
# Self-contained on purpose: bin/theme-switch sources JUST this file from the deployed
# clone ($ROOT/lib/plasma-theme.sh) — same pattern bin/archfrican-update uses for its libs —
# so the single copy serves both the installer and live switches, and the pending BreezeDark
# format verification below is a one-file fix.
#
# Caller contract: kwriteconfig6 exists (the caller gates on it — its absence is a reliable
# "Plasma isn't installed" signal), and the palette/token cascade is already sourced:
#   BG FG ACCENT [BG_ALT BG_DIM FG_DIM ACCENT_FG] ICON_THEME CURSOR_THEME CURSOR_SIZE
#   FONT_UI FONT_MONO FONT_GTK_SIZE

plasma_hex2rgb() { local h="${1#\#}"; printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }

plasma_paint() {
  mkdir -p "$HOME/.local/share/color-schemes"
  cat > "$HOME/.local/share/color-schemes/Archfrican.colors" <<CLR
[General]
Name=Archfrican
ColorScheme=Archfrican

[Colors:Window]
BackgroundNormal=$(plasma_hex2rgb "$BG")
ForegroundNormal=$(plasma_hex2rgb "$FG")

[Colors:View]
BackgroundNormal=$(plasma_hex2rgb "${BG_ALT:-$BG}")
ForegroundNormal=$(plasma_hex2rgb "$FG")

[Colors:Button]
BackgroundNormal=$(plasma_hex2rgb "${BG_ALT:-$BG}")
ForegroundNormal=$(plasma_hex2rgb "$FG")

[Colors:Selection]
BackgroundNormal=$(plasma_hex2rgb "$ACCENT")
ForegroundNormal=$(plasma_hex2rgb "${ACCENT_FG:-#ffffff}")

[WM]
activeBackground=$(plasma_hex2rgb "$BG")
activeForeground=$(plasma_hex2rgb "$FG")
inactiveBackground=$(plasma_hex2rgb "${BG_DIM:-$BG}")
inactiveForeground=$(plasma_hex2rgb "${FG_DIM:-$FG}")
CLR
  # UNVERIFIED .colors format (drafted from the public KDE color-scheme spec — Plasma isn't
  # installed on the machine this was written on). Diff against a real
  # /usr/share/color-schemes/BreezeDark.colors once Plasma is installed and correct if needed.
  # `|| true` on every call below: callers run under `set -e` (lib/common.sh's subshell,
  # theme-switch top level), and a nonzero exit (a timed-out D-Bus call, a locked config file)
  # would otherwise abort mid-sequence, silently skipping every step after the first failure.
  { command -v plasma-apply-colorscheme >/dev/null 2>&1 \
      && timeout 5 plasma-apply-colorscheme Archfrican >/dev/null 2>&1; } || true

  timeout 5 kwriteconfig6 --file kdeglobals --group Icons   --key Theme "$ICON_THEME"          2>/dev/null || true
  timeout 5 kwriteconfig6 --file kcminputrc --group Mouse   --key cursorTheme "$CURSOR_THEME"  2>/dev/null || true
  timeout 5 kwriteconfig6 --file kcminputrc --group Mouse   --key cursorSize  "$CURSOR_SIZE"   2>/dev/null || true
  timeout 5 kwriteconfig6 --file kdeglobals --group General --key font  "$FONT_UI,$FONT_GTK_SIZE,-1,5,50,0,0,0,0,0"   2>/dev/null || true
  timeout 5 kwriteconfig6 --file kdeglobals --group General --key fixed "$FONT_MONO,$FONT_GTK_SIZE,-1,5,50,0,0,0,0,0" 2>/dev/null || true

  # Wallpaper: needs a running Plasma session to know which containment/screen to paint — its
  # behavior with no Plasma session ever started (fresh opt-in) is unverified.
  if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    local img=""
    if [ -r "$HOME/.config/archfrican/wallpaper" ]; then
      img="$(head -1 "$HOME/.config/archfrican/wallpaper" 2>/dev/null)" || true
    fi
    { [ -n "$img" ] && [ -r "$img" ]; } || img=""
    if [ -z "$img" ] && command -v convert >/dev/null 2>&1; then
      img="$HOME/.local/state/archfrican/plasma-bg.png"; mkdir -p "$(dirname "$img")" || true
      timeout 5 convert -size 64x64 "xc:$BG" "$img" 2>/dev/null || img=""
    fi
    if [ -n "$img" ]; then timeout 5 plasma-apply-wallpaperimage "$img" >/dev/null 2>&1 || true; fi
  fi
  return 0
}
