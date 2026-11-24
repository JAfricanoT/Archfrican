#!/usr/bin/env bash
# Unit test for the niri SHAPE tokens — gaps, struts, corner radius and the focus ring reaching
# config.kdl through theme-switch's cascade, plus the personal override layer that keeps them.
#
# The bug it pins: ~/.config/niri/config.kdl is a GENERATED artifact. lib/phase2.sh deploys it with
# `chezmoi init --apply --force`, which overwrites the destination with no diff and no backup, so a
# gap/radius tweak made by hand in the live file is destroyed by the next `archfrican-update` — the
# user's adjustments vanish with no error and no trace to recover from. Shape had no override layer
# at all: only colour and accessibility did.
#
# The fix under test: gaps/struts/radius/ring are tokens rendered into theme-switch's managed
# regions (so they exist in exactly ONE place), and ~/.config/archfrican/tokens.local.sh is a
# cascade layer that survives both loss vectors — the converge AND a theme change.
#
# Black-box: runs the real bin/theme-switch against a throwaway HOME, same harness as a11y-tokens.sh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
_eq(){ if [ "$2" = "$3" ]; then _ok "$1"; else _no "$1 — got [$2], expected [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/gsettings"
for c in sudo kwriteconfig6 pkill swaync-client; do printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/$c"; done
chmod +x "$WORK/fakebin"/*
export PATH="$WORK/fakebin:$PATH"

KDL=""
# One theme-switch run against a fresh HOME. $2 = optional tokens.local.sh line, $3 = a11y line.
run_switch() {                    # run_switch <theme> [local-token-line] [a11y-token-line]
  local theme="$1" localtok="${2:-}" a11ytok="${3:-}"
  export HOME="$WORK/home"; export XDG_CONFIG_HOME="$HOME/.config"
  rm -rf "$HOME"; mkdir -p "$HOME/.config/niri" "$HOME/.config/archfrican"
  # Same fixture rationale as a11y-tokens.sh: chezmoi renders the .tmpl before niri sees it, so the
  # raw template (with `{{ .chezmoi.homeDir }}` and the keyboard `{{ output … }}`) is not valid KDL.
  sed -e "s#{{ \.chezmoi\.homeDir }}#$HOME#g" -e 's#"{{[^}]*}}"#"us"#g' \
      "$ROOT/home/dot_config/niri/config.kdl.tmpl" > "$HOME/.config/niri/config.kdl"
  [ -n "$localtok" ] && printf '%s\n' "$localtok" > "$HOME/.config/archfrican/tokens.local.sh"
  [ -n "$a11ytok" ]  && printf '%s\n' "$a11ytok"  > "$HOME/.config/archfrican/a11y-tokens.sh"
  ARCHFRICAN_ROOT="$ROOT" bash "$ROOT/bin/theme-switch" "$theme" >/dev/null 2>&1
  KDL="$HOME/.config/niri/config.kdl"
}
val(){ grep -oE "^\s*$1 [0-9-]+" "$KDL" | head -1 | awk '{print $2}'; }          # top-of-line scalar
ring(){ grep -A6 'focus-ring' "$KDL" | grep -oE 'width [0-9]+' | head -1 | awk '{print $2}'; }
radius(){ grep -oE 'geometry-corner-radius [0-9]+' "$KDL" | head -1 | awk '{print $2}'; }
strut(){ grep -oE 'struts \{ left -[0-9]+' "$KDL" | head -1 | grep -oE '[0-9]+$'; }

# ---- 1. the shipped defaults reach niri (tokens are wired, not decorative) ------------------------
# DESIGN-LANGUAGE.md called GAP_WINDOW/RADIUS_WINDOW "declared but unwired" — changing them had no
# effect because config.kdl.tmpl carried hardcoded literals instead.
run_switch archfrican-dark
_eq "GAP_WINDOW reaches niri gaps"              "$(val gaps)"  "4"
_eq "RADIUS_WINDOW reaches geometry-corner-radius" "$(radius)" "7"
_eq "FOCUS_RING_WIDTH reaches focus-ring width" "$(ring)"      "1"

# ---- 2. struts is DERIVED, never a second number to keep in sync ---------------------------------
# A negative strut cancels the outer half of `gaps`; holding back exactly the ring's width is what
# leaves a window flush to the screen edge somewhere to draw its focus ring.
_eq "struts = -(GAP_WINDOW - FOCUS_RING_WIDTH)" "$(strut)" "3"

# ---- 3. exactly ONE copy of each — niri fails the WHOLE config on a duplicate --------------------
# theme-switch splices into config.kdl; a literal left behind in the .tmpl would make niri reject
# everything ("duplicate node `gaps`, single node expected"), bricking the desktop rather than
# losing an override.
n="$(grep -cE '^\s*gaps [0-9]' "$KDL")"
_eq "config.kdl declares gaps exactly once" "$n" "1"
n="$(grep -cE '^\s*struts \{' "$KDL")"
_eq "config.kdl declares struts exactly once" "$n" "1"
n="$(grep -cE '^\s*geometry-corner-radius [0-9]' "$KDL")"
_eq "config.kdl declares geometry-corner-radius exactly once" "$n" "1"

# ---- 4. the whole thing still parses -------------------------------------------------------------
if command -v niri >/dev/null 2>&1; then
  if niri validate -c "$KDL" >/dev/null 2>&1; then _ok "spliced config passes niri validate"
  else _no "spliced config REJECTED by niri validate"; fi
else _ok "niri absent (CI) — validate skipped"; fi

# ---- 5. tokens.local.sh survives a theme change (loss vector #2) ---------------------------------
# theme-switch runs on every converge AND on every theme switch; a personal shape tweak has to
# outrank the theme's own tokens or it is reverted twice over.
run_switch archfrican-dark 'export GAP_WINDOW="9"'
_eq "tokens.local.sh overrides the theme's GAP_WINDOW" "$(val gaps)" "9"
_eq "derived struts follows the override"              "$(strut)"    "8"

# ---- 6. …including on a theme that sets the token itself ------------------------------------------
run_switch high-contrast 'export GAP_WINDOW="9"'
_eq "tokens.local.sh outranks a theme's own tokens.sh" "$(val gaps)" "9"

# ---- 6b. the radius cascade specifically: theme identity, then personal override ------------------
# archfrican-dark/light carry their own RADIUS_WINDOW (the shipped identity's corner family), so this
# pins the ORDER rather than a constant — a theme still owns its look, the user still gets the last
# word over it, and neither is a literal in config.kdl any more.
run_switch archfrican-dark 'export RADIUS_WINDOW="16"'
_eq "tokens.local.sh overrides the theme's RADIUS_WINDOW" "$(radius)" "16"

# ---- 7. accessibility is still the FLOOR, above personal taste ------------------------------------
# An accommodation is not a preference. high-contrast raises FOCUS_RING_WIDTH to 3 for low vision;
# a personal 1px ring must not be allowed to undo that, so a11y-tokens.sh is sourced LAST.
run_switch archfrican-dark 'export FOCUS_RING_WIDTH="1"' 'export FOCUS_RING_WIDTH="3"'
_eq "a11y-tokens.sh outranks tokens.local.sh" "$(ring)" "3"

# ---- 8. no unrendered token leaks into the live config -------------------------------------------
if grep -qE '\$\{[A-Z_]+\}' "$KDL"; then
  _no "unrendered \${TOKEN} left: $(grep -oE '\$\{[A-Z_]+\}' "$KDL" | sort -u | tr '\n' ' ')"
else _ok "no unrendered \${TOKEN} in config.kdl"; fi

printf '\nniri-tokens: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
