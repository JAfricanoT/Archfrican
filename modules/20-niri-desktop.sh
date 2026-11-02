#!/usr/bin/env bash
# Phase 2, step: the niri compositor layer. Swap this file + packages/niri-desktop.txt to change
# compositor. Desktop-environment-agnostic services (SDDM, NetworkManager, audio, Bluetooth, power
# profiles, XDG dirs) live in modules/15-desktop-services.sh, which runs before this one — they're
# shared with the opt-in modules/25-plasma-desktop.sh, not niri-specific.
source "$(dirname "$0")/../lib/common.sh"

substep "installing the niri desktop + Wayland utilities"
pac_install_file "$REPO_ROOT/packages/niri-desktop.txt"

# --- screen-share portal: route ScreenCast to xdg-desktop-portal-gnome (niri's own default) ---
# niri implements org.gnome.Mutter.ScreenCast itself (version 4), and that is exactly the D-Bus API
# xdg-desktop-portal-gnome's ScreenCast backend records through. This is what gives monitor AND
# individual-window casts, plus niri's "Dynamic Cast Target" stream — the features documented at
# github.com/niri-wm/niri/wiki/Screencasting. The old xdg-desktop-portal-wlr route only exposed full
# monitors over wlr-screencopy; it was a workaround for niri builds before its Mutter ScreenCast API
# and cannot cast a window or the dynamic target. Keep the override explicit (rather than relying on
# niri's packaged /usr/share default) so a future package change can't silently pick a backend that
# can't work here. Higher precedence than niri's /usr/share file, see portals.conf(5).
substep "routing the ScreenCast portal to xdg-desktop-portal-gnome (monitor + window casts)"
write_system_file /etc/xdg-desktop-portal/niri-portals.conf <<'PORTAL'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.ScreenCast=gnome;
PORTAL
# Apply now on a re-converge of an already-running desktop (a fresh install has no --user session
# yet at this point, so this is a harmless no-op there — the config is simply in place for first login).
best_effort systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gnome.service

# waybar via its OWN shipped systemd --user service (Restart=on-failure), not niri
# spawn-at-startup — SIGUSR2 reload (theme-switch sends it on every theme change/converge) is a
# long-standing, well-documented upstream GTK/waybar bug that can segfault the bar
# (github.com/Alexays/Waybar/issues/2224, #1017, #3126, #307, #433, #3400 — not something we can
# fix from this repo). Letting systemd own it means a crash auto-restarts the bar instead of
# leaving it gone until the next login. Never spawn it from BOTH places — that races two instances.
substep "enabling waybar (auto-restarts if it crashes — a known upstream reload bug)"
resilient_enable_user waybar.service

# swaync via its OWN shipped, D-Bus-activated systemd --user service (Type=dbus,
# BusName=org.freedesktop.Notifications, Restart=on-failure), not niri spawn-at-startup — the
# SAME "never spawn it from BOTH places" mistake as waybar above, just for a different daemon.
# Confirmed live: this boot's journal showed niri's spawn-at-startup launch (its own
# "app-niri-swaync-*.scope") racing a SEPARATE "Starting Swaync notification daemon" launch of the
# packaged unit, competing for the same D-Bus name — exactly the documented upstream failure mode
# (github.com/ErikReider/SwayNotificationCenter/issues/47: two launch paths for the same
# BusName-activated service race and can leave a stray/duplicate instance fighting over the
# control-center's layer-shell surface). That's the "opens on its own and freezes" bug reported by
# users — intermittent because most races quietly resolve to one winner, but not always. Enabling
# ONLY the systemd unit (removed from niri's spawn-at-startup in config.kdl.tmpl) makes it the sole
# launch path, with systemd auto-restarting it on an actual crash.
substep "enabling swaync (single launch path — auto-restarts if it crashes)"
resilient_enable_user swaync.service

substep "configuring keyd (⌘+letter → Ctrl, macOS muscle memory)"
write_system_file /etc/keyd/default.conf <<'KEYD'
# Archfrican keyd map. Two layers split ⌘ cleanly between app shortcuts and the WM:
#   [meta]        ⌘+<letter>        -> Ctrl+<letter>          (copy/paste/save/… macOS muscle memory)
#   [meta+shift]  ⌘+Shift+<letter>  -> Super+Shift+<letter>   (passed to niri for its WM/launcher binds)
# Without the [meta+shift] layer, keyd's [meta] mapping ALSO fires on ⌘+Shift+<letter> and DROPS the
# Shift (documented keyd behaviour), stealing ⌘+Shift+A/C/F/… from niri. A composite layer takes
# precedence when all its modifiers are held, so the two stop colliding. niri binds no plain Mod+letter
# EXCEPT w and q — deliberately left out of [meta] below so bare ⌘+W/⌘+Q reach niri instead of being
# rewritten into Ctrl+W/Ctrl+Q first. niri owns window/app-close there (see config.kdl.tmpl): a
# WM-level close is guaranteed to work, unlike Ctrl+W/Ctrl+Q which depend on the focused app
# supporting them (and Ctrl+W collides with the shell's word-delete in a terminal).
[ids]
*

[main]
capslock = overload(control, esc)   # bonus: tap=Esc, hold=Ctrl (great for vim)

# ⌘+letter -> Ctrl+letter (app-level macOS shortcuts). These MUST live in the [meta] modifier-layer
# section: keyd REJECTS the `meta.x = …` shorthand ("not a valid key or alias"). Inside [meta] the
# meta modifier is consumed, so the app receives a clean Ctrl+letter — ⌘+C copies, ⌘+A selects all, etc.
# (w and q are intentionally absent — see the note above.)
[meta]
c = C-c
v = C-v
x = C-x
z = C-z
a = C-a
s = C-s
f = C-f
t = C-t
n = C-n
l = C-l
r = C-r

# ⌘+Shift+<letter>: composite layer (MUST come after [meta]). The letters niri binds with Shift pass
# through as Super+Shift+<letter> so niri receives its WM/launcher binds; the rest keep the app's
# Ctrl+Shift shortcut (e.g. ⌘+Shift+Z = redo). M = meta/super, S = shift, C = control.
[meta+shift]
a = M-S-a
c = M-S-c
f = M-S-f
l = M-S-l
n = M-S-n
q = M-S-q
r = M-S-r
s = M-S-s
t = M-S-t
v = M-S-v
w = M-S-w
x = C-S-x
z = C-S-z
KEYD
# enable for boot + validate-then-(re)start so the map is live now AND on every converge (a re-render
# of default.conf only takes effect after a restart; never restart onto a config keyd rejects).
substep "enabling keyd"
sudo systemctl enable keyd.service
if sudo keyd check >/dev/null 2>&1; then
  sudo systemctl restart keyd.service
else
  warn "keyd config failed 'keyd check' — left the running map as-is (inspect: sudo keyd check)"
fi

ok "niri-desktop module done"
