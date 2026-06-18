#!/usr/bin/env bash
# Phase 2, step 3: editor-agnostic dev environment.
source "$(dirname "$0")/../lib/common.sh"

log "Installing dev toolchains + language servers"
pac_install_file "$REPO_ROOT/packages/dev.txt"

log "Bootstrapping version managers (user-scoped, not system languages)"
have rustup && best_effort rustup default stable
have fnm    && best_effort fnm install --lts

log "Docker (rootless-friendly): enabling service + adding you to the group"
enable_service docker.service
best_effort sudo usermod -aG docker "$USER"
warn "Log out/in for docker group to take effect."

# Code-OSS launches in native Wayland for crisp scaling on niri/NVIDIA
cat > "$HOME/.config/code-flags.conf" <<'FLAGS'
--ozone-platform-hint=auto
--enable-features=UseOzonePlatform,WaylandWindowDecorations
FLAGS
ok "dev module done"
