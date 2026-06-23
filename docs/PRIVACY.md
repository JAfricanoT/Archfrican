# Privacy & data posture

Archfrican collects **no telemetry of its own** — no analytics, no phone-home, no account. The
installer, the convergent updater (`archfrican-update`), the health check (`archfrican-doctor`) and the
helper tools all run entirely on your machine.

## What is set for you

- **`DO_NOT_TRACK=1`** is exported in the session (niri `environment`). This is a community convention
  ([donottrack.sh](https://donottrack.sh)) honored by a growing set of modern CLI/dev tools — **not all
  of them** — so treat it as a helpful signal, not a guarantee. App-specific opt-outs still matter.
- **VS Code / Code-OSS** — `archfrican-privacy` sets `telemetry.telemetryLevel: off`. Note that
  *extensions* collect independently; review the ones you install.
- **fwupd** records firmware-update results locally, but **uploading** that history to LVFS is opt-in
  upstream; Archfrican never enables the upload.

## What can still phone home (yours to control)

Browsers (Brave/Vivaldi, opt-in), Steam/Proton (opt-in gaming), Flatpak apps, and editor extensions
each ship their own settings. `archfrican-privacy` summarizes them; Flatpak permissions are inspectable
in **Flatseal**.

## Filesystem strategy: snapshots, not image-based immutability

Archfrican is a **mutable, rolling** Arch system made **recoverable** with Btrfs + Snapper snapshots
(one-reboot rollback) — deliberately *not* an image-based atomic system (Fedora Silverblue/OSTree,
bootc). The trade-off:

- Snapshots fit a rolling CachyOS base and native **AUR** build-from-source, and give a one-reboot way
  back from a bad update. (A snapshot is a consistent point-in-time; the update itself is **not**
  transactionally atomic the way an OSTree deployment swap is — rollback ≠ image atomicity.)
- Image-based atomic systems optimize for **reproducibility / a fleet baseline** and reboot-to-apply
  layering — a *poor fit* (not strictly impossible) for per-package rolling updates and AUR.

Archfrican stays mutable-but-recoverable on purpose. Hardware-rooted trust is available opt-in without
changing that model: `archfrican-secureboot` (Secure Boot via sbctl, keeps GRUB) and
`archfrican-tpm-unlock` (TPM2 LUKS auto-unlock, your passphrase always still works).
