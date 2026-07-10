#!/usr/bin/env bash
# Unit test for home/dot_local/bin/executable_archfrican-defaults's scriptable entry points
# (__list/__apply — what all 11 native elephant/menus/defaults-*.lua providers shell out to via
# io.popen). Black-box: invokes the real script as a subprocess (not sourced), pointed at a fake
# HOME + PATH, so it exercises the actual is_installed()/list_category() logic with no root and no
# real package manager. Zero prior coverage (audit finding: 259 lines, 0 tests, despite being the
# single source of truth 11 providers depend on).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_archfrican-defaults"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
export HOME="$WORK/home"
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/bin" "$WORK/fakebin"

# The script's very first check is `have fuzzel || exit 1` (line 8) — unconditional, even though
# __list/__apply never call fuzzel themselves. A no-op stub satisfies that gate. notify-send is ALSO
# stubbed — note() calls the REAL one if it's on PATH, and this test's PATH prefix does not hide the
# rest of the real system PATH, so without this stub, running this test on a real desktop with
# notify-send installed would pop a real, visible notification as a side effect of the test. The stub
# echoes its args (instead of a bare exit 0) so assertions can still see what note() would have shown.
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/fuzzel"
printf '#!/bin/sh\necho "$@"\n' > "$WORK/fakebin/notify-send"
chmod +x "$WORK/fakebin/fuzzel" "$WORK/fakebin/notify-send"
export PATH="$WORK/fakebin:$PATH"

run() { bash "$SCRIPT" "$@"; }

# ---- 1. list_category (mime/.desktop-kind): a real .desktop file is detected as installed --------
cat > "$HOME/.local/share/applications/kitty.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Kitty
Exec=kitty
DESKTOP
# Note: this only asserts on Kitty, the row this test explicitly gave a fixture .desktop file for —
# NOT on Ghostty/Alacritty/foot showing "0", since whether those are ACTUALLY installed depends on
# the machine running the test (this repo's own package list installs ghostty, so a real Archfrican
# desktop legitimately has it — asserting its absence would be a false failure on exactly that box).
out="$(run __list terminal)"
if printf '%s\n' "$out" | grep -qP '^Kitty\t1$'; then _ok "list_category(terminal): Kitty (real .desktop file) reported installed"; else _no "list_category(terminal) did not report Kitty as installed: [$out]"; fi

# ---- 2. list_category (cli-kind): a binary on PATH is detected as installed ------------------------
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/lazydocker"
chmod +x "$WORK/fakebin/lazydocker"
out="$(run __list contenedores)"
if printf '%s\n' "$out" | grep -qP '^LazyDocker\t1$'; then _ok "list_category(contenedores): LazyDocker (real binary on PATH) reported installed"; else _no "list_category(contenedores) did not report LazyDocker as installed: [$out]"; fi

# ---- 3. list_category on an unknown slug fails cleanly (category_data returns 1) -------------------
run __list not-a-real-category >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then _ok "list_category on an unknown slug exits non-zero (category_data's return 1 propagates)"; else _no "list_category on an unknown slug wrongly exited 0"; fi

# ---- 4. apply_category on a CLI tool that's ALREADY installed just confirms — no install attempted --
# LazyDocker is "installed" (fake binary on PATH from test 2) — apply_category must recognize that and
# only note "listo", never call do_install (which would try `sudo pacman -S` and fail/hang without a
# real package manager). notify-send is unavailable in this sandbox, so note() falls back to plain echo.
out="$(run __apply contenedores 'LazyDocker' 2>&1)"
if printf '%s\n' "$out" | grep -qi 'listo'; then _ok "apply_category(contenedores, LazyDocker): recognizes it's already installed, no install attempted"; else _no "apply_category did not report LazyDocker as ready: [$out]"; fi

rm -rf "$WORK"
printf '\ndefaults unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
