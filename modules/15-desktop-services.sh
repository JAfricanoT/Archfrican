#!/usr/bin/env bash
# Phase 2, step: desktop-environment-agnostic services — SDDM (the login manager shared by EVERY
# session, niri or the opt-in Plasma one), NetworkManager, audio, Bluetooth, power profiles, XDG
# user dirs, and the optional sensor probe. None of this is niri-specific; it used to live in
# modules/20-niri-desktop.sh, whose own header claimed "niri lives ONLY in this module" while
# actually also carrying all of the above — meaning modules/25-plasma-desktop.sh (its own header:
# "Never touches niri/waybar/swaync/keyd in ANY way") silently depended on 20-niri-desktop having
# already run for NetworkManager/Bluetooth/audio/power-profiles to exist at all. Not a live bug
# today (20-niri-desktop is Always-active, so the dependency is always satisfied), but a real
# maintainability/scope problem the audit flagged, and it'll bite the day a SECOND opt-in desktop
# is added and doesn't happen to also be layered after 20-niri-desktop. Runs between 10-gpu and
# 20-niri-desktop (both niri and Plasma need these ready before their own module runs).
source "$(dirname "$0")/../lib/common.sh"

# --- graphical login: SDDM + the Archfrican theme (macOS, themed from the active palette) ----
# SDDM lists Wayland sessions from /usr/share/wayland-sessions/*.desktop (niri ships niri.desktop,
# the opt-in Plasma module ships plasma*.desktop), so the session command is NEVER hardcoded here —
# whichever session packages are installed, SDDM just lists them. The greeter renders on Wayland via
# weston (no xorg). Fallback: set DisplayServer=x11 here (needs xorg-server) if a GPU dislikes the
# Wayland greeter — see docs/CONTEXT.md.
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
THEME_NOW="$(current_theme)"
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

# Auto-switch the profile on AC plug/unplug — the macOS "just works" behavior a bare compositor
# (no GNOME/KDE power daemon) otherwise lacks. The udev rule fires archfrican-power-auto through
# `systemd-run --no-block`, so it runs detached with a clean env + system D-Bus (never blocking
# udev). Inert on desktops (no AC-adapter `online` transitions / profile absent) and on any box
# without power-profiles-daemon; ATTR{online} matches ONLY the mains adapter, never a battery.
# Disable/remap per-machine via /etc/archfrican/power-auto.conf (see the helper's header).
substep "auto power profile on AC/battery (udev)"
sudo ln -sf "$REPO_ROOT/bin/archfrican-power-auto" /usr/local/bin/archfrican-power-auto
write_system_file /etc/udev/rules.d/60-archfrican-power-profile.rules 0644 <<'RULES'
# Archfrican: set the CPU power profile from the AC-adapter state. add|change so it also applies
# the current state at boot (a no-op until power-profiles-daemon is up, then the next event fixes it).
ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block /usr/local/bin/archfrican-power-auto ac"
ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block /usr/local/bin/archfrican-power-auto battery"
RULES
best_effort sudo udevadm control --reload-rules

substep "creating XDG user dirs + default file manager"
best_effort xdg-user-dirs-update
best_effort xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Optional hardware-sensor probe (writes /etc/conf.d/lm_sensors). OFF by default — it
# interrogates buses that can misbehave; the waybar temperature module uses thermal-zone 0.
if [ "${ARCHFRICAN_SENSORS_DETECT:-0}" = 1 ]; then
  substep "running sensors-detect (ARCHFRICAN_SENSORS_DETECT=1)"
  best_effort sudo sensors-detect --auto
fi

ok "desktop-services module done"
