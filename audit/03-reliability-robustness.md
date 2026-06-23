# Phase 3 — Reliability & Robustness

**Scope:** error-handling vocabulary (`die`/`best_effort`/`attempt` vs blanket `|| true`), partial-failure recovery & resume, network resilience (timeouts/retries), `set -e`/errexit/pipefail interactions, and a thin performance sub-lens (installer runs once → only material waste counts).
**Method:** 5 parallel finder lenses → adversarial verifier per candidate → my own reading + grep reproduction. Pinned at **git HEAD `821e217`**.

## Verdict for this phase

The error-handling **discipline is excellent** — a deliberate `die`/`best_effort`/`attempt` vocabulary (27 `best_effort`, 8 `attempt` sites), verify-or-die GRUB edits, a sentinel-gated NVIDIA rebuild, a timeout-capped os-prober, and an `on_err` resume trap. The prior audit's reliability HIGHs (GPU-abort, rustup, no-ERR-trap) are **fixed**. **But this phase surfaces the audit's most consequential findings so far: 3 HIGH.** Two are failure-path bugs in the **first-boot resume** that can leave a machine in an *unrecoverable boot loop* (one of them on a common WiFi-only laptop), and one is a **silently-swallowed `git reset`** that makes `archfrican-update` run a stale tree while reporting success. All three are *failure-path* bugs — the happy path works; the danger is what happens when a step fails.

### Candidate accounting

| | Count |
|---|---|
| Candidates raised | 14 |
| Survived adversarial verification | 9 |
| Refuted / discarded | 5 |
| **HIGH** | 3 |
| **MEDIUM** | 1 |
| **LOW** | 4 |
| **INFO** | 1 |

## Reproduction (run locally, read-only)

```
best_effort sites: 27   attempt sites: 8        (disciplined vocabulary, not blanket || true)
raw '|| true' sites: all reviewed — legitimate (health counts, /dev/tty reads, tolerant cleanup)
grub-mkconfig call sites: base-install:156, 00-base:53, 10-gpu:64(NVIDIA), 50-snapshots:50,
                          55-multiboot:33(opt-in), 60-security:136(ucode)
network calls w/o retry: 00-base:9 curl (no --retry/--max-time), install.sh:39/42 git (no retry)
                         preflight:19-20 curl --max-time 8 (timeout, no retry — but gated, see Refuted)
```

---

## HIGH findings

### H1 — First-boot resume retries a *deterministic* failure forever, leaving the NOPASSWD drop-in present every boot
*(= the reliability facet of Phase 1 **M1** — same NOPASSWD-resume artifact, now with the stuck-forever dimension)*

- **Files:** `templates/archfrican-resume.service:26-29` · `lib/common.sh:159-161` (warn-only preflight) · `lib/phase1.sh:40` (the drop-in)
- **Severity:** HIGH *(finder said CRITICAL; verifier corrected — see below)* · **Confidence:** high
- **Evidence:** `preflight_pkgs` is **warn-only by default** — `warn "preflight: these will likely fail to install …"` (`common.sh:161`); it only `die`s under `ARCHFRICAN_STRICT_PREFLIGHT=1`, which the resume unit **does not set** (`phase1.sh:59-68` forwards only `ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS`). So a package that has been **dropped/renamed in the repos** passes preflight, then fails fatally at `pac_install` (`common.sh:100`, under `set -e`) → `ExecStart` fails → the success-gated `ExecStartPost` cleanup never runs → the unit (no `StartLimit*`) **retries every boot** and the `NOPASSWD: ALL` drop-in **lingers indefinitely**.
- **Impact:** an unattended first-boot install can get **permanently stuck half-installed** (no desktop), retrying forever, with the temporary passwordless-root grant never removed. *Verifier's two corrections (both honest and adopted):* (1) the privilege angle is a **hardening regression** (the grant is to the already-`wheel` user — removes the password gate, not a new root path), so HIGH not CRITICAL; (2) the failure **is** surfaced on-screen — `firstboot-notice.sh:12-13` prints a login-time "setup hit a snag" notice with `journalctl`/retry hints. The CI `pkg-resolution` gate makes the trigger less likely for *shipped* lists, but a package can drop from the repos after the last CI run.
- **Recommendation:** set `Environment=ARCHFRICAN_STRICT_PREFLIGHT=1` in `archfrican-resume.service` so an unresolvable package fails **before** any state change (and before the NOPASSWD window opens); add `StartLimitIntervalSec`/`StartLimitBurst` (or a boot counter) so after N failed boots the unit **removes the drop-in and disables itself** — failing *closed* on privilege.

