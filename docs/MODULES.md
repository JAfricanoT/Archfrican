# Archfrican — Module Reference

Phase 2 installs the desktop and dev layer through 15 sequential modules. Each is
content-addressed: it only re-runs when its input files (script + package lists + shared libs)
change. Re-running a module manually is safe — all operations are idempotent.

```bash
./install.sh <module-name>        # re-run a single module
./install.sh <module-name> yes    # pass opt-in argument (25-plasma-desktop, 55-multiboot, 65-gaming, 67-virtualization)
FORCE=1 ./install.sh              # ignore .done stamps, re-run everything
```

---

## Quick reference

| Module | Default | Key packages | Services enabled |
|--------|---------|--------------|-----------------|
| 00-base | Always | base-devel, zsh, snapper, paru | — |
| 10-gpu | Always | mesa/nvidia/vulkan (auto-detected) | nvidia-suspend (if NVIDIA) |
| 15-desktop-services | Always | (reuses base/niri-desktop packages) | sddm, NetworkManager, bluetooth, power-profiles-daemon |
| 20-niri-desktop | Always | niri, ghostty, waybar, swaync, keyd | waybar, swaync, keyd |
| 25-plasma-desktop | **Opt-in** | plasma-desktop, dolphin, plasma-nm, plasma-pa | — |
| 30-dev | Always | code, rustup, go, docker, lazygit | docker |
| 35-apps | Always | flatpak, gnome-software, rclone | — |
| 40-theming | Always | WhiteSur GTK, SF Pro fonts | — |
| 45-print | Always | cups, avahi, sane-airscan | cups.socket, avahi-daemon, ipp-usb |
| 50-snapshots | Always | snapper, grub-btrfsd | grub-btrfsd, snapper timers |
| 55-multiboot | **Opt-in** | os-prober, ntfs-3g | — |
| 60-security | Always | nftables, pam-u2f, bubblewrap | nftables, optionally sshd |
| 65-gaming | **Opt-in** | steam, gamescope, proton-ge | ananicy-cpp |
| 67-virtualization | **Opt-in** | qemu-desktop, libvirt, virt-manager | libvirtd |
| 70-hygiene | Always | (reuses base packages) | paccache, fstrim, smartd timers |

---

## 00-base — Base system

**Always active.** Sets up the CachyOS repository, installs core system tools,
and adds the dual-kernel safety net.

**Packages** (`packages/base.txt`): `base-devel`, `git`, `curl`, `wget`, `zsh`,
`btrfs-progs`, `snapper`, `snap-pac`, `grub-btrfs`, `inotify-tools`, `reflector`,
`pacman-contrib`, `zram-generator`, `openssh`, `man-db`, `pciutils`, `smartmontools`,
`fwupd`, `arch-audit`, `libnotify`.

**What it does**

1. Pins and locally-signs the CachyOS GPG key (fingerprint `882DCFE4…DB35A47`)
2. Adds the CachyOS repository to `/etc/pacman.conf`
3. Installs packages from `packages/base.txt`
4. Installs dual kernel: `linux-cachyos` (primary, optimized) + `linux-lts` (fallback)
5. Installs `paru` AUR helper (binary from CachyOS repo; source-build opt-in)
6. Regenerates GRUB to list both kernels

**Environment variables**

| Variable | Effect |
|----------|--------|
| `ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1` | Skip keyserver reachability check (air-gapped systems) |
| `ARCHFRICAN_ALLOW_AUR_PARU=1` | Build paru from AUR if CachyOS binary not available |

**Re-run**: `./install.sh 00-base`

---

## 10-gpu — GPU drivers

**Always active.** Auto-detects the GPU vendor and installs the correct driver stack.
No manual selection needed; override with `ARCHFRICAN_GPU=<vendor>` if detection is wrong.

**Detection logic** (`lib/detect-gpu.sh`):
Reads `/sys/bus/pci/devices/*/class` + vendor IDs. Priority: NVIDIA > AMD > Intel > VM.

**Driver packages per GPU**

