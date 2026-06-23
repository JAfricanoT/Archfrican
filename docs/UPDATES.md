# Updates — convergence to the desired state ("the system = the repo, applied")

Archfrican keeps a machine current by **convergence**, not by patching: the installed system is
*defined* by the repo, and an update simply re-applies that definition. The consequence is the whole
point — **updating an old Archfrican gives the same result as a fresh install** of the current repo,
plus the upstream Arch package upgrades.

There is one command:

```
archfrican-update              # read-only report: pre-checks + drift (changes nothing)
archfrican-update --run        # snapshot → repo refresh → migrate → converge → pacman -Syu → AUR
archfrican-update --converge   # only re-apply the repo's config/dotfiles (no package upgrade)
archfrican-update --prune      # also drop Archfrican-managed pkgs no longer in the repo (opt-in)
archfrican-update --no-aur     # skip the AUR phase in --run
```

`--run` is interactive and **never** uses `--noconfirm`; nothing is auto-removed; an AUR build
failure never blocks the official upgrade.

## Why this works: the modules are already convergent
Every module is idempotent — `pac_install` uses `--needed`, `write_system_file` compares and skips
when unchanged (backing up once), GRUB/mkinitcpio/NVIDIA use sentinels, snapper checks for an
existing config. Re-running a module brings it to the desired state and does nothing if already
there. So a converge is just "re-run the modules" — cheaply.

### Only what changed re-runs (content-addressed) — `lib/converge.sh`
Each module's `.done` stamp stores a **hash of its inputs** (its script + its `packages/*.txt` +
shared libs). On a converge a module re-runs **only if that hash changed**:
- fresh install → everything runs, records its hash;
- update, repo unchanged → every hash matches → a true no-op;
- update after, say, `packages/dev.txt` was bumped → only `30-dev` re-runs.

This one mechanism serves both **install-resume** (a completed module skips on the next boot) and
**update** — and lets the health check report **drift** (applied state vs the on-disk repo) with no
sudo and no network.

## The `--run` pipeline
1. **Pre-check** (read-only): disk headroom on `/` and `/boot`, snapshots, mirrorlist age, Arch news,
   fixable CVEs, plus **drift** (repo behind `origin`? modules changed? migrations pending?).
2. **Pre-snapshot**: an explicit `snapper` snapshot of `/`. snap-pac already checkpoints the
   `pacman -Syu`, but a *config-only* converge touches `/etc` without any pacman transaction — this
   snapshot makes the **whole** update one rollback point. A broken update is one reboot from being
   undone (grub-btrfs lists the snapshot in the boot menu).
3. **Repo refresh**: `git fetch && git reset --hard` of `~/.archfrican` to the latest ref.
4. **Migrations** (`migrations/`): one-shot fixes for *old* state — see below.
5. **Converge**: re-apply the desired state (only changed modules) + `chezmoi` dotfiles + theme.
6. **System upgrade**: `sudo pacman -Syu` (interactive).
7. **AUR**: `paru -Sua` as a separate, reviewed phase (a failed build doesn't block step 6).
8. **Summary**: `archfrican-doctor`, plus a reboot hint if the kernel changed.

## Migrations — the one place update ≠ fresh install — `migrations/`
Convergence puts the *current* desired state in place, but it can't see **stale** state a clean
install never created (a renamed config, a retired service). A migration *undoes* that. They are
versioned (`migrations/NNNN-slug.sh`), idempotent, and run once; the applied version lives in
`/var/lib/archfrican/state-version`. A **fresh install** is marked straight to the latest **without
running any** — it's already at the target state. Only an older machine runs the delta. See
[migrations/README.md](../migrations/README.md).

## Pruning — convergence, safely — `lib/manifest.sh`
A fresh install has only what the lists declare; an old one can accumulate packages dropped from the
lists over time. `--prune` (opt-in, interactive) removes those — but **only ever** packages
Archfrican itself installed and no longer wants:

- every converge writes `manifest.txt` (currently-desired set) and folds it into `managed.txt`
  (cumulative "ours");
- prune candidate = explicitly-installed **∩** `managed.txt` **−** `manifest.txt` **−**
  has-dependents.

A package you installed by hand is never in `managed.txt`, so it can never be a candidate. The
removal is `sudo pacman -Rns` (never `--noconfirm`; pacman itself refuses unsafe removals).

## Staying informed — manual, never unattended
The weekly `archfrican-doctor` user timer (from `70-hygiene`) **notifies** when the applied state
lags the repo (the `config drift` check) or when updates/CVEs are available — it never changes
anything. Run `archfrican-update --run` when you're ready. There is no auto-update timer by design:
*nothing explodes* while you're not looking.

## Rollback
If an update misbehaves, reboot and pick the pre-update snapshot from the grub-btrfs submenu
(`snapper list` shows it, described `archfrican-update <date>`), then `snapper rollback` if you want
to make it permanent.
