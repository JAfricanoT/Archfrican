# Phase 1 — Security & Supply Chain

**Project:** Archfrican — a personal Arch Linux installer (Bash) + chezmoi-managed dotfiles.
**Scope of this phase:** supply-chain / remote-code trust, privilege escalation & system-file
writes, injection / unsafe expansion, and secrets. Web-app lenses (AuthN/AuthZ, IDOR/BOLA,
RLS/multi-tenant, XSS/CORS/CSRF, rate limiting, uploads) **do not apply** — there is no server,
no web surface, and no database.

**Method:** 4 parallel finders (one per lens) → 1 adversarial verifier per candidate that tried to
**refute** it by reading the code. **31 candidates → 27 survived, 4 refuted** (see *Refuted /
Discarded*). Findings below are deduplicated across lenses (one issue = one entry with cross-lens
notes). Every entry cites `file:line` (paths relative to `archfrican/`) and quotes the actual code.

> **Important baseline correction (reshapes several findings).** My Phase-0 recon noted that
> `set -euo pipefail` is literally absent from the 6 modules and that `install.sh` runs them via
> `bash modules/X.sh` (not sourced), and inferred "modules silently continue on error." The
> adversarial verifiers **refuted that inference and proved it wrong empirically.** Every module's
> *first executable line* is `source "$(dirname "$0")/../lib/common.sh"` ([common.sh:4](../../lib/common.sh#L4)
> is `set -euo pipefail`), and `set` options set in a sourced file **persist in the calling shell**.
> So the modules **do** run under errexit/nounset/pipefail. This is honest and material: it means
> failures generally **abort loudly** rather than silently continue — which is good for safety, and
> it is precisely why the CRITICAL parser bug below *halts* the install instead of half-completing.

---

## Severity summary (this phase, deduplicated)

| Severity | Count | Items |
|----------|-------|-------|
| CRÍTICO  | 1 | SEC-01 |
| ALTO     | 1 | SEC-02 |
| MEDIO    | 8 | SEC-03 … SEC-10 |
| BAJO     | 6 | SEC-11 … SEC-16 |
| INFO     | 5 | SEC-17 … SEC-21 (incl. 2 positive) |

Candidates refuted by adversarial verification: **4** (listed at the end).

---

## CRÍTICO

### SEC-01 — Package-list parser does not strip inline comments → the phase-2 install cannot complete
- **File:** [lib/common.sh:34-35](../../lib/common.sh#L34-L35) · lenses: injection · confidence: alta
- **Evidence:**
  ```bash
  pac_install_file() { mapfile -t _p < <(grep -vE '^\s*(#|$)' "$1"); pac_install "${_p[@]}"; }
  aur_install_file() { mapfile -t _p < <(grep -vE '^\s*(#|$)' "$1"); aur_install "${_p[@]}"; }
  ```
- **Impact:** The `grep -vE '^\s*(#|$)'` filter drops only **whole-line** comments and blank lines;
  it does **not** strip **trailing inline comments**. Every package list ships inline comments —
  e.g. [niri-desktop.txt:4](../../packages/niri-desktop.txt#L4) `keyd                   # ⌘-style shortcut remaps for ex-mac users`,
  [base.txt:11-12](../../packages/base.txt#L11-L12) (`inotify-tools …`, `reflector …`). Because
  `mapfile -t` reads each line as **one array element**, that element keeps the comment, and the
  quoted expansion `"${_p[@]}"` passes the whole string as a single argument. So pacman receives a
  literal target `inotify-tools          # needed by grub-btrfs daemon` (verified empirically by the
  finder under bash). pacman/paru fail the **entire batch** on an unknown target, and since errexit
  is active (see baseline note), the first failing `pac_install_file` — `base.txt` in module
  `00-base` — **aborts the whole phase-2 installer on every run.** The very first package install
  breaks.
- **Honest caveat:** This only bricks **phase 2**. The base OS produced by the `archinstall` phase
  remains bootable, and `theme-switch` (which never installs packages) works — consistent with
  `CONTEXT.md`'s honest "v0 … not for running blindly on hardware yet."
- **Recommendation:** Strip inline comments + surrounding whitespace before building the array, e.g.
  `grep -vE '^\s*(#|$)' "$1" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//'`, or
  `awk '{sub(/#.*/,""); gsub(/^ +| +$/,""); if($0!="") print}'`. Add a test asserting no array
  element contains whitespace.
- **Cross-phase:** Also a reliability defect (Phase 3) and the strongest evidence that the package
  path was never executed on hardware (Phase 4: no tests/CI).

---

## ALTO

### SEC-02 — CachyOS repo bootstrap: unverified tarball fetched and executed as root (no checksum/signature/pin)
- **File:** [modules/00-base.sh:8-11](../../modules/00-base.sh#L8-L11) · lenses: supply-chain + priv-esc + trust-keys (3 lenses converged) · confidence: alta
- **Evidence:**
  ```bash
  curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz
  tar xf repo.tar.xz && cd cachyos-repo
  sudo ./cachyos-repo.sh        # auto-detects x86-64-v3/v4 and wires the repo
  ```
- **Impact:** A tarball is downloaded and its `cachyos-repo.sh` executed with **full root** (`sudo`)
  with **no SHA256, no GPG signature on the tarball, and no version pin** (it fetches the rolling
  `cachyos-repo.tar.xz`). That script is the single **root of trust** for the rest of the system: it
  adds the `[cachyos]` repos to `/etc/pacman.conf` **and imports the CachyOS signing key**, after
  which every `pacman -S --noconfirm` ([common.sh:21](../../lib/common.sh#L21)) installs CachyOS
  packages (including the `linux-cachyos` kernel). A compromised/spoofed `mirror.cachyos.org`, a DNS
  hijack, or a TLS-terminating edge proxy yields arbitrary root code execution and persistent
  attacker control.
- **Calibration (verifier):** The URL **is HTTPS**, so passive on-path MITM is mitigated by TLS —
  the realistic vector is infrastructure compromise, not passive interception. This is also the
  **upstream-documented official CachyOS install method**, so the gap is *defense-in-depth*, not an
  invented flaw; one verifier argued MEDIO on that basis. Kept at **ALTO** because it is root-level
  RCE with zero local verification around an unpinned rolling artifact.
- **Recommendation:** Pin and verify a known-good SHA256 (downloaded out-of-band) before `tar xf`,
  and/or verify CachyOS's detached signature with a pre-pinned key. After running, assert the
  imported key fingerprint matches the published CachyOS fingerprint (`pacman-key --finger <FPR>`)
  and abort on mismatch. Document in the README that this step runs upstream code as root.

---

## MEDIO

### SEC-03 — AUR supply chain: `paru-bin` bootstrap and all AUR installs are unreviewed, unpinned, `--noconfirm`
- **Files:** [modules/00-base.sh:28-29](../../modules/00-base.sh#L28-L29), [lib/common.sh:30](../../lib/common.sh#L30) · lenses: supply-chain + trust-keys · confidence: alta
- **Evidence:**
  ```bash
  tmp="$(mktemp -d)"; git clone https://aur.archlinux.org/paru-bin.git "$tmp"
  ( cd "$tmp" && makepkg -si --noconfirm ); rm -rf "$tmp"
  # …and later, the generic AUR path:
  paru -S --needed --noconfirm "${missing[@]}"
  ```
- **Impact:** `paru-bin` is cloned at **HEAD (no commit pin)** and built/installed via
  `makepkg -si --noconfirm` with **no PKGBUILD review**. AUR PKGBUILDs are arbitrary maintainer
  shell: `package()` runs as the user and `-i` installs as root via `pacman -U`. paru then becomes
  the trusted tool for **all** further AUR installs (`aur.txt`: WhiteSur theme/icons, McMojave
  cursors, SF Pro/Mono fonts, nwg-dock — several download third-party binaries at build time), all
  with `--noconfirm` and no pinning. A hijacked AUR account or malicious PKGBUILD edit runs with
  **no human checkpoint.**
- **Verifier correction:** Drop the original "auto-imports build keys" claim — `makepkg --noconfirm`
  does **not** silently import unknown `validpgpkeys`; it **fails** on a missing key. The real surface
  is the unreviewed/unpinned build, not key auto-import.
- **Recommendation:** Install `paru` from the **CachyOS repo** (already enabled in this same module)
  to drop the unreviewed build entirely; otherwise pin `paru-bin` to a known commit. For app AUR
  packages, vendor the small set of PKGBUILDs into the repo (version-controlled, auditable) or print
  PKGBUILDs on first install.

### SEC-04 — Bootstrap entry point is `curl|bash` and auto-`pull`s unpinned updates before running privileged steps
- **File:** [bootstrap.sh:3-7](../../bootstrap.sh#L3-L7) · lenses: supply-chain + trust-keys · confidence: alta
- **Evidence:**
  ```bash
  #   bash <(curl -fsSL https://raw.githubusercontent.com/YOU/archfrican/main/bootstrap.sh)
  sudo pacman -S --needed --noconfirm git
  git clone https://github.com/YOU/archfrican.git "$HOME/.archfrican" 2>/dev/null || git -C "$HOME/.archfrican" pull
  exec "$HOME/.archfrican/install.sh"
  ```
- **Impact:** The documented path pipes a remote script into bash (TLS is correctly enforced via
  `-fsSL`, good) with **no out-of-band checksum/GPG**, then clones the repo with **no tag/commit pin
  or signature** and `exec`s `install.sh` (which runs all six privileged modules). On every re-run
  the `|| git … pull` branch **fast-forwards `main` and re-executes** whatever upstream now contains —
  a later upstream compromise is fetched and run with `sudo` automatically. `2>/dev/null` also hides
  clone errors.
- **Recommendation:** Pin to a signed tag/commit (`git clone --branch vX.Y --depth 1`, verify the
  signed tag) and make updates an explicit, reviewable action rather than an automatic `pull` before
  `exec`. Publish a checksum/signature for `bootstrap.sh`. Replace the `YOU/archfrican` placeholder before
  publishing.

### SEC-05 — `greetd` (and `keyd`) system configs are unconditionally clobbered with no idempotency guard or backup
- **File:** [modules/20-niri-desktop.sh:10-16](../../modules/20-niri-desktop.sh#L10-L16) (and the `keyd` block at line 26) · lenses: priv-esc · confidence: alta
- **Evidence:**
  ```bash
  sudo tee /etc/greetd/config.toml >/dev/null <<TOML
  [terminal]
  vt = 1
  [default_session]
  command = "tuigreet --remember --asterisks --time --cmd niri-session"
  user = "greeter"
  TOML
  ```
- **Impact:** Unlike the package/grub/mkinitcpio edits (guarded by `grep`/`pacman -Q`), this writes
  `/etc/greetd/config.toml` **every run**, overwriting any user customization with no backup. The
  `keyd` block immediately below ([:26](../../modules/20-niri-desktop.sh#L26)) has the **same**
  unguarded-clobber defect. Re-running `./install.sh 20-niri-desktop` silently destroys hand-tuned
  login/keymap config.
- **Recommendation:** Back up before writing (`cp … .archfrican.bak`) or write only when absent/differs,
  mirroring the idempotent pattern used elsewhere; add `sudo install -d /etc/greetd` for symmetry
  with the keyd block. *(Primarily a Phase-2 data-integrity issue; reported here as found.)*

### SEC-06 — `theme-switch` interpolates palette values into a `sed s|…|…|` replacement without escaping
- **File:** [bin/theme-switch:19](../../bin/theme-switch#L19) · lenses: injection · confidence: alta
- **Evidence:** `for v in "${VARS[@]}"; do args+=(-e "s|\${$v}|${!v}|g"); done`
- **Impact:** Each palette value `${!v}` is spliced into the replacement side with **no escaping** of
  the `|` delimiter, `&` (whole-match backreference), or `\`. All current palettes use literal hex
  (`#1c1c1e`), so there is **no present-day exploit**; this is **latent correctness fragility**: a
  future palette value containing `|`, `&`, `\`, or a newline would silently corrupt the generated
  ghostty/waybar/fuzzel/mako/niri config.
- **Verifier correction:** Not a security "injection" — `colors.sh` is author-written bash that is
  `source`d (already arbitrary code by the trust root); frame as robustness, severity MEDIO.
- **Recommendation:** Render via pure-bash parameter expansion (`${template//.../}`) instead of sed,
  or escape `\`, the delimiter, and `&`; constrain palette values to `^#[0-9a-fA-F]{6,8}$` at load.

### SEC-07 — `theme-switch` niri splice destroys the rest of the config if the `THEME-END` marker is missing
- **File:** [bin/theme-switch:35-39](../../bin/theme-switch#L35-L39) · lenses: injection · confidence: alta
- **Evidence:**
  ```bash
  awk 'NR==FNR{blk=blk $0 ORS; next}
       /THEME-START/{printf "%s", blk; skip=1; next}
       /THEME-END/{skip=0; next}
       !skip{print}' "$tmpblk" "$CFG/niri/config.kdl" > "$CFG/niri/config.kdl.new"
  mv "$CFG/niri/config.kdl.new" "$CFG/niri/config.kdl"
  ```
- **Impact:** If `config.kdl` has a `THEME-START` but the matching `THEME-END` is missing/removed,
  `skip` stays `1` and **every line after THEME-START is dropped**, then `mv` overwrites the original —
  permanent loss of the rest of the niri config. Markers are also **unanchored substring** matches:
  any line merely containing `THEME-START`/`THEME-END` (comment, string) triggers splice/skip. The
  shipped config ([config.kdl:27-33](../../home/dot_config/niri/config.kdl#L27-L33)) has both
  markers, so the happy path is fine, but there is no validation before overwriting.
- **Recommendation:** Assert exactly one well-formed `START…END` pair (START before END) and bail
  out keeping the original otherwise; anchor markers; back up before `mv`. *(Also Phase 2/3.)*

### SEC-08 — `usermod -aG docker` grants root-equivalent access; the comment claims "rootless"
- **File:** [modules/30-dev.sh:13-15](../../modules/30-dev.sh#L13-L15) · lenses: priv-esc · confidence: alta
- **Evidence:**
  ```bash
  enable_service docker.service
  sudo usermod -aG docker "$USER" || true
  warn "Log out/in for docker group to take effect."
  ```
- **Impact:** docker-group membership is **passwordless root**: any member can
  `docker run -v /:/host …` and read/modify the whole host as root. Enabling `docker.service` + the
  group is the **rootful** daemon — the opposite of the line-12 "rootless-friendly" comment. The
  `|| true` also masks a `usermod` failure.
- **Recommendation:** If rootless is the goal, use rootless Docker or `podman`; otherwise document
  that docker-group = root-equivalent so the choice is informed. Drop the `|| true`.

### SEC-09 — NVIDIA GRUB cmdline `sed` silently no-ops on non-standard `/etc/default/grub`, but still reports success
- **File:** [modules/10-gpu.sh:24-27](../../modules/10-gpu.sh#L24-L27) · lenses: priv-esc · confidence: alta
- **Evidence:**
  ```bash
  if ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
    sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
  ```
- **Impact:** The `sed` matches only a **double-quoted** single-line `GRUB_CMDLINE_LINUX_DEFAULT="…"`.
  If the entry is single-quoted, commented, absent, or the system isn't GRUB, **no edit is made** yet
  the module proceeds and [line 33](../../modules/10-gpu.sh#L33) still `warn`s that NVIDIA is
  configured. Early KMS is then silently not applied (black-screen risk on first niri launch).
- **Verifier correction:** The original "module lacks `set -e`" sub-claim is **false** (errexit is
  inherited via the sourced common.sh). The valid core is the **silent `sed` no-op + false success
  report**; the stale-`grub.cfg`-on-re-run concern stands.
- **Recommendation:** Verify the post-edit file actually contains the param on the
  `GRUB_CMDLINE_LINUX_DEFAULT` line and fail loudly otherwise.

### SEC-10 — mkinitcpio `MODULES` edit gated by an over-broad substring grep
- **File:** [modules/10-gpu.sh:28-31](../../modules/10-gpu.sh#L28-L31) · lenses: priv-esc · confidence: alta
- **Evidence:**
  ```bash
  if ! grep -q 'nvidia' /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P
  fi
  ```
- **Impact:** The guard greps `nvidia` **anywhere** in the file (incl. comments). If a prior
  edit/tool added an `nvidia` comment, the guard short-circuits and the `MODULES` line is never
  patched → early KMS silently unconfigured while line 33 claims success. The `sed` also assumes a
  **single-line** `MODULES=(…)` and silently no-ops on multi-line array syntax.
- **Verifier correction:** Stock Arch `mkinitcpio.conf` does **not** ship the literal substring
  `nvidia` and uses single-line `MODULES`, so the clean-install path actually works; the false-skip
  is the narrower (still real) edge. No post-edit verification before the success message.
- **Recommendation:** Anchor the guard (`grep -qE '^MODULES=\(.*\bnvidia\b'`) and verify the `sed`
  changed the file before reporting success.

---

## BAJO

### SEC-11 — `pacman --noconfirm` auto-accepts key-trust prompts; no `archlinux-keyring`/`pacman-key --populate` refresh before bulk installs
- **File:** [lib/common.sh:21](../../lib/common.sh#L21) · lenses: trust-keys · confidence: alta
- **Evidence:** `sudo pacman -S --needed --noconfirm "${missing[@]}"`
- **Impact:** `--noconfirm` removes the interactive checkpoint where a new signing key would be
  noticed. **Verifier correction:** `--noconfirm` only auto-accepts keys that already have a trust
  path; it is **not** a blanket "import any key" switch (that risk lives in SEC-02), and `reflector`
  is never actually invoked here. `--noconfirm` is also standard/required for an unattended installer.
  The real residual: no `archlinux-keyring` update / `pacman-key --populate` runs before bulk installs.
- **Recommendation:** Refresh `archlinux-keyring` and run `pacman-key --populate` before bulk
  installs; document that `--noconfirm` trusts new keys without prompting.

### SEC-12 — `zinit` cloned unpinned from GitHub and `source`d on every shell startup (persistent TOFU)
- **File:** [home/dot_zshrc:6-9](../../home/dot_zshrc#L6-L9) · lenses: supply-chain · confidence: alta
- **Evidence:**
  ```zsh
  [ -d "$ZINIT_HOME" ] || { mkdir -p "$(dirname "$ZINIT_HOME")"; \
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"; }
  source "$ZINIT_HOME/zinit.zsh"
  ```
- **Impact:** zinit (and the three plugins it then loads) are HTTPS-cloned with **no commit/tag pin**
  and `source`d into every interactive shell — trust-on-first-use of third-party code in **user**
  context. Bounded to the user account; this is the **upstream-documented** zinit install method,
  hence BAJO.
- **Recommendation:** Pin zinit and plugins to commits/tags (`ver"…"`/`@<sha>`) or vendor them.

### SEC-13 — `bootstrap.sh` `exec`s `install.sh` relying on the executable bit (a fresh clone may not preserve it)
- **File:** [bootstrap.sh:7](../../bootstrap.sh#L7) · lenses: supply-chain · confidence: media
- **Evidence:** `exec "$HOME/.archfrican/install.sh"`
- **Impact:** If `install.sh` is committed mode `100644` (or a `core.fileMode`/Windows-checked-in
  tree), the clone lands without `+x` and `exec` fails with *Permission denied*, bricking the
  one-liner on a clean machine (the local copy here is `-rwxr-xr-x`). Reliability, not security.
- **Recommendation:** `exec bash "$HOME/.archfrican/install.sh"`, or ensure mode `755` is committed and
  CI-checked.

### SEC-14 — CachyOS download uses `curl -L` without `-f` (HTTP error bodies saved as the tarball)
- **File:** [modules/00-base.sh:8](../../modules/00-base.sh#L8) · lenses: supply-chain · confidence: alta
- **Evidence:** `curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz`
- **Impact:** Without `-f`, a 404/5xx/captive-portal response is written to `repo.tar.xz` with exit 0.
  **Verifier correction:** because errexit is active, the next `tar xf` fails and **aborts** (no
  garbage reaches `sudo`); the only residual is a confusing `tar`-level error instead of a clean
  download failure — and it is **inconsistent** with `bootstrap.sh`'s `curl -fsSL`. Downgraded to BAJO.
- **Recommendation:** Use `curl -fL --proto '=https' --tlsv1.2`.

### SEC-15 — `theme-switch` fuzzel hash-strip `sed -i 's/=#/=/g'` is unanchored
- **File:** [bin/theme-switch:30](../../bin/theme-switch#L30) · lenses: injection · confidence: media
- **Evidence:** `sed -i 's/=#/=/g' "$CFG/fuzzel/colors.ini"   # fuzzel wants hex without #`
- **Impact:** Global match of literal `=#` anywhere in the file. Correct today (file only holds
  rendered `key=#RRGGBBaa` lines), brittle if the template later gains a comment or a value starting
  with `#`.
- **Recommendation:** Anchor to the value, e.g. `sed -i -E 's/=#([0-9a-fA-F]+)/=\1/'`, or render
  hex-without-`#` directly in the template.

### SEC-16 — `reflector` installed (potential unconstrained mirrorlist rewrite) — informational hygiene
- **File:** [packages/base.txt:12](../../packages/base.txt#L12) · lenses: trust-keys · confidence: media
- **Evidence:** `reflector              # keep mirrorlist fast`
- **Impact:** **Verifier:** Archfrican only **installs** `reflector`; it never invokes it nor enables
  `reflector.timer`/writes `reflector.conf` (repo-wide grep confirms). So any unconstrained
  mirror-rewrite is hypothetical/manual. pacman package signatures remain the integrity backstop.
  Near-INFO.
- **Recommendation:** If ever invoked, constrain it (`--protocol https --age … --sort rate`).

---

## INFO (incl. positive findings)

### SEC-17 — ✅ No plaintext secrets in the repo; credentials file correctly gitignored *(positive)*
- **File:** [archinstall/user_config.json](../../archinstall/user_config.json), [.gitignore:1](../../.gitignore#L1)
- A repo-wide grep for password/token/secret/api_key/private-key patterns returned **nothing**.
  `user_config.json` holds only non-sensitive install choices (bootloader, kernel, hostname,
  filesystem). The sensitive `archinstall/user_credentials.json` is listed in `.gitignore` (and
  `*.log`). Per **rule #3**: the repo is **not** a git repo locally, so nothing is "versioned"
  regardless — no leaked-secret-in-history risk to assess.
- **Note:** Keep all password fields strictly in the gitignored credentials file; consider a
  pre-commit grep guard once this becomes a git repo.

### SEC-18 — ✅ GPU `/etc` edits use static replacement text — no injection *(positive, with note)*
- **File:** [modules/10-gpu.sh:24-31](../../modules/10-gpu.sh#L24-L31) — replacement strings are
  hardcoded constants and the GPU profile comes from `lspci` detection, never reaching the `sed`
  replacement. (The robustness of the *guards* is tracked separately as SEC-09/SEC-10.)

### SEC-19 — `greetd` heredoc delimiter is unquoted (`<<TOML`) — latent footgun
- **File:** [modules/20-niri-desktop.sh:10-16](../../modules/20-niri-desktop.sh#L10-L16) — the body
  has no `$`/backtick/backslash today so it is benign, but a future edit adding `$…` would be expanded
  at install time into a root-owned config. The neighboring `keyd` block correctly uses `<<'KEYD'`.
- **Recommendation:** Quote it as `<<'TOML'` for consistency.

### SEC-20 — Shell tool initializers run via `eval "$(tool init …)"` at every startup (standard pattern)
- **File:** [home/dot_zshrc:26-31](../../home/dot_zshrc#L26-L31) — standard upstream integration of
  zoxide/fnm/direnv/starship from trusted binaries; marginal risk only if a binary is already
  compromised. Note: `starship init` is **not** guarded by `command -v`, so a missing starship errors
  on startup — guard it for consistency.

### SEC-21 — No version/commit pinning anywhere (reproducibility/auditability) — standard for rolling Arch
- **File:** [packages/aur.txt](../../packages/aur.txt) and all repo manifests — no lockfile, no
  pinned versions. **Verifier:** downgraded MEDIO→INFO since this is expected for rolling Arch and
  repo packages stay signature-verified; only AUR is unsigned-by-design. Optional: snapshot installed
  versions for forensics.

---

## Refuted / Discarded (4) — transparency

| Candidate | Orig. sev. | Why refuted (verifier read the code) |
|-----------|-----------|--------------------------------------|
| "curl lacks `--fail`; modules do not abort on error" ([00-base.sh:8-10](../../modules/00-base.sh#L8-L10)) | ALTO | The "modules don't abort" premise is **false** — errexit is inherited via the sourced `common.sh`; `tar` failure aborts before `sudo` runs. Only the cosmetic missing-`-f` survives (kept as SEC-14, BAJO). |
| "`enable_service` failures not surfaced; safety-net defeated" ([common.sh:37](../../lib/common.sh#L37)) | MEDIO | Same false premise: callers invoke it as a plain statement under active errexit, so a failed `systemctl enable` **aborts loudly** (proven empirically) — `ok()` never falsely reports success. Only a cosmetic missing `systemctl cat` precheck remains. |
| "snapper `^root` grep misfires → create-config errors every run" ([50-snapshots.sh:6-13](../../modules/50-snapshots.sh#L6-L13)) | BAJO | Mischaracterizes `snapper list-configs` output: the `Config` column is **left-aligned at column 0**, so `^root` matches reliably. The failure chain doesn't occur. |
| "`theme-switch` sources an attacker-influenceable path (traversal)" ([bin/theme-switch:7-11](../../bin/theme-switch#L7-L11)) | BAJO | No privilege boundary: `$1` is the **user's own argv** in their interactive shell (they are the trust root), and a `[ -f "$PAL" ]` guard plus the need for a pre-placed `colors.sh` mean no escalation. Hygiene at most, not a real finding in this threat model. |

---

## Cross-cutting note for later phases
- The **two highest-leverage files** in this phase are `lib/common.sh` (SEC-01 critical parser +
  SEC-11) and `modules/00-base.sh` (SEC-02 + SEC-03 + SEC-14) — both will recur in Phases 3–4.
- `bin/theme-switch` carries SEC-06/SEC-07/SEC-15 (escaping + destructive splice + strip) → revisit
  under Phase 2 (data integrity) and Phase 3 (reliability).
- The errexit-inheritance correction means **Phase 3 should NOT report "modules lack error handling"**
  as a blanket finding; the real reliability gaps are specific (silent `sed` no-ops, unguarded
  clobbers, `|| true` masking) rather than a global missing `set -e`.
