# Phase 3 — Reliability & Runtime Robustness

**Scope:** the project's **stated #1 principle is "nothing explodes"** (reliability first), so this
phase replaces the generic "performance" lens (irrelevant for a one-shot installer) with: error
handling, **silent-failure masking**, hardware edge cases, **recovery from a mid-install failure**,
and whether documented runtime behavior (live reload, applied settings) is **actually wired**.

**Method:** 3 parallel finders → 1 adversarial verifier per candidate. **27 candidates → 24 survived,
3 refuted.** The 3 refutations were all dismantled by precise `set -e` semantics (see end).

> Carried correction from Phase 1 (central to this phase): modules **do** run under `set -euo
> pipefail` (inherited from the sourced `common.sh`). So I do **not** report "modules lack error
> handling" globally. The real reliability gaps are the opposite shape: errexit is *so* active that
> **best-effort steps that forgot `|| true` abort the whole install**, while `|| true` elsewhere
> **masks failures that leave the system silently misconfigured**. The honest theme of Phase 3 is
> **inconsistent error handling**, not missing error handling.

---

## Severity summary (this phase, deduplicated)

| Severity | Count | Items |
|----------|-------|-------|
| CRÍTICO  | 0 | — |
| ALTO     | 4 | REL-01 … REL-04 |
| MEDIO    | 7 | REL-05 … REL-11 |
| BAJO     | 6 | REL-12 … REL-17 |
| INFO     | 3 (positive) | REL-18 … REL-20 |

Refuted: **3**. Cross-references: SEC-09/SEC-10/SEC-20 (Phase 1), DATA-01/DATA-03 (Phase 2).

---

## ALTO

