#!/usr/bin/env bash
# Root's login shell profile for the Archfrican live environment.
# Loaded by getty@tty1 auto-login (inherited from archiso releng).

[[ -f /etc/profile ]] && . /etc/profile
[[ -f ~/.bashrc    ]] && . ~/.bashrc

# Auto-launch the installer. The repo is pre-bundled at /root/.archfrican by build-iso.sh,
# so install.sh finds lib/common.sh (in_repo() == true) and skips the GitHub clone.
# is_iso() detects /run/archiso → run_phase1() starts immediately.
# ARCHFRICAN_REEXEC guard prevents a re-exec loop if the installer re-execs itself.
if [[ -f /root/.archfrican/install.sh ]] && [[ -z "${ARCHFRICAN_REEXEC:-}" ]]; then
  exec bash /root/.archfrican/install.sh
fi
