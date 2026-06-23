# Archfrican — Real-Install Validation Guide

How to prove the installer actually works on real Arch before you trust it on your main machine. This
guide focuses on the **P0 fixes** already applied and the **"a confirmar"** items that could only be
verified on a real Arch target (this repo was developed and statically checked on macOS).

**Golden rule:** validate in a **throwaway VM first**, snapshot it before phase 2, and only move to bare
metal once every check below passes. Nothing here should be run for the first time on a machine whose
data you care about.

---

## 0. Test environment

You need a UEFI VM (QEMU/virt-manager, GNOME Boxes, or VirtualBox) with:
- The latest **Arch ISO**, ≥ 4 GB RAM, ≥ 30 GB disk, internet access.
- **Two GPU scenarios at minimum** (run the whole flow on each): (a) the default VM virtual GPU
  (exercises the *unknown/VM* path), and (b) if you can, GPU passthrough or test later on the real
  NVIDIA/AMD/Intel box. A pure-VM run validates everything except the vendor-specific driver install.

> **VM hygiene:** after phase 1 (base install + reboot) and again right before phase 2, take a VM
> snapshot named e.g. `pre-phase2`. Every time a check fails or you want a clean re-run, restore that
> snapshot instead of reinstalling. This is what makes iterating fast.

### Phase 0 — static checks (run anywhere, before touching a VM)
```bash
# in a clone of the repo
for f in install.sh lib/*.sh modules/*.sh bin/* themes/*/colors.sh; do bash -n "$f"; done
# if you have shellcheck (the CI runs it for you on push):
shellcheck -x -e SC1091 install.sh lib/*.sh modules/*.sh bin/*
```
Expect: no output (all pass). The GitHub Actions CI also runs shellcheck + a theme-switch idempotency
smoke test + a package-resolution check on every push — green CI is your first gate.

---

## 1. Phase 1 — base install (minimal Arch base)

```bash
archinstall          # interactive — pick the Btrfs layout / Snapper / GRUB / linux-lts options below
```
- Review the TUI: confirm **Btrfs**, the subvolumes **`@ @home @log @pkg @.snapshots`**, **Snapper**
  snapshot type, **GRUB** bootloader, **linux-lts** kernel, and **select the correct disk** (the config
  intentionally ships no disk device — you pick it).
- **a confirmar (archinstall fstab):** after install, before rebooting, check that `@.snapshots` was
  written to fstab — the rollback fix depends on it:
  ```bash
  grep snapshots /mnt/etc/fstab   # expect a line mounting subvol=/@.snapshots at /.snapshots
  ```
- Reboot into the installed system. **Snapshot the VM now (`pre-phase2`).**

---

## 2. Phase 2 — run the installer & validate each P0 fix

Clone and start:
```bash
git clone https://github.com/<you>/archfrican.git ~/.archfrican   # or copy the repo to ~/.archfrican
cd ~/.archfrican && ./install.sh
```
Run as your **normal user** (the script refuses root). Validate the following — each maps to an audit
finding that was fixed.

### 2.1 Package-list parser — **SEC-01 (the critical one)**
The bug that blocked every install: inline `#` comments in `packages/*.txt` reaching pacman as malformed
targets. Validate the install gets **past the first package module** with no `target not found`:
```bash
# the preflight runs automatically right after GPU detection; you should see:
#   ✓ preflight: all pacman lists resolve
# and 00-base / 20-niri-desktop installing packages cleanly.
```
Pass criteria: no `error: target not found: <pkg>  # <comment>` and the install proceeds through all the
modules. To exercise the preflight explicitly:
```bash
ARCHFRICAN_STRICT_PREFLIGHT=1 ./install.sh 20-niri-desktop   # should still pass; fails loudly if a list has a bad/AUR entry
```

