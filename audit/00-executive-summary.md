# Archfrican — Audit Executive Summary

**Target:** `Archfrican` — a personal Arch Linux installer + chezmoi dotfiles manager + convergent updater, **pure Bash** (~3,000 LOC), built around the **niri** compositor with a macOS-friendly UX and **SDDM** login. Stated #1 principle: reliability — "nothing explodes."
**Deliverable:** report only — **no source code was modified**; the only output is `audit/`.
**Method:** 5 fan-out phases, each with parallel finder lenses + an **adversarial verifier per candidate** that tried to *refute* it before it entered the report, plus my own line-by-line re-verification and reproducible checks (shellcheck, `bash -n`, CI-gate replay, migration sandbox). **Frozen at committed HEAD `2a3f9b5`** (see the moving-target note in the appendix).
**Independent of the prior audit** (`docs/audit/`) — produced from fresh evidence, then reconciled against it.

---

## Honest verdict

**Archfrican is a markedly more mature codebase than the prior audit found — and the prior audit was clearly acted upon.** That audit's lone **CRITICAL** (the package-parser that blocked every install) and **~10 of its 11 HIGHs** are **fixed**; the project added an **11-gate CI net**, replaced archinstall with a **dry-run-gated bedrock installer**, migrated greetd→SDDM, and built a **content-addressed convergent updater**. The security fundamentals are **genuinely sound**: secrets are FD-passed and zeroed (never argv/env/disk), the disk-wipe path is triple-gated, the firewall never flushes foreign tables, FIDO2 is provably non-exclusive with a CVE-2025-23013 guard, and `SECURITY.md`'s every guarantee holds in code.

**No CRITICAL finding survived verification.** The codebase is shellcheck-clean and `bash -n`-clean.

What remains are **7 HIGH** issues, and they share a signature: they are **failure-path and latent bugs, not happy-path breakage**. The install works; the danger is what happens when a step *fails* or a value is *edited*. The single dominant theme is the **first-boot resume**: on a deterministic failure (a dropped package; a WiFi-only laptop) it can **boot-loop forever with a passwordless-root sudoers drop-in left live** — the convergence of a security finding and two reliability findings on one systemd unit. The second theme is the **convergent updater + theming path**: it can silently run a stale tree, silently reset the user's theme, miss palette drift, or truncate a pre-degraded niri config (the one prior finding still open, **SEC-07**).

**This is a solid v0.x that needs a focused failure-path + first-boot-resume hardening pass — not a redesign.** The biggest single return is hardening **one systemd unit**.

> **Honesty caveat:** I could **not** run the VM end-to-end install (no Arch VM available; it is destructive). The on-hardware install behavior is covered by the project's own `tests/e2e/selftest.sh` + my static analysis and reproductions — not by me executing the installer. See Limitations.

---

## Numbers by phase and severity

Per-phase **adjusted, de-duplicated** counts as reported in each phase file. "Candidates → survived / **refuted**" are the raw finder outputs, showing the adversarial filter's work.

| Phase | CRIT | HIGH | MED | LOW | INFO | Candidates → survived / **refuted** |
|-------|:----:|:----:|:---:|:---:|:----:|:---:|
| 1 · Security & supply chain | 0 | 0 | 4 | 3 | 6 | 16 → 15 / **1** |
| 2 · State integrity & destructive ops | 0 | 3 | 6 | 5 | 2 | 15 → 15 / **0** |
| 3 · Reliability & robustness | 0 | 3 | 1 | 4 | 1 | 14 → 9 / **5** |
| 4 · Quality, deprecations & hygiene | 0 | 1 | 6 | 8 | 1 | 34 → 31 / **3** |
| 5 · Docs ↔ code (+ reconciliation) | 0 | 0¹ | 2 | 8 | 2² | 33 → 32 / **1** |
| **Total (pre cross-phase dedup)** | **0** | **7** | **19** | **28** | **12** | **112 → 102 / 10** |

¹ Phase 5 surfaced prior **SEC-07** as still-open, but it is counted once as Phase 2 **H3** (not double-counted). ² Excludes the **8 positive "PRIOR-FIXED" confirmations** the reconciliation produced.
**Refuted = 10 / 112 ≈ 9%** — including the "FIDO2 bypasses faillock" claim (faillock only counts *failures*), the "grub-mkconfig 3-5× is material perf waste" claim (sub-second; os-prober not active on the baseline regens), the "`pf_net` needs retry" claim (`network-online.target` already gates it), and two "praise notes" dropped as non-findings.

---

## Cross-phase convergence — the highest-ROI fixes

These files/artifacts appear across **multiple phases** — fix them first.

