# shellcheck shell=sh
# Archfrican first-boot status notice. Installed to /etc/profile.d/ by lib/phase1.sh::inject_resume, so EVERY
# console login during the first boot tells the user that the desktop/dev layer is installing in the
# background (the resume runs headless — its output only goes to the journal). Goes quiet once the
# graphical login (SDDM) is up. POSIX sh; ASCII + ANSI only (the TTY console font has no emoji).
__af_firstboot_notice() {
  command -v systemctl >/dev/null 2>&1 || return 0
  if systemctl is-active --quiet sddm.service 2>/dev/null \
    || systemctl is-active --quiet graphical.target 2>/dev/null; then
    return 0   # the graphical login (SDDM) is up — stay silent (harmless if the file lingers)
  elif [ -f /var/lib/archfrican/firstboot-done ]; then
    printf '\n\033[1;32m==> Archfrican: setup complete.\033[0m  Reboot into your desktop:  sudo systemctl reboot\n\n'
  elif systemctl is-failed --quiet archfrican-resume.service 2>/dev/null; then
    printf '\n\033[1;31m==> Archfrican setup hit a snag.\033[0m\n    Details:  journalctl -u archfrican-resume -b | tail -40\n    Retry:    sudo systemctl start archfrican-resume.service\n\n'
  elif systemctl is-active --quiet archfrican-resume.service 2>/dev/null \
    || systemctl is-enabled --quiet archfrican-resume.service 2>/dev/null; then
    printf '\n\033[1;36m==> Archfrican is installing your desktop in the background (~20-40 min).\033[0m\n'
    printf '    Watch live:  journalctl -u archfrican-resume -f\n'
    printf '    It will broadcast here when it is done; then reboot.\n'
    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet 2>/dev/null \
      && [ ! -e /dev/dri/renderD128 ]; then
      printf '    \033[1;33m[!] This VM has no 3D GPU -> the graphical desktop will be a black screen\033[0m\n'
      printf '    \033[1;33m    (niri needs a render device). Fix it on the HOST:\033[0m\n'
      case "$(systemd-detect-virt 2>/dev/null)" in
        kvm|qemu)
          printf '    \033[1;33m    virt-manager: Video=Virtio + "3D acceleration"; Display=Spice + OpenGL +\033[0m\n'
          printf '    \033[1;33m    Listen:None (host needs virglrenderer).  Details: ~/.archfrican/tests/e2e/README.md\033[0m\n' ;;
        oracle)
          printf '    \033[1;33m    VirtualBox: Display -> Graphics Controller=VMSVGA + Enable 3D Acceleration.\033[0m\n' ;;
        *)
          printf '    \033[1;33m    enable virtio-gpu / 3D accel in your hypervisor.  Details: ~/.archfrican/tests/e2e/README.md\033[0m\n' ;;
      esac
    fi
    printf '\n'
  fi
}
case "$-" in *i*) __af_firstboot_notice ;; esac    # interactive shells only
unset -f __af_firstboot_notice 2>/dev/null || true