| GPU | Packages installed |
|-----|-------------------|
| AMD | `mesa`, `vulkan-radeon`, `vulkan-icd-loader` |
| Intel | `mesa`, `vulkan-intel`, `intel-media-driver`, `vulkan-icd-loader` |
| AMD+Intel hybrid | All AMD + all Intel packages |
| NVIDIA (modern) | `nvidia-dkms` (or `nvidia-open-dkms`), `nvidia-utils`, `egl-wayland`, `vulkan-icd-loader`, `libva-nvidia-driver` |
| NVIDIA legacy (Fermi/Kepler) | `mesa`, `vulkan-swrast` (nouveau; no 3D acceleration) |
| VM / unknown | `mesa`, `vulkan-swrast`, `vulkan-icd-loader` |

**NVIDIA-specific steps**

- Adds `nvidia_drm.modeset=1 nvidia_drm.fbdev=1` to `GRUB_CMDLINE_LINUX_DEFAULT`
- Adds NVIDIA modules to `MODULES=()` in `/etc/mkinitcpio.conf`
- Regenerates initramfs + GRUB
- Enables: `nvidia-suspend.service`, `nvidia-resume.service`, `nvidia-hibernate.service`

**Environment variable override**: `ARCHFRICAN_GPU=vm|nvidia|amd|intel`

**Re-run**: `./install.sh 10-gpu`

---

## 15-desktop-services — Desktop-environment-agnostic services

**Always active.** SDDM login manager (the same greeter for niri AND the opt-in Plasma session),
NetworkManager, audio, Bluetooth, and power profiles — none of it niri-specific. Runs between
10-gpu and 20-niri-desktop so both niri and Plasma can rely on it already being done. Installs no
packages of its own (reuses `packages/base.txt` + `packages/niri-desktop.txt`'s NetworkManager/
Bluetooth/pipewire entries, already pulled in by 20-niri-desktop).

**What it configures**

| File / Service | What |
|----------------|------|
| `/usr/share/sddm/themes/archfrican/` | Custom SDDM QML theme (macOS-inspired login screen) |
| `/etc/sddm.conf.d/10-archfrican.conf` | Wayland session, remember last user |
| `/usr/share/backgrounds/archfrican/` | Curated Archfrican wallpapers (pickable in the install wizard) |
| `/etc/bluetooth/main.conf.d/10-archfrican.conf` | Bluetooth auto-power-on |
| Services enabled | `sddm`, `NetworkManager`, `bluetooth`, `power-profiles-daemon` |
| User sockets | `pipewire.socket`, `pipewire-pulse.socket`, `wireplumber.service` |

**Re-run**: `./install.sh 15-desktop-services`

---

## 20-niri-desktop — Wayland desktop

**Always active.** The niri compositor layer: package install, keyd (⌘-style remaps), waybar/
swaync (each via its own systemd --user service, not niri spawn-at-startup — see the comments in
the module for the two upstream bugs that fixed), and the screen-share portal routing.

**Packages** (`packages/niri-desktop.txt`):

- **Compositor core**: `niri`, `ghostty`, `xwayland-satellite`, `keyd`
- **Login**: `sddm`, `qt6-virtualkeyboard`
- **Panel + notifications**: `waybar`, `swaync`
- **Launcher**: `fuzzel`
- **Screen tools**: `swayidle`, `swaylock`, `grim`, `slurp`, `wl-clipboard`, `cliphist`, `brightnessctl`, `playerctl`
- **Audio**: `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber`, `pavucontrol`, `easyeffects`, `qpwgraph`
- **File management**: `nautilus`, `file-roller`, `yazi`, `gvfs`, `gvfs-mtp`, `gvfs-afc`, `udiskie`, `tumbler`
- **Networking**: `networkmanager`, `nm-connection-editor`, `network-manager-applet`, `tailscale`, `wireguard-tools`, `networkmanager-openvpn`, `networkmanager-openconnect`
- **Bluetooth**: `bluez`, `bluez-utils`, `blueman`
- **Accessibility**: `orca`, `speech-dispatcher`, `espeak-ng`
- **Continuity**: `kdeconnect`, `restic`, `fprintd`, `libfprint`
- **Theming runtime**: `matugen`, `darkman`, `geoclue`, `colord`
- **Qt compatibility**: `qt5-wayland`, `qt6-wayland`, `qt5ct`, `qt6ct`
- **Portals**: `xdg-desktop-portal`, `xdg-desktop-portal-gnome`, `xdg-desktop-portal-wlr`, `polkit-gnome`, `gnome-keyring`

