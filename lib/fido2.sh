#!/usr/bin/env bash
# FIDO2 hardware-key mode. INVARIANT: non-exclusive / no-lockout — every leg is
# ADD-ONLY. PAM lines are `sufficient` ABOVE an untouched password include, so a key
# touch OR the password both authenticate; losing the key never locks you out.
# Sourced after lib/common.sh + lib/ui.sh.

FIDO2_AUTHFILE=/etc/u2f_mappings
FIDO2_APPID="pam://archfrican"
# PAM services that get the key leg by default (greetd is DEFAULT-OFF until VM-proven).
FIDO2_PAM_SERVICES="sudo system-local-login"

# pam-u2f < 1.3.1 had a fallthrough weakness (CVE-2025-23013). Refuse to wire PAM on older.
fido2_assert_version() {
  have pamu2fcfg || { warn "pam-u2f not installed — cannot wire FIDO2 PAM"; return 1; }
  local v; v="$(pacman -Q pam-u2f 2>/dev/null | awk '{print $2}')"; v="${v%%-*}"
  [ -n "$v" ] || { warn "cannot read pam-u2f version — proceeding (CVE-2025-23013 unchecked)"; return 0; }
  if [ "$(printf '%s\n1.3.1\n' "$v" | sort -V | head -1)" = "$v" ] && [ "$v" != "1.3.1" ]; then
    die "pam-u2f $v < 1.3.1 (CVE-2025-23013 fallthrough) — refusing to wire FIDO2 PAM"
  fi
}

# Enroll PRIMARY (+ strongly-recommended BACKUP) key into $FIDO2_AUTHFILE. Touches happen
# HERE (wizard time, real TTY + key). Never die on a touch timeout — it's skippable.
fido2_enroll() {                   # fido2_enroll <username>
  have pamu2fcfg || { warn "pam-u2f not installed yet — FIDO2 enroll skipped"; return 1; }
  local user="$1" line extra
  ui_note "Touch your PRIMARY security key when it blinks (30s)…"
  line="$(timeout 30 pamu2fcfg -o "$FIDO2_APPID" -i "$FIDO2_APPID" -u "$user" 2>/dev/null || true)"
  [ -n "$line" ] || { warn "no key registered (timeout/declined) — FIDO2 not enabled"; return 1; }
  if ui_confirm "Register a BACKUP key now? (strongly recommended — swap keys when prompted)"; then
    ui_note "Now touch your BACKUP key when it blinks (30s)…"
    extra="$(timeout 30 pamu2fcfg -n -o "$FIDO2_APPID" -i "$FIDO2_APPID" 2>/dev/null || true)"
    [ -n "$extra" ] && line="${line}${extra}"   # pamu2fcfg -n already emits a leading ':'
  else
    warn "no backup key — if you lose this key you fall back to your PASSWORD (which still works)."
  fi
  printf '%s\n' "$line" | sudo tee "$FIDO2_AUTHFILE" >/dev/null
  sudo chmod 0644 "$FIDO2_AUTHFILE"
  ok "registered $(printf '%s' "$line" | awk -F: '{print NF-1}') key(s) for $user in $FIDO2_AUTHFILE"
}

# The single PAM line we insert (sufficient + cue; nouserok so users WITHOUT a mapping
# are skipped, not blocked; origin/appid pinned explicitly).
fido2_pam_line() {
  printf 'auth\tsufficient\tpam_u2f.so cue nouserok origin=%s appid=%s authfile=%s\n' \
    "$FIDO2_APPID" "$FIDO2_APPID" "$FIDO2_AUTHFILE"
}

# Insert our line as the FIRST auth line of a PAM service file (idempotent, backed up once).
fido2_pam_insert() {               # fido2_pam_insert <pam-service-file>
  local f="$1" tmp
  [ -r "$f" ] || { warn "PAM file missing: $f — skipping"; return 0; }
  grep -q 'pam_u2f\.so' "$f" && { ok "FIDO2 already present in $f"; return 0; }
  [ -e "$f.archfrican.bak" ] || sudo cp -a "$f" "$f.archfrican.bak"
  tmp="$(mktemp)"
  awk -v line="$(fido2_pam_line)" '
    !ins && /^[[:space:]]*auth/ { print line; ins=1 }
    { print }
    END { if (!ins) print line }       # no auth line? still add ours
  ' "$f" > "$tmp"
  sudo install -m 0644 "$tmp" "$f"; rm -f "$tmp"
  ok "FIDO2 auth added to $(basename "$f") (password remains a valid fallback)"
}

# Wire the default PAM services. ADD-ONLY; password include left untouched.
fido2_write_pam() {
  fido2_assert_version || return 1
  local svc
  for svc in $FIDO2_PAM_SERVICES; do fido2_pam_insert "/etc/pam.d/$svc"; done
}

# The visudo-analogue for PAM (no `pam -cf` exists). Refuses to leave a lockout-prone stack.
# Static asserts run WITHOUT pamtester so a fresh box still self-checks.
fido2_pam_selfcheck() {            # fido2_pam_selfcheck <service>
  local svc="$1" rc=0
  local f="/etc/pam.d/$svc"
  [ -r "$f" ] || { warn "selfcheck: $f missing"; return 1; }
  grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_u2f\.so' "$f" \
    || { warn "selfcheck FAIL ($svc): pam_u2f is not 'sufficient'"; rc=1; }
  grep -qE '^auth[[:space:]]+(include|substack)[[:space:]]+(system-|common-)' "$f" \
    || { warn "selfcheck FAIL ($svc): password include missing — would be key-only!"; rc=1; }
  # nothing ELSE 'sufficient' above the password include (the no-lockout / CVE guarantee)
  awk '
    /^auth[[:space:]]+(include|substack)[[:space:]]+(system-|common-)/ { exit }
    /^auth[[:space:]]+sufficient/ && $3 != "pam_u2f.so" { bad=1 }
    END { exit (bad?1:0) }
  ' "$f" || warn "selfcheck note ($svc): a non-u2f 'sufficient' auth precedes the password (e.g. fingerprint) — verify it also falls through; not a lockout, the password include is intact"
  if [ "$rc" -eq 0 ]; then
    ok "FIDO2 selfcheck OK for $svc — key OR password both authenticate"
    have pamtester && ui_note "Verify in another terminal:  pamtester $svc $USER authenticate  (touch key, or type password)"
  fi
  return "$rc"
}
