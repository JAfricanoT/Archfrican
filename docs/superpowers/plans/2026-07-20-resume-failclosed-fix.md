# Resume Fail-Closed Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `archfrican-resume.service` from retrying (and failing) on every single boot forever
once its fail-closed threshold is hit, by removing sudo from the critical "stop retrying" path
entirely, and remediate machines already stuck in the loop.

**Architecture:** `lib/resume-guard.sh` moves its attempt counter and adds a new "stop retrying"
marker to user-owned XDG state (never root-owned `/var/lib/archfrican`), so writing them never
depends on sudo. `templates/archfrican-resume.service` gains a `ConditionPathExists=!<marker>` —
systemd itself (already root, no sudo needed) refuses to start the unit once that marker exists,
replacing `sudo systemctl disable` as the load-bearing "never again" mechanism on both the success
and give-up paths. A new migration (`migrations/0003-...`) remediates machines already stuck in the
broken retry loop, since it runs from `archfrican-update`'s interactive (real sudo) context.

**Tech Stack:** Bash (`set -uo pipefail`/`set -euo pipefail`), systemd unit file syntax, the
existing fixture-based bash unit test pattern (`tests/unit/*.sh`), the existing `migrations/NNNN-slug.sh`
convention.

## Global Constraints

- Full spec: `docs/superpowers/specs/2026-07-20-resume-failclosed-fix-design.md`.
- **The marker path is a shared constant across tasks — it must be byte-identical everywhere it
  appears**: `${XDG_STATE_HOME:-$HOME/.local/state}/archfrican/resume-stopped` in
  `lib/resume-guard.sh` and `/home/@USER@/.local/state/archfrican/resume-stopped` in
  `templates/archfrican-resume.service` (the unit file hardcodes the non-XDG-var default, since
  `ConditionPathExists=` cannot expand shell variables — see the spec's "Nota de consistencia").
- Confirmed via `man systemd.unit`: multiple `ConditionPathExists=` lines in the same unit are
  combined with a logical AND by default (not OR — OR only applies to the `|`-prefixed "triggering
  condition" variant, which this plan does not use). The existing
  `ConditionPathExists=/home/@USER@/.archfrican/install.sh` line and the new negated one both apply.
- The counter/marker mechanism must never require sudo to read, write, or remove — only the
  legitimately-privileged install steps themselves (unchanged, out of scope) still use sudo.
- `ARCHFRICAN_RESUME_MAX_BOOTS` (default 5) and the counter-increment logic are unchanged — only the
  "what happens when exceeded" mechanism changes.
- `migrations/0003-fix-resume-failclosed-loop.sh` must be idempotent and a no-op on a fresh
  system/CI sandbox (no real systemd, no real `/etc/sudoers.d`) — follow the exact pattern already
  used by `migrations/0002-greetd-to-sddm.sh` (`if systemctl is-enabled --quiet X 2>/dev/null; then
  ... else ...`), which already survives the `migrations-idempotent` CI job's no-systemd sandbox.
- Every script edited/created must pass `bash -n`.
- Actually running the new migration against this machine's real, currently-broken
  `archfrican-resume.service` (a live-system change, even though the effect is "stop a thing that's
  already failing") is a manual step for the user to run themselves — not something a task
  automates. See Task 4.

---

### Task 1: Fix `lib/resume-guard.sh` (TDD: test first)

**Files:**
- Modify: `lib/resume-guard.sh` (full rewrite of the counter/marker logic, lines 12-33)
- Create: `tests/unit/resume-guard.sh`
- Modify: `.github/workflows/ci.yml:326-333` (add the new test to `unit-logic`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the marker filename `resume-stopped` (inside
  `${XDG_STATE_HOME:-$HOME/.local/state}/archfrican/`) — Task 2's unit-file condition and Task 3's
  migration both reference this exact filename literally.

- [ ] **Step 1: Confirm the current exact content of `lib/resume-guard.sh`**

Run: `cat lib/resume-guard.sh`

Expected: matches the file exactly as quoted in the spec's "Contexto" section — 34 lines, ending in
`sudo systemctl disable archfrican-resume.service 2>/dev/null || true` then `exit 1` then `fi` then
`exit 0`. If it doesn't match, STOP and re-read before proceeding — something changed concurrently.

- [ ] **Step 2: Write the failing test**

Create `tests/unit/resume-guard.sh`:

```bash
#!/usr/bin/env bash
# Unit test for lib/resume-guard.sh's counter + fail-closed marker logic. Fixture-based — points
# ARCHFRICAN_STATE_DIR at a temp dir and stubs sudo, so it needs NO root and runs in CI. Covers the
# bug this script exists to prevent: the "stop retrying" decision must NEVER depend on sudo
# succeeding, or a machine whose NOPASSWD grant is already gone retries (and fails) forever.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

run_guard() {                     # run_guard <fresh-state-dir> -> sets RC to resume-guard.sh's exit code
  (
    export ARCHFRICAN_STATE_DIR="$1"
    sudo(){ return 1; }            # stub: sudo always FAILS (simulates the exact broken-grant scenario)
    export -f sudo
    bash "$ROOT/lib/resume-guard.sh"
  )
  RC=$?
}

# ---- 1. counter increments across repeated calls, no sudo needed ---------------------------------
state1="$(mktemp -d)"
for i in 1 2 3; do run_guard "$state1"; done
n="$(cat "$state1/resume-attempts" 2>/dev/null || echo MISSING)"
if [ "$n" = 3 ]; then _ok "counter reaches 3 after 3 calls, written without sudo"; else _no "counter=$n, expected 3"; fi
[ -e "$state1/resume-stopped" ] && _no "marker created too early (n=3, MAX defaults to 5)" || _ok "no marker yet at n=3"

# ---- 2. exceeding MAX creates the marker BEFORE any sudo cleanup, and exits 1 ---------------------
state2="$(mktemp -d)"
for i in 1 2 3 4 5 6; do run_guard "$state2"; done
[ "$RC" -eq 1 ] && _ok "6th call (n=6 > MAX=5) exits 1" || _no "6th call exit code = $RC, expected 1"
[ -e "$state2/resume-stopped" ] && _ok "marker exists after exceeding MAX, with sudo fully stubbed out" \
                                 || _no "marker MISSING — the fail-closed path still silently depends on sudo"

# ---- 3. a fresh call after the marker exists still increments harmlessly (systemd's own Condition,
#         not this script, is what actually stops future runs — this only proves the script itself
#         never re-derives "should I run" from anything requiring privilege) --------------------------
run_guard "$state2"
[ -e "$state2/resume-stopped" ] && _ok "marker persists across a subsequent call" || _no "marker disappeared"

rm -rf "$state1" "$state2"
printf '\nresume-guard unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
```

- [ ] **Step 3: Run it to confirm it fails against the CURRENT (unfixed) `lib/resume-guard.sh`**

Run: `bash tests/unit/resume-guard.sh`

Expected: FAILs at least the "marker exists after exceeding MAX" assertion — the current script
never creates any `resume-stopped` file at all (it doesn't exist as a concept yet), and separately,
the current script writes the counter via `sudo tee` — with `sudo` stubbed to a no-op, the counter
write vanishes too, so several assertions should fail. Confirm you see `FAIL` lines before proceeding
— if the test passes against the unfixed script, the test itself is wrong.

- [ ] **Step 4: Rewrite `lib/resume-guard.sh`**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# First-boot resume fail-safe (ExecStartPre of templates/archfrican-resume.service).
#
# WHY: the resume installs a temporary `NOPASSWD: ALL` sudoers drop-in
# (/etc/sudoers.d/99-archfrican-resume) so the headless first-boot install can use sudo without a
# TTY. On SUCCESS the unit's ExecStartPost touches a marker file (and best-effort removes the
# drop-in) — one boot. But a DETERMINISTIC failure (a package dropped from the repos, etc.) would
# otherwise retry every boot FOREVER with passwordless root left live. This bounds that window: each
# boot bumps a counter in USER-OWNED state (never sudo, so it can never itself be blocked by a
# broken grant); after ARCHFRICAN_RESUME_MAX_BOOTS failed boots it touches the SAME marker file —
# systemd's own ConditionPathExists=! on the unit is what actually stops future boots from starting
# it again, not a sudo call. This is the fix for a real bug: the OLD version tried to
# `sudo systemctl disable` itself here, which depends on the exact grant that may already be gone by
# the time this branch runs — a chicken-and-egg failure that left a machine retrying (and failing)
# every single boot for weeks. Runs as the wheel user; the NOPASSWD grant, when it's live, lets the
# best-effort sudo cleanup lines below actually clean up — but nothing here REQUIRES them to succeed.
set -uo pipefail

MAX="${ARCHFRICAN_RESUME_MAX_BOOTS:-5}"
state="${ARCHFRICAN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/archfrican}"
counter="$state/resume-attempts"
stopped="$state/resume-stopped"
dropin="${ARCHFRICAN_RESUME_SUDOERS:-/etc/sudoers.d/99-archfrican-resume}"

mkdir -p "$state"

n="$(cat "$counter" 2>/dev/null || echo 0)"
case "$n" in ''|*[!0-9]*) n=0 ;; esac          # tolerate a corrupt/absent counter -> start fresh
n=$((n + 1))
printf '%s\n' "$n" > "$counter"                # no sudo -- $state is user-owned, this can never fail on privilege

if [ "$n" -gt "$MAX" ]; then
  echo "archfrican-resume: giving up after $((n - 1)) failed boots — stopping future retries" \
       "(fail-closed). See: journalctl -u archfrican-resume -b" >&2
  touch "$stopped"                             # load-bearing: the unit's own Condition reads this, no sudo needed
  sudo rm -f "$dropin" 2>/dev/null || true      # best-effort cleanup only -- no longer required for correctness
  sudo systemctl disable archfrican-resume.service 2>/dev/null || true
  exit 1
fi
exit 0
```

- [ ] **Step 5: Run the test again to confirm it passes**

Run: `bash tests/unit/resume-guard.sh`

Expected (confirmed via a real dry-run of this exact test against this exact fix while writing this
plan):
```
resume-guard unit test: 5 passed, 0 failed
```

- [ ] **Step 6: Verify syntax**

Run: `bash -n lib/resume-guard.sh && bash -n tests/unit/resume-guard.sh`
Expected: no output, exit code 0.

- [ ] **Step 7: Wire the new test into CI**

Run: `grep -n -A2 "defaults — is_installed" .github/workflows/ci.yml`

Expected (confirm before editing):
```
      - name: defaults — is_installed()/list_category() cli+desktop-file detection (11 providers depend on this)
        run: bash tests/unit/defaults.sh

  modules-list-consistency:
```

Edit `.github/workflows/ci.yml`, replacing:
```yaml
      - name: defaults — is_installed()/list_category() cli+desktop-file detection (11 providers depend on this)
        run: bash tests/unit/defaults.sh

  modules-list-consistency:
```
with:
```yaml
      - name: defaults — is_installed()/list_category() cli+desktop-file detection (11 providers depend on this)
        run: bash tests/unit/defaults.sh
      - name: resume-guard — counter/marker never depend on sudo succeeding (the fail-closed bug)
        run: bash tests/unit/resume-guard.sh

  modules-list-consistency:
```

- [ ] **Step 8: Verify the CI edit**

Run: `git diff .github/workflows/ci.yml`

Expected: exactly one new `- name:`/`run:` pair added (6 spaces before `- name:`, 8 spaces before
`run:` — matching every sibling step in the same job), no other line changed, and the
`modules-list-consistency:` job header still follows immediately after with its original 2-space
indentation.

- [ ] **Step 9: Commit**

```bash
chmod +x tests/unit/resume-guard.sh
git add lib/resume-guard.sh tests/unit/resume-guard.sh .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
fix(resume): stop the fail-closed retry loop from depending on sudo

Confirmed live via 3 weeks of journalctl history on the daily
driver: the old fail-closed branch tried to `sudo systemctl
disable` itself, which depends on the exact NOPASSWD grant that may
already be gone by the time that branch runs -- a chicken-and-egg
failure that left the unit retrying (and failing) on every single
boot since it first hit the cap. The counter and a new
"stop retrying" marker move to user-owned XDG state, written
without sudo, so they can never be blocked by a broken grant.
EOF
)"
```

---

### Task 2: Add the systemd Condition to `templates/archfrican-resume.service`

**Files:**
- Modify: `templates/archfrican-resume.service`

**Interfaces:**
- Consumes: the marker filename `resume-stopped` produced by Task 1 — must match byte-for-byte.
- Produces: nothing further tasks depend on.

- [ ] **Step 1: Confirm the current exact content**

Run: `cat templates/archfrican-resume.service`

Expected: matches the file exactly as quoted in the spec's "Contexto" section — 41 lines. If it
doesn't match, STOP and re-read before proceeding.

- [ ] **Step 2: Add the negated Condition and update the header comment**

Edit `templates/archfrican-resume.service`, replacing:
```ini
# Lifecycle: runs ONCE as the wheel user. phase 2 is non-interactive here
# (ARCHFRICAN_NONINTERACTIVE=1, no TTY) so it reads ~/.archfrican-answers instead
# of prompting. On SUCCESS the ExecStartPost lines disable this unit and remove the
# temporary NOPASSWD sudoers drop-in — so the elevated window is exactly one boot.
# On failure it retries next boot (phase-2 .done checkpoints make that safe). The
# elevated window is BOUNDED: ExecStartPre (lib/resume-guard.sh) counts boots and,
# after ARCHFRICAN_RESUME_MAX_BOOTS (default 5), drops the NOPASSWD drop-in and
# disables the unit — so passwordless root can never linger on a permanently-failing
# install (fail-closed). ARCHFRICAN_STRICT_PREFLIGHT=1 makes an unresolvable package
# fail loudly at preflight BEFORE any state change, instead of mid-module.
[Unit]
Description=Archfrican first-boot install (niri desktop + dev layer)
After=network-online.target systemd-user-sessions.service
Wants=network-online.target
ConditionPathExists=/home/@USER@/.archfrican/install.sh
```
with:
```ini
# Lifecycle: runs ONCE as the wheel user. phase 2 is non-interactive here
# (ARCHFRICAN_NONINTERACTIVE=1, no TTY) so it reads ~/.archfrican-answers instead
# of prompting. On SUCCESS the ExecStartPost lines touch a marker file (and best-effort
# disable this unit + remove the temporary NOPASSWD sudoers drop-in) — so the elevated
# window is exactly one boot. On failure it retries next boot (phase-2 .done checkpoints
# make that safe). The elevated window is BOUNDED: ExecStartPre (lib/resume-guard.sh)
# counts boots and, after ARCHFRICAN_RESUME_MAX_BOOTS (default 5), touches the same
# marker file. ConditionPathExists=! below is what actually stops future boots from
# starting this unit again — systemd evaluates it with its own privilege, so (unlike the
# old sudo-systemctl-disable-based approach) it can never be blocked by a broken NOPASSWD
# grant. ARCHFRICAN_STRICT_PREFLIGHT=1 makes an unresolvable package fail loudly at
# preflight BEFORE any state change, instead of mid-module.
[Unit]
Description=Archfrican first-boot install (niri desktop + dev layer)
After=network-online.target systemd-user-sessions.service
Wants=network-online.target
ConditionPathExists=/home/@USER@/.archfrican/install.sh
ConditionPathExists=!/home/@USER@/.local/state/archfrican/resume-stopped
```

- [ ] **Step 3: Update the ExecStartPost lines**

Edit `templates/archfrican-resume.service`, replacing:
```ini
# Fail-safe: bound the elevated retry window — gives up + drops the NOPASSWD grant after N boots.
ExecStartPre=/usr/bin/bash /home/@USER@/.archfrican/lib/resume-guard.sh
ExecStart=/usr/bin/bash /home/@USER@/.archfrican/install.sh
# Order matters: disable while we still have NOPASSWD, then drop NOPASSWD last.
ExecStartPost=/usr/bin/sudo /usr/bin/systemctl disable archfrican-resume.service
ExecStartPost=/usr/bin/sudo /usr/bin/rm -f /etc/sudoers.d/99-archfrican-resume
```
with:
```ini
# Fail-safe: bound the elevated retry window — resume-guard.sh touches the stop marker after N boots.
ExecStartPre=/usr/bin/bash /home/@USER@/.archfrican/lib/resume-guard.sh
ExecStart=/usr/bin/bash /home/@USER@/.archfrican/install.sh
# The marker is what actually stops future boots (via ConditionPathExists=! above, no sudo needed).
# The two sudo lines below are best-effort cleanup only, not required for correctness.
ExecStartPost=/usr/bin/touch /home/@USER@/.local/state/archfrican/resume-stopped
ExecStartPost=/usr/bin/sudo /usr/bin/systemctl disable archfrican-resume.service
ExecStartPost=/usr/bin/sudo /usr/bin/rm -f /etc/sudoers.d/99-archfrican-resume
```

- [ ] **Step 4: Verify the marker path matches Task 1 byte-for-byte**

Run:
```bash
grep -o 'resume-stopped' templates/archfrican-resume.service | sort -u
grep -n 'stopped="' lib/resume-guard.sh
```
Expected: the template's occurrences all say `resume-stopped`, matching the `$state/resume-stopped`
constructed in `lib/resume-guard.sh` (accounting for `$state` resolving to
`${XDG_STATE_HOME:-$HOME/.local/state}/archfrican`, i.e. `/home/<user>/.local/state/archfrican` when
`XDG_STATE_HOME` is unset, which it is inside this unit's own `[Service]` block).

- [ ] **Step 5: Confirm no other line was disturbed**

Run: `git diff templates/archfrican-resume.service`
Expected: only the header comment, the one new `ConditionPathExists=!...` line, and the
`ExecStartPost=` block change — `WorkingDirectory`, `Environment=`, `TimeoutStartSec`, `ExecStart=`,
`[Install]` all unchanged.

- [ ] **Step 6: Commit**

```bash
git add templates/archfrican-resume.service
git commit -m "$(cat <<'EOF'
fix(resume): let systemd's own Condition stop future retries, not sudo

Adds ConditionPathExists=!<marker> so systemd itself (already root,
no sudo needed) refuses to start the unit once lib/resume-guard.sh
has given up. Confirmed against man systemd.unit: multiple
ConditionPathExists= lines on the same unit AND together by
default, so this combines correctly with the existing install.sh
existence check. The two sudo ExecStartPost lines remain as
best-effort cleanup only -- they're no longer what stops the loop.
EOF
)"
```

---

### Task 3: Add the remediation migration for already-stuck machines

**Files:**
- Create: `migrations/0003-fix-resume-failclosed-loop.sh`

**Interfaces:**
- Consumes: the marker filename/path from Task 1 (`${XDG_STATE_HOME:-$HOME/.local/state}/archfrican/resume-stopped`).
- Produces: nothing further tasks depend on. Picked up automatically by the existing
  `migrations-idempotent` CI job and by `lib/migrate.sh::run_migrations` (both already iterate
  `migrations/[0-9]*.sh` generically — no wiring needed beyond creating the file).

- [ ] **Step 1: Confirm the next migration number**

Run: `ls migrations/`
Expected: `0001-resume-sudoers-rename.sh`, `0002-greetd-to-sddm.sh`, `README.md` — confirming `0003`
is the next number. If a `0003-*.sh` already exists, STOP — something else claimed that slot
concurrently; use the next free number instead and adjust this task's filename accordingly.

- [ ] **Step 2: Create the migration**

Create `migrations/0003-fix-resume-failclosed-loop.sh`:

```bash
#!/usr/bin/env bash
# 0003 — stop an archfrican-resume.service stuck retrying every boot forever.
# The fail-closed branch in lib/resume-guard.sh used to depend on `sudo systemctl disable`
# succeeding -- but if the NOPASSWD grant is already gone by the time that branch runs, that call
# silently fails too, and the unit keeps retrying (and failing) on every single boot. This
# migration runs from an interactive archfrican-update context (real sudo), so it can actually
# break the loop: disable the unit if enabled, clean up the stale grant/counter, and write the
# new user-owned marker so a future re-enable still can't restart it (ConditionPathExists=! on
# the unit reads this same marker). No-op on a fresh install or a machine already past this fix.
set -euo pipefail

state="${XDG_STATE_HOME:-$HOME/.local/state}/archfrican"
mkdir -p "$state"

if systemctl is-enabled --quiet archfrican-resume.service 2>/dev/null; then
  sudo systemctl disable archfrican-resume.service
  printf '  \e[32m✓\e[0m disabled archfrican-resume.service (was stuck retrying every boot)\n'
else
  printf '  \e[32m✓\e[0m archfrican-resume.service already disabled (nothing to do)\n'
fi

if [ -e /etc/sudoers.d/99-archfrican-resume ]; then
  sudo rm -f /etc/sudoers.d/99-archfrican-resume
  printf '  \e[32m✓\e[0m removed stale resume sudoers drop-in\n'
fi

if [ -e /var/lib/archfrican/resume-attempts ]; then
  sudo rm -f /var/lib/archfrican/resume-attempts
  printf '  \e[32m✓\e[0m removed stale root-owned attempt counter\n'
fi

touch "$state/resume-stopped"
printf '  \e[32m✓\e[0m wrote %s (blocks any future re-enable)\n' "$state/resume-stopped"
```

- [ ] **Step 3: Make it executable and verify syntax**

Run:
```bash
chmod +x migrations/0003-fix-resume-failclosed-loop.sh
bash -n migrations/0003-fix-resume-failclosed-loop.sh
```
Expected: no output, exit code 0.

- [ ] **Step 4: Dry-run the SCRIPT'S CONTROL FLOW with `systemctl`/`sudo` stubbed out**

**Important:** if you're running this on a machine that already has a real, stuck
`archfrican-resume.service` (like the exact machine this bug was found on), a genuinely
unstubbed run of this migration will try to actually exercise its `sudo`-requiring branches, which
will fail without a real interactive password prompt (that's expected — see Task 4 Step 5 for the
real remediation, which explicitly asks the user first). To validate the script's logic itself
without touching real state or requiring a password, stub both commands:

```bash
bash -c '
  systemctl() { echo "STUB systemctl: $*" >&2; case "$1" in is-enabled) return 1 ;; esac; }
  sudo() { echo "STUB sudo: $*" >&2; }        # note: does NOT re-execute the command — pure no-op stub
  export -f systemctl sudo
  export XDG_STATE_HOME; XDG_STATE_HOME="$(mktemp -d)"
  bash migrations/0003-fix-resume-failclosed-loop.sh
  echo "exit: $?"
  ls "$XDG_STATE_HOME/archfrican/"
'
```
Expected: prints "archfrican-resume.service already disabled (nothing to do)" (the stub always
reports `is-enabled` false), skips both `/etc/sudoers.d/...`/`/var/lib/archfrican/...` blocks if
those paths don't exist on your machine (or logs a no-op `STUB sudo: rm -f ...` if they do — either
way nothing is actually removed, since the stub never re-executes), `exit: 0`, and `ls` shows
`resume-stopped` was created. This only proves the script's control flow is correct — the real
`migrations-idempotent` CI job (a genuinely clean container, no leftover Archfrican state at all)
is what proves the true fresh-system no-op path end to end, the same way it already does for
`migrations/0001` and `0002`.

- [ ] **Step 5: Confirm it's idempotent — run the stubbed dry-run again**

Run the exact same stubbed command from Step 4 a second time (fresh `mktemp -d`, so this checks
the script's own idempotence, not leftover state from the first run).
Expected: identical output shape, `exit: 0` again — no command fails on a second run.

- [ ] **Step 6: Commit**

```bash
git add migrations/0003-fix-resume-failclosed-loop.sh
git commit -m "$(cat <<'EOF'
fix(migrate): remediate machines already stuck in the resume retry loop

Confirmed live: this exact failure has been retrying (and failing)
on every boot for 3 weeks on the daily driver, because the old
fail-closed mechanism's own sudo call was what was broken. This
migration runs from archfrican-update's interactive context (real
sudo), so it can actually disable the stuck unit, clean up the
stale grant + counter, and write the new marker so a future
re-enable still can't restart the loop.
EOF
)"
```

---

### Task 4: End-to-end verification + live remediation instructions

**Files:** none modified — this task runs checks and documents the manual remediation step for the
user (actually disabling the currently-broken unit on this exact machine needs the user's own sudo
password and their explicit go-ahead, same convention as every prior live-system step in this repo).

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing further downstream.

- [ ] **Step 1: Full static re-check of every file this plan touched**

```bash
for f in lib/resume-guard.sh tests/unit/resume-guard.sh migrations/0003-fix-resume-failclosed-loop.sh; do
  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done
