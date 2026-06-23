# Appendix — Baseline, Method & Limitations

## Phase 0 baseline (the stack, as detected — not assumed)

The prompt's default web-app lenses (authZ/IDOR/RLS/XSS/CORS, ORM/SQL) were **dropped** after reconnaissance: there is no server, no database, no web framework. The lenses were re-aimed at a **Bash system-installer**.

| Dimension | Finding (frozen at `2a3f9b5`) |
|---|---|
| **Language / size** | Pure **Bash**, ~3,000 LOC; **110 tracked files**. No `package.json`/`go.mod`/`Cargo.toml`/etc. No git submodules. |
| **What it is** | (1) an Arch **ISO installer** (`lib/base-install.sh`: `sgdisk`/`cryptsetup`/`mkfs.btrfs`/`pacstrap`/`arch-chroot`/GRUB — the "bedrock" replacement for archinstall, ships **dry-run-gated**); (2) a **chezmoi** dotfiles manager (`home/`); (3) a **convergent updater** (`bin/archfrican-update`, `lib/converge.sh` — "the system = the repo, applied"). |
| **Layout** | `install.sh` (dispatcher) → `lib/` (17 files) → `modules/` (9: `00-base`…`70-hygiene`) → `bin/` (4 tools) → `packages/*.txt`, `themes/`, `templates/`, `migrations/`, `assets/sddm/`. |
| **Login stack** | **SDDM** + a custom QML `archfrican` theme (migrated from greetd/tuigreet during the prior dev cycle). |
| **Tooling** | shellcheck (`-x -e SC1091`) + `bash -n` in CI; `.editorconfig`. **No** `.shellcheckrc`, **no** `shfmt`, **no** bats/shunit2. `set -euo pipefail` centralized in `common.sh:4`. |
| **CI** | `.github/workflows/ci.yml` — **11 hard-gate jobs** on every push/PR: `shellcheck`, `bashn`, `firewall-ruleset`, `iso-safety-gate`, `migrations-idempotent`, `prune-safety`, `cachyos-trust`, `theme-switch-smoke`, `sddm-theme`, `pkg-resolution`, `grub-helper`. (GHA `run:` defaults to `set -e`, so each is blocking — *not* informational.) No `schedule:`/`workflow_dispatch:`. |
| **Tests** | **No unit tests.** One VM-based e2e harness `tests/e2e/selftest.sh` (~244 LOC; ~49 assertions across `install`/`postboot`/`update`/`rerun`) requiring a real UEFI Arch VM — **not runnable in CI or here**. |
| **Secrets** | **None tracked.** `.gitignore` excludes `archinstall/user_credentials.json`, `tests/e2e/answers.env`, `*.log`, `*.zip`, `.DS_Store`. Verified untracked + absent from git history (`git ls-files`, `git check-ignore`, `git log --diff-filter=A`). |
| **Prior audit** | `docs/audit/` (~mid-2026): 1 CRITICAL, 11 HIGH, 25 MED, 26 LOW, 30 INFO. Reconciled in [05-docs-vs-code.md](05-docs-vs-code.md). |

## Moving-target chronology (audit-integrity note)

The repository was **actively developed during this audit**. This is unusual for a point-in-time audit and is disclosed for transparency:

| Observed at | Tracked files | HEAD | What changed |
|---|:---:|---|---|
| Phase 0–1 | 97 | (original) | baseline |
| Phase 2 (re-baseline) | 102 | `821e217` | **greetd → SDDM** login migration (+ `migrations/0002`) |
| Phase 4 (re-baseline) | 110 | `2a3f9b5` | "premium SDDM greeter"; `module_hash` now hashes **directories**; **dirty working tree** (6 uncommitted new scripts: `archfrican-auto-appearance`/`-blur`/`-defaults`/`-keys`/`-privacy-indicator`/`-welcome-notify` + untracked darkman hooks; edited README/niri/waybar) |

