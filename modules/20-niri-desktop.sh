#!/usr/bin/env bash
# Phase 2, step 2: the desktop layer. niri lives ONLY in this module +
# its dotfiles. Swap this file + packages/niri-desktop.txt to change compositor.
source "$(dirname "$0")/../lib/common.sh"

log "Installing niri desktop + Wayland utilities"
pac_install_file "$REPO_ROOT/packages/niri-desktop.txt"

log "Configuring greetd to launch niri"
write_system_file /etc/greetd/config.toml <<'TOML'
[terminal]
vt = 1
[default_session]
command = "tuigreet --remember --asterisks --time --cmd niri-session"
user = "greeter"
TOML
enable_service greetd.service

# user audio services (socket-activated). Enable linger so they can run without a
# graphical login; resilient_enable_user skips any unit absent on this pipewire build.
best_effort sudo loginctl enable-linger "$USER"
resilient_enable_user pipewire.socket
resilient_enable_user pipewire-pulse.socket
resilient_enable_user wireplumber.service

log "keyd: making ⌘ feel like macOS for app shortcuts (copy/paste/etc.)"
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
sudo systemctl enable keyd.service

ok "niri-desktop module done"
