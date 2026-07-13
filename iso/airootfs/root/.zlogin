# Archfrican live environment — root's LOGIN hook. This overrides archiso releng's own
# root/.zlogin, so it must preserve releng's two behaviors (below) before adding ours.
# getty@tty1 auto-login starts root's login shell, which on the archiso profile is ZSH
# (releng airootfs/etc/passwd: /usr/bin/zsh) — a .bash_profile here is never read.

# (releng) screen-reader boot entry: keep zle in single-line mode for accessibility
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

# (releng) hook for fully-automated deployments (script=... on the kernel cmdline)
~/.automated_script.sh

# Auto-launch the installer. The repo is pre-bundled at /root/.archfrican by build-iso.sh,
# so install.sh finds lib/common.sh (in_repo() == true) and skips the GitHub clone.
# is_iso() detects /run/archiso → run_phase1() starts immediately.
# No `exec`: a completed dry-run preview or a die must drop to a usable shell — exec would
# kill the login shell and getty would respawn the wizard in an endless loop.
# ARCHFRICAN_REEXEC guard prevents a re-launch loop if the installer re-execs itself.
if [[ -f /root/.archfrican/install.sh && -z "${ARCHFRICAN_REEXEC:-}" ]]; then
  bash /root/.archfrican/install.sh
fi
