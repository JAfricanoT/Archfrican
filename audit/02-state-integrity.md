# Phase 2 — State Integrity & Destructive Ops

**Scope:** convergence idempotency & drift detection, migrations (one-shot/ordering/crash-recovery), manifest & prune safety, chezmoi/dotfiles/theme state, destructive disk/subvolume ops, and `/etc` append-safety.
**Method:** 5 parallel finder lenses → independent adversarial verifier per candidate → my own hand-verification + sandbox reproduction. Pinned at **git HEAD `821e217`** (102 files).
**Moving-target note:** the repo advanced **5 commits during this audit** — it migrated the graphical login **greetd → SDDM** (commits `90b44b9..821e217`, incl. `migrations/0002-greetd-to-sddm.sh`). This phase audits the *current* tree. (This also refuted a preliminary lead of mine: the SDDM assets `lib/converge.sh` references are real, not phantom — `converge.sh` was correctly updated to track them.)

## Verdict for this phase

The convergence/migration/manifest machinery is **well-architected and mostly sound** — migrations are one-shot, idempotent, crash-resumable; the prune triple-guard provably cannot remove a hand-installed, depended-upon, or boot/login/GPU-critical package; `/etc` appends are guarded against duplication; the snapshot setup is post-condition-checked. But the **content-hash drift engine has systematic input-coverage gaps** (it only hashes files explicitly listed in `module_inputs`), and the **theme application path has two real integrity bugs**, one of which (niri-splice config loss) is the prior audit's **still-unresolved SEC-07**.

### Candidate accounting

| | Count |
|---|---|
| Candidates raised (4 of 5 lenses; see note) | 15 |
| Survived adversarial verification | 15 |
| Refuted | 0 |
| **HIGH** | 3 |
| **MEDIUM** | 6 |
| **LOW** | 5 *(4 from workflow + 1 from my own reproduction)* |
| **INFO** | 2 |

> **Coverage note (transparency):** the `destructive-append` finder aborted on an infrastructure error ("Connection closed mid-response"), returning nothing. I covered that surface **by direct reading** (`50-snapshots.sh`, `host-config.sh` appends, `base-install.sh` fstab/locale, `write_system_file`). Conclusion: appends are pre-existence-guarded (no duplication), and the only note is an INFO-level snapshot-umount crash window (see I3). No HIGH/MEDIUM was missed there.

## Reproduction (run locally, read-only)

```
# Migration version math + numeric-vs-lexical ordering (temp REPO_ROOT, no sudo):
glob 'migrations/[0-9]*.sh' expands LEXICALLY:  0001-a.sh  00010-d.sh  0002-b.sh  0010-c.sh
_mig_latest      = 10      (integer max — correct)
pending (v=empty)= 10      (absent state-version → v0 → full delta — by design)
pending (v=1)    = 9       (correct)
```
The math is correct, but the **glob iteration order is lexical** → see **L5**.

---

## HIGH findings

### H1 — SDDM login palette is a drift false-negative: `themes/*/colors.sh` defines the rendered login theme but is in no `module_inputs`
- **Files:** `lib/converge.sh:24-26` (inputs for `20-niri-desktop`) · render at `modules/20-niri-desktop.sh:19-20` + `lib/common.sh:79-89`
- **Severity:** HIGH · **Confidence:** high
- **Evidence:**
  ```bash
  # lib/converge.sh:24-26 — 20-niri-desktop inputs (no themes/*)
  20-niri-desktop) printf ' packages/niri-desktop.txt templates/sddm.theme.conf'
                   printf ' assets/sddm/archfrican/Main.qml assets/sddm/archfrican/theme.conf'
                   printf ' assets/sddm/archfrican/metadata.desktop' ;;
  # lib/common.sh:81 — the authoritative login render reads the palette:
  local pal="$REPO_ROOT/themes/$theme/colors.sh" tmpl="$REPO_ROOT/templates/sddm.theme.conf"
  $ grep -n "themes/" lib/converge.sh   → (no match)
  ```
