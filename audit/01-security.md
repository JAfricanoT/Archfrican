# Phase 1 — Security & Supply Chain

**Project:** Archfrican — Arch Linux installer + chezmoi dotfiles manager + convergent updater (pure Bash, ~3,036 LOC, 97 tracked files).
**Method:** 6 parallel finder lenses (privilege, secrets, supply-chain, injection, disk-ops, firewall/permissions), each candidate passed through an independent *adversarial verifier* that tried to refute it by re-reading the code. Reproducible claims were re-run locally (read-only). Agent output was treated as candidate evidence and cross-checked by hand against the source.
**Threat model:** this is a **local system installer** that runs as the operating user / root on the target machine. There is no remote HTTP attacker. The real threats are: privilege mistakes, supply-chain trust, destructive disk/data loss, secret leakage to disk/logs, and shell-injection from values that flow into commands.

## Verdict for this phase

**The security posture is genuinely strong — no CRITICAL or HIGH findings survived verification.** Secrets are handled correctly (file-descriptor passing, never argv/env/disk, zeroed after use), the destructive disk path is triple-gated, the firewall never flushes foreign tables, FIDO2 is provably non-exclusive, and the codebase is shellcheck-clean. The prior audit's single CRITICAL (package-list parser) and its fragile-grub-sed HIGH are **fixed**. What remains are **4 MEDIUM** robustness/hardening gaps (two of them sharp), **3 LOW**, and **6 INFO** notes.

### Candidate accounting (rigor signal)

| | Count |
|---|---|
| Candidates raised by finders | 16 |
| Survived adversarial verification (`isReal=true`) | 15 |
| Refuted / discarded | 1 |
| Distinct findings after de-duplication | 14 |
| — of which MEDIUM | 4 |
| — of which LOW | 3 |
| — of which INFO | 6 |
| — *(the LOCALE-in-sed issue was independently found by 3 lens instances → consolidated to 1)* | |

## Reproduction baseline (run locally, read-only)

```
$ shellcheck --version            → 0.11.0
$ shellcheck -x -e SC1091 <all .sh + bin/>   → exit 0   (clean, as CI runs it)
$ shellcheck -x         <all .sh + bin/>      → 0 findings (histogram empty)
$ bash -n               <all .sh + bin/>      → all OK (no syntax errors)
$ git ls-files | grep -i user_credentials     → (none — untracked)
$ git check-ignore -v archinstall/user_credentials.json tests/e2e/answers.env
    .gitignore:1: archinstall/user_credentials.json    (IGNORED)
    .gitignore:2: tests/e2e/answers.env                (IGNORED)
$ git log --all --diff-filter=A … (secret-ish filenames)  → none in history
$ git grep -n 'eval '                          → no eval anywhere
$ git grep curl|bash patterns                  → only a doc comment (install.sh:4) + a comment (ui.sh:8)
```

**Secrets: not a leak.** No credential file is tracked, both sensitive paths are gitignored, and nothing secret appears in git history. Per audit rule #3 this is "local file, properly ignored," not "secret in the repo."

---

## MEDIUM findings

### M1 — First-boot NOPASSWD-ALL sudoers drop-in is removed only on a *successful* resume; a permanently-failing install leaves passwordless root in place

- **File:** `lib/phase1.sh:40-43` (write) · `templates/archfrican-resume.service:26-29` (removal) · `lib/migrate.sh` / `lib/health.sh` (no detection)
- **Severity:** MEDIUM · **Confidence:** high
- **Evidence:**
  ```bash
  # lib/phase1.sh:40
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > /mnt/etc/sudoers.d/99-archfrican-resume
  chmod 0440 /mnt/etc/sudoers.d/99-archfrican-resume
  arch-chroot /mnt visudo -cf /etc/sudoers.d/99-archfrican-resume >/dev/null || die "…"
  ```
  ```ini
  # templates/archfrican-resume.service:19-29
  Type=oneshot
  RemainAfterExit=yes
  ExecStart=/usr/bin/bash /home/@USER@/.archfrican/install.sh
  ExecStartPost=/usr/bin/sudo /usr/bin/systemctl disable archfrican-resume.service
  ExecStartPost=/usr/bin/sudo /usr/bin/rm -f /etc/sudoers.d/99-archfrican-resume
  ```
  The service's own header (`archfrican-resume.service:8-11`) documents the behaviour: *"On failure it stays enabled and retries next boot …, keeping the drop-in until it finally succeeds."*
