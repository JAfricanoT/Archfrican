#!/usr/bin/env bash
# First-boot resume fail-safe (ExecStartPre of templates/archfrican-resume.service).
#
# WHY: the resume installs a temporary `NOPASSWD: ALL` sudoers drop-in
# (/etc/sudoers.d/99-archfrican-resume) so the headless first-boot install can use sudo without a
# TTY. On SUCCESS the unit's ExecStartPost removes it — one boot. But a DETERMINISTIC failure (a
# package dropped from the repos, etc.) would otherwise retry every boot FOREVER with passwordless
# root left live. This bounds that window: each boot bumps a counter; after ARCHFRICAN_RESUME_MAX_BOOTS
# failed boots it removes the drop-in and disables the unit, then exits non-zero so ExecStart is
# skipped — i.e. it fails CLOSED (no lingering passwordless root). The happy path never hits the cap
# (a successful resume disables the unit first). Runs as the wheel user with the NOPASSWD grant live.
set -uo pipefail

MAX="${ARCHFRICAN_RESUME_MAX_BOOTS:-5}"
state="${ARCHFRICAN_STATE_DIR:-/var/lib/archfrican}"
counter="$state/resume-attempts"
dropin="${ARCHFRICAN_RESUME_SUDOERS:-/etc/sudoers.d/99-archfrican-resume}"

sudo install -d -m 0755 "$state" 2>/dev/null || true

n="$(cat "$counter" 2>/dev/null || echo 0)"
case "$n" in ''|*[!0-9]*) n=0 ;; esac          # tolerate a corrupt/absent counter -> start fresh
n=$((n + 1))
printf '%s\n' "$n" | sudo tee "$counter" >/dev/null 2>&1 || true

if [ "$n" -gt "$MAX" ]; then
  echo "archfrican-resume: giving up after $((n - 1)) failed boots — removing the temporary" \
       "NOPASSWD grant and disabling the unit (fail-closed). See: journalctl -u archfrican-resume -b" >&2
  sudo rm -f "$dropin"
  sudo systemctl disable archfrican-resume.service 2>/dev/null || true
  exit 1
fi
exit 0
