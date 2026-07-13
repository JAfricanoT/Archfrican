# Archfrican — ISO Guide

The Archfrican ISO is a custom Arch Linux live medium that auto-launches the
installer wizard on boot. No manual steps before installation begins.

---

## What it is

The Archfrican ISO is built on top of archiso's official `releng` profile — the
same base used by the official Arch Linux ISO. It inherits the full boot
infrastructure (GRUB, syslinux, EFI, Secure Boot stubs) and adds:

- The Archfrican installer repo pre-bundled at `/root/.archfrican`
- `gum` (the TUI wizard library) in the live environment
- Auto-launch: root auto-logs in at TTY1 → installer starts immediately
- A `motd` with WiFi instructions if the user reaches a shell

The installer detects it is running from a live medium (`is_iso()` checks for
`/run/archiso`) and enters Phase 1 — base OS install — instead of Phase 2.

---

## How to get the ISO

**Tagged releases** (stable, validated):

Download from the [GitHub Releases](https://github.com/JAfricanoT/Archfrican/releases)
page. Look for the latest `v*` or `iso-*` tag. These are manually published by the
maintainer when a feature set is ready.

**Nightly builds** (weekly, latest packages):

The `nightly` prerelease is rebuilt every Sunday at 02:00 UTC with the latest Arch
Linux packages. Use this for the most current packages; prefer a tagged release for
production installs.

**CI artifacts** (every push to main):

Every merge to `main` builds an ISO and uploads it as a GitHub Actions artifact
(available for 14 days). Download from the `build-iso` workflow run.

---

## Flashing to a USB drive

**Linux / macOS — dd:**

```bash
# Replace /dev/sdX with your USB device (check with lsblk / diskutil list)
sudo dd if=archfrican-2026.06.29-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**Balena Etcher** (GUI, cross-platform): drag and drop the ISO, select the USB, flash.

**Ventoy** (multi-boot USB): copy the ISO file to the Ventoy partition — no flashing needed.

---

## Boot flow

```
USB boot
    │
    └─ GRUB → root auto-login at TTY1
           │
           └─ /root/.zlogin → install.sh (root del live usa zsh; sin exec — un fallo cae a shell)
                  │
                  ├─ is_iso() == true → run_phase1()
                  ├─ in_repo() == true → no GitHub clone (repo is pre-bundled)
                  │
                  └─ wizard (gum TUI)
                         Pick disk → encryption → hostname → user →
                         locale → timezone → theme → GPU → options
                             │
                             └─ confirm_wipe (type device name to proceed)
                                    │
                                    └─ run_base_install() → Phase 1 → reboot
                                           │
                                           └─ (new disk boots its own kernel for the first time)
                                                  │
                                                  └─ archfrican-resume.service (headless, ~20-40 min)
                                                         Phase 2: desktop/dev modules + dotfiles (chezmoi)
                                                         │
                                                         ├─ log in on any console during this window ->
                                                         │  progress streams automatically (no command
                                                         │  needed); goes quiet once SDDM is up
                                                         │
                                                         └─ finishes -> broadcasts "desktop ready" -> reboot
                                                                (this is the LAST reboot for the base desktop)
```

**Safety gate**: `ARCHFRICAN_ISO_ARMED` defaults to `0`. In that mode the installer
prints its plan and exits without touching any disk. A real install requires the user
to either set `ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1` or confirm the wizard's
`confirm_wipe` prompt interactively (type the bare device name, e.g. `nvme0n1`).

**Two reboots, not one.** The first (end of Phase 1) is a hard Arch requirement — booting the
freshly-installed kernel/initramfs/GRUB stack for the first time. The second (end of Phase 2)
gets you onto the fully-configured desktop; it's required for NVIDIA (early-KMS) and is the
uniform way everyone reaches the newly-enabled login manager. A themed boot/unlock splash and
TPM auto-unlock are *not* part of either reboot — they're optional, separately-run commands
(`archfrican-plymouth`, `archfrican-tpm-unlock`) that each need one more reboot of their own to
take effect; see [FIRST-STEPS.md](FIRST-STEPS.md).

---

## WiFi before installation

If you need WiFi to reach the internet for `pacstrap`:

```bash
# In the installer shell (Ctrl+C to stop the wizard first):
nmtui             # curses TUI — easiest
# or:
iwctl
  station wlan0 connect "SSID"
```

The WiFi credentials entered here are copied into the installed system by
`inject_resume()` — you won't need to re-enter them after reboot.

---

## Build locally

Requirements: an Arch Linux host with `archiso` installed and root access.

```bash
sudo pacman -S archiso rsync

# Clone the repo (or use an existing checkout):
git clone https://github.com/JAfricanoT/Archfrican
cd Archfrican

sudo bash build-iso.sh
# → out/archfrican-YYYY.MM.DD-x86_64.iso
# Build takes 8–15 minutes on first run (pacstrap downloads the live env packages)
```

**Reproducible build** (bit-for-bit stable ISO name/label):

```bash
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) sudo bash build-iso.sh
```

**Test in QEMU** without touching any real disk:

```bash
# Create a throwaway disk image:
qemu-img create -f raw /tmp/test-disk.img 25G

