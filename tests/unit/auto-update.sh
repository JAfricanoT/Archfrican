#!/usr/bin/env bash
# Unit test for bin/archfrican-auto-update (>30-day safety-gated automatic system update).
# Fixture/mock-based: needs no root, no network, no Btrfs, and no real pacman. Verifies every
# fail-closed safety gate so an unattended upgrade can NEVER touch pacman without a safety net:
#   1. Opt-out flag (/etc/archfrican/no-auto-update) skips cleanly.
#   2. Recent update (< 30 days via last-update stamp) skips cleanly.
#   3. Recent manual pacman -Syu (< 30 days in pacman.log) skips even without stamp.
#   4. Stale (> 30 days) on non-Btrfs root aborts without calling pacman.
#   5. Stale (> 30 days) with low disk space (< 5000 MiB) aborts without calling pacman.
#   6. Stale (> 30 days) with Arch News "manual intervention" aborts without calling pacman.
#   7. Stale (> 30 days) where Snapper fails aborts BEFORE calling pacman.
#   8. Stale (> 30 days) with all gates green creates snapshot -> refreshes keyring -> runs pacman -Su
#      -> updates last-update stamp.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/bin/archfrican-auto-update"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MOCK="$WORK/bin"; mkdir -p "$MOCK"
LOG="$WORK/calls.log"

