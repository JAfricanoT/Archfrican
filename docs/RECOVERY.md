# Archfrican — Recovery Playbook

Ten scenarios with symptoms, causes, and exact steps.

---

## 1. System won't boot — GRUB or black screen before login

**Symptom**: machine powers on but never reaches SDDM or a shell.

**Step 1 — Try a Btrfs snapshot**

At the GRUB menu, hold `Shift` to open the menu if it auto-hides. Select
`Archfrican Snapshots` from the submenu to boot into a known-good state.
This works without any external media.

**Step 2 — chroot from a live USB**

Boot an Arch ISO (or the Archfrican ISO):

```bash
# Identify your disk — usually nvme0n1 or sda
lsblk

# If LUKS encrypted:
cryptsetup open /dev/nvme0n1p2 root

# Mount Btrfs subvolumes
mount -o subvol=@ /dev/mapper/root /mnt
mount -o subvol=@home /dev/mapper/root /mnt/home
mount /dev/nvme0n1p1 /mnt/boot

# chroot
arch-chroot /mnt
```

Inside the chroot you can:

```bash
# Reinstall GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Archfrican
grub-mkconfig -o /boot/grub/grub.cfg

# Regenerate initramfs
mkinitcpio -P

# Roll back to a snapshot
snapper -c root list
snapper -c root rollback <N>
```

---

## 2. Black screen after SDDM login

**Symptom**: SDDM greeter appears, credentials accepted, then a black screen.

**Cause A — invalid niri config**

Press `Ctrl+Alt+F2` to reach a TTY. Log in. Validate and fix the config:

```bash
niri validate
# fix errors in ~/.config/niri/config.kdl
# then kill the failed session:
systemctl --user restart niri
```

**Cause B — GPU driver mismatch**

```bash
# Check for driver errors:
journalctl -b | grep -iE 'drm|nvidia|amdgpu|i915|error'

# Re-run the GPU module (installs/switches drivers):
~/.archfrican/install.sh 10-gpu
```

**Cause C — Wayland session not starting**

```bash
journalctl --user -u graphical-session.target -b
# look for the failing unit and fix or restart it
```

---

## 3. LUKS: passphrase not accepted

**Cause**: LUKS2 passphrases are irrecoverable by design. There is no backdoor.

**What to do**:

- Double-check keyboard layout — the boot initramfs may use a different layout than
  your installed system. Try typing the passphrase assuming a US layout.
- If using TPM2 auto-unlock and it fails, the passphrase keyslot is unaffected. Type
  the passphrase manually.
- There is no recovery path for a forgotten LUKS passphrase. Keep it in a password
  manager and/or hardware security key.

To remove a broken TPM2 enrollment (passphrase still works):

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
```

---

## 4. FIDO2 key lost or not working

**Your password always works.** FIDO2 is added as `sufficient` — PAM falls through to
the password if the key is absent or declined. You cannot lock yourself out.

To remove FIDO2 enrollment:

```bash
sudo mv /etc/pam.d/sudo.archfrican.bak /etc/pam.d/sudo
sudo mv /etc/pam.d/system-local-login.archfrican.bak /etc/pam.d/system-local-login
sudo rm -f /etc/u2f_mappings
```

To enroll a replacement key:

```bash
⌘+Shift+A   →   "Huella / FIDO2"   →   "Agregar llave"
```

or directly:

```bash
archfrican-fingerprint
```

See [FIDO2-RECOVERY.md](FIDO2-RECOVERY.md) for the full rotation procedure.

---

## 5. TPM2 unlock fails at boot

**Symptom**: LUKS prompt appears even though TPM auto-unlock was configured.

**Cause**: TPM state changed — usually a firmware update, Secure Boot key change, or
PCR values drifted.

**Resolution**: enter your passphrase at the prompt. Once booted:

```bash
# Wipe the old TPM slot and re-enroll:
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
archfrican-tpm-unlock
```

The passphrase slot is never touched and always works as a fallback.

---

## 6. First-boot resume is stuck or keeps retrying

**Symptom**: after initial install, every boot starts `archfrican-resume.service` but
the Phase 2 install never completes.

**Check the journal**:

```bash
journalctl -u archfrican-resume -b        # current boot
journalctl -u archfrican-resume -b -1     # previous boot
```

**Manual retry**: run the installer directly:

```bash
~/.archfrican/install.sh --update
```

**Fail-safe**: the resume guard (`lib/resume-guard.sh`) counts failed boots. After
5 failed attempts it removes the temporary `NOPASSWD` sudoers drop-in and disables
`archfrican-resume.service` (fail-closed). At that point:

```bash
# Re-enable manually after fixing the root cause:
sudo systemctl enable --now archfrican-resume.service

