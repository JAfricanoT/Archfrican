# Archfrican Design Language (ADL)

The contract that makes everything feel *designed for Archfrican* instead of a bag of independent
apps. One source of truth → every surface. This is the Human Interface Guidelines: read it before
adding or restyling anything.

## Philosophy

- **Hybrid identity.** Familiar, comfortable ergonomics (the niri scrolling model, ⌘-style
  shortcuts) wearing an *original* Archfrican skin — a signature teal on warm graphite, not a macOS
  clone.
- **Homogeneity is the paradigm.** The thing that makes Archfrican feel "outside the paradigms" is
  that *everything* — shell, GTK, Qt, Electron, web-apps — looks and behaves like one system, to a
  degree most desktops never reach. Cohesion is the feature.
- **The system = the repo, applied.** Identity lives in version-controlled tokens; `theme-switch`
  renders them onto every surface. Nothing is hand-painted per app.
- **Nothing explodes.** Every token has a fallback; every app-level change is graceful and
  reversible.

## Where the identity lives

Three layers, sourced by `bin/theme-switch` as a cascade (later wins):

1. **`themes/tokens.defaults.sh`** — the shared NON-colour identity (fonts, type scale, radius,
   spacing, motion, elevation, cursor, accent-contrast fallback). The base layer.
2. **`themes/<name>/colors.sh`** — the theme's colour palette (the 17 colour vars + `ACCENT_FG`).
   Overrides the defaults.
3. **`themes/<name>/tokens.sh`** *(optional)* — per-theme shape/type overrides (e.g. `macos-*`
   restore SF fonts + 8/12/16 radii; `high-contrast` kills translucency/blur). Wins last.

`theme-switch` derives the substitution set by grepping every `${TOKEN}` under `templates/`, so a
token only needs to *exist in a template* to flow through the same render path as colour. Because the
defaults are the base layer, the matugen **`dynamic`** palette (colours only) inherits every
non-colour token for free — no template token is ever left unrendered.

> The defaults file is a top-level file, **not** a `themes/<dir>/`, because the theme pickers
> (`archfrican-welcome`, `archfrican-actions`) glob `themes/*/` and a subdir would show up as a fake
> theme.

## Colour

The 17 palette vars: `GTK_SCHEME GTK_THEME ICON_THEME`, `BG BG_ALT BG_DIM`, `FG FG_DIM`, `ACCENT`,
`RED GREEN YELLOW BLUE MAGENTA CYAN`, `BORDER_ACTIVE BORDER_INACTIVE` — plus **`ACCENT_FG`** (readable
text/icon colour ON the accent; the bright teal needs dark text, so it is per-theme).

- **Default identity** = `adl-dark` (teal `#2dd4bf` on warm graphite `#17181b`) and its pair
  `adl-light` (teal `#0d9488` on warm paper `#faf9f6`). Selectable alternatives: `macos-dark`,
  `macos-light`, `catppuccin-mocha`, `tokyo-night`, `high-contrast`.
- **Accent is used sparingly** — focus, selection, active/hover states. It is the teal *thread* that
  ties shell and apps together; do not flood surfaces with it.
- **Light / dark / high-contrast** must all work. `darkman` auto-switches light↔dark *within* the
  identity family. `high-contrast` forces `OPACITY_*=1.0`, `BLUR_*=0`, thicker borders.

## Typography — `FONT_*`

| Token | Value (ADL) | Use |
|---|---|---|
| `FONT_DISPLAY` / `FONT_UI` | `Inter` | everything UI/display (max comfort, one family) |
| `FONT_MONO` / `FONT_ICON` | `JetBrainsMono Nerd Font` | terminal, code, bar/launcher glyphs |

