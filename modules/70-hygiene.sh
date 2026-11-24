#!/usr/bin/env bash
# Phase 2, step 8: hygiene. Schedules maintenance timers (none destructive) and the weekly
# health check. Reuses tools already in base.txt (pacman-contrib, reflector, smartmontools,
# fwupd) + btrfs-progs/util-linux. Nothing here auto-updates or auto-removes — it notifies.
source "$(dirname "$0")/../lib/common.sh"

# --- state dir for the converge/update machinery (manifest, managed ledger, migration version) ---
substep "ensuring the Archfrican state dir (/var/lib/archfrican)"
best_effort sudo install -d -m 0755 /var/lib/archfrican

# --- maintenance timers (heavy ones gated to AC power + jittered) ------------
substep "scheduling package-cache trim (paccache, keep 3)"
resilient_enable paccache.timer

substep "scheduling fstrim (weekly, on AC)"
write_system_file /etc/systemd/system/fstrim.service.d/10-archfrican.conf 0644 <<'UNIT'
[Unit]
ConditionACPower=true
UNIT
resilient_enable fstrim.timer

# Btrfs-only, and btrfs-progs (hence the unit) ships in the bedrock set even on an ext4 root — so
# resilient_enable's "does the unit exist?" check would happily arm a timer that fails every month,
# turning the health check's failed-units probe permanently red. Gate on the actual filesystem, the
# same way lib/health.sh skips its scrub probe.
if is_btrfs /; then
  substep "scheduling a monthly Btrfs scrub of / (on AC, jittered)"
  write_system_file /etc/systemd/system/btrfs-scrub@.service.d/10-archfrican.conf 0644 <<'UNIT'
[Unit]
ConditionACPower=true
UNIT
  write_system_file /etc/systemd/system/btrfs-scrub@.timer.d/10-archfrican.conf 0644 <<'UNIT'
[Timer]
RandomizedDelaySec=1h
UNIT
  resilient_enable "btrfs-scrub@-.timer"   # @- = the / subvolume (drops the redundant @home scrub)
else
  ok "Btrfs scrub not scheduled — root is not Btrfs (nothing to scrub)"
fi

substep "enabling SMART disk monitoring + firmware metadata refresh"
resilient_enable smartd.service
resilient_enable fwupd-refresh.timer

# reflector overwrites the mirrorlist unattended -> OPT-IN (default off). The config is written
# either way so an opt-in (or archfrican-update's refresh) is fast and warning-free:
# `--sort score` ranks mirrors from Arch's live status JSON in <0.2s with ZERO timeout warnings
# (whereas `--latest 20 --sort rate` downloaded ~8 MB from 20 random worldwide mirrors one by one,
# taking ~53s and spamming `failed to rate ... timed out` warnings on non-European connections).
substep "writing the reflector config (fast --sort score, 100% complete HTTPS mirrors)"
write_system_file /etc/xdg/reflector/reflector.conf 0644 <<'REFL'
--save /etc/pacman.d/mirrorlist
--protocol https
--completion-percent 100
--age 12
--number 15
--sort score
REFL
if [ "${ARCHFRICAN_ENABLE_REFLECTOR:-0}" = 1 ]; then
  substep "enabling reflector.timer (ARCHFRICAN_ENABLE_REFLECTOR=1)"
  resilient_enable reflector.timer
else
  ok "reflector.timer left OFF (set ARCHFRICAN_ENABLE_REFLECTOR=1 to auto-rank mirrors)"
fi

# --- weekly health check: a USER timer so it can notify-send to the session ---
substep "arming the weekly health check (archfrican-doctor --notify)"
udir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; mkdir -p "$udir"
cat > "$udir/archfrican-health.service" <<'SVC'
[Unit]
Description=Archfrican weekly health check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/archfrican-doctor --notify
SVC
cat > "$udir/archfrican-health.timer" <<'TMR'
[Unit]
Description=Run the Archfrican health check weekly
[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h
[Install]
WantedBy=timers.target
TMR
best_effort systemctl --user daemon-reload
best_effort systemctl --user enable archfrican-health.timer

# --- expose the update gate on PATH ------------------------------------------
substep "installing the archfrican-update command to /usr/local/bin"
chmod +x "$REPO_ROOT/bin/archfrican-update"
sudo ln -sf "$REPO_ROOT/bin/archfrican-update" /usr/local/bin/archfrican-update

# --- safety-gated auto-update after >30 days without upgrades (system timer) -
# Installed as a root-owned COPY (never a symlink into user-writable $HOME — same rule as
# archfrican-power-auto and archfrican-multicast-route). Runs daily on AC power; is a fast no-op
# until >30 days have elapsed since the last full upgrade, and then requires Btrfs+snapper, free
# disk headroom, no Arch News manual-intervention notice, and a fresh pre-snapshot before running
# official `pacman -Su --noconfirm` (never AUR, never forces a reboot). Opt out: /etc/archfrican/no-auto-update.
substep "arming >30-day safety-gated auto-update timer (archfrican-auto-update.timer)"
sudo install -D -m 0755 "$REPO_ROOT/bin/archfrican-auto-update" /usr/local/bin/archfrican-auto-update
write_system_file /etc/systemd/system/archfrican-auto-update.service 0644 <<'AU_SVC'
[Unit]
Description=Archfrican automatic official package update (triggers after >30 days without updates)
After=network-online.target
Wants=network-online.target
ConditionACPower=true

[Service]
Type=oneshot
ExecStart=/usr/local/bin/archfrican-auto-update
Nice=15
IOSchedulingClass=idle
AU_SVC
write_system_file /etc/systemd/system/archfrican-auto-update.timer 0644 <<'AU_TMR'
[Unit]
Description=Check daily whether Archfrican has gone >30 days without a system update

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
AU_TMR
sudo systemctl daemon-reload
resilient_enable archfrican-auto-update.timer

# --- hourly repo-update check: a USER timer so it can notify-send to the session ---
# Separate from archfrican-health above (that's a local config/system health report; this is
# purely "does origin have commits we don't" — a fast, silent git fetch --depth 1 unless there's
# something to show). Clicking the notification's "Update now" action runs archfrican-update --run.
substep "arming the hourly repo-update check (archfrican-update --notify)"
cat > "$udir/archfrican-update-check.service" <<'SVC'
[Unit]
Description=Archfrican repo-update check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/archfrican-update --notify
SVC
cat > "$udir/archfrican-update-check.timer" <<'TMR'
[Unit]
Description=Check hourly for new Archfrican commits
[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
TMR
best_effort systemctl --user daemon-reload
best_effort systemctl --user enable archfrican-update-check.timer

ok "hygiene module done — timers scheduled, weekly health check + hourly update check armed, archfrican-update ready"