### H2 — First-boot WiFi resume carries credentials from the wrong directory → a WiFi-only laptop hits the fatal net check and boot-loops forever
- **File:** `lib/phase1.sh:48-49` (with `preflight.sh:53` fatal `pf_net`, `archfrican-resume.service:14-15`)
- **Severity:** HIGH *(finder said MEDIUM; verifier raised it — common trigger + unrecoverable)* · **Confidence:** high
- **Evidence:**
  ```bash
  # lib/phase1.sh:48 (comment) — factually wrong about iwctl:
  # connected with on the ISO (iwctl/nmtui write to /etc/NetworkManager/system-connections).
  if compgen -G '/etc/NetworkManager/system-connections/*' >/dev/null 2>&1; then
  ```
- **Impact:** `iwctl` is **iwd**, which stores WiFi profiles in `/var/lib/iwd/<SSID>.psk` — **not** in `/etc/NetworkManager/system-connections`. The official Arch ISO documents `iwctl` for WiFi and doesn't run NetworkManager, so an operator who brings up WiFi the standard Arch way leaves the NM dir **empty**. `inject_resume` then carries no profile (falls to the "relies on auto wired DHCP" warn at `:55`). On first boot the resume waits on `network-online.target`, NetworkManager has nothing to connect with, `pf_net` (the **fatal** preflight gate) aborts, and the unit **retries every boot forever** — an **unrecoverable headless boot loop** on a WiFi-only laptop (a primary install case), with the NOPASSWD drop-in (H1) also lingering. `grep` confirms iwd credentials are carried **nowhere** in the repo. (Verifier note: the comment is half-right — `nmtui` *does* write to the NM dir; only the `iwctl` claim is false.)
- **Recommendation:** in `inject_resume`, also detect iwd: if `/var/lib/iwd/*.psk` exists, copy to `/mnt/var/lib/iwd/` (preserve `0600`) and `arch-chroot /mnt systemctl enable iwd` (or set NM `wifi.backend=iwd`), or translate the SSID into an NM keyfile. At minimum fix the comment and make the no-profiles branch detect the iwd case instead of silently assuming wired DHCP.

### H3 — `converge()`: a failed `git reset --hard FETCH_HEAD` is silently swallowed under `set +e` → the update runs against a **stale** tree while reporting success
- **File:** `bin/archfrican-update:107` (errexit disabled at `:23`)
- **Severity:** HIGH · **Confidence:** high
- **Evidence:**
  ```bash
  if git -C "$ROOT" fetch --depth 1 origin "$ARCHFRICAN_REF" >/dev/null 2>&1; then
      git -C "$ROOT" reset --hard FETCH_HEAD >/dev/null 2>&1          # no || handler; errexit OFF
      new="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"
      if [ "$old" != "$new" ]; then _ok "repo $old → $new"; else _ok "repo already current ($new)"; fi
  ```
- **Impact:** the whole interactive flow runs under `set +e +u +o pipefail` (`:23`). If the `reset --hard` fails (a stale `.git/index.lock` from an interrupted prior run, a full/read-only working tree, a corrupted object), HEAD doesn't move → `old == new` → it prints **"repo already current"** — indistinguishable from "no new commits" — then `converge()` runs `install.sh --update` against the **old** tree and converges to the **old** desired state, **reporting success**. This silently defeats the product's core promise ("updating == a fresh install"): the machine stays behind the repo and the user is told they're current. A partially-applied reset can also leave a half-updated tree undetected. The identical `git reset --hard` in `install.sh:40` runs under `set -euo pipefail` and **aborts loudly** — here it's masked.
- **Recommendation:** check the reset's exit status explicitly (`if git … reset --hard …; then … else _note "git reset failed — repo NOT updated; converging stale on-disk repo ($old)"; fi`) and base the `$old → $new` vs "already current" message on whether the reset actually succeeded.
- **Cross-ref:** same line as Phase 2 **M3** (a *successful* reset discards local edits) — different failure mode, same fix surface (`archfrican-update:106-107`).

