#!/usr/bin/env bash
# Unit test for archfrican-bar-mode and the two waybar mode fragments it switches between.
#
# Black-box: runs the real script against a fake HOME with stubbed systemctl/systemd-run/pkill, so no
# test ever restarts the developer's actual bar.
#
# The stakes are higher than a cosmetic toggle. config.jsonc defines its module groups NOWHERE — they
# arrive through a single `include` of ~/.config/waybar/mode.jsonc. If that link is missing, dangling,
# or points at a file whose group definitions have drifted, waybar resolves those groups to nothing and
# drops cpu, network and the whole system tray from the bar, logging one warning and exiting 0. Every
# case below guards a path to that outcome.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_archfrican-bar-mode"
MODESRC="$ROOT/home/dot_config/waybar/modes"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME/waybar/modes" "$WORK/fakebin"
cp "$MODESRC"/collapsed.jsonc "$MODESRC"/expanded.jsonc "$XDG_CONFIG_HOME/waybar/modes/"

# Stub every way the script can touch the session. `systemctl --user cat` must succeed so the script
# takes the systemd branch rather than the pkill fallback.
for t in systemctl systemd-run pkill; do
  printf '#!/bin/sh\nexit 0\n' > "$WORK/fakebin/$t"; chmod +x "$WORK/fakebin/$t"
done
export PATH="$WORK/fakebin:$PATH"

LINK="$XDG_CONFIG_HOME/waybar/mode.jsonc"
run() { bash "$SCRIPT" "$@"; }

# ---- 1. the two modes must describe the SAME groups with the SAME modules ------------------------
# Drift here is the silent killer: a module added to one mode and forgotten in the other simply stops
# existing for every user whose toggle happens to sit on the other side.
py_groups() {
  python3 - "$1" <<'PY'
import json,re,sys,io
s=io.open(sys.argv[1],encoding="utf-8").read()
out=[];instr=False;esc=False;i=0
while i<len(s):
    c=s[i]
    if instr:
        out.append(c)
        if esc: esc=False
        elif c=='\\': esc=True
        elif c=='"': instr=False
        i+=1; continue
    if c=='"': instr=True; out.append(c); i+=1; continue
    if s.startswith('//',i):
        while i<len(s) and s[i]!='\n': i+=1
        continue
    out.append(c); i+=1
d=json.loads(re.sub(r',(\s*[}\]])',r'\1',''.join(out)))
for k in sorted(d):
    mods=[m for m in d[k]["modules"] if m != "custom/systray-toggle"]
    print(k, ",".join(mods))
PY
}
a="$(py_groups "$MODESRC/collapsed.jsonc" 2>&1)"
b="$(py_groups "$MODESRC/expanded.jsonc" 2>&1)"
if [ -z "$a" ] || [ -z "$b" ]; then
  _no "a mode fragment is not parseable JSONC: ${a:-<collapsed empty>} / ${b:-<expanded empty>}"
elif [ "$a" = "$b" ]; then
  _ok 'both modes define the same groups with the same modules'
else
  _no "mode fragments drifted:"$'\n'"--- collapsed ---"$'\n'"$a"$'\n'"--- expanded ---"$'\n'"$b"
fi

# ---- 2. only collapsed carries drawers; expanded must carry none ---------------------------------
grep -q '"drawer"' "$MODESRC/collapsed.jsonc" \
  && _ok 'collapsed.jsonc defines drawers' || _no 'collapsed.jsonc has no drawer — nothing would collapse'
grep -q '"drawer"' "$MODESRC/expanded.jsonc" \
  && _no 'expanded.jsonc contains a drawer — expanded mode would stay collapsed' \
  || _ok 'expanded.jsonc carries no drawer'

# ---- 3. config.jsonc must include EXACTLY ONE mode file ------------------------------------------
# waybar merges includes deeply, so a second include leaks its `drawer` key into the expanded group and
# pins the bar collapsed no matter what the symlink says. This is a real regression that was measured,
# not a hypothetical — see the include comment in config.jsonc.
inc="$(sed -n '/"include": \[/,/\]/p' "$ROOT/home/dot_config/waybar/config.jsonc" | grep -c 'jsonc"')"
[ "$inc" = "1" ] && _ok 'config.jsonc includes exactly one mode file' \
                 || _no "config.jsonc includes $inc mode files; a second one deep-merges its drawer back in"

# ---- 4. config.jsonc must NOT define the groups itself -------------------------------------------
if grep -qE '^\s*"group/(system|net|systray)":' "$ROOT/home/dot_config/waybar/config.jsonc"; then
  _no 'config.jsonc defines a group; "first definition wins" would make the toggle a no-op'
else
  _ok 'config.jsonc leaves every group to the mode fragment'
fi

# ---- 5. a missing link reports collapsed AND is healed -------------------------------------------
rm -f "$LINK"
out="$(run status)"
printf '%s' "$out" | grep -q '"class":"collapsed"' \
  && _ok 'a missing link reports collapsed' || _no "missing link reported: $out"
[ "$(readlink "$LINK")" = "modes/collapsed.jsonc" ] \
  && _ok 'a missing link is healed to collapsed' || _no "link not healed: $(readlink "$LINK" || echo none)"

# ---- 6. a DANGLING link is healed too ------------------------------------------------------------
ln -sfn modes/gone.jsonc "$LINK"
run status >/dev/null
[ "$(readlink "$LINK")" = "modes/collapsed.jsonc" ] \
  && _ok 'a dangling link is healed to collapsed' || _no "dangling link survived: $(readlink "$LINK")"

# ---- 7. toggle flips both ways -------------------------------------------------------------------
run collapsed >/dev/null
run toggle    >/dev/null
[ "$(readlink "$LINK")" = "modes/expanded.jsonc" ] \
  && _ok 'toggle: collapsed -> expanded' || _no "toggle did not expand: $(readlink "$LINK")"
run toggle >/dev/null
[ "$(readlink "$LINK")" = "modes/collapsed.jsonc" ] \
  && _ok 'toggle: expanded -> collapsed' || _no "toggle did not collapse: $(readlink "$LINK")"

# ---- 8. status reflects the active mode ----------------------------------------------------------
run expanded >/dev/null
run status | grep -q '"class":"expanded"' \
  && _ok 'status reports expanded when the link points there' || _no 'status did not report expanded'

# ---- 9. the link stays RELATIVE so it survives $HOME moving --------------------------------------
case "$(readlink "$LINK")" in
  /*) _no 'link target is absolute; it would break if $HOME moved' ;;
  modes/*) _ok 'link target is relative to its own directory' ;;
  *) _no "unexpected link target: $(readlink "$LINK")" ;;
esac

# ---- 10. an unknown argument fails loudly --------------------------------------------------------
if run nonsense >/dev/null 2>&1; then
  _no 'an unknown command exited 0'
else
  _ok 'an unknown command exits nonzero'
fi

printf '\n  %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