| Artifact | Phases | Findings | Why it matters |
|---|:---:|---|---|
| **`archfrican-resume.service` + `phase1.sh:40` (NOPASSWD) + warn-only preflight** | **1 · 3** | P1-M1, **P3-H1**, **P3-H2** | **The #1 fix.** Deterministic first-boot failure → infinite retry → desktop never installs → passwordless-root drop-in stays live. Two triggers (dropped pkg; WiFi-only laptop). |
| **`bin/theme-switch` + theming path (`40-theming`, `converge.sh` inputs)** | **2 · 4 · 5** | **P2-H1/H2/H3**, M1, L3/L4, Q-M6, D-reconcile | The recurring hot spot (it was in all 5 phases of the prior audit too): config-truncation (SEC-07), silent theme reset, palette drift-blindness. |
| **`bin/archfrican-update:107` (`git reset --hard`)** | **2 · 3** | **P3-H3**, P2-M3 | One line, two failure modes: a *failed* reset reports "current" and converges stale; a *successful* reset silently discards local edits. |
| **`modules/00-base.sh:9` (CachyOS bootstrap)** | **1 · 3** | P1-M2, P3-M1 | Unverified root-run script (security) + no retry/timeout (reliability) on the same download. |
| **`lib/security.sh` `fw_allow`** | **1 · 4** | P1-M4, Q-M1 | The no-port-range firewall-wedge (P1-M4) reached `main` *because* that code has no test (Q-M1). |

---

## All HIGH issues (deduplicated across phases) — there are no CRITICALs

| # | Issue | Where | Phase |
|---|-------|-------|:----:|
| 1 | **First-boot resume retries a deterministic failure forever, leaving the `NOPASSWD: ALL` drop-in live every boot** (preflight is warn-only by default, so a dropped/renamed package passes then fails fatally; `ExecStartPost` cleanup runs only on success). | `archfrican-resume.service:26-29`, `common.sh:161`, `phase1.sh:40` | 3·1 |
| 2 | **WiFi-only laptop → unrecoverable first-boot boot-loop**: `inject_resume` reads WiFi creds from the NM dir, but the standard ISO tool `iwctl`/iwd writes to `/var/lib/iwd`; no profile → the fatal `pf_net` gate aborts every boot (NOPASSWD also lingers). | `phase1.sh:48-49` | 3 |
| 3 | **`archfrican-update` runs a STALE tree and reports success** when `git reset --hard` fails under `set +e` (prints "repo already current"). Defeats the "system = the repo" promise. | `archfrican-update:107` | 3 |
| 4 | **`40-theming` hardcodes `theme-switch macos-dark`**, silently overriding the user's wizard-chosen theme on install and **resetting a long-standing theme on every converge** (violates the documented "set once, preserved" invariant). | `40-theming.sh:20-21` | 2 |
| 5 | **niri config splice truncates the user's entire config** when `THEME-END` is missing (everything after `THEME-START` dropped, committed atomically, no backup). **= prior SEC-07, still open.** | `theme-switch:45-49` | 2 |
| 6 | **SDDM login palette is a drift false-negative**: editing `themes/*/colors.sh` changes no module hash, so drift detection reports "matches the repo" and `--converge` never re-renders the login theme. | `converge.sh:24` + `20-niri-desktop.sh:20` | 2 |
| 7 | **The FIDO2 no-lockout / CVE-2025-23013 PAM stack has zero automated test reach** — safety-critical, lockout-capable, correct today but unprotected against regression. | `lib/fido2.sh` | 4 |

