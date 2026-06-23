# Phase 4 — Quality, Deprecations & Hygiene

**Scope:** CI enforcement reality, honest test-coverage map, deprecated APIs/package names, dead code & single-source-of-truth violations, comment/in-code-doc drift.
**Method:** 5 parallel finder lenses → adversarial verifier per candidate → my own grep reproduction.
**Pinned at committed HEAD `2a3f9b5`** — see the moving-target note below.

> ### ⚠ Moving-target note (audit integrity)
> The repo has **changed three times during this audit**: 97 → 102 → **110 tracked files**, and HEAD advanced from the original through `821e217` to **`2a3f9b5`** (4 new commits: a "premium SDDM greeter" + `module_hash` now hashing directories). The working tree is also **currently dirty** — modified `README.md`/`niri`/`waybar` configs and **6 untracked new scripts** (`archfrican-auto-appearance`, `-blur`, `-defaults`, `-keys`, `-privacy-indicator`, `-welcome-notify`) plus untracked darkman hooks. The Phase 4 finders read this live tree, so a few findings touch **uncommitted work-in-progress** (flagged inline). This phase audits the **committed** tree at `2a3f9b5`; uncommitted WIP is out of scope. **I recommend freezing the tree for Phases 5–6** (see the checkpoint).
>
> I re-verified that the `module_hash`-hashes-directories commit (`af81439`) added the `assets/sddm/archfrican` **directory** to 20-niri-desktop's inputs but **not** `themes/*/colors.sh` — so Phase 2 **H1/M1 still stand**.

## Verdict for this phase

Code **quality is high**: shellcheck-clean, a disciplined failure vocabulary, and — contradicting my Phase 0 baseline — the CI is a **real 11-gate enforcement net** (every `run:` step is `set -e`, so a shellcheck/`bash -n`/assertion failure fails the build; not "informational"). The prior audit's top P1 recommendation ("a minimal CI net") is **done and then some**. The real weaknesses are: **(1) test coverage** — CI smoke-tests the *pure-logic* units well, but the *system-mutating and security-critical* code (modules, `disk`, `fido2`, `health`, `detect-gpu`) is reachable only by a **manual VM e2e that can't run in CI**; and **(2) the greetd→SDDM migration is incomplete** — it left a real functional bug (`firstboot-notice.sh` checks the dead `greetd.service`) plus stale strings/comments.

### Candidate accounting (consolidated)

| | Count |
|---|---|
| Candidates raised | 34 |
| Survived verification | 31 |
| Refuted | 3 |
| **Distinct after consolidation** | ~16 |
| — HIGH | 1 |
| — MEDIUM | 6 |
| — LOW | 8 |
| — INFO | 1 |
| *(firstboot-notice greetd bug found by **3** lenses → 1 finding; 7 test-coverage findings → 1 themed map)* | |

## Reproduction (run locally, read-only)

```
CI jobs (all hard gates — GHA run: defaults to bash -e): shellcheck, bashn, firewall-ruleset,
  iso-safety-gate, migrations-idempotent, prune-safety, cachyos-trust, theme-switch-smoke,
  sddm-theme, pkg-resolution, grub-helper  = 11
Dead functions (0 call-sites): ui_spin, enable_user_service, faillock_recover_doc, ensure_git
Duplicated ucode detection: base-install.sh:39-41  ≡  60-security.sh:129-131  (GenuineIntel|AuthenticAMD)
Stale 'archinstall' in active code: install.sh:70 (die msg), disk.sh:5, 50-snapshots:17/21/22
Stale 'greetd' after SDDM migration: firstboot-notice.sh:5,8 (LIVE check!), phase2.sh:27, common.sh:45
```

---

## HIGH