**Resolution (user decision):** the audit was **frozen at committed HEAD `2a3f9b5`** from Phase 4 onward. Dirty files were read via `git show 2a3f9b5:<path>`; the 6 uncommitted WIP scripts and the WIP config/README edits are **out of scope**. Findings from Phases 1–3 were spot-re-verified against the moving tree where relevant (e.g. Phase 2 **H1** was re-confirmed after the directory-hashing commit; the SDDM migration's incompleteness produced Phase 4 **Q-M2**).

## Tools run (reproductions, all read-only / non-destructive)

| Check | Result |
|---|---|
| `shellcheck -x -e SC1091` (CI mode) over all `.sh` + `bin/*` | **exit 0 — clean** |
| `shellcheck -x` (unfiltered) | **0 findings** (the only suppressions are 4 inline `# shellcheck disable` directives) |
| `bash -n` over all scripts | **all pass** |
| `git ls-files` / `git check-ignore` / `git log --diff-filter=A` for secrets | none tracked, properly ignored, none in history |
| `git grep` for `eval`, `curl\|bash`, dangerous patterns | no `eval`; `curl\|bash` only in a doc comment |
| Migration sandbox (temp `REPO_ROOT`, no sudo): `_mig_latest`, `pending_migrations`, glob order | math correct; surfaced the **lexical-vs-numeric glob ordering** foot-gun (P2-L5) |
| Dead-function grep (define vs call sites) | confirmed `ui_spin`/`enable_user_service`/`faillock_recover_doc`/`ensure_git` uncalled |
| `git show 2a3f9b5:packages/niri-desktop.txt` (Ghostty), `:config.kdl.tmpl` (blur) | Ghostty present (`:3`); blur present-but-commented (opt-in) |
| CI gate logic read + traced (`migrations-idempotent`, `prune-safety`, `grub-helper`, `sddm-theme`, `firewall-ruleset`) | gates are real (each `set -e` + `exit 1`); the `nft -c` step is by-design best-effort with grep gates as the hard guarantee |

## Method

- **Per phase (1–5):** a `Workflow` fan-out of 4–6 finder lenses (each reading the real code, returning structured findings), then an **independent adversarial verifier per candidate** instructed to *refute* it by re-reading the code (default `isReal=false`). Survivors only; severities and citations corrected; refutations recorded. De-duplicated across lenses, then synthesized into the phase `.md`.
- **Independent verification:** I read every `lib/`, `modules/`, and `bin/` file myself and hand-checked each reported `file:line` and quote against the source — agent output was treated as *candidate evidence*, not conclusion. Several agent claims were corrected or dropped on that basis (the Phase-0 finders' optimistic "SAFE"/"LIKELY-FIXED" labels were not trusted; my own "phantom SDDM inputs" lead was self-refuted when the files turned out to exist).
- **Severity:** CRITICAL = exploitable / data-loss / breaks-today; HIGH = serious latent bug or false safety claim; MEDIUM = correctness/robustness/test-gap; LOW = hygiene; INFO = note. For docs↔code, severity = the risk that someone trusts the wrong doc.
- **Rigor signal:** 112 candidates → 102 survived / **10 refuted (~9%)**, comparable to the prior audit's ~8.6%. Each phase carries an open **"Refuted / Discarded"** section.

## Limitations (read these before trusting any single finding)

1. **No VM end-to-end run.** The destructive ISO install + first-boot resume could **not** be executed here (no Arch UEFI VM; it wipes a disk). Findings about install-time behavior are from **static analysis + tracing + the project's own `selftest.sh`**, not from observing a real install. The first-boot-resume HIGHs (H#1/H#2) are reasoned from the systemd unit semantics + code, and should be **confirmed on a throwaway VM**.
2. **Frozen snapshot.** Pinned at `2a3f9b5`; the live repo has since diverged (dirty tree, 6 uncommitted scripts). Re-check findings against the tip before acting, and **audit the new scripts separately** once committed.
3. **CVE / version / deprecation claims are "to confirm live."** Auditor knowledge has a cutoff; package-name/deprecation/CVE statements were grounded against the repo where possible (e.g. the pinned pam-u2f ≥ 1.3.1 / CVE-2025-23013 guard) and otherwise flagged "to confirm with `pacman`/current Arch docs." No CVE was asserted from memory; recommend `arch-audit` / `pacman -Qu` on a target.
4. **One finder aborted** (Phase 2 `destructive-append`, infrastructure error) — that surface was covered by my own direct reading (appends are guarded; only an INFO-level snapshot-umount window), noted in [02-state-integrity.md](02-state-integrity.md).
5. **The `audit/` folder is the only artifact written.** No source, config, doc, or CI file was modified; no commits were made.
