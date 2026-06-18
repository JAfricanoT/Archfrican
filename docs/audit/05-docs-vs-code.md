# Phase 5 — Documentation ↔ Code Consistency

**Scope:** every claim in `README.md` and `docs/CONTEXT.md` cross-checked against the real code, citing
**both** sides. Each item is **(A)** a *contract promised but absent* (dangerous — someone builds on a
capability/guarantee that doesn't exist) or **(B)** a *stale/obsolete doc* (names/versions/counts —
confusing, not load-bearing). Web lenses (ports, env vars, error contract, rate limiting, pagination,
sync model, roles) **do not apply** (no server/API/DB).

**Method:** 3 parallel finders → 1 adversarial verifier per candidate. **33 candidates → 32 survived,
1 refuted.** Notably **14 survivors are positive matches** — recorded below as a reconciliation matrix,
because showing what the docs get *right* is what makes the mismatches credible. Items overlapping
earlier phases are cross-referenced.

---

## Severity summary (this phase, deduplicated)

| Severity | Count | Type |
|----------|-------|------|
| ALTO     | 2 | A (contract absent) — DOC-01, DOC-02 |
| MEDIO    | 4 | A — DOC-03 … DOC-06 |
| BAJO     | 6 | B (stale doc) — DOC-07 … DOC-12 |
| INFO     | 13 | positive matches (reconciliation matrix) |

Refuted: **1**. Cross-references: QUAL-01/QUAL-05/QUAL-07, DATA-01/DATA-03, REL-05/REL-09.

---

## ALTO — promised contracts that are absent

