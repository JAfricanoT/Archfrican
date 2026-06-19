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
`install`/`rerun` **wipe the target disk**. They only proceed because the harness arms the VM's *own*
clone (`sed ARCHFRICAN_ISO_ARMED=1`) and sets the explicit autopilot gates
(`ARCHFRICAN_AUTOPILOT=1` + `ARCHFRICAN_ISO_GO=1` + `ARCHFRICAN_AUTOPILOT_CONFIRM_WIPE=<device>`). The
**shipped** repo always stays `ARCHFRICAN_ISO_ARMED=0` (CI enforces it), so none of this can fire from a
normal run on a real machine. Use only in a disposable VM.

## Prerequisites
- A **UEFI/OVMF** VM (UTM, VirtualBox with EFI enabled, or qemu `-bios OVMF`), ≥4 GB RAM, a **throwaway
  ≥25 GB disk**, networking up.
- A current **Arch ISO** booted in it (root autologin).

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
