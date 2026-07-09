#!/usr/bin/env bash
# Phase 2, step 2: the desktop layer. niri lives ONLY in this module +
# its dotfiles. Swap this file + packages/niri-desktop.txt to change compositor.
source "$(dirname "$0")/../lib/common.sh"

substep "installing the niri desktop + Wayland utilities"
pac_install_file "$REPO_ROOT/packages/niri-desktop.txt"

# --- screen-share portal: route ScreenCast to -wlr, not niri's packaged default of gnome/gtk ----
# niri ships /usr/share/xdg-desktop-portal/niri-portals.conf with `default=gnome;gtk;` and no
# per-interface override — so ScreenCast (used by RustDesk/AnyDesk, browser tab/screen sharing,
# OBS's portal capture, etc.) goes to xdg-desktop-portal-gnome, whose ScreenCast implementation
# calls into GNOME Shell/mutter's own D-Bus API (org.gnome.Mutter.ScreenCast) — which doesn't
# exist under niri, so every screen-share request fails (confirmed live: RustDesk reported
# "failed to create capturer for display 0"). xdg-desktop-portal-wlr implements ScreenCast via
# wlr-screencopy, the same protocol niri already supports for grim/wf-recorder — an /etc override
# (higher precedence than niri's own /usr/share default, see portals.conf(5)) routes just that one
# interface there while leaving gnome/gtk as-is for everything else (FileChooser, Notification, …).
substep "routing the ScreenCast portal to xdg-desktop-portal-wlr (screen-share over niri)"
write_system_file /etc/xdg-desktop-portal/niri-portals.conf <<'PORTAL'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.ScreenCast=wlr;
PORTAL
# Apply now on a re-converge of an already-running desktop (a fresh install has no --user session
# yet at this point, so this is a harmless no-op there — the config is simply in place for first login).
best_effort systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gnome.service xdg-desktop-portal-wlr.service

# --- graphical login: SDDM + the Archfrican theme (macOS, themed from the active palette) ----
# SDDM lists Wayland sessions from /usr/share/wayland-sessions/*.desktop (niri ships niri.desktop),
# so the session command (niri-session) is NOT hardcoded. The greeter renders on Wayland via weston
# (no xorg). Fallback: set DisplayServer=x11 here (needs xorg-server) if a GPU dislikes the Wayland
# greeter — see docs/CONTEXT.md.
substep "installing the SDDM theme (archfrican)"
sudo install -d -m 0755 /usr/share/sddm/themes/archfrican
sudo cp -a "$REPO_ROOT/assets/sddm/archfrican/." /usr/share/sddm/themes/archfrican/

# Curated wallpapers — dropped where archfrican-wallpaper's own directory scan (find ...
# /usr/share/backgrounds ...) already looks, so they're pickable with ZERO changes to that
# script. Same install-d + cp -a idempotent-copy pattern as the SDDM theme assets above.
substep "installing curated Archfrican wallpapers"
sudo install -d -m 0755 /usr/share/backgrounds/archfrican
sudo cp -a "$REPO_ROOT/assets/wallpapers/." /usr/share/backgrounds/archfrican/
# Paint the theme from the user's current palette (themes/<name>/colors.sh via the token template).
substep "theming the login from the active palette"
THEME_NOW="$(cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo archfrican-dark)"
render_sddm_theme "$THEME_NOW"     # lib/common.sh helper: token-render -> /usr/share/sddm/themes/archfrican/theme.conf

substep "configuring SDDM (Wayland greeter, remember last user/session)"
# Minimal on purpose: DisplayServer=wayland makes SDDM host the greeter under its OWN packaged,
# version-matched weston compositor command (overriding it with a specific weston shell is fragile —
# the shell name changed across weston releases). If the Wayland greeter ever misbehaves on a GPU,
# the documented fallback is one line: DisplayServer=x11 (and add xorg-server) — see docs/CONTEXT.md.
write_system_file /etc/sddm.conf.d/10-archfrican.conf <<'SDDM'
[Theme]
Current=archfrican