# Mock external binaries used by archfrican-auto-update.
cat > "$MOCK/findmnt" <<'EOF'
#!/bin/sh
echo "${MOCK_FSTYPE:-btrfs}"
EOF
cat > "$MOCK/df" <<'EOF'
#!/bin/sh
printf 'Avail\n%sM\n' "${MOCK_AVAIL_MB:-20000}"
EOF
cat > "$MOCK/mountpoint" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$MOCK/curl" <<'EOF'
#!/bin/sh
[ "${MOCK_OFFLINE:-0}" = 1 ] && exit 7
printf '%s\n' "${MOCK_NEWS_XML:-<rss><channel><title>Arch Linux</title><item><title>Regular news</title></item></channel></rss>}"
EOF
cat > "$MOCK/snapper" <<'EOF'
#!/bin/sh
printf 'snapper %s\n' "$*" >> "$MOCK_CALL_LOG"
[ "${MOCK_SNAPPER_FAIL:-0}" = 1 ] && exit 1
echo "42"
EOF
cat > "$MOCK/pacman" <<'EOF'
#!/bin/sh
printf 'pacman %s\n' "$*" >> "$MOCK_CALL_LOG"
[ "$1" = "-Q" ] && exit 0
exit "${MOCK_PACMAN_RC:-0}"
EOF
cat > "$MOCK/reflector" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$MOCK/notify-send" <<'EOF'
#!/bin/sh
printf 'notify %s\n' "$*" >> "$MOCK_CALL_LOG"
EOF
chmod +x "$MOCK"/*

NOW="$(date +%s)"
OLD_EPOCH=$(( NOW - 35 * 86400 ))
NEW_EPOCH=$(( NOW - 5 * 86400 ))

run_case() {
  rm -f "$LOG" "$WORK/lock" "$WORK/no-auto" "$WORK/stamp" "$WORK/pacman.log" "$WORK/db.lck"
  rm -rf "$WORK/lock"
  : > "$LOG"
  MOCK_CALL_LOG="$LOG" \
  PATH="$MOCK:$PATH" \
  ARCHFRICAN_AUTO_UPDATE_CONF="$WORK/none.conf" \
  ARCHFRICAN_AUTO_UPDATE_DISABLE="$WORK/no-auto" \
  ARCHFRICAN_LAST_UPDATE_STAMP="$WORK/stamp" \
  ARCHFRICAN_PACMAN_LOG="$WORK/pacman.log" \
  ARCHFRICAN_PACMAN_LOCK="$WORK/db.lck" \
  ARCHFRICAN_AUTO_UPDATE_LOCK="$WORK/lock" \
  ARCHFRICAN_MIRRORLIST="$WORK/mirrorlist" \
  "$@" bash "$SCRIPT" >/dev/null 2>&1
}

# ---- 1. opt-out flag skips completely ------------------------------------------------------------
rm -f "$LOG"; : > "$LOG"
printf '%s\n' "$OLD_EPOCH" > "$WORK/stamp"
: > "$WORK/no-auto"
MOCK_CALL_LOG="$LOG" PATH="$MOCK:$PATH" \
  ARCHFRICAN_AUTO_UPDATE_CONF="$WORK/none.conf" \
  ARCHFRICAN_AUTO_UPDATE_DISABLE="$WORK/no-auto" \
  ARCHFRICAN_LAST_UPDATE_STAMP="$WORK/stamp" \
  ARCHFRICAN_PACMAN_LOG="$WORK/pacman.log" \
  ARCHFRICAN_PACMAN_LOCK="$WORK/db.lck" \
  ARCHFRICAN_AUTO_UPDATE_LOCK="$WORK/lock" \
  bash "$SCRIPT" >/dev/null 2>&1
if ! grep -q 'pacman' "$LOG"; then _ok "opt-out flag skips auto-update"
else _no "opt-out flag still called pacman"; fi
rm -f "$WORK/no-auto"

# ---- 2. recent stamp (< 30d) skips ---------------------------------------------------------------
rm -f "$LOG" "$WORK/pacman.log"; : > "$LOG"
printf '%s\n' "$NEW_EPOCH" > "$WORK/stamp"
MOCK_CALL_LOG="$LOG" PATH="$MOCK:$PATH" \
  ARCHFRICAN_AUTO_UPDATE_CONF="$WORK/none.conf" \
  ARCHFRICAN_AUTO_UPDATE_DISABLE="$WORK/no-auto" \
  ARCHFRICAN_LAST_UPDATE_STAMP="$WORK/stamp" \
  ARCHFRICAN_PACMAN_LOG="$WORK/pacman.log" \
  ARCHFRICAN_PACMAN_LOCK="$WORK/db.lck" \
  ARCHFRICAN_AUTO_UPDATE_LOCK="$WORK/lock" \
  bash "$SCRIPT" >/dev/null 2>&1
if ! grep -q 'pacman' "$LOG"; then _ok "recent stamp (5d ago) skips cleanly"
else _no "recent stamp triggered update"; fi

# ---- 3. recent manual pacman -Syu in pacman.log skips even without stamp -------------------------
rm -f "$LOG" "$WORK/stamp"; : > "$LOG"
printf '[%s] [PACMAN] starting full system upgrade\n' "$(date -d "@$NEW_EPOCH" -Iseconds)" > "$WORK/pacman.log"
MOCK_CALL_LOG="$LOG" PATH="$MOCK:$PATH" \
  ARCHFRICAN_AUTO_UPDATE_CONF="$WORK/none.conf" \
  ARCHFRICAN_AUTO_UPDATE_DISABLE="$WORK/no-auto" \
  ARCHFRICAN_LAST_UPDATE_STAMP="$WORK/stamp" \
  ARCHFRICAN_PACMAN_LOG="$WORK/pacman.log" \
  ARCHFRICAN_PACMAN_LOCK="$WORK/db.lck" \
  ARCHFRICAN_AUTO_UPDATE_LOCK="$WORK/lock" \
  bash "$SCRIPT" >/dev/null 2>&1
if ! grep -q 'pacman' "$LOG"; then _ok "recent manual pacman -Syu (5d ago) resets 30d clock"
else _no "recent pacman.log upgrade was ignored"; fi

# Helper for stale (35d old) tests
run_stale() {
  rm -f "$LOG" "$WORK/pacman.log" "$WORK/db.lck" "$WORK/no-auto"
  rm -rf "$WORK/lock"
  : > "$LOG"
  printf '%s\n' "$OLD_EPOCH" > "$WORK/stamp"
  env MOCK_CALL_LOG="$LOG" PATH="$MOCK:$PATH" \
    ARCHFRICAN_AUTO_UPDATE_CONF="$WORK/none.conf" \
    ARCHFRICAN_AUTO_UPDATE_DISABLE="$WORK/no-auto" \
    ARCHFRICAN_LAST_UPDATE_STAMP="$WORK/stamp" \
    ARCHFRICAN_PACMAN_LOG="$WORK/pacman.log" \
    ARCHFRICAN_PACMAN_LOCK="$WORK/db.lck" \
    ARCHFRICAN_AUTO_UPDATE_LOCK="$WORK/lock" \
    ARCHFRICAN_MIRRORLIST="$WORK/mirrorlist" \
    "$@" bash "$SCRIPT" >/dev/null 2>&1
}

# ---- 4. non-Btrfs root aborts safely -------------------------------------------------------------
run_stale MOCK_FSTYPE=ext4
if ! grep -q 'pacman' "$LOG"; then _ok "non-Btrfs root aborts without calling pacman"
else _no "non-Btrfs root ran pacman unattended"; fi

# ---- 5. low disk space (< 5000 MiB) aborts safely ------------------------------------------------
run_stale MOCK_AVAIL_MB=2000
if ! grep -q 'pacman' "$LOG"; then _ok "low disk space (2000M < 5000M) aborts without calling pacman"
else _no "low disk space still ran pacman"; fi

# ---- 6. Arch News 'manual intervention' aborts safely --------------------------------------------
run_stale MOCK_NEWS_XML='<rss><channel><title>Arch Linux</title><item><title>linux-firmware upgrade requires manual intervention</title></item></channel></rss>'
if ! grep -q 'pacman' "$LOG"; then _ok "Arch News manual intervention aborts without calling pacman"
else _no "manual intervention news was ignored"; fi

# ---- 7. failed Snapper snapshot aborts BEFORE pacman ---------------------------------------------
run_stale MOCK_SNAPPER_FAIL=1 || true
if grep -q '^snapper ' "$LOG" && ! grep -q '^pacman ' "$LOG"; then
  _ok "failed Snapper snapshot aborts BEFORE touching pacman"
else
  _no "failed snapshot did not block pacman: $(cat "$LOG")"
fi

# ---- 8. happy path (>30d, all gates green) -------------------------------------------------------
if run_stale; then _ok "stale (>30d) happy path exited 0"
else _no "stale (>30d) happy path exited nonzero"; fi
if grep -q '^snapper -c root create' "$LOG"; then _ok "happy path created Snapper pre-snapshot"
else _no "happy path skipped Snapper pre-snapshot"; fi
if grep -q '^pacman -Sy --needed --noconfirm archlinux-keyring' "$LOG"; then _ok "happy path refreshed archlinux-keyring first"
else _no "happy path skipped keyring refresh"; fi
if grep -q '^pacman -Su --noconfirm' "$LOG"; then _ok "happy path ran official pacman -Su --noconfirm"
else _no "happy path did not run pacman -Su --noconfirm"; fi
new_stamp="$(cat "$WORK/stamp")"
if [ "$new_stamp" -gt "$OLD_EPOCH" ]; then _ok "happy path updated last-update stamp"
else _no "happy path did not update last-update stamp"; fi

# ---- 9. reflector tuning: --sort score + global CDNs (no slow --sort rate timeouts) --------------
if grep -vE '^[[:space:]]*#' "$ROOT/modules/70-hygiene.sh" | grep -qF -- '--sort score' \
   && grep -vE '^[[:space:]]*#' "$ROOT/modules/70-hygiene.sh" | grep -qF -- '--completion-percent 100' \
   && ! grep -vE '^[[:space:]]*#' "$ROOT/modules/70-hygiene.sh" | grep -qF -- '--sort rate'; then
  _ok "70-hygiene.sh configures reflector with fast --sort score (no --sort rate timeouts)"
else
  _no "70-hygiene.sh reflector config regressed"
fi
if grep -qF 'fastly.mirror.pkgbuild.com' "$ROOT/bin/archfrican-update" \
   && grep -qF 'geo.mirror.pkgbuild.com' "$ROOT/bin/archfrican-update"; then
  _ok "archfrican-update pins global Arch CDNs (fastly + geo) ahead of reflector fallbacks"
else
  _no "archfrican-update missing global Arch CDN pin"
fi

printf '\nauto-update unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
