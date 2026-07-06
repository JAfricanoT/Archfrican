# Archfrican Wallpapers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bundle 5 curated Archfrican wallpaper images with the repo, deploy them to
`/usr/share/backgrounds/archfrican/` at install/converge time, and let the install wizard
pick one by name (staged the same way the theme choice already is).

**Architecture:** New `assets/wallpapers/` directory (same convention as `assets/sddm/`) holds
the 5 JPGs. `modules/20-niri-desktop.sh` deploys them to `/usr/share/backgrounds/archfrican/`
with the identical `sudo install -d` + `sudo cp -a` pattern already used for the SDDM theme
assets two lines above. `lib/converge.sh` registers the new directory as a drift input for that
module. `lib/phase2.sh` gets one more wizard question (`ui_choose`, same pattern as the existing
theme question) whose answer is staged into `~/.config/archfrican/wallpaper` — the exact file
`archfrican-wallpaper-restore` already reads, so no new runtime mechanism is needed at all.
`archfrican-wallpaper` itself is NOT modified: it already scans `/usr/share/backgrounds` (among
other directories) for pickable images, so the new files show up there automatically.

**Tech Stack:** Bash (`set -euo pipefail` throughout), existing `lib/common.sh`/`lib/ui.sh`
helpers, no new dependencies.

## Global Constraints

- Full spec: `docs/superpowers/specs/2026-07-03-archfrican-wallpapers-design.md`.
- The 5 source images already exist at `/home/jafricanot/Downloads/Archfrican-{Blue,Cross,Cube,
  CubeTwo,Curve}.jpg` — copy them into the repo verbatim, no resizing/recompression (explicit
  spec decision: prioritize quality on real 4K/8K monitors over repo size).
- Do NOT modify `home/dot_local/bin/executable_archfrican-wallpaper` or
  `executable_archfrican-wallpaper-restore` — the spec explicitly keeps this out of scope; the
  existing directory scan already covers the new location.
- Do NOT touch `lib/phase1.sh` (ISO Stage-1 resume) — the wallpaper question, like the Plasma
  question before it, is wizard-only (no ISO fast-path plumbing).
