# Appendix — Baseline (Phase 0) & Method / Limitations

## A. Reconnaissance baseline (Phase 0) — verified facts

All figures below were established read-only before Phase 1 and reproduced where possible.

| Item | Verified value |
|------|----------------|
| **Repo type** | **Not a git repository** locally → nothing is "versioned"; the `.gitignore` and bootstrap `git pull` are aspirational. (Affects the secret-versioning rule: a `.env`/credentials file can't be "leaked in history" because there is no history.) |
| **Stack** | Bash installer (**15 `.sh` files, ~347 lines**) + config: KDL (niri), TOML (starship), JSON/JSONC (archinstall, waybar), INI (fuzzel), CSS (waybar). Dotfiles via **chezmoi**. **No web app, no server, no database** → web/DB/ORM audit lenses N/A. |
| **File count** | `find archfrican -type f` = **42** — matches CONTEXT.md:80's "42 archivos" ✅ |
| **`bash -n`** | Passes on all 14 scripts — matches CONTEXT.md:81 ✅ |
| **`set -euo pipefail`** | Literally present only in `install.sh`, `bootstrap.sh`, `lib/common.sh`. **But** every module sources `common.sh` as its first line, and `set` **persists** from a sourced file → modules **do** run under errexit (verified empirically by the Phase-1 verifiers; this corrected a recon assumption). |
| **Module invocation** | `bash "modules/$1.sh"` ([install.sh:15](../../install.sh#L15)) — executed as subprocesses, not sourced. |
| **Duplication** | `install.sh`, `theme-switch`, `config.kdl`, `README.md` at the wrapper root are **byte-identical** to their `archfrican/` copies; `theme-switch` exists in **3 identical copies** (root, `bin/`, `home/dot_local/bin/`). |
| **Cruft** | `archfrican.zip` (29 KB, a byte-identical whole-repo snapshot) and `.DS_Store` (8 KB) at the wrapper root; `.gitignore` ignores only `archinstall/user_credentials.json` and `*.log`. |
| **Tests / CI** | **None.** No `.github/`, no `Makefile`, no test files. `bash -n` is the only validation. |
| **Secrets** | No hardcoded secrets anywhere; `archinstall/user_credentials.json` is gitignored (and not present). |
| **Structure** | Real project lives in `archfrican/`; the parent dir is `Archfrican`; docs say clone into `~/.archfrican` (three names). `docs/CONTEXT.md` and this `audit/` live in the wrapper, outside `archfrican/`. |

### Detected stack → which lenses applied
- **Applied** (system-installer lenses): supply chain / remote-code trust, privilege escalation &
  `/etc` writes, shell injection/unsafe expansion, **destructive disk ops** (archinstall), Btrfs
  snapshot/rollback correctness, idempotency & re-run safety, shell error-handling/robustness, hardware
  (GPU) detection, package correctness (official vs AUR), repo hygiene, tests/CI, docs↔code.
- **Dropped** (no applicable surface): AuthN/AuthZ, IDOR/BOLA, multi-tenant/RLS, XSS/CORS/CSRF/CSWSH,
  rate limiting, uploads, SQL/ORM/migrations, money-in-decimal, offline-sync, N+1, bundle-splitting,
  i18n. Stated explicitly in each phase so their absence is a deliberate scoping decision, not an
  oversight.

---

## B. Method

- **Per phase:** N parallel **finders** (one per lens) returned structured candidates
  `{title, severity, file, line, evidence, impact, recommendation, confidence}`; then an **adversarial
  verifier** per candidate attempted to **refute** it by re-reading the code. Only survivors entered the
  report; severities and quotes were corrected; duplicates were consolidated (one issue = one entry with
  cross-references).
- **Finder counts:** 4 (Phase 1), 4 (Phase 2), 3 (Phases 3-5) — scaled to a small repo.
- **Evidence discipline:** every finding cites `file:line` + a verbatim quote. Claims that couldn't be
  verified from the repo (systemd unit names, archinstall version behavior, package repo status, dbus
  availability during install) are marked **"a confirmar"** with the exact command to check.
- **Reproduced where possible:** `bash -n` (all pass), `find archfrican -type f | wc -l` (42),
  byte-identity of duplicates (`diff`/`shasum`), `grep -rn ghostty packages/ modules/` (absent), the
  inline-comment parser behavior (SEC-01), and the errexit-inheritance correction (empirically, by the
  verifiers).
- **Adversarial yield:** **13 of 151** candidates refuted (~8.6%), including an invented
  "AUR-package-breaks-the-batch", an invented GPU-agnostic "contract violation", a "polkit deprecated"
  claim that had read the wrong (duplicate) file, and several findings whose load-bearing premise
  ("modules lack `set -e`") was disproven.

---

## C. Limitations

1. **Static analysis only — no Arch hardware.** The installer was never executed; runtime claims about
   destructive disk operations, systemd activation, dbus/dconf availability, and snapshot/rollback
   behavior are reasoned from the code and marked "a confirmar". **The single most valuable next step is
   to run the install in a VM** and validate: the package install completes (post-SEC-01 fix), GPU
   detection, the rollback loop, and `theme-switch` from `~/.local/bin`.
2. **`shellcheck` / `shfmt` / `kdl` not available locally.** Shell quality was reviewed manually; running
   `shellcheck` is a recommendation (QUAL-02), not something performed here. `jq` was available and used.
3. **Not a git repo.** No history to inspect for leaked-secret-in-history analysis; the
   versioning/`.gitignore`/`git pull` concerns are assessed against the intended (future) git workflow.
4. **Package & systemd-unit & version facts may be stale.** Per the audit's own rules, no package was
   asserted "missing/AUR/deprecated" or any CVE attributed without high confidence; uncertain ones are
   "a confirmar" against `pacman -Ss` / `paru -Ss` / `<pkg-manager> audit` on a live Arch system. Knowledge
   cutoff and rolling-repo drift mean these should be re-checked on target.
5. **niri 26.04 blur syntax** could not be verified against release notes from the repo alone; the
   DOC-03 finding rests on the *config not enabling any blur directive*, which is repo-verifiable
   regardless of the exact syntax.

---

## D. How to reproduce the headline checks

```bash
cd archfrican
bash -n install.sh bootstrap.sh lib/*.sh modules/*.sh bin/theme-switch   # all pass (syntax)
find . -type f | wc -l                                                   # 42
grep -rn -i ghostty packages/ modules/                                   # (empty) — never installed
grep -vE '^\s*(#|$)' packages/base.txt | sed -n '11p'                    # shows an inline comment survives → SEC-01
# Recommended on a real Arch box / VM:
shellcheck install.sh bootstrap.sh lib/*.sh modules/*.sh bin/theme-switch
pacman -Sp --print-format '%n' $(grep -hvE '^\s*(#|$)' packages/{base,dev,niri-desktop,theming}.txt | sed 's/#.*//')
```
