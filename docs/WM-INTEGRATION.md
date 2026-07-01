# WM integration — where Archfrican touches the compositor

Archfrican targets **niri**, but ~90% of the desktop (login, keyd, the bar/launcher/notification tools,
the theming engine's shared-tool outputs, ~41 of the `archfrican-*` helpers) is **compositor-agnostic** —
it runs unchanged under any Wayland compositor. This file is the single source of truth for the small
part that is **niri-specific**, so maintenance (and a future port to sway/Hyprland) is obvious.

See `docs/…`/the multi-compositor evaluation for the cost tiers of actually supporting more WMs. This
doc only maps the boundary; it does not add other compositors.

## A. Inherently niri (the WM itself — a different WM = a different artifact, not a shared abstraction)
| What | File | Note |
|---|---|---|
| The WM config: input, layout, window/layer rules, `spawn-at-startup` autostart, the `binds { … }` block | `home/dot_config/niri/config.kdl.tmpl` | niri KDL + its scrolling-tiler actions (`focus/move-column`, `consume/expel`, `set-column-width`). No 1:1 in Hyprland/sway. |
| Focus-ring theme fragment + its tokens | `templates/niri.theme.kdl`; `themes/tokens.defaults.sh` (`RADIUS_WINDOW`, `GAP_WINDOW`, `FOCUS_RING_WIDTH`) | Spliced into the config's `THEME-START/END` markers by theme-switch. |
| waybar workspace/window modules | `home/dot_config/waybar/config.jsonc` | `niri/workspaces`, `niri/window` (sway/Hyprland use `sway/*`, `hyprland/*`). |
| Install of the niri package + session | `modules/20-niri-desktop.sh` | Only the `niri` package + session are niri-specific; the rest of the module (SDDM, keyd, NetworkManager, audio, bluetooth, power) is generic desktop infra. |

## B. WM-IPC seams (the reusable boundary — one labelled place per file)
Every compositor call goes through a small **`wm_*` seam** defined near the top of each niri-tied helper
(grep `# ── WM seam`). To port a helper to another WM, change the seam body — nothing else in the file
speaks to the compositor.

| Helper (`home/dot_local/bin/executable_archfrican-*`) | Seam fn(s) | niri command behind it |
|---|---|---|
| `-layout` | `wm_action` | `niri msg action <tiling-action>` |
| `-session` | `wm_focus_workspace` | `niri msg action focus-workspace` |
| `-window` | `wm_windows_json`, `wm_focus_window` | `niri msg --json windows`, `niri msg action focus-window --id` |
| `-displays` | `wm_outputs_json`, `wm_validate` | `niri msg --json outputs`, `niri validate` |
| `-blur` | `wm_validate` | `niri validate` |

Two more niri touchpoints live in the installer libs (labelled inline, pointing here):
- `lib/health.sh` → `check_niri_config()` runs `niri validate` (RED health check: an invalid config makes
  niri silently fall back to defaults — no binds/bar/dock).
- `lib/common.sh` → `verify_spawns()` parses the niri KDL `spawn-at-startup "…"` lines to preflight that
  every autostart target is installed.

**Known duplication (intentional, for now):** the "replace text between `START/END` markers, with an
unbalanced-marker guard" awk pattern exists in **both** `bin/theme-switch` (`THEME-*`) and
`archfrican-displays` (`ARCHFRICAN-DISPLAYS-*`). A shared runtime library would DRY it, but that adds a
deployed dependency; the helpers are deliberately standalone, so it stays duplicated (labelled in both).

## What is WM-agnostic (runs under any compositor — do NOT niri-couple these)
keyd (`/etc/keyd/default.conf`, evdev-level) · the shared Wayland tools (waybar shell, fuzzel, swaync,
swayidle/lock, swayosd, awww, cliphist, ghostty, portals) · theme-switch's rendered outputs for those
tools (colors/CSS/INI) + GTK/Qt cohesion · SDDM session listing (auto-discovers every
`/usr/share/wayland-sessions/*.desktop`) · ~41 `archfrican-*` helpers that only run fuzzel menus / spawn
apps (spotlight, actions, calc, find, git, defaults, power, vpn, backup, …).

## To port to / add another compositor (checklist, if ever pursued)
1. A new WM config artifact (`home/dot_config/<wm>/…`) with equivalent binds + autostart + window rules +
   theme markers — this is bespoke design, not find-replace.
2. Swap the waybar workspace/window module names.
3. A per-WM focus-ring/theme fragment + re-tune the keyd `[meta+shift]` map to that WM's Shift binds.
4. Reimplement each `wm_*` seam body (niri → `hyprctl`/`swaymsg`); the helpers above then work unchanged.
5. A parallel `2X-<wm>-desktop.sh` module (the converge system already supports parallel modules) + a
   per-WM `check_<wm>_config` health check.