# Or run Phase 2 directly with normal sudo:
~/.archfrican/install.sh --update
```

**Check resume counter**:

```bash
cat /var/lib/archfrican/resume-attempts
```

---

## 7. Rollback after a bad update

**Interactive** (recommended):

```bash
archfrican-rollback
```

Presents a fuzzel list of snapper checkpoints with dates and commit SHAs.
After selecting one, confirms, runs `snapper rollback <N>`, and offers to reboot.

**GRUB menu** (if the system won't boot):

Reboot → hold `Shift` at GRUB → `Archfrican Snapshots` → select a date.

**Manual snapper**:

```bash
sudo snapper -c root list
sudo snapper -c root rollback <N>
sudo systemctl reboot
```

After rollback, `archfrican-update --run` will re-converge from the rolled-back state.

---

## 8. Broken AUR package blocking updates

**Symptom**: `archfrican-update --run` fails during the AUR phase.

**Quick fix** — skip AUR this cycle:

```bash
archfrican-update --run --no-aur
```

**Identify the broken package**:

```bash
paru --aur -Su                    # run standalone to see the full error
```

**Pin to last known good version**:

```bash
# Add to /etc/pacman.conf:
IgnorePkg = broken-aur-pkg

# Reinstall last known good:
paru -U /var/cache/pacman/pkg/broken-aur-pkg-*.pkg.tar.zst
```

**Wait for upstream fix**: AUR helper failures are non-fatal in `archfrican-update`.
The system packages (`pacman -Syu`) succeed regardless.

---

## 9. CachyOS keyring expired or untrusted

**Symptom**: `pacman -Syu` or `paru` fails with `unknown trust` or
`key ... could not be looked up remotely`.

```bash
# Refresh all keys:
sudo pacman-key --refresh-keys

# If the CachyOS signing key specifically is broken:
sudo pacman-key --recv-keys <KEY_ID>
sudo pacman-key --lsign-key <KEY_ID>
```

If the keyring package itself is broken:

```bash
# Re-install from the keyring URL directly:
sudo pacman -U 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-*.pkg.tar.zst'
```

Then re-run the update:

```bash
archfrican-update --run
```

---

## 10. Reinstall without losing home data

The `@home` Btrfs subvolume is independent from `@` (root). A fresh Archfrican
install on the same disk preserves it.

**Procedure**:

1. Boot the Archfrican ISO.
2. Run the installer wizard.
3. When asked for disk: pick the same device.
4. When asked for encryption: use the **same passphrase** (LUKS container is reused).
5. The installer re-formats `@` (root) but **does not touch `@home`**.
6. After Phase 2 completes, your home directory is intact.

**What survives**: all files in `$HOME`, dotfiles, projects, photos.

**What does not survive**: installed packages (`/usr`), `/etc` config, system state.
Phase 2 re-installs everything from the repo anyway.

**Before reinstalling**: take a backup with `archfrican-backup now` as an extra
safety net, even if you are confident the procedure is non-destructive.

---

## Quick reference

| Problem | First step |
|---------|-----------|
| Won't boot at all | GRUB Snapshots submenu or live USB chroot |
| Black screen after login | `Ctrl+Alt+F2` → `niri validate` |
| LUKS passphrase rejected | Check keyboard layout; no backdoor exists |
| FIDO2 key lost | Use password; re-enroll with `archfrican-fingerprint` |
| TPM2 unlock fails | Enter passphrase; re-enroll with `archfrican-tpm-unlock` |
| Resume stuck/looping | `journalctl -u archfrican-resume`, then manual `install.sh --update` |
| Bad update | `archfrican-rollback` |
| AUR package broken | `archfrican-update --run --no-aur` |
| Keyring expired | `sudo pacman-key --refresh-keys` |
| Reinstall clean | Same disk + same passphrase; `@home` survives |