### DOC-01 — Ghostty is documented as THE terminal (and bound to `Mod+Return`) but installed by nothing
- **Doc:** [README.md:34](../../README.md#L34) `| Terminal | **Ghostty** (Kitty graphics protocol, blur, native Wayland) |`; [CONTEXT.md:38](../CONTEXT.md). **Code:** [config.kdl:64](../../home/dot_config/niri/config.kdl#L64) `Mod+Return { spawn "ghostty"; }` — but `grep -rn ghostty packages/ modules/` returns **nothing**. · type A · alta · cross-ref **QUAL-01**
- **Impact:** Both docs name Ghostty as the headline terminal and a full ghostty dotfile ships, yet the
  binary is in no package list or module. After a full install, `Mod+Return` (the primary "open a
  terminal" action) silently does nothing — the documented default terminal **does not exist** on the
  installed system. Anyone relying on the doc contract has no terminal at all.
- **Recommendation:** Add `ghostty` to a package list (a confirmar `pacman -Ss ghostty`), or change the
  docs to state the terminal isn't provisioned. Don't leave a load-bearing keybind pointing at an
  uninstalled binary.

### DOC-02 — CONTEXT claims theme-switch is "probado funcionando e idempotente" — but only the repo copy was tested; the deployed copy is broken
- **Doc:** [CONTEXT.md:82-83](../CONTEXT.md) "`theme-switch` **probado funcionando** y **idempotente**". **Code:** [theme-switch:6](../../bin/theme-switch#L6) `ROOT="$(cd "$(dirname "$0")/.." && pwd)"` — the **deployed** `~/.local/bin/theme-switch` resolves `ROOT` to `~/.local`, where no `themes/`/`templates/` exist. · type A · alta · cross-ref **DATA-01**
- **Impact:** The "tested working" claim was validated against the **repo** copy (which happens to sit
  beside `themes/`), not the copy users actually run from `~/.local/bin`. On a real install the deployed
  switcher dies at line 9 (`no such theme`). The doc's "probado funcionando" gives **false assurance**
  that the shipped artifact works.
- **Recommendation:** State that only the repo-relative copy was tested; fix the deployed copy to locate
  data via an absolute install path; re-test the `~/.local/bin` copy before re-asserting the claim.

---

## MEDIO — promised features that silently don't work / overstated guarantees

### DOC-03 — niri "blur / frosted glass" is promised by both docs, the config enables none, and the inline comment lies about it
- **Doc:** [README.md:37](../../README.md#L37) "niri blur"; [CONTEXT.md:44](../CONTEXT.md) "blur nativo de niri 26.04 (efecto vidrio)"; CONTEXT.md:105. **Code:** [config.kdl:39-44](../../home/dot_config/niri/config.kdl#L39-L44) — comment says `// layer-rule / window blur is enabled per-rule below`, but the `window-rule` sets **only** `geometry-corner-radius 10` + `clip-to-geometry true`; **no `blur` directive, no `layer-rule`.** · type A · alta · **personally verified**
- **Impact:** The signature "frosted glass" macOS look — sold as a core aesthetic in both docs — is
  **never enabled**. Worse, the code comment at config.kdl:40 actively asserts blur "is enabled per-rule
  below" when it is not, so a maintainer reading the config believes the feature is wired and won't add
  it. Double mismatch: doc promises the capability **and** the comment claims it's implemented. (Ghostty
  also sets `background-blur = true` in its config — but ghostty isn't installed (DOC-01), so even
  terminal-level blur won't render.) niri 26.04 blur syntax: a confirmar against release notes.
- **Recommendation:** Add the real niri blur directive/`layer-rule` (verify against niri 26.04), or
  remove the blur claims and **fix the misleading comment**. Don't ship a comment that contradicts the
  code beneath it.

### DOC-04 — "Switching is live (…ghostty…) — no logout" overstates live-reload
- **Doc:** [README.md:65](../../README.md#L65) "Switching is live (waybar, mako, fuzzel, ghostty, niri borders, GTK) — no logout." **Code:** [theme-switch:47-49](../../bin/theme-switch#L47-L49) signals **only** waybar (`SIGUSR2`) and mako (`makoctl reload`). · type A · alta · cross-ref **REL-09**
- **Impact:** The doc lists six live targets; the code reloads two. After `theme-switch tokyo-night`,
  open **ghostty** terminals keep the old palette until restarted (fuzzel is next-launch). The "live"
  contract names the most visible offender (ghostty) as if it were covered.
- **Recommendation:** Trim README.md:65 to what is actually live (waybar, mako, niri borders, GTK), and
  mark ghostty/fuzzel as "applies to new windows/launches".

### DOC-05 — "Idempotent: safe to re-run any time" is overstated
- **Doc:** [install.sh:4](../../install.sh#L4), [README.md:54](../../README.md#L54), README.md:82. **Code:** [install.sh:31](../../install.sh#L31) `chezmoi init --apply` runs unconditionally on every full run. · type A · alta · cross-ref **DATA-03, REL-05**
- **Impact:** A re-run is **not** a no-op: it reverts the user's live theme and any hand-edits under
  `~/.config` (DATA-03), and a failed `chezmoi apply` isn't transactional (REL-05). Anyone trusting the
  idempotency claim to re-run after a tweak loses state.
- **Recommendation:** Qualify the guarantee — reserve "idempotent" for the package/module steps that
  truly are, and note that re-running re-applies dotfiles over `~/.config` and that `chezmoi apply` is
  not atomic.

### DOC-06 — Layout docs show only `bin/theme-switch`, hiding the deployed (broken) `home/dot_local/bin/theme-switch`
- **Doc:** [README.md:90](../../README.md#L90) / [CONTEXT.md:68](../CONTEXT.md) list only `bin/theme-switch`. **Code:** a second, byte-identical [home/dot_local/bin/theme-switch](../../home/dot_local/bin/theme-switch) is what chezmoi deploys to `~/.local/bin` (the on-PATH copy). · type A · alta · cross-ref **DATA-01/DATA-04, QUAL-03**
- **Impact:** The Layout omission hides a load-bearing duplication: the docs imply one switcher; reality
  ships two, and the *deployed* one is the broken copy (DOC-02). The omission is what lets the
  two-copies-with-no-source-of-truth problem stay invisible.
- **Recommendation:** Show `home/dot_local/bin/theme-switch` in the Layout as the deployed PATH entry and
  clarify that `bin/theme-switch` only works in-repo — or collapse to one copy.

---

## BAJO — stale docs (names / versions / counts)

| ID | Doc says | Reality | Fix |
|----|----------|---------|-----|
| **DOC-07** | [README.md:89](../../README.md#L89) `templates/ … (envsubst)` | [theme-switch:4,19](../../bin/theme-switch#L4) pure **sed**, "no envsubst/gettext" (CONTEXT.md:84 agrees) — README is the lone outlier | "(pure-sed `${VAR}` substitution)" |
| **DOC-08** | [README.md:86](../../README.md#L86) module `20-niri` | file is `20-niri-desktop.sh`; [install.sh:24](../../install.sh#L24) + README.md:14 + CONTEXT.md:64 all say `20-niri-desktop` | `20-niri-desktop` (internal inconsistency) |
| **DOC-09** | [README.md:35](../../README.md#L35)/CONTEXT.md:41 "VS Code" | [dev.txt:2](../../packages/dev.txt#L2) `code` = **Code-OSS** (Open VSX, no MS Marketplace) — cross-ref QUAL-07 | "Code-OSS (`code`)" |
| **DOC-10** | [README.md:76](../../README.md#L76) keyd maps **7** letters (C/V/X/Z/A/S/F) | [20-niri-desktop.sh:38-50](../../modules/20-niri-desktop.sh#L38-L50) maps **13** (adds w/t/n/q/l/r) | list the full set or make it open-ended |
| **DOC-11** | [README.md:75](../../README.md#L75) "⌘+←/→ → **move** across the strip" | [config.kdl:72-73](../../home/dot_config/niri/config.kdl#L72-L73) binds **focus**-column; **move** is `Mod+Shift+←/→` ([:76-77](../../home/dot_config/niri/config.kdl#L76-L77)) | "focus/navigate across the strip" |
| **DOC-12** | `README.md` exists at wrapper root **and** `archfrican/` (byte-identical) | no doc states which is canonical — drift hazard — cross-ref QUAL-05 | make `archfrican/README.md` canonical; pointer/symlink the other |

---

## ✅ Reconciliation matrix — claims the docs get RIGHT (credibility baseline)

The adversarial pass confirmed **13 doc↔code matches**. These hold up:

| Claim | Doc | Code — verified |
|-------|-----|-----------------|
| Keybind rule "niri never uses plain `Mod+<letter>`" | CONTEXT.md:49-51 | [config.kdl:62-116](../../home/dot_config/niri/config.kdl#L62-L116) — **0 plain Mod+letter binds** ✅ |
| "cerrar ventana = `Mod+Shift+Q`" | CONTEXT.md:51 | [config.kdl:67](../../home/dot_config/niri/config.kdl#L67) ✅ |
| ⌘+Space=launcher, ⌘+Tab=overview | README.md:74 | config.kdl:65-66 ✅ |
| keyd ⌘+letter→Ctrl **no collision** | README.md:70-72 | keyd maps only plain `meta.<letter>`; niri uses `Mod+Shift+<letter>` — no overlap ✅ |
| "42 archivos" | CONTEXT.md:80 | `find archfrican -type f` = **42** ✅ |
| "Todos los scripts pasan `bash -n`" | CONTEXT.md:81 | all 14 scripts parse ✅ |
| Dual kernel cachyos + **lts** fallback | README.md:29 / CONTEXT.md:32 | [00-base.sh:20-24](../../modules/00-base.sh#L20-L24) ✅ |
| GPU auto stacks (nvidia-open-dkms / vulkan-radeon / vulkan-intel) | README.md:31 | [10-gpu.sh:11-22](../../modules/10-gpu.sh#L11-L22) ✅ |
| 4 themes, **identical variable schema** | README.md:88 / CONTEXT.md:76 | `themes/{macos-dark,macos-light,catppuccin-mocha,tokyo-night}` ✅ |
| Theming hot-reload mechanics (source→sed-render→waybar SIGUSR2/makoctl/niri splice/fuzzel `#`-strip) | CONTEXT.md:72-76 | [theme-switch:17-49](../../bin/theme-switch#L17-L49) ✅ |
| niri lives in exactly one module + dotfiles (swap-the-module) | README.md:13-16 | install.sh:24 + 20-niri-desktop.sh ✅ (also QUAL-09) |
| Snapper + snap-pac + grub-btrfs rollback stack wired | README.md:19,28 | [50-snapshots.sh:5-13](../../modules/50-snapshots.sh#L5-L13) ✅ *(but see DATA-02 unit-name caveat)* |
| `templates/` engine + 5 template files present | CONTEXT.md:67,72-76 | `templates/` ✅ |

---

## Refuted / Discarded (1) — transparency

| Candidate | Type | Why refuted |
|-----------|------|-------------|
| "'GPU-agnostic — the same installer runs on any machine' (README.md:17-18) is an absolute guarantee the detection code doesn't back" | A | The specific framing ("detect_gpu returns an unhandled profile → wrong/no stack") is **false**: [detect-gpu.sh:16](../../lib/detect-gpu.sh#L16) has an explicit `else echo "unknown"` and `10-gpu.sh:35` handles it. The real gap (detect_gpu **aborting** before returning on a no-VGA/missing-`lspci` host) is a distinct issue already tracked as **REL-01** — not a "doc contract" violation. "Runs on any machine" is loose marketing language, not a precise contract. |

---

## Cross-cutting note for synthesis (Phase 6)
- **Convergence reinforced:** the **ghostty** gap and the **theme-switch** breakage each appear as both a
  code defect (QUAL-01 / DATA-01) **and** a documentation contract violation (DOC-01 / DOC-02/DOC-06) —
  these are the two clearest "documented headline feature that doesn't work" stories.
- The docs are **mostly honest** (13 verified matches, including the non-trivial keybind-collision design)
  — the failures cluster in **aspirational features not yet wired** (blur, full live-reload, ghostty
  install) and **overstated guarantees** (idempotency, "tested working"). Per the prompt's guidance: blur
  / live-reload / ghostty should be **implemented or degraded to 🚧 ROADMAP**; the idempotency and
  "tested" claims should be **softened to match reality**.
