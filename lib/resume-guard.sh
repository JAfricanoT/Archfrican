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