### Q-H1 — The FIDO2 no-lockout PAM stack (the safety-critical security code) has **zero automated test reach**
- **File:** `lib/fido2.sh` (all 6 functions, esp. `fido2_pam_selfcheck:74-93`, `fido2_assert_version:13-20`)
- **Severity:** HIGH (test-gap on safety-critical code) · **Confidence:** high
- **Impact:** `lib/fido2.sh` enforces the project's strongest safety promises — the **no-lockout invariant** (the u2f line is `sufficient` *above* an intact password include, verified by `fido2_pam_selfcheck`) and the **CVE-2025-23013 version guard** (`fido2_assert_version` refuses pam-u2f < 1.3.1). Phase 1 verified the code is *correct today*, but **no test exercises it** — not CI (no key/PAM stack on the runner), not even the VM e2e (the autopilot path enrolls no key). The PAM-stack manipulation (`awk` insertion, selfcheck's `grep`/`awk` assertions) is exactly the kind of logic where a future refactor could silently break the "password always works" guarantee and **lock a user out of sudo/login** — with nothing to catch it. Untested + safety-critical + lockout-capable = HIGH.
- **Recommendation:** add a CI unit test that feeds `fido2_pam_insert`/`fido2_pam_selfcheck` **fixture** `/etc/pam.d/` files (a normal stack, a key-only stack, a stack with a non-u2f `sufficient` above the include) and asserts the selfcheck verdict + that the password include survives; and a `fido2_assert_version` test with fixture version strings around the 1.3.1 boundary. All are pure string-logic — no key needed.

---

## MEDIUM

### Q-M1 — Test-coverage map: system-mutating & security code is reachable only by the un-runnable VM e2e *(consolidates 7 findings)*
CI smoke-tests the **pure-logic** units that run on a container (theme render, migrations math, prune set-logic, grub helpers, pkg resolution, sddm render). Everything that mutates the system or needs hardware is covered **only** by `tests/e2e/selftest.sh`, which requires a real UEFI Arch VM and **cannot run in CI**. Honest gap map:

| Unit | Automated reach | Risk |
|---|---|---|
| `lib/fido2.sh` (no-lockout/CVE) | **none** | **HIGH** → Q-H1 |
| `lib/health.sh` (15 `check_*`) | **none** | MEDIUM — the doctor users trust |
| `lib/detect-gpu.sh` (`detect_gpu`/`nvidia_tier`) | only the VM's actual GPU | MEDIUM — pure `lspci`-string parsing, **fixture-unit-testable**; vendor/hybrid/tier branches untested |
| `lib/disk.sh` `confirm_wipe` | none (autopilot bypasses it) | MEDIUM — the **second destructive gate** before a wipe, untested |
| `lib/security.sh` `fw_allow` / `bin/fw-allow` | none | MEDIUM — *this is why Phase 1 **M4** (no port-range check) slipped through* |
| `bin/archfrican-doctor` (dispatch, `--fix` allowlist) | none | MEDIUM |
| `modules/*.sh` bodies | VM e2e only | MEDIUM (inherent for an installer) |
| `lib/ui.sh` | none | LOW |

- **Recommendation:** the `detect-gpu`, `fido2`, `fw_allow`/port-validation, `health` count-parsers, and `confirm_wipe` matching are **all pure string-logic** that can be fixture-unit-tested in CI without a VM — the highest-ROI coverage to add. (Bats would fit; the existing inline-CI-job style also works.)

### Q-M2 — Incomplete greetd→SDDM migration left a **functional bug**: `firstboot-notice.sh` gates its silence on the dead `greetd.service` *(found by 3 lenses: deprecations, dead-code, comment-drift)*
- **File:** `templates/firstboot-notice.sh:8` (comment at `:5`)
- **Severity:** MEDIUM · **Confidence:** high
- **Evidence:**
  ```sh
  if systemctl is-active --quiet greetd.service 2>/dev/null; then
    return 0   # the graphical desktop is up — stay silent
  ```
- **Impact:** the login stack is now **SDDM** (greetd is disabled by `migrations/0002` / never installed). So this branch — meant to silence the first-boot notice "once the desktop is up" — **never fires**. After a successful install (`/var/lib/archfrican/firstboot-done` exists), the notice falls through to branch 2 and **persistently prints "Archfrican: setup complete — reboot into your desktop"** on every interactive login shell, *even after the user is already in the SDDM/niri desktop*. The profile.d file is never removed (`phase2.sh:204` removes only the issue banner). Cosmetic but real and confusing; a one-line fix.
- **Recommendation:** check `sddm.service` (and update the `:5` comment). More robustly, gate on `graphical.target`/an active session rather than a specific DM name so the next DM swap doesn't re-break it.

