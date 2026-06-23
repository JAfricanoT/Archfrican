# Archfrican

[![CI](https://github.com/JAfricanoT/Archfrican/actions/workflows/ci.yml/badge.svg)](https://github.com/JAfricanoT/Archfrican/actions/workflows/ci.yml)
[![License: PolyForm-NC-1.0.0](https://img.shields.io/badge/license-PolyForm--NC--1.0.0-orange)](LICENSE)
[![Code of Conduct](https://img.shields.io/badge/Code%20of%20Conduct-Contributor%20Covenant%202.1-blueviolet)](CODE_OF_CONDUCT.md)

> **Source-available, noncommercial** — not an OSI "open source" license. See [License](#license--licencia).

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
| Compositor   | **niri** (isolated module) · **SDDM** graphical login (theme `archfrican`) |
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
dev layer, and ends with a reboot prompt. Re-running is safe and **convergent**: each module re-runs
only when its inputs change (content-hashed `.done`), so **updating an old install converges to the
same state as a fresh one**. Run one module with `~/.archfrican/install.sh 30-dev`.

Keep it current with one command — `archfrican-update` (report) / `--run` (snapshot → refresh →
converge → `pacman -Syu` → AUR, all reversible). See [docs/UPDATES.md](docs/UPDATES.md).

> Full install straight from the Arch ISO (disk + base + desktop in one shot) is coming in a
> VM-validated release — for now use the base-Arch one-liner above.

### Multi-boot (dual-boot)

Off by default. The wizard asks *"Share this machine with another OS already installed (multi-boot)?"* —
say yes and Archfrican enables GRUB's `os-prober` so an OS that's **already installed** (Windows or another
Linux, usually on a **second disk**) shows up in the GRUB menu — **without** losing the snapshot-rollback
submenu. Enable it later with `~/.archfrican/install.sh 55-multiboot yes`.

- It only **detects** an OS that's already there — it does **not** install-alongside / repartition / shrink.
- `os-prober` mounts other partitions as root, so it's opt-in (Arch disables it by default).
- A BitLocker-locked or hibernated/fast-startup Windows may not be detected — fully shut it down first.

*ES — Multi-boot (apagado por defecto):* el asistente pregunta si compartes el equipo con otro SO ya
instalado; al activarlo, `os-prober` lo añade al menú de GRUB **sin** perder el submenú de rollback por
snapshots. Solo **detecta** un SO ya presente (no instala-junto-a ni reparticiona). Un Windows con BitLocker
o hibernado puede no detectarse — apágalo del todo primero.

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
- `⌘ + Shift + V` → clipboard history   ·   `⌘ + Shift + K` → searchable shortcut cheatsheet
- `⌘ + Shift + A` → **command surface** (actions hub)   ·   `⌘ + Shift + W` → window switcher   ·   `⌘ + Shift + C` → calculator   ·   `⌘ + Shift + G` → file search

The **command surface** (`⌘ + Shift + A`, the launcher pushed toward Spotlight/Raycast) reaches every
setting and mode as a named verb: switch theme, check updates, set default apps, toggle blur/auto-dark,
**emoji** picker, **web search** with bang prefixes (`g`, `yt`, `w`, `aw`, `aur`, `gh`), calculator, and
local file search — all over the same fuzzel.

**Apps:** Flatpak + Flathub are set up out of the box (sandboxed GUI apps, browsable in `gnome-software`;
manage per-app permissions with **Flatseal**); a curated, declarative catalog lives in `flatpak/apps.txt`.
Pick a browser with `archfrican-browser` (**Brave** or **Vivaldi** — opt-in, none installed by default),
turn a URL into a dockable app with `archfrican-webapp`, and connect cloud/SMB storage with
`archfrican-cloud`. **Printing & scanning** work driverless (CUPS + SANE, auto-discovered on the network).

**Control center** (`⌘ + Shift + D`, or click the bar bell): swaync notifications + Quick-Settings
toggles (Wi-Fi, Bluetooth, dark/light, night light, displays) with a real Do-Not-Disturb. VPN via
`archfrican-vpn` (Tailscale or WireGuard/OpenVPN); pro-audio with EasyEffects (mic noise suppression
+ EQ) and a qpwgraph patchbay.

**Onboarding & identity:** the first login shows a gentle, optional welcome (`archfrican-welcome`)
that teaches the few Archfrican keys and offers the consequential toggles — and after a major update
it shows what changed. A **Migration Assistant** (`archfrican-migrate`) restores your dotfiles,
SSH/GPG keys and Flatpak app set from a backup or another machine, so you arrive already at home.
Plus a Snap-Layouts-style **layout picker** (`⌘ + Shift + T`), a project/**session** restorer, and a
distraction-free **focus** mode.

Desktop niceties: **Quick Look** — select a file in Files and press <kbd>Space</kbd> for a preview.
Handy commands: `archfrican-auto-appearance on` (auto light/dark by sun position) ·
`archfrican-blur on` (frosted-glass blur, `niri validate`-guarded so it can't break your config) ·
`archfrican-defaults` (set the default browser/mail the no-nag way). A privacy dot appears in the bar
whenever the mic or camera is in use.

## Layout

```
archfrican/
├── install.sh            # one entry (curl|sh): self-clone + detect + preflight + wizard + dispatch
├── archinstall/          # phase-1 base config (ISO)
├── lib/                  # common, ui, grub, detect-gpu, env, preflight, host-config, security, fido2, health, disk, phase1/2
├── modules/              # 00-base 10-gpu 20-niri-desktop 30-dev 40-theming 50-snapshots 55-multiboot 60-security
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

## Community / Contributing

Contributions are welcome under the project's [noncommercial license](LICENSE). Docs are bilingual (EN/ES):
[Vision](VISION.md) · [Contributing](CONTRIBUTING.md) · [Governance](GOVERNANCE.md) ·
[Code of Conduct](CODE_OF_CONDUCT.md) · [Security policy](SECURITY.md).

## License / Licencia

**Source-available, noncommercial.** Archfrican is licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE): anyone may use, modify, and share it for **noncommercial**
purposes, but **commercial use is not granted**. This is **not** an OSI "open source" license. Contributions
are accepted under the same license (inbound = outbound).

**Código disponible, no comercial.** Bajo [PolyForm Noncommercial 1.0.0](LICENSE): cualquiera puede usarlo,
modificarlo y compartirlo con fines **no comerciales**; **no se concede uso comercial**. No es una licencia
"open source" de la OSI.
