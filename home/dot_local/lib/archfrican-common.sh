#!/usr/bin/env bash
# archfrican-common.sh — shared have()/note()/confirm() for the archfrican-* helper scripts.
# Sourced, not executed: `source "$(dirname "$0")/../lib/archfrican-common.sh"`.

have() { command -v "$1" >/dev/null 2>&1; }

note() { have notify-send && notify-send "Archfrican" "$1" || echo "$1"; }

# confirm "texto de la acción" ["etiqueta del prompt"] -> 0 si el usuario confirma, 1 si cancela/Escape
confirm() {
  local action="$1" label="${2:-confirmar}" c
  c="$(printf 'Sí, %s\nCancelar\n' "$action" | fuzzel --dmenu --prompt "  $label  ")" || return 1
  case "$c" in "Sí,"*) return 0 ;; *) return 1 ;; esac
}
