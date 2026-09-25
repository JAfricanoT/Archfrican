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

# ---- 5. apply_category(remoto): an ALREADY-installed app still gets its daemon switched on --------
# RustDesk and AnyDesk both ship their systemd service DISABLED (upstream just prints a post-install
# "run systemctl enable --now …" note nobody reads). Without that daemon the box never registers with
# the ID server, so every INBOUND connection fails while the app itself looks perfectly installed.
# The daemon step must therefore run on EVERY pick, not only after a fresh install — a machine where
# the app is already installed but its service is off is exactly the broken case this repairs.
# Stubs: systemctl reports the unit as present-but-off; ghostty logs its argv instead of opening a window.
cat > "$HOME/.local/share/applications/rustdesk.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=RustDesk
Exec=rustdesk
DESKTOP
cat > "$WORK/fakebin/systemctl" <<'SYSCTL'
#!/bin/sh
case " $* " in
  *" list-unit-files "*) echo "rustdesk.service disabled disabled"; exit 0 ;;
esac
exit 1   # is-enabled / is-active: the daemon is OFF
SYSCTL
cat > "$WORK/fakebin/ghostty" <<'GHOSTTY'
#!/bin/sh
printf '%s\n' "$*" >> "$GHOSTTY_LOG"
GHOSTTY
chmod +x "$WORK/fakebin/systemctl" "$WORK/fakebin/ghostty"
export GHOSTTY_LOG="$WORK/ghostty.log"; : > "$GHOSTTY_LOG"
run __apply remoto 'RustDesk' >/dev/null 2>&1
if grep -q 'enable --now' "$GHOSTTY_LOG" && grep -q 'rustdesk.service' "$GHOSTTY_LOG"; then
  _ok "apply_category(remoto, RustDesk): switches on the rustdesk.service daemon when it's off"
else _no "apply_category(remoto, RustDesk) did not enable rustdesk.service: [$(cat "$GHOSTTY_LOG")]"; fi

# ---- 6. …and is a no-op when that daemon is already enabled + running (idempotent re-pick) --------
# list-unit-files still prints the unit here: an empty answer means "no unit shipped", which would
# make ensure_service bail out early and produce the same empty log for the wrong reason.
cat > "$WORK/fakebin/systemctl" <<'SYSCTL'
#!/bin/sh
case " $* " in
  *" list-unit-files "*) echo "rustdesk.service enabled enabled"; exit 0 ;;
esac
exit 0   # is-enabled / is-active: the daemon is already up
SYSCTL
chmod +x "$WORK/fakebin/systemctl"
: > "$GHOSTTY_LOG"
run __apply remoto 'RustDesk' >/dev/null 2>&1
if [ ! -s "$GHOSTTY_LOG" ]; then _ok "apply_category(remoto, RustDesk): no terminal spawned when the daemon is already up"
else _no "apply_category re-enabled an already-running daemon: [$(cat "$GHOSTTY_LOG")]"; fi

# ---- 7. the extra service field does not leak into row_how (every read site parses 5 fields) ------
# The rows carrying a unit name have one field MORE than the rest; `read -r a b c d` would stuff
# "none|rustdesk.service" into row_how and silently break is_installed()'s cli/none/desktop dispatch.
out="$(run __list remoto)"
if printf '%s\n' "$out" | grep -qP '^RustDesk\t1$'; then _ok "list_category(remoto): 5-field rows still parse (RustDesk reported installed)"; else _no "list_category(remoto) mis-parsed the service field: [$out]"; fi

# ---- 8. list_category(ia-cli): Open Design is detected by `open-design`, never coreutils' `od` ----
# Upstream names its CLI `od`, but /usr/bin/od is octal dump and exists on every box — checking for it
# would report Open Design installed everywhere. The AUR package installs it as `open-design` instead.
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/open-design"
chmod +x "$WORK/fakebin/open-design"
out="$(run __list ia-cli)"
if printf '%s\n' "$out" | grep -qP '^Open Design\t1$'; then _ok "list_category(ia-cli): Open Design (open-design on PATH) reported installed"; else _no "list_category(ia-cli) did not report Open Design as installed: [$out]"; fi