```
Expected: `OK:` for all three.

- [ ] **Step 2: Re-run the new unit test**

Run: `bash tests/unit/resume-guard.sh`
Expected: `resume-guard unit test: N passed, 0 failed`.

- [ ] **Step 3: Re-run the existing test suites to confirm nothing regressed**

```bash
bash tests/unit/manifest.sh | tail -3
bash tests/unit/detect-gpu.sh | tail -3
```
Expected: `manifest unit test: 9 passed, 0 failed` and `detect-gpu unit test: 13 passed, 0 failed`
(this plan doesn't touch either file — if the counts differ, something else changed concurrently;
investigate before continuing).

- [ ] **Step 4: Confirm the migration is discovered correctly**

The full `run_migrations` flow (via `lib/migrate.sh`) itself calls `sudo install -d`/`sudo tee` to
persist its own state-version marker, REGARDLESS of `ARCHFRICAN_STATE_DIR` overrides — that's fine
on a real GitHub Actions runner (passwordless sudo is already configured there) or a real machine
(interactive password prompt), but it means running the FULL chain end-to-end isn't reproducible in
a plain non-interactive shell without passwordless sudo. Keep this step to what's actually safe and
meaningful here — confirming discovery, not full execution:

```bash
REPO_ROOT="$PWD" bash -c '
  source lib/common.sh; source lib/migrate.sh
  latest="$(_mig_latest)"
  [ "$latest" -ge 3 ] && echo "OK: latest migration is $latest (>= 3)" || echo "FAIL: expected >= 3, got $latest"