### REL-01 — GPU detection aborts the entire installer on headless/no-VGA hosts or where `lspci` is absent; the documented "unknown" fallback is unreachable
- **File:** [lib/detect-gpu.sh:5](../../lib/detect-gpu.sh#L5) · confidence: alta (defect) / media (does a given base ship `pciutils` — **a confirmar**)
- **Evidence:** `local vga; vga="$(lspci -nn | grep -Ei 'vga|3d|display')"`
- **Impact:** Under the active `set -euo pipefail`, the bare assignment `vga="$(…)"` aborts whenever its
  RHS pipeline exits non-zero — and there are **two realistic paths**: (a) `grep` matches nothing
  (headless box / a VM whose display device name lacks `vga|3d|display`) → `pipefail` propagates exit 1;
  (b) `lspci` is **missing** — `pciutils` is **not** in the archinstall base packages
  ([user_config.json:26](../../archinstall/user_config.json#L26) lists only git/vim/sudo/zsh/btrfs-progs),
  not in `base.txt`, and this is the only `lspci` in the repo. Either way the function aborts **at line
  5**, so the `else echo "unknown"` fallback ([:16](../../lib/detect-gpu.sh#L16)) is **never
  reached**, and `GPU="$(detect_gpu)"` ([install.sh:20](../../install.sh#L20)) then dies at the
  installer's **very first real step**, before any module runs. The advertised graceful auto-detect is
  false on these paths.
- **Recommendation:** Make detection failure-tolerant so the fallback works:
  `vga="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)"` (neutralizes both the missing-127
  and no-match-1 cases). **And** ensure `pciutils` is present before detection (add to `base.txt` and/or
  guard with `command -v lspci`), since `base.txt` is only processed by `00-base`, which runs **after**
  detect_gpu.

### REL-02 — `rustup` vs `fnm` asymmetric error handling: a transient `rustup` hiccup halts the *entire* installer
- **File:** [modules/30-dev.sh:9-10](../../modules/30-dev.sh#L9-L10) · confidence: alta (defect) / media (rustup network trigger — a confirmar)
- **Evidence:**
  ```bash
  command -v rustup &>/dev/null && rustup default stable
  command -v fnm   &>/dev/null && fnm install --lts || true
  ```
- **Impact:** Line 10 parses as `(command -v fnm && fnm install --lts) || true` — fnm failures fully
  swallowed. Line 9 has **no `|| true`**: it is an `&&` list whose **final** command (`rustup default
  stable`) is **not** exempt from errexit. `rustup default stable` downloads the toolchain on first run;
  a transient network/mirror failure makes line 9 abort the module — and because `run_module 30-dev`
  ([install.sh:25](../../install.sh#L25)) is a bare command under install.sh's own errexit, **the
  whole installer halts**: 40-theming, 50-snapshots, and the chezmoi `init --apply` never run → the box
  ends with **no dotfiles, no theme switcher, no snapshots** — over a step that was clearly meant to be
  best-effort, while the *more* fragile `fnm` is treated as ignorable.
- **Recommendation:** Make both symmetric and best-effort:
  `if command -v rustup &>/dev/null; then rustup default stable || warn "rustup default failed"; fi`
  (same shape for fnm).

### REL-03 — No `trap`/rollback/resume guidance: a mid-install abort leaves a half-configured system
- **File:** [install.sh:22-31](../../install.sh#L22-L31) · confidence: alta
- **Evidence:** six sequential `run_module …` calls under `set -e`; repo-wide grep for `trap` → zero
  real hits.
- **Impact:** If any module aborts (and Phase 3 shows several realistic ways: REL-01, REL-02, REL-10),
  the script just dies — no rollback, no "which step failed / how to resume" message. Leftover state is
  partial and order-dependent (e.g. `20-niri-desktop` enables `greetd.service` at line 17, then aborts
  at line 20 before pipewire user services → greetd launches `niri-session` without audio configured).
  "Idempotent: safe to re-run" only self-heals where each module happens to be guarded; an arbitrary
  abort point has no guaranteed clean resume. **Bounded** by the `linux-lts` GRUB fallback
  ([00-base.sh:23-24](../../modules/00-base.sh#L23)) and Snapper — which is *why this is ALTO, not
  CRÍTICO* — but the operator is given no signal.
- **Recommendation:** Add an `ERR`/`EXIT` trap in `install.sh` that prints the failed module and the
  exact `./install.sh <module>` resume command ([install.sh:17](../../install.sh#L17) already
  supports single-module runs); optionally checkpoint completed modules with a touch-file; document the
  resume path in the README near the "idempotent" claim.

### REL-04 — `gsettings` during a TTY phase-2 install almost certainly no-ops: the macOS GTK look is **not** applied at install time (masked by `|| true`)
- **File:** [modules/40-theming.sh:10-15](../../modules/40-theming.sh#L10-L15) (and the identical pattern in [theme-switch:43-45](../../bin/theme-switch#L43-L45)) · confidence: media (**a confirmar** — depends on session-bus availability)
- **Evidence:**
  ```bash
  gsettings set org.gnome.desktop.interface gtk-theme    "WhiteSur-Dark"    || true
  gsettings set org.gnome.desktop.interface cursor-theme "McMojave-cursors" || true
  ```
- **Impact:** Phase 2 runs from a plain TTY/SSH as the normal user (`[ "$EUID" -eq 0 ] && die …`).
  `gsettings` writes to dconf over the D-Bus **session** bus; on a TTY with no graphical session there
  is typically no session bus, so every call fails and is swallowed by `|| true`. The WhiteSur GTK/icon
  theme, McMojave cursors, SF fonts, and `prefer-dark` are then recorded as applied by the green log
  line but **never written to dconf** — the user's first niri login shows default Adwaita, directly
  contradicting `log "Applying WhiteSur GTK theme…"`. The macOS look is a core selling point.
- **Recommendation:** Don't rely on `gsettings` from a TTY. Write the GTK look via chezmoi-managed files
  dconf can't miss (`~/.config/gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`, `~/.icons/default/index.theme`),
  or run under `dbus-launch --exit-with-session`, or defer to a niri `spawn-at-startup` one-shot. At
  minimum, `warn` (not `|| true`) so a skipped apply is visible.

---

## MEDIO

### REL-05 — `chezmoi init --apply` at the very end can abort after all six modules ran → package-complete but config-empty
- **File:** [install.sh:30-31](../../install.sh#L30-L31) · confidence: media
- A template-render error, destination-file conflict, or a re-run over a partial/foreign chezmoi state
  makes the **bare** `chezmoi init --apply` exit non-zero — aborting **after** every module already
  mutated the system. Dotfiles aren't deployed, so greetd launches `niri-session` with **no niri config
  and no theme files** = broken first login, even though every package step "succeeded". Violates the
  documented "safe to re-run (idempotent)" ([README.md:54](../../README.md#L54)).
- **Recommendation:** Detect existing chezmoi state and use `chezmoi apply` vs `init --apply`; on
  failure emit an explicit *"dotfiles NOT applied — run: chezmoi init --apply --source …/home"* instead
  of a bare errexit abort.

### REL-06 — NVIDIA grub + mkinitcpio edits aren't atomic, and a failed `mkinitcpio` isn't retried on re-run
- **File:** [modules/10-gpu.sh:24-33](../../modules/10-gpu.sh#L24-L33) · confidence: media · cross-ref SEC-09/SEC-10
- The two boot-critical mutations are committed in **separate** guarded blocks. If `mkinitcpio -P`
  (line 30) fails under errexit, the module aborts with `nvidia_drm.modeset=1` already in the kernel
  cmdline but the nvidia modules **absent from the initramfs** → early-KMS for a missing module (a known
  black-screen recipe). Worse, the inner guard `grep -q 'nvidia' /etc/mkinitcpio.conf` matches the names
  the **line-29 sed already wrote**, so on re-run the block is **skipped** — the failed rebuild is never
  retried (broken self-heal). **Verifier correction:** the grub cmdline edit applies to **every** GRUB
  entry including `linux-lts`, so the dual-kernel fallback does **not** escape the torn cmdline; and the
  black-screen outcome is situational (udev may load modules late) — hence MEDIO, not CRÍTICO.
- **Recommendation:** Edit both files first, then run `grub-mkconfig` + `mkinitcpio -P` **together** at
  the end; gate the rebuild on a sentinel (not on the module names it just wrote) so a failed rebuild
  re-attempts; emit *"NVIDIA early-KMS incomplete — boot linux-lts and re-run"* on failure.

### REL-07 — AMD-discrete + Intel-iGPU combo installs only the AMD stack, leaving the Intel iGPU without its driver
- **File:** [lib/detect-gpu.sh:14](../../lib/detect-gpu.sh#L14) · confidence: alta
- A machine with an Intel CPU iGPU + AMD Radeon dGPU (no NVIDIA) sets `has_amd=1, has_intel=1`. There is
  **no `hybrid-amd-intel` case**, so it falls to `elif [ $has_amd -eq 1 ]; then echo "amd"` (tested
  *before* the intel branch). `10-gpu.sh:11` then installs only `mesa vulkan-radeon …`, omitting
  `vulkan-intel`/`intel-media-driver` → the Intel iGPU (which often drives the internal laptop panel)
  gets no Vulkan ICD and no VA-API HW video decode. mesa GL still works, so not a brick.
- **Recommendation:** Add a `hybrid-amd-intel` profile (before the bare `amd` elif) and install both open
  stacks (they coexist): `mesa vulkan-radeon vulkan-intel libva-mesa-driver intel-media-driver`.

### REL-08 — NVIDIA suspend/resume enable failures fully masked; hibernate not covered at all
- **File:** [modules/10-gpu.sh:32](../../modules/10-gpu.sh#L32) · confidence: media (a confirmar on unit presence)
- `systemctl enable nvidia-suspend.service nvidia-resume.service 2>/dev/null || true` discards stderr
  **and** exit code; if the units are missing (version skew), suspend/resume is silently unconfigured on
  exactly the NVIDIA hardware this branch targets — contradicting the line-23 "resume-from-suspend works"
  comment. `nvidia-hibernate.service` is never enabled at all. (Current `nvidia-utils` ships all three,
  so the common path is fine — MEDIO.)
- **Recommendation:** Per-unit existence check + `warn` on real failure (cover `nvidia-hibernate` too),
  keeping the installer non-fatal but surfacing the gap.

### REL-09 — README's "live switching across all 6 surfaces" is false for ghostty (stays stale until restart)
- **File:** [bin/theme-switch:47-49](../../bin/theme-switch#L47-L49) · confidence: alta · **also Phase 5 (docs↔code)**
- theme-switch pushes a runtime reload only to **waybar** (`SIGUSR2`) and **mako** (`makoctl reload`).
  It writes `~/.config/ghostty/colors` but sends ghostty **no** reload — already-open ghostty windows
  keep the old palette until a new window/restart. fuzzel is next-launch (it's not a daemon). So
  [README.md:65](../../README.md#L65) *"Switching is live (waybar, mako, fuzzel, ghostty, niri borders, GTK)
  — no logout"* is inaccurate for ghostty and overstated for fuzzel.
- **Recommendation:** Correct the README ("waybar + mako reload live; GTK via gsettings; ghostty applies
  to new windows; fuzzel on next launch"), or add a ghostty reload trigger if/when ghostty exposes one.

### REL-10 — `enable_user_service pipewire.service` is the wrong unit and can abort the install
- **File:** [modules/20-niri-desktop.sh:20-21](../../modules/20-niri-desktop.sh#L20-L21) · confidence: media (a confirmar)
- `enable_user_service` is `systemctl --user enable "$1"` ([common.sh:38](../../lib/common.sh#L38)),
  a **bare** command under errexit. `systemctl --user` needs the user's systemd instance/bus; over a
  sudo-less TTY/SSH it can fail with *"Failed to connect to bus"* → aborts the whole install at this
  line. Also, modern pipewire is **socket-activated** (`pipewire.socket`, WantedBy session) — manually
  enabling `pipewire.service` is usually unnecessary and can fight socket activation.
- **Recommendation:** `loginctl enable-linger "$USER"` first, or defer pipewire/wireplumber to first
  graphical login; wrap `enable_user_service` so a bus failure `warn`s instead of aborting; verify
  whether `pipewire.socket` is the correct unit.

### REL-11 — First interactive zsh blocks on a network `git clone` of zinit, then `source`s unconditionally
- **File:** [home/dot_zshrc:7-9](../../home/dot_zshrc#L7-L9) · confidence: alta
- The first login shell does a **blocking** `git clone` of zinit (worst time: right after install, on a
  flaky network), then `source "$ZINIT_HOME/zinit.zsh"` **unconditionally on the next line** even if the
  clone failed → `no such file` error + the `zinit wait lucid` block becomes an unknown command → first
  shell is visibly broken (no highlighting/autosuggestions), and the "<50ms startup" comment is
  unattainable on that run. Self-heals once network returns.
- **Recommendation:** Chain `git clone … && source …` (or guard `[ -r "$ZINIT_HOME/zinit.zsh" ]`), guard
  the `zinit wait` block, and ideally provision zinit at install time so first login is offline-safe.

### (Cross-ref, not re-counted) theme-switch ↔ chezmoi at install time
- [theme-switch:18,33-40](../../bin/theme-switch#L33-L40): 40-theming runs `theme-switch macos-dark`
  **before** chezmoi applies dotfiles, so `~/.config/niri/config.kdl` doesn't exist yet and the niri
  splice is silently skipped; the color files it writes are then overwritten by chezmoi. **Visually
  benign for the default theme only** (the committed dotfiles already are macos-dark). This is the
  install-ordering angle of **DATA-01/DATA-03** — tracked there.

---

## BAJO

- **REL-12** — `pac_install_file`/`aur_install_file` mask a failing `grep` in a process substitution
  ([common.sh:34-35](../../lib/common.sh#L34-L35)): a **missing/unreadable** package list yields
  `_p=()` → "already present:" → success with **nothing installed**. Compounds SEC-01. *Fix:* `[ -r
  "$1" ] || die …; [ ${#_p[@]} -gt 0 ] || die …`.
- **REL-13** — `mktemp -d` temp dirs leaked on abort (no `trap`) ([00-base.sh:7-11, 28](../../modules/00-base.sh#L7-L11)). Low priority (/tmp is volatile). *Fix:* `trap 'rm -rf "$tmp"' EXIT`.
- **REL-14** — `usermod -aG docker … || true` ([30-dev.sh:14](../../modules/30-dev.sh#L14)) masks a
  group-add failure while line 15 implies it worked. *Fix:* `|| warn "…docker will need sudo"`.
- **REL-15** — `bootstrap.sh` `2>/dev/null` ([bootstrap.sh:6](../../bootstrap.sh#L6)) hides the clone's
  stderr, so a first-run clone failure (no network / placeholder `YOU` org) shows only the misleading
  fallback-pull error. *Fix:* don't discard clone stderr; verify the repo before pulling.
- **REL-16** — VM/generic-mesa branch ([10-gpu.sh:35](../../modules/10-gpu.sh#L35)) installs no
  software Vulkan ICD → `vkEnumeratePhysicalDevices` returns 0 on a VM with a virtual adapter that
  matches no vendor grep. *Fix:* add `vulkan-swrast` (lavapipe), optionally `vulkan-virtio`.
- **REL-17** — `eval "$(starship init zsh)"` unguarded ([dot_zshrc:31](../../home/dot_zshrc#L31)) →
  `command not found: starship` + lost prompt on a partial install (= **SEC-20**). *Fix:* `command -v
  starship &>/dev/null && eval …`, matching the guarded zoxide/fnm/direnv lines above it.

---

## INFO — positive findings

- **REL-18 ✅** theme-switch's live-reload `|| true` ([:48-49](../../bin/theme-switch#L48-L49)) is
  **correct** defensive masking (signalling a non-running waybar/mako at install time must be a no-op,
  not an abort) — the right contrast to the *harmful* masks above (REL-04, SEC-09).
- **REL-19 ✅** Hybrid-NVIDIA `case` grouping and `[[ … ]] && pac_install …` conditional add-ons
  ([10-gpu.sh:18-22](../../modules/10-gpu.sh#L18-L22)) are correct under `set -e` (a false `[[ ]]` in
  an `&&` list short-circuits without aborting).
- **REL-20 ✅** The `command -v <tool> &>/dev/null && eval …` pattern for zoxide/fnm/direnv
  ([dot_zshrc:26-28](../../home/dot_zshrc#L26-L28)) is the correct robustness contract — it's exactly
  what starship (REL-17) and the zinit clone (REL-11) should be brought up to.

---

## Refuted / Discarded (3) — transparency
All three were dismantled by the **active errexit** the finders initially under-modeled:

| Candidate | Orig. sev. | Why refuted |
|-----------|-----------|-------------|
| "greetd enabled before niri is confirmed installed → unusable login" ([20-niri-desktop.sh:7-17](../../modules/20-niri-desktop.sh#L7-L17)) | ALTO | `pac_install_file` (line 7) runs **before** the greetd config (line 10), and `pacman -S` is a **bare** command (atomic transaction) under errexit — a failed niri install aborts **before** greetd is ever configured. No partial "greeter without session" state. |
| "`theme-switch … \|\| true` masks a broken default-theme apply" ([40-theming.sh:17-18](../../modules/40-theming.sh#L17-L18)) | MEDIO | theme-switch creates its own output dirs and all templates/palettes exist, so on the common path it **doesn't fail** — there's nothing for `\|\| true` to mask. (The real issue is the redundant ordering, folded into DATA-03.) |
| "snapper create-config aborts 50-snapshots, leaving snapshots *silently* inactive" ([50-snapshots.sh:6-13](../../modules/50-snapshots.sh#L6-L13)) | MEDIO | Already **DATA-02**; and the abort is **loud** (errexit halts the run before the "Snapshots active" banner at line 14), not silent. |

---

## Cross-cutting note for later phases
- **Convergence:** `bin/theme-switch` now appears in **Phases 1, 2, and 3** (SEC-06/07/15, DATA-01/03/04,
  REL-09 + cross-refs) — the single highest-ROI file. `modules/10-gpu.sh` carries REL-06/07/08/16 +
  SEC-09/10. `install.sh` orchestration (REL-02/03/05) is the second cluster.
- **Theme transversal:** the dominant reliability pattern is **inconsistent error handling** — some
  best-effort steps abort the whole install (REL-01/02/10), while `|| true` elsewhere masks real
  misconfiguration (REL-04/08/12/14). A consistent `warn`-on-failure helper would fix most of them.
- REL-09 (live-reload claim) and REL-04 (macOS look not applied) are **also Phase-5 docs↔code** items.
