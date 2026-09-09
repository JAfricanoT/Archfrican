#!/usr/bin/env bash
# Unit test for list_desktop_apps' visibility rules — the single filter that decides what counts as
# a launchable app for BOTH launcher surfaces (the fuzzel fallback in archfrican-spotlight, and the
# category picker in archfrican-defaults).
#
# Why it has teeth: Walker's backend hides on four keys — NoDisplay, Hidden, NotShowIn, OnlyShowIn
# (elephant desktopapplications/query.go:37, splitting XDG_CURRENT_DESKTOP on ":"). This helper used
# to check the first two, so the two surfaces silently disagreed about what exists; on a live niri
# box that was blueman-adapters (OnlyShowIn=XFCE;MATE;), correctly absent from the Walker grid and
# still offered by the fallback. Parity is what makes NotShowIn usable to keep a control surface out
# of the app list without hiding it from a Plasma session, which NoDisplay cannot express.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/apps"

# shellcheck disable=SC1091
source "$ROOT/home/dot_local/lib/archfrican-common.sh"
ARCHFRICAN_APPDIRS=("$WORK/apps")

entry() {                          # entry <id> <extra-lines...>
  local id="$1"; shift
  { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=/bin/true\nIcon=%s-icon\n' "$id" "$id"
    [ "$#" -gt 0 ] && printf '%s\n' "$@"; } > "$WORK/apps/$id.desktop"
}
# "${2-niri}", not "${2:-niri}": the empty-string case is a real case to test (a session that sets
# no current desktop), and ":-" would silently substitute the default for it.
visible() { XDG_CURRENT_DESKTOP="${2-niri}" list_desktop_apps | cut -f1 | grep -qx "$1"; }

# ---- the four keys elephant applies ---------------------------------------------------------------
entry plain
entry nodisp   'NoDisplay=true'
entry hidden   'Hidden=true'
entry notniri  'NotShowIn=niri;'
entry notkde   'NotShowIn=KDE;'
entry onlyniri 'OnlyShowIn=niri;'
entry onlykde  'OnlyShowIn=KDE;'

visible plain     && _ok "a plain entry is listed"                        || _no "a plain entry was not listed"
visible nodisp    && _no "NoDisplay=true was listed"                      || _ok "NoDisplay=true hides"
visible hidden    && _no "Hidden=true was listed"                         || _ok "Hidden=true hides"
visible notniri   && _no "NotShowIn=niri was listed under niri"           || _ok "NotShowIn naming this desktop hides"
visible notkde    && _ok "NotShowIn=KDE is listed under niri"             || _no "NotShowIn=KDE wrongly hidden under niri"
visible onlyniri  && _ok "OnlyShowIn=niri is listed under niri"           || _no "OnlyShowIn=niri wrongly hidden under niri"
visible onlykde   && _no "OnlyShowIn=KDE was listed under niri"           || _ok "OnlyShowIn naming another desktop hides"

# ---- XDG_CURRENT_DESKTOP is a ":"-separated LIST, and any token counts -----------------------------
visible notniri "niri:wlroots" && _no "NotShowIn=niri survived a niri:wlroots session" \
                               || _ok "a \":\"-separated XDG_CURRENT_DESKTOP matches on any token"
visible notniri "KDE"          && _ok "NotShowIn=niri is listed under KDE (the Plasma session keeps it)" \
                               || _no "NotShowIn=niri wrongly hidden under KDE"
visible notniri ""             && _ok "an empty XDG_CURRENT_DESKTOP hides nothing" \
                               || _no "NotShowIn hid an entry with no current desktop set"

# ---- group-awareness: an action's keys are not the app's -------------------------------------------
# The grep this replaced scanned the whole file, so a NoDisplay belonging to a [Desktop Action …]
# block hid the application itself. Several system entries ship exactly that shape.
printf '[Desktop Entry]\nType=Application\nName=withaction\nExec=/bin/true\nIcon=i\nActions=new;\n\n[Desktop Action new]\nName=New\nExec=/bin/true\nNoDisplay=true\n' \
  > "$WORK/apps/withaction.desktop"
visible withaction && _ok "NoDisplay inside [Desktop Action] does not hide the app" \
                   || _no "an action's NoDisplay hid the whole application"

# ---- a localized Name must not win over the real one ------------------------------------------------
printf '[Desktop Entry]\nType=Application\nName=realname\nName[es]=nombretraducido\nExec=/bin/true\nIcon=i\n' \
  > "$WORK/apps/localized.desktop"
visible realname && _ok "Name= wins over Name[es]=" || _no "a localized Name[es]= was used as the name"

# ---- the shipped contract: which entries are apps, and which are control surfaces --------------------
# archfrican-actions opens a LAUNCHER; listing it inside the launcher is the one redundant row in
# ⌘+Space, and it is already on ⌘+Shift+A and the "," prefix. archfrican-setup is a settings
# application and the first thing a new user needs — it stays in the grid, in every session.
A="$ROOT/home/dot_local/share/applications"
if grep -qE '^NotShowIn=.*\bniri\b' "$A/archfrican-actions.desktop.tmpl"; then
  _ok "archfrican-actions is out of the niri app grid (NotShowIn=niri)"
else _no "archfrican-actions no longer declares NotShowIn=niri"; fi
if grep -qE '^(NotShowIn|NoDisplay|Hidden)=' "$A/archfrican-setup.desktop.tmpl"; then
  _no "archfrican-setup is hidden — the first-run wizard must stay findable in the app grid"
else _ok "archfrican-setup stays visible in every session"; fi
# NoDisplay would hide these from Plasma too, where there is no niri bind, no waybar and no Walker.
if grep -rqE '^NoDisplay=true' "$A"/; then
  _no "a shipped .desktop uses NoDisplay=true — that hides it from the Plasma session as well"
else _ok "no shipped .desktop uses the blanket NoDisplay=true"; fi

printf '\ndesktop-visibility unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
