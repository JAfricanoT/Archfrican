# Archfrican — Audit Executive Summary

**Target:** `Archfrican` — a personal Arch Linux installer (Bash) + chezmoi-managed dotfiles, built around
the **niri** scrolling compositor with a macOS-friendly UX. **Stated #1 principle:** reliability —
"nothing explodes".
**Deliverable:** report only (no source code modified — the only output is `audit/`).
**Method:** 5 fan-out phases, each with parallel finders + an **adversarial verifier** per candidate
that tried to *refute* it before it entered the report. Static analysis only (see Limitations).

---

## Honest verdict

Archfrican is a **thoughtfully-designed but unfinished v0 whose package-install path has clearly never run
end-to-end on hardware** — which `docs/CONTEXT.md` itself admits ("un v0 para iterar, no para correr a
ciegas en hardware todavía"). The architecture is genuinely good: modular/swappable compositor,
sensible Btrfs+Snapper layout, a dual-kernel safety net, a clean `REPO_ROOT` convention, correct module
isolation, and **docs that are mostly honest** (13 verified doc↔code matches, including the non-trivial
keyd/niri no-collision keybinding design).

But the two things Archfrican sells as its essence — the **hot-swap theme switcher** and the **one-reboot
rollback safety net** — are exactly what's broken, and a **single CRITICAL parser bug means phase-2
installs cannot complete at all** as shipped. None of this is caught by any test, because **there are no
tests and no CI** — the only check is `bash -n` (syntax-only), which catches none of the findings below.

The good news: most fixes are small and local. The CRITICAL is a one-line `sed`; the rollback,
detect-gpu, and theme-switch breakages are each a handful of lines. This is a v0 that needs a **focused
correctness pass + a minimal CI net**, not a redesign.

---

## Numbers by phase and severity

Severities are the **deduplicated report counts** (one issue = one entry; cross-lens duplicates merged).
"Survived / Refuted" are the **raw** finder candidates, showing the adversarial filter's work.

| Phase | CRÍT | ALTO | MEDIO | BAJO | INFO | Raw candidates → survived / **refuted** |
|-------|:----:|:----:|:-----:|:----:|:----:|:---------------------------------------:|
| 1 · Security & supply chain | **1** | 1 | 8 | 6 | 5 | 31 → 27 / **4** |
| 2 · Data integrity & destructive ops | 0¹ | 2 | 4 | 4 | 7 | 32 → 29 / **3** |
| 3 · Reliability & robustness | 0 | 4 | 7 | 6 | 3 | 27 → 24 / **3** |
| 4 · Quality, deprecations & hygiene | 0 | 2 | 2 | 4 | 2 | 28 → 26 / **2** |
| 5 · Docs ↔ code | 0 | 2 | 4 | 6 | 13² | 33 → 32 / **1** |
| **Total** | **1** | **11** | **25** | **26** | **30** | **151 → 138 / 13** |

¹ Phase 2's DATA-02 is a **conditional CRITICAL** (escalates if the systemd unit name is confirmed wrong
on target — very likely). ² Phase 5's INFO count is mostly **positive matches** (the reconciliation
matrix). **Refuted = 13/151 ≈ 8.6%** — including an invented "AUR package breaks the batch", an invented
"CVE-class" GPU-agnostic contract violation, a "polkit deprecated" claim that read the wrong file, and
several findings dismantled by the *errexit-is-actually-active* correction (see below).

> **A refutation worth highlighting** (rigor signal): the Phase-0 recon asserted "modules lack
> `set -euo pipefail`, so they silently continue on errors." The verifiers **disproved this empirically**
> — every module sources `common.sh` (which sets it) as its first line, and `set` persists. This flipped
> the entire reliability narrative: the real problem is **inconsistent** error handling (errexit so
> active that best-effort steps abort the whole install), not *missing* error handling.

---

## Convergence — the highest-ROI fixes

One file dominates: **`bin/theme-switch` appears in ALL FIVE phases.** If you fix one thing, fix it.

