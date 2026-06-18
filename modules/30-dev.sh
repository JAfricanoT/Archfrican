#!/usr/bin/env bash
# Phase 2, step 3: editor-agnostic dev environment.
source "$(dirname "$0")/../lib/common.sh"

substep "installing dev toolchains + language servers (from packages/dev.txt)"
pac_install_file "$REPO_ROOT/packages/dev.txt"

substep "bootstrapping version managers (user-scoped, not system languages)"
have rustup && { substep "rustup: installing the stable Rust toolchain"; best_effort rustup default stable; }
have fnm    && { substep "fnm: installing the Node LTS";                 best_effort fnm install --lts; }

substep "enabling docker + adding you to the docker group"
enable_service docker.service
best_effort sudo usermod -aG docker "$USER"
warn "Log out/in for docker group to take effect."

substep "writing Code-OSS native-Wayland flags"
cat > "$HOME/.config/code-flags.conf" <<'FLAGS'
--ozone-platform-hint=auto
--enable-features=UseOzonePlatform,WaylandWindowDecorations
FLAGS
ok "dev module done"
