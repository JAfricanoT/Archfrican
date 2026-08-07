#!/usr/bin/env bash
# Unit test for the accessibility override layer — the 4th and LAST layer of theme-switch's token
# cascade (defaults -> palette -> theme tokens.sh -> ~/.config/archfrican/a11y-tokens.sh).
#
# The bug it pins: theme-switch re-asserts the THEME's CURSOR_SIZE via gsettings on every single run,
# so a pointer enlarged from archfrican-a11y was silently reverted by the next theme change — by
# darkman's twice-daily light/dark flip, by every archfrican-update converge, and (worst) by
# "Alto contraste: activar", which lives two lines away in the SAME accessibility menu and is itself
# a theme change. An accommodation must outrank a theme, so it is sourced last.
#
# Black-box: runs the real bin/theme-switch as a subprocess against a throwaway HOME, with gsettings
# stubbed to an argv logger (no session bus in CI, and we need to see the VALUE it was called with).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/fakebin"

# gsettings stub: log every call, succeed. theme-switch invokes it as `timeout 5 gsettings …`, and
# timeout resolves its argument through PATH, so the stub is reached.
cat > "$WORK/fakebin/gsettings" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GS_LOG"
STUB
# Never let the test touch the real system theme paths or a live bar.
for c in sudo kwriteconfig6 pkill swaync-client; do printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/$c"; done
chmod +x "$WORK/fakebin"/*
export PATH="$WORK/fakebin:$PATH"

# One theme-switch run against a fresh HOME. Echoes the cursor-size gsettings saw.
run_switch() {                    # run_switch <theme> [a11y-token-line]
  local theme="$1" override="${2:-}"
  export HOME="$WORK/home"; rm -rf "$HOME"; mkdir -p "$HOME/.config/niri"
  # chezmoi renders this file before niri ever loads it, so the RAW .tmpl — which carries
  # `{{ .chezmoi.homeDir }}` and a `{{ output … }}` for the keyboard layout — is not valid KDL.
  # Substituting those two expression kinds gives a fixture matching what is actually deployed.
  # This matters: theme-switch now runs `niri validate` on the spliced result and correctly
  # refuses to install a config that doesn't parse, so an unrendered fixture would make this
  # test fail on any machine that HAS niri while silently passing on one that doesn't.
  sed -e "s#{{ \.chezmoi\.homeDir }}#$HOME#g" -e 's#"{{[^}]*}}"#"us"#g' \
      "$ROOT/home/dot_config/niri/config.kdl.tmpl" > "$HOME/.config/niri/config.kdl"
  if [ -n "$override" ]; then
    mkdir -p "$HOME/.config/archfrican"
    printf '%s\n' "$override" > "$HOME/.config/archfrican/a11y-tokens.sh"
  fi
  export GS_LOG="$WORK/gs.log"; : > "$GS_LOG"
  ARCHFRICAN_ROOT="$ROOT" bash "$ROOT/bin/theme-switch" "$theme" >/dev/null 2>&1
  grep '^set org.gnome.desktop.interface cursor-size ' "$GS_LOG" | tail -1 | awk '{print $NF}'
}

# ---- 1. baseline: with no override, the theme's own CURSOR_SIZE reaches gsettings -----------------
got="$(run_switch adl-dark)"
if [ "$got" = 24 ]; then _ok "no override: theme CURSOR_SIZE (24) is applied"
else _no "expected cursor-size 24 from the theme, got [$got]"; fi

# ---- 2. THE REGRESSION: an accessibility override outranks the theme ------------------------------
got="$(run_switch adl-dark 'export CURSOR_SIZE="48"')"
if [ "$got" = 48 ]; then _ok "a11y override wins over the theme (cursor stays 48 across a theme switch)"
else _no "a11y override was clobbered by the theme — got cursor-size [$got], expected 48"; fi

# ---- 3. …including on the high-contrast switch that archfrican-a11y itself performs ---------------
# This is the exact in-menu self-cancellation: "Cursor grande" then "Alto contraste: activar".
got="$(run_switch high-contrast 'export CURSOR_SIZE="48"')"
if [ "$got" = 48 ]; then _ok "a11y override survives the high-contrast switch (the same-menu self-cancel)"
else _no "high-contrast switch reverted the a11y cursor — got [$got], expected 48"; fi

# ---- 4. high-contrast's own FOCUS_RING_WIDTH=3 actually reaches niri now --------------------------
# Was hardcoded `width 2` in templates/niri.theme.kdl, so the thicker low-vision ring never applied.
export HOME="$WORK/home"
w="$(grep -A8 'focus-ring' "$HOME/.config/niri/config.kdl" | grep -oE 'width [0-9]+' | head -1 | awk '{print $2}')"
if [ "$w" = 3 ]; then _ok "high-contrast FOCUS_RING_WIDTH=3 reaches niri (was hardcoded to 2)"
else _no "focus-ring width is [$w] under high-contrast, expected 3"; fi

# ---- 5. no unrendered token left in the spliced niri block ----------------------------------------
if grep -qE '\$\{[A-Z_]+\}' "$HOME/.config/niri/config.kdl"; then
  _no "unrendered \${TOKEN} left in niri config.kdl: $(grep -oE '\$\{[A-Z_]+\}' "$HOME/.config/niri/config.kdl" | sort -u | tr '\n' ' ')"
else _ok "niri config.kdl has no unrendered tokens"; fi

# ---- 6. archfrican-a11y's writer is idempotent and its removal path actually removes --------------
A11Y="$ROOT/home/dot_local/bin/executable_archfrican-a11y"
export HOME="$WORK/home2"; mkdir -p "$HOME/.config"
# Exercise a11y_token in isolation: source the script's helper without running its fuzzel menu.
# shellcheck disable=SC1090
eval "$(sed -n '/^a11ytokens=/,/^}$/p' "$A11Y")"
a11y_token CURSOR_SIZE 48; a11y_token CURSOR_SIZE 48       # twice: must not duplicate the line
n="$(grep -c '^export CURSOR_SIZE=' "$HOME/.config/archfrican/a11y-tokens.sh")"
if [ "$n" = 1 ]; then _ok "a11y_token is idempotent (one export line after two writes)"
else _no "a11y_token wrote $n CURSOR_SIZE lines, expected 1"; fi
a11y_token CURSOR_SIZE                                      # no value = drop the override
# The file must still EXIST and merely lack the export — asserting only "no match" would pass
# vacuously on a tree where a11y_token never ran and the file was never created.
if [ -f "$HOME/.config/archfrican/a11y-tokens.sh" ] \
   && ! grep -q '^export CURSOR_SIZE=' "$HOME/.config/archfrican/a11y-tokens.sh"; then
  _ok "a11y_token with no value removes the override (\"Cursor normal\" really resets)"
else _no "a11y_token failed to remove the override (or never wrote the file at all)"; fi

printf '\na11y-tokens unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