Type scale (px): `FONT_SIZE_XS 11 · SM 12 · BASE 13 · MD 15 · LG 20 · XL 32 · CLOCK 92`.
Weights: `FONT_WEIGHT_NORMAL 400 · MED 600 · BOLD 700`. GTK numeric size: `FONT_GTK_SIZE 11`.
System-wide fallback chain (fontconfig): identity font → Inter → JetBrainsMono → Noto, so even an
unconfigured app inherits the stack and a missing AUR font degrades cohesively.

## Shape — `RADIUS_*`

The signature progression is **7 / 11 / 15** (deliberately one px tighter than macOS's 8/12/16).

| Token | px | Use |
|---|---|---|
| `RADIUS_SM` | 7 | chips, close buttons, small toggles |
| `RADIUS_MD` | 11 | buttons, list rows, inputs, notification cards |
| `RADIUS_LG` | 15 | control-center, launcher, big cards, login card |
| `RADIUS_XL` | 20 | largest floating surfaces / sheets |
| `RADIUS_PILL` | 999 | switches, avatar, dots |
| `RADIUS_WINDOW` | 12 | niri `geometry-corner-radius` (harmonised with the 12px gap) |

## Spacing — `SPACE_*` (the 4px grid)

`SPACE_XS 4 · SM 6 · MD 8 · LG 12 · XL 18 · 2XL 24`. Structural: `GAP_WINDOW 12`,
`BORDER_WIDTH 1`, `FOCUS_RING_WIDTH 2`.

## Motion — `MOTION_*`

Signature easing `cubic-bezier(0.22,0.61,0.18,1.0)` (confident, soft settle); entrances
`MOTION_EASE_DECEL`. Durations: `FAST 120 · BASE 220 · SLOW 360` (ms).

## Elevation / translucency / cursor

`OPACITY_BAR .85 · PANEL .96 · CARD .94 · TERM .92`, `ELEV_BORDER .22` (hairline alpha),
`BLUR_PASSES 3 / BLUR_RADIUS 8` (frosted glass, opt-in via `archfrican-blur`). Focus-presence shadow:
`SHADOW_SOFTNESS/SPREAD/OFFSET_*/COLOR`. One pointer everywhere: `CURSOR_THEME`, `CURSOR_SIZE`.

## Do / Don't

- **Don't** hardcode a colour, font, radius or duration in a config. **Do** reference a `${TOKEN}`.
- **Don't** invent a new radius/size. **Do** pick the nearest existing token.
- **Don't** flood a surface with the accent. **Do** reserve it for focus/selection/active.
- **Don't** add a token to a template without a value in `tokens.defaults.sh` (or every palette),
  or `theme-switch` aborts under `set -u` / leaves a stray `${TOKEN}` and CI fails.

## How to make a new app feel "designed for Archfrican"

The recipe that scales cohesion to any app:

1. Split the app's static config from a small generated partial that references `${TOKEN}`s
   (e.g. `templates/<app>.tokens.css`).
2. Drop the partial in `templates/` — `theme-switch` auto-discovers its tokens.
3. Add a `render <partial> <~/.config/...>` line to `bin/theme-switch`, and have the app's static
   config `@import`/`include`/splice the generated file.
4. Add the generated output to `home/.chezmoiignore` (theme-switch is its sole writer).
5. Extend the `theme-switch-smoke` CI job: add the new file to the snapshot + the stray-`${TOKEN}`
   grep so every theme is proven to render it cleanly.

For apps that ignore GTK/Qt settings entirely (Electron, Chromium web-apps) see
[COHESION.md](COHESION.md) — they go through the opt-in `archfrican-cohesion` layer.

## Honest limits

- **Qt accent palette** (teal inside Qt's colour roles, via a qt6ct colorscheme or Kvantum) is
  deferred to hardware validation — the role order can't be verified statically. The Qt baseline
  (Fusion + ADL icons + portal dark + Inter via fontconfig) is in place and graceful.
- **libadwaita** honours the accent + colours but not arbitrary radius/spacing — full internal
  re-skin of GTK4 apps is not a goal.
- Nothing here has been hardware-validated yet; every mechanism is statically checked and degrades
  gracefully.
