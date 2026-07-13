# Archfrican — Command Reference

All user-facing CLI tools available after installation. Every command is in `$PATH`;
most are interactive by default — a native Walker menu when the launcher stack is up,
the same menu rendered in fuzzel otherwise — and accept subcommands for scripting.

---

## archfrican-update

Bring the system to desired state and upgrade packages under a pre-snapshot.

```
archfrican-update [--run] [--converge] [--prune] [--no-aur] [--notify] [-h]
```

| Mode | What it does |
|------|-------------|
| *(no flags)* | Read-only pre-check: drift report + warnings. Nothing changes. |
| `--run` | Full pipeline: snapshot → repo pull → migrations → converge → `pacman -Syu` → AUR |
| `--converge` | Re-apply config/dotfiles only (no package upgrade, no snapshot) |
| `--prune` | Offer to remove Archfrican-managed packages no longer in the repo |
| `--no-aur` | Skip AUR phase when combined with `--run` |
| `--notify` | Silent unless origin has new commits; sends a notification whose "Update now" action runs `--run` (meant for `archfrican-update-check.timer`, hourly) |

**Environment variables**

| Variable | Default | Description |
|----------|---------|-------------|
| `ARCHFRICAN_REF` | `main` | Git branch/tag to track |

**What `--run` does step by step**

