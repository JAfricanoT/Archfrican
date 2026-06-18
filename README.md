# Archfrican

A personal, fully-customizable Arch installer in the spirit of Omarchy — but built
around **niri** (scrolling tiling), a **macOS-friendly** UX for people migrating
off the Mac, and a hard requirement that **nothing explodes**.

> The project (and default hostname) is **archfrican** — rename the folder/repo freely if you fork it.

## Design principles

1. **Two layers, never mixed.** The *system* (Arch + packages) and the
   *configuration* (dotfiles) are separate, each with the right tool.
2. **Modular & swappable.** niri lives in exactly one module
   (`modules/20-niri-desktop.sh`) and its dotfiles. The day something better
   than niri shows up, you swap that module + one package list — nothing else
   changes.
3. **GPU-agnostic.** `lib/detect-gpu.sh` auto-detects AMD / Intel / NVIDIA /
   hybrid and installs the right stack. The same installer runs on any machine.
4. **Reliability first.** Btrfs + Snapper snapshots (rollback in one reboot),
   a dual kernel (linux-cachyos primary, **linux-lts** as a safety net), and
   zero fragile compositor plugins.

## What you get

| Layer        | Choice                                                        |
|--------------|---------------------------------------------------------------|
| Base         | Arch vanilla **+ CachyOS repos** (optimized pkgs + kernel)    |
| Filesystem   | Btrfs + Snapper + snap-pac + grub-btrfs                       |
| Kernel       | `linux-cachyos` (default) · `linux-lts` (fallback in GRUB)    |
| Compositor   | **niri** (isolated module) · greetd + tuigreet login          |
| GPU          | auto: `nvidia-open-dkms` / `vulkan-radeon` / `vulkan-intel`   |
| Shell        | Zsh + zinit + fast-syntax-highlighting + autosuggestions      |
| Prompt       | **Starship** (cross-shell — survives a shell swap)            |
| Terminal     | **Ghostty** (Kitty graphics protocol, blur, native Wayland)   |
| Editor       | Code-OSS (Wayland; Open VSX) — LSPs are system-level & editor-agnostic|
| Dev          | rustup · go · uv · fnm + gopls/rust-analyzer/pyright/ruff/clangd|
| Look         | macOS-like: WhiteSur GTK, SF fonts, niri blur (opt-in), fuzzel |
| Theming      | hot-swap switcher: `theme-switch <name>`                       |
| macOS keys   | `keyd` maps ⌘+C/V/X/Z/… → Ctrl, ⌘+Space → launcher            |

## Install

On a freshly-installed **base Arch** (install a minimal base with `archinstall`, then reboot),
run **one command** as your user:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/JAfricanoT/Archfrican/refs/heads/main/install.sh)"
```

It self-clones the repo to `~/.archfrican`, verifies the environment (preflight), runs a comfortable
wizard (hostname, user + password, timezone/locale/keyboard, theme, GPU), installs the niri desktop +
dev layer, and ends with a reboot prompt. Re-running is safe (idempotent; completed modules skipped);
run one module with `~/.archfrican/install.sh 30-dev`.

> Full install straight from the Arch ISO (disk + base + desktop in one shot) is coming in a
> VM-validated release — for now use the base-Arch one-liner above.

## Theming

```bash
theme-switch macos-dark        # default
theme-switch macos-light
theme-switch catppuccin-mocha
theme-switch tokyo-night
```
Switching is live for waybar, mako, niri borders and GTK (no logout); ghostty
repaints new windows and fuzzel applies on its next launch.
Add a theme by dropping a `themes/<name>/colors.sh` with the same variables.

## macOS muscle-memory (the real friction-killer)

`keyd` translates plain **⌘+letter** editing shortcuts to Ctrl system-wide, so
copy/paste/save/quit feel native. The ⌘ key still drives niri for **non-letter**
and **Shift** combos, so there's no collision:

- `⌘ + Space` → launcher (Spotlight)   ·   `⌘ + Tab` → overview (Mission Control)
- `⌘ + ←/→` → focus across the strip (`⌘ + Shift + ←/→` moves the column)   ·   3-finger swipe too
- `⌘ + C/V/X/Z/A/S/F/W/T/N/Q/L/R` → native Ctrl shortcuts   ·   `Caps` → Esc(tap)/Ctrl(hold)

## Layout

```
archfrican/
├── install.sh            # one entry (curl|sh): self-clone + detect + preflight + wizard + dispatch
├── archinstall/          # phase-1 base config (ISO)
├── lib/                  # common, detect-gpu, env, ui, preflight, host-config, phase2
├── modules/              # 00-base 10-gpu 20-niri-desktop 30-dev 40-theming 50-snapshots
├── packages/             # per-layer package lists (swap a list, not the script)
├── themes/               # palettes (one schema, many themes)
├── templates/            # per-app theme templates (pure-sed ${VAR})
├── bin/theme-switch      # live theme switcher
└── home/                 # chezmoi dotfiles source (niri, zsh, ghostty, …)
```

## Swapping the compositor later

1. Add `modules/2x-<new>.sh` + `packages/<new>-desktop.txt`.
2. Point `install.sh` at it.
3. Add its dotfiles under `home/dot_config/<new>/`.
Everything else (dev, theming, shell, GPU) is untouched.

## Caveats

- `archinstall`'s JSON schema changes between releases — review the TUI before
  committing the disk layout.
- NVIDIA on Wayland: reboot after phase 2 before the first niri session.
- WhiteSur on some Wayland apps can be imperfect; `nwg-look` lets you tweak.
