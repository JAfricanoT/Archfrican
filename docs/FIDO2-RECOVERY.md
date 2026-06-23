# FIDO2 hardware-key mode — how it works, and how to never get locked out

Archfrican's "physical-key mode" lets a **key touch replace your password** for `sudo` and login. It is
**non-exclusive by design**: the key is *added* as an option — your **password always still works**. You
cannot lock yourself out by losing the key.

## What gets changed when you enable it

- A mapping of your key(s) is written to **`/etc/u2f_mappings`** (`pamu2fcfg`, origin/appid pinned to
  `pam://archfrican`).
- One line is **inserted at the top** of `/etc/pam.d/sudo` and `/etc/pam.d/system-local-login`:
  ```
  auth sufficient pam_u2f.so cue nouserok origin=pam://archfrican appid=pam://archfrican authfile=/etc/u2f_mappings
  ```
  - `sufficient` → if the key check passes, you're in; **if it doesn't, PAM falls through to the password**
    line just below (which is left completely untouched).
  - `nouserok` → a user with *no* mapping is skipped, not blocked.
  - Each edited file is backed up once as `<file>.archfrican.bak`.
- The installer runs `fido2_pam_selfcheck` before finishing: it refuses to proceed unless the password
  include is still present and nothing else is `sufficient` above it. The key leg covers `sudo`,
  `system-local-login` and **`sddm`** (the graphical login's own PAM service), so a touch works at the
  SDDM greeter — the password is always still a fallback.

## The no-lockout guarantee (what we verified)

| Situation | Result |
|-----------|--------|
| Key present, you touch it | Authenticated, no password typed |
| Key present, you decline the touch | Falls through to the **password** prompt |
| Key lost / not plugged in | **Password** prompt as normal — no lockout |
| You only enrolled ONE key and lost it | **Password** still works; re-enroll a new key any time |
| LUKS (P1, opt-in) | Key unlocks the disk **and** the original passphrase still works (slot 0 is re-asserted) |

**Always enroll a BACKUP key** when prompted (keep it somewhere safe). Even without one, the password is
your fallback.

## Verify it yourself (after enabling)

```sh
pamtester sudo "$USER" authenticate     # touch the key  -> success
pamtester sudo "$USER" authenticate     # decline touch  -> falls back to password
```

## Rotate / add / revoke a key

- **Add another key:** re-run the wizard's enroll step (recommended). By hand: generate a credential with
  `pamu2fcfg -n -o pam://archfrican -i pam://archfrican` and paste its `:cred…` output onto the END of your
  existing `username:…` line in `/etc/u2f_mappings` — on the **same line** (a bare `:cred` on its own line
  is silently ignored).
- **Revoke a key / disable the mode entirely:** restore the backups and remove the mapping:
  ```sh
  sudo mv /etc/pam.d/sudo.archfrican.bak /etc/pam.d/sudo
  sudo mv /etc/pam.d/system-local-login.archfrican.bak /etc/pam.d/system-local-login
  sudo rm -f /etc/u2f_mappings
  ```
  Your password-based login/sudo is now exactly as it was before.

## If you ever can't authenticate

You can't be locked out by FIDO2 (password always works), but if a misconfiguration ever bites:
1. Reboot, choose **linux-lts** or a **Snapper snapshot** in GRUB.
2. Get a root shell, restore the `.archfrican.bak` PAM files (above).
3. `root` login is disabled here, so recover via the snapshot/LTS path — see also the faillock recovery
   note in `lib/security.sh::faillock_recover_doc`.

## Deferred to a later release (documented, not shipped on by default)
- **greetd (graphical login) key leg** — code is present but OFF until tuigreet's touch-cue timing is
  validated on real hardware.
- **LUKS unlock by key on the ISO armed path** — the booted-base LUKS fallback ships in P1; enrolling on
  the destructive ISO path waits until the archinstall schema is VM-captured and the `sd-encrypt` hook is
  the default (`docs/STAGE2-VALIDATION.md`).
