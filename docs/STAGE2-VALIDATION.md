# Stage 2 (ISO full install) — VM capture & validation

Stage 2 boots the Arch live USB and installs a complete, encrypted Archfrican that finishes its
desktop/dev layer **automatically after the first reboot**. Because it **partitions and formats a
disk**, it ships **disabled** and must be validated on a VM before it is armed.

## Why it ships disabled

Two independent gates stand between this code and a wiped disk:

1. **`ARCHFRICAN_ISO_ARMED`** (in [lib/phase1.sh](../lib/phase1.sh)) ships `0`. Unarmed, the ISO path
   runs **`archinstall --dry-run` only** — it validates the generated config and saves *what it would
   do*; **no disk is touched**. Arming additionally requires the runtime opt-in `ARCHFRICAN_ISO_GO=1`.
2. **`confirm_wipe`** ([lib/disk.sh](../lib/disk.sh)) — even when armed, you must retype the exact
   device name before the format.

The committed [archinstall/user_config.json](../archinstall/user_config.json) is a **base template**.
`lib/phase1.sh::gen_config` injects the wizard's disk/encryption/hostname/timezone into it. The exact
**archinstall 2.x `disk_config` / `encryption` / `user_credentials` / `custom_commands` schema is
version-specific** and is captured on a VM here — never guessed.

## Prerequisites

- A VM with **UEFI/OVMF firmware** (required: `preflight iso` fails on BIOS), ≥4 GB RAM, a **throwaway
  ≥25 GB disk**, and a **snapshot** taken before each destructive run.
- A current **Arch ISO** booted in that VM, with networking up.
- Record the archinstall version: `archinstall --version` (the schema is tied to it).

---

## Step A — Dry-run capture (no disk touched)

1. Boot the Arch ISO in the VM (as root). Run the one-liner:
   ```
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/JAfricanoT/Archfrican/refs/heads/main/install.sh)"
   ```
   It self-clones, runs `preflight iso`, the wizard (pick the VM disk, choose **encrypt = yes**, set a
   user/password/passphrase), then **because it is unarmed** runs `archinstall --dry-run` and exits
   without touching the disk.
2. Confirm the dry-run **accepts the generated config** (no schema error). If it errors, note the exact
   complaint — that *is* the schema gap to close in Step B.

## Step B — Capture the authoritative schema

Run archinstall **guided** once to get a known-good config for *this* archinstall version:

1. `archinstall` (the interactive TUI). Configure to match our base: **GRUB**, **Btrfs** with the
   `@ / @home / @log / @pkg / @.snapshots` subvolumes, **Snapper**, **LUKS on root, plaintext ESP**,
   NetworkManager, pipewire, Minimal profile, **root disabled / sudo user**, your VM disk.
2. Before installing, use **"Save configuration"** → save `user_configuration.json` +
   `user_credentials.json` (and `user_disk_layout.json` if offered). Or run `archinstall --dry-run` from
   the TUI, which writes the config to `/var/log/archinstall/` (or the path it prints).
3. **Diff** that saved config against what `gen_config` produced in Step A. Reconcile each
   **a-confirmar** below into `archinstall/user_config.json` (base) and/or `lib/phase1.sh::gen_config`
   (injection). Commit the corrected base — *that* is the validated schema.

### a-confirmar checklist (close each from the saved config)

| # | Item | How to close |
|---|------|--------------|
| 1 | `disk_config` 2.x shape (`config_type`, `device_modifications`) + `encryption` block | Copy verbatim from the saved `user_configuration.json`; adjust `gen_config` to inject the device into the right field. |
| 2 | `user_credentials.json` keys (user vs encryption password; plaintext vs hash) | Match the saved creds keys in `gen_creds`. |
| 3 | `custom_commands` key/semantics (if used as the resume-injection path) | If present and able to `git clone` + `systemctl enable`, prefer it over the `/mnt` injection in `inject_resume`. |
| 4 | Disable-root / sudo-only representation | Match how the TUI encoded it (empty `root_password`, a `!` marker, or a setting). |
| 5 | Does `archinstall --silent` leave the target mounted at `/mnt`? | If **no**, `inject_resume` must remount (and `cryptsetup open` for LUKS) before injecting; update it. If **yes**, current code works. |
| 6 | `is_iso` marker (`/run/archiso`) on this ISO build, and resume ordering | Confirm `[ -d /run/archiso ]` is true on the live medium; confirm `network-online.target` is reached before the resume runs. |

## Step C — Arm and validate the real install

1. In a branch, set `ARCHFRICAN_ISO_ARMED=1` in `lib/phase1.sh` and point `ARCHFRICAN_REF` at it.
2. **Snapshot the VM.** Re-run the one-liner with the opt-in:
   ```
   ARCHFRICAN_ISO_GO=1 sh -c "$(curl -fsSL https://raw.githubusercontent.com/.../install.sh)"
   ```
   Retype the device name at `confirm_wipe`. archinstall now installs for real, then `inject_resume`
   wires the first-boot service and reboots.

### Pass criteria (all must hold)

- [ ] `archinstall --silent` completes; the system boots from the new disk.
- [ ] **Exactly one passphrase prompt** at boot (initramfs only — GRUB must not prompt). This is the
      whole point of plaintext-ESP + LUKS-on-root; if GRUB *also* prompts, the layout is wrong.
- [ ] After login/boot, `archfrican-resume.service` runs and finishes the **6 modules + chezmoi**
      unattended (`journalctl -u archfrican-resume`), reading `~/.archfrican-answers` (correct
      GPU/theme/keyboard).
- [ ] On success the service **disables itself** (`systemctl is-enabled archfrican-resume` → `disabled`)
      and **removes** `/etc/sudoers.d/00-archfrican-resume` (the NOPASSWD window lasted one boot).
      `/etc/sudoers.d/10-archfrican-wheel` (password sudo) remains.
- [ ] Re-running (force a mid-way failure, reboot) **resumes** via the `.done` checkpoints, then cleans
      up — no duplicate work, no broken sudo.
- [ ] niri starts, theme + keyboard layout match the wizard, snapshots/rollback work (see
      [VALIDATION.md](VALIDATION.md) for the desktop-layer checks).

Only after every box is checked should `ARCHFRICAN_ISO_ARMED=1` be merged to `main`.

## Optional — zero-prompt boot (not the default)

On trusted hardware with a TPM2, enroll the LUKS key so no passphrase is typed at all:
```
sudo systemd-cryptenroll --tpm2-device=auto /dev/<luks-partition>
```
Leave this **out of the default** — it is hardware-specific and weakens at-rest protection if the TPM is
not trustworthy. Document it for users who opt in.
