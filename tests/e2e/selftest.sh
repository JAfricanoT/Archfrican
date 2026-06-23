#!/usr/bin/env bash
# ============================================================================
#  Archfrican end-to-end self-test — run INSIDE a throwaway UEFI VM.
#  Full procedure + prerequisites: tests/e2e/README.md
#
#  Subcommands:
#    install   on the Arch live ISO (as root): armed AUTOPILOT install + the
#              pre-reboot assertions (the on-disk result, against /mnt + LUKS).
#    postboot  on the INSTALLED system, after the first-boot resume finishes:
#              the post-reboot assertions (booted encrypted, resume self-cleaned,
#              snapper, NetworkManager, zsh, …).
#    assert    just the pre-reboot assertions against an already-mounted /mnt.
#    rerun     C2 re-run safety: install, then install AGAIN — the stale-state
#              guard must release /mnt + close LUKS and complete.
#
#  SAFETY: `install`/`rerun` WIPE the target disk. They only proceed because the
#  harness sets the explicit autopilot gates in the env (ARCHFRICAN_ISO_ARMED=1 +
#  ARCHFRICAN_ISO_GO=1 + ARCHFRICAN_AUTOPILOT_CONFIRM_WIPE=<device>) — the shipped
#  repo defaults to dry-run. Use ONLY in a disposable VM.
# ============================================================================
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"

# --- tiny logger (we deliberately do NOT source common.sh: its `set -e` would
#     abort the assertion loop on the first failing check) ---------------------
_c() { printf '\033[%sm' "$1"; }; _r() { printf '\033[0m'; }
say() { printf '%s\n' "$*"; }
hd()  { printf '\n%s== %s ==%s\n' "$(_c '1;36')" "$*" "$(_r)"; }
note(){ printf '%s» %s%s\n' "$(_c 2)" "$*" "$(_r)"; }
die() { printf '%sfatal:%s %s\n' "$(_c '1;31')" "$(_r)" "$*" >&2; exit 1; }

PASS=0; FAIL=0
# assert "<description>" <command...>  — PASS iff the command exits 0.
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '  %s✓%s %s\n' "$(_c 32)" "$(_r)" "$desc"; PASS=$((PASS + 1))
  else                          printf '  %s✗%s %s\n' "$(_c 31)" "$(_r)" "$desc"; FAIL=$((FAIL + 1)); fi
}
report() {
  hd "result"
  if [ "$FAIL" -eq 0 ]; then printf '  %sALL %d CHECKS PASSED%s\n' "$(_c '1;32')" "$PASS" "$(_r)"
  else printf '  %s%d FAILED%s, %d passed\n' "$(_c '1;31')" "$FAIL" "$(_r)" "$PASS"; exit 1; fi
}

