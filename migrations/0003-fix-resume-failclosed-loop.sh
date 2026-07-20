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

# Load-bearing action first, unconditionally, before any sudo call: this is the
# one guaranteed-no-privilege step that actually stops the retry loop
# (ConditionPathExists=! on the unit reads this same marker). Everything below
# is best-effort cleanup that must not gate this.
touch "$state/resume-stopped"
printf '  \e[32m✓\e[0m wrote %s (blocks any future re-enable)\n' "$state/resume-stopped"

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
