# ADL — the Archfrican Design Language: the NON-COLOUR identity (fonts, type scale, radius family,
# 4px spacing grid, motion, elevation/translucency). Colour lives in each theme's colors.sh; THIS is
# the shared default for shape/type/motion, sourced by theme-switch for EVERY theme (and the matugen
# 'dynamic' palette). A theme overrides only the deltas it wants via its own themes/<name>/tokens.sh
# (e.g. macos-* restore SF + 8/12/16; high-contrast kills translucency). These feed templates through
# the same ${TOKEN} substitution as colours — see docs/DESIGN-LANGUAGE.md.
#
# NOTE: this is a top-level file, not a themes/<dir>/ — the theme pickers glob themes/*/ (directories),
# so a subdir here would surface as a fake selectable theme.

# ── Type stack — identity = Inter everywhere + JetBrainsMono for mono/icons ────────────────────────
export FONT_DISPLAY="Inter"
export FONT_UI="Inter"
export FONT_MONO="JetBrainsMono Nerd Font"
export FONT_ICON="JetBrainsMono Nerd Font"

# ── Type scale (px) ────────────────────────────────────────────────────────────────────────────────
export FONT_SIZE_XS="11"        # tray / dim secondary labels
export FONT_SIZE_SM="12"        # captions, button labels
export FONT_SIZE_BASE="13"      # body / waybar / lists (the comfortable base)
export FONT_SIZE_MD="15"        # section / widget titles
export FONT_SIZE_LG="20"        # card headings, login username
export FONT_SIZE_XL="32"        # display
export FONT_SIZE_CLOCK="92"     # SDDM login clock
export FONT_WEIGHT_NORMAL="400"
export FONT_WEIGHT_MED="600"
export FONT_WEIGHT_BOLD="700"
export FONT_GTK_SIZE="11"       # numeric size for gtk-font-name

# ── Radius family (px) — signature progression 7/11/15 (vs macOS 8/12/16) ───────────────────────────
export RADIUS_SM="7"            # chips, close buttons, small toggles
export RADIUS_MD="11"           # buttons, list rows, inputs, notification cards
export RADIUS_LG="15"           # control-center / launcher / big cards / login card
export RADIUS_XL="20"           # largest floating surfaces / modal sheets
export RADIUS_PILL="999"        # switches, avatar, dot indicators
export RADIUS_WINDOW="12"       # niri geometry-corner-radius (harmonised with the 12px gap)

# ── Spacing — the 4px grid — and structural widths ──────────────────────────────────────────────────
export SPACE_XS="4"
export SPACE_SM="6"
export SPACE_MD="8"
export SPACE_LG="12"
export SPACE_XL="18"
export SPACE_2XL="24"
export GAP_WINDOW="12"          # niri layout gaps
export BORDER_WIDTH="1"         # hairline width
export FOCUS_RING_WIDTH="2"     # niri focus-ring

# ── Motion — the signature easing + durations (ms) ──────────────────────────────────────────────────
export MOTION_EASE_STANDARD="cubic-bezier(0.22,0.61,0.18,1.0)"   # confident, soft settle
export MOTION_EASE_DECEL="cubic-bezier(0.05,0.7,0.1,1.0)"        # entrances
export MOTION_DUR_FAST="120"
export MOTION_DUR_BASE="220"
export MOTION_DUR_SLOW="360"

# ── Elevation / translucency / frosted glass ────────────────────────────────────────────────────────
export OPACITY_BAR="0.85"       # waybar
export OPACITY_PANEL="0.96"     # control center / dense panels
export OPACITY_CARD="0.94"      # notification cards / launcher
export OPACITY_TERM="0.92"      # ghostty background-opacity
export ELEV_BORDER="0.22"       # alpha for 1px hairline borders
export BLUR_PASSES="3"
export BLUR_RADIUS="8"

# ── Focus-presence — the soft shadow on the focused window (the "Archfrican window") ────────────────
export SHADOW_SOFTNESS="30"
export SHADOW_SPREAD="5"
export SHADOW_OFFSET_X="0"
export SHADOW_OFFSET_Y="8"
export SHADOW_COLOR="#00000055"
