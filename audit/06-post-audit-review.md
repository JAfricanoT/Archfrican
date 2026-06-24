# Phase 6 (addendum) — Review of the post-audit feature work

**Why this exists:** the original audit (Phases 0-5, `audit/00`–`05`) was frozen at the installer core.
After it, the maintainer added **11 feature commits** (`0d9e918`→`135c701`, ~2,869 lines) the audit's
lenses never examined: TPM2 LUKS auto-unlock, Secure Boot (sbctl), fingerprint PAM, KDE Connect/LocalSend,
backup/rollback, Flatpak, gaming, a11y, onboarding, plus ~35 new user-session scripts. This addendum
reviews that surface.

**Method:** read-only. Deep-read every security/network/data/boot-critical script + the 3 new modules
(`35-apps`, `45-print`, `65-gaming`) + the SDDM QML greeter, plus a danger-pattern sweep (`eval`/`rm -rf`/
`mkfs`/`dd`/`curl|sh`/variable-into-`/etc`) and `shellcheck` over all ~35 new scripts. *Honest caveat:*
the planned 5-lens adversarial **subagent fan-out failed on transient API errors**, so this was done
solo (each finding still hand-verified against the code); the ~20 cosmetic niri/gsettings wrappers were
**swept** (clean) but not line-by-line read; **VM validation** of boot-critical code is the maintainer's.

## Verdict

**The post-audit code is well-built — the maintainer clearly internalized the audit.** Recurring good
patterns: opt-in + fuzzel-confirmed destructive actions, LUKS-header backup + recovery key + preserved
passphrase keyslot, the FIDO2 *no-lockout* PAM design reused for fingerprint, **no `eval`/injection**
(`calc`→`qalc -t`, `websearch` URL-encodes, `find`→`plocate -- "$q"`), GPG-verified Flathub, encrypted
restic backups (`chmod 600` password, never in repo), `cp -an`+`700/600` for SSH/GPG restore, a
**pure-visual** SDDM greeter (no `Process`/`exec`/network), `plymouth`/`65-gaming` edits that back up +
**verify-or-restore**, and all 3 new modules properly wired into `converge`/`phase2`. **0 CRITICAL,
0 HIGH.** Danger sweep: clean.

| | Count |
|---|---|
| New findings | 6 (3 MEDIUM, 3 LOW) |
| Fixed in this branch | 5 (N-1,N-2,N-3,N-4,N-6) |
| Deferred | 1 (N-5, optional refactor) |

## Findings & fixes

### N-1 (MEDIUM) — `continuity` opened KDE Connect / LocalSend ports to *all* sources → **FIXED**
- **Was:** `archfrican-continuity` `allow()` wrote `… input tcp dport 1714-1764 accept` (and `udp`, and
  `53317`) with **no source scoping** — exposing LAN-only services (KDE Connect, LocalSend) to any
  reachable source, e.g. on public WiFi. Broke the deny-inbound posture.
- **Fix:** `allow()` now scopes to **private sources only** — `ip saddr { 10.0.0.0/8, 172.16.0.0/12,
  192.168.0.0/16 }` + `ip6 saddr { fe80::/10, fc00::/7 }` — for both stacks. Verified: the persisted
  rules carry the scope and are idempotent.

### N-2 (MEDIUM) — TPM2 enrolled with no PCR policy → **FIXED**
- **Was:** `archfrican-tpm-unlock` ran `systemd-cryptenroll --tpm2-device=auto` with **no `--tpm2-pcrs`**,
  so binding fell to systemd's default; without Secure Boot a physical-access attacker could coax the
  TPM to release the LUKS key (the at-rest threat LUKS exists for). *(No lockout/data-loss — passphrase
  keyslot 0 is preserved; this is auto-unlock strength.)*
- **Fix:** enroll now binds **`--tpm2-pcrs=7`**, and the script **warns if Secure Boot is not active**
  ("run `archfrican-secureboot` first"). The excellent header-backup + recovery-key + passphrase design
  is unchanged. **VM-validate before real use.**

### N-3 (MEDIUM) — `gaming/packages.txt` escaped the CI resolution gate → **FIXED**
- **Was:** CI `pkg-resolution` globbed only `packages/*.txt`, but `65-gaming` installs
  `gaming/packages.txt` (pacman pkgs, outside `packages/`) → a typo'd/dropped gaming package would fail
  only at install (the "ghostty-class" miss the gate exists to prevent).
- **Fix:** the gate now also resolves `gaming/packages.txt` (`flatpak/apps.txt` stays excluded — those
  are Flathub app-ids, not pacman). Verified the glob + that `gaming/packages.txt` (9 pkgs) is covered.

### N-4 (LOW) — `fingerprint` self-check weaker than FIDO2's → **FIXED**
- **Was:** after inserting `pam_fprintd.so`, it only checked that *an* `auth include` existed — not that
  `pam_fprintd` was correctly `sufficient`.
- **Fix:** the self-check now mirrors `lib/fido2.sh::fido2_pam_selfcheck` — asserts `pam_fprintd` is
  `sufficient` **and** an untouched password `include` remains, else restores the backup. *(Still wires
  only `/etc/pam.d/sudo`; extending to `system-local-login`/`sddm` like FIDO2 is a possible follow-up.)*

### N-6 (LOW) — `migrate` interpolated the chezmoi `$url` into `sh -c` → **FIXED**
- **Was:** `ghostty -e sh -c "chezmoi init --apply '$url'; …"` — a quote/metachar in the user-typed URL
  could break out of the inner `sh`. (Self-input, so low risk — but a real quoting bug.)
- **Fix:** `$url` is now passed as an **argument** (`sh -c '… "$1" …' _ "$url"`), never interpolated.
  *(Note: `chezmoi init --apply` from a URL inherently runs that repo's scripts — trust your own backup.)*

### N-5 (LOW) — `continuity` reimplements `fw_allow` (SSOT) → **DEFERRED**
- The clean fix is to add port-range support to `lib/security.sh::fw_allow` and have `continuity` call it.
  Deferred to avoid touching the core firewall lib in this pass; the N-1 fix removes the security risk.
  Tracked for a follow-up.

## Notable positives (no action)
`secureboot` (Setup-Mode check, `enroll-keys -m` anti-brick, `sbctl verify` before activation, documented
recovery) · `backup` (encrypted restic, 600 password, manual restore) · `rollback` (root-scoped → `@home`
preserved, num-validated + confirmed) · `plymouth` (backup + restore-on-`mkinitcpio`-fail) · `migrate`
SSH/GPG restore (`cp -an`, `700/600`) · Flathub GPG-verified · SDDM greeter visual-only · `vpn`/`cloud`
thin wrappers (no rolled crypto).

## Verification (read-only, run on the branch)
- `shellcheck -x -e SC1091` + `bash -n` clean on all changed scripts.
- N-1: ran the fixed `allow()` in isolation → emits the LAN-scoped v4+v6 rules, idempotent.
- N-3: confirmed the CI glob includes `gaming/packages.txt` (9 pkgs).
- **Boot-critical (N-2, plymouth, secureboot): NOT runnable here — VM-validate per `docs/STAGE2-VALIDATION.md`.**
