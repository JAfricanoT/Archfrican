#!/usr/bin/env bash
# Phase 2, step 2: the desktop layer. niri lives ONLY in this module +
# its dotfiles. Swap this file + packages/niri-desktop.txt to change compositor.
source "$(dirname "$0")/../lib/common.sh"

log "Installing niri desktop + Wayland utilities"
pac_install_file "$REPO_ROOT/packages/niri-desktop.txt"

log "Configuring greetd to launch niri"
sudo tee /etc/greetd/config.toml >/dev/null <<TOML
[terminal]
vt = 1
[default_session]
command = "tuigreet --remember --asterisks --time --cmd niri-session"
user = "greeter"
TOML
enable_service greetd.service

# user services
enable_user_service pipewire.service
enable_user_service wireplumber.service
ok "niri-desktop module done"

log "keyd: making ⌘ feel like macOS for app shortcuts (copy/paste/etc.)"
sudo install -d /etc/keyd
sudo tee /etc/keyd/default.conf >/dev/null <<'KEYD'
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
