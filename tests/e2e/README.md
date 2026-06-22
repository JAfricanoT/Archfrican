# e2e self-test — run the full armed install in a throwaway VM, automatically checked

This harness runs the **real armed installer** end-to-end inside a disposable UEFI VM and asserts the
result, so a feature/integration can be regression-tested without eyeballing every step. You drive your
own VM (UTM / VirtualBox / qemu — whatever you already use); the harness runs **inside** it. The only
manual touch is typing the LUKS passphrase once at first boot — which *is* the test for "exactly one
passphrase prompt".

It maps to the 8 checks in [docs/STAGE2-VALIDATION.md](../../docs/STAGE2-VALIDATION.md): the on-disk ones
(#4 cryptdevice, #6 packages incl. cryptsetup, #7 resume wired, plus the full install correctness) are
verified **before reboot**; the runtime ones (#2 boots, #3 single passphrase, #7 resume self-cleans,
snapper/NetworkManager/zsh) are verified **after** the resume by `postboot`; #5 has its own `rerun` mode.

## Why "inside the VM" (not a qemu orchestrator)
No serial-console driving, no OVMF/pexpect plumbing, and it doesn't care that an x86_64 guest is slow
under TCG on Apple Silicon — you boot the VM however you like and run one command in it.

## Safety
`install`/`rerun` **wipe the target disk**. They only proceed because the harness sets the explicit gates in
the env (`ARCHFRICAN_AUTOPILOT=1` + `ARCHFRICAN_ISO_ARMED=1` + `ARCHFRICAN_ISO_GO=1` +
`ARCHFRICAN_AUTOPILOT_CONFIRM_WIPE=<device>`). The committed repo **defaults to `ARCHFRICAN_ISO_ARMED=0`**
(CI enforces it) and autopilot also requires the exact-device confirm — so none of this can fire from a
normal run on a real machine. Use only in a disposable VM.

## Prerequisites
- A **UEFI/OVMF** VM (UTM, VirtualBox with EFI enabled, or qemu `-bios OVMF`), ≥4 GB RAM, a **throwaway
  ≥25 GB disk**, networking up.
- A current **Arch ISO** booted in it (root autologin).
- **3D acceleration enabled in the VM** (see below) — otherwise the install completes but the **graphical
  desktop is a black screen**: niri (Wayland) needs a GPU render device.

## Wayland needs a GPU — enable 3D acceleration in your VM
niri (like every Wayland compositor) requires a DRM **render** device. A VM only exposes one when 3D
acceleration / virtio-gpu is on. Confirm inside the guest with `ls /dev/dri/` — you want a **`renderD128`**
(not just `card0`). To enable it on the **host**:
- **virt-manager (QEMU/KVM)** — the **XML** is the reliable path (the GUI checkboxes move/disappear between
  versions). `virsh edit <vm>` (or `virsh -c qemu:///session edit <vm>` for the user session; or
  virt-manager → Edit → Preferences → *Enable XML editing*, then the VM's **XML** tab). Set:
  ```xml
  <graphics type='spice'>
    <listen type='none'/>
    <gl enable='yes' rendernode='/dev/dri/renderD128'/>
  </graphics>
  <video><model type='virtio' heads='1' primary='yes'><acceleration accel3d='yes'/></model></video>
  ```
  GUI equivalent — **Display Spice**: *Listen type* (dropdown) = **None** → Apply; then the **separate
  `OpenGL` checkbox** (it is NOT one of the Listen-type values — that dropdown only has `address`/`none`) =
  ✅, and set its *Render node* if it shows `Auto`. **Video**: *Model* = **Virtio** + **3D acceleration** ✅.
- **Two common errors:**
  - `display backend does not have OpenGL support enabled` → Video 3D is on but the Display GL is not (enable
    the OpenGL checkbox / `<gl enable='yes'/>`).
  - `No DRM render nodes available` → the **HOST** has no usable render node (`ls /dev/dri/` on the host shows
    no `renderD128`). Most common with the **NVIDIA proprietary** host driver — it exposes `/dev/nvidia*`, not
    a mesa `/dev/dri/renderD128`, so virgl can't use it. Fixes: use **nouveau** on the host, run the VM on an
    Intel/AMD/nouveau host, or add your user to the `render`/`video` group if the node exists but is
    inaccessible.
- With `Listen:None` you can only view via the local virt-manager console, not a remote SPICE client.
- **plain qemu** — `-device virtio-gpu-gl-pci -display gtk,gl=on` (or `sdl,gl=on`).
- **UTM** — Display → *Emulated Display Card* = `virtio-gpu-gl (GPU Supported)`.
- **VirtualBox** — Display → Graphics Controller = **VMSVGA** + **Enable 3D Acceleration**.

(The base install itself doesn't need 3D — only the desktop does. The installer's GPU profile **vm** installs
software rendering, but niri still needs the DRM render node the steps above provide.)

## Steps
1. Boot the Arch ISO in the VM. Get the repo (the one-liner self-clones into `/root/.archfrican`, or clone
   manually):
   ```
   pacman -Sy --noconfirm git && git clone https://github.com/JAfricanoT/Archfrican /root/.archfrican
   cd /root/.archfrican
   ```
2. Set the answers — copy and edit `tests/e2e/answers.env`, or just export them:
   ```
   cp tests/e2e/answers.env.example tests/e2e/answers.env && nano tests/e2e/answers.env
   ```
3. Run the armed autopilot install + pre-reboot assertions:
   ```
   tests/e2e/selftest.sh install
   ```
   It prints `ALL N CHECKS PASSED` (or the failures) and leaves `/mnt` mounted.
4. Reboot. **Type the LUKS passphrase once** at the prompt — there must be **exactly one** prompt and
   GRUB must not ask (check #3). Try `AF_AP_XKB=latam`/`es` to confirm the keymap works there.
5. After the desktop settles (the first-boot resume installs CachyOS + niri + dev layer unattended —
   watch `journalctl -u archfrican-resume`), run the post-reboot checks:
   ```
   ~/.archfrican/tests/e2e/selftest.sh postboot
   ```

## Re-run safety (#5), on the ISO
```
tests/e2e/selftest.sh rerun     # installs, then installs AGAIN; the stale-state guard must recover
```

## What each subcommand asserts
- **install / assert** (pre-reboot): GPT layout, LUKS2 on root, btrfs subvolumes + zstd mounts, ESP at
  /boot, `cryptsetup` present in the target, kernel+initramfs+GRUB+EFI entry, `cryptdevice=UUID=` matches
  the container, mkinitcpio HOOKS order, user created + root locked, NetworkManager(+wait-online) enabled,
  zram, and the resume fully wired.
- **postboot**: booted with the LUKS root unlocked, `cryptdevice` in the live cmdline, resume self-disabled
  (cleanup ran), snapper `root` config present, NetworkManager active, login shell zsh, `awww-daemon`
  resolves, both kernels installed, niri config rendered.

## CI
This needs a KVM-capable Linux host to run in reasonable time (a full install + desktop resume is
20–40 min); it is **not** a per-push job. A `workflow_dispatch` wrapper on a KVM runner can reuse the
exact same autopilot env contract.
