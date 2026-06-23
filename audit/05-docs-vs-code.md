# Phase 5 — Docs ↔ Code Consistency + Prior-Audit Reconciliation

**Scope:** every doc claim cross-checked against code (both sides cited), split into **TYPE A** (a contract promised in docs that doesn't exist → dangerous) vs **TYPE B** (stale/wrong name/count → confusing). Plus the **full reconciliation** of the prior `docs/audit/` against current code — the user's explicit "verify the previous audit" mandate.
**Method:** 5 finder lenses → adversarial verifier citing both `doc:line` and `code:line`. **Frozen at committed HEAD `2a3f9b5`** (dirty files read via `git show 2a3f9b5:…`; the 6 uncommitted WIP scripts out of scope).

## Verdict for this phase

**The docs are largely honest, and the project substantially acted on its prior audit.** `SECURITY.md`'s every guarantee **holds in code** (key-pin with an honest "no tarball signature" caveat, ARMED=0 + CI-enforced, FIDO2 non-exclusive + CVE guard, root-disabled, nftables-never-flush) — **no security-contract drift**. The prior audit's **1 CRITICAL + ~10 of 11 HIGHs are FIXED**; only **SEC-02 (partial)** and **SEC-07 (open)** remain, and a large set of prior doc errors (envsubst, "20-niri", "VS Code", keyd-7, blur, live-reload) are corrected. The residual drift is concentrated and explainable: the project ran **two migrations** (archinstall→bedrock `base-install.sh`, greetd→SDDM) and **swept the code but not all the docs/comments** — leaving stale `archinstall/`/`greetd` references and a **stale `VALIDATION.md`**. One doc (`FIDO2-RECOVERY.md`) **overstates an unimplemented LUKS-by-key feature**.

### Candidate accounting

| | Count |
|---|---|
| Candidates raised | 33 |
| Survived verification | 32 |
| Refuted | 1 |
| — of survivors: **FIXED-prior confirmations (INFO)** | 8 |
| — cross-phase duplicates (greetd firstboot/desc → Phase 4) | 3 |
| **Distinct NEW doc-drift findings** | ~12 (2 MEDIUM, ~8 LOW, 2 INFO) |
| **Prior-audit items reconciled** | 1 CRIT + 11 HIGH + DOC set |

---

## MEDIUM (new doc drift)

### D-M1 — `docs/VALIDATION.md` instructs a base-install procedure that no longer exists
- **Doc:** `docs/VALIDATION.md:37-41` · **Code:** `lib/base-install.sh:1-5` (no `archinstall/`); also `:28` references a non-existent `bootstrap.sh`
- **Severity:** MEDIUM *(one finder rated HIGH; verifier settled MEDIUM — fails loudly, no data loss)* · **Confidence:** high
- **Evidence:** the guide's Phase 1 says verbatim:
  ```
  ## 1. Phase 1 — base install (archinstall)
  archinstall --config archinstall/user_config.json
  ```
  But `base-install.sh` **replaced** archinstall ("Bedrock Arch base installer — replaces the archinstall dependency … NO version-unstable JSON schema"), and there is **no `archinstall/user_config.json`** in the repo. The same doc lints `bash -n bootstrap.sh` (`:28,30`) — `bootstrap.sh` doesn't exist (bootstrap is a function inside `install.sh`). It also says the install proceeds through "all **six** modules" (`:72,204`) — there are **nine** (`00-base`…`70-hygiene`).
- **Impact:** TYPE A-leaning — someone validating the installer (the doc's whole purpose) would run a command and reference files that don't exist, and validate against the wrong (archinstall-era) model. Fails loudly rather than causing data loss, hence MEDIUM.
- **Recommendation:** rewrite VALIDATION.md's Phase-1 section around `install.sh` on the ISO (`lib/base-install.sh`, dry-run-gated) or the documented base-Arch one-liner; drop the `archinstall/user_config.json` + `bootstrap.sh` references; fix "six modules" → the current set.

### D-M2 — `FIDO2-RECOVERY.md` lists LUKS-unlock-by-key under "what we verified", but no LUKS/FIDO2 code exists (and the doc contradicts itself)
- **Doc:** `docs/FIDO2-RECOVERY.md:32` (under the `:24` heading "## The no-lockout guarantee (what we verified)") vs the `:66-71` "Deferred … not shipped" section · **Code:** `lib/fido2.sh` (PAM-only), `lib/base-install.sh:68-79` (`base_luks` = single passphrase)
- **Severity:** MEDIUM *(finder said HIGH; verifier lowered — conservative/no-lockout direction)* · **Confidence:** high
- **Evidence:** the "what we verified" table row reads: *"| LUKS (P1, opt-in) | Key unlocks the disk **and** the original passphrase still works (slot 0 is re-asserted) |"*. But repo-wide there is **no `systemd-cryptenroll` / `--fido2` / LUKS-slot enrollment** — `fido2.sh` only touches PAM (`/etc/u2f_mappings`, services `sudo system-local-login sddm`), and `base_luks` formats with a single passphrase and "re-asserts" no slot. The doc's **own** "Deferred (not shipped)" section then says LUKS-unlock-by-key *isn't* shipped — an internal contradiction.
- **Impact:** a user could form a false mental model that touching their key unlocks the encrypted disk — then be surprised at the LUKS prompt. **Not** a lockout (the passphrase always works), so MEDIUM not HIGH; but a "what we verified" guarantee that has zero implementing code is exactly the TYPE-A trust hazard this phase exists to catch.
- **Recommendation:** move the LUKS row out of "what we verified" into "Deferred / 🚧 ROADMAP" (consistent with the doc's own `:69-71`), or implement `systemd-cryptenroll`-based LUKS-FIDO2.

---

## LOW (consolidated doc drift)

| # | Finding | Doc → Code |
|---|---------|-----------|
| **D-L1** | **README Layout diagram is stale** — lists an `archinstall/` directory that doesn't exist; the `lib/` one-liner omits the most load-bearing libs (`base-install`, `converge`, `manifest`, `migrate`); the `modules/` list omits `70-hygiene`. | `README.md` Layout block (`:111-113`) → no `archinstall/` at `2a3f9b5`; `lib/`+`modules/` contents |
| **D-L2** | **CI-gate count understated** — `CONTRIBUTING.md`/`GOVERNANCE.md` list **7** CI gates; `ci.yml` has **11** (omits `cachyos-trust`, `migrations-idempotent`, `prune-safety`, `sddm-theme`). Undersells the safety net. | `CONTRIBUTING.md`/`GOVERNANCE.md` → `ci.yml` (11 jobs) |
| **D-L3** | **`GOVERNANCE.md` mischaracterizes the supply-chain anchor as a "sha256 pin"** — the code pins a **GPG key fingerprint** (`882DCFE4…`), not a sha256. (SECURITY.md gets this right.) | `GOVERNANCE.md` → `00-base.sh:17-22` |
| **D-L4** | **`CONTEXT.md` stale** — architecture tree lists an `archinstall/ user_config.json` dir (doesn't exist) and an outdated 6-module tree; peripherals table names the wallpaper daemon **`swww`**, but the code installs/spawns **`awww-daemon`** (`verify_spawns` would `die` on `swww`). | `CONTEXT.md` → repo tree; `niri` config / `verify_spawns` |
| **D-L5** | **`VALIDATION.md` lints a non-existent `bootstrap.sh`** (folded into D-M1's evidence; listed for the count). | `VALIDATION.md:28,30` → no `bootstrap.sh` |
| **D-L6** | **`FIDO2-RECOVERY.md:67` "Deferred" note describes a `greetd`/`tuigreet` graphical-login key leg** that no longer applies (login is SDDM; the key leg now covers `sddm`, per the doc's own `:22`). | `FIDO2-RECOVERY.md:67` → `fido2.sh` (`sddm`, not greetd) |

## INFO

- **D-I1** — `CONTEXT.md` calls the project a skeleton of **"42 archivos"**; the repo has **110** tracked files. Count drift (the prior audit's appendix also used "42 files"/"~347 lines").
- **D-I2** — leftover `greetd` references in **code comments/strings** (`phase2.sh:27` module description shown to the user; `common.sh:45` comment) — **already filed as Phase 4 Q-L2 / Q-M2**; noted here for the docs↔code convergence (see below).

---

## Refuted / Discarded (1 of 33)

| Claim | Why refuted |
|---|---|
| **README Caveats warns about "archinstall's JSON schema" but the project no longer uses archinstall** | Correct usage, not drift — the README's `archinstall` here refers to the **external Arch tool** the user runs to lay down base Arch before the one-liner (the documented install path), not Archfrican's removed internal dir. Leave as-is. *(Distinguish from D-L1's `archinstall/` **directory** reference, which IS stale.)* |

---

## ★ Prior-Audit Reconciliation Matrix (the "verify the previa" deliverable)

Prior audit (`docs/audit/`, ~mid-2026): **1 CRITICAL, 11 HIGH, 25 MED, 26 LOW, 30 INFO**. Status of the CRITICAL + HIGH + key DOC items at current HEAD `2a3f9b5`:

| Prior ID | Sev | Status | Current evidence |
|---|:---:|:---:|---|
| **SEC-01** package parser keeps inline comments → every install aborts | CRIT | ✅ **FIXED** | `common.sh:113` `${__rpl_line%%#*}` strips inline+whole-line; CI `pkg-resolution` gate |
| **DATA-02** rollback uses wrong unit `grub-btrfs.path` + snapper collision | HIGH | ✅ **FIXED** | `50-snapshots.sh:46` `grub-btrfsd.service`; ArchWiki `@.snapshots` procedure + post-condition `die` (`:53-57`) |
| **SEC-02** CachyOS bootstrap = unverified root code execution | HIGH | ⚠ **PARTIAL** | key pinned+lsigned (`00-base.sh:17-22`) → *packages* verified; the **bootstrap script itself still unverified** → **Phase 1 M2** |
| **DATA-01/QUAL-03/DOC-02/06** deployed theme-switch dead / 3 copies / false "tested" | HIGH | ✅ **FIXED** | `theme-switch:8` `ROOT=…/.archfrican`; CI `theme-switch-smoke`. *(New, separate bug: `40-theming` hardcodes the theme → Phase 2 H2.)* |
| **#5 / QUAL-01 / DOC-01** Ghostty installed by nothing | HIGH | ✅ **FIXED** | `packages/niri-desktop.txt:3` `ghostty`; `verify_spawns` gate |
| **REL-01** GPU detection aborts on no-VGA/missing lspci | HIGH | ✅ **FIXED** | `detect-gpu.sh:8` guard + `:10` `|| true` + PCI-id match |
| **REL-02** `rustup default stable` lacks `|| true` → halts install | HIGH | ✅ **FIXED** | `30-dev.sh:9` `best_effort rustup default stable` |
| **REL-03** no trap/rollback/resume guidance | HIGH | ✅ **FIXED** | `phase2.sh:9-17` `on_err`; `firstboot-notice.sh` on-screen |
| **REL-04** macOS GTK look not applied (TTY gsettings masked) | HIGH | ✅ **FIXED** | chezmoi `gtk-3.0/4.0/settings.ini` (session-bus-independent) + `40-theming` `attempt` (loud, not masked) |
| **QUAL-02** no tests, no CI | HIGH | ✅ **FIXED** | **11 hard-gate CI jobs** (`shfmt` still absent → Phase 4) |
| **SEC-07** theme-switch niri splice truncates config on missing `THEME-END` | (P1) | ❌ **STILL-OPEN** | `theme-switch:45-49` unchanged → **Phase 2 H3** |
| **DOC-03** niri blur falsely claimed enabled | INFO | ✅ **FIXED** | `config.kdl.tmpl:45` blur commented (opt-in); README says "(opt-in)" |
| **DOC-04** "live across 6 apps" oversold | — | ✅ **FIXED** | README now specifies live (waybar/mako/niri/GTK) vs deferred (ghostty/fuzzel) |
| **DOC-B set** envsubst→sed · 20-niri→20-niri-desktop · VS Code→Code-OSS · keyd 7→13 | — | ✅ **FIXED** | README "pure-sed", "20-niri-desktop", "Code-OSS", 13-letter keyd list |

**Reconciliation summary:** of the prior **1 CRIT + 11 HIGH**, **~10 FIXED**, **1 PARTIAL** (SEC-02 — the residual is Phase 1 M2), **1 STILL-OPEN** (SEC-07 = Phase 2 H3). The prior audit's entire DOC-error set is corrected. **The project demonstrably used its prior audit** — a strong process signal.

---

## Cross-cutting: the two migrations were swept through code but not docs/comments

Both `D-M1`/`D-L1`/`D-L4` (archinstall→bedrock) and `D-I2`/`D-L6` + **Phase 4 Q-M2/Q-L2** (greetd→SDDM) are the **same shape**: a real migration applied to the executable path but not to the surrounding docs, comments, and user-facing strings. A single sweep for `archinstall`/`greetd`/`tuigreet`/`bootstrap.sh`/`swww` across `docs/` + comments would close most of Phase 5's LOWs and the Phase 4 comment-drift cluster at once — and the **firstboot-notice greetd bug (Q-M2) is the one place that drift is *functional*, not cosmetic.**

---

*Next: Phase 6 — Executive synthesis (`audit/00-executive-summary.md` + `appendix-baseline.md`): cross-phase convergence, full CRITICAL/HIGH list, P0/P1/P2 roadmap, and the method/limitations note.*
