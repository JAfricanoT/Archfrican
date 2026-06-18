#!/usr/bin/env bash
# Phase 1 — the Arch live-USB full install. Flow: preflight -> wizard (disk,
# encryption, host/user/locale/theme/GPU) -> generate archinstall config+creds ->
# archinstall -> inject the self-cleaning first-boot resume -> reboot. The new
# system finishes the desktop/dev layer automatically (see lib/phase2.sh +
# templates/archfrican-resume.service). Sourced after common.sh + ui.sh + env.sh +
# detect-gpu.sh + preflight.sh + host-config.sh + phase2.sh (for on_err) + disk.sh.
#
# ┌─ SAFETY: two independent gates stand between this code and a wiped disk ─────┐
# │ 1) ARCHFRICAN_ISO_ARMED ships 0. Unarmed -> we run `archinstall --dry-run`   │
# │    ONLY: it validates the config and prints what it WOULD do; no disk is     │
# │    touched. Arming ALSO requires the runtime opt-in ARCHFRICAN_ISO_GO=1.     │
# │ 2) confirm_wipe (lib/disk.sh) — retype the device name before the format.    │
# │ The schema below is PROVISIONAL until captured + validated on a VM. See      │
# │ docs/STAGE2-VALIDATION.md.                                                    │
# └──────────────────────────────────────────────────────────────────────────────┘

# Flip to 1 ONLY in the commit that lands a VM-validated archinstall config.
ARCHFRICAN_ISO_ARMED=0

# Build the archinstall config from the committed base + the wizard's answers.
# Uses python3 (always on the Arch ISO — archinstall is python) so JSON escaping
# is correct and we add no dependency. The disk/encryption shape is PROVISIONAL:
# the VM dry-run produces the authoritative 2.x schema we then commit.
gen_config() {                      # gen_config <disk> <encrypt yes|no> <host> <tz>
  AF_BASE="$REPO_ROOT/archinstall/user_config.json" \
  AF_DISK="$1" AF_ENC="$2" AF_HOST="$3" AF_TZ="$4" \
  python3 - <<'PY'
import json, os
with open(os.environ["AF_BASE"]) as f:
    cfg = json.load(f)
cfg["hostname"] = os.environ["AF_HOST"]
cfg["timezone"] = os.environ["AF_TZ"]
dc = cfg.setdefault("disk_config", {})
# Inject the chosen device so a --silent/--dry-run run has a concrete target
# (the committed base uses default_layout, which otherwise asks interactively).
dc["device"] = os.environ["AF_DISK"]
if os.environ["AF_ENC"] == "yes":
    # Encrypt the root partition only; the ESP stays plaintext so GRUB never
    # prompts -> a single passphrase at the initramfs. Exact keys validated on VM.
    dc["encryption"] = {"encryption_type": "luks", "partitions": "root"}
# root disabled / sudo-only: no root_password is emitted here or in creds.
print(json.dumps(cfg, indent=2))
PY
}

# Build the credentials file. Passwords arrive on STDIN (line 1 = user pw, line 2
# = disk passphrase) so they never hit argv or the environment. The program is
# written to a (secret-free) temp file and run with the caller's stdin intact —
# a `python3 - <<EOF` heredoc would BE python's stdin and swallow the passwords.
# Caller writes the result to a 0600 tmpfs file that _wipe_creds shreds after.
gen_creds() {                       # gen_creds <user> <encrypt yes|no>   (pws on stdin)
  local prog rc=0; prog="$(mktemp)"
  cat > "$prog" <<'PY'
import json, os, sys
lines = sys.stdin.read().split("\n")
user_pw = lines[0] if len(lines) > 0 else ""
disk_pw = lines[1] if len(lines) > 1 else ""
creds = {
    "users": [{"username": os.environ["AF_USER"], "password": user_pw, "sudo": True}],
    "root_password": "",            # root disabled / sudo-only
}
if os.environ["AF_ENC"] == "yes":
    creds["encryption_password"] = disk_pw
json.dump(creds, sys.stdout, indent=2)
PY
  AF_USER="$1" AF_ENC="$2" python3 "$prog" || rc=$?
  rm -f "$prog"
  return "$rc"
}