1. Pre-checks: disk space (root ≥3 GB, boot ≥100 MB), mirrorlist age, CVE status
2. Pre-snapshot via snapper (description includes current commit SHA)
3. `git fetch --depth 1 origin $ARCHFRICAN_REF && git reset --hard FETCH_HEAD`; run pending migrations
4. Mirrorlist refresh (via `reflector`) if the current list is older than 7 days
5. `sudo pacman -Syu` (interactive; never `--noconfirm`) — **upgrade first** so new packages are available
6. Re-converge only modules whose content hash changed (installs against the already-upgraded system)
7. AUR upgrade via paru (failures don't block the system upgrade)
8. Grouped changelog of what changed (commit subjects from the pulled range)
9. `archfrican-doctor` health summary

**Examples**

```bash
archfrican-update               # see what would change (safe, read-only)
archfrican-update --run         # full upgrade with snapshot safety net
archfrican-update --converge    # re-apply dotfiles only (faster than --run)
archfrican-update --run --no-aur  # upgrade system packages, skip AUR
archfrican-update --prune       # review and remove orphaned managed packages
```

---

## archfrican-doctor

System health monitor. Runs 22 checks across disk, services, packages, security,
and Archfrican config. Safe to run anytime — never modifies the system except with `--fix`.

```
archfrican-doctor [--json] [--notify] [--fix]
```

| Mode | Output | Exit code |
|------|--------|-----------|
| *(no flags)* | Human-readable report with colored status lines | Count of critical+warning issues (0 = healthy) |
| `--json` | `{"text":"N","class":"ok\|amber\|red","tooltip":"…"}` — for waybar | 0 always |
| `--notify` | Silent unless problems exist; sends a desktop notification | 0 always |
| `--fix` | Runs only provably-safe maintenance (paccache, reset-failed, pacdiff list) | 0 always |

**Environment variables**

| Variable | Default | Description |
|----------|---------|-------------|
| `ARCHFRICAN_HEALTH_TTL` | `3600` | Cache duration for `--json` output (seconds; 0 disables) |

**Waybar integration** — add to `~/.config/waybar/config.jsonc`:

```json
"custom/health": {
  "exec": "archfrican-doctor --json",
  "return-type": "json",
  "interval": 1800,
  "on-click": "ghostty -e archfrican-doctor"
}
```

**What it checks**

- Failed systemd units (system + user)
- Journal errors since boot
- Disk space (/ and /boot)
- Snapper snapshot count
- Btrfs scrub status
- SMART disk health
- EFI boot entries (Archfrican + fallback)
- Multi-boot GRUB detection
- Orphan packages, pending .pacnew configs
- Available system updates
- Arch CVE audit (`arch-audit`)
- Firmware updates (`fwupd`)
- Kernel mismatch (reboot required)
- AUR packages (informational)
- Maintenance timers (paccache, fstrim, btrfs-scrub, archfrican-health)
- Config module drift (content hash vs `.done` stamps)
- Pending migrations
- Niri config validity (`niri validate`)
- Desktop stack presence (niri, waybar, swaync, ghostty, keyd…)
- Archfrican CLI tools on PATH
- Unrendered `${TOKEN}` in config files
- keyd service status

---

## archfrican-rollback

Undo the last update by picking a snapper checkpoint. Surfaces the Btrfs snapshot
safety net as a single interactive command.

```
archfrican-rollback
```

Interactive — shows a fuzzel list of snapper snapshots with date and description
(descriptions include the git commit SHA from `archfrican-update --run`).
After selection: confirms, runs `sudo snapper -c root rollback <N>`, and offers
immediate reboot or defer.

**Manual alternative**: reboot → hold Shift at GRUB → Archfrican Snapshots submenu.

---

## archfrican-backup

Encrypted, deduplicated home directory backup with restic.

```
archfrican-backup [menu|init|now|list|restore|schedule]
```

| Subcommand | What it does |
|------------|-------------|
| *(no args)* or `menu` | Interactive fuzzel menu of all options |
| `init` | Configure backup destination + generate encryption password |
| `now` | Run backup immediately |
| `list` | List all snapshots interactively |
| `restore` | Show restore command (`restic restore latest --target ~/restaurado`) |
| `schedule` | Create systemd user timer for daily backups (30-min random delay) |

**Configuration files**

| File | Content |
|------|---------|
| `~/.config/archfrican/restic-repo` | Backup destination path or rclone remote |
| `~/.config/archfrican/restic-pass` | Encryption password (mode 600; back this up separately) |

**Destination examples**

```bash
/run/media/user/USB/backup     # external USB drive
/mnt/nas/backups               # NAS mount
rclone:gdrive:backups          # Google Drive via rclone
```

**Restore manually**

```bash
export RESTIC_REPOSITORY="$(cat ~/.config/archfrican/restic-repo)"
export RESTIC_PASSWORD_FILE=~/.config/archfrican/restic-pass
restic restore latest --target ~/restaurado
```

---

## archfrican-migrate

Arrive at a new machine pre-personalized: restore dotfiles, SSH/GPG keys, and
Flatpak apps from a backup or another machine.

```
archfrican-migrate [menu|do_dotfiles|do_keys|do_apps]
```

| Subcommand | What it does |
|------------|-------------|
| *(no args)* or `menu` | Interactive fuzzel menu |
| `do_dotfiles` | `chezmoi init --apply <url>` from your dotfiles git repo |
| `do_keys` | Copy `$backup/.ssh` and `$backup/.gnupg` to `$HOME` (no-clobber) |
| `do_apps` | Install all Flatpak apps from `flatpak/apps.txt` |

Each operation is idempotent — safe to re-run.

---

## archfrican-welcome

Guided onboarding tour. Teaches Archfrican-specific shortcuts and consequential
toggles. Post-update: shows a changelog of what changed since last visit.

```
archfrican-welcome [--tour]
```

| Flag | Behavior |
|------|----------|
| *(no flags)* | Shows changelog (if post-update) then offers the full menu |
| `--tour` | Forces the full tour regardless of onboarding state |

**State file**: `~/.local/state/archfrican/onboarded-rev` (last visited git SHA)

Access via: `⌘+Shift+A → "Bienvenida/tour"` or run directly.

---

## archfrican-browser

Install and set a default browser. Archfrican ships with no browser by design
(opt-in choice is yours).

```
archfrican-browser [brave|vivaldi]
```

| Arg | Browser | Notes |
|-----|---------|-------|
| *(no args)* | Interactive fuzzel picker | |
| `brave` | Brave Browser | Lightweight, built-in ad blocking |
| `vivaldi` | Vivaldi | Tab stacking, hibernation for many tabs |

Both install from AUR via paru and set themselves as the default via `xdg-settings`.

---

## archfrican-session

Launch a saved project/workspace session: open apps on declared niri workspaces
in one command.

```
archfrican-session [<name>]
```

| Arg | Behavior |
|-----|----------|
| *(no args)* | Interactive fuzzel list of saved sessions |
| `<name>` | Launch session file `~/.config/archfrican/sessions/<name>.session` |

**Session file format** (`~/.config/archfrican/sessions/dev.session`):

```
# workspace  command
1            firefox
2            code ~/project
3            ghostty
```

Lines starting with `#` are ignored. Commands are daemonized with `setsid`.
See `~/.config/archfrican/sessions/dev.session.example` for a complete example.

---

## archfrican-project

Project-jumper: an ad-hoc, zero-config counterpart to `archfrican-session` — a fuzzel
picker over zoxide's frecency database (whatever directories you've actually `cd`'d
into), not a hand-authored session file. Opens a new `ghostty` terminal there.
**Keyboard shortcut**: `⌘+Shift+O`.

```
archfrican-project
```

Requires `zoxide` (opt-in, `packages/dev.txt`). If zoxide isn't installed, or hasn't
learned any directories yet, it notifies and exits instead of showing an empty picker.

---

## archfrican-focus

Toggle distraction-free mode: hide waybar and nwg-dock for a clean single-app view.
Second call restores both.

```
archfrican-focus
```

Stateful toggle — presence of `$XDG_RUNTIME_DIR/archfrican-focus` = focus active.
Sends a desktop notification on each toggle.

---

## archfrican-wallpaper