---

## MEDIUM findings

### M1 — CachyOS bootstrap tarball download has no `--retry`/`--max-time`/`--connect-timeout`
- **File:** `modules/00-base.sh:9`
- **Severity:** MEDIUM *(finder said HIGH; verifier lowered — recoverable)* · **Confidence:** high
- **Evidence:** `curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz`
- **Impact:** a bare `curl` under `set -euo pipefail` to a **single non-Arch host** with no mirror failover; a transient DNS hiccup / TCP reset / stalled connection aborts module `00-base`. The codebase already uses `--max-time 8` in `preflight.sh:19`, so the omission is a gap, not house style. *Verifier's mitigation:* recoverable — a mid-module failure writes no `.done` (so re-run re-enters cleanly via the `[cachyos]` guard), and the ISO resume auto-retries; on a manual booted-base install it's one manual re-run. The "silently extracts a truncated tarball" angle is self-mitigating (`curl -f` errors on short read; `tar xf` fails under `set -e`).
- **Recommendation:** `curl -fL --proto '=https' --tlsv1.2 --retry 3 --retry-connrefused --retry-delay 2 --connect-timeout 15 --max-time 180 -o repo.tar.xz …`; optionally `tar tf … >/dev/null` before extracting.

---

## LOW findings

| # | Finding | File | Note |
|---|---------|------|------|
| **L1** | `grub-btrfsd` is enabled `best_effort` (swallowed on failure), but the post-condition only checks the *snapper config* and then prints "one reboot away from a rollback" **unconditionally** — overstating the safety net if the daemon enable silently failed. | `50-snapshots.sh:46,53-54` | `grub-btrfs` is fatally installed (`base.txt`) so the unit is present and enable rarely fails; line 50's one `grub-mkconfig` still puts *current* snapshots in the menu — only *future* auto-regeneration is lost. Fix: assert `systemctl is-enabled --quiet grub-btrfsd` before the success line. |
| **L2** | Non-fatal service enables (`resilient_enable`) aren't self-healing across runs: a failed enable still lets the module stamp `.done`, so converge skips it. | `common.sh:46-51` + modules | *Verifier corrected scope:* `health.sh:check_timers` **already** re-asserts the 4 maintenance timers weekly; the real residual gap is the non-timer daemons (`NetworkManager`, `bluetooth`, `power-profiles-daemon`, `smartd`) — extend `check_timers` to cover them. NetworkManager-enable failure is low-probability (static symlink op). |
| **L3** | Bootstrap `git fetch`/`clone` (the first network op of `curl\|sh`) has no retry. | `install.sh:39,42` | *Downgraded MEDIUM→LOW:* the abort is **stateless and trivially re-run** (most recoverable point in the flow); the ISO resume runs from an already-cloned repo so never hits bootstrap. Optional: a 3-attempt loop + `git -c http.lowSpeedLimit=… -c http.lowSpeedTime=…`. |
| **L4** | `converge()`'s `run_migrations \|\| { _note …; return 1; }` handler is **dead code**: `run_migrations` hard-`exit`s via `die` on a failed migration (even under `set +e`), so control never reaches the `\|\|` branch. The abort is still correct; the message the user sees differs from the source's intent. | `archfrican-update:112` | Make `run_migrations` `return 1` instead of `die`, or drop the unreachable handler. |

## INFO

