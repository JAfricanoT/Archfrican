# Archfrican — First Steps

What to do when the installer finishes and you see the desktop for the first time.

---

## 1. Welcome tour

On first boot `archfrican-welcome` launches automatically and offers a menu-driven tour.
Every item is optional — you can skip and come back any time.

To relaunch it:

```
⌘+Shift+A   →   "Bienvenida"
```

or directly:

```bash
archfrican-welcome          # shows changelog if post-update, then the menu
archfrican-welcome --tour   # forces the full tour regardless of state
```

After each system update the welcome hub shows a changelog of what changed since your
last visit. To dismiss: just run through the menu once.

---

## 2. Essential shortcuts

Archfrican maps `⌘` (Super/Win key) as the compositor modifier. keyd re-maps `⌘+letters`
to the expected macOS-style app shortcuts (copy/paste/quit/etc.) inside every app.
The cheat sheet is always one key away:

```
⌘+Shift+K       searchable key reference (archfrican-keys)
```

**Core shortcuts**

| Shortcut | Action |
|----------|--------|
| `⌘+Space` | Spotlight launcher (Walker) — apps, files, web, calc, clipboard |
| `⌘+Return` | New terminal (Ghostty) |
| `⌘+W` | Close window |
| `⌘+Q` | Quit app (closes every window of the focused app) |
| `⌘+Tab` | Mission-Control overview of all workspaces |
| `⌘+Shift+A` | Actions hub — all Archfrican commands in one place |
| `⌘+Shift+K` | Key cheat sheet |
| `⌘+Shift+V` | Clipboard history picker |
| `⌘+Shift+N` | File manager (Nautilus) |
| `⌘+Shift+Y` | TUI file manager (yazi) |
| `⌘+Shift+B` | System monitor (btop) |
| `⌘+Shift+W` | Window switcher |
| `⌘+Shift+D` | Control center / notifications |
| `⌘+Shift+T` | Layout / snap-layout picker |
| `⌘+Shift+C` | Calculator |
| `⌘+Shift+G` | File search |
| `⌘+Shift+L` | Lock screen |
| `⌘+Shift+S` | Screenshot (region) |
| `⌘+Shift+R` | Screen record toggle |
| `⌘+Alt+S` | Screen reader (Orca) |

**Window / layout shortcuts**

| Shortcut | Action |
|----------|--------|
| `⌘+← / →` | Focus column left/right (niri scroll model) |
| `⌘+↑ / ↓` | Focus window up/down in column (or cross to next workspace at edge) |
| `⌘+Shift+← / →` | Move column |
| `⌘+Shift+↑ / ↓` | Move window up/down in column (or to adjacent workspace) |
| `⌘+Shift+F` | Maximize column |
| `⌘+Shift+M` | Fullscreen |
| `⌘+Shift+Space` | Toggle floating |
| `⌘+,` | Pull window into column (stack) |
| `⌘+.` | Expel window from column |
| `⌘+− / =` | Resize column ±10% |
| `⌘+1…5` | Jump to workspace 1–5 |
| `⌘+Shift+1…3` | Move column to workspace |

**Multi-monitor shortcuts** (when two or more screens are connected)

| Shortcut | Action |
|----------|--------|
| `⌘+Ctrl+← / → / ↑ / ↓` | Focus the monitor in that direction |
| `⌘+Ctrl+Shift+← / → / ↑ / ↓` | Move column to monitor in that direction |
| `⌘+Ctrl+Alt+← / → / ↑ / ↓` | Move entire workspace to monitor in that direction |

---

## 3. Connect to WiFi

If you installed from the ISO, WiFi credentials were copied automatically and the
network should be live. To add or change networks:

```bash
nmtui                    # TUI — works in the terminal
nm-connection-editor     # GUI editor (⌘+Space → "Red" or "nm-connection")
archfrican-net-status    # quick connection summary in the terminal
```

For Enterprise/WPA2-EAP or eduroam networks, `nm-connection-editor` is the most
reliable path.

---

## 4. Install a browser

No browser ships by default — the choice is yours. Install one with:

```bash
archfrican-browser              # interactive fuzzel picker
archfrican-browser brave        # Brave (built-in ad blocking, lightweight)
archfrican-browser vivaldi      # Vivaldi (tab stacking, hibernation)
```

