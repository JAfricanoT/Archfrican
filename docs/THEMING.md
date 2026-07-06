# Archfrican — Theming

Archfrican ships nine curated themes plus dynamic theming from any wallpaper image.
A theme swap affects every surface simultaneously — terminal, waybar, notifications,
GTK 3/4, Qt 5/6, VS Code, web apps, SDDM login screen — in under one second.

---

## Switching themes

```bash
theme-switch <name>
```

The selection is saved to `~/.config/.archfrican-theme` and restored on every
`archfrican-update --converge`.

From the desktop:

```
⌘+Shift+A   →   "Cambiar el tema"
```

or from the welcome tour:

```
archfrican-welcome   →   "Cambiar el tema"
```

---

## Available themes

| Name | Description |
|------|-------------|
| `adl-dark` | Archfrican Design Language — teal accent on deep graphite. The default. |
| `adl-light` | ADL light variant — teal on warm white. |
| `archfrican-dark` | Archfrican palette dark variant (warmer than adl-dark). |
| `archfrican-light` | Archfrican palette light variant. |
| `catppuccin-mocha` | [Catppuccin](https://catppuccin.com/) Mocha — mauve/lavender on dark brown. |
| `tokyo-night` | Tokyo Night — cyan on near-black with blue-purple accents. |
| `high-contrast` | Accessibility high-contrast — maximum legibility, no translucency. |
| `dynamic` | Wallpaper-generated Material You palette (see below). |

---

## Dynamic theming from a wallpaper

Generate the entire shell palette from any image using Material You (matugen):

```bash
archfrican-wallpaper /path/to/photo.jpg     # apply image + extract palette
archfrican-wallpaper                        # interactive path prompt
```

The command ships with five curated Archfrican wallpapers pre-installed in `/usr/share/backgrounds/archfrican/` 
and selectable from the picker out of the box, alongside custom images from your Pictures/Downloads folders.

The process:
1. Sets the wallpaper via awww
2. Extracts a Material You palette from the image (matugen)
3. Writes `~/.config/archfrican/dynamic-colors.sh`
4. Calls `theme-switch dynamic` to apply the palette

The generated palette lives in `~/.config/archfrican/` — not in the repo — so it
is user state and never causes convergence drift.

**Restore wallpaper after reboot**: the path is saved to `~/.config/archfrican/wallpaper`
and restored at login by `archfrican-wallpaper-restore`.

To revert to a static theme after dynamic theming, just run any named theme:

```bash
theme-switch adl-dark
```

**Requirements**: `matugen` and `jq` (installed by the niri-desktop module).

---

## App cohesion (Tier B)

Third-party apps that ignore GTK/Qt settings — VS Code and Chromium-based web apps —
are kept in sync with the active theme through the cohesion layer.

Cohesion is on by default. To toggle:

```bash
archfrican-cohesion on      # re-enable and apply to VS Code
archfrican-cohesion off     # disable; restores VS Code to its pre-cohesion backup
archfrican-cohesion status  # print "on" or "off"
```

VS Code settings are **backed up** before the first cohesion write (to
`~/.config/Code/User/settings.json.archfrican.bak`) and fully restored by `off`.

**What Tier B covers**: VS Code color customizations, Chromium web-app instances.
**What Tier A covers**: GTK 3/4, Qt 5/6, fonts, cursor, icons, waybar, swaync,
fuzzel, Walker launcher, gtklock, ghostty, niri borders, SDDM, GRUB boot menu (palette
change visible next boot — no `grub-mkconfig` required). Tier A is always active in `theme-switch`.

See [COHESION.md](COHESION.md) for the full Tier-A/B architecture.

---

## Creating a custom theme

Each theme is a directory under `themes/` with a single required file:

```
themes/
└── my-theme/
    ├── colors.sh       # required — color tokens
    └── tokens.sh       # optional — shape/type/motion overrides
```

### Step 1 — Define colors

Copy `themes/adl-dark/colors.sh` as a starting point. Export the full set of color
tokens that `theme-switch` expects:

```bash
# themes/my-theme/colors.sh
export GTK_SCHEME="prefer-dark"
export GTK_THEME="WhiteSur-Dark"
export ICON_THEME="WhiteSur-dark"

export BG="#1c1c1e"         # main background
export BG_ALT="#2c2c2e"     # secondary surface
export BG_DIM="#3a3a3c"     # tertiary / hover surface
export FG="#f5f5f7"         # primary text
export FG_DIM="#8e8e93"     # secondary / disabled text

export ACCENT="#20b2aa"     # your brand accent color
export RED="#ff5555"        # semantic red (errors, destructive)
export GREEN="#50fa7b"
export YELLOW="#f1fa8c"
export BLUE="#8be9fd"
export MAGENTA="#ff79c6"
export CYAN="#80ffea"

export BORDER_ACTIVE="$ACCENT"
export BORDER_INACTIVE="$BG_DIM"
```

### Step 2 — Override shape/type tokens (optional)

`themes/tokens.defaults.sh` defines the shared non-color identity (Inter font, 7/11/15
radius family, 4 px grid, motion). Your theme only needs to override what differs:

```bash
# themes/my-theme/tokens.sh  — only needed if you deviate from the defaults
export FONT_DISPLAY="SF Pro Display"
export FONT_UI="SF Pro Text"
export RADIUS_SM="8"
export RADIUS_MD="12"
export RADIUS_LG="16"
```

The `macos-*` themes use this to restore SF fonts and Apple-style radii.
The `high-contrast` theme uses it to disable translucency tokens.

### Step 3 — Test it

```bash
theme-switch my-theme
```

If `themes/my-theme/` exists, `theme-switch` finds it automatically — no registration
needed. To verify it appears in the welcome picker and cohesion layer, run:

```bash
archfrican-welcome   →   "Cambiar el tema"
```

Your theme appears in the fuzzel list alongside the built-in themes.

---

## How theme-switch works internally

`theme-switch` is a pure bash/sed pipeline:

1. Sources `themes/tokens.defaults.sh` (shared shape/type/motion)
2. Sources `themes/<name>/colors.sh` (color tokens)
3. Sources `themes/<name>/tokens.sh` if present (shape/type overrides)
4. Renders every `*.tmpl` config in `$HOME/.config/` via `${TOKEN}` substitution
5. Sends `SIGUSR2` to waybar (live color reload)
6. Calls `swaync-client --reload-config`
7. Calls `archfrican-cohesion apply` (VS Code + web-app sync)
8. Writes `~/.config/.archfrican-theme` (persistence)

The template substitution is the key mechanism — every config file that should respond
to theme changes has a `.tmpl` source with `${BG}`, `${ACCENT}`, `${FONT_MONO}` etc.
placeholders. `theme-switch` renders these into the live config files.

For the full token catalog and template authoring guide, see
[DESIGN-LANGUAGE.md](DESIGN-LANGUAGE.md).

---

## Auto dark/light by time of day

To switch between dark and light automatically based on sunrise/sunset:

```bash
archfrican-auto-appearance on
```

This enables a user systemd timer that runs `theme-switch adl-dark` at sunset and
`theme-switch adl-light` at sunrise based on your locale.

To disable:

```bash
archfrican-auto-appearance off
```