- Every script edited must still pass `bash -n`.
- Never run the real `sudo install -d /usr/share/backgrounds/archfrican` / `sudo cp -a` command
  against this live machine's actual `/usr/share` during automated verification — simulate it
  against a scratch directory instead (see Task 2's test). Actually deploying to the real system
  path is a live-system change the user reviews and runs themselves, not something to automate.

---

### Task 1: Add the 5 wallpaper images to the repo

**Files:**
- Create: `assets/wallpapers/Archfrican-Blue.jpg`
- Create: `assets/wallpapers/Archfrican-Cross.jpg`
- Create: `assets/wallpapers/Archfrican-Cube.jpg`
- Create: `assets/wallpapers/Archfrican-CubeTwo.jpg`
- Create: `assets/wallpapers/Archfrican-Curve.jpg`

**Interfaces:**
- Consumes: nothing (source files already exist on disk).
- Produces: `assets/wallpapers/*.jpg` — Task 2 reads this directory's contents via a glob copy
  (`cp -a "$REPO_ROOT/assets/wallpapers/." <dest>/`), not individual filenames, so exact
  filenames only matter for Task 4's wizard labels.

- [ ] **Step 1: Create the directory and copy the 5 images verbatim**

```bash
mkdir -p /home/jafricanot/Developer/Archfrican/assets/wallpapers
cp /home/jafricanot/Downloads/Archfrican-Blue.jpg \
   /home/jafricanot/Downloads/Archfrican-Cross.jpg \
   /home/jafricanot/Downloads/Archfrican-Cube.jpg \
   /home/jafricanot/Downloads/Archfrican-CubeTwo.jpg \
   /home/jafricanot/Downloads/Archfrican-Curve.jpg \
   /home/jafricanot/Developer/Archfrican/assets/wallpapers/
```

- [ ] **Step 2: Verify all 5 landed and are valid JPEGs**

Run: `identify /home/jafricanot/Developer/Archfrican/assets/wallpapers/*.jpg`

Expected: 5 lines, each `... JPEG <WxH> ... 8-bit sRGB ...`, no errors. Confirm no file is 0
bytes: `find /home/jafricanot/Developer/Archfrican/assets/wallpapers -size 0` must print nothing.

- [ ] **Step 3: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add assets/wallpapers/
git commit -m "$(cat <<'EOF'
feat(wallpaper): add 5 curated Archfrican wallpaper images

Same visual family (dark, system-blue #0a84ff accent, glass/prism
abstracts) fitting the macOS-grade identity already declared in
docs/DESIGN-LANGUAGE.md. Stored at full resolution (3840x2160 to
8000x4500) -- no resize/recompress, per spec.
EOF
)"
```

---

### Task 2: Deploy the wallpapers in `modules/20-niri-desktop.sh`

**Files:**
- Modify: `modules/20-niri-desktop.sh:15-16`

**Interfaces:**
- Consumes: `assets/wallpapers/` (Task 1's output), `$REPO_ROOT` (already exported by
  `lib/common.sh`, sourced at the top of this module).
- Produces: `/usr/share/backgrounds/archfrican/*.jpg` on the live system once this module
  actually runs — Task 5's live verification checks for this path. No other task in this plan
  reads this path programmatically.

- [ ] **Step 1: Read the current exact lines to confirm context**

Run: `sed -n '13,17p' /home/jafricanot/Developer/Archfrican/modules/20-niri-desktop.sh`

Expected output (confirm it matches before editing — if it doesn't, STOP and re-read the whole
file, something else changed it):

```bash
# greeter — see docs/CONTEXT.md.
substep "installing the SDDM theme (archfrican)"
sudo install -d -m 0755 /usr/share/sddm/themes/archfrican
sudo cp -a "$REPO_ROOT/assets/sddm/archfrican/." /usr/share/sddm/themes/archfrican/
# Paint the theme from the user's current palette (themes/<name>/colors.sh via the token template).
```

- [ ] **Step 2: Insert the wallpaper deployment right after the SDDM copy**

Edit `modules/20-niri-desktop.sh`, replacing:

```bash
substep "installing the SDDM theme (archfrican)"
sudo install -d -m 0755 /usr/share/sddm/themes/archfrican
sudo cp -a "$REPO_ROOT/assets/sddm/archfrican/." /usr/share/sddm/themes/archfrican/
```

with:

```bash
substep "installing the SDDM theme (archfrican)"
sudo install -d -m 0755 /usr/share/sddm/themes/archfrican
sudo cp -a "$REPO_ROOT/assets/sddm/archfrican/." /usr/share/sddm/themes/archfrican/

# Curated wallpapers — dropped where archfrican-wallpaper's own directory scan (find ...
# /usr/share/backgrounds ...) already looks, so they're pickable with ZERO changes to that
# script. Same install-d + cp -a idempotent-copy pattern as the SDDM theme assets above.
substep "installing curated Archfrican wallpapers"
sudo install -d -m 0755 /usr/share/backgrounds/archfrican
sudo cp -a "$REPO_ROOT/assets/wallpapers/." /usr/share/backgrounds/archfrican/
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n /home/jafricanot/Developer/Archfrican/modules/20-niri-desktop.sh`
Expected: no output, exit code 0.

- [ ] **Step 4: Dry-run the copy logic against a scratch directory (do NOT touch the real /usr/share)**

```bash
cd /home/jafricanot/Developer/Archfrican
tmpdest="$(mktemp -d)"
sudo() { "$@"; }  # stub: run the "sudo" commands as the current user against the scratch path
export -f sudo
REPO_ROOT="$PWD" bash -c '
  install -d -m 0755 "'"$tmpdest"'/archfrican"
  cp -a "$REPO_ROOT/assets/wallpapers/." "'"$tmpdest"'/archfrican/"
'
ls "$tmpdest/archfrican"
rm -rf "$tmpdest"
```

Expected: `ls` lists the same 5 `Archfrican-*.jpg` filenames from Task 1, nothing else.

- [ ] **Step 5: Commit**

```bash
git add modules/20-niri-desktop.sh
git commit -m "$(cat <<'EOF'
feat(wallpaper): deploy curated wallpapers to /usr/share/backgrounds

Same sudo install -d + cp -a pattern already used for the SDDM theme
assets two lines above. Lands them exactly where
archfrican-wallpaper's existing directory scan already looks, so
they become pickable with no changes to that script at all.
EOF
)"
```

---

### Task 3: Register the new assets for drift detection in `lib/converge.sh`

**Files:**
- Modify: `lib/converge.sh:27`

**Interfaces:**
- Consumes: nothing new.
- Produces: `module_inputs 20-niri-desktop` now includes `assets/wallpapers` in its
  space-separated output string — Task 3's own test reads this directly; no other task depends
  on it.

- [ ] **Step 1: Read the current exact line**

Run: `grep -n "20-niri-desktop" /home/jafricanot/Developer/Archfrican/lib/converge.sh`

Expected (line number may differ slightly if the file changed — locate the `20-niri-desktop)`
case arm inside `module_inputs()`, not the `ARCHFRICAN_MODULES` line):

```
    20-niri-desktop) printf ' packages/niri-desktop.txt templates/sddm.theme.conf assets/sddm/archfrican themes' ;;
```

- [ ] **Step 2: Add `assets/wallpapers` to that line**

Replace:
```bash
    20-niri-desktop) printf ' packages/niri-desktop.txt templates/sddm.theme.conf assets/sddm/archfrican themes' ;;
```
with:
```bash
    20-niri-desktop) printf ' packages/niri-desktop.txt templates/sddm.theme.conf assets/sddm/archfrican assets/wallpapers themes' ;;
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n /home/jafricanot/Developer/Archfrican/lib/converge.sh`
Expected: no output, exit code 0.

- [ ] **Step 4: Functional test — module_hash changes when a wallpaper file changes**

```bash
cd /home/jafricanot/Developer/Archfrican
REPO_ROOT="$PWD" bash -c '
  source lib/common.sh
  source lib/converge.sh
  before="$(module_hash 20-niri-desktop)"
  touch assets/wallpapers/Archfrican-Blue.jpg
  after="$(module_hash 20-niri-desktop)"
  if [ "$before" != "$after" ]; then
    echo "OK: hash changed ($before -> $after)"
  else
    echo "FAIL: hash did not change after touching a wallpaper file"
    exit 1
  fi
'
```

Expected: prints `OK: hash changed (...)`. (`touch` only updates the mtime, but `module_hash`
tree-hashes directory *content* per the existing pattern used for `assets/sddm/archfrican` and
`themes` on the same line — if this fails, re-check how `module_hash` hashes a bare directory
name vs a file, in `lib/converge.sh`, before assuming the line edit was wrong.)

- [ ] **Step 5: Confirm `module_inputs` output includes the new path**

```bash
cd /home/jafricanot/Developer/Archfrican
REPO_ROOT="$PWD" bash -c 'source lib/common.sh; source lib/converge.sh; module_inputs 20-niri-desktop'
```

Expected output:
```
 packages/niri-desktop.txt templates/sddm.theme.conf assets/sddm/archfrican assets/wallpapers themes
```

- [ ] **Step 6: Commit**

```bash
git add lib/converge.sh
git commit -m "$(cat <<'EOF'
fix(converge): track assets/wallpapers as a 20-niri-desktop drift input

Without this, editing or adding a wallpaper image would never trigger
re-convergence (archfrican-doctor would report no drift, and
archfrican-update --converge would skip re-copying it) -- same
reasoning already applied to assets/sddm/archfrican on the same line.
EOF
)"
```

---

### Task 4: Add the wallpaper question to the install wizard in `lib/phase2.sh`

**Files:**
- Modify: `lib/phase2.sh` (three spots: local var declaration, the interactive wizard block, the
  "Applying your choices" staging block)

**Interfaces:**
- Consumes: nothing from earlier tasks at the bash level (this task only needs to know the 5
  image basenames from Task 1, hardcoded into the `ui_choose` call and the `case` mapping below
  — if Task 1's filenames ever change, this task's `case` statement must be updated to match).
- Produces: `~/.config/archfrican/wallpaper` may get written during a fresh interactive install —
  this is the exact file `archfrican-wallpaper-restore` (unmodified, pre-existing script) already
  reads at every login. No other task in this plan reads or writes this file.

- [ ] **Step 1: Read the current exact lines to confirm context**

Run: `sed -n '91,92p' /home/jafricanot/Developer/Archfrican/lib/phase2.sh`

Expected (the local var declaration line — confirm `PLASMA=no` is the last flag before editing;
if the line looks different, STOP and re-read the whole `run_phase2` function before proceeding):

```bash
  local HOST USER_NAME USER_PW TZ LOCALE XKB THEME GPU MULTIBOOT=no SSH_ENABLE=no GAMING=no PLASMA=no
```

- [ ] **Step 2: Add the `WALLPAPER` local variable**

Replace:
```bash
  local HOST USER_NAME USER_PW TZ LOCALE XKB THEME GPU MULTIBOOT=no SSH_ENABLE=no GAMING=no PLASMA=no
```
with:
```bash
  local HOST USER_NAME USER_PW TZ LOCALE XKB THEME GPU MULTIBOOT=no SSH_ENABLE=no GAMING=no PLASMA=no WALLPAPER=none
```

- [ ] **Step 3: Add the wizard question right after the theme question**

Find this line (still inside the interactive `if` block):
```bash
    THEME="$(ui_choose 'Initial theme' archfrican-dark archfrican-light catppuccin-mocha tokyo-night high-contrast)"
```

Insert immediately after it:
```bash
    WALLPAPER="$(ui_choose 'Wallpaper' none Blue Cross Cube CubeTwo Curve)"
```

(`none` is the literal choice value used below in Step 5's `case`, matching the pattern of a
plain sentinel string rather than free text — `ui_choose` returns exactly one of the words
passed to it, so this is safe to `case`-match verbatim.)

- [ ] **Step 4: Confirm the "Applying your choices" staging block's current exact content**

Run: `grep -n -A9 'step "Applying your choices"' /home/jafricanot/Developer/Archfrican/lib/phase2.sh`

Expected:
```bash
    step "Applying your choices" "hostname · user · timezone · locale · keyboard"
    apply_hostname        "$HOST"
    apply_user            "$USER_NAME" "$USER_PW"
    apply_timezone        "$TZ"
    apply_locale_keyboard "$LOCALE" "$XKB" "$XKB"
    mkdir -p "$HOME/.config"
    printf '%s\n' "$THEME" > "$HOME/.config/.archfrican-theme"   # chezmoi run_after applies it last
    printf '%s\n' "$XKB"   > "$HOME/.config/.archfrican-kbd"     # niri config.kdl template reads it
    ok "staged theme=$THEME, niri keyboard=$XKB"
```

- [ ] **Step 5: Add wallpaper staging into that same block**

Replace:
```bash
    mkdir -p "$HOME/.config"
    printf '%s\n' "$THEME" > "$HOME/.config/.archfrican-theme"   # chezmoi run_after applies it last
    printf '%s\n' "$XKB"   > "$HOME/.config/.archfrican-kbd"     # niri config.kdl template reads it
    ok "staged theme=$THEME, niri keyboard=$XKB"
```
with:
```bash
    mkdir -p "$HOME/.config"
    printf '%s\n' "$THEME" > "$HOME/.config/.archfrican-theme"   # chezmoi run_after applies it last
    printf '%s\n' "$XKB"   > "$HOME/.config/.archfrican-kbd"     # niri config.kdl template reads it
    # Wallpaper (opt-in, default "none" = keep the solid-color fallback exactly as before). Written
    # to the SAME file archfrican-wallpaper-restore already reads at every login -- no new mechanism.
    if [ "$WALLPAPER" != none ]; then
      mkdir -p "$HOME/.config/archfrican"
      printf '%s\n' "/usr/share/backgrounds/archfrican/Archfrican-$WALLPAPER.jpg" > "$HOME/.config/archfrican/wallpaper"
    fi
    ok "staged theme=$THEME, niri keyboard=$XKB, wallpaper=$WALLPAPER"
```

- [ ] **Step 6: Verify syntax**

Run: `bash -n /home/jafricanot/Developer/Archfrican/lib/phase2.sh`
Expected: no output, exit code 0.

- [ ] **Step 7: Functional test — staging logic in isolation**

This test exercises just the staging block's logic (not the full interactive wizard, which needs
a real TTY) by simulating the two cases directly:

```bash
tmphome="$(mktemp -d)"
HOME="$tmphome" WALLPAPER=Blue bash -c '
  if [ "$WALLPAPER" != none ]; then
    mkdir -p "$HOME/.config/archfrican"
    printf "%s\n" "/usr/share/backgrounds/archfrican/Archfrican-$WALLPAPER.jpg" > "$HOME/.config/archfrican/wallpaper"
  fi
'
echo "--- case WALLPAPER=Blue ---"
cat "$tmphome/.config/archfrican/wallpaper"
rm -rf "$tmphome"

tmphome="$(mktemp -d)"
HOME="$tmphome" WALLPAPER=none bash -c '
  if [ "$WALLPAPER" != none ]; then
    mkdir -p "$HOME/.config/archfrican"
    printf "%s\n" "/usr/share/backgrounds/archfrican/Archfrican-$WALLPAPER.jpg" > "$HOME/.config/archfrican/wallpaper"
  fi
'
echo "--- case WALLPAPER=none (must NOT create the file) ---"
[ -e "$tmphome/.config/archfrican/wallpaper" ] && echo "FAIL: file was created" || echo "OK: no file created"
rm -rf "$tmphome"
```

Expected output:
```
--- case WALLPAPER=Blue ---
/usr/share/backgrounds/archfrican/Archfrican-Blue.jpg
--- case WALLPAPER=none (must NOT create the file) ---
OK: no file created
```

- [ ] **Step 8: Commit**

```bash
cd /home/jafricanot/Developer/Archfrican
git add lib/phase2.sh
git commit -m "$(cat <<'EOF'
feat(wallpaper): ask for a wallpaper in the install wizard

Same ui_choose pattern as the existing theme question -- picks by
name (the wizard is a terminal TUI, no image preview there). Staged
into ~/.config/archfrican/wallpaper, the exact file
archfrican-wallpaper-restore already reads at every login, so
picking one here means it's applied from the very first login with
no extra mechanism. Default "none" preserves today's solid-color
fallback exactly.
EOF
)"
```

---

### Task 5: End-to-end static verification + live-verification instructions

**Files:** none modified — this task only runs checks and documents the manual live-verification
steps for the user to run themselves (deploying to the real `/usr/share/backgrounds` requires
sudo on the real machine, which this plan does not run automatically).

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: nothing further downstream.

- [ ] **Step 1: Full static re-check of every file this plan touched**

```bash
cd /home/jafricanot/Developer/Archfrican
for f in modules/20-niri-desktop.sh lib/converge.sh lib/phase2.sh; do
  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done
identify assets/wallpapers/*.jpg
```

Expected: `OK: <file>` for all three scripts, and 5 valid JPEG lines from `identify`.

- [ ] **Step 2: Re-run the existing test suites to confirm nothing regressed**

```bash
bash tests/unit/manifest.sh | tail -3
bash tests/unit/detect-gpu.sh | tail -3
```

Expected: `manifest unit test: 9 passed, 0 failed` and `detect-gpu unit test: 13 passed, 0
failed` (this plan doesn't touch either file, so these numbers should be unchanged from before
this plan started — if they differ, something else changed concurrently; investigate before
continuing).

- [ ] **Step 3: Document the live-verification steps (for the user to run themselves)**

Add nothing to a file — this step is just running the following manually, since it touches the
real system's `/usr/share`:

```bash
~/.archfrican/install.sh 20-niri-desktop
ls /usr/share/backgrounds/archfrican/
```
Expected: the 5 `Archfrican-*.jpg` files are present.

Then, from inside the niri session: press `Mod+Shift+A` → `Wallpaper / theming dinámico…` (or
run `archfrican-wallpaper` directly), and confirm the 5 new images appear in the picker list
alongside anything already in `~/Pictures`/`~/Downloads`.

- [ ] **Step 4: No commit for this task** (verification-only; nothing to add to git).