Set a wallpaper and re-tint the entire shell palette from its colors using
Material You (matugen). The generated palette is user state — it never causes
convergence drift. Five curated Archfrican wallpapers ship on-disk in 
`/usr/share/backgrounds/archfrican/` and are immediately pickable out of the box.

```
archfrican-wallpaper [/path/to/image.jpg]
```

| Arg | Behavior |
|-----|----------|
| *(no args)* | Interactive image picker via fuzzel (shows bundled wallpapers + user images) |
| `<path>` | Apply image directly |

**Process**: sets wallpaper (awww) → extracts palette (matugen) → writes
`~/.config/archfrican/dynamic-colors.sh` → applies via `theme-switch dynamic`.

**Requirements**: `matugen`, `jq` (both installed by the niri-desktop module).

---

## archfrican-power

Power and thermal management. power-profiles-daemon (PPD) is the default;
this tool lets you swap to TLP or add thermald.

```
archfrican-power
```

Interactive fuzzel menu with four options:

| Option | Effect |
|--------|--------|
| PPD (default) | `systemctl enable --now power-profiles-daemon` (disables TLP if active) |
| TLP | `systemctl enable --now tlp` (disables PPD; installs if needed) |
| thermald | `systemctl enable --now thermald` (Intel thermal management; complements either) |
| Estado actual | Show status of all three services |

PPD and TLP are mutually exclusive. thermald can run alongside either.

---

## archfrican-power-auto

Internal helper (you rarely call it by hand): sets the CPU power profile from the AC-adapter
state — **balanced on the charger, power-saver on battery** — the macOS behavior a bare
compositor (no GNOME/KDE power daemon) otherwise lacks. A udev rule
(`/etc/udev/rules.d/60-archfrican-power-profile.rules`, installed by module `15-desktop-services`)
fires it through `systemd-run` on every plug/unplug. Inert on desktops and on any machine without
`power-profiles-daemon`.

```
archfrican-power-auto ac        # force the AC profile now
archfrican-power-auto battery   # force the battery profile now
```

**Override / disable** — create `/etc/archfrican/power-auto.conf` (shell syntax) with any of:

```sh
AUTO=off           # disable auto-switching (keep your manual profile)
AC=performance     # profile to use on AC       (default: balanced)
BATTERY=balanced   # profile to use on battery  (default: power-saver)
```

---

## archfrican-vpn

VPN connection manager: Tailscale mesh or NetworkManager (WireGuard/OpenVPN/OpenConnect).

```
archfrican-vpn
```

Interactive fuzzel menu:

| Option | Effect |
|--------|--------|
| Tailscale: conectar | Enables tailscaled + runs `tailscale up` (shows login URL in terminal) |
| Tailscale: desconectar | `tailscale down` |
| WireGuard / OpenVPN | Opens `nm-connection-editor` |

Tailscaled is never auto-enabled at install — always opt-in here.

---

## archfrican-secureboot

Set up Secure Boot with sbctl (keeps GRUB — no bootloader change). Creates and
enrolls PK/KEK/db keys, signs GRUB and kernels.

```
archfrican-secureboot
```

**Prerequisites**: firmware must be in Setup Mode (check: `sbctl status`).
Interactive flow with a confirmation step before any key enrollment.

**Recovery**: if boot fails after enabling SB in firmware, disable Secure Boot —
no brick risk (passphrase keyslot untouched, passphrase always works).

See [docs/FIDO2-RECOVERY.md](FIDO2-RECOVERY.md) for related auth recovery.

---

## archfrican-tpm-unlock

Enroll TPM2 for LUKS auto-unlock at boot (FileVault-style). The passphrase
keyslot is preserved — passphrase always works as a fallback.

```
archfrican-tpm-unlock
```

**Prerequisites**: TPM 2.0 chip present, LUKS2 (not LUKS1), Secure Boot recommended
(PCR 7 binding is weaker without it).

**After enrollment** you must manually update `/etc/crypttab.initramfs` and run
`sudo mkinitcpio -P`. The command prints the exact steps.

**Recovery**: disable the TPM-enrollment keyslot with
`sudo systemd-cryptenroll --wipe-slot=tpm2 <device>` — the passphrase slot remains.

---

## archfrican-privacy

Review Archfrican's privacy posture and flip app-level telemetry opt-outs.

```
archfrican-privacy
```

Interactive menu:

| Option | Effect |
|--------|--------|
| Ver postura de privacidad | Opens `docs/PRIVACY.md` in less |
| Desactivar telemetría de VS Code | Writes `{"telemetry.telemetryLevel": "off"}` to Code settings |
| ¿Qué puede 'phone home'? | Summary: browser, Steam, Flatpak, extensions (yours to control) |

`DO_NOT_TRACK=1` is set in the shell session by the dotfiles.

---

## archfrican-actions

Central control hub — one fuzzel interface reaching every Archfrican command.
The equivalent of Spotlight Actions or an omarchy-menu.

```
archfrican-actions
```

