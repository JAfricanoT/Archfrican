# Archfrican — Hardware Compatibility

---

## Minimum requirements

| Requirement | Minimum |
|-------------|---------|
| Architecture | x86_64 |
| Firmware | UEFI (BIOS is not supported) |
| Disk | 20 GiB (one whole disk; partitioning is automatic) |
| RAM | 4 GB (8 GB recommended for comfort) |
| Internet | Required during Phase 1 (`pacstrap`) and Phase 2 (AUR packages) |

The installer checks these at startup (preflight) and aborts with a clear message if
any requirement is not met.

---

## GPUs

GPU drivers are auto-detected by `lib/detect-gpu.sh` using `lspci`. The 10-gpu module
installs the correct stack without manual input.

| GPU type | Detected as | Packages installed | Notes |
|----------|------------|-------------------|-------|
| AMD (RX 400 series and newer) | `amd` | mesa, vulkan-radeon, vulkan-icd-loader | Open-source stack. Zero extra config; the most reliable path on Wayland. |
| Intel (Gen 8+ / Iris / Arc) | `intel` | mesa, vulkan-intel, intel-media-driver, vulkan-icd-loader | Open-source stack. Hardware video decode via VA-API. |
| NVIDIA Maxwell / Pascal / Volta (GTX 700–1600, RTX 20–30) | `nvidia` | nvidia-dkms, nvidia-utils, egl-wayland, libva-nvidia-driver | Proprietary driver. Wayland is stable since driver 525+. Early KMS is configured automatically. |
| NVIDIA Turing+ (RTX 20 series and newer) | `nvidia` | nvidia-open-dkms, nvidia-utils, egl-wayland, libva-nvidia-driver | Open-kernel module (preferred on Turing+). Same Wayland experience. |
| NVIDIA legacy (Fermi/Kepler, GTX 400–700) | `nvidia` → nouveau tier | mesa, vulkan-swrast | The proprietary 390xx/470xx packages break on CachyOS kernels. nouveau (in-kernel) is used instead. 3D performance is limited. |
| AMD + Intel (hybrid laptop) | `hybrid-amd-intel` | mesa, vulkan-radeon, vulkan-intel, intel-media-driver, vulkan-icd-loader | Both open stacks installed side by side. |
| NVIDIA + Intel (hybrid laptop, e.g. Optimus) | `hybrid-intel-nvidia` | nvidia-dkms/open-dkms + mesa + vulkan-intel | Proprietary NVIDIA driver with Intel iGPU open stack. |
| NVIDIA + AMD (hybrid desktop) | `hybrid-amd-nvidia` | nvidia-dkms/open-dkms + mesa + vulkan-radeon | Proprietary NVIDIA driver with AMD iGPU open stack. |
| VM (virtio-gpu, QXL, VMware SVGA, Hyper-V) | `vm` | mesa, vulkan-swrast | Software rasterizer (llvmpipe). niri needs a DRM device — enable virtio-gpu / 3D acceleration in the hypervisor. |

**Unknown GPU**: if `lspci` is unavailable or no match is found, the module echoes
`unknown` and exits gracefully. Install drivers manually after Phase 2.

**Wayland requirement**: niri is a Wayland-native compositor. An NVIDIA GPU requires
driver 525 or newer for stable Wayland support. Pascal-era (GTX 10xx) cards with
`nvidia-dkms` work well.

---

## TPM 2.0 (auto-unlock LUKS at boot)

| Requirement | Detail |
|-------------|--------|
| TPM chip | TPM 2.0 (not 1.2) |
| LUKS version | LUKS2 (Archfrican's default) |
| Secure Boot | Recommended — adds PCR 7 binding (TPM unlock is weaker without it) |

**Setup**: after installation, run:

```bash
archfrican-tpm-unlock
```

**Recovery**: if the TPM slot fails (firmware update, PCR drift), enter your passphrase
at boot. The passphrase keyslot is never removed. Re-enroll with `archfrican-tpm-unlock`.

---

## FIDO2 / Security keys (sudo and login)

Any FIDO2-compatible hardware key is supported via `pam-u2f`:

- YubiKey 5 series (USB-A, USB-C, NFC, nano)
- YubiKey 4 (FIDO U2F only)
- Google Titan Security Key
- Any FIDO2/WebAuthn key compliant with the FIDO2 standard (libfido2)
- Passkeys on Android/iOS (via Bluetooth) — not supported in PAM mode

**Setup**:

```bash
archfrican-fingerprint     # enroll; prompts to touch the key twice
```

The key is added as `sufficient` in PAM — your password always remains a fallback.
Losing the key does not lock you out.

---

## Fingerprint readers

Fingerprint authentication is supported via `fprintd` and `libfprint` on compatible hardware.

**Setup**:

```bash
archfrican-fingerprint     # if a fingerprint reader is detected, offers enrollment
```

**Compatible hardware**: most built-in fingerprint sensors on ThinkPads, Frameworks, and
Dell XPS laptops are supported. For a device-specific compatibility list, consult:

- [linux-hardware.org](https://linux-hardware.org) — filter by `fprintd` or `libfprint`
- [fprint.freedesktop.org](https://fprint.freedesktop.org/supported-devices.html) — official list

**Not supported**: some Apple/Synaptics sensors and most USB-external readers have no
Linux driver. The installer skips fingerprint enrollment gracefully if no compatible
reader is found.

---

## WiFi

Archfrican inherits Arch Linux WiFi support — if the firmware is in the Arch repos, it works.

| Driver status | Examples |
|--------------|---------|
| Works out of the box | Intel AX200/AX210 (iwlwifi), Realtek RTL8821CE (kernel 6.2+), Atheros QCA6174 (ath10k), MediaTek MT7921 (mt7921e) |
| Works with AUR firmware | Some Realtek adapters (rtl8821cu-dkms, rtl88x2bu-dkms) |
| Limited support | Broadcom (brcmfmac works on many; b43/wl are problematic) |
| Not supported | Some USB WiFi adapters with proprietary-only drivers |

**During Phase 1**: if the installer is running from the Archfrican ISO, WiFi credentials
entered via `nmtui` or `iwctl` are copied to the installed system automatically.

**Wired ethernet**: always preferred for installation — avoids firmware dependency.

---

## Secure Boot

Secure Boot setup is optional and runs after installation:

```bash
archfrican-secureboot
```

**Requirements**:
- Firmware in Setup Mode (check: `sbctl status` — should show `Setup Mode: Enabled`)
- GRUB is kept as the bootloader (no systemd-boot or rEFInd)

**Process**: `sbctl` creates and enrolls custom PK/KEK/db keys, then signs GRUB and
all installed kernels.

**Safety**: if boot fails after enabling Secure Boot in firmware, disable Secure Boot —
no brick risk, LUKS passphrase is unaffected.

---

## Summary table

| Feature | Tool | Opt-in? |
|---------|------|---------|
| GPU drivers | Auto (module 10-gpu) | No — auto at Phase 2 |
| TPM2 LUKS unlock | `archfrican-tpm-unlock` | Yes — user-initiated |
| FIDO2 auth | `archfrican-fingerprint` | Yes — wizard or manual |
| Fingerprint auth | `archfrican-fingerprint` | Yes — wizard or manual |
| Secure Boot | `archfrican-secureboot` | Yes — post-install |
| Gaming (32-bit, Steam) | Module 65-gaming | Yes — `./install.sh 65-gaming yes` |
