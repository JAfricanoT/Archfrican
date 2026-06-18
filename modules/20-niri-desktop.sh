#!/usr/bin/env bash
# Phase 2, step 2: the desktop layer. niri lives ONLY in this module +
# its dotfiles. Swap this file + packages/niri-desktop.txt to change compositor.
source "$(dirname "$0")/../lib/common.sh"

substep "installing the niri desktop + Wayland utilities"
pac_install_file "$REPO_ROOT/packages/niri-desktop.txt"

substep "configuring greetd (login manager) to launch niri"
write_system_file /etc/greetd/config.toml <<'TOML'
[terminal]
vt = 1
[default_session]
command = "tuigreet --remember --asterisks --time --cmd niri-session"
user = "greeter"
TOML
enable_service greetd.service

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

substep "configuring keyd (⌘+letter → Ctrl, macOS muscle memory)"
write_system_file /etc/keyd/default.conf <<'KEYD'
# Archfrican keyd map. The ⌘ (meta) key stays the niri WM modifier for non-letter and
# Shift combos, but plain ⌘+<letter> editing shortcuts are translated to Ctrl so
# copy/paste/save/etc. keep your macOS muscle memory. No collision with niri,
# because niri never binds plain Mod+<letter>.
[ids]
*

[main]
capslock = overload(control, esc)   # bonus: tap=Esc, hold=Ctrl (great for vim)

# ⌘+letter -> Ctrl+letter  (app-level macOS shortcuts)
meta.c = C-c
meta.v = C-v
meta.x = C-x
meta.z = C-z
meta.a = C-a
meta.s = C-s
meta.f = C-f
meta.w = C-w
meta.t = C-t
meta.n = C-n
meta.q = C-q
meta.l = C-l
meta.r = C-r
KEYD
substep "enabling keyd"
sudo systemctl enable keyd.service

# --- ecosystem integration (P1) ------------------------------------------------
# Bluetooth: enable the daemon + auto-power-on adapters (main.conf.d drop-in; on older
# bluez without .d support this is harmless and AutoEnable already defaults on).
substep "enabling Bluetooth (bluez + auto-power-on)"
write_system_file /etc/bluetooth/main.conf.d/10-archfrican.conf 0644 <<'BT'
[Policy]
AutoEnable=true
BT
resilient_enable bluetooth.service

# Power profiles (battery vs performance) — laptops only, and ppd NOT tlp.
if compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
  substep "enabling power-profiles-daemon (laptop power management)"
  if pacman -Q tlp &>/dev/null; then
    best_effort sudo systemctl disable --now tlp.service
    warn "disabled tlp (conflicts with power-profiles-daemon)"
  fi
  resilient_enable power-profiles-daemon.service
else
  ok "desktop (no battery) — skipping power-profiles-daemon"
fi

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
