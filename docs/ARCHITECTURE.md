# Archfrican — Architecture

How the two-phase installer, convergence engine, and update loop work together.

---

## The two execution contexts

Archfrican has a single entry point (`install.sh`) that behaves differently depending on where
it runs. `is_iso()` checks for `/run/archiso` (only present on an Arch live medium):

```
install.sh
    │
    ├─ is_iso() == true  ──→  run_phase1()   (live USB: base OS install)
    │
    └─ is_iso() == false ──→  run_phase2()   (booted system: desktop + dev layer)
```

---

## Phase 1 — Base install (live ISO)

Runs as **root** from the Arch ISO (official or Archfrican custom). Builds the bootable
base system from scratch.

```
boot Arch ISO
    │
    └─ install.sh ──→ run_phase1()
           │
           ├─ 1. preflight iso
           │      check: UEFI, x86_64, keyring, internet, ≥20 GB disk
           │
           ├─ 2. wizard (gum TUI or autopilot env vars)
           │      pick_disk()            → /dev/nvme0n1
           │      encrypt? (LUKS)        → yes/no
           │      hostname, user         → "archfrican", "jose"
           │      locale, XKB layout     → en_US.UTF-8, us
           │      theme, GPU             → adl-dark, amd (auto-detected)
           │      multiboot, SSH         → no, no
           │      user password, LUKS passphrase (never touch argv or files)
           │
           ├─ 3. run_base_install()      [lib/base-install.sh]
           │      sgdisk --zap-all /dev/nvme0n1
           │      sgdisk --new=1 (ESP 1GiB) --new=2 (root, rest)
           │      cryptsetup luksFormat (if encrypting)
           │      cryptsetup open root
           │      mkfs.fat -F32 ESP
           │      mkfs.btrfs root
           │      mount + btrfs subvolumes: @, @home, @log, @pkg, @.snapshots
           │      pacstrap: base linux-lts grub efibootmgr networkmanager git zram-generator ...
           │      genfstab -U >> /mnt/etc/fstab
           │      arch-chroot: locale, hostname, user, GRUB install (primary + removable fallback)
           │      UEFI BootOrder → Archfrican first
           │
           └─ 4. inject_resume()         [lib/phase1.sh]
                  copy installer repo → /mnt/home/<user>/.archfrican
                  stage wizard answers → /mnt/home/<user>/.archfrican-answers
                  copy live WiFi creds → NM keyfiles + iwd PSKs into target
                  write NOPASSWD sudoers drop-in (removed after resume)
                  install archfrican-resume.service → enabled in target
                  → reboot
```

**Safety**: `ARCHFRICAN_ISO_ARMED` defaults to `0` (dry-run, prints plan, touches nothing).
Real install requires interactive opt-in or `ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1`.
`confirm_wipe` is the final gate: user must retype the bare device name (`nvme0n1`).

---

## Phase 2 — Desktop + dev layer (booted system)

Runs as the **wheel user** (never root directly) on the first boot via
`archfrican-resume.service`, and on every subsequent `archfrican-update --converge`.

```
first boot
    │
    └─ archfrican-resume.service [templates/archfrican-resume.service]
           │
           ├─ ExecStartPre: lib/resume-guard.sh
           │      counts boots; after 5 failed boots → removes NOPASSWD sudoers,
           │      disables unit (fail-closed)
           │
           └─ ExecStart: install.sh --update (as wheel user, NOPASSWD window)
                  │
                  └─ run_phase2()          [lib/phase2.sh]
                         │
                         ├─ read wizard answers from ~/.archfrican-answers
                         │
                         ├─ for each module in order:
                         │    run_module <name> [<arg>]
                         │      │
                         │      ├─ module_hash() → sha256 of (script + packages + libs)
                         │      ├─ compare to $PHASE2_STATE/<name>.done stamp
                         │      ├─ SKIP if hashes match (already applied, nothing changed)
                         │      └─ RUN  modules/<name>.sh
                         │           exit 3 = opted out (not an error)
                         │           writes new .done stamp on success
                         │
                         │    00-base → 10-gpu → 15-desktop-services → 20-niri-desktop
                         │    → 25-plasma-desktop → 30-dev → 35-apps → 40-theming → 45-print
                         │    → 50-snapshots → 55-multiboot → 60-security → 65-gaming → 70-hygiene
                         │
                         ├─ chezmoi apply     (dotfiles)
                         ├─ write_manifest()  (desired-state ledger)
                         └─ mig_mark_latest() (stamp migrations current on fresh install)

on success:
    archfrican-resume.service disables itself
    NOPASSWD sudoers drop-in removed
    → login to niri desktop
```