**Keyboard shortcut**: `⌘+Shift+A` (configured in niri)

Covers ~50 actions organized by category: Configuración, Sistema, Sesión/Interfaz,
Herramientas, Red, Audio/Visual, Accesibilidad, Privacidad/Seguridad, Gaming,
Continuidad/Datos, Notificaciones.

---

## theme-switch

Hot-swap the entire desktop theme live: colors, fonts, spacing, borders, cursor.
Zero dependencies — pure bash/sed. Runs in under 1 second.

```
theme-switch <theme-name>
```

**Available themes**

| Theme | Description |
|-------|-------------|
| `adl-dark` | Archfrican Design Language — teal accent on deep graphite. The default. |
| `adl-light` | ADL light variant — teal on warm white |
| `archfrican-dark` | Archfrican palette dark variant (warmer than adl-dark) |
| `archfrican-light` | Archfrican palette light variant |
| `catppuccin-mocha` | Catppuccin Mocha palette |
| `tokyo-night` | Tokyo Night palette |
| `high-contrast` | Accessibility high-contrast |
| `dynamic` | Wallpaper-generated Material You palette (see `archfrican-wallpaper`) |

**What it renders**: ghostty, waybar, fuzzel, swaync, niri, nwg-dock, GTK 3/4,
Qt5/Qt6, fontconfig, icons, SDDM login screen, VS Code (via cohesion), web-apps (via cohesion).

**Reloads live**: sends SIGUSR2 to waybar, `swaync-client --reload-config`.

**Stores selection** in `~/.config/.archfrican-theme` (read at each converge).

For custom themes see [docs/THEMING.md](THEMING.md).

---

## fw-allow

Open an inbound firewall port persistently (survives reboots).

```
fw-allow <PORT>/<PROTOCOL>
```

**Arguments**: `PORT` is a number, `PROTOCOL` is `tcp` or `udp`.

**Examples**

```bash
fw-allow 3000/tcp      # dev server
fw-allow 5353/udp      # mDNS
fw-allow 51820/udp     # WireGuard
```

Rules are written to `/etc/nftables.d/archfrican-allows.nft` and loaded live.
The base firewall (module 60) denies all inbound by default; use this command
to carve out exceptions. See `modules/60-security.sh` for the full ruleset.

---

## install.sh (advanced)

The installer itself can re-run individual modules.

```bash
./install.sh                  # full run (skips completed modules)
./install.sh 30-dev           # re-run a single module by name
FORCE=1 ./install.sh          # redo everything regardless of .done stamps
./install.sh 55-multiboot yes  # pass an argument to an opt-in module
./install.sh 65-gaming yes     # enable gaming module
./install.sh 25-plasma-desktop yes   # enable the Plasma desktop session (Windows-familiar, opt-in)
./install.sh --update          # convergence mode (same as archfrican-update --converge)
```

---

## archfrican-spotlight

The main launcher (`⌘+Space`). One surface to reach everything: launch any app, search
files, search the web, open the calculator, switch windows, or browse clipboard history.

Uses **Walker** (GTK4 Raycast-style launcher with an app grid, icons, and built-in modes)
backed by the `elephant` daemon. Falls back automatically to the fuzzel launcher if Walker
or elephant are not installed, so `⌘+Space` never fails.

```
archfrican-spotlight
```

**Walker path** (when `walker` + `elephant` are on PATH): Walker opens with its built-in
mode prefixes for apps, files, clipboard, calc, web, and open windows. Walker's stylesheet
is styled from ADL tokens by `theme-switch` so it matches every other Archfrican surface.

**Walker modes** (elephant providers — these replaced the old standalone
`archfrican-calc/find/window/websearch/emoji` scripts):

| Mode | Shortcut / prefix | What it does |
|------|-------------------|-------------|
| `walker -m windows` | `⌘+Shift+W` / `$` | Window switcher across all workspaces |
| `walker -m calc` | `⌘+Shift+C` / `=` | Calculator (libqalculate: units, conversions) |
| `walker -m files` | `⌘+Shift+G` / `/` | Local file search (fd) |
| `walker -m clipboard` | `⌘+Shift+V` / `:` | Clipboard history |
| `walker -m websearch` | `@` prefix | Web search |
| `walker -m symbols` | `.` prefix | Emoji / symbol picker |

**Fuzzel fallback** (when Walker is absent): the full app list plus two mode entries —
`Portapapeles…` (cliphist history) and `Acciones y ajustes…` (the archfrican-actions hub,
which itself falls back to fuzzel and still reaches every action above).

**Keyboard shortcut**: `⌘+Space`

---

## archfrican-setup

Settings assistant hub — a categorized menu over all runtime-configurable Archfrican
settings. Offered once on first boot and always available from the actions hub.

```
archfrican-setup
```

Covers: default apps (browser, IDE, PDF, image viewer), language/locale/keyboard,
display arrangement, appearance/theme, accessibility, privacy, backup, VPN, and more.