'
```
Expected: `OK: latest migration is 3 (>= 3)`. The full apply-and-verify-idempotent proof is the
existing `migrations-idempotent` CI job, which already covers this generically for every file
matching `migrations/[0-9]*.sh` — it will pick up `0003` automatically once this task's commit
lands, the same way it already covers `0001` and `0002`.

- [ ] **Step 5: Manual live remediation on this machine (ask the user first — do not run automatically)**

This machine is the exact one the spec's "Contexto" section describes as currently stuck (verified:
`archfrican-resume.service` has been retrying every boot since 2026-06-30). Closing the loop for
real requires the user's own sudo password, so it's a manual step, not something a task automates:

```bash
git -C ~/.archfrican pull            # or archfrican-update, once this branch is merged/pushed
bash ~/.archfrican/migrations/0003-fix-resume-failclosed-loop.sh
```
**Do NOT prefix that whole command with `sudo`** — run it as your regular user. The script itself
only escalates the two specific lines that need it (`sudo systemctl disable`, `sudo rm -f`, each
prompting for your password individually); `mkdir -p`/`touch` must run as YOU, since they write to
your own `$HOME` — wrapping the whole script in `sudo bash ...` would run everything as root and
write the marker to `/root/.local/state/archfrican/` instead of yours, silently defeating the fix.

```bash
systemctl is-enabled archfrican-resume.service   # expect: disabled
ls ~/.local/state/archfrican/resume-stopped      # expect: file exists
```

Then, at the NEXT reboot, confirm the loop is actually broken:
```bash
journalctl -u archfrican-resume.service -b       # expect: empty -- systemd's Condition skipped it entirely
```

- [ ] **Step 6: No commit for this task** (verification-only; nothing to add to git).