- **Impact:** `20-niri-desktop` renders the **authoritative** login theme (`/usr/share/sddm/themes/archfrican/theme.conf`) from `themes/<name>/colors.sh`, yet `module_hash` for that module hashes only the SDDM *template* + static assets — never any palette. Editing `themes/macos-dark/colors.sh` (BG/ACCENT/FG) changes **no** module hash, so `drift_modules()` returns nothing, `archfrican-doctor` reports *"config drift: matches the repo"*, and `archfrican-update --converge` **skips** `20-niri-desktop` — the login theme never re-renders. This directly contradicts the engine's own contract (`converge.sh:1-8`: "updating an old Archfrican == a fresh install" + "report drift"). Impact is cosmetic (login colors), hence HIGH not CRITICAL.
- **Recommendation:** add `themes/*/colors.sh` (glob) to `20-niri-desktop`'s inputs, or make `render_sddm_theme` run unconditionally each converge rather than hash-gated.

### H2 — `40-theming` hardcodes `theme-switch macos-dark`, clobbering the user's chosen theme (wizard pick on install; long-standing theme on converge)
- **Files:** `modules/40-theming.sh:20-21` · `bin/theme-switch:71` · flow: `phase2.sh:150,161,163,172` + `run_after_99-apply-theme.sh.tmpl:10` · invariant violated: `phase2.sh:140-142`
- **Severity:** HIGH · **Confidence:** high
- **Evidence:**
  ```bash
  # modules/40-theming.sh:20-21
  substep "setting the default theme (your wizard pick is applied last by chezmoi)"
  attempt "default theme" env ARCHFRICAN_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/theme-switch" macos-dark
  # bin/theme-switch:71
  echo "$THEME" > "$CFG/.archfrican-theme"
  ```
- **Impact:** **Fresh install:** `phase2.sh:150` stages the wizard pick (e.g. `tokyo-night`) into `~/.config/.archfrican-theme`; `20-niri-desktop` renders SDDM from that pick; then `40-theming` runs `theme-switch macos-dark` **unconditionally**, which overwrites `.archfrican-theme` back to `macos-dark` and rewrites every color file. chezmoi's `run_after` then reads `.archfrican-theme` (now `macos-dark`) and re-applies macos-dark. **Net: a user who picks any non-default theme silently boots into macos-dark** on desktop and login. The inline comment "your wizard pick is applied last by chezmoi" is **false** — this line destroys the value chezmoi reads. **Converge:** `40-theming` is content-addressed on `packages/theming.txt`+`aur.txt`+shared `lib/common.sh`, so any theming-layer (or `common.sh`) bump re-runs it during `archfrican-update` and **silently resets a user's long-standing theme to macos-dark** — violating the documented invariant (`phase2.sh:140-142`) that identity/theme set once at install is preserved on converge.
- **Recommendation:** read the staged value instead of hardcoding (`theme="$(cat ~/.config/.archfrican-theme 2>/dev/null || echo macos-dark)"; theme-switch "$theme"`, mirroring `20-niri-desktop.sh:19`), or **drop the `theme-switch` call from `40-theming` entirely** and let the chezmoi `run_after` be the single applier (it already does exactly that). Fix the misleading comment.

### H3 — niri config splice swallows everything after `THEME-START` when `THEME-END` is missing → total silent loss of the user's niri config *(= prior audit SEC-07, STILL OPEN)*
- **File:** `bin/theme-switch:45-49`
- **Severity:** HIGH · **Confidence:** medium (conditional trigger)
- **Evidence:**
  ```bash
  awk 'NR==FNR{blk=blk $0 ORS; next}
       /THEME-START/{printf "%s", blk; skip=1; next}
       /THEME-END/{skip=0; next}
       !skip{print}' "$tmpblk" "$CFG/niri/config.kdl" > "$CFG/niri/config.kdl.new"
  mv "$CFG/niri/config.kdl.new" "$CFG/niri/config.kdl"
  ```