**Access via**: `⌘+Shift+A → "Configurar el sistema"`

---

## archfrican-layout

Visual layout / snap-layout picker for niri. Shows common column widths and applies the
choice to the focused column via niri IPC. Teaches the scrolling tiling model without
needing to remember commands. Keyboard shortcut: `⌘+Shift+T`.

```
archfrican-layout
```

Available options: ⅓, ½, ⅔, maximize column, fullscreen, consume window into column,
expel window from column.

---

> **Retired commands** — `archfrican-window`, `archfrican-websearch`, `archfrican-calc`,
> `archfrican-find` and `archfrican-emoji` were replaced by Walker's native modes
> (see the table under [archfrican-spotlight](#archfrican-spotlight)): `walker -m
> windows/websearch/calc/files/symbols`. The old keyboard shortcuts kept working — they
> now open the equivalent Walker mode.

---

## archfrican-blur

Toggle frosted-glass blur on niri windows and the Spotlight launcher layer. Guards with
`niri validate` and auto-reverts if the running niri version is too old to support blur.

```
archfrican-blur on
archfrican-blur off
archfrican-blur toggle
archfrican-blur status
```

Blur modifies `~/.config/niri/config.kdl` in-place. A backup is kept as
`config.kdl.archfrican.bak`. niri live-reloads on save — no restart needed.

---

## archfrican-nightlight

Night-light toggle: warms the screen color to 4000 K. Toggle on/off with one command.

```
archfrican-nightlight on
archfrican-nightlight off
archfrican-nightlight toggle    # default when no arg given
archfrican-nightlight status
```

Uses `wlsunset` with fixed constant-temperature mode (no location needed). Persists state
across calls via `$XDG_RUNTIME_DIR/archfrican-nightlight`.

---

## archfrican-record

Screen recording toggle. First invocation starts recording to `~/Videos/rec-YYYYMMDD-HHMMSS.mp4`;
second invocation stops it. Keyboard shortcut: `⌘+Shift+R`.

```
archfrican-record
```

Uses `wf-recorder` (software H.264 encode). For GPU-accelerated encoding add `-c h264_vaapi`
flags to the script after verifying your GPU supports VAAPI.

---

## archfrican-screenshot

Region capture with **annotation** — the macOS `⌘+Shift+4` flow. `slurp` selects a region,
`grim` captures it, and `satty` opens it for markup (arrows, text, boxes, blur, crop). On save
it both copies to the clipboard and writes a PNG to `~/Pictures/Screenshots`. Keyboard shortcut:
`⌘+Shift+4`.

```
archfrican-screenshot
```

Coexists with niri's native captures (`Print` / `⌘+Shift+S` = region, `⌘+Shift+P` = whole
screen) — those stay the fast path; this adds the markup step. If `satty` is absent it falls
back to `grim` + `wl-copy` (still captures and copies), so the key is never a no-op.

**Requires**: `satty` (in `packages/niri-desktop.txt`), plus `grim`/`slurp`/`wl-clipboard`.

---

## archfrican-displays

Persist your monitor layout across reboots and `chezmoi apply` runs — with one saved
layout **per set of connected monitors** (docked / undocked / any combination), not a
single global layout.

```
archfrican-displays edit        # open nwg-displays, auto-save layout when it closes
archfrican-displays save        # snapshot current live layout → config.kdl + this monitor set's profile
archfrican-displays restore     # re-apply the profile matching the CURRENTLY connected monitors
```

`nwg-displays` arranges monitors live via niri IPC but does not write the config — this
command snapshots the layout into `~/.config/niri/config.kdl` between managed markers.
Backs up and validates with `niri validate` before saving; auto-reverts on failure.

**Profiles**: each layout is keyed by its "fingerprint" — the sorted, `+`-joined set of
connected output names (e.g. `eDP-1` alone vs. `eDP-1+DP-1` when docked) — stored under
`~/.config/archfrican/displays/<fingerprint>.kdl`. `restore` computes today's fingerprint
and re-splices whichever profile matches; if this exact monitor set was never saved, it's
a safe no-op (`config.kdl` is left as-is) rather than guessing. A pre-existing single-layout
install (the old `~/.config/.archfrican-displays.kdl`) is adopted as the first profile
automatically, with no manual migration step.

---

## archfrican-idle

Idle and lock daemon driver (spawned by niri at session start). Locks on suspend and
after configurable idle timeout.

```
archfrican-idle
```

Configuration (`~/.config/archfrican/lock.conf`):

```bash
ARCHFRICAN_LOCK_TIMEOUT=900    # idle seconds before locking (0 = disable idle lock)
```

Default: 900 seconds (15 minutes). Suspend lock is always enabled.

---

## archfrican-screenreader

Toggle the Orca screen reader. niri is the only tiling Wayland compositor that exposes
its UI via AccessKit + the keyboard-grab interface Orca needs. Keyboard shortcut:
`⌘+Alt+S`.

```
archfrican-screenreader
```

First call starts Orca; second call stops it. Sends a desktop notification on each toggle.

**Requires**: `orca` (`sudo pacman -S orca` — or installed by the 60-security module).

---

## archfrican-git

Interactive assistant to configure Git identity and SSH authentication for GitHub,
GitLab, Bitbucket, or any host.

```
archfrican-git
```

**What it does**:

1. Sets git global `user.name` and `user.email`
2. Generates an `ed25519` SSH key (never overwrites an existing one)
3. Loads the key into the running `ssh-agent` (enabled by default — see `modules/60-security.sh`)
   and tells you clearly if that failed, instead of failing silently later
4. For GitHub: installs the `gh` CLI, runs `gh auth login`, uploads the key
5. For other hosts: shows the public key for manual upload + tests the connection with `ssh -T`

Option 5 ("Estado actual") also reports whether the SSH agent is active and whether your key is
currently loaded in it.

Idempotent — safe to re-run.

---

## archfrican-locale

Change language, keyboard layout, timezone, or hostname at runtime.

```
archfrican-locale
```

Interactive fuzzel menu. Applies changes via `localectl`, `timedatectl`, and `hostnamectl`
(the same commands the installer uses). Language and keyboard layout require a re-login
for full effect.

**Accents on the `us` layout**: niri uses the `altgr-intl` xkb variant
(`home/dot_config/niri/config.kdl.tmpl`), so `Right Alt` (AltGr) + a letter gives the accent in
ONE combo — hold AltGr, press the letter, release both:

| Combo | Result |
|-------|--------|
| `AltGr` + `a`/`e`/`i`/`o`/`u` | á é í ó ú |
| `AltGr` + `n` | ñ |
| `AltGr` + `y` | ü |
| `AltGr` + `1` | ¡ |
| `AltGr` + `/` | ¿ |

Normal typing (`'`, `"`, `` ` ``, `~` on their own) is unaffected — AltGr also still has its own
dead keys (`AltGr` + `'` then a letter, `AltGr` + `` ` `` then a letter) for accents not listed
above.

---

## archfrican-ime

Install and enable fcitx5 for CJK, Indic, and other input methods (opt-in).

```
archfrican-ime install        # install fcitx5 + common engines + start user service
archfrican-ime status         # show fcitx5 service status
```

Wayland-native apps use text-input-v3 (no env vars needed). XWayland apps need
`export XMODIFIERS=@im=fcitx` in your shell. Configure engines with `fcitx5-configtool`.

**Installed packages**: `fcitx5`, `fcitx5-configtool`, `fcitx5-gtk`, `fcitx5-qt`,
`fcitx5-mozc` (Japanese), `fcitx5-chinese-addons`, `fcitx5-hangul` (Korean).

---

## archfrican-continuity

Enable cross-device continuity: shared clipboard, phone notifications, file transfer
(KDE Connect + LocalSend). Opens only the required LAN-scoped firewall ports.

```
archfrican-continuity
```

Interactive fuzzel menu. Ports are restricted to RFC1918 (private LAN) addresses only
— not exposed publicly. Nothing is opened until you run this command.

---

## archfrican-cloud

Connect cloud storage (Google Drive, Dropbox, OneDrive, etc.) via rclone, or browse an
SMB/Windows share in Nautilus.

```
archfrican-cloud
```

Interactive fuzzel menu with three options: configure a new rclone remote, mount/unmount
an existing remote, or connect to an SMB share. Credentials stay in `~/.config/rclone`.

---

## archfrican-webapp

Turn a URL into a frameless, dockable app that appears in the launcher like a native
application. Works with any installed Chromium-class browser.

```
archfrican-webapp "Gmail" https://mail.google.com
archfrican-webapp                                     # interactive prompts
```

Creates a `.desktop` file in `~/.local/share/applications/` with `--app=URL` flag.
The app gets its own icon, taskbar entry, and window ID (separate from the browser).

**Requires**: Brave or Vivaldi installed (`archfrican-browser`).

---

## archfrican-mullvad

Install Mullvad VPN and/or Mullvad Browser from the AUR (opt-in, privacy-first).

```
archfrican-mullvad              # interactive menu
archfrican-mullvad vpn          # install only Mullvad VPN + daemon
archfrican-mullvad browser      # install only Mullvad Browser (Tor-derived)
archfrican-mullvad both         # install both
```

Installs in a Ghostty terminal so you can see the AUR build and authorize sudo.

---

## archfrican-plymouth

Install a boot splash screen (Plymouth) for a clean boot-to-SDDM transition (opt-in).
Touches the initramfs — validate in a VM first.

```
archfrican-plymouth
```

Interactive confirmation required before any changes. Backs up `mkinitcpio.conf` to
`mkinitcpio.conf.archfrican.bak`. Recovery: boot `linux-lts` or a Btrfs snapshot if
the boot splash causes issues.

---

## archfrican-net-status

Internet reachability monitor for waybar. Reports online / unstable / offline with
latency via a JSON waybar module.

```
archfrican-net-status
```

Pings `1.1.1.1` (3 packets) and reports packet loss and average latency.

**Waybar integration** — add to `~/.config/waybar/config.jsonc`:

```json
"custom/net": {
  "exec": "archfrican-net-status",
  "return-type": "json",
  "interval": 60
}
```

---

## archfrican-gh-status

GitHub attention badge for waybar: review requests, CI activity, and mentions across
every repo you participate in. Reads GitHub's `/notifications` endpoint
(`participating=true`) rather than a hand-picked repo list, so it follows whatever
notification settings you already have on github.com. Requires `gh` (opt-in,
`packages/dev.txt`), authenticated via `gh auth login`; hides itself (empty text) if `gh`
isn't installed or isn't authenticated.

```
archfrican-gh-status
```

**Waybar integration** — add to `~/.config/waybar/config.jsonc`:

```json
"custom/github": {
  "exec": "archfrican-gh-status",
  "return-type": "json",
  "interval": 300,
  "on-click": "xdg-open 'https://github.com/notifications?query=is%3Aunread'"
}
```

---

## archfrican-defaults

Set default applications per category (browser, terminal, IDE, PDF viewer, image viewer,
file manager, email, container manager, messaging, remote desktop). Smarter than
`xdg-settings`: shows only apps you have installed, plus install shortcuts for common ones
you don't.

```
archfrican-defaults
```

Interactive fuzzel menu. Assigns all relevant MIME types for the chosen category at once.
"Another installed app…" offers the full `xdg-mime` fallback. The "Gestor de contenedores"
(LazyDocker, Docker Desktop), "Mensajería" (Telegram, Signal, Discord, WhatsApp), and
"Acceso remoto" (RustDesk, AnyDesk) categories have no MIME/default-handler concept —
picking one just installs it and confirms.

---

## archfrican-lock

Screen lock entry point. **Keyboard shortcut**: `⌘+Shift+L`. Also called by
`archfrican-idle` (before screen-off) and before suspend.

```
archfrican-lock
```

Prefers **gtklock** (login-styled: ext-session-lock, avatar + power bar, themed from ADL
tokens, wallpaper as backdrop). Falls back to **swaylock** (themed) if gtklock is absent.
Both authenticate via the guaranteed PAM stack wired by `modules/60-security.sh` — the
correct password is never refused.

**Locked out?**

```bash
# Switch to a text TTY (Ctrl+Alt+F3), log in, then:
loginctl unlock-session
```

---

## archfrican-quit-app

Closes **every** window of the focused app (`⌘+Q` semantics — quit the whole
application, not just the frontmost window). **Keyboard shortcut**: `⌘+Q`.

```
archfrican-quit-app
```

niri has no native "quit app" action — only `close-window` per window. This command
queries the niri IPC for every window sharing the focused app-id and closes each one.
Requires `jq`.

---

## archfrican-keys

Live, never-drifting keybinding cheatsheet. Reads the **actual deployed niri config** (so
it can never go stale) plus the keyd `⌘→Ctrl` map and shows everything in a fuzzel
picker. Read-only — selecting an item just closes the picker.

```
archfrican-keys
```

**Keyboard shortcut**: `⌘+Shift+K`

Shortcuts are grouped by category header (comment lines in `config.kdl`) so finding a
binding is fast even as the config grows.

---

## archfrican-a11y

Accessibility hub — screen reader, high-contrast, cursor size, text size.

```
archfrican-a11y
```

Interactive fuzzel menu offering:

| Option | What it does |
|--------|-------------|
| Screen reader (Orca): toggle | Start/stop Orca via `archfrican-screenreader` |
| High contrast: on / off | `theme-switch high-contrast` / restore previous theme |
| Large cursor | `gsettings` cursor size 48 |
| Normal cursor | Cursor size back to 24 |
| Larger text | `gsettings` text-scaling-factor 1.3 |
| Normal text | Text scaling back to 1.0 |
| Magnifier / sticky keys (info) | Status note (no mature Wayland-native magnifier yet) |

Access via: `⌘+Shift+A → "Accesibilidad"` or run directly.

---

## archfrican-cohesion

Toggle Tier-B app cohesion (opt-in theming for apps that ignore GTK/Qt, such as VS Code
and Chromium web-apps).

```
archfrican-cohesion [on|off|status|apply]
```

| Subcommand | What it does |
|------------|-------------|
| `on` | Enable Tier-B cohesion; backs up VS Code settings before the first write |
| `off` | Disable; restores the VS Code settings backup |
| `status` | Print whether cohesion is on/off and the staging path |
| `apply` | Re-apply without toggling (called automatically by `theme-switch`) |

Tier-A (GTK/Qt/fonts/cursor/waybar) is always-on and is NOT governed here.

---

## archfrican-auto-appearance

Toggle automatic light/dark switching by sun position via **darkman**. Off by default
(it changes your theme by time of day).

```
archfrican-auto-appearance [on [lat lng]|off|status]
```

| Subcommand | What it does |
|------------|-------------|
| `on` | Enable darkman (geoclue for location, or pinned coordinates) |
| `on <lat> <lng>` | Pin coordinates so darkman works without a geoclue agent |
| `off` | Disable and stop darkman |
| `status` | Show whether darkman is running |

Switches only within the active identity family (ADL dark ↔ light, macOS dark ↔ light).
A manual `catppuccin` / `tokyo-night` / `high-contrast` pick is left untouched.

---

## archfrican-fingerprint

Enroll a fingerprint (Touch-ID-style) for sudo authentication. Opt-in.

```
archfrican-fingerprint
```

Requires `fprintd` and a supported reader. On enroll:
1. Opens a Ghostty terminal with `fprintd-enroll` (swipe guided by the terminal)
2. Inserts `pam_fprintd.so sufficient` into `/etc/pam.d/sudo` before the password line
3. Self-checks the PAM stack (same logic as `lib/fido2.sh` — no-lockout guarantee)
4. Restores the backup and exits cleanly if the self-check fails

Your password always still works regardless.

---

## archfrican-privacy-indicator

Waybar microphone/camera "in-use" dot, like the macOS menubar indicator.

```
archfrican-privacy-indicator   # outputs waybar JSON
```

Reads PipeWire (`pw-dump`) for running capture streams. Outputs a single status
dot (same Nerd Font glyph as the bar's other status dots) with a tooltip when
mic/camera is in use (`{"text":"<dot>","class":"privacy","tooltip":"Micrófono|Cámara|... en uso"}`),
or empty string (hidden) when idle. Add to `~/.config/waybar/config.jsonc`:

```json
"custom/privacy": {
  "exec": "archfrican-privacy-indicator",
  "return-type": "json",
  "interval": 3
}
```

Requires `pw-dump` and `jq`.

---

## archfrican-wallpaper-restore

Restore the saved wallpaper at login. Spawned automatically by niri at startup —
not meant for direct use.

```
archfrican-wallpaper-restore
```

`awww` (the wallpaper daemon) does not persist across reboots. This command reposes the
image saved to `~/.config/archfrican/wallpaper`, or falls back to a solid backdrop in the
active theme's background colour — the desktop is never blank.

---

## archfrican-welcome-notify

One-shot first-login welcome notification (stamp-gated — fires only once). Spawned by
niri at startup.

```
archfrican-welcome-notify
```

Sends a clickable `notify-send` notification with three actions:

| Action | What it does |
|--------|-------------|
| Configurar el sistema | Opens `archfrican-setup` |
| Ver el tour | Opens `archfrican-welcome --tour` |
| Buscar actualizaciones | Runs `archfrican-update` in a terminal |

Stamp: `~/.local/state/archfrican/welcome-shown` — delete it to re-show.

---

## archfrican-caffeine

Idle-inhibitor toggle (the coffee-cup icon in waybar). ON stops `swayidle`, so the screen
never auto-locks or auto-suspends — for presentations, long reads, or watching a build.
OFF restarts `archfrican-idle`, restoring the normal lock/sleep policy.

```
archfrican-caffeine toggle    # flip the state (what the waybar click runs)
archfrican-caffeine           # print the waybar JSON (icon + tooltip)
```

**Access via**: click the waybar icon (moon = off, coffee = on).

---

## archfrican-colorpicker

Pick any pixel on screen and copy its hex color to the clipboard (grim + slurp +
imagemagick — all already in the niri stack). Shows a notification with the value.

```
archfrican-colorpicker
```

**Access via**: Spotlight (app grid) or `⌘+Shift+A → "Selector de color"`.

---

## archfrican-notepad

Persistent markdown scratchpad. The file lives at
`~/.local/state/archfrican/notepad.md`, so it survives `chezmoi apply` and converge
re-runs. Opens in the best available terminal editor (falls back to `xdg-open`).

```
archfrican-notepad
```

**Access via**: Spotlight (app grid).

---

## archfrican-weather

Weather pill for waybar (wttr.in). City resolution: an explicit name in
`~/.config/archfrican/weather`, `auto` (derive from the system timezone — the default),
or `off` (hide the module).

```bash
echo "off"          > ~/.config/archfrican/weather   # disable
echo "auto"         > ~/.config/archfrican/weather   # timezone-based (default)
echo "Buenos Aires" > ~/.config/archfrican/weather   # explicit city
```

**Access via**: always visible in waybar's center (next to the clock).
