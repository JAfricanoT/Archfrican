# Phase 4 — Quality, Deprecations, Packages & Hygiene

**Scope:** code quality, package correctness, deprecations, repo hygiene, tests/CI, and architecture.
(TypeScript-strictness/i18n lenses don't apply — this is Bash + config.)

**Method:** 3 parallel finders → 1 adversarial verifier per candidate. **28 candidates → 26 survived,
2 refuted.** Many survivors overlap Phases 1-3 and are **cross-referenced, not re-counted**. The 2
refutations are exactly the *don't-invent-a-fact* discipline (an AUR package claim and a "deprecated"
claim that couldn't be verified without `pacman`).

> Tooling note: `shellcheck`/`shfmt` are **not installed locally**, so this phase reasons about shell
> quality manually and **recommends** running them — it does not claim to have linted. Package
> official-vs-AUR status is marked **"a confirmar with `pacman -Ss`"** wherever not certain (Rule #5).

---

## Severity summary (this phase, deduplicated)

| Severity | Count | Items |
|----------|-------|-------|
| CRÍTICO  | 0 | — |
| ALTO     | 2 | QUAL-01, QUAL-02 |
| MEDIO    | 2 | QUAL-03, QUAL-04 |
| BAJO     | 4 (clustered) | QUAL-05 … QUAL-08 |
| INFO     | 2 (positive) | QUAL-09, QUAL-10 |

Refuted: **2**. Cross-references: SEC-06/SEC-19 (Phase 1), DATA-04/DATA-07 (Phase 2), REL-02 (Phase 3).

---

## ALTO

### QUAL-01 — Ghostty (the documented, bound, themed terminal) is in no package list or module → never installed
- **File:** absent from [packages/niri-desktop.txt](../../packages/niri-desktop.txt); referenced at [config.kdl:64](../../home/dot_config/niri/config.kdl#L64), [README.md:34](../../README.md#L34), [ghostty/config:1](../../home/dot_config/ghostty/config#L1), [theme-switch:26](../../bin/theme-switch#L26) · confidence: alta (defect) / media (exact repo — a confirmar)
- **Evidence:** `config.kdl:64` `Mod+Return        { spawn "ghostty"; }`; `README.md:34` documents Ghostty
  as **the** terminal; theme-switch even `render ghostty.colors "$CFG/ghostty/colors"`. Yet
  `grep -i ghostty packages/*.txt modules/` returns **nothing**.
- **Impact:** On a fresh install the **primary terminal is never installed** — `Mod+Return` (the most-used
  keybind) silently does nothing and the desktop ships with no terminal launcher, while the ghostty
  dotfile and theme renderer target a binary that doesn't exist. This is the package-completeness facet
  of a defect that also spans config and docs (**Phase 5**).
- **Recommendation:** Add `ghostty` to a package list — **a confirmar with `pacman -Ss ghostty`**: if it
  resolves in `extra`/official, add to `niri-desktop.txt` (pacman-installable); if only `paru -Ss` finds
  it (AUR), add to `aur.txt`. Either way the spawn bind / dotfile / renderer are currently dead.

### QUAL-02 — No tests and no CI on a "reliability-first" installer; the only check is `bash -n`
- **File:** repo-wide (no `.github/`, no `Makefile`, no test files); claims at [CONTEXT.md:81-82](../CONTEXT.md), [README.md:5](../../README.md#L5) · confidence: alta
- **Evidence:** A find for tests/CI returns nothing. The only validation is `bash -n` ("Todos los
  scripts pasan bash -n", CONTEXT.md:81) — which is **parse-only**: it executes nothing, so it catches
  **none** of the Phase 1-3 bugs (the SEC-01 inline-comment parser, the REL-01/REL-02 errexit aborts, an
  AUR package in a `pacman -S` list, the deployed-theme-switch `ROOT` break, …).
- **Impact:** The single loudest design principle ("nothing explodes") has **zero automated
  enforcement**. Every reliability claim — theme-switch idempotency, scripts not aborting, package lists
  installable — rests on manual memory, and regressions only surface on real hardware mid-install (the
  worst possible place for this class of tool).
- **Recommendation:** Add a minimal CI/Makefile pipeline that would have caught real findings here:
  (1) **`shellcheck`** over `install.sh`/`bootstrap.sh`/`lib/*.sh`/`modules/*.sh`/`bin/theme-switch`
  (catches quoting/masking issues `bash -n` misses); (2) **`shfmt -d`** formatting; (3) a **theme-switch
  idempotency smoke test** in a container (HOME=tmp, seed a `config.kdl` with markers, apply all 4 themes
  **twice**, assert run-2 output == run-1 and no literal `${VAR}` survives); (4) a **package-name
  existence check** (`pacman -Sp --print-format '%n' $(grep -v '^#' packages/*.txt)` on an Arch image) to
  catch SEC-01 and any AUR-in-pacman-list entry.

---

## MEDIO

### QUAL-03 — `theme-switch` exists in THREE identical copies; its documented idempotency is asserted in prose, not tested
- **Files:** [bin/theme-switch](../../bin/theme-switch), [home/dot_local/bin/theme-switch](../../home/dot_local/bin/theme-switch), and the wrapper-root [theme-switch](theme-switch) — all `sha256 54d9cf88…` · confidence: alta · extends **DATA-04**
- **Impact:** No single source of truth: the installer runs the in-repo copy ([40-theming.sh:18](../../modules/40-theming.sh#L18)) while the user runs the chezmoi-deployed `~/.local/bin` copy. A fix to one (e.g. the DATA-01 `ROOT` break, the dead-var cleanup, any sed/awk change) won't reach the others → the installer can apply a *different* switcher than the user later invokes. Compounding: CONTEXT.md:82 claims it's "probado funcionando y idempotente", but the idempotency-sensitive logic (the niri awk splice, the fuzzel `=#` strip) has **no encoded test**, despite being the one component trivially runnable off-target (pure sed/awk against `$HOME`).
- **Recommendation:** One canonical source (keep `bin/theme-switch`; make the chezmoi copy a symlink/template). Add the idempotency smoke test from QUAL-02 — it directly encodes the CONTEXT.md:82 claim.

### QUAL-04 — The `VARS` array is a hand-maintained triple-duplicate (colors.sh ↔ `VARS` ↔ template tokens) with a silent reverse-drift hazard
- **File:** [bin/theme-switch:14-15](../../bin/theme-switch#L14-L15) (and the identical copy in `home/dot_local/bin`) · confidence: alta
- **Evidence:** `VARS=(BG BG_ALT … ACCENT2 … ORANGE … BORDER_INACTIVE)`. `render()` only substitutes
  names in `VARS`, which must be kept in sync **by hand** with (a) the exports in all 4 `colors.sh` and
  (b) the `${…}` tokens in `templates/*`.
- **Impact:** Drift already happened (ACCENT2/ORANGE are in `VARS` but used by no template — see QUAL-06).
  The **reverse** failure is worse: add a new `${NEW}` token to a template but forget to add `NEW` to
  `VARS`, and `render` silently leaves the literal `${NEW}` in the generated config **with no error**.
  This duplication spans `VARS` (×2 copies) + 4 palettes + the templates.
- **Recommendation:** Derive `VARS` programmatically (e.g. `compgen -A export` after sourcing the palette,
  or grep the template tokens) for a single source of truth; add a guard that **fails loudly** if any
  `${…}` token survives rendering.

### (Cross-ref, not re-counted) `rustup default stable` missing `|| true`
- [30-dev.sh:9-10](../../modules/30-dev.sh#L9-L10) — the asymmetric error handling that can abort the
  whole install. Fully covered as **REL-02** (Phase 3); surfaced again here under the shell-quality lens.

---

## BAJO (clustered)

### QUAL-05 — Repo hygiene & packaging cluster
- **`archfrican.zip`** ([wrapper root](archfrican.zip), 29 KB) — a **byte-identical whole-repo snapshot** committed
  beside the source (verified: zipped `install.sh` hash == live hash). Guaranteed to drift; would
  resurrect old code if ever extracted. *Delete; add `*.zip` to `.gitignore`; generate releases from a
  tag via `git archive` if needed.*
- **`.DS_Store`** ([wrapper root](.DS_Store), 8 KB) — macOS cruft, **not** ignored. *Add `.DS_Store` to
  `.gitignore` (ideally a global `~/.gitignore_global`).*
- **4 byte-identical root duplicates** — [install.sh](install.sh), [README.md](../../README.md),
  [config.kdl](config.kdl), [theme-switch](theme-switch) at the wrapper root mirror their `archfrican/`
  copies (and have already begun to drift at the **permission** level — the root copies are non-exec).
  Read by nothing; pure confusion. *Delete; treat `archfrican/` as the one repo.*
- **`.gitignore` is minimal** — [archfrican/.gitignore](../../.gitignore) ignores only
  `archinstall/user_credentials.json` and `*.log`; misses `.DS_Store`, `*.zip`.
- **Naming/structure mismatch** — wrapper dir `Archfrican`, project `archfrican`, clone target `~/.archfrican`
  ([README.md:51](../../README.md#L51)), plus README:7 "Archfrican is a placeholder name". Three names for one
  thing, and the publishable repo is a **subdirectory**. *Make `archfrican/` a standalone repo; resolve the
  placeholder name once so repo dir / GitHub repo / clone target agree.*
- *(Note: this is **not** a git repo yet — once it becomes one, these matter for what gets published.)*

### QUAL-06 — Dead code & unused dependencies cluster
- **`ACCENT2`, `ORANGE`** — defined in all 4 `colors.sh` and listed in `VARS` (×2) but referenced by
  **zero** templates (token set is `BG BG_ALT BG_DIM FG FG_DIM ACCENT RED GREEN YELLOW BLUE MAGENTA CYAN
  BORDER_ACTIVE BORDER_INACTIVE`). [colors.sh:6-7](../../themes/macos-dark/colors.sh#L6-L7).
- **`THEME_NAME`** — exported in all 4 `colors.sh` ([:2](../../themes/macos-dark/colors.sh#L2)) but
  **never read** (theme-switch persists its own `$THEME` arg, not `$THEME_NAME`). Even more orphaned than
  ACCENT2/ORANGE (not even in `VARS`).
- **`inter-font`** — installed ([theming.txt:3](../../packages/theming.txt#L3)) but **referenced by no
  config** (every UI surface uses "SF Pro Display"/"SF Mono"). Dead weight — *or* a missing fallback: the
  comment says "SF-Pro-like UI font" but no config lists `Inter` as a fallback family. *Either wire it in
  as the documented fallback (`"SF Pro Display","Inter",…`) or drop it.*
- **`code-flags.conf.d`** — [30-dev.sh:18](../../modules/30-dev.sh#L18) `mkdir`s a `.conf.d` directory
  that is never written to (the flags go to the flat `code-flags.conf`); not a recognized Code-OSS
  drop-in. Stray empty dir = copy-paste artifact. (= **DATA-07**.) *Delete line 18.*

### QUAL-07 — `code` is Code-OSS, but docs call it "VS Code"
- [dev.txt:2](../../packages/dev.txt#L2) installs `code` = **Code - OSS** (telemetry-free open build,
  Open VSX), **not** Microsoft's proprietary VS Code (`visual-studio-code-bin`, AUR). The dev.txt comment
  is self-aware ("OSS build") but [README.md:35](../../README.md#L35) and [30-dev.sh:17](../../modules/30-dev.sh#L17)
  just say "VS Code". MS-Marketplace-only extensions (Pylance, ms-vscode.cpptools, Remote-SSH, Live Share)
  are unavailable on Code-OSS. *Pick one and make docs match.* (Also **Phase 5**.)

### QUAL-08 — Shell style & consistency cluster
- **Inconsistent intra-repo sourcing** — `install.sh` uses bare relative `source lib/common.sh` (relying
  on its `cd`), modules use `$(dirname "$0")/../lib/…`, but [10-gpu.sh:4](../../modules/10-gpu.sh#L4)
  uses `$REPO_ROOT/…`. Three idioms for "find a sibling". *Standardize on `REPO_ROOT` (already exported,
  BASH_SOURCE-based, robust).* (Note: re-sourcing `detect-gpu.sh` in 10-gpu is **correct**, not redundant
  — modules are subprocesses and only inherit exported vars, not functions.)
- **`run_module` passes an empty positional** — [install.sh:15](../../install.sh#L15)
  `bash "modules/$1.sh" "${2:-}"` hands every module a literal `""`. Harmless (only 10-gpu reads `$1`).
  *Use `"${@:2}"` for a clean empty arg list.*
- **Heredoc quoting inconsistency** — greetd uses unquoted `<<TOML` ([20-niri-desktop.sh:10](../../modules/20-niri-desktop.sh#L10))
  while keyd/code-flags use `<<'…'`. Latent footgun. (= **SEC-19**.) *Quote all static-config delimiters.*
- **`pac_install_file` uses a global `_p`** ([common.sh:34](../../lib/common.sh#L34)) instead of
  `local` — style nit (overwritten each call, no real leak). Pair with the REL-12 readability/empty-list
  guard.
- **Lone, never-run lint directive** — the SC1090 `# shellcheck disable` ([theme-switch:10](../../bin/theme-switch#L10))
  is justified, but it's the only lint signal in a codebase that has no evidence of ever being linted.
- **`render` sed-escaping fragility** — [theme-switch:19](../../bin/theme-switch#L19) (= **SEC-06**).

---

## INFO — positive findings

- **QUAL-09 ✅ Module isolation VERIFIED.** `grep -rn niri modules/` outside `20-niri-desktop.sh` returns
  exactly two hits — a `warn` string ([10-gpu.sh:33](../../modules/10-gpu.sh#L33)) and a comment
  ([30-dev.sh:17](../../modules/30-dev.sh#L17)) — **not** coupling. The README's "niri lives in exactly
  one module + its dotfiles; swap one module + one package list" promise genuinely **holds** (niri is also
  referenced in `waybar/config.jsonc` and the switcher, which the "+ its dotfiles" clause covers).
- **QUAL-10 ✅ `REPO_ROOT` is a clean single source of truth** ([common.sh:40-41](../../lib/common.sh#L40-L41),
  BASH_SOURCE-based) and all 6 modules use it consistently. Package install **ordering** is also correct
  (CachyOS repo enabled before `linux-cachyos`; paru built before any `aur_install`).

*(Meta-note: `audit/` and `docs/CONTEXT.md` live in the wrapper dir, outside `archfrican/` — confirm intended
placement before publishing; `archfrican/docs/` doesn't exist and the README Layout lists neither.)*

---

## Refuted / Discarded (2) — transparency

| Candidate | Orig. sev. | Why refuted |
|-----------|-----------|-------------|
| "An AUR-only entry in `niri-desktop.txt` fails the whole `pacman` batch — several entries need re-confirming" | MEDIO | The **mechanism** is real (pacman is all-or-nothing under errexit), but **no specific entry could be confirmed AUR-only** without `pacman` access — asserting one would be an invented fact. Kept as a **recommendation** (the QUAL-02 package-existence CI check), not a finding. |
| "`polkit-gnome` is the deprecated/legacy polkit agent; auth prompts won't appear" | BAJO | **False on the substantive claim:** [config.kdl:58](../../home/dot_config/niri/config.kdl#L58) has `spawn-at-startup "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"` — the agent **is** autostarted (the candidate looked at the wrong duplicate file). "Deprecated" is also unverifiable without `pacman`. |

---

## Cross-cutting note for later phases
- **QUAL-01 (ghostty)** and **QUAL-07 (Code-OSS vs "VS Code")** are also **Phase-5 docs↔code** items.
- **Convergence reinforced:** `bin/theme-switch` now spans **Phases 1-4** (SEC-06/07/15, DATA-01/03/04,
  REL-09, QUAL-03/04 + dead vars) — unambiguously the highest-ROI file to fix.
- The strongest *new* Phase-4 message is **QUAL-02**: a reliability-first installer with **no automated
  test catches none of the bugs this audit found** — a single shellcheck + theme-switch-smoke CI job
  would have surfaced a large fraction of Phases 1-3.
