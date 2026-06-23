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

substep "scheduling a monthly Btrfs scrub of / (on AC, jittered)"
write_system_file /etc/systemd/system/btrfs-scrub@.service.d/10-archfrican.conf 0644 <<'UNIT'
[Unit]
ConditionACPower=true
UNIT
write_system_file /etc/systemd/system/btrfs-scrub@.timer.d/10-archfrican.conf 0644 <<'UNIT'
[Timer]
RandomizedDelaySec=1h
UNIT
resilient_enable "btrfs-scrub@-.timer"     # @- = the / subvolume (drops the redundant @home scrub)

substep "enabling SMART disk monitoring + firmware metadata refresh"
resilient_enable smartd.service
resilient_enable fwupd-refresh.timer

# reflector overwrites the mirrorlist unattended -> OPT-IN (default off). The config is written
# either way so an opt-in (or a manual `reflector @/etc/xdg/reflector/reflector.conf`) is ready.
substep "writing the reflector config (mirror auto-ranking is opt-in)"
write_system_file /etc/xdg/reflector/reflector.conf 0644 <<'REFL'
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 20
--sort rate
--age 12
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

ok "hygiene module done — timers scheduled, weekly health check armed, archfrican-update ready"