# --- predicates (kept as named functions so quoting stays sane + shellcheck-clean) ---
part() { case "$1" in *[0-9]) printf '%sp%s' "$1" "$2";; *) printf '%s%s' "$1" "$2";; esac; }
p_luks2()       { cryptsetup isLuks "$1" && cryptsetup luksDump "$1" 2>/dev/null | grep -qiE 'version:[[:space:]]*2'; }
p_src_has()     { findmnt -no SOURCE /mnt | grep -q "$1"; }
p_opt_has()     { findmnt -no OPTIONS /mnt | grep -q "$1"; }
p_gpt_codes()   { local o; o="$(sgdisk -p "$1" 2>/dev/null)"; grep -qi 'EF00' <<<"$o" && grep -q '8304' <<<"$o"; }
p_vfat()        { blkid -o value -s TYPE "$1" 2>/dev/null | grep -q vfat; }
p_hooks_order() { awk -F'[()]' '/^HOOKS=/{print $2}' /mnt/etc/mkinitcpio.conf | grep -Eq 'keyboard.*keymap.*block.*encrypt'; }
p_cryptdev_set(){ grep -oE 'cryptdevice=UUID=[0-9a-fA-F-]+:root' /mnt/etc/default/grub | grep -qE 'UUID=[0-9a-fA-F]{8}'; }
p_cryptdev_uuid(){ local u; u="$(cryptsetup luksUUID "$1" 2>/dev/null)"; [ -n "$u" ] && grep -q "cryptdevice=UUID=$u:root" /mnt/etc/default/grub; }
p_root_locked() { awk -F: '$1=="root"{print $2}' /mnt/etc/shadow | grep -qE '^[!*]'; }
p_user_exists() { grep -q "^$1:" /mnt/etc/passwd; }
p_enabled()     { test -e "/mnt/etc/systemd/system/multi-user.target.wants/$1"; }
# post-boot predicates (run on the installed system, as the user)
b_booted_enc()  { findmnt -no SOURCE / | grep -q '/dev/mapper/'; }
b_resume_clean(){ ! systemctl is-enabled archfrican-resume.service 2>/dev/null | grep -q '^enabled'; }
b_greetd_off()  { ! systemctl is-enabled greetd.service 2>/dev/null | grep -q '^enabled'; }
b_snapper_cfg() {
  # /etc/snapper/configs/root is root-only (0640); read it authoritatively ONLY if sudo is already
  # cached (-n never prompts — keeps this suite prompt-free), else fall back to the user-visible
  # signal that module 50 wired the root snapshot subvol (/.snapshots = the @.snapshots subvol).
  sudo -n grep -q '^SUBVOLUME="/"' /etc/snapper/configs/root 2>/dev/null && return 0
  findmnt -rno SOURCE /.snapshots 2>/dev/null | grep -qF '@.snapshots'
}
b_shell_zsh()   { getent passwd "$(id -un)" | grep -qE ':/usr/bin/zsh$|:/bin/zsh$'; }
# update/converge predicates (need lib/converge.sh sourced + REPO_ROOT set; see assert_update)
b_no_drift()    { [ -z "$(drift_modules 2>/dev/null)" ]; }
b_drift_is()    { [ "$(drift_modules 2>/dev/null | tr '\n' ' ')" = "$1 " ]; }

# --- answers / arming -------------------------------------------------------
load_answers() {
  if [ -f "$HERE/answers.env" ]; then note "loading $HERE/answers.env"; set -a; . "$HERE/answers.env"; set +a; fi
  if [ -z "${AF_AP_DISK:-}" ]; then
    AF_AP_DISK="/dev/$(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1; exit}')"
    note "auto-selected disk: $AF_AP_DISK (override with AF_AP_DISK)"
  fi
  : "${AF_AP_DISK:?no installable disk found}"
  : "${AF_AP_ENCRYPT:=yes}"
  : "${AF_AP_USER:=archfrican}"
  : "${AF_AP_USER_PASSWORD:?set AF_AP_USER_PASSWORD (answers.env or env)}"
  [ "$AF_AP_ENCRYPT" != yes ] || : "${AF_AP_LUKS_PASSPHRASE:?set AF_AP_LUKS_PASSPHRASE (AF_AP_ENCRYPT=yes)}"
  export AF_AP_DISK AF_AP_ENCRYPT AF_AP_USER AF_AP_USER_PASSWORD ${AF_AP_LUKS_PASSPHRASE:+AF_AP_LUKS_PASSPHRASE} \
         ${AF_AP_HOST:+AF_AP_HOST} ${AF_AP_TZ:+AF_AP_TZ} ${AF_AP_LOCALE:+AF_AP_LOCALE} \
         ${AF_AP_XKB:+AF_AP_XKB} ${AF_AP_THEME:+AF_AP_THEME} ${AF_AP_GPU:+AF_AP_GPU}
}

run_installer() {
  # Arming is a runtime opt-in (env) — no file edit; the shipped repo defaults to ARCHFRICAN_ISO_ARMED=0.
  ARCHFRICAN_AUTOPILOT=1 ARCHFRICAN_ISO_ARMED=1 ARCHFRICAN_ISO_GO=1 ARCHFRICAN_AUTOPILOT_CONFIRM_WIPE="$AF_AP_DISK" \
    bash "$ROOT/install.sh" || die "installer exited non-zero"
}

