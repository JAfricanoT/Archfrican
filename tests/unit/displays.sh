#!/usr/bin/env bash
# Unit test for archfrican-displays (persist the niri monitor layout). Mocks `niri` (msg + validate)
# and uses real jq, so it needs NO niri/monitors and runs in CI. Guards:
#   1. save: the live `niri msg --json outputs` becomes niri `output { … }` blocks spliced between the
#      managed markers; the disabled output is omitted and surrounding config is preserved.
#   2. validate-or-revert: a config `niri validate` rejects is rolled back to the last-good version
#      (a malformed nested KDL block would otherwise silently disable the whole niri config).
#   3. restore: re-splices the saved sidecar after the template re-renders (the run_after path).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_archfrican-displays"
command -v jq >/dev/null 2>&1 || { echo "displays unit test: SKIP (jq not available)"; exit 0; }

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
has(){ if grep -qF "$2" "$1"; then _ok "$3"; else _no "$3"; fi; }
hasnt(){ if grep -qF "$2" "$1"; then _no "$3"; else _ok "$3"; fi; }

WORK="$(mktemp -d)"
export XDG_CONFIG_HOME="$WORK/cfg"; mkdir -p "$XDG_CONFIG_HOME/niri"
KDL="$XDG_CONFIG_HOME/niri/config.kdl"
export NIRI_OUTPUTS="$WORK/outputs.json"

# fixture: two enabled outputs (one scaled, one with VRR) + one DISABLED (logical=null -> must be omitted)
cat > "$NIRI_OUTPUTS" <<'JSON'
{ "eDP-1": {"modes":[{"width":2560,"height":1600,"refresh_rate":60000}],"current_mode":0,"vrr_enabled":false,"logical":{"x":0,"y":0,"scale":1.5,"transform":"Normal"}},
  "DP-3":  {"modes":[{"width":3840,"height":2160,"refresh_rate":59997}],"current_mode":0,"vrr_enabled":true,"logical":{"x":1707,"y":0,"scale":1.0,"transform":"Normal"}},
  "OFF-1": {"modes":[],"current_mode":null,"vrr_enabled":false,"logical":null} }
JSON

# mock niri on PATH: `niri msg …` prints the fixture; `niri validate` exits NIRI_VALIDATE_RC
MOCK="$WORK/bin"; mkdir -p "$MOCK"
cat > "$MOCK/niri" <<'EOF'
#!/bin/sh
[ "$1" = msg ] && { cat "$NIRI_OUTPUTS"; exit 0; }
[ "$1" = validate ] && exit "${NIRI_VALIDATE_RC:-0}"
exit 0
EOF
chmod +x "$MOCK/niri"; export PATH="$MOCK:$PATH"

printf 'input { keyboard {} }\n// ARCHFRICAN-DISPLAYS-START (managed)\n// ARCHFRICAN-DISPLAYS-END\nbinds { Mod+Q {} }\n' > "$KDL"

# ---- 1. save -------------------------------------------------------------------------------------
NIRI_VALIDATE_RC=0 bash "$SCRIPT" save >/dev/null 2>&1
has   "$KDL" 'output "eDP-1"'        "save: wrote the eDP-1 block"
has   "$KDL" 'scale 1.5'             "save: captured the 1.5 scale"
has   "$KDL" 'position x=1707 y=0'   "save: captured DP-3 position"
has   "$KDL" 'variable-refresh-rate' "save: captured DP-3 VRR"
hasnt "$KDL" 'OFF-1'                 "save: omitted the disabled output"
has   "$KDL" 'binds { Mod+Q'         "save: preserved surrounding config"
if [ "$(grep -c 'output "eDP-1"' "$KDL")" = 1 ]; then _ok "save: single eDP-1 block (no dup)"; else _no "save: duplicated block"; fi

NIRI_VALIDATE_RC=0 bash "$SCRIPT" save >/dev/null 2>&1   # idempotent
if [ "$(grep -c 'output "DP-3"' "$KDL")" = 1 ]; then _ok "save twice: still a single DP-3 block"; else _no "save twice duplicated"; fi

# ---- 2. validate-or-revert: a layout that niri rejects must roll back ----------------------------
good="$(cat "$KDL")"
cat > "$NIRI_OUTPUTS" <<'JSON'
{ "DP-3": {"modes":[{"width":3840,"height":2160,"refresh_rate":59997}],"current_mode":0,"vrr_enabled":false,"logical":{"x":9999,"y":0,"scale":1.0,"transform":"Normal"}} }
JSON
NIRI_VALIDATE_RC=1 bash "$SCRIPT" save >/dev/null 2>&1
if [ "$(cat "$KDL")" = "$good" ]; then _ok "validate fail: config.kdl rolled back (no x=9999 written)"; else _no "validate fail: config.kdl NOT reverted"; fi
hasnt "$KDL" 'x=9999' "validate fail: the rejected position never persisted"

# ---- 3. restore: re-splice the saved sidecar after a fresh template render -----------------------
printf 'input {}\n// ARCHFRICAN-DISPLAYS-START (managed)\n// ARCHFRICAN-DISPLAYS-END\n' > "$KDL"
NIRI_VALIDATE_RC=0 bash "$SCRIPT" restore >/dev/null 2>&1
has "$KDL" 'output "eDP-1"' "restore: re-splices the saved layout after a re-render"

rm -rf "$WORK"
printf '\ndisplays unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
