# Stage 2 (ISO full install) — VM validation

Stage 2 boots the Arch live USB and installs a complete, encrypted Archfrican that finishes its
desktop/dev layer **automatically after the first reboot**. It is driven by our own **bedrock-tools base
installer** ([lib/base-install.sh](../lib/base-install.sh): `sgdisk`, `cryptsetup`, `mkfs.btrfs`, `pacstrap`,
`genfstab`, `arch-chroot`, `grub-install`, `mkinitcpio`) — **no archinstall**, no JSON config, no creds
file. Because it **partitions and formats a disk**, it **defaults to a dry-run preview**; a real install is
an explicit opt-in. Validate on a VM before trusting it on real hardware.

## Why it defaults to preview — the gates
1. **`ARCHFRICAN_ISO_ARMED`** (in [lib/base-install.sh](../lib/base-install.sh)) **defaults to `0`** — it is
   `${ARCHFRICAN_ISO_ARMED:-0}`, set at runtime, never by editing the file. While `0`, every destructive op
   goes through `run`/`run_pipe`, which **print the exact command and execute nothing** — so a preview run
   prints the *entire* install plan (partition → LUKS → mkfs → subvolumes → pacstrap → arch-chroot → GRUB,
   with `<UUID>` placeholders) and touches **no disk**. A real install is armed by either:
   - **env**: `ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1`, or
   - **interactive**: answer **yes** to the wizard's "REAL install?" prompt (which defaults to preview).

   `ARCHFRICAN_DRY_RUN=1` forces preview. CI enforces that the committed file always defaults to `0`.
2. **`confirm_wipe`** ([lib/disk.sh](../lib/disk.sh)) — armed either way, you still **retype the exact device
   name** before anything is written. This is the final gate.

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

## Step B — Run the real install (no file edit)
**Snapshot the VM first.** Then arm it any of these ways:
- **Interactive** — re-run the one-liner, do the wizard, answer **yes** to "REAL install?", and retype the
  device at `confirm_wipe`; or
- **Env (headless-friendly)**:
  ```
  ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1 sh -c "$(curl -fsSL https://raw.githubusercontent.com/JAfricanoT/Archfrican/refs/heads/main/install.sh)"
  ```
  then retype the device at `confirm_wipe`; or
- **Automated** — `tests/e2e/selftest.sh install` (autopilot install + the on-disk assertions; see
  [tests/e2e/README.md](../tests/e2e/README.md)).

The base install runs for real, `inject_resume` wires the first-boot service, and you reboot.

### Pass criteria — all must hold (the design's 8 checks)
- [ ] The install completes; the system boots from the new disk.
- [ ] **Exactly one passphrase prompt** at boot (the initramfs `encrypt` hook — GRUB must NOT prompt; the
      plaintext ESP=/boot is what guarantees this). A non-`us` keyboard layout (latam/es) **works at that
      prompt** (`keyboard keymap` are before `block encrypt`).
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

The committed `main` **always defaults to `0`** (CI-enforced) — arming is a runtime opt-in, never a commit.
`tests/e2e/selftest.sh` automates this whole flow (the install + the assertions) inside a VM.

## Optional — zero-prompt boot (not the default)
On trusted hardware with a TPM2, enroll the LUKS key for a no-passphrase boot:
```
sudo systemd-cryptenroll --tpm2-device=auto /dev/<luks-root-partition>
```
Left out of the default — hardware-specific and weakens at-rest protection if the TPM isn't trustworthy.