[General]
DisplayServer=wayland

[Users]
RememberLastUser=true
RememberLastSession=true
SDDM

# On-screen keyboard: only wire SDDM's input method when the theme opts in (the rendered theme.conf
# knob). Default-off keeps the desktop login clean (qtvirtualkeyboard auto-raises on field focus);
# flip virtualKeyboardEnabled=true + re-converge for a touchscreen.
if grep -q '^virtualKeyboardEnabled=true' /usr/share/sddm/themes/archfrican/theme.conf 2>/dev/null; then
  substep "enabling the on-screen keyboard input method (virtualKeyboardEnabled=true)"
  write_system_file /etc/sddm.conf.d/15-archfrican-vkbd.conf <<'VK'
[General]
InputMethod=qtvirtualkeyboard
VK
else
  best_effort sudo rm -f /etc/sddm.conf.d/15-archfrican-vkbd.conf
fi
enable_service sddm.service

# Network: enable the NetworkManager DAEMON (the applet in packages/ is inert without it).
# resilient_enable (not --now) so we never drop the install's own connection mid-run.
substep "enabling NetworkManager (the network daemon)"
resilient_enable NetworkManager.service

# user audio services (socket-activated). Enable linger so they can run without a
# graphical login; resilient_enable_user skips any unit absent on this pipewire build.
substep "enabling audio (pipewire + wireplumber)"
best_effort sudo loginctl enable-linger "$USER"
resilient_enable_user pipewire.socket
resilient_enable_user pipewire-pulse.socket
resilient_enable_user wireplumber.service

# waybar via its OWN shipped systemd --user service (Restart=on-failure), not niri
# spawn-at-startup — SIGUSR2 reload (theme-switch sends it on every theme change/converge) is a
# long-standing, well-documented upstream GTK/waybar bug that can segfault the bar
# (github.com/Alexays/Waybar/issues/2224, #1017, #3126, #307, #433, #3400 — not something we can
# fix from this repo). Letting systemd own it means a crash auto-restarts the bar instead of
# leaving it gone until the next login. Never spawn it from BOTH places — that races two instances.
substep "enabling waybar (auto-restarts if it crashes — a known upstream reload bug)"
resilient_enable_user waybar.service

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

# --- ecosystem integration (P1) ------------------------------------------------
# Bluetooth: enable the daemon + auto-power-on adapters (main.conf.d drop-in; on older
# bluez without .d support this is harmless and AutoEnable already defaults on).
substep "enabling Bluetooth (bluez + auto-power-on)"
write_system_file /etc/bluetooth/main.conf.d/10-archfrican.conf 0644 <<'BT'
[Policy]
AutoEnable=true
BT
resilient_enable bluetooth.service

# Power profiles (balanced/performance/power-saver) — power-profiles-daemon, NOT tlp. Enable it on
# laptops AND desktops: PPD exposes whatever profiles the platform supports (CPU EPP / ACPI
# platform_profile), and the waybar switch needs the daemon RUNNING to load at all (it was silently
# absent on desktops). On hardware with no profile backend the daemon still runs harmlessly — the
# switch just shows the single available profile instead of failing to load.
substep "enabling power-profiles-daemon (balanced/performance switch)"
if pacman -Q tlp &>/dev/null; then
  best_effort sudo systemctl disable --now tlp.service
  warn "disabled tlp (conflicts with power-profiles-daemon)"
fi
resilient_enable power-profiles-daemon.service

substep "creating XDG user dirs + default file manager"
best_effort xdg-user-dirs-update
best_effort xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Optional hardware-sensor probe (writes /etc/conf.d/lm_sensors). OFF by default — it
# interrogates buses that can misbehave; the waybar temperature module uses thermal-zone 0.
if [ "${ARCHFRICAN_SENSORS_DETECT:-0}" = 1 ]; then
  substep "running sensors-detect (ARCHFRICAN_SENSORS_DETECT=1)"
  best_effort sudo sensors-detect --auto
fi

ok "niri-desktop module done"
