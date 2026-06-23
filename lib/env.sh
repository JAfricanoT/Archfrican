#!/usr/bin/env bash
# Environment detection — the ONE canonical place that decides ISO-live vs
# booted-base and where to clone. Sourced after lib/common.sh.

# Arch live ISO marker: /run/archiso is the archiso airootfs run dir, present only on the
# live medium (confirmed on the current Arch ISO).
is_iso() { [ -d /run/archiso ]; }

# Where the self-clone lands. ISO -> /root (you are root); booted -> $HOME.
clone_dest() { if is_iso; then echo /root/.archfrican; else echo "$HOME/.archfrican"; fi; }

# Make sure git exists before the self-clone (root on ISO, sudo when booted).
ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  if [ "$EUID" -eq 0 ]; then pacman -Sy --needed --noconfirm git
  else sudo pacman -Sy --needed --noconfirm git; fi
}
