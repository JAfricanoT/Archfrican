#!/usr/bin/env bash
# 0001 — drop the stale first-boot-resume sudoers drop-in left by pre-rename installs.
# The resume NOPASSWD drop-in was renamed 00-archfrican-resume -> 99-archfrican-resume (sudoers is
# last-match-wins + lexical order, and the 00- name sorted BEFORE 10-wheel, so the password rule
# won and headless sudo failed). A machine installed before that fix may still carry the stale 00-
# file; remove it. No-op on anything installed after the rename — and on every fresh install (which
# never runs migrations at all). Idempotent: safe to run repeatedly.
set -euo pipefail
stale=/etc/sudoers.d/00-archfrican-resume
if [ -e "$stale" ]; then
  sudo rm -f "$stale"
  printf '  \e[32m✓\e[0m removed stale %s\n' "$stale"
else
  printf '  \e[32m✓\e[0m no stale resume sudoers (nothing to do)\n'
fi