After installation the chosen browser is set as the system default via `xdg-settings`.

For Mullvad Browser (privacy-first, Tor-compatible):

```bash
⌘+Shift+A   →   "Mullvad Browser"
```

---

## 5. Switch or customize the theme

```bash
theme-switch adl-dark           # default: Archfrican dark
theme-switch adl-light          # light variant
theme-switch archfrican-dark    # owned identity, dark
theme-switch archfrican-light   # owned identity, light
theme-switch catppuccin-mocha   # Catppuccin Mocha
theme-switch tokyo-night        # Tokyo Night
theme-switch high-contrast      # accessibility high-contrast
```

The theme applies live across every surface — terminal, waybar, notifications, GTK/Qt,
VS Code, web apps — in under one second. The selection is saved across reboots.

**Wallpaper + dynamic theming** — generate the palette from any image:

```bash
archfrican-wallpaper /path/to/photo.jpg     # extracts Material You palette
archfrican-wallpaper                        # interactive image picker
```

After setting a wallpaper, `theme-switch dynamic` re-applies the generated palette.
To revert to a static theme, just run `theme-switch <name>` again.

See [THEMING.md](THEMING.md) for available themes and how to create a custom one.

**Boot & disk-unlock polish (optional, not installed by default)** — the install does not
automatically theme the disk-encryption prompt or enroll TPM auto-unlock. Two opt-in commands
add that, each needing one more reboot of its own to take effect:

```bash
archfrican-plymouth      # themed boot splash so the LUKS passphrase prompt matches the login/desktop look
archfrican-tpm-unlock    # enroll the TPM so a correct BIOS/firmware state unlocks the disk with no passphrase
```

Keep your passphrase on hand for the reboot right after either one — until it's confirmed
working, that reboot is your only way back in.

---

## 6. Configure backups

Run this once to set up encrypted, deduplicated home directory backups:

```bash
archfrican-backup init          # pick destination + generate password
archfrican-backup schedule      # create a daily systemd user timer
```

Destination options:

```
/run/media/you/USB/backup       # external drive
/mnt/nas/backups                # NAS
rclone:gdrive:backups           # Google Drive via rclone
```

The encryption password is saved to `~/.config/archfrican/restic-pass` (mode 600).
**Back this file up separately** — without it, the backup is unreadable.

After setup, verify it works:

```bash
archfrican-backup now           # run a backup immediately
archfrican-backup list          # list snapshots
```

---

## 7. Maintenance

Check system health (read-only — nothing changes):

```bash
archfrican-doctor               # full health report
archfrican-doctor --json        # waybar widget output
```

Run a full update (snapshot → pull → converge → package upgrade):

```bash
archfrican-update               # dry-run: shows what would change
archfrican-update --run         # full update with pre-snapshot safety net
```

**When to update**: run `archfrican-update --run` any time you want the latest
packages and configuration. The pre-snapshot means you can always roll back with
`archfrican-rollback` if something breaks.

To re-apply only configuration and dotfiles without upgrading packages:

```bash
archfrican-update --converge
```

---

## 8. Migrate from another machine

If you have an existing machine (Mac or Linux) with dotfiles, SSH/GPG keys, and apps:

```bash
archfrican-migrate              # interactive menu
archfrican-migrate do_dotfiles  # chezmoi init --apply <your-dotfiles-repo>
archfrican-migrate do_keys      # copy .ssh and .gnupg (no-clobber)
archfrican-migrate do_apps      # install Flatpak apps from apps.txt
```

Each operation is idempotent — safe to re-run if interrupted.

For KDE Connect (phone ↔ desktop clipboard, notifications, files):

```bash
⌘+Shift+A   →   "Continuidad / KDE Connect"
```

---

## Quick reference

| Task | Command |
|------|---------|
| All shortcuts | `⌘+Shift+K` |
| Actions hub | `⌘+Shift+A` |
| Add WiFi network | `nmtui` |
| Install browser | `archfrican-browser` |
| Change theme | `theme-switch <name>` |
| Set wallpaper | `archfrican-wallpaper` |
| System health | `archfrican-doctor` |
| Full update | `archfrican-update --run` |
| Roll back update | `archfrican-rollback` |
| Configure backups | `archfrican-backup init` |
| Migrate from old machine | `archfrican-migrate` |
| Welcome tour | `archfrican-welcome` |