| # | Note | File |
|---|------|------|
| **I1** | On an os-prober **timeout (rc 124)**, `55-multiboot` warns but falls through to `ok`, so `.done` is stamped and a later converge won't auto-retry the *optional* multi-boot feature. *Verifier refuted the finder's "incomplete/corrupt menu" premise:* `grub-mkconfig` builds into `grub.cfg.new` and `mv`s atomically only at the end, so a kill mid-run leaves the **prior working menu intact** (the module comment relies on exactly this). Purely a "re-run the optional feature yourself" gap. Optional: `return 3` on rc 124 so it isn't stamped. | `55-multiboot.sh:33-39` |

---

## Refuted / Discarded (transparency — 5 of 14)

| Claim | Why refuted |
|---|---|
| **`grub-mkconfig` regenerated 3-5× per install is material perf waste** | Facts correct, but **doesn't clear the run-once perf bar**: the expensive part (os-prober disk scan) is **not** active on the 3 baseline regens (os-prober only enabled by opt-in `55-multiboot`); a fresh box enumerates ~2 kernels + a few `grub.d` scripts → sub-second each, a few seconds total. Install-scale micro-opt — discarded. |
| **`pf_net` 8s single-shot with no retry is a fatal gate** | The headless resume declares `After=/Wants=network-online.target`, so systemd **waits for the link** before `pf_net` runs — defusing the "link still settling" race; failure self-heals (retry next boot); and the proposed `--retry`/`--retry-connrefused` wouldn't even retry a `--max-time` timeout without `--retry-all-errors`. Adequate as-is. |
| **`ssh_enable_hardened` validates config `best_effort` then enables anyway** | Intentional for an **opt-in** feature under `set -e`: gating with `die` would abort the whole install over an optional nicety; the config is a static heredoc that can't realistically fail `sshd -t`; a truly bad merged config would fail-loud at `systemctl start` (also `best_effort`). At most a comment wording nit. |
| **chezmoi dotfiles step is outside the `.done` resume model** | Intentional and correct — chezmoi `init --apply` is idempotent and *should* always re-run; failure is a **loud `die`** with an explicit re-run command; the ISO resume retries to success. No silent path. |
| **NVIDIA early-KMS sentinel is a correct resume design** | A *praise note*, not a bug — verified correct (sentinel touched only after **both** `grub-mkconfig` and `mkinitcpio` succeed; `need_build` keys off sentinel *absence* so a crash mid-rebuild re-runs both). Dropped. |

---

## Cross-cutting: the first-boot resume is the reliability hot spot

**H1 + H2** both end in the same failure mode — the first-boot resume **stuck in an infinite boot loop with the NOPASSWD drop-in still live** — reached by two independent triggers (a dropped package; a WiFi-only laptop). Combined with **Phase 1 M1** (the NOPASSWD artifact itself), the **`archfrican-resume.service` + warn-only-preflight + success-gated-cleanup** design is the single highest-leverage area to harden: `STRICT_PREFLIGHT=1` in the unit, bounded retries, and an `ExecStopPost` that drops the NOPASSWD grant on failure would close M1, H1, and the privilege half of H2 at once.

## Prior-audit reconciliation (reliability items — full matrix in Phase 5)

| Prior finding | Status now | Evidence |
|---|---|---|
| **REL-01 (HIGH)** — GPU detection aborts on no-VGA / `lspci` absent | **FIXED** | `detect-gpu.sh:8` `command -v lspci … || { echo unknown; return 0; }`; `:10` `… || true`; PCI-vendor-id match avoids the "ati"/"CorporATIon" bug |
| **REL-02 (HIGH)** — `rustup default stable` lacks `\|\| true` → transient failure halts install | **FIXED** | `30-dev.sh:9` `have rustup && { … best_effort rustup default stable; }` |
| **(prior #8, HIGH)** — no trap/rollback/resume guidance on mid-abort | **FIXED** | `phase2.sh:9-17` `on_err` trap prints failed step + resume command; `firstboot-notice.sh` surfaces it on-screen |

---

*Next: Phase 4 — Quality, Deprecations & Hygiene (shellcheck/CI enforcement reality, deprecated APIs, honest test-coverage map, dead code, comment/doc drift).*
