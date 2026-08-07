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

# Electron/Chromium native-Wayland flags used to be hand-written HERE, for code-flags.conf only.
# They are chezmoi dotfiles now (home/dot_config/*-flags.conf) so the whole family is covered —
# Code-OSS, Cursor and Antigravity — instead of just the one this module happened to know about.
# See home/dot_config/code-flags.conf for why it matters (XWayland + fractional scale = offset clicks).
ok "dev module done"
