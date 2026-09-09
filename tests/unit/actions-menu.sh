#!/usr/bin/env bash
# Unit test for the archfrican-actions fuzzel fallback — the menu people get when Walker/elephant
# are absent. Nothing else in CI exercises it: the native path exec's into Walker on line 16, so a
# regression here is invisible on a healthy desktop and only shows up on the machines least able to
# cope with it.
#
# Black-box: builds a throwaway bin/ + lib/ + menus/ tree, stubs fuzzel with a scripted answer queue
# that also records every list it was asked to draw, and asserts on what got drawn, what ran, and the
# exit status. Set ACTIONS_SRC to point at a different copy of the script (handy for checking that a
# case really fails against the version that had the bug).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"/{bin,lib,menus,fake,themes/adl-dark,themes/adl-light,xdgcfg/elephant}
cp "${ACTIONS_SRC:-$ROOT/home/dot_local/bin/executable_archfrican-actions}" "$WORK/bin/archfrican-actions"
cp "$ROOT/home/dot_local/lib/archfrican-common.sh" "$WORK/lib/archfrican-common.sh"
chmod +x "$WORK/bin/archfrican-actions"
ln -sfn "$WORK/menus" "$WORK/xdgcfg/elephant/menus"

# Same shape as the real menus/*.toml: `submenu` is a top-level key on the entry, `run` lives under
# `actions`. Kept minimal — this test is about navigation, not about the real menu's contents.
cat > "$WORK/menus/actions.toml" <<'TOML'
name = "actions"
[[entries]]
text = "Bloquear pantalla"
actions = { run = "echo LOCKED" }
[[entries]]
text = "Accion que falla"
actions = { run = "exit 3" }
[[entries]]
text = "Pantallas"
submenu = "pantallas"
[[entries]]
text = "Cambiar tema"
submenu = "themes"
[[entries]]
text = "Submenu roto"
submenu = "noexiste"
TOML
cat > "$WORK/menus/pantallas.toml" <<'TOML'
name = "pantallas"
parent = "actions"
[[entries]]
text = "Organizar pantallas"
actions = { run = "echo DISPLAYS" }
TOML