| File | Phases | Findings |
|------|:------:|----------|
| **`bin/theme-switch`** | 1·2·3·4·5 | SEC-06/07/15, DATA-01/03/04, REL-09, QUAL-03/04, DOC-02/06 — broken `ROOT` when deployed, reverted by chezmoi, 3 copies, sed/awk fragility, dead vars, false "tested" claim |
| **`modules/00-base.sh`** | 1·2·3 | SEC-02/03/14, REL-13 — unverified root RCE (CachyOS), unreviewed AUR bootstrap |
| **`lib/common.sh`** | 1·3 | **SEC-01 (the CRITICAL)**, REL-12 — package-list parser + silent no-op masks |
| **`modules/50-snapshots.sh`** | 2 | DATA-02 — the rollback safety net (the #1 reliability promise) not reliably wired |
| **`install.sh`** | 2·3 | REL-02/03/05, DATA-06 — fragile orchestration, no trap/resume |
| **`modules/10-gpu.sh`** | 1·3 | SEC-09/10, REL-01/06/07/08/16 — detect abort, silent sed no-ops, hardware gaps |

---

## All CRITICAL / HIGH issues (deduplicated across phases)

| # | Sev | Issue | Where | Phase refs |
|---|:---:|-------|-------|-----------|
| 1 | **CRÍTICO** | Package-list parser doesn't strip **inline comments** → every `pacman` batch gets a malformed target → **phase-2 install aborts on the first module, every run** | [lib/common.sh:34-35](../../lib/common.sh#L34-L35) | SEC-01 |
| 2 | **ALTO→CRÍT cond.** | Btrfs **rollback safety net not wired**: `grub-btrfs.path` is the wrong unit (modern = `grub-btrfsd.service`) → module 50 aborts under errexit; + `snapper create-config` collides with archinstall's `@.snapshots` | [50-snapshots.sh:6-13](../../modules/50-snapshots.sh#L6-L13) | DATA-02 |
| 3 | **ALTO** | **CachyOS repo bootstrap = unverified root code execution** (no checksum/signature/pin; fetched then `sudo ./script`) | [00-base.sh:8-11](../../modules/00-base.sh#L8-L11) | SEC-02 |
| 4 | **ALTO** | **Deployed `theme-switch` is dead**: `ROOT` resolves to `~/.local` (no `themes/`/`templates/`); reverted by chezmoi; ships in 3 copies; docs call it "tested working" | [theme-switch:6](../../bin/theme-switch#L6) | DATA-01, QUAL-03, DOC-02/06 |
| 5 | **ALTO** | **Ghostty (the documented terminal) is installed by nothing** → `Mod+Return` dead on a fresh box | [packages/*](../../packages/) (absent), [config.kdl:64](../../home/dot_config/niri/config.kdl#L64) | QUAL-01, DOC-01 |
| 6 | **ALTO** | **GPU detection aborts the installer at step 1** on a no-VGA host or where `lspci`/`pciutils` is absent (the "unknown" fallback is unreachable under pipefail) | [detect-gpu.sh:5](../../lib/detect-gpu.sh#L5) | REL-01 |
| 7 | **ALTO** | **`rustup default stable` lacks `\|\| true`** (its `fnm` sibling has it) → a transient failure **halts the entire installer** before theming/snapshots/chezmoi | [30-dev.sh:9-10](../../modules/30-dev.sh#L9-L10) | REL-02 |
| 8 | **ALTO** | **No `trap`/rollback/resume guidance** → a mid-install abort leaves a partial, order-dependent state with no signal | [install.sh:22-31](../../install.sh#L22-L31) | REL-03 |
| 9 | **ALTO** | **macOS GTK look not applied at install** — `gsettings` from a TTY (no session bus) fails, masked by `\|\| true` | [40-theming.sh:10-15](../../modules/40-theming.sh#L10-L15) | REL-04 |
| 10 | **ALTO** | **No tests, no CI** on a reliability-first installer — `bash -n` catches none of the above | repo-wide | QUAL-02 |

---

## Cross-cutting themes

1. **The package path was never executed on hardware.** SEC-01 (parser) + QUAL-02 (no tests) + the fact
   that "tested working" only ever exercised the repo-relative theme-switch copy → the *install* is
   unverified. (CONTEXT.md is honest about this being a v0.)
2. **The two signature features are the broken ones.** Hot-swap theming (DATA-01/03, DOC-02/06) and
   one-reboot rollback (DATA-02) — plus the macOS aesthetic (blur DOC-03, GTK REL-04) — are exactly the
   selling points that don't work as shipped.
3. **Inconsistent error handling.** errexit *is* active (via sourced `common.sh`), so the failure mode is
   bimodal: best-effort steps that forgot `|| true` **abort the whole install** (REL-01/02), while
   `|| true` elsewhere **masks real misconfiguration** (REL-04/08/12/14). A single `warn`-on-failure
   discipline fixes most.
4. **Supply chain is entirely trust-on-first-use.** curl|bash bootstrap, unverified CachyOS tarball,
   unpinned/unreviewed AUR + paru bootstrap — all `--noconfirm`, none pinned or checksummed
   (SEC-02/03/04/11).
5. **Docs are mostly honest but oversell aspirational features.** blur, full live-reload, and ghostty are
   presented as done; idempotency and "tested working" are overstated. 13 claims verify correctly.

---

## Prioritized roadmap (grouped by theme, not a flat list)

### P0 — Immediate (before *any* real-hardware run)
- **Make the install able to complete:** strip inline comments in the package parser (SEC-01); verify
  every package name resolves in official repos (`pacman -Sp` on an Arch image) to kill the
  AUR-in-pacman-list risk; **add `ghostty`** to a package list (QUAL-01).
- **Make GPU detection survive:** `vga="$(lspci -nn 2>/dev/null | grep … || true)"` + ensure `pciutils`
  (REL-01); make `rustup` best-effort (REL-02).
- **Make the theme switcher actually work as deployed:** fix `ROOT` to an absolute install path and
  collapse the 3 copies to one (DATA-01, QUAL-03).
- **Make rollback real:** `grub-btrfsd.service` + snapper-create-config robustness, validated on a VM
  (DATA-02).

### P1 — Near-term (weeks)
- **Reliability net:** add an `ERR` trap with the failed-module + resume command (REL-03); make
  `chezmoi init --apply` resilient (REL-05); group NVIDIA grub+mkinitcpio edits atomically + retry
  (REL-06); add a `hybrid-amd-intel` profile (REL-07).
- **Apply the macOS look for real:** write GTK settings via `~/.config/gtk-*/settings.ini` instead of
  TTY `gsettings` (REL-04).
- **Theme/chezmoi ownership:** chezmoi-ignore the generated color files + re-apply saved `.archfrican-theme`
  (DATA-03); guard the niri splice against a missing `THEME-END` (SEC-07); stop clobbering `/etc/greetd`
  & `/etc/keyd` unconditionally (SEC-05).
- **Supply-chain hardening:** pin/verify the CachyOS tarball and bootstrap; pin AUR; refresh
  `archlinux-keyring`/`pacman-key` before bulk installs (SEC-02/03/04/11).
- **A minimal CI net** (the highest single ROI): shellcheck + shfmt + a `theme-switch` idempotency
  smoke test + a package-existence check (QUAL-02). This alone would have caught a large fraction of
  Phases 1-3.

### P2 — Medium-term
- **Implement or downgrade to 🚧 ROADMAP:** niri blur (DOC-03) and full live-reload (DOC-04/REL-09).
- **Reconcile the docs:** soften "idempotent" and "tested working" (DOC-02/05); fix envsubst→sed,
  `20-niri`→`20-niri-desktop`, VS Code→Code-OSS, keyd 7→13, "move"→"focus", README duplication
  (DOC-07…12).
- **Hygiene & dead code:** remove `archfrican.zip`/`.DS_Store`/root duplicates, fix `.gitignore`, resolve the
  `Archfrican`/`archfrican`/`~.archfrican` naming (QUAL-05); delete `ACCENT2`/`ORANGE`/`THEME_NAME`/`inter-font`/
  `code-flags.conf.d` and derive `VARS` programmatically (QUAL-04/06); guard zinit/starship in zshrc
  (REL-11/17).

---

## Documentary reconciliation matrix

| Documented contract | Real state | Action |
|---------------------|-----------|--------|
| "Ghostty is the terminal" (README:34) | Installed by nothing | **Implement** (add package) |
| "rollback in one reboot" (README:19) | grub-btrfs unit wrong / create-config collision | **Fix code** |
| "theme-switch tested working & idempotent" (CONTEXT:82) | Deployed copy broken; only repo copy tested | **Fix code + correct doc** |
| "niri blur / efecto vidrio" (README:37, CONTEXT:44) | No blur enabled; comment falsely claims it is | **Implement or 🚧 ROADMAP + fix comment** |
| "Switching is live across 6 apps" (README:65) | Only waybar+mako reload | **Soften doc / add reloads** |
| "Idempotent: safe to re-run any time" (install.sh:4) | Re-run reverts theme; chezmoi not atomic | **Soften doc + fix code** |
| "GPU-agnostic, runs on any machine" (README:17) | Aborts on no-VGA/missing lspci | **Fix code** (REL-01) |
| templates use "envsubst" (README:89) | pure sed | **Fix doc** (B) |
| module "20-niri" (README:86) | `20-niri-desktop` | **Fix doc** (B) |
| "VS Code" (README:35) | `code` = Code-OSS | **Fix doc** (B) |
| keyd maps ⌘+C/V/X/Z/A/S/F (README:76) | maps 13 letters | **Fix doc** (B) |
| Keybind "no plain Mod+letter" (CONTEXT:49) | ✅ Upheld | none |
| Dual kernel, GPU stacks, 4 themes, isolation, 42 files, `bash -n` | ✅ Match | none |

---

## Appendices
- **Baseline (Phase 0) & method/limitations:** see [appendix-baseline.md](appendix-baseline.md).
- **Per-phase detail:** [01-security-supply-chain.md](01-security-supply-chain.md) ·
  [02-data-integrity-ops.md](02-data-integrity-ops.md) ·
  [03-reliability-robustness.md](03-reliability-robustness.md) ·
  [04-quality-hygiene.md](04-quality-hygiene.md) · [05-docs-vs-code.md](05-docs-vs-code.md).