### 2.2 GPU detection — **REL-01**
The fix makes detection failure-tolerant and ensures `lspci`/`pciutils` exists before it runs.
```bash
command -v lspci          # must exist (install.sh installs pciutils up front)
# On the VM virtual-GPU path, detect_gpu must NOT abort — confirm it resolves to a profile:
ARCHFRICAN_ROOT=~/.archfrican bash -c 'source lib/detect-gpu.sh; detect_gpu'   # prints nvidia|amd|intel|hybrid-*|unknown
```
Pass criteria: on a no/virtual-GPU VM it prints `unknown` and the installer **continues** (the old code
aborted at step 1). On real NVIDIA/AMD/Intel, confirm the right stack installed:
```bash
pacman -Q nvidia-open-dkms nvidia-utils 2>/dev/null   # NVIDIA path
pacman -Q mesa vulkan-radeon 2>/dev/null              # AMD path
pacman -Q mesa vulkan-intel 2>/dev/null               # Intel path
pacman -Q vulkan-swrast 2>/dev/null                   # VM/unknown path (software Vulkan)
```

### 2.3 Btrfs rollback safety net — **DATA-02 (highest "a confirmar")**
This is the project's #1 promise and the most environment-dependent fix. Validate **the whole loop**.
```bash
# a confirmar — the systemd unit name (the fix assumes grub-btrfsd.service, not grub-btrfs.path):
systemctl list-unit-files | grep -i grub-btrfs      # confirm 'grub-btrfsd.service' exists
systemctl is-enabled grub-btrfsd.service            # should be 'enabled' after 50-snapshots

# the snapper root config must exist and be usable (this is the module's post-condition):
sudo snapper -c root list                           # must succeed; module dies loudly if not
mountpoint -q /.snapshots && echo "/.snapshots mounted OK"   # archinstall subvol still mounted

# end-to-end: make a change, confirm a snapshot appears, then actually roll back
sudo pacman -S --noconfirm cowsay                   # snap-pac makes pre/post snapshots
sudo snapper -c root list | tail                    # see the new snapshots
sudo grub-mkconfig -o /boot/grub/grub.cfg           # (50-snapshots already did this)
sudo reboot                                          # at GRUB, open "Arch Linux snapshots" submenu,
                                                     # boot a pre-change snapshot, then from it:
#   sudo snapper rollback   &&   sudo reboot          # you should be back to the pre-cowsay state
```
Pass criteria: `grub-btrfsd.service` enabled, `snapper -c root list` works, a GRUB **snapshots submenu**
appears with bootable entries, and a `snapper rollback` from a booted snapshot reverts the system.
**If `systemctl list-unit-files | grep grub-btrfs` shows a different unit name, tell me — the fix needs
that exact name.**

### 2.4 Error handling & resume — **REL-02 / REL-03**
The fix makes best-effort steps non-fatal and adds a resumable ERR trap.
```bash
# best-effort: simulate a transient rustup failure and confirm the install does NOT abort.
#   e.g. temporarily break network during 30-dev, or run:
sudo ip link set <iface> down    # then ./install.sh 30-dev ; expect a yellow "skipped (non-fatal)" warn, not an abort
sudo ip link set <iface> up

# resume + checkpoints:
ls ~/.local/state/archfrican/                       # one <module>.done file per completed module
./install.sh                                         # a re-run prints "skip <module> (already done)"
FORCE=1 ./install.sh                                 # re-runs everything
./install.sh 30-dev                                  # always re-runs just that module
# on a real mid-install failure you should see: "step '<module>' FAILED … resume with ./install.sh <module>"
```
Pass criteria: a failing best-effort step warns and continues; a hard failure prints the resume hint;
completed modules are skipped on a normal re-run; `FORCE=1` redoes them.

### 2.5 Ghostty + spawn completeness — **QUAL-01**
```bash
pacman -Q ghostty                                    # must be installed (it's in packages/niri-desktop.txt)
# the post-install spawn check should have printed:  ✓ all niri spawns resolve
# negative test (optional): remove ghostty from packages/niri-desktop.txt and re-run — install.sh must
# DIE at verify_spawns with "config spawns binaries no package installs: ghostty"
```
After reboot into niri: **`⌘+Return` (Mod+Return) must open a ghostty terminal.**