---

## Convergence — content-addressed modules

The core invariant: **every module is idempotent and only re-runs when its inputs change**.

```
module_hash(<name>)
    │
    ├─ collects: modules/<name>.sh
    │            packages/<name>.txt (if exists)
    │            lib/common.sh  lib/env.sh  lib/converge.sh
    │            [additional inputs declared in module_inputs()]
    │
    └─ sha256sum of all file contents + paths (order-stable)
         │
         └─ compare to $HOME/.local/state/archfrican/<name>.done
                │
                ├─ MATCH  → skip (module is current)
                └─ DIFFER → run module, write new stamp on success
```

**What this enables:**

- **Resume safety**: a crash mid-install is safe — only the unfinished module re-runs on next boot
- **Convergence updates**: `archfrican-update --run` re-runs only what changed in the pull
- **Drift detection**: `archfrican-doctor` reads `.done` stamps without sudo to report drift

**Opt-in modules** (25-plasma-desktop, 55-multiboot, 65-gaming) use `exit 3` when the opt-in flag is not set.
`run_module` treats exit 3 as "skipped by choice" — not an error, no `.done` stamp written.

---

## Migrations — one-shot state repairs

Migrations handle state that a machine accumulated over its lifetime that a fresh install
never has. They are not for idempotent configuration — modules handle that.

```
migrations/
├── 0001-resume-sudoers-rename.sh    # rename renamed file
└── 0002-greetd-to-sddm.sh          # stop old greeter, remove its config

/var/lib/archfrican/state-version   # world-readable: "0002"
```

**Semantics:**

| Scenario | state-version | Behavior |
|----------|--------------|----------|
| Fresh install | stamped to latest by `mig_mark_latest()` | No migrations run |
| Old machine (no state-version) | treated as v0 | Full delta runs |
| Regular update | e.g. "0001" | Only migrations > 0001 run |

Each migration runs once, in order, in its own bash subprocess. Progress is recorded after
each individual migration — a crash mid-delta resumes from where it left off.

`run_migrations` is called by `archfrican-update --run` before `run_phase2`.

---

## State file locations

| Path | Contents | Owner |
|------|----------|-------|
| `$HOME/.local/state/archfrican/*.done` | Module content hashes | user |
| `/var/lib/archfrican/state-version` | Migration level (world-readable) | root |
| `/var/lib/archfrican/manifest.txt` | Current desired packages | root |
| `/var/lib/archfrican/managed.txt` | Cumulative ever-managed packages | root |
| `$HOME/.config/.archfrican-theme` | Active theme name | user |
| `$HOME/.config/archfrican/` | User preferences (backup, restic, sessions…) | user |
| `$HOME/.local/state/archfrican/` | Runtime state (onboarded rev, health cache) | user |
| `$HOME/.archfrican-answers` | Wizard answers for headless resume (removed after Phase 2) | user |
| `$XDG_RUNTIME_DIR/archfrican-health.json` | Doctor `--json` cache (15 min TTL) | user |

---

## The update loop

```
archfrican-update --run
    │
    ├─ 1. precheck()
    │      disk space, mirrorlist age, CVEs, git drift, config drift
    │
    ├─ 2. snapper -c root create --description "archfrican-update YYYY-MM-DD @<sha>"
    │
    ├─ 3. git fetch --depth 1 origin main && git reset --hard FETCH_HEAD
    │
    ├─ 4. run_migrations()
    │      run all pending migrations/NNNN-slug.sh
    │
    ├─ 5. ARCHFRICAN_UPDATE=1 install.sh --update
    │      run_phase2() — only modules whose hash changed re-run
    │      (ARCHFRICAN_UPDATE=1 preserves user opt-ins: SSH, multiboot, gaming)
    │
    ├─ 6. sudo pacman -Syu   (interactive)
    │
    ├─ 7. paru --aur -Su     (AUR upgrade; failures non-fatal)
    │
    └─ 8. archfrican-doctor (summary report)
```

**Prune** (`--prune`): after the above, `prune_candidates()` computes:

```
(explicitly-installed) ∩ (managed.txt) − (manifest.txt) − (has dependents)
```

Only packages Archfrican ever installed that are no longer desired and have no dependents
are offered for removal. Hand-installed packages are never touched.
