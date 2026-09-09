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

# THE default theme — what a machine wears while ~/.config/.archfrican-theme doesn't exist yet
# (first boot, cleared state). lib/common.sh carries the same constant for the installer side;
# keep the two identical. A few spots can't source this bash lib and carry the literal —
# keep them in sync too: home/run_after_99-apply-theme.sh.tmpl, menus/setup.toml.tmpl, and
# the POSIX-sh darkman hooks (share/dark-mode.d + light-mode.d).
ARCHFRICAN_DEFAULT_THEME=archfrican-dark
theme_now() { cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo "$ARCHFRICAN_DEFAULT_THEME"; }

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

# The four .desktop application dirs (native + flatpak, system + user) — shared by every
# script that enumerates launchable apps.
ARCHFRICAN_APPDIRS=(/usr/share/applications "$HOME/.local/share/applications"
                    /var/lib/flatpak/exports/share/applications
                    "$HOME/.local/share/flatpak/exports/share/applications")

# list_desktop_apps — one line per VISIBLE app: "Name<TAB>file.desktop<TAB>Icon" (Icon may be
# empty; Name falls back to the file name). Unsorted: each consumer picks its own ordering.
#
# ONE visibility filter for the whole OS — and that has to mean the same four keys Walker's
# backend applies, or the two launcher surfaces disagree about what exists. elephant hides on
# NoDisplay, Hidden, NotShowIn and OnlyShowIn (desktopapplications/query.go:37, splitting
# XDG_CURRENT_DESKTOP on ":"); this used to check only the first two, so a session-scoped entry
# was correctly absent from the Walker grid and still listed in the fuzzel fallback. That gap is
# what makes NotShowIn usable to keep the control surfaces out of the app list without hiding
# them from a Plasma session, which NoDisplay cannot do.
#
# Group-aware, which the grep it replaces was not: a NoDisplay inside a [Desktop Action …] block
# belongs to that action, not to the app, and must not hide the app. Matching is exact and
# case-sensitive on the desktop names, the way elephant compares them.
#
# One awk over every file rather than three processes per file. At 83 .desktop entries that was
# ~250 forks and ~320 ms on the ⌘+Space fallback path — dead time before the launcher draws, and
# it grows with every Flatpak installed.
list_desktop_apps() {
  local d f files=()
  for d in "${ARCHFRICAN_APPDIRS[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.desktop; do [ -e "$f" ] && files+=("$f"); done
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  awk -v cur="${XDG_CURRENT_DESKTOP:-}" '
    BEGIN { nd = split(cur, DESK, ":") }
    function matches(list,   i, j, m, T) {      # does any ";"-separated token name this desktop?
      m = split(list, T, ";")
      for (i = 1; i <= m; i++) if (T[i] != "")
        for (j = 1; j <= nd; j++) if (T[i] == DESK[j]) return 1
      return 0
    }
    function flush(   base) {
      if (path == "" || hidden || nodisplay) return
      if (notin != "" && matches(notin)) return
      if (only  != "" && !matches(only))  return
      base = path; sub(/^.*\//, "", base)
      if (name == "") { name = base; sub(/\.desktop$/, "", name) }
      printf "%s\t%s\t%s\n", name, base, icon
    }
    function val(   v) { v = $0; sub(/^[^=]*=/, "", v); return v }
    FNR == 1 { flush(); path = FILENAME; ingroup = 0
               name = ""; icon = ""; hidden = 0; nodisplay = 0; only = ""; notin = "" }
    /^[[:space:]]*\[/ { ingroup = ($0 ~ /^[[:space:]]*\[Desktop Entry\][[:space:]]*$/); next }
    !ingroup { next }
    /^[[:space:]]*Name[[:space:]]*=/       { if (name == "") name = val(); next }
    /^[[:space:]]*Icon[[:space:]]*=/       { if (icon == "") icon = val(); next }
    /^[[:space:]]*NoDisplay[[:space:]]*=/  { if (tolower(val()) ~ /^[[:space:]]*true/) nodisplay = 1; next }
    /^[[:space:]]*Hidden[[:space:]]*=/     { if (tolower(val()) ~ /^[[:space:]]*true/) hidden = 1; next }
    /^[[:space:]]*OnlyShowIn[[:space:]]*=/ { only  = val(); next }
    /^[[:space:]]*NotShowIn[[:space:]]*=/  { notin = val(); next }
    END { flush() }
  ' "${files[@]}"
}

# Theme picker (fuzzel) over the clone's themes/ — honors ARCHFRICAN_ROOT (dev checkout) the
# way theme-switch itself does, so every picker offers the SAME theme set. Mirrors the live
# discovery menus/themes.lua does natively. Returns nonzero when the user cancels.
pick_theme() {
  local root="${ARCHFRICAN_ROOT:-$HOME/.archfrican}" t
  t="$(for d in "$root"/themes/*/; do [ -d "$d" ] && basename "$d"; done \
      | fuzzel --dmenu --prompt '  tema  ')" && [ -n "$t" ] && theme-switch "$t"
}

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