*(Findings #1 and #2 funnel into the same boot-loop + lingering-NOPASSWD failure; #1 absorbs Phase 1's NOPASSWD finding as its security facet.)*

---

## Cross-cutting themes

1. **The first-boot resume is the reliability/security hot spot.** Warn-only preflight + success-gated cleanup + no retry bound + a missing WiFi-cred path combine into "stuck forever with passwordless root." One unit, biggest payoff.
2. **The convergent-update machinery trusts its own happy path.** A failed `git reset` (H#3), a hardcoded theme (H#4), and incomplete drift-input coverage (H#6) all let the updater *report success while diverging from the repo* — the opposite of its core promise. The mechanics (idempotent migrations, prune triple-guard, content-hashing) are otherwise sound.
3. **Two migrations were swept through code but not docs/comments.** archinstall→bedrock and greetd→SDDM left stale `archinstall/`/`greetd`/`bootstrap.sh`/`swww` references — mostly cosmetic, **except** the functional `firstboot-notice.sh` greetd check (Q-M2).
4. **Test coverage stops at the system boundary.** CI hard-gates the *pure-logic* units well (11 gates), but system-mutating + security-critical code (`fido2`, `health`, `detect-gpu`, `disk`, `fw_allow`, module bodies) is reachable only by a VM e2e that can't run in CI — which is *how* the firewall bug (P1-M4) reached `main`.
5. **Supply chain is trust-on-first-use, honestly documented.** CachyOS key-pinned (packages verified) but the bootstrap *script* and the `curl|sh` install are TLS+account trust; `SECURITY.md` states this accurately rather than overselling.

---

## Prioritized roadmap (grouped by theme)

### P0 — before any *unattended* or real-hardware first-boot install
- **Harden `archfrican-resume.service`** (closes H#1, H#2, P1-M1): set `Environment=ARCHFRICAN_STRICT_PREFLIGHT=1` so an unresolvable package fails *before* state changes; bound retries (`StartLimitIntervalSec`/`StartLimitBurst` or a boot counter); add `ExecStopPost=-… rm -f /etc/sudoers.d/99-archfrican-resume` so the NOPASSWD grant is dropped on failure (fail *closed*); carry iwd WiFi creds (or detect-and-warn instead of assuming wired DHCP).
- **Guard the niri-splice** (closes H#5 / SEC-07): assert exactly one well-formed `THEME-START`…`THEME-END` pair (anchored), back up before `mv`, skip+warn otherwise.

### P1 — near-term (weeks)
- **Make the updater fail honestly** (H#3, P2-M3): check `git reset --hard` exit status (never report stale as "current"); guard a dirty working tree before hard-reset (stash/warn).
- **Stop `40-theming` clobbering the theme** (H#4): read the staged `.archfrican-theme` (mirror `20-niri-desktop.sh:19`) or let the chezmoi `run_after` be the sole applier.
- **Complete drift-input coverage** (H#6, P2-M1/M2): hash `themes/*/colors.sh`, `bin/theme-switch` + its templates, and the GPU arg (or render authoritatively-unconditionally).
- **Fixture-unit-test the safety-critical pure-logic** (H#7, Q-M1): `fido2_pam_selfcheck`/`assert_version`, `detect_gpu`/`nvidia_tier`, `fw_allow` validation, `confirm_wipe`, `health` count-parsers — all VM-free.
- **Add `fw-allow` port-range validation + validate-before-persist** (P1-M4); harden the CachyOS download with `--retry`/`--max-time` + `sha256sum -c` (P1-M2, P3-M1).

### P2 — medium-term
- **Doc/comment sweep** for both migrations (Phase 4 + 5 cluster): fix the functional `firstboot-notice.sh` greetd check (Q-M2); rewrite `VALIDATION.md` off archinstall/`bootstrap.sh`/"six modules" (D-M1); move FIDO2-RECOVERY's LUKS row to 🚧 ROADMAP (D-M2); correct the README Layout (`archinstall/`, omitted libs/modules), the CI-gate count (7→11), the `sha256 pin`→GPG-fingerprint wording, and `swww`→`awww-daemon`.
- **SSOT & dead code:** dedupe `cpu_ucode` (Q-M4); delete `ui_spin`/`enable_user_service`/`faillock_recover_doc`/`ensure_git` (Q-L1).
- **Robustness LOWs:** validate `state-version` numeric + make `_mig_set` checked/atomic + sort migrations numerically (P2-L1/L2/L5); atomic color-file renders (P2-L4); validate/escape `LOCALE` before `sed` (P1-M3); add a weekly `schedule:` CI run for `pkg-resolution` (Q-M3).

---

## Condensed documentary reconciliation matrix

(Full version in [05-docs-vs-code.md](05-docs-vs-code.md).)

| Documented contract | Real state | Action |
|---|---|---|
| `SECURITY.md` guarantees (key-pin, ARMED=0, FIDO2 non-exclusive, root-disabled, nft-never-flush) | ✅ all uphold in code | none — honest |
| "system = the repo, applied" / convergent update | ✅ mechanics sound, **but** can silently run stale (H#3) / reset theme (H#4) / miss palette drift (H#6) | **fix code** |
| `VALIDATION.md`: "Phase 1 — `archinstall --config archinstall/user_config.json`" | archinstall replaced by `base-install.sh`; file doesn't exist | **fix doc** (D-M1) |
| `FIDO2-RECOVERY.md`: LUKS-unlock-by-key "what we verified" | no LUKS/FIDO2 code exists; doc self-contradicts | **fix doc → ROADMAP** (D-M2) |
| README Layout `archinstall/` dir; CI "7 gates"; `swww` | dir gone; 11 gates; `awww-daemon` | **fix doc** (LOW) |
| **Prior audit: 1 CRIT + 11 HIGH** | **~10 FIXED, 1 PARTIAL (SEC-02), 1 OPEN (SEC-07)** | **finish SEC-02/07** |

---

## Appendices
- **Phase-0 baseline, moving-target chronology, tools run, method & limitations:** [appendix-baseline.md](appendix-baseline.md).
- **Per-phase detail:** [01-security.md](01-security.md) · [02-state-integrity.md](02-state-integrity.md) · [03-reliability-robustness.md](03-reliability-robustness.md) · [04-quality-hygiene.md](04-quality-hygiene.md) · [05-docs-vs-code.md](05-docs-vs-code.md).