# fuzzel stub: append the list it was handed to $DRAW, then pop the next scripted answer off $Q.
cat > "$WORK/fake/fuzzel" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "--- DRAW ---" >> "$DRAW"; cat >> "$DRAW"
ans="$(head -1 "$Q")"; sed -i 1d "$Q"
[ "$ans" = "@CANCEL" ] && exit 1
printf '%s\n' "$ans"
STUB
# walker/elephant must fail so walker_menu falls through to the fallback instead of exec'ing away.
for c in walker elephant notify-send ghostty; do printf '#!/bin/sh\nexit 1\n' > "$WORK/fake/$c"; done
printf '#!/bin/sh\necho "THEME:$1" >> "$RAN_LOG"\nexit 0\n' > "$WORK/fake/theme-switch"
chmod +x "$WORK/fake"/*

RC=0
run() {                            # run <answer>... ; sets RC, fills draw.log / ran.log / out.log
  export DRAW="$WORK/draw.log" Q="$WORK/queue" RAN_LOG="$WORK/ran.log"
  : > "$DRAW"; : > "$RAN_LOG"; printf '%s\n' "$@" > "$Q"
  PATH="$WORK/fake:$PATH" HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/xdgcfg" \
    ARCHFRICAN_ROOT="$WORK" bash "$WORK/bin/archfrican-actions" > "$WORK/out.log" 2>&1
  RC=$?
}
draws() { grep -c -- '--- DRAW ---' "$WORK/draw.log"; }
nth_draw() { awk -v n="$1" '/--- DRAW ---/{i++; next} i==n' "$WORK/draw.log"; }

# ---- 1. the root menu offers no way "back" — there is nothing above it -----------------------------
run "@CANCEL"
if ! grep -q 'Volver' "$WORK/draw.log"; then _ok "root menu offers no back entry"
else _no "root menu drew a back entry"; fi
if [ "$RC" = 0 ]; then _ok "cancelling at the root exits 0"; else _no "cancelling at the root exited $RC"; fi

# ---- 2. a submenu offers one, and it is LAST ------------------------------------------------------
# fuzzel preselects the first row. A back entry at the top means the first Enter after opening a
# submenu walks straight back out of it — a trapdoor where an affordance was intended.
run "Pantallas" "@CANCEL"
sub="$(nth_draw 2)"
if [ "$(printf '%s\n' "$sub" | tail -1)" = "── Volver" ]; then _ok "the back entry is the LAST row of a submenu"
else _no "last row of the submenu is [$(printf '%s\n' "$sub" | tail -1)], expected '── Volver'"; fi
if [ "$(printf '%s\n' "$sub" | head -1)" = "Organizar pantallas" ]; then _ok "the preselected row is a real action, not the back entry"
else _no "first row of the submenu is [$(printf '%s\n' "$sub" | head -1)]"; fi

# ---- 3. choosing it re-shows the list you came from -----------------------------------------------
run "Pantallas" "── Volver" "@CANCEL"
if [ "$(draws)" = 3 ]; then _ok "back re-shows the parent list"
else _no "back drew $(draws) menus, expected 3 (root, submenu, root again)"; fi

# ---- 4. running an entry closes every level --------------------------------------------------------
run "Pantallas" "Organizar pantallas"
if grep -q DISPLAYS "$WORK/out.log" && [ "$(draws)" = 2 ]; then _ok "running an entry inside a submenu closes the whole menu"
else _no "run-in-submenu: out=[$(cat "$WORK/out.log")] draws=$(draws), expected the action to run and 2 draws"; fi

# ---- 5. applying a theme is running an entry, so it closes too --------------------------------------
# The Lua-backed "Cambiar tema" is the one submenu that isn't a sibling .toml, and it was the one
# branch that never reported back: the theme applied and then the root menu reappeared on top of the
# freshly re-themed desktop, unlike every other action.
run "Cambiar tema" "adl-light"
if grep -q 'THEME:adl-light' "$WORK/ran.log" && [ "$(draws)" = 2 ]; then _ok "applying a theme closes the menu, like any other entry"
else _no "theme apply: ran=[$(cat "$WORK/ran.log")] draws=$(draws), expected the theme applied and 2 draws"; fi

# ---- 6. …but cancelling the picker is not, so it goes back ------------------------------------------
run "Cambiar tema" "@CANCEL" "@CANCEL"
if [ ! -s "$WORK/ran.log" ] && [ "$(draws)" = 3 ]; then _ok "cancelling the theme picker re-shows the parent"
else _no "theme cancel: ran=[$(cat "$WORK/ran.log")] draws=$(draws), expected nothing run and 3 draws"; fi

# ---- 7. a failing action is loud ---------------------------------------------------------------------
# The menu must not swallow the failure. This is what a trailing `|| true` on the top-level call
# costs: it puts the whole call tree in a tested context and bash suspends errexit inside it.
run "Accion que falla"
if grep -qi 'fall' "$WORK/out.log"; then _ok "an action that fails says so"
else _no "an action exiting 3 produced no message: [$(cat "$WORK/out.log")]"; fi

# ---- 8. a missing submenu file is survivable ---------------------------------------------------------
run "Submenu roto" "@CANCEL"
if grep -qi 'no encuentro' "$WORK/out.log" && [ "$RC" = 0 ]; then _ok "a missing submenu file warns and returns to the parent"
else _no "missing submenu: rc=$RC out=[$(cat "$WORK/out.log")]"; fi

# ---- 9. …but a missing ROOT menu is a real failure ----------------------------------------------------
mv "$WORK/menus/actions.toml" "$WORK/menus/actions.off"
run "@CANCEL"
if [ "$RC" = 1 ]; then _ok "a missing actions.toml still exits 1"
else _no "missing actions.toml exited $RC, expected 1"; fi
mv "$WORK/menus/actions.off" "$WORK/menus/actions.toml"

# ---- 10. errexit is still live inside the call tree ----------------------------------------------------
if grep -qE '^run_toml_menu "\$MENUS/actions\.toml"[^|]*$' "$WORK/bin/archfrican-actions"; then
  _ok "the top-level call is not in a tested context (errexit stays on)"
else _no "the top-level run_toml_menu call is tested (|| true / || rc=\$?), which suspends errexit"; fi

printf '\nactions-menu unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
