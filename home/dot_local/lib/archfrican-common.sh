#!/usr/bin/env bash
# archfrican-common.sh — shared have()/note()/confirm()/toml_menu_* for the archfrican-* helper
# scripts. Sourced, not executed: `source "$(dirname "$0")/../lib/archfrican-common.sh"`.

have() { command -v "$1" >/dev/null 2>&1; }

note() { have notify-send && notify-send "Archfrican" "$1" || echo "$1"; }

# confirm "texto de la acción" ["etiqueta del prompt"] -> 0 si el usuario confirma, 1 si cancela/Escape
confirm() {
  local action="$1" label="${2:-confirmar}" c
  c="$(printf 'Sí, %s\nCancelar\n' "$action" | fuzzel --dmenu --prompt "  $label  ")" || return 1
  case "$c" in "Sí,"*) return 0 ;; *) return 1 ;; esac
}

# Walker/elephant native-menu availability — the ONE definition of "walker is up" (walker on
# PATH AND the elephant daemon actually serving its baseline provider). Every script that
# offers a native menu or a walker dmenu must gate on this, never on its own variant.
walker_native() {
  have walker && elephant listproviders 2>/dev/null | grep -q '^desktopapplications$'
}

# walker_menu <name> — exec the native menus:<name> (never returns) when Walker is up; plain
# return otherwise so the caller falls through to its fuzzel fallback. The `if` keeps the
# probe's failure from tripping `set -e` in callers.
walker_menu() { if walker_native; then exec walker -m "menus:$1"; fi; }

# toml_menu_list <file.toml> — print each [[entries]]' "text" field, one per line, in file order.
# Reads the same static menus/*.toml the native Walker/elephant provider reads, so a fuzzel fallback
# built on these two functions can never drift from the native menu — one file, two renderers.
toml_menu_list() {
  python3 -c '
import tomllib, sys
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
for e in data.get("entries", []):
    print(e.get("text", ""))
' "$1"
}

# toml_menu_action <file.toml> <selected-text> — print one TSV line for the entry whose "text"
# matches: "run\t<cmd>", "terminal\t<cmd>" (same as run, but the caller should open it in a terminal —
# mirrors the toml's own terminal = true), or "submenu\t<name>". Prints nothing if not found.
toml_menu_action() {
  python3 -c '
import tomllib, sys
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
sel = sys.argv[2]
for e in data.get("entries", []):
    if e.get("text") != sel:
        continue
    if "submenu" in e:
        print("submenu\t" + e["submenu"])
    elif "actions" in e and "run" in e["actions"]:
        kind = "terminal" if e.get("terminal") else "run"
        print(kind + "\t" + e["actions"]["run"])
    break
' "$1" "$2"
}