- **Impact:** `skip` is set at `THEME-START` and only cleared at `THEME-END`. If `config.kdl` has a `THEME-START` but **no** `THEME-END` (external truncation, or a user edited/removed the marker), `skip` never resets and **everything from `THEME-START` to EOF is dropped** — binds, environment, spawn-at-startup, window-rules — then `mv` atomically commits the truncated config with no error, no backup. The verifier reproduced this. The happy path is safe (the chezmoi-managed `config.kdl.tmpl:27,33` ships both markers), so the trigger is a pre-degraded config — hence HIGH not CRITICAL. A secondary defect: the markers are **unanchored substring matches** (any line *containing* the string triggers splice/skip).
- **Recommendation:** before splicing, assert exactly one well-formed `START`-before-`END` pair (`grep -c`, ordering check); if not, skip + warn, leaving the file untouched. Anchor the markers; back up before `mv`.
- **Cross-ref:** this is the prior audit's **SEC-07** (`docs/audit/01-security-supply-chain.md:182`) — **still unresolved** at HEAD `821e217`. (Tracked in Phase 5 reconciliation.)

---

## MEDIUM findings

### M1 — `bin/theme-switch` + the non-SDDM palette templates are in no `module_inputs` → `40-theming` drift false-negative for color files / niri block
- **File:** `lib/converge.sh:28` (40-theming inputs = only `packages/theming.txt packages/aur.txt`)
- **Impact:** `theme-switch` is the sole writer of the runtime color files (ghostty/waybar/fuzzel/mako) and the niri THEME block, invoked authoritatively by `40-theming:21`. Neither it nor `templates/{ghostty.colors,waybar.colors.css,fuzzel.colors.ini,mako.colors,niri.theme.kdl}` is hashed, so a change to the renderer or a palette template produces **no drift signal** and a converge won't re-run `40-theming`; the fix only lands opportunistically via the chezmoi `run_after`. *(Verifier corrected the candidate's scope: the SDDM template **is** already tracked under `20-niri-desktop`; the real gap is the user-side color files — H1 covers the SDDM-palette half.)*
- **Recommendation:** add `bin/theme-switch` + those 5 templates to `40-theming`'s `module_inputs` case.

### M2 — `10-gpu` arg is not hashed → a GPU hardware swap never re-converges drivers and shows no drift
- **File:** `lib/converge.sh:36-38` (arg deliberately excluded) · `phase2.sh:42-44,66,75,160`
- **Impact:** `module_hash` excludes the module arg, justified by "in update mode the args are inferred from the live system so they already match." That is **unsound for `10-gpu`**: its arg comes from `detect_gpu` (current *hardware*), not the installed-driver state. Swap in an NVIDIA card → `10-gpu`'s input files are unchanged → `run_module` skips it → the NVIDIA driver + early-KMS are never installed, and `drift_modules` shows nothing. *(Verifier confirmed the justification **is** sound for `55-multiboot`/`60-security`, which read their args from the applied effect — so the fix is `10-gpu`-specific.)*
- **Recommendation:** fold the resolved arg into the `.done` stamp for arg-bearing modules whose arg is a *desired input* (10-gpu), so a changed effective arg re-converges and surfaces as drift.

### M3 — `git reset --hard FETCH_HEAD` discards local repo edits silently (converge + bootstrap)
- **Files:** `bin/archfrican-update:106-107` · `install.sh:38-40`
- **Impact:** both `archfrican-update --run/--converge` and the bootstrap hard-reset the working clone (`~/.archfrican`) with **no `git status`/stash/dirty check** (grep confirms none exists). The repo is exactly where the project invites edits — `theme-switch` tells users to set `ARCHFRICAN_ROOT=<repo dir>` and the palettes/templates live there. Any uncommitted edit to `themes/*/colors.sh` or a template is **discarded without warning** on the next update (output redirected to `/dev/null`). Confined to the clone (no data loss elsewhere), but silent.
- **Recommendation:** gate the reset on `git status --porcelain` being empty; if dirty, auto-stash or warn-and-name the paths. Document that durable customization belongs in a fork/branch.

### M4 — Corrupt/non-numeric `state-version` makes `run_migrations` silently skip ALL migrations and print false success
- **File:** `lib/migrate.sh:34-40` (also `pending_migrations` at `:60`) · runs under `archfrican-update`'s `set +e +u +o pipefail` (`:23`)
- **Impact:** `cur="${cur:-0}"` only substitutes when **empty**, not when garbage. A non-numeric `state-version` makes `[ "$cur" -ge "$latest" ]` error ("integer expression expected", rc 2) → the `&&` doesn't fire the up-to-date return → falls into the loop where every `[ "$n" -gt "$cur" ]` also errors and is swallowed by `|| continue` → **every migration skipped, `ran=0`**, yet `ok "migrations: applied 0 (now at v$latest)"` prints a **false success**, and the corrupt file is never repaired. Meanwhile `pending_migrations` reports the *full* count — an internal contradiction. Trigger is low-probability (the only writer `_mig_set` always emits a clean int; root-owned file), hence MEDIUM.
- **Recommendation:** normalize a non-numeric reading to 0 in both consumers (`case "$cur" in (''|*[!0-9]*) cur=0;; esac`), so garbage **fails open** into re-running the idempotent delta (and self-heals the stamp) rather than silently skipping with a false success.

