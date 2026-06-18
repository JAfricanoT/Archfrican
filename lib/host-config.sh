#!/usr/bin/env bash
# Apply the wizard's host/user choices on a BOOTED base, idempotently. Sourced
# after lib/common.sh (reuses write_system_file/log/ok/warn/die). systemd-* tools
# (hostnamectl/timedatectl/localectl) are themselves idempotent.

apply_hostname() {                 # apply_hostname <name>
  local h="$1"; [ -n "$h" ] || return 0
  sudo hostnamectl set-hostname "$h"
  if ! grep -qE "^127\.0\.1\.1[[:space:]]+$h\b" /etc/hosts 2>/dev/null; then
    printf '127.0.1.1\t%s\n' "$h" | sudo tee -a /etc/hosts >/dev/null
  fi
  ok "hostname -> $h"
}

apply_user() {                     # apply_user <name> <password-or-empty>
  local u="$1" pw="$2"; [ -n "$u" ] || return 0
  if ! id -u "$u" &>/dev/null; then
    sudo useradd -m -G wheel -s "$(command -v zsh || echo /bin/bash)" "$u"; ok "created user $u"
  else
    sudo usermod -aG wheel "$u"; ok "user $u present (ensured wheel)"
  fi
  # wheel -> sudo via a validated drop-in (reuses write_system_file).
  printf '%%wheel ALL=(ALL:ALL) ALL\n' | write_system_file /etc/sudoers.d/10-archfrican-wheel 0440
  sudo visudo -cf /etc/sudoers.d/10-archfrican-wheel >/dev/null \
    || die "sudoers drop-in invalid — refusing to leave a broken sudo"
  # Only set a password when one was supplied; never blank an existing one. (stdin only.)
  [ -n "$pw" ] && { printf '%s:%s' "$u" "$pw" | sudo chpasswd; ok "password set for $u"; }
  return 0
}

apply_timezone() {                 # apply_timezone <tz>
  local tz="$1"; [ -n "$tz" ] || return 0
  sudo timedatectl set-timezone "$tz"; ok "timezone -> $tz"
}

apply_locale_keyboard() {          # apply_locale_keyboard <locale> <xkb-layout> <vconsole-keymap>
  local loc="$1" xkb="$2" vc="$3"
  if [ -n "$loc" ]; then
    sudo sed -i "s/^#\\s*\\(${loc}\\b.*\\)/\\1/" /etc/locale.gen
    sudo locale-gen
    sudo localectl set-locale "LANG=$loc"; ok "locale -> $loc"
  fi
  [ -n "$xkb" ] && { best_effort sudo localectl set-x11-keymap "$xkb"; ok "x11 keymap -> $xkb"; }
  [ -n "$vc" ]  && { best_effort sudo localectl set-keymap "$vc";       ok "vconsole keymap -> $vc"; }
  return 0
}