**What it configures**

| File / Service | What |
|----------------|------|
| `/etc/keyd/default.conf` | macOS-style keyboard: `Meta` → `Ctrl`, `Meta+Shift` → `Ctrl+Shift` |
| `/etc/xdg-desktop-portal/niri-portals.conf` | Routes the `ScreenCast` portal to `-wlr` (RustDesk/AnyDesk/browser/OBS screen-share) — niri's own packaged default sends it to `-gnome`, which needs mutter's D-Bus API and can't work under niri |
| Services enabled | `waybar.service`, `swaync.service`, `keyd` |

(SDDM, NetworkManager, Bluetooth, audio, and power profiles are shared with the opt-in Plasma
session — see modules/15-desktop-services.sh above. `~/.config/code-flags.conf` is written by
modules/30-dev.sh, not here.)

**Re-run**: `./install.sh 20-niri-desktop`

---

## 25-plasma-desktop — Windows-familiar desktop session (opt-in)

**Opt-in.** A MINIMAL KDE Plasma Wayland session, selectable at SDDM login alongside niri —
for people migrating from Windows who find niri's scrolling-tiling model unfamiliar. niri is
never touched: this is a genuinely parallel session, not a replacement.

**Enable during install**: Phase 2 wizard asks (defaults to no).
**Enable post-install**: `./install.sh 25-plasma-desktop yes`

**Packages**

From `packages/plasma-desktop.txt`: `plasma-desktop` (pulls `plasma-workspace`, which brings
`kwin` + `kde-cli-tools` + `kconfig` along as dependencies), `dolphin` (file manager — not
auto-pulled), `plasma-nm` (network applet), `plasma-pa` (audio applet),
`xdg-desktop-portal-kde` (screencast/file-picker portals under Wayland). Deliberately excludes
Konsole, Kate, and Discover — Plasma reuses ghostty (terminal) and gnome-software (app store),
already installed by other modules.

**What it does**

1. Installs the package list above (never the whole `plasma` group — that pulls in Discover
   and other extras this setup intentionally skips).
2. Confirms the SDDM Wayland session file landed under `/usr/share/wayland-sessions/`.
3. Paints Plasma's color scheme, icon theme, cursor theme, and fonts from the currently active
   Archfrican theme (best-effort — `bin/theme-switch` keeps it in sync on every later switch).

**Inside Plasma**: menu, taskbar, and window management are 100% native Plasma (Kickoff, KWin)
— Archfrican doesn't inject niri's macOS-style keybinds or launcher there. Familiarity with
Windows depends on Plasma's own components, not Archfrican's.

**Known limitation**: `keyd` remaps `⌘+L`/`⌘+R` → `Ctrl+L`/`Ctrl+R` system-wide (not
niri-specific), so Win+L (lock) and Win+R (run) won't behave as a Windows user expects inside
Plasma. Fixing this needs `keyd` to be session-aware — out of scope for this module.

**Re-run**: `./install.sh 25-plasma-desktop yes`

---

## 30-dev — Developer environment

**Always active.** Language toolchains, LSP servers, CLI productivity tools, and Docker.

**Packages** (`packages/dev.txt`):

