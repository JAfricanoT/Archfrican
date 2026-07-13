#!/usr/bin/env bash
# Environment detection — the ONE canonical place that decides ISO-live vs
# booted-base and where to clone. Sourced after lib/common.sh.

# Arch live ISO marker: /run/archiso is the archiso airootfs run dir, present only on the
# live medium (confirmed on the current Arch ISO).
is_iso() { [ -d /run/archiso ]; }

# Where the self-clone lands. ISO -> /root (you are root); booted -> $HOME.
# (git bootstrap lives in install.sh's _ensure_git — it must exist before lib/ is on disk.)
clone_dest() { if is_iso; then echo /root/.archfrican; else echo "$HOME/.archfrican"; fi; }