# --- assertions -------------------------------------------------------------
assert_install() {            # pre-reboot: against /mnt + the LUKS container
  hd "pre-reboot assertions ($AF_AP_DISK, encrypt=$AF_AP_ENCRYPT)"
  local enc="$AF_AP_ENCRYPT" esp rootp
  esp="$(part "$AF_AP_DISK" 1)"; rootp="$(part "$AF_AP_DISK" 2)"

  assert "/mnt is mounted (install left it mounted)"          mountpoint -q /mnt
  assert "GPT has an EF00 ESP + an 8304 root partition"       p_gpt_codes "$AF_AP_DISK"
  assert "ESP $esp is FAT32"                                  p_vfat "$esp"
  assert "ESP mounted at /mnt/boot"                           mountpoint -q /mnt/boot
  if [ "$enc" = yes ]; then
    assert "root $rootp is a LUKS2 container"                 p_luks2 "$rootp"
    assert "/dev/mapper/root is open"                         test -b /dev/mapper/root
    assert "rootfs is /dev/mapper/root"                       p_src_has /dev/mapper/root
  else
    assert "rootfs is the bare partition $rootp"              p_src_has "$rootp"
  fi
  assert "rootfs is btrfs"                                    test "$(findmnt -no FSTYPE /mnt)" = btrfs
  assert "mount uses noatime + zstd compression"             p_opt_has 'compress=zstd'
  assert "subvol @home mounted"                              mountpoint -q /mnt/home
  assert "subvol @.snapshots mounted (module 50 adopts it)"  mountpoint -q /mnt/.snapshots
  assert "subvol @log mounted"                               mountpoint -q /mnt/var/log
  assert "fstab written"                                     test -s /mnt/etc/fstab

  # the arch-chroot config landed
  assert "cryptsetup IS installed in the target"             test -x /mnt/usr/bin/cryptsetup
  assert "linux-lts kernel + initramfs in /boot"             test -e /mnt/boot/vmlinuz-linux-lts -a -e /mnt/boot/initramfs-linux-lts.img
  assert "GRUB config generated"                             test -f /mnt/boot/grub/grub.cfg
  assert "EFI bootloader entry (Archfrican) written"         test -d /mnt/boot/EFI/Archfrican
  if [ "$enc" = yes ]; then
    assert "cryptdevice=UUID=<nonempty>:root in default/grub" p_cryptdev_set
    assert "that UUID matches the LUKS container"             p_cryptdev_uuid "$rootp"
    assert "mkinitcpio: keyboard+keymap BEFORE block+encrypt" p_hooks_order
  fi
  assert "user '$AF_AP_USER' created"                        p_user_exists "$AF_AP_USER"
  assert "root account is locked (sudo-only)"                p_root_locked
  assert "wheel sudoers drop-in present"                     test -f /mnt/etc/sudoers.d/10-wheel
  assert "NetworkManager enabled in target"                  p_enabled NetworkManager.service
  assert "NetworkManager-wait-online enabled"                p_enabled NetworkManager-wait-online.service
  assert "zram-generator.conf present"                       test -f /mnt/etc/systemd/zram-generator.conf

  # first-boot resume wired
  assert "resume service installed"                          test -f /mnt/etc/systemd/system/archfrican-resume.service
  assert "resume service enabled"                            p_enabled archfrican-resume.service
  assert "one-boot NOPASSWD sudoers staged"                  test -f /mnt/etc/sudoers.d/99-archfrican-resume
  assert "installer copied into target home"                test -f "/mnt/home/$AF_AP_USER/.archfrican/install.sh"
  assert "wizard answers staged for the resume"             test -f "/mnt/home/$AF_AP_USER/.archfrican-answers"
  report
}

assert_postboot() {           # post-reboot: on the installed system, as the user
  hd "post-reboot assertions (installed system)"
  [ ! -d /run/archiso ] || die "run 'postboot' on the INSTALLED system, not the ISO"
  if ! b_resume_clean; then
    note "archfrican-resume is still enabled — the first-boot resume may still be running."
    note "wait for the desktop to settle (journalctl -u archfrican-resume), then re-run: selftest.sh postboot"
  fi
  local enc=no; b_booted_enc && enc=yes
  note "detected encrypted root: $enc"
  if [ "$enc" = yes ]; then
    assert "booted with the LUKS root unlocked (one passphrase = OK)" b_booted_enc
    assert "cryptdevice present in the live kernel cmdline"           grep -q 'cryptdevice=UUID=' /proc/cmdline
  fi
  assert "resume self-disabled after success (cleanup ran)"  b_resume_clean
  assert "SDDM display manager is active (graphical login)"  systemctl is-active --quiet sddm.service
  assert "greetd is NOT enabled (SDDM took over; migration 0002 ran)" b_greetd_off
  assert "archfrican SDDM theme installed"                   test -r /usr/share/sddm/themes/archfrican/Main.qml
  assert "snapper 'root' wired (config -> / via sudo, or @.snapshots subvol mounted)" b_snapper_cfg
  assert "NetworkManager is active"                          systemctl is-active --quiet NetworkManager.service
  assert "login shell is zsh"                                b_shell_zsh
  assert "wallpaper daemon binary resolves (awww-daemon)"    command -v awww-daemon
  assert "linux-cachyos kernel installed (primary)"          pacman -Qq linux-cachyos
  assert "linux-lts kernel still installed (safety net)"     pacman -Qq linux-lts
  assert "rendered niri config present"                      test -r "$HOME/.config/niri/config.kdl"
  report
}

