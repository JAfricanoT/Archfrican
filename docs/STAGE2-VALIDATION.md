# Stage 2 (ISO full install) — VM validation

Stage 2 boots the Arch live USB and installs a complete, encrypted Archfrican that finishes its
desktop/dev layer **automatically after the first reboot**. It is driven by our own **bedrock-tools base
installer** ([lib/base-install.sh](../lib/base-install.sh): `sgdisk`, `cryptsetup`, `mkfs.btrfs`, `pacstrap`,
`genfstab`, `arch-chroot`, `grub-install`, `mkinitcpio`) — **no archinstall**, no JSON config, no creds
file. Because it **partitions and formats a disk**, it ships **disabled** and must be validated on a VM
before it is armed.

## Why it ships disabled — two gates
1. **`ARCHFRICAN_ISO_ARMED`** (in [lib/base-install.sh](../lib/base-install.sh)) ships `0`. Unarmed, every
   destructive op goes through `run`/`run_pipe`, which **print the exact command and execute nothing** — so
   an unarmed run prints the *entire* install plan (partition → LUKS → mkfs → subvolumes → pacstrap →
   arch-chroot → GRUB, with `<UUID>` placeholders) and touches **no disk**. Arming additionally requires the
   runtime opt-in `ARCHFRICAN_ISO_GO=1`.
2. **`confirm_wipe`** ([lib/disk.sh](../lib/disk.sh)) — even when armed, you retype the exact device name
   before anything is written.

There is no schema to capture or guess: the bedrock CLIs are stable for 10+ years, and the dry-run **is**
the audit (read the printed plan).

## Prerequisites
- A VM with **UEFI/OVMF firmware** (`preflight iso` fails on BIOS), ≥4 GB RAM, a **throwaway ≥25 GB disk**,
  and a **snapshot** before each armed run.
- A current **Arch ISO** booted in that VM (as root), networking up.

---

## Step A — Dry-run (no disk touched)
Boot the Arch ISO in the VM and run the one-liner:
```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/JAfricanoT/Archfrican/refs/heads/main/install.sh)"
```
It self-clones, runs `preflight iso`, the wizard (pick the VM disk, **encrypt = yes**, set user/password/
passphrase, timezone, keyboard…), then — because it is **unarmed** — prints the **full destructive plan**
and exits, touching nothing. **Read the plan top to bottom** and confirm:
- the ESP + root partitioning targets *your* disk (and only it);
- LUKS `luksFormat`/`open` on the root partition, `mkfs.btrfs` on `/dev/mapper/root`, the 5 subvolumes;
- `pacstrap -K /mnt base linux-lts … grub … networkmanager …`;
- the `arch-chroot` config script (locale/user/`chpasswd -e`/HOOKS with `keyboard keymap … block encrypt`/
  `cryptdevice=UUID=…:root` in `GRUB_CMDLINE_LINUX`/`grub-install`).

## Step B — Arm and validate the real install
1. In a branch, set `ARCHFRICAN_ISO_ARMED=1` in `lib/base-install.sh`; point `ARCHFRICAN_REF` at it.
2. **Snapshot the VM**, then re-run with the opt-in:
   ```
   ARCHFRICAN_ISO_GO=1 sh -c "$(curl -fsSL https://raw.githubusercontent.com/JAfricanoT/Archfrican/.../install.sh)"
   ```
   Retype the device name at `confirm_wipe`. The base install runs for real, then `inject_resume` wires the
   first-boot service and reboots.

### Pass criteria — all must hold (the design's 8 checks)
- [ ] The install completes; the system boots from the new disk.
- [ ] **Exactly one passphrase prompt** at boot (the initramfs `encrypt` hook — GRUB must NOT prompt; the
      plaintext ESP=/boot is what guarantees this). A non-`us` keyboard layout (latam/es) **works at that
      prompt** (`keyboard keymap consolefont` are before `block encrypt`).
- [ ] `cryptdevice=UUID=…` is present in `/etc/default/grub` (the chroot script asserts this) and resolves.
- [ ] **C2 (re-run safety):** deliberately abort an armed run mid-way, then re-run — the stale-state guard
      (`umount -R`/`swapoff`/`cryptsetup close`) lets it complete (no "device busy").
- [ ] **C3 (fast NVMe):** `mkfs`/`luksFormat` succeed (the `udevadm settle` holds).
- [ ] **C4 (stale keyring):** `pacstrap` succeeds even on a weeks-old ISO (the `pacman -Sy archlinux-keyring`
      refresh on the live medium ran first).
- [ ] `/mnt` is mounted at the end ⇒ `inject_resume` runs; first boot reaches `archfrican-resume.service`,
      **NetworkManager brings up the net**, it finishes the modules unattended (`journalctl -u
      archfrican-resume`), then disables itself + removes `/etc/sudoers.d/00-archfrican-resume`. Module 50
      adopts the pre-mounted `@.snapshots`.
- [ ] `/run/archiso` exists on this ISO build (so `is_iso` routes to phase 1).

Flip `ARCHFRICAN_ISO_ARMED=1` to `main` **only** in the commit that lands a green run of all of the above.

## Optional — zero-prompt boot (not the default)
On trusted hardware with a TPM2, enroll the LUKS key for a no-passphrase boot:
```
sudo systemd-cryptenroll --tpm2-device=auto /dev/<luks-root-partition>
```
Left out of the default — hardware-specific and weakens at-rest protection if the TPM isn't trustworthy.
