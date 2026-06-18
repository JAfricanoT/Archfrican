# Phase 2 — Data Integrity & Destructive Operations

**Scope:** the "data" a system installer can damage — the user's **disk** (partition/format), the
Btrfs **snapshot/rollback safety net** (the project's stated #1 reliability lever), `/etc` system
configs, and `~/.config` dotfiles — plus **idempotency** of re-running the installer. Web/DB lenses
(schema/constraints/indexes, SQL migrations, money/decimal, offline-sync) **do not apply** (no DB).

**Method:** 4 parallel finders → 1 adversarial verifier per candidate. **32 candidates → 29
survived, 3 refuted.** Deduplicated below; items that overlap Phase-1 findings are cross-referenced,
not re-counted. Verifier corrections folded in (notably: one ALTO **down-graded to BAJO**, "no LUKS").

> Carried correction from Phase 1: modules **do** run under `set -euo pipefail` (inherited from the
> sourced `common.sh`). For Phase 2 this matters in both directions — failures **abort loudly** (good:
> no silent half-state), but an abort in the **last** module (`50-snapshots`) means the snapshot
> safety net is left **unconfigured**.

---

## Severity summary (this phase, deduplicated)

| Severity | Count | Items |
|----------|-------|-------|
| CRÍTICO  | 0 (1 conditional — see DATA-02) | — |
| ALTO     | 2 | DATA-01, DATA-02 |
| MEDIO    | 4 | DATA-03 … DATA-06 (+ cross-refs) |
| BAJO     | 4 | DATA-07 … DATA-10 |
| INFO     | 7 (all positive) | DATA-11 … DATA-17 |

Refuted by adversarial verification: **3**. Cross-references to Phase 1: SEC-02, SEC-05, SEC-07, SEC-10.

---

## ALTO

### DATA-01 — The deployed `theme-switch` is permanently broken on the installed system (`ROOT` resolves to `~/.local`)
- **File:** [bin/theme-switch:6](../../bin/theme-switch#L6) (and the chezmoi-deployed copy `home/dot_local/bin/theme-switch:6`) · confidence: alta · **personally verified**
- **Evidence:**
  ```bash
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  PAL="$ROOT/themes/$THEME/colors.sh"
  [ -f "$PAL" ] || { echo "no such theme: $THEME"; echo "available:"; ls "$ROOT/themes"; exit 1; }
  ```
- **Impact:** chezmoi deploys this script to `~/.local/bin/theme-switch` (which is on PATH via
  [dot_zshrc:2](../../home/dot_zshrc#L2)). When the **user** runs `theme-switch macos-dark`, `$0`
  is `~/.local/bin/theme-switch`, so `ROOT` becomes **`~/.local`** → `$ROOT/themes` = `~/.local/themes`
  which **does not exist** (and `themes/`/`templates/` are **not under `home/`**, so chezmoi never
  deploys them anywhere). Line 9 fails → `no such theme` → `exit 1`, for **every** theme. The
  signature "hot-swap theme switcher" ([README.md:60-63](../../README.md#L60-L63), [install.sh:38](../../install.sh#L38))
  is **dead on the installed machine.** Only the in-repo `bin/theme-switch` — run once during
  `40-theming` where `$0` sits next to `themes/` — succeeds, which is what `CONTEXT.md` "tested working"
  actually exercised (the wrong copy).
- **Recommendation:** The user-facing switcher must locate `themes/`/`templates/` at a fixed deployed
  path, not via `$(dirname "$0")/..`. Options: (a) deploy `themes/`+`templates/` into the home tree
  (e.g. `~/.local/share/archfrican/{themes,templates}`) and point `ROOT` there; (b) ship a thin launcher in
  `~/.local/bin` that calls the repo clone; (c) embed palettes/templates in the script.
- **Cross-phase:** Compounds with DATA-07 (two copies must be fixed together) and DATA-04 (even a fix
  is undone by chezmoi re-apply). Also a Phase-5 docs↔code contradiction ("tested working").

### DATA-02 — Btrfs rollback safety net is not reliably wired (the project's #1 reliability promise) — escalates to CRÍTICO if the unit name is confirmed wrong
- **File:** [modules/50-snapshots.sh:6-13](../../modules/50-snapshots.sh#L6-L13) · confidence: alta (defect) / media (exact systemd-unit string — **a confirmar**)
- **Two concrete defects in the module that is supposed to make "rollback in one reboot"
  ([README.md:19](../../README.md#L19)) real:**

  **(a) Wrong/obsolete systemd unit `grub-btrfs.path`.**
  ```bash
  enable_service grub-btrfs.path           # → sudo systemctl enable grub-btrfs.path
  ```
  Current `grub-btrfs` (Arch `extra`, v4.x) ships the inotify **daemon `grub-btrfsd.service`**, not
  `grub-btrfs.path` (corroborated by [base.txt:11](../../packages/base.txt#L11): *"needed by
  grub-btrfs **daemon**"*). `systemctl enable grub-btrfs.path` then exits non-zero → under inherited
  errexit, **module 50 aborts at line 10** → lines 11-13 (`snapper-timeline.timer`,
  `snapper-cleanup.timer`, the initial `grub-mkconfig`) **never run** → no snapshot tooling is
  enabled. *If the unit name is confirmed wrong on the target (very likely), this is CRÍTICO: the
  advertised safety net is not live after install.*

  **(b) `snapper create-config` can collide with archinstall's pre-existing `@.snapshots`.**
  ```bash
  if ! sudo snapper list-configs | grep -q '^root'; then
    sudo snapper -c root create-config /
  fi
  ```
  archinstall (`snapshot_config: Snapper`, [user_config.json:16-22](../../archinstall/user_config.json#L16-L22))
  already creates `@.snapshots` mounted at `/.snapshots`. `snapper create-config /` tries to create
  its **own** `.snapshots` subvolume and fails *"since it already exists"*. The line-6 guard saves
  this **only if** archinstall also registered the snapper `root` config; if a given archinstall
  version creates the subvolume but **not** the config, the guard misses, line 7 runs, fails, and
  aborts module 50. (**a confirmar** — depends on archinstall version, which the config header itself
  warns shifts between releases.)
- **Recommendation:** (a) Replace with `enable_service grub-btrfsd.service` (verify on target with
  `systemctl list-unit-files | grep grub-btrfs`); make each `enable_service` resilient so one bad unit
  doesn't abort the whole snapshot setup. (b) Make module 50 robust to a pre-existing `/.snapshots`
  (ArchWiki snapper-on-existing-layout: temporarily unmount, create-config, delete snapper's
  auto-subvol, remount) and add a post-condition `snapper -c root list` check before printing
  "Snapshots active". **Validate the whole loop on a VM** (install → pacman change → snapshot submenu
  appears in GRUB → boot it → `snapper rollback`).

---

## MEDIO

### DATA-03 — chezmoi ↔ theme-switch state-ownership conflict: live theme reverts on re-apply, and the choice is non-durable
- **File:** [install.sh:31](../../install.sh#L31) + [home/.chezmoiignore:1](../../home/.chezmoiignore#L1) + the committed color files · confidence: alta
- **Evidence:** `install.sh:31` runs `chezmoi init --apply --source "$PWD/home"` (the **final** step of
  every run). The chezmoi source ships the **same** files theme-switch writes, frozen at the
  macos-dark palette — e.g. [ghostty/colors:1](../../home/dot_config/ghostty/colors#L1)
  `background = #1c1c1e`, [waybar/colors.css:1](../../home/dot_config/waybar/colors.css#L1),
  [mako/colors:1](../../home/dot_config/mako/colors#L1),
  [fuzzel/colors.ini:2](../../home/dot_config/fuzzel/colors.ini#L2), and the niri block at
  [config.kdl:30-31](../../home/dot_config/niri/config.kdl#L30-L31). `.chezmoiignore` contains only
  `README.md`, so none are excluded. theme-switch writes those exact paths
  ([theme-switch:26-29, 38](../../bin/theme-switch#L26-L29)) and records the choice only in
  `~/.config/.archfrican-theme` ([:50](../../bin/theme-switch#L50)) — which **nothing reads back**.
- **Impact:** After `theme-switch tokyo-night`, a later `install.sh` re-run (advertised "safe to re-run
  any time", [install.sh:4](../../install.sh#L4)) makes `chezmoi apply` **revert all five color
  files + the niri block to macos-dark**, while `.archfrican-theme` still says `tokyo-night` → internally
  inconsistent state. More generally, `chezmoi apply` overwrites **any** hand-edited managed dotfile
  (`~/.zshrc`, `waybar/style.css`, …) with no `chezmoi diff`/confirmation. Recoverable by re-running
  theme-switch — **except** DATA-01 means the deployed switcher is broken, so it is **not** recoverable
  on the installed machine.
- **Recommendation:** Make generated artifacts chezmoi-ignored (add `dot_config/ghostty/colors`,
  `…/waybar/colors.css`, `…/fuzzel/colors.ini`, `…/mako/colors` to `.chezmoiignore`) so theme-switch is
  the sole writer; for the partially-generated `niri/config.kdl`, move the themed block to an
  included, switch-owned file. Add a `chezmoi run_after`/niri startup hook that reads `.archfrican-theme`
  and re-applies it (self-healing). Gate dotfile application behind `chezmoi diff` + confirmation, or
  decouple it from the package re-run path.

### DATA-04 — Two byte-identical `theme-switch` copies with no single source of truth (drift)
- **File:** [bin/theme-switch](../../bin/theme-switch) vs [home/dot_local/bin/theme-switch](../../home/dot_local/bin/theme-switch) · confidence: alta
- **Evidence:** `diff` → identical (distinct inodes — two independent files, not a symlink). The
  installer runs `bin/theme-switch` ([40-theming.sh:18](../../modules/40-theming.sh#L18)); the user
  runs the chezmoi-deployed `home/dot_local/bin/theme-switch`.
- **Impact:** A fix to one (e.g. the DATA-01 `ROOT` bug, or the SEC-07 splice) silently won't apply to
  the other → install-time vs post-install divergence. The DATA-01/SEC-07 defects physically live in
  **both**, so a one-file patch leaves the user-facing copy broken.
- **Recommendation:** One canonical source — keep logic in repo `bin/` and symlink/templatize the home
  copy via chezmoi.

### DATA-05 — Standalone module runs before `00-base` abort on missing prerequisites
- **File:** [install.sh:17](../../install.sh#L17) + [40-theming.sh:7](../../modules/40-theming.sh#L7) + [50-snapshots.sh:7](../../modules/50-snapshots.sh#L7) · confidence: alta
- **Evidence:** `if [ $# -gt 0 ]; then run_module "$1"; exit 0; fi` advertises single-module runs
  (`./install.sh 30-dev`), but `40-theming` calls `paru` (only installed by `00-base`) and
  `50-snapshots` calls `snapper` (only installed via `base.txt`). Under errexit, `./install.sh
  40-theming` aborts at `paru -S`; `./install.sh 50-snapshots` aborts at line 7 `snapper … create-config`
  (the line-6 `snapper list-configs` is in an `if !` condition, exempt from errexit).
- **Impact:** Breaks the documented single-module re-entry contract for dependency-bearing modules.
- **Recommendation:** Assert prerequisites at module top (`command -v paru >/dev/null || die 'run
  00-base first'`), or auto-run `00-base` when a prerequisite is missing.

### DATA-06 — `grub-mkconfig` regenerated 2–3× per full run (non-idempotent churn)
- **File:** [00-base.sh:22](../../modules/00-base.sh#L22) + [10-gpu.sh:26](../../modules/10-gpu.sh#L26) + [50-snapshots.sh:13](../../modules/50-snapshots.sh#L13) · confidence: alta
- **Impact:** `00-base.sh:22` and `50-snapshots.sh:13` run `grub-mkconfig` **unconditionally on every
  run** (10-gpu's is guarded and no-ops after first NVIDIA run). Pure waste + repeated rewrites of
  `/boot/grub/grub.cfg`; not data loss.
- **Recommendation:** Generate `grub.cfg` **once** at the end of `install.sh`, or guard each call on an
  actual change to `/etc/default/grub`/kernels.

### Cross-references to Phase 1 (tracked there; idempotency/integrity facets noted, not re-counted)
- **SEC-05** — `/etc/greetd/config.toml` & `/etc/keyd/default.conf` unconditionally clobbered every run
  (no backup) → re-running the installer silently destroys local edits to these system configs.
- **SEC-07** — `theme-switch` awk splice destroys the rest of `~/.config/niri/config.kdl` if the
  `THEME-END` marker is missing (atomic `mv` of the truncated file).
- **SEC-10** — mkinitcpio `MODULES` guard greps the bare substring `nvidia` (can mis-fire on re-run /
  pre-existing comment), leaving early-KMS unconfigured while reporting success. Also a `^root`
  snapper-guard analogue at [50-snapshots.sh:6](../../modules/50-snapshots.sh#L6): `grep '^root'`
  prefix-over-matches a config named `root-*`.
- **SEC-02** — `00-base.sh:8-10` CachyOS `curl → sudo ./script` mutates `/etc/pacman.conf` + key trust
  before any package install (system-config-integrity facet).

---

## BAJO

### DATA-07 — VS Code `code-flags.conf` overwritten each run + stray empty `code-flags.conf.d` dir
- **File:** [modules/30-dev.sh:18-19](../../modules/30-dev.sh#L18-L19) · confidence: alta
- `mkdir -p "$HOME/.config/code-flags.conf.d"` creates a **directory** that is never used (the flags
  are written to the **file** `code-flags.conf` on the next line) — a copy-paste artifact; and the file
  is rewritten unguarded each run.
- **Recommendation:** Drop the bogus `.d` mkdir; guard the write if preserving user edits matters.

### DATA-08 — No disk encryption (LUKS) and no note that it's intentional *(down-graded ALTO→BAJO by verifier)*
- **File:** [archinstall/user_config.json:12-25](../../archinstall/user_config.json#L12-L25) · confidence: alta (fact) / media (archinstall behavior, **a confirmar**)
- No `encryption` key under `disk_config`; the four `//` comment lines document Btrfs/snapshots/kernel
  but not encryption. **Verifier:** this is a confidentiality/informed-choice gap, **not** a Phase-2
  integrity/destructive defect — and both disk selection **and** LUKS are deferred to the TUI review
  the config explicitly instructs. Hardening note only.
- **Recommendation:** Add a `//` comment stating encryption is intentionally left to the TUI, and note
  it in `README §Install`, so the choice is conscious.

### DATA-09 — Snapper timers enabled without `--now` (don't start until reboot)
- **File:** [modules/50-snapshots.sh:10-13](../../modules/50-snapshots.sh#L10-L13) · confidence: media (a confirmar on units)
- `enable_service` runs `systemctl enable` only ([common.sh:37](../../lib/common.sh#L37)) — timers
  are enabled for next boot but not started in-session. The mandatory post-phase-2 reboot starts them,
  so the safety net is live "one reboot away" as promised; purely a robustness nit (assuming DATA-02a
  is fixed first).
- **Recommendation:** Use `systemctl enable --now` for the timers and the grub-btrfs daemon.

### DATA-10 — `.chezmoiignore` ignores a non-existent `home/README.md` (dead rule)
- **File:** [home/.chezmoiignore:1](../../home/.chezmoiignore#L1) · confidence: alta
- No `README.md` exists under `home/`, so the only rule is a no-op; harmless but misleading (and the
  files that *should* be ignored — the generated color files, DATA-03 — are not).

---

## INFO — positive findings (credibility baseline)

- **DATA-11 ✅** Subvolume layout `@ / @home / @log / @pkg / @.snapshots`
  ([user_config.json:17-23](../../archinstall/user_config.json#L17-L23)) is the correct
  snapper-compatible scheme; combined with dual kernel (cachyos + **lts** fallback) it's a genuinely
  resilient design — *provided* the DATA-02 activation gaps are closed.
- **DATA-12 ✅** `@log` and `@pkg` correctly carved out so they're **excluded** from root snapshots
  (logs survive a rollback; package cache isn't duplicated into every snapshot).
- **DATA-13 ✅** `snap-pac` is correctly handled — it's a pacman ALPM hook, so installing the package
  ([base.txt:9](../../packages/base.txt#L9)) is sufficient; no `systemctl enable` needed and none
  attempted.
- **DATA-14 ✅** chezmoi `dot_` mapping is correct (`dot_config`→`~/.config`, `dot_local/bin`→
  `~/.local/bin`, `dot_zshrc`→`~/.zshrc`); no shadowed/mis-mapped file.
- **DATA-15 ✅** Theme `include`/`@import`/`config-file` directives in mako/fuzzel/waybar/ghostty
  configs correctly reference the exact files theme-switch writes — the wiring is consistent (the
  breakage is purely the DATA-01 `ROOT` issue, not mis-wiring).
- **DATA-16 ✅** Shipped `niri/config.kdl` has exactly one well-formed `THEME-START/THEME-END` pair
  matching the template, so SEC-07's destructive splice **does not** fire on the as-shipped file.
- **DATA-17 ✅** Idempotency guards on the writes most likely to break on re-run (CachyOS repo stanza,
  snapper config, package installs via `pacman -Q`, paru build) are correct — this part genuinely
  lives up to "safe to re-run".

---

## Refuted / Discarded (3) — transparency

| Candidate | Orig. sev. | Why refuted |
|-----------|-----------|-------------|
| "`default_layout` formats the wrong disk; only the TUI stands between JSON and a wipe" ([user_config.json:13](../../archinstall/user_config.json#L13)) | ALTO | No `device` is pinned → disk selection is **deferred to the TUI** (the safer design, which the finding itself recommends keeping), and the wipe is already documented (README:46/104, JSON comments). Reduces to "an installer formats the disk you select" — intended behavior, no defect. INFO at most. |
| "`swap: true` + `zram-generator` = redundant/conflicting swap" ([user_config.json:28](../../archinstall/user_config.json#L28)) | MEDIO | archinstall `swap: true` provisions **zram**, not a disk partition; and `zram-generator` is **inert without a config** (repo-wide grep: only the package line in `base.txt:14`, no `zram-generator.conf` anywhere). No competing backend ever materializes. (archinstall internals: a confirmar.) |
| "`rm -rf "$tmp"` could expand to `rm -rf /`" ([00-base.sh:11](../../modules/00-base.sh#L11)) | BAJO | Safe under the active `set -euo pipefail`: a failed `mktemp -d` aborts at the assignment (errexit) and an unset `$tmp` errors (nounset) — the empty-var catastrophe can't trigger. Speculative future-refactor hardening only. |

---

## Cross-cutting note for later phases
- **`modules/50-snapshots.sh`** and **`bin/theme-switch`** are the two highest-leverage files here.
  The snapshot module carries the project's headline reliability claim and has two activation defects
  (DATA-02). The theme switcher is **doubly broken** on the installed system: dead `ROOT` path
  (DATA-01) **and** reverted by chezmoi (DATA-03), duplicated across two files (DATA-04) — strong
  Phase-6 convergence and a direct Phase-5 contradiction of "tested working".
- **`theme-switch` now appears in Phases 1, 2, and (pending) 3** — top convergence candidate.