- **Editors**: `code` (VS Code OSS), `neovim`
- **Language toolchains**: `rustup`, `go`, `uv` (Python), `fnm` (Node.js)
- **JS runtime + package managers**: `bun`, `pnpm` (standalone binaries, independent of fnm's node version)
- **Language servers**: `gopls`, `rust-analyzer`, `pyright`, `ruff`, `typescript-language-server`, `clang`, `lldb`
- **CLI tools**: `ripgrep`, `fd`, `fzf`, `bat`, `eza`, `zoxide`, `jq`, `lazygit`, `github-cli`, `direnv`, `starship`
- **Containers**: `docker`, `docker-compose`
- **Database clients**: `postgresql` (`psql`/`pg_dump`/etc. — Arch bundles client+server in one
  package; `postgresql.service` is never enabled by this repo, so it's client-only in practice)

**What it does after package install**

1. Enables `docker.service`; adds user to the `docker` group
2. Bootstraps Rust stable toolchain: `rustup toolchain install stable`
3. Bootstraps Node.js LTS: `fnm install --lts`
4. Sets VS Code Wayland flags in `~/.config/code-flags.conf`

**Note**: Docker group membership takes effect on next login.

**Re-run**: `./install.sh 30-dev`

---

## 35-apps — App ecosystem

**Always active.** Flatpak runtime, Flathub repository, GNOME Software app store,
and a curated app catalog.

**Packages** (`packages/apps.txt`): `flatpak`, `gnome-software`, `gvfs-smb`, `rclone`, `fuse3`.

**What it does**

1. Installs Flatpak + adds Flathub as a system-wide remote
2. Installs GNOME Software for GUI app discovery
3. Installs cloud/SMB tools: rclone (configured via `archfrican-cloud`), gvfs-smb
4. Installs curated apps from `flatpak/apps.txt`:
   - `com.github.tchx84.Flatseal` — Flatpak permission manager (always installed)
   - `org.localsend.localsend_app` — AirDrop-class local file transfer (always installed)
   - Commented-out suggestions: Bitwarden, Obsidian, Spotify, Signal, Telegram, Discord, LibreOffice, GIMP

**Browser**: not installed here — use `archfrican-browser` (opt-in, your choice).

**Re-run**: `./install.sh 35-apps`

---

## 40-theming — Desktop theming

**Always active.** Installs GTK theme, icon theme, cursor theme, system fonts, and
wires up the `theme-switch` binary.

**Packages**

- From `packages/theming.txt`: `ttf-jetbrains-mono-nerd`, `inter-font`, `noto-fonts`, `noto-fonts-emoji`, `nwg-look`
- From `packages/aur.txt` (via paru): `whitesur-gtk-theme`, `whitesur-icon-theme`, `mcmojave-cursors`, `otf-san-francisco`, `otf-san-francisco-mono`, `nwg-dock`

**What it configures**

- Runs `theme-switch` with the theme selected in the wizard (stored in `~/.config/.archfrican-theme`) — it owns every `gsettings` identity key (gtk/icon/cursor themes, UI + mono fonts, color-scheme), all driven by the theme's token cascade
- Stages the wallpaper selected in the wizard into `~/.config/archfrican/wallpaper`, applied at first login by `archfrican-wallpaper-restore` (five curated options available out of the box)
- Sets cohesion on (VS Code + web-app theme injection); user can toggle with `archfrican-cohesion off`

See [docs/THEMING.md](THEMING.md) for the full theming guide.

**Re-run**: `./install.sh 40-theming`

---

## 45-print — Printing & scanning

**Always active.** Driverless printing (IPP Everywhere) and scanning (eSCL/WSD).
Most modern printers and scanners work with zero configuration.

**Packages** (`packages/print.txt`): `cups`, `cups-pdf`, `cups-filters`, `system-config-printer`,
`avahi`, `ipp-usb`, `sane`, `sane-airscan`, `simple-scan`.

**Services enabled**: `cups.socket` (socket-activated), `avahi-daemon.service`, `ipp-usb.service`.

**Discovery**: Avahi/mDNS auto-discovers network printers and scanners.
USB printers are handled by ipp-usb (turns USB into IPP over HTTP).
PDF virtual printer is available as "CUPS-PDF" immediately after install.

**Add a printer manually**: `system-config-printer` or CUPS web UI at `http://localhost:631`.

**Re-run**: `./install.sh 45-print`

---

## 50-snapshots — Btrfs snapshots & rollback

**Always active.** Configures snapper for automatic Btrfs snapshots and wires the
GRUB submenu for one-reboot rollback.

**Packages** (from base): `snapper`, `snap-pac`, `grub-btrfs`, `inotify-tools`.

**What it configures**

1. Creates snapper config for `/` (or reuses existing)
2. Sets `/.snapshots` permissions to `750` (wheel group read access — no sudo needed to list)
3. Enables `grub-btrfsd.service` — inotify daemon that regenerates `/boot/grub/grub.cfg` whenever a new snapshot appears
4. Enables `snapper-timeline.timer` + `snapper-cleanup.timer` for automatic scheduled snapshots
5. Enables `snap-pac` — hook that creates snapshots before/after every pacman transaction

**Rollback flow**: `archfrican-rollback` (interactive) or GRUB → Archfrican Snapshots submenu → boot snapshot → `snapper rollback`.

**Re-run**: `./install.sh 50-snapshots`

---

## 55-multiboot — Multi-boot GRUB entries (opt-in)

**Opt-in.** Detects other operating systems on other disks and adds them to the GRUB
boot menu. The target install disk is never touched.

**Enable during install**: the Phase 1 wizard detects other OSes and asks to enable.
**Enable post-install**: `./install.sh 55-multiboot yes`

**Packages** (`packages/multiboot.txt`): `os-prober`, `fuse3`, `ntfs-3g`.

**What it does**

1. Installs os-prober + NTFS/FUSE support
2. Sets `GRUB_DISABLE_OS_PROBER=false` in `/etc/default/grub`
3. Runs `grub-mkconfig` — os-prober scans other disks and adds entries
4. Preserves the grub-btrfs snapshot submenu

**Known limitations**

- BitLocker-locked Windows partitions may not be detected
- Hibernated Windows (fast startup) may not be detected
- Large/slow NTFS volumes: 5-minute timeout cap

**Re-run**: `./install.sh 55-multiboot yes`

---

## 60-security — Security hardening

**Always active.** Firewall, kernel hardening, faillock, microcode, and optional SSH/FIDO2.

**Packages** (`packages/security.txt`): `nftables`, `pam-u2f`, `libfido2`, `bubblewrap`, `openssh`,
plus `intel-ucode` or `amd-ucode` (auto-detected).

**Firewall (nftables)**

- Default policy: drop all inbound
- Allowed by default: loopback, established/related, ICMP, DHCPv4/v6, mDNS (5353/udp)
- User rules: `/etc/nftables.d/archfrican-allows.nft` (managed by `fw-allow`)
- Safety: named table (`inet filter`) — never `flush ruleset` (Docker-safe)
- Custom `ExecStop` in the nftables unit prevents flushing Docker/Podman tables on reload

**Kernel hardening** (`/etc/sysctl.d/99-archfrican-hardening.conf`)

Dev-safe: `gdb`, `strace`, `perf`, `eBPF`, `containers`, and `unprivileged_userns` are preserved.

| Parameter | Value | Effect |
|-----------|-------|--------|
| `kernel.dmesg_restrict` | 1 | Non-root can't read dmesg |
| `kernel.kptr_restrict` | 1 | Kernel pointers hidden (not =2, dev-safe) |
| `kernel.sysrq` | 176 | Safe keys only (sync, remount-ro, reboot) |
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse path filtering |
| `net.ipv4.conf.all.accept_redirects` | 0 | No ICMP redirects |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |

**PAM faillock**: 5 failed attempts → 10-minute auto-unlock (no manual intervention needed).

**SSH (opt-in)**: `./install.sh 60-security yes` or `ARCHFRICAN_ENABLE_SSH=1`
Enables a hardened `sshd.service`.

**FIDO2 (opt-in)**: if a FIDO2 key was enrolled in the Phase 2 wizard, the module
wires `pam_u2f.so` into `/etc/pam.d/sudo` and `system-local-login`. Non-exclusive:
key OR password always works (no lockout risk). See [docs/FIDO2-RECOVERY.md](FIDO2-RECOVERY.md).

**Re-run**: `./install.sh 60-security` or `./install.sh 60-security yes` (with SSH)

---

## 65-gaming — Gaming stack (opt-in)

**Opt-in.** Steam, Proton-GE, GameMode, MangoHud, and 32-bit GPU drivers.

**Enable during install**: Phase 2 wizard asks (defaults to no).
**Enable post-install**: `./install.sh 65-gaming yes` or via `archfrican-actions → Gaming`

**Packages**

- From `gaming/packages.txt`: `steam`, `gamescope`, `gamemode`, `lib32-gamemode`, `mangohud`, `lib32-mangohud`, `lib32-mesa`, `lib32-vulkan-icd-loader`, `vulkan-tools`
- GPU-matched 32-bit drivers (auto-detected):
  - AMD: `lib32-vulkan-radeon`
  - Intel: `lib32-vulkan-intel`
  - NVIDIA: `lib32-nvidia-utils`
  - Hybrid: both
- AUR: `proton-ge-custom-bin`, `ananicy-cpp`

**What it does**

1. Enables `[multilib]` in `/etc/pacman.conf` (backup at `.archfrican.bak`)
2. Installs Steam + Gamescope + 32-bit GPU drivers
3. Enables `ananicy-cpp.service` for auto-renice (reduces input latency)
4. Installs MangoHud (in-game performance overlay: FPS, VRAM, temps)
5. Installs Proton-GE (community Proton fork with extra game compatibility)

**Launch games**: Steam → game → right-click → Properties → Launch options:
`PROTON_USE_WINED3D=1 %command%` or use Proton-GE from the compatibility dropdown.

**Re-run**: `./install.sh 65-gaming yes`

---

## 67-virtualization — Virtualization (opt-in)

**Opt-in.** KVM/QEMU + libvirt + virt-manager — the Linux-native, hardware-accelerated hypervisor
(the same tech behind most cloud providers). No serious "more native/stable/performant"
alternative exists on Linux; VirtualBox isn't kernel-integrated, VMware is proprietary.

**Not a wizard question** — unlike gaming/Plasma, it's discovered on-demand from
`archfrican-defaults → Máquinas virtuales` (same "pick it, it installs" pattern as "Acceso remoto"),
or directly: `./install.sh 67-virtualization yes`.

**Packages** (`packages/virtualization.txt`): `qemu-desktop`, `libvirt`, `virt-manager`,
`virt-viewer`, `edk2-ovmf` (UEFI firmware for guests), `dnsmasq` (DHCP for the default NAT
network), `swtpm` (emulated TPM 2.0 — Windows 11 guests need it), `dmidecode`.

**What it does**

1. Warns (non-fatal) if the CPU lacks VT-x/AMD-V — VMs still work, just software-emulated
2. Installs the package set above
3. Writes `/etc/libvirt/network.conf` with `firewall_backend = "nftables"` — this repo's firewall
   is nftables-only (`modules/60-security.sh`, no iptables/iptables-nft anywhere), so libvirt talks
   to nftables directly instead of needing an iptables compatibility layer just for this. The
   forward chain already scopes `ct state new iifname/oifname "virbr*" accept` for the default
   network (virbr0) — no firewall changes needed here.
4. Adds you to the `libvirt` group (manage VMs without `sudo` every time — needs a new login)
5. Enables + starts `libvirtd.service` (unlike most modules, started immediately, not just
   enabled for next boot — libvirtd isn't providing anything the running install session depends
   on, and starting it now lets the default network's autostart flag get set below)
6. Starts + autostarts the default NAT network (`virbr0` — DHCP/internet access for VMs)

**First VM**: open virt-manager, "Create a new virtual machine", point it at an install ISO.

**Re-run**: `./install.sh 67-virtualization yes`

---

## 70-hygiene — Maintenance timers

**Always active.** Sets up non-destructive maintenance timers and wires CLI tools into
`/usr/local/bin`.

**Packages**: reuses what base already installed (reflector, pacman-contrib, smartmontools, btrfs-progs, fwupd).

**Timers enabled**

| Timer | Schedule | Condition | Effect |
|-------|----------|-----------|--------|
| `paccache.timer` | Weekly | — | Keep 3 latest cached pkg versions; remove older |
| `fstrim.timer` | Weekly | AC power only | SSD TRIM pass |
| `btrfs-scrub@-.timer` | Monthly | AC power, +1h jitter | Btrfs data integrity check on `/` |
| `smartd.service` | Continuous | — | SMART disk health monitoring |
| `fwupd-refresh.timer` | System default | — | Firmware metadata refresh |
| `archfrican-health.timer` | Weekly | Persistent | Runs `archfrican-doctor --notify` |
| `archfrican-update-check.timer` | Hourly | Persistent, +5min jitter | Runs `archfrican-update --notify` — silent unless origin has new commits, otherwise a notification whose "Update now" action runs `archfrican-update --run` |

**Reflector** (opt-in): `ARCHFRICAN_ENABLE_REFLECTOR=1` enables weekly mirror auto-ranking
(HTTPS mirrors, 20 candidates, sorted by rate, max 12h age).

**CLI tools symlinked to `/usr/local/bin`**

- `archfrican-update` → `bin/archfrican-update`
- `archfrican-doctor` → `bin/archfrican-doctor`

**Re-run**: `./install.sh 70-hygiene`