# Shred the credentials file (it held passwords) and drop the work dir.
_wipe_creds() {                     # _wipe_creds <creds-file> <workdir>
  [ -f "$1" ] && { shred -u "$1" 2>/dev/null || rm -f "$1"; }
  [ -n "${2:-}" ] && rm -rf "$2"
}

# The non-secret wizard answers the first-boot resume needs (no password — that
# was set during archinstall; the resume re-applies everything else idempotently).
gen_answers() {                     # gen_answers <host> <user> <tz> <locale> <xkb> <theme> <gpu>
  printf 'ARCHFRICAN_HOST=%q\nARCHFRICAN_USER=%q\nARCHFRICAN_TZ=%q\nARCHFRICAN_LOCALE=%q\nARCHFRICAN_XKB=%q\nARCHFRICAN_THEME=%q\nARCHFRICAN_GPU=%q\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# Install the self-cleaning first-boot resume into the freshly-installed target.
# Runs ONLY on the armed (real-install) path, after archinstall succeeds. Requires
# the target mounted at /mnt (a-confirmar #5: whether --silent leaves it mounted).
inject_resume() {                   # inject_resume <user> <host> <tz> <locale> <xkb> <theme> <gpu>
  local user="$1" host="$2" tz="$3" loc="$4" xkb="$5" theme="$6" gpu="$7"
  local src; src="$(clone_dest)"    # the ISO self-clone, e.g. /root/.archfrican
  mountpoint -q /mnt || die "target not mounted at /mnt — cannot wire the resume (see docs/STAGE2-VALIDATION.md a-confirmar #5)"
  local home="/mnt/home/$user"
  [ -d "$home" ] || die "expected $home (archinstall should have created user '$user')"

  substep "copying the installer into the new system ($home/.archfrican)"
  rm -rf "$home/.archfrican"; cp -a "$src" "$home/.archfrican"

  substep "staging the wizard answers + theme/keyboard for the headless resume"
  gen_answers "$host" "$user" "$tz" "$loc" "$xkb" "$theme" "$gpu" > "$home/.archfrican-answers"
  install -d -m 0700 "$home/.config"
  printf '%s\n' "$theme" > "$home/.config/.archfrican-theme"
  printf '%s\n' "$xkb"   > "$home/.config/.archfrican-kbd"
  arch-chroot /mnt chown -R "$user:$user" "/home/$user/.archfrican" \
    "/home/$user/.archfrican-answers" "/home/$user/.config"
  chmod 0600 "$home/.archfrican-answers"

  substep "writing the temporary NOPASSWD sudoers drop-in (removed after resume)"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > /mnt/etc/sudoers.d/00-archfrican-resume
  chmod 0440 /mnt/etc/sudoers.d/00-archfrican-resume
  arch-chroot /mnt visudo -cf /etc/sudoers.d/00-archfrican-resume >/dev/null \
    || die "resume sudoers drop-in invalid — refusing to leave a broken sudo"

  substep "installing + enabling archfrican-resume.service (runs once on first boot)"
  sed "s/@USER@/$user/g" "$REPO_ROOT/templates/archfrican-resume.service" \
    > /mnt/etc/systemd/system/archfrican-resume.service
  arch-chroot /mnt systemctl enable archfrican-resume.service
  ok "first-boot resume wired — the desktop/dev layer installs itself after reboot"
}

run_phase1() {
  set -E; trap on_err ERR
  step_total 6

  step "Preflight" "verifying this live environment can install Archfrican"
  preflight iso

  # ---- wizard ---------------------------------------------------------------
  step "Setup wizard" "disk · encryption · hostname · user · locale · keyboard · theme · GPU"
  ui_install_gum
  local DETECTED_GPU; DETECTED_GPU="$(detect_gpu)"

  local DISK ENCRYPT HOST USER_NAME TZ LOCALE XKB THEME GPU
  DISK="$(pick_disk)"
  if ui_confirm "¿Cifrar el disco $DISK? (recomendado)"; then ENCRYPT=yes; else ENCRYPT=no; fi
  HOST="$(ui_input 'Hostname' archfrican)"
  USER_NAME="$(ui_input 'Primary user' arch)"
  TZ="$(ui_input 'Timezone' America/New_York)"
  LOCALE="$(ui_input 'Locale (LANG)' en_US.UTF-8)"
  XKB="$(ui_input 'Keyboard layout (xkb: us, latam, es, ...)' us)"
  THEME="$(ui_choose 'Initial theme' macos-dark macos-light catppuccin-mocha tokyo-night)"
  GPU="$(ui_choose "GPU profile (detected: $DETECTED_GPU)" \
         "$DETECTED_GPU" amd intel nvidia hybrid-intel-nvidia hybrid-amd-nvidia hybrid-amd-intel)"
  # Passwords last, and never echoed. Collected here so config gen has them on stdin.
  local USER_PW DISK_PW=""
  USER_PW="$(ui_password "Password for $USER_NAME")"
  [ "$ENCRYPT" = yes ] && DISK_PW="$(ui_password 'Disk passphrase')"

  # ---- generate archinstall config + creds (creds: 0600, tmpfs, shredded) ----
  step "Preparing archinstall" "generating the disk + credential config for $DISK"
  local workdir cfg creds
  workdir="$(mktemp -d)"; cfg="$workdir/user_configuration.json"; creds="$workdir/user_credentials.json"
  ( umask 077; : > "$creds" )       # lock the creds file down before a byte lands in it
  gen_config "$DISK" "$ENCRYPT" "$HOST" "$TZ" > "$cfg"
  printf '%s\n%s\n' "$USER_PW" "$DISK_PW" | gen_creds "$USER_NAME" "$ENCRYPT" > "$creds"
  USER_PW=""; DISK_PW=""             # drop the plaintext from this shell's memory
  substep "config:      $cfg"
  substep "credentials: $creds (0600, tmpfs, shredded after install)"

  # ---- the destructive step, behind the two gates ---------------------------
  step "Installing the base system" "archinstall partitions, formats and bootstraps $DISK"
  if [ "$ARCHFRICAN_ISO_ARMED" = 1 ] && [ "${ARCHFRICAN_ISO_GO:-0}" = 1 ]; then
    confirm_wipe "$DISK" || { _wipe_creds "$creds" "$workdir"; die "aborted at the disk-erase confirmation (nothing was changed)"; }
    substep "running archinstall (silent, unattended) — this formats $DISK"
    archinstall --silent --config "$cfg" --creds "$creds" \
      || { _wipe_creds "$creds" "$workdir"; die "archinstall failed (see its log above) — the disk may be partially written"; }
    _wipe_creds "$creds" "$workdir"
  else
    warn "SAFE MODE — the ISO installer is NOT armed (ARCHFRICAN_ISO_ARMED=$ARCHFRICAN_ISO_ARMED, ARCHFRICAN_ISO_GO=${ARCHFRICAN_ISO_GO:-0})."
    warn "Running 'archinstall --dry-run': it validates the config and saves what it WOULD do. NO disk is touched."
    substep "running archinstall --dry-run (no changes)"
    best_effort archinstall --dry-run --config "$cfg" --creds "$creds"
    _wipe_creds "$creds" "$workdir"
    ok  "Dry-run done. To finish enabling Stage 2: capture archinstall's saved config, validate it on a VM,"
    ok  "commit the real schema, set ARCHFRICAN_ISO_ARMED=1, then re-run with ARCHFRICAN_ISO_GO=1."
    ok  "Full procedure: docs/STAGE2-VALIDATION.md"
    return 0
  fi

  # ---- wire the post-reboot finish + reboot ---------------------------------
  step "Wiring the post-reboot finish" "first-boot service that adds the niri desktop + dev layer"
  inject_resume "$USER_NAME" "$HOST" "$TZ" "$LOCALE" "$XKB" "$THEME" "$GPU"

  step "Reboot" "into your new encrypted system; the rest installs automatically on first boot"
  ok "Base install complete. Hostname $HOST · user $USER_NAME (sudo) · GPU $GPU · theme $THEME."
  if ui_confirm 'Reboot now?'; then
    ok "rebooting"; systemctl reboot
  else
    warn "Reboot when ready: systemctl reboot. After you unlock the disk once, the install finishes on its own."
  fi
}