### M5 — `managed.txt` privilege/mode asymmetry can silently disable `--prune`
- **File:** `lib/manifest.sh:36,37,45,50`
- **Impact:** `manifest.txt` is force-mode `sudo install -m 0644` (`:36`), but `managed.txt` is written via `sudo tee` (`:37`) — so its mode is set once by **root's umask at first creation** and preserved thereafter, never explicitly `0644`. Yet `prune_candidates` reads it **without sudo** (`:45` `[ -r ]` guard, `:50` `grep`), running as the regular user. Under a hardened root umask, `managed.txt` could be non-world-readable → the guard fails or `grep` matches nothing → `prune_candidates` returns empty → **`--prune` becomes a silent no-op**, defeating the greetd→sddm cleanup that explicitly defers stale-package removal to `--prune`. Fail-safe (under-prunes, never over-prunes — no data loss), non-default trigger, hence MEDIUM.
- **Recommendation:** write `managed.txt` via `sudo install -m 0644` (symmetric with `manifest.txt`) and pick one privilege model for both read and write sides.

### M6 — `Required By` parse is locale-dependent → `--prune` silently prunes nothing on non-English systems
- **File:** `lib/manifest.sh:51-52`
- **Impact:** `pacman -Qi` **localizes** both the `Required By` label and the `None` value per `LANG`/`LC_MESSAGES`. The installer sets `LANG` from the user's chosen locale (`base-install.sh:124`, `host-config.sh:51`), so on any non-English install the `awk '/^Required By/'` match fails → `reqby` is empty → `[ "$reqby" = "None" ]` is false → **every candidate is skipped** → `prune_candidates` outputs nothing and `do_prune` reports the success-looking *"nothing to prune"*. An advertised feature is a **silent no-op for the entire class of non-English users**. Fail-safe (never over-prunes), hence MEDIUM (verifier *raised* this from the finder's LOW — it's a correctness defect, not hygiene).
- **Recommendation:** force `LC_ALL=C` on the query: `reqby="$(LC_ALL=C pacman -Qi "$p" … )"` (and harmlessly on the `pacman -Qeq` feed for consistency).

---

## LOW findings

| # | Finding | File | Note |
|---|---------|------|------|
| **L1** | Fresh install that crashes **before** `mig_mark_latest` leaves no `state-version` → `archfrican-update` treats the brand-new machine as pre-migrations **v0** and re-runs the full historical delta. | `phase2.sh:189`; `migrate.sh:34` | *Downgraded HIGH→LOW by verifier:* current migrations no-op on a fresh box; the v0 semantic is **intentional + CI-enforced** (`ci.yml:77`); documented recovery is to re-run `install.sh` (resumes via `.done`, stamps correctly). Still worth hardening: stamp the baseline **early** (e.g. after `00-base`) so a crash never re-classifies a new machine as v0. |
| **L2** | `_mig_set` writes `state-version` non-atomically and its exit status is **unchecked** → a failed `sudo tee` (read-only `/var`, disk full) leaves the level un-advanced and the same migration re-runs. | `migrate.sh:27,43` | Harmless today (migrations idempotent). Fix: `_mig_set "$n" || die`; optional temp-then-`mv`. |
| **L3** | Live SDDM theme update fails **silently** when sudo creds aren't cached (`sudo -n … 2>/dev/null`, no else) → login screen diverges from desktop until next converge. | `bin/theme-switch:55-61` | *Downgraded MEDIUM→LOW:* intentional best-effort, self-healing via `render_sddm_theme` each converge; only the silence is the gap. Add an `else` note. |
| **L4** | Color files (ghostty/waybar/fuzzel/mako) are rendered **non-atomically** straight onto their live paths (unlike the niri/SDDM paths which use temp+mv). A mid-write crash leaves a truncated `.chezmoiignore`d file that persists. | `bin/theme-switch:27-40` | Self-healing on next run. Fix: render to temp + `mv`. |
| **L5** | **(my reproduction)** `run_migrations` iterates the glob `migrations/[0-9]*.sh` in **lexical** order. This equals numeric order only while all migration numbers share a digit-width. A future inconsistently-named migration (e.g. `00010` or `10-foo`) would sort *before* `0002`, run first, bump the version past it, and `0002` would then be **permanently skipped** (`2 > 10` is false). | `migrate.sh:37` | No current trigger (only 4-digit `0001`/`0002`). Repro above. Fix: sort numerically (parse `NNNN`, sort `-n`) rather than relying on glob order. |