### Q-M3 — `pkg-resolution` runs only on push/PR — no `schedule:`/`workflow_dispatch:`, so repo drift between commits is never re-caught
- **File:** `.github/workflows/ci.yml:7-9` (triggers), `:181-202` (job)
- **Severity:** MEDIUM · **Confidence:** high
- **Impact:** the recurrence-prevention net for "the class that let ghostty go missing" only fires on code changes. A package renamed/moved-to-AUR/dropped from the binary repos *after* the last push keeps the last CI run green while real installs hit it. *(Verifier tempered: the runtime `preflight_pkgs` re-checks at install time — but only **warns** by default, so a fresh install isn't fully protected either.)*
- **Recommendation:** add a weekly `schedule:` (and `workflow_dispatch:`) running at least `pkg-resolution`.

### Q-M4 — CPU-microcode detection is duplicated (SSOT violation)
- **Files:** `lib/base-install.sh:39-41` (`cpu_ucode`) ≡ `modules/60-security.sh:129-131` (`ucode_pkg` case)
- **Severity:** MEDIUM · **Confidence:** high
- **Impact:** the identical `GenuineIntel|AuthenticAMD → intel-ucode|amd-ucode` logic lives in two places (Stage-1 ISO + Stage-2 booted). A future vendor/logic change to one silently drifts from the other. (Contrast the GPU logic, which is correctly centralized in `detect-gpu.sh`.)
- **Recommendation:** extract one `cpu_ucode` helper (e.g. into `common.sh` or a small shared lib both already source).

### Q-M5 — `lib/disk.sh` header documents a workflow that no longer exists ("the format happens later, inside archinstall")
- **File:** `lib/disk.sh:2-5`
- **Severity:** MEDIUM *(finder said HIGH; verifier lowered — misleading-doc, not a code bug)* · **Confidence:** high
- **Impact:** `base-install.sh` **replaced** archinstall (it drives `sgdisk`/`cryptsetup`/`mkfs` directly), but `disk.sh`'s header still says formatting "happens later, inside archinstall." A maintainer reading it would misunderstand where the wipe actually occurs — dangerous context for the highest-consequence code. (Same class: `install.sh:70` die message "it drives archinstall" → LOW below.)
- **Recommendation:** rewrite the header to reference `lib/base-install.sh`.

### Q-M6 — `bin/theme-switch` comment names the wrong module as the authoritative SDDM render owner
- **File:** `bin/theme-switch:54`
- **Severity:** MEDIUM · **Confidence:** high
- **Impact:** the comment says "the authoritative render happens at install/converge (40-theming)", but `render_sddm_theme` is owned by **20-niri-desktop** (`common.sh:79`, called at `20-niri-desktop.sh:20`). A maintainer chasing the login-theme render would look in the wrong module — and this is adjacent to the Phase 2 H1 palette-drift gap.
- **Recommendation:** correct to `20-niri-desktop`.

---

## LOW

| # | Finding | File |
|---|---------|------|
| **Q-L1** | Dead functions (0 call-sites, verified): `ui_spin`, `enable_user_service` (superseded by `resilient_enable_user`), `faillock_recover_doc` (its text is duplicated inline in the faillock heredoc), `ensure_git` (dead duplicate of `install.sh::_ensure_git`). | `ui.sh`, `common.sh`, `security.sh`, `env.sh` |
| **Q-L2** | Stale `greetd` strings/comments after the SDDM migration: `phase2.sh:27` `module_desc` still says "greetd login" (printed to the user during install); `common.sh:45` comment "(greetd, docker)". | `phase2.sh`, `common.sh` |
| **Q-L3** | Stale `archinstall` references in active code: `install.sh:70` die message "it drives archinstall"; `50-snapshots.sh:17,21,22` credit the `@.snapshots` mount to archinstall (it's `base-install` now). Logic still works; attribution is wrong. | `install.sh`, `50-snapshots.sh` |
| **Q-L4** | `lib/env.sh:5-6` ships a self-flagged uncertainty `(a confirmar on the exact ISO build…)` in the canonical ISO-detection comment — verify `/run/archiso` is the right marker and resolve the note. | `env.sh` |
| **Q-L5** | CI minor gaps: `firstboot-notice.sh` is shellcheck'd but not in the `bash -n` glob (`ci.yml:29-30`); `theme-switch-smoke` checks `niri/config.kdl` idempotency but not for unrendered `${VAR}` tokens (only the 4 color files); migration *script* idempotency is only incidentally exercised by the runner-level `migrations-idempotent` job. | `ci.yml` |
| **Q-L6** | `lib/ui.sh` wizard primitives untested (no CI, no e2e) — the stdout-value/stderr-prompt contract under errexit is unverified. | `ui.sh` |
| **Q-L7** | Partition-suffix helper duplicated: `part_dev()` (`base-install.sh:37`) re-implemented verbatim as `part()` in `selftest.sh:48`. *(Lower priority — test code intentionally independent of prod; noted for SSOT completeness.)* | `base-install.sh`, `selftest.sh` |
| **Q-L8** | **(uncommitted WIP)** The darkman `{dark,light}-mode.d/executable_*` hooks are linted by **no** CI gate (the globs only match `home/dot_local/bin/executable_*`). *These files are currently **untracked** — when committed, extend the shellcheck (`-s sh`) + `bash -n` globs to `home/dot_local/share/*-mode.d/executable_*`.* | `ci.yml` |

## INFO

- **Q-I1** — `docs/CONTEXT.md` peripherals table still lists `swww` as the wallpaper daemon, but the deployed config/packages use `awww-daemon` (`verify_spawns` expects `awww-daemon`). → folded into **Phase 5** docs reconciliation.

---

## Refuted / Discarded (3 of 34)

| Claim | Why refuted |
|---|---|
| **`firewall-ruleset` `nft -c` is best-effort, so the gate is vacuous** | By design — the comment says so, and the **two `grep` gates** (`flush ruleset` absent → `exit 1`; `table inet filter` present → `exit 1`) are the hard guarantee; `nft -c` can't cleanly validate the create/delete/recreate idiom. The gate enforces what matters. |
| **`selftest.sh` runs ~49 assertions but a doc claims "8 checks"** | No real doc/code mismatch — the "8" refers to the STAGE2 pass-criteria, not the assertion count; nothing misclaims coverage. Not a finding. |
| **`40-theming` comment "applied last by chezmoi" is false** | Real, but already captured as **Phase 2 H2** (the hardcoded `theme-switch macos-dark` bug) — deduped, not double-counted. |

---

## Cross-references

- **Q-M2 (firstboot-notice) + Q-L2 + Q-L3** all stem from one root: the **greetd→SDDM migration was applied to the convergence inputs and the install path but not swept across the support scripts/strings/comments**. A single grep-sweep for `greetd`/`tuigreet`/`archinstall` would close them.
- **Q-M1 (fw_allow untested)** explains how **Phase 1 M4** (the `fw-allow` no-range-check firewall-wedge) reached `main`: that code path has no test.
- **Q-M5/Q-M6** (wrong-module / replaced-tech comments) feed the **Phase 5** docs↔code reconciliation.

## Prior-audit reconciliation (quality items — full matrix in Phase 5)

| Prior finding | Status now | Evidence |
|---|---|---|
| **P1 (highest-ROI): "add a minimal CI net — shellcheck + shfmt + theme-switch smoke + package-existence"** | **DONE (and exceeded)** | 11 hard-gate CI jobs incl. shellcheck, theme-switch-smoke, pkg-resolution, migrations/prune/grub/sddm gates. *(Caveat: `shfmt` was recommended but is **not** present — only shellcheck.)* |
| Prior "no tests / 0 unit tests" | **PARTIALLY ADDRESSED** | CI smoke-tests the pure-logic units; system-mutating + security code still untested → **Q-M1/Q-H1** |
| Prior hygiene (`.DS_Store`, `*.zip` cruft) | **MOSTLY FIXED** | `.gitignore` now covers `*.zip`, `.DS_Store`, `*.log`; no tracked cruft (`git ls-files` clean) |

---

*Next: Phase 5 — Docs ↔ Code consistency + the full prior-audit reconciliation matrix (pending the pinning decision at the checkpoint).*
