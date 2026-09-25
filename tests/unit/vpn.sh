#!/usr/bin/env bash
# Unit test for home/dot_local/bin/executable_archfrican-vpn — the menu's routing, not its GUIs.
# Black-box: runs the real script as a subprocess with fuzzel, nm-connection-editor, ghostty and
# sudo stubbed, so every branch is exercised without a compositor, a VPN or root.
#
# Why this file exists: the menu used ONE entry, "WireGuard / OpenVPN (NetworkManager)", matched by
# the glob `"WireGuard"*)`. Splitting WireGuard out as its own entry (it is the predefined VPN) makes
# that glob ambiguous — it matches every WireGuard-prefixed label — so a new entry would silently
# open the wrong window instead of failing. These tests pin each label to the argv it must produce.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_archfrican-vpn"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/fakebin"
export NM_LOG="$WORK/nm.log" TERM_LOG="$WORK/term.log" OFFERED="$WORK/offered"

# fuzzel: records the whole menu it was handed (for the ordering assertion) and answers $AF_PICK.
cat > "$WORK/fakebin/fuzzel" <<'FUZZEL'
#!/bin/sh
cat > "$OFFERED"
[ -n "${AF_PICK:-}" ] || exit 1      # no pick = user pressed Escape
printf '%s\n' "$AF_PICK"
FUZZEL
# nm-connection-editor / ghostty: log argv instead of opening anything. The script backgrounds
# nm-connection-editor with `&`, so the log is written asynchronously — see wait_log below.
cat > "$WORK/fakebin/nm-connection-editor" <<'NM'
#!/bin/sh
printf '%s\n' "$*" >> "$NM_LOG"
NM
cat > "$WORK/fakebin/ghostty" <<'GHOSTTY'
#!/bin/sh
printf '%s\n' "$*" >> "$TERM_LOG"
GHOSTTY
# notify-send echoes its args rather than exiting 0: note() calls the REAL one when it's on PATH
# (`have notify-send && notify-send … || echo …`), so on a desktop this test would otherwise pop a
# visible notification AND leave the assertions below with nothing on stdout to look at.
printf '#!/bin/sh\necho "$@"\n' > "$WORK/fakebin/notify-send"
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/tailscale"
printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/sudo"
chmod +x "$WORK"/fakebin/*
export PATH="$WORK/fakebin:$PATH"

# The `&`-backgrounded GUI launch races this test's assertion: poll briefly instead of sleeping a
# fixed amount, so the test is neither flaky on a loaded machine nor slow on an idle one.
wait_log() { local f="$1" i=0; while [ "$i" -lt 50 ]; do [ -s "$f" ] && return 0; sleep 0.02; i=$((i + 1)); done; return 1; }
pick() { : > "$NM_LOG"; : > "$TERM_LOG"; AF_PICK="$1" bash "$SCRIPT" >/dev/null 2>&1; }

# ---- 1. WireGuard leads the menu: it is the predefined VPN ----------------------------------------
AF_PICK="" bash "$SCRIPT" >/dev/null 2>&1
if [ "$(head -1 "$OFFERED")" = "WireGuard: nuevo túnel" ]; then _ok "WireGuard is the first entry offered"; else _no "menu does not lead with WireGuard: [$(head -1 "$OFFERED")]"; fi

# ---- 2. "nuevo túnel" opens the editor straight on NetworkManager's native WireGuard page ---------
# NetworkManager speaks WireGuard itself (no VPN plugin), so the type is `wireguard`, not `vpn`.
pick "WireGuard: nuevo túnel"
if wait_log "$NM_LOG" && grep -q -- '--create' "$NM_LOG" && grep -q -- '--type=wireguard' "$NM_LOG"; then
  _ok "WireGuard: nuevo túnel -> nm-connection-editor --create --type=wireguard"
else _no "WireGuard: nuevo túnel did not open the WireGuard page: [$(cat "$NM_LOG")]"; fi

# ---- 3. "gestionar" opens the plain editor — NOT the create dialog --------------------------------
# This is the case the old `"WireGuard"*)` glob gets wrong: it matches this label too, so both
# entries would end up on whichever branch came first.
pick "WireGuard / VPN: gestionar…"
if wait_log "$NM_LOG" && ! grep -q -- '--create' "$NM_LOG"; then
  _ok "WireGuard / VPN: gestionar… -> plain nm-connection-editor, no --create"
else _no "gestionar… wrongly opened the create dialog: [$(cat "$NM_LOG")]"; fi

# ---- 4. OpenVPN/OpenConnect are plugin-backed, so their type is `vpn`, not their own name ---------
pick "OpenVPN / OpenConnect: nuevo"
if wait_log "$NM_LOG" && grep -q -- '--create' "$NM_LOG" && grep -q -- '--type=vpn' "$NM_LOG"; then
  _ok "OpenVPN / OpenConnect: nuevo -> nm-connection-editor --create --type=vpn"
else _no "OpenVPN / OpenConnect: nuevo did not open the VPN create dialog: [$(cat "$NM_LOG")]"; fi

# ---- 5. Tailscale still connects in a terminal (the login URL has to be visible) ------------------
# Unchanged behaviour, pinned here because reordering the menu is exactly when it could be dropped.
pick "Tailscale: conectar"
if wait_log "$TERM_LOG" && grep -q 'tailscale up' "$TERM_LOG"; then
  _ok 'Tailscale: conectar still runs `tailscale up` in a terminal'
else _no "Tailscale: conectar did not open a terminal: [$(cat "$TERM_LOG")]"; fi

# ---- 6. no nm-connection-editor installed -> a note, never a silent nothing -----------------------
# Without the guard the branch just backgrounds a missing binary: the menu closes and nothing opens,
# with no clue why. network-manager-applet is what ships the editor.
# Deleting the stub is NOT enough to simulate "not installed": $PATH still carries the rest of the
# real system PATH, so `have` would find the machine's own /usr/bin/nm-connection-editor and this
# test would pop a real editor window on the tester's desktop. Hence a PATH with only the stubs the
# script legitimately needs — and no editor anywhere on it.
mkdir -p "$WORK/nobin"
cp "$WORK/fakebin/fuzzel" "$WORK/fakebin/notify-send" "$WORK/nobin/"
ln -s "$(command -v dirname)" "$WORK/nobin/dirname"   # the script's `source "$(dirname "$0")/…"`
out="$(PATH="$WORK/nobin" AF_PICK="WireGuard: nuevo túnel" "$(command -v bash)" "$SCRIPT" 2>&1)"
if printf '%s\n' "$out" | grep -qi 'network-manager-applet'; then _ok "missing nm-connection-editor is reported, not swallowed"; else _no "missing nm-connection-editor failed silently: [$out]"; fi

rm -rf "$WORK"
printf '\nvpn unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