---

## INFO notes

| # | Note | File |
|---|------|------|
| **I1** | **Safety verification (not a bug):** kernel (`linux-cachyos`/`linux-lts`), `grub`, `efibootmgr`, `linux-firmware`, and GPU drivers are pacstrapped/computed **outside** `packages/*.txt`, so they never enter `managed.txt` and **can never become prune candidates**. `sddm`/`weston` are in the always-on `niri-desktop.txt` so they stay in the manifest. The prune blast radius provably excludes all boot/login/GPU-critical packages. | `base-install.sh:100`, `manifest.sh:21,50` |
| **I2** | niri splice is a benign silent no-op when **neither** marker is present (config copied through verbatim, focus-ring left unthemed) — distinct from the data-loss H3 (START without END). | `bin/theme-switch:45-49` |
| **I3** | **(my coverage of the failed lens)** The `50-snapshots` `umount /.snapshots && rm -rf /.snapshots && create-config && mount -a` sequence runs **only on first config creation** (`have_root_config` gates it) and the `rm` is `&&`-chained after a successful `umount`, so it cannot delete mounted snapshot data; a crash between `umount` and `mount -a` leaves `/.snapshots` unmounted (data intact, recoverable via `mount -a`). `/etc/hosts` and `locale.gen` appends are pre-existence-guarded (no duplication); `genfstab >> fstab` runs only on the armed fresh-disk path. | `50-snapshots.sh:15-37`, `host-config.sh:9-11`, `base-install.sh:210` |

---

## Cross-cutting theme: drift-detection input coverage

**H1, M1, M2 share one root cause:** `module_hash` only sees files explicitly listed in `module_inputs()`, so any state-defining input not listed there is a **drift false-negative** — editing it converges nothing and `archfrican-doctor` falsely reports "matches the repo." Three distinct state-defining sources are currently unlisted: the theme **palettes** (`themes/*/colors.sh`), the theme **renderer + its templates** (`bin/theme-switch`, `templates/*.colors*`, `niri.theme.kdl`), and the **GPU arg**. This is the highest-leverage fix in this phase: completing `module_inputs` coverage (or rendering authoritatively-unconditionally) closes all three at once.

## Prior-audit reconciliation (state items — full matrix in Phase 5)

| Prior finding | Status now | Evidence |
|---|---|---|
| **HIGH** — btrfs rollback: `grub-btrfs.path` wrong unit + snapper create-config collision | **FIXED** | `50-snapshots.sh:46` uses `grub-btrfsd.service`; the ArchWiki `@.snapshots` procedure + post-condition `die` (`:53-57`) handle the collision |
| **SEC-07 (HIGH)** — theme-switch niri splice can truncate config on missing `THEME-END` | **STILL OPEN** | re-confirmed verbatim at `bin/theme-switch:45-49` → **H3** |
| **DATA-01 (HIGH)** — deployed theme-switch dead / 3 copies / docs falsely "tested" | **PARTIALLY FIXED** | `theme-switch` now resolves `ARCHFRICAN_ROOT` to the real clone and is exercised by CI `theme-switch-smoke`; but `40-theming` still hardcodes the wrong theme → new bug **H2** |

---

*Next: Phase 3 — Reliability & Robustness (error-handling vocabulary, partial-failure recovery, network resilience, `set -e` interactions; thin perf sub-lens).*
