#!/usr/bin/env bash
# 0002 — switch the login from greetd to SDDM on an already-installed machine.
# The module re-converge ENABLES sddm, but convergence only adds — it never disables the old display
# manager. Two display managers both grabbing the seat = a broken login, so disabling greetd is OLD
# state to undo here. No-op on a fresh install (greetd was never enabled there) and idempotent: safe
# to run repeatedly. The stale greetd/greetd-tuigreet packages are left to `archfrican-update --prune`
# (they dropped out of the desired manifest), not removed here.
set -euo pipefail

if systemctl is-enabled --quiet greetd.service 2>/dev/null; then
  sudo systemctl disable greetd.service
  printf '  \e[32m✓\e[0m disabled greetd.service (SDDM now owns the login)\n'
else
  printf '  \e[32m✓\e[0m greetd not enabled (nothing to disable)\n'
fi

# Drop the old greetd config so a future greetd reinstall can't accidentally re-grab the seat.
if [ -e /etc/greetd/config.toml ]; then
  sudo rm -f /etc/greetd/config.toml
  printf '  \e[32m✓\e[0m removed stale /etc/greetd/config.toml\n'
fi