### 2.6 Theme switcher (Approach B) — **DATA-01 / DATA-03 / QUAL-03**
The deployed switcher must work from a normal shell and survive `chezmoi apply`.
```bash
ls -l ~/.local/bin/theme-switch                      # must be a SYMLINK into ~/.archfrican/bin/theme-switch
theme-switch tokyo-night                              # runs from PATH, prints "switched to tokyo-night"
cat ~/.config/.archfrican-theme                       # -> tokyo-night
chezmoi apply                                         # MUST NOT revert the theme (color files are chezmoi-ignored;
                                                       # run_after re-applies the saved theme)
grep -c 'THEME-START' ~/.config/niri/config.kdl       # still exactly 1 (no duplication)
for t in macos-dark macos-light catppuccin-mocha tokyo-night; do theme-switch "$t"; done   # all 4 work
```
Pass criteria: the on-PATH `theme-switch <name>` works for all four themes (the old deployed copy was
dead), and a `chezmoi apply` does **not** snap the theme back to macos-dark. Live reload: waybar + mako
repaint immediately; ghostty/fuzzel apply to new windows (this is expected — see the README note).

### 2.7 Idempotency / re-run safety
```bash
./install.sh && ./install.sh                          # second run is a no-op-ish: pac_install skips installed pkgs,
                                                       # snapper config is not recreated, /etc writes are deterministic
```
Pass criteria: no errors, no duplicated repo stanzas, no duplicated GRUB/mkinitcpio edits, theme intact.

---

## 3. "A confirmar" — quick command reference

Run these on the target and report any mismatch (they couldn't be verified off-Arch):

| Item | Command | Expected |
|------|---------|----------|
| grub-btrfs unit name | `systemctl list-unit-files \| grep grub-btrfs` | `grub-btrfsd.service` present |
| ghostty repo | `pacman -Si ghostty` | resolves in `extra` (else move it to `packages/aur.txt`) |
| snapper timers | `systemctl list-unit-files \| grep -E 'snapper-(timeline\|cleanup)'` | both exist |
| nvidia suspend/resume (NVIDIA only) | `systemctl list-unit-files \| grep nvidia` | suspend/resume/hibernate units exist |
| vulkan-swrast | `pacman -Si vulkan-swrast` | resolves (VM software-Vulkan fallback) |
| archinstall fstab | `grep snapshots /etc/fstab` | `@.snapshots` mounted at `/.snapshots` |
| snapper csv support | `snapper --csvout list-configs --columns config` | works (module has an awk fallback if not) |

---

## 4. Recovery drills (validate the safety net itself)

Before trusting this on real hardware, prove you can recover:
1. **Boot the LTS kernel:** at GRUB, pick `linux-lts` and confirm the system boots (the dual-kernel net).
2. **Boot a snapshot:** GRUB → "Arch Linux snapshots" → boot a pre-update snapshot (read-only).
3. **Roll back:** from a booted snapshot, `sudo snapper rollback && sudo reboot` → confirm the system is
   back to that earlier state.

If any of these three fails, the "rollback in one reboot" promise is not yet real on your hardware —
stop and fix `50-snapshots.sh` / the GRUB config before bare-metal.

---

## 5. Pass/fail checklist

Tick every box on the VM before bare metal:

- [ ] Static: `bash -n` + shellcheck clean; CI green.
- [ ] Phase 1: Btrfs + `@.snapshots` in fstab; correct disk; reboots.
- [ ] **SEC-01:** install completes all 6 modules; no `target not found`; preflight passes.
- [ ] **REL-01:** `lspci` present; VM resolves `unknown` and install proceeds; right GPU stack on real HW.
- [ ] **DATA-02:** `grub-btrfsd.service` enabled; `snapper -c root list` works; `/.snapshots` mounted;
      snapshots appear in GRUB; `snapper rollback` reverts.
- [ ] **REL-02/03:** best-effort step failure warns & continues; resume hint + checkpoints work.
- [ ] **QUAL-01:** `ghostty` installed; `⌘+Return` opens it; `verify_spawns` passed.
- [ ] **DATA-01/03:** `~/.local/bin/theme-switch` is a symlink; all 4 themes apply from PATH; `chezmoi
      apply` does not revert the theme.
- [ ] Idempotency: a second `./install.sh` is safe.
- [ ] Recovery drills (LTS boot, snapshot boot, rollback) all pass.

---

## 6. Resetting between runs
- VM: restore the `pre-phase2` snapshot and re-run phase 2.
- Checkpoints only: `rm -rf ~/.local/state/archfrican` (forces every module to re-run) or `FORCE=1 ./install.sh`.
- Logs: the installer prints colored `==>/✓/!/✗` lines; capture them with `./install.sh 2>&1 | tee install.log`
  (note `*.log` is gitignored).