# ---- 9. list_category(editor): Orca the ADE is NOT the `orca` screen reader already on every box --
# Same class of name trap as Open Design above, and a worse one: this repo INSTALLS `orca`, the GNOME
# screen reader (⌘+Alt+S, packages/niri-desktop.txt), on every desktop it builds. Orca the ADE is an
# unrelated program whose AUR package (orca-ide-bin) ships /usr/bin/orca-ide + orca-ide.desktop. A row
# written the naive way — "Orca (ADE)|orca|aur:orca-ide-bin|cli" — would therefore report the ADE
# installed on literally every Archfrican machine, off the screen reader's binary. Runs BEFORE test 10
# creates the .desktop fixture, so the only "orca" in sight here is the screen-reader-shaped decoy.
# Skipped on a box where the ADE genuinely is installed: ARCHFRICAN_APPDIRS includes the real
# /usr/share/applications, so there the "not installed" answer would be wrong rather than proof.
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/orca"
chmod +x "$WORK/fakebin/orca"
if [ -e /usr/share/applications/orca-ide.desktop ]; then
  _ok "list_category(editor): negative Orca check skipped — orca-ide-bin really is installed on this box"
else
  out="$(run __list editor)"
  if printf '%s\n' "$out" | grep -qP '^Orca \(ADE\)\t0$'; then _ok "list_category(editor): the screen reader's \`orca\` binary does not pass Orca the ADE off as installed"; else _no "list_category(editor) mistook the \`orca\` screen reader for the ADE: [$out]"; fi
fi

# ---- 10. …and IS detected once its own .desktop is present --------------------------------------
cat > "$HOME/.local/share/applications/orca-ide.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Orca
Exec=orca-ide
DESKTOP
out="$(run __list editor)"
if printf '%s\n' "$out" | grep -qP '^Orca \(ADE\)\t1$'; then _ok "list_category(editor): Orca ADE (orca-ide.desktop) reported installed"; else _no "list_category(editor) did not report Orca ADE as installed: [$out]"; fi

# ---- 11. list_category(vpn): WireGuard is the category's predefined pick, found by `wg` -----------
# None of the VPN rows ship a .desktop file, and the NetworkManager plugins have no binary of their
# own — so these are cli-kind rows keyed on the binary each one actually puts on PATH (wireguard-tools
# -> wg). Written as desktop-kind rows they would report "not installed" on a fully-provisioned box.
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/wg"
chmod +x "$WORK/fakebin/wg"
out="$(run __list vpn)"
if printf '%s\n' "$out" | grep -qP '^WireGuard \(NetworkManager\)\t1$'; then _ok "list_category(vpn): WireGuard (wg on PATH) reported installed"; else _no "list_category(vpn) did not report WireGuard as installed: [$out]"; fi

# ---- 12. …and WireGuard heads the category — it is the default the menu offers first --------------
if [ "$(run __list vpn | head -1 | cut -f1)" = "WireGuard (NetworkManager)" ]; then _ok "list_category(vpn): WireGuard is the first row (the predefined VPN)"; else _no "list_category(vpn) does not lead with WireGuard: [$(run __list vpn | head -1)]"; fi

# ---- 13. every category is actually REACHABLE from the walker menu -------------------------------
# This script is only the data layer: the menu the user really clicks is elephant's, one
# defaults-<slug>.lua provider per category plus its entry in defaults.toml.tmpl. Adding a category
# here and forgetting either file leaves it working perfectly and visible to nobody — which is
# exactly how a category can look "added" in the repo and never show up on the desktop.
# CATEGORY_LABELS is read out of the script's source (it is a plain literal array): the file can't be
# sourced for it, since its top level runs `set -euo pipefail` and a hard `have fuzzel || exit 1`.
MENUS="$ROOT/home/dot_config/elephant/menus"
slugs="$(sed -n '/^CATEGORY_LABELS=(/,/^)/p' "$SCRIPT" | grep -o '"[a-z-]*|' | tr -d '"|')"
missing=""
for s in $slugs; do
  [ -e "$MENUS/defaults-$s.lua" ] || missing="$missing defaults-$s.lua"
  grep -q "submenu = \"defaults-$s\"" "$MENUS/defaults.toml.tmpl" || missing="$missing defaults.toml.tmpl:$s"
done
if [ -z "$missing" ]; then _ok "every CATEGORY_LABELS slug has a walker provider and a defaults.toml entry ($(printf '%s\n' $slugs | wc -l) categories)"; else _no "categories unreachable from the walker menu:$missing"; fi

rm -rf "$WORK"
printf '\ndefaults unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
