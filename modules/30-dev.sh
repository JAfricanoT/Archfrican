#!/usr/bin/env bash
# Phase 2, step 3: editor-agnostic dev environment.
source "$(dirname "$0")/../lib/common.sh"

substep "installing dev toolchains + language servers (from packages/dev.txt)"
pac_install_file "$REPO_ROOT/packages/dev.txt"

substep "bootstrapping version managers (user-scoped, not system languages)"
# timeout: both download a toolchain over the network; best_effort only catches a nonzero exit,
# never a hang, so a stalled connection here would freeze the headless first-boot resume
# indefinitely (TimeoutStartSec=infinity on that unit) — same class of bug already fixed elsewhere.
have rustup && { substep "rustup: installing the stable Rust toolchain"; best_effort timeout 300 rustup default stable; }
have fnm    && { substep "fnm: installing the Node LTS";                 best_effort timeout 300 fnm install --lts; }

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