- **Impact:** systemd runs `ExecStartPost` **only when `ExecStart` succeeds**. If the Stage-2 install never completes (an unresolvable package, no network on first boot, a keyring/AUR failure), the unit stays enabled (`RemainAfterExit=yes`), retries every boot, and the `NOPASSWD: ALL` grant for the primary wheel user **persists indefinitely**. The intended "exactly one boot" elevated window becomes open-ended. There is no health check and no migration that detects or clears a stuck `99-archfrican-resume` (migration `0001` only handles the older `00-` name; `lib/health.sh` has no sudoers check). *Blast radius (verifier's tempering):* the grant is to a user who already holds full `wheel` sudo, so the practical delta is "passwordless vs. password-prompted root for a principal who already has root," not a new-privilege escalation — but it does remove the password barrier on the failure path (a malicious user-session script or a payload pulled in by the still-running install gets root with no prompt), and it self-heals only once the resume eventually succeeds.
- **Recommendation:** (a) add `ExecStopPost=-/usr/bin/sudo /usr/bin/rm -f /etc/sudoers.d/99-archfrican-resume` so the file is removed when the unit stops/fails, not only on success; (b) scope the grant to the commands the resume actually needs (pacman/systemctl/install) instead of `ALL`; (c) have `lib/health.sh` / `archfrican-doctor` flag a lingering `99-archfrican-resume` on a fully-booted system as RED; (d) bound retries.

### M2 — CachyOS repo-bootstrap tarball is extracted and its script run as **root** with no checksum/signature; key-pin protects later packages, not this script

- **File:** `modules/00-base.sh:9-35`
- **Severity:** MEDIUM · **Confidence:** high
- **Evidence:**
  ```bash
  curl -fL --proto '=https' --tlsv1.2 https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  …
  tar xf repo.tar.xz; cd cachyos-repo || die "CachyOS tarball missing the cachyos-repo/ dir"
  …
  ( set +o pipefail; yes 2>/dev/null | sudo ./cachyos-repo.sh )
  ```
- **Impact:** the `.tar.xz` is fetched over TLS but verified by **no checksum and no signature**, then its enclosed `cachyos-repo.sh` runs as root. The pinned-key trust (`00-base.sh:18-22`) gates the *signed packages* the repo installs afterward — it does **not** gate this bootstrap script, which runs first, as root, with whatever bytes `mirror.cachyos.org` (or a TLS-terminating proxy / compromised CDN origin) serves. A substituted tarball ⇒ arbitrary root code execution before any pacman signature check applies. This is honestly documented in-file as a deliberate trade-off (CachyOS publishes no detached signature), so it is a **known, mitigated** residual surface, not a latent bug. (`grep -rn sha256sum` confirms the only checksum use in the repo is `lib/converge.sh` module-hashing — there is no tarball verification the finder missed.)
- **Recommendation:** pin the tarball by content hash — record an expected `sha256` and `sha256sum -c` before `tar xf`, refusing on mismatch unless `ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1` (the same escape hatch already used for the key import). Update the known-good hash in-repo whenever CachyOS rotates the bootstrap.

### M3 — Operator-supplied `LOCALE` flows unescaped into `sed`/`grep` regex; a `/` or regex metacharacter mis-edits `/etc/locale.gen` or aborts the install (two code paths)

*Found independently by the privilege, injection, and a second injection lens → high-confidence convergence.*

- **Files:** `lib/base-install.sh:121-122` (ISO chroot path) · `lib/host-config.sh:49` (booted/resume path)
- **Severity:** MEDIUM · **Confidence:** high
- **Evidence:**
  ```bash
  # lib/base-install.sh:121
  if grep -qE "^#\s*${LOCALE} " /etc/locale.gen; then sed -i "s/^#\s*\(${LOCALE} .*\)/\1/" /etc/locale.gen
  # lib/host-config.sh:49
  sudo sed -i "s/^#\\s*\\(${loc}\\b.*\\)/\\1/" /etc/locale.gen
  ```
- **Impact:** `LOCALE` is unvalidated free text — `ui_input 'Locale (LANG)'` (`phase1.sh:126`, `phase2.sh:87`), `AF_AP_LOCALE`, or `ARCHFRICAN_LOCALE`; there is **no validation anywhere in `lib/`** between intake and use. It is interpolated into an ERE (`grep -qE`) and into the **LHS of a `sed s///`** that uses `/` as the delimiter. The verifier reproduced both failure modes: (1) a `LOCALE` containing a literal `/` breaks the `s/…/…/` delimiter, sed exits non-zero, and because the chroot script runs under `set -euo pipefail` (`base-install.sh:115`) **the install aborts after partitioning/pacstrap**; the booted path has no error guard either, so a bad value **aborts the first-boot resume**. (2) regex metacharacters (`.`, `*`) make the grep guard and the sed over/under-match, so the *wrong* `locale.gen` line gets uncommented. Not attacker-controlled (the operator types their own LANG, with a working default pre-filled), so this is a real robustness/correctness bug, fail-loud, not data-loss or privesc — hence MEDIUM, not higher.
- **Recommendation:** validate once at intake (`[[ $LOCALE =~ ^[A-Za-z0-9._@-]+$ ]] || die`, or check against `localectl list-locales`) so both consumers are covered; or drop `sed` for the fixed-string + bash-rewrite approach that `lib/grub.sh::append_grub_cmdline` already uses deliberately to avoid token-in-regex.

### M4 — `fw-allow` validates that a port is numeric but not in range; an out-of-range port is persisted and wedges the entire firewall load (fail-open)

- **File:** `lib/security.sh:13-21` (with `modules/60-security.sh:18-42`)
- **Severity:** MEDIUM · **Confidence:** high
- **Evidence:**
  ```bash
  # lib/security.sh:13
  case "$port" in ''|*[!0-9]*) echo "fw-allow: port must be numeric" >&2; return 2;; esac
  …
  printf '%s\n' "$rule" | sudo tee -a "$ARCHFRICAN_FW_ALLOWS" >/dev/null
  sudo nft "${rule_args[@]}" 2>/dev/null || true   # live add … (failure swallowed)
  ```
- **Impact:** `70000`, `99999`, even `0` pass the digits-only check. The rule is appended to `/etc/nftables.d/archfrican-allows.nft` **before** the live `nft add`, and the live add's failure is silenced by `2>/dev/null || true` (line 22 then prints "allowed…" regardless). `/etc/nftables.conf` is a single `nft -f` script ending in `include "/etc/nftables.d/archfrican-allows.nft"` (`60-security.sh:41`); `nft -f` is **transactional**, so on the next reload/reboot the bad line aborts the **whole** ruleset load — the `policy drop` input chain never installs and the box silently comes up **with no firewall (fail-open)** until someone hand-edits the file. The breakage is invisible at `fw-allow` time and only surfaces at next boot.
- **Recommendation:** add a range check (`[ "$port" -ge 1 ] && [ "$port" -le 65535 ]`); reorder to **validate → live-add → persist only on success**; and surface a real error instead of `|| true` so an invalid rule never reaches the on-disk include that gates every future firewall load.

---

## LOW findings

### L1 — Cosmetic AUR packages built/installed unattended (`paru -S --noconfirm`), unreviewed and unpinned
- **File:** `lib/common.sh:95` · `packages/aur.txt`
- **Evidence:** `paru -S --needed --noconfirm "$p" || { warn "AUR build failed (continuing): $p"; … }`
- **Impact:** every `aur.txt` entry (whitesur-gtk-theme, whitesur-icon-theme, mcmojave-cursors, otf-san-francisco{,-mono}, nwg-dock) is built from whatever revision the AUR currently serves, running each upstream PKGBUILD unreviewed. This is the inherent AUR trust model on a **purely cosmetic** layer (a failed/compromised build warns and continues; `preflight_pkgs` deliberately skips `aur.txt`). Documented here so the trust boundary is explicit: these are **not** signature-verified the way pacman/CachyOS packages are.
- **Recommendation:** acceptable as-is; for tighter assurance, vendor pinned PKGBUILDs in-repo, or document in the README that `aur.txt` entries are unsigned third-party builds.

### L2 — Disk picker does not exclude (or flag) the live/boot medium
- **File:** `lib/disk.sh:19-24`
- **Impact:** `list_disks` enumerates every `type=disk` device with no filter; on a real machine the Arch ISO USB is itself `type=disk` (e.g. `/dev/sda`), so the operator can select and wipe the very USB they booted from. Gated only by the human `confirm_wipe` retype (`disk.sh:43-62`) — operator-error data loss, not exploitable. The codebase already detects the ISO (`env.sh:7`) and uses `findmnt -no SOURCE /` elsewhere (`health.sh:59`), so a fix is feasible with existing primitives.
- **Recommendation:** drop the live-medium device from `list_disks`, or annotate any candidate with mounted child partitions (`lsblk -o NAME,MOUNTPOINTS`) so the label flags it as in-use before confirmation.

### L3 — No busy/mounted-device guard before `wipefs --all` / `sgdisk --zap-all`
- **File:** `lib/base-install.sh:51-66`
- **Impact:** `base_stale_guard` only releases the installer's *own* prior state (`/mnt`, swap, the `root` mapper). It does not verify the chosen `$disk` is otherwise idle (partitions mounted elsewhere, an open LUKS/LVM/RAID member). If the target is in use, signatures get destroyed and `partprobe` may fail mid-operation, corrupting an in-use disk. Double-gated by `ARMED`+`GO`+`confirm_wipe`, so it is a hardening gap, not an unattended wipe; `wipefs`+`sgdisk --zap-all` is also the standard Arch-install approach.
- **Recommendation:** before `base_partition`, `die` with a clear message if `lsblk -nro MOUNTPOINTS "$disk"` shows an active mountpoint or the disk holds an open LUKS/LVM/RAID member, unless an explicit override is passed.

---

## INFO notes

| # | Note | File |
|---|------|------|
| I1 | `$user` substituted into `sed s/@USER@/…/`; only safe today because `useradd` (run earlier under errexit) rejects names with `/` or `&` first — implicit, ordering-dependent. Defense-in-depth: validate `USER_NAME` at intake or use fixed-string templating. | `lib/phase1.sh:59` |
| I2 | `curl\|bash` bootstrap + self-clone default to the moving `main` branch (`ARCHFRICAN_REF:-main`), no signed-tag/commit verification. Standard first-party trust model; overridable to a tag. | `install.sh:17,42` |
| I3 | `ARCHFRICAN_ALLOW_UNVERIFIED_CACHYOS=1` lets the install proceed with the CachyOS key un-pinned (packages then unverifiable). Off by default (else-branch `die`s), explicit loud opt-in. | `modules/00-base.sh:23-24` |
| I4 | AUR `paru-bin` fallback clones HEAD (no commit pin) and builds unattended. Off by default — gated behind `ARCHFRICAN_ALLOW_AUR_PARU=1`; the default path `die`s and prefers the signed binary. | `modules/00-base.sh:67-69` |
| I5 | In-process secret zeroing (`pass=""`/`hash=""`) is skipped on the error path, but `on_err` calls `exit` which frees the whole address space — a *stronger* clear than the skipped line; secrets never touch disk/argv/env. Hygiene note only. | `lib/base-install.sh:73-75,175-176` |
| I6 | Autopilot test path puts the plaintext password + LUKS passphrase in the installer's environment (readable via `/proc/<pid>/environ`). Strictly the throwaway-VM test path (`ARCHFRICAN_AUTOPILOT=1`); production wizard never exports them; secrets still reach the installer on fd 3/4. | `lib/phase1.sh:97-99` |

---

## Refuted / Discarded (transparency)

### R1 — "FIDO2 `sufficient` line sits above the faillock include, exempting the key path from rate-limiting" — **NOT A REAL FINDING**
- **Claimed:** `lib/fido2.sh:56-60` inserts the u2f `sufficient` line above `auth include system-auth`, so a key touch short-circuits before `pam_faillock`, exempting it from `deny=5`.
- **Why refuted:** the PAM mechanism is real but there is no security regression. `pam_faillock` counts only **failed** authentications — a *successful* key touch (or password) was never going to be counted. A *failed* key touch returns failure from the `sufficient` line and PAM falls **through** to the password include where faillock's preauth/authfail still run, so the brute-forceable secret (the password) stays fully gated. A hardware key requires physical possession and is not a brute-force target faillock exists to counter. The "silently undocumented" premise is also false: the non-exclusive / no-lockout design is documented (`fido2.sh:1-4` header, `SECURITY.md:31`, `docs/FIDO2-RECOVERY.md`) and enforced by `fido2_pam_selfcheck` (`fido2.sh:78-87`). At most an INFO doc-nuance; not a bug.

---

## Prior-audit reconciliation (security items — full matrix in Phase 5)

| Prior finding | Status now | Evidence |
|---|---|---|
| **CRITICAL** — package-list parser keeps inline comments → every pacman batch malformed | **FIXED** | `lib/common.sh:113` `__rpl_pkg="${__rpl_line%%#*}"` strips inline + whole-line comments; CI `pkg-resolution` gate added |
| **HIGH** — fragile raw `sed` editing `/etc/default/grub` in `10-gpu` | **FIXED** | centralized in `lib/grub.sh` with parse + fixed-string membership + verify-or-die |
| **HIGH** — CachyOS bootstrap unverified root code execution | **PARTIALLY FIXED** | key now pinned-by-fingerprint + lsigned (`00-base.sh:17-22`) so *packages* are verified; the bootstrap *script* itself is still unverified → see **M2** |
| **HIGH** — unpinned `paru-bin` from AUR built by default | **FIXED** | now `die`s by default; AUR build gated behind `ARCHFRICAN_ALLOW_AUR_PARU=1` (`00-base.sh:59-69`) → residual is **I4** |

---

*Next: Phase 2 — State Integrity & Destructive Ops (convergence idempotency, migrations, manifest/prune, chezmoi, append-safety).*