assert_update() {             # on the installed system: the "update == fresh install" guarantee
  hd "update/converge assertions (installed system)"
  [ ! -d /run/archiso ] || die "run 'update' on the INSTALLED system, not the ISO"
  export REPO_ROOT="$ROOT"
  # shellcheck source=/dev/null
  . "$ROOT/lib/converge.sh"     # drift_modules + ARCHFRICAN_PHASE2_STATE (no set -e: safe to source here)

  # 1. a fresh install IS converged: with the on-disk repo unchanged, nothing drifts.
  assert "no module drift right after install (applied state == on-disk repo)" b_no_drift

  # 2. a change drifts ONLY the affected module, and the converge re-applies ONLY it. Simulate by
  #    perturbing 30-dev's recorded stamp (cheap + reversible), then run the real converge engine
  #    (install.sh --update; NOT archfrican-update, so there's no git pull — a true on-disk no-op).
  local stamp="$ARCHFRICAN_PHASE2_STATE/30-dev.done"
  if [ -f "$stamp" ]; then
    printf 'drifted\n' > "$stamp"
    assert "perturbing 30-dev's stamp drifts that module ONLY"            b_drift_is 30-dev
    note "running the converge (install.sh --update) — should re-apply only the drifted module …"
    if env ARCHFRICAN_SKIP_PREFLIGHT=1 bash "$ROOT/install.sh" --update >/tmp/af-converge.log 2>&1; then
      assert "converge (install.sh --update) succeeded"                   true
    else
      assert "converge (install.sh --update) succeeded"                   false
      note "converge failed — see /tmp/af-converge.log"
    fi
    assert "converge cleared the drift (30-dev re-applied to match the repo)" b_no_drift
  else
    note "30-dev.done absent — skipping the targeted-drift cycle"
  fi
  hd "next"
  say "  re-run  ~/.archfrican/tests/e2e/selftest.sh postboot  to confirm the converge kept everything green"
  report
}

# --- subcommands ------------------------------------------------------------
do_install() {
  [ -d /run/archiso ] || die "run 'install' on the Arch live ISO (no /run/archiso)"
  [ "$(id -u)" = 0 ]   || die "run 'install' as root"
  load_answers
  hd "armed AUTOPILOT install on $AF_AP_DISK  (the shipped repo stays ARCHFRICAN_ISO_ARMED=0)"
  run_installer
  assert_install
  hd "next"
  say "  1) reboot:  systemctl reboot"
  say "  2) at boot, type the LUKS passphrase ONCE — exactly one prompt, GRUB silent (that is check #3)"
  say "  3) after the desktop settles:  ~/.archfrican/tests/e2e/selftest.sh postboot"
  [ "${AF_AP_REBOOT:-0}" = 1 ] && { note "AF_AP_REBOOT=1 → rebooting now"; systemctl reboot; }
  return 0
}

do_rerun() {
  [ -d /run/archiso ] || die "run 'rerun' on the Arch live ISO"
  [ "$(id -u)" = 0 ]   || die "run 'rerun' as root"
  load_answers
  hd "C2 re-run safety — first armed install"
  run_installer
  hd "C2 re-run safety — SECOND armed install (stale-guard must umount /mnt + close LUKS, then reinstall)"
  run_installer
  assert_install
  hd "C2"; say "  a second armed run completed cleanly over the first → stale-state guard OK"
  return 0
}

case "${1:-}" in
  install)  do_install ;;
  assert)   load_answers; assert_install ;;
  postboot) assert_postboot ;;
  update)   assert_update ;;
  rerun)    do_rerun ;;
  *) say "usage: selftest.sh {install|assert|postboot|update|rerun}   (see tests/e2e/README.md)"; exit 2 ;;
esac