qemu-system-x86_64 -enable-kvm -m 4G \
  -cdrom out/archfrican-*.iso \
  -drive file=/tmp/test-disk.img,format=raw,if=virtio \
  -bios /usr/share/edk2/x64/OVMF.fd

# ARCHFRICAN_ISO_ARMED defaults to 0 — wizard runs but nothing is written.
# Set ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1 to test an actual install.
```

---

## CI and releases

| Trigger | What it produces |
|---------|-----------------|
| Push to `main` | Build artifact (14-day retention, no public release) |
| Tag `v*` or `iso-*` | Versioned GitHub Release with the ISO |
| Weekly schedule (Sun 02:00 UTC) | Updates the `nightly` prerelease with fresh packages |
| `workflow_dispatch` | Manual on-demand artifact |

**Container**: `archlinux:latest` with `--privileged` (loop devices required for
squashfs and ISO mounting). The CI step runs `modprobe loop 2>/dev/null || true`
before `mkarchiso`.

**To publish a new release**:

```bash
git tag iso-2026.07.01
git push origin iso-2026.07.01
```

The `build-iso` CI job runs automatically and creates a GitHub Release with the ISO
attached and auto-generated release notes.

---

## Profile structure

```
iso/
├── airootfs/
│   ├── root/
│   │   └── .zlogin             # auto-launches install.sh on root login (zsh — releng)
│   └── etc/
│       ├── motd                # WiFi instructions shown if user reaches shell
│       └── hostname            # "archfrican" in the live environment
└── packages.extra.x86_64       # extra packages appended to releng's list (gum, rsync)

build-iso.sh                    # local build script
.github/workflows/iso.yml       # CI: build on push/tag/schedule/dispatch
```

`build-iso.sh` does not maintain a full archiso profile. Instead it:

1. Copies the installed `releng` profile to a temp dir
2. Appends metadata overrides to `profiledef.sh` (last assignment wins in bash)
3. Appends our extra packages to `packages.x86_64`
4. Overlays `iso/airootfs/` onto `releng`'s airootfs
5. rsyncs the repo into `/root/.archfrican` in the live env
6. Runs `mkarchiso`

This keeps boot infrastructure (GRUB, syslinux, EFI) in sync with archiso updates
without duplicating it.

---

## When to rebuild the ISO

| Change | Action |
|--------|--------|
| Code changes in `lib/`, `modules/`, `install.sh` | Push to `main` → CI rebuilds automatically |
| Package list changes (`packages/*.txt`) | Push to `main` → CI rebuilds |
| Live env packages age (gum version, etc.) | Weekly schedule handles this |
| Ready for a public release | `git tag iso-YYYY.MM.DD && git push --tags` |
