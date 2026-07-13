#!/usr/bin/env bash
# Shared helpers for all modules. Sourced, never executed directly.

set -euo pipefail

# ---- pretty logging -------------------------------------------------------
c_reset=$'\e[0m'; c_blue=$'\e[34m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'
log()   { printf '%s==>%s %s\n' "$c_blue"  "$c_reset" "$*"; }
ok()    { printf '%s  ✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn()  { printf '%s  !%s %s\n' "$c_yellow" "$c_reset" "$*"; }
die()   { printf '%s  ✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

# ---- progress narration ---------------------------------------------------
# step()    = a prominent [N/TOTAL] phase banner (owned by the orchestrator).
# substep() = one action inside a phase, so nothing happens silently.
# UI_BACKEND is exported by lib/ui.sh, so module subprocesses inherit it.
STEP_N=0; STEP_TOTAL=0
step_total() { STEP_TOTAL="$1"; STEP_N=0; }
step() {                          # step "title" ["detail"]
  STEP_N=$((STEP_N + 1))
  if [ "${UI_BACKEND:-plain}" = gum ]; then
    gum style --border rounded --border-foreground 39 --padding "0 1" \
      "$(printf '[%d/%d]  %s' "$STEP_N" "$STEP_TOTAL" "$1")" >&2
  else
    printf '\n\e[1;36m╭─ [%d/%d] %s\e[0m\n' "$STEP_N" "$STEP_TOTAL" "$1" >&2
  fi
  [ -n "${2:-}" ] && printf '   \e[2m%s\e[0m\n' "$2" >&2
  return 0
}
substep() { printf '\e[36m   → %s\e[0m\n' "$*" >&2; }

# ---- failure-intent vocabulary -------------------------------------------
# One mechanism per concern, so no module has to re-derive set -e short-circuit
# rules (the thing 30-dev's rustup line got wrong). Policy:
#   FATAL          = no helper; let `set -e` abort (package installs, /etc writes,
#                    grub-mkconfig, snapper create-config, must-succeed services).
#   best_effort … = step may legitimately be absent/no-op; failure -> warn, continue.
#   attempt "L" … = step should work but must not abort a desktop install; failure
#                    is LOUD (replaces blanket `|| true`, so nothing fails silently).
have()        { command -v "$1" &>/dev/null; }
best_effort() { "$@" || { warn "skipped (non-fatal): $*"; return 0; }; }
attempt()     { local _l="$1"; shift; "$@" || { warn "FAILED (continuing): ${_l} [$*]"; return 0; }; }

# Enable a unit only if it exists; never abort the caller (built on best_effort).
# Use plain `enable_service` for units that MUST succeed (sddm, docker).
resilient_enable() {
  local u="$1"
  sudo systemctl list-unit-files --no-legend -- "$u" 2>/dev/null | grep -q . \
    || { warn "unit not present, skipping: $u"; return 0; }
  best_effort sudo systemctl enable "$u"
}

# --user analogue: enable a user unit only if it exists; never abort (a TTY install
# may have no user bus). Pairs well with `loginctl enable-linger "$USER"`.
resilient_enable_user() {
  local u="$1"
  systemctl --user list-unit-files --no-legend -- "$u" 2>/dev/null | grep -q . \
    || { warn "user unit not present, skipping: $u"; return 0; }
  best_effort systemctl --user enable "$u"
}

# Write content (on stdin) to a root-owned file idempotently: back up an existing
# DIFFERENT file once (<path>.archfrican.bak), skip the write when unchanged, and
# create parent dirs. Replaces blind `tee` clobbers of /etc configs.
write_system_file() {             # write_system_file <path> [mode]   (content on stdin)
  local path="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"; cat > "$tmp"
  if [ -e "$path" ] && sudo cmp -s "$tmp" "$path"; then rm -f "$tmp"; ok "unchanged: $path"; return 0; fi
  if [ -e "$path" ] && [ ! -e "$path.archfrican.bak" ]; then
    sudo cp -a "$path" "$path.archfrican.bak"; warn "backed up $path -> $path.archfrican.bak"
  fi
  sudo install -D -m "$mode" "$tmp" "$path"; rm -f "$tmp"; ok "wrote $path"
}

# The bedrock pacstrap set — what makes a bootable Archfrican base. Single source for
# lib/base-install.sh (fresh install) and lib/deep-clean.sh (factory reset rebuilds @ from this
# same set, so the two can never drift). Conditional extras (cryptsetup when encrypted, the CPU
# microcode) are appended by each caller — they are probe-dependent, not part of the fixed set.
# shellcheck disable=SC2034  # consumed by the two libs above, sourced after this file
AF_BEDROCK_PKGS=(base linux-lts linux-firmware btrfs-progs grub efibootmgr sudo networkmanager git zram-generator)

# All curated themes = the directories under themes/ — the SAME glob the user-side pickers use
# (archfrican-welcome, archfrican-setup), so the wizard list can never drift from what ships
# (themes/tokens.defaults.sh documents this as the intended pattern).
list_themes() { local d; for d in "$REPO_ROOT"/themes/*/; do [ -d "$d" ] && basename "$d"; done; }

# THE default theme — what a machine wears while ~/.config/.archfrican-theme doesn't exist yet.
# home/dot_local/lib/archfrican-common.sh carries the same constant for the deployed user
# scripts (they never see this lib); keep the two identical.
ARCHFRICAN_DEFAULT_THEME=archfrican-dark
current_theme() { cat "$HOME/.config/.archfrican-theme" 2>/dev/null || echo "$ARCHFRICAN_DEFAULT_THEME"; }

# CPU-microcode package for THIS machine: intel-ucode / amd-ucode / nothing (unknown vendor).
# Used by lib/base-install.sh (pacstrap extras) and modules/60-security.sh (booted backfill).
cpu_ucode() {
  case "$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo 2>/dev/null)" in
    GenuineIntel) printf 'intel-ucode';; AuthenticAMD) printf 'amd-ucode';;
  esac
}

# Enable a locale in locale.gen: validate the charset (the name is interpolated into the
# regexes), uncomment an existing '#<locale> …' line, or APPEND '<locale> UTF-8' when the file
# doesn't carry it at all (a trimmed locale.gen, an exotic LANG) — without the append branch the
# edit is a silent no-op and LANG ends up pointing at an ungenerated locale. Runs unprivileged
# and never calls sudo itself: the ISO chroot embeds it via `declare -f` (already root), the
# booted path (lib/host-config.sh) wraps it in `sudo bash -c`.
enable_locale_gen() {             # enable_locale_gen <locale> [<locale.gen path>]
  local loc="$1" gen="${2:-/etc/locale.gen}"
  case "$loc" in *[!A-Za-z0-9._@-]*) echo "FATAL: invalid locale '$loc'" >&2; return 1;; esac
  if grep -qE "^#\s*${loc} " "$gen"; then sed -i "s/^#\s*\(${loc} .*\)/\1/" "$gen"
  elif ! grep -qE "^${loc} " "$gen"; then printf '%s UTF-8\n' "$loc" >> "$gen"; fi
}

# Paint the SDDM login theme from a palette: token-substitute templates/sddm.theme.conf with the
# colors in themes/<theme>/colors.sh and write it to the system theme path (idempotent, via
# write_system_file). The greeter runs pre-login (no ~/.config), so this MUST live under /usr/share.
# Used authoritatively by modules/15-desktop-services.sh; bin/theme-switch updates it live (best-effort).
render_sddm_theme() {             # render_sddm_theme <theme-name>
  local theme="$1"
  local pal="$REPO_ROOT/themes/$theme/colors.sh" tmpl="$REPO_ROOT/templates/sddm.theme.conf"
  if [ ! -r "$pal" ] || [ ! -r "$tmpl" ]; then warn "render_sddm_theme: missing $pal or $tmpl — skipping"; return 0; fi
  ( # same defaults -> palette -> per-theme tokens cascade bin/theme-switch uses: the template
    # now carries ${FONT_UI} (the Inter identity), not just palette colours.
    # shellcheck disable=SC1090
    if [ -r "$REPO_ROOT/themes/tokens.defaults.sh" ]; then . "$REPO_ROOT/themes/tokens.defaults.sh"; fi
    # shellcheck disable=SC1090
    . "$pal"
    # shellcheck disable=SC1090
    if [ -r "$REPO_ROOT/themes/$theme/tokens.sh" ]; then . "$REPO_ROOT/themes/$theme/tokens.sh"; fi
    # shellcheck disable=SC2154
    sed -e "s|\${BG}|$BG|g" -e "s|\${BG_ALT}|$BG_ALT|g" -e "s|\${BG_DIM}|$BG_DIM|g" \
        -e "s|\${FG}|$FG|g" -e "s|\${FG_DIM}|$FG_DIM|g" -e "s|\${ACCENT}|$ACCENT|g" \
        -e "s|\${MAGENTA}|$MAGENTA|g" -e "s|\${CYAN}|$CYAN|g" \
        -e "s|\${FONT_UI}|$FONT_UI|g" "$tmpl"
  ) | write_system_file /usr/share/sddm/themes/archfrican/theme.conf 0644
}

render_grub_theme() {             # render_grub_theme <theme-name>  ->  /boot/grub/themes/archfrican/theme.txt
  local theme="$1"
  local pal="$REPO_ROOT/themes/$theme/colors.sh" tmpl="$REPO_ROOT/templates/grub.theme.txt"
  if [ ! -r "$pal" ] || [ ! -r "$tmpl" ]; then warn "render_grub_theme: missing $pal or $tmpl — skipping"; return 0; fi
  ( # shellcheck disable=SC1090
    . "$pal"
    # shellcheck disable=SC2154   # BG/BG_DIM/FG/FG_DIM/ACCENT come from the sourced palette (GRUB uses hex directly)
    sed -e "s|\${BG}|$BG|g" -e "s|\${BG_DIM}|$BG_DIM|g" \
        -e "s|\${FG}|$FG|g" -e "s|\${FG_DIM}|$FG_DIM|g" -e "s|\${ACCENT}|$ACCENT|g" "$tmpl"
  ) | write_system_file /boot/grub/themes/archfrican/theme.txt 0644
}

# Best-effort: paint KDE Plasma (if installed) from the SAME palette used by GTK/niri/waybar/etc.
# Used authoritatively by modules/25-plasma-desktop.sh (once, at install/re-run); bin/theme-switch
# paints LIVE switches with the same shared lib/plasma-theme.sh (sourced from the deployed clone).
# Gated on kwriteconfig6 (ships with kconfig, a guaranteed transitive dependency of plasma-desktop)
# — a hard no-op on any niri-only machine.
apply_plasma_theme() {            # apply_plasma_theme <theme-name>
  have kwriteconfig6 || return 0
  local theme="$1"
  # 'dynamic' = the wallpaper-generated palette in user state (archfrican-wallpaper), same special
  # case bin/theme-switch handles — it lives OUTSIDE themes/ on purpose (see bin/theme-switch's own
  # comment), so it needs its own path instead of themes/$theme/colors.sh.
  local pal="$REPO_ROOT/themes/$theme/colors.sh"
  if [ "$theme" = dynamic ] && [ -r "$HOME/.config/archfrican/dynamic-colors.sh" ]; then
    pal="$HOME/.config/archfrican/dynamic-colors.sh"
  fi
  [ -r "$pal" ] || { warn "apply_plasma_theme: no such theme $theme — skipping"; return 0; }
  (
    # shellcheck disable=SC1090
    if [ -r "$REPO_ROOT/themes/tokens.defaults.sh" ]; then . "$REPO_ROOT/themes/tokens.defaults.sh"; fi
    # shellcheck disable=SC1090
    . "$pal"
    # Per-theme shape/type override (e.g. a theme restoring different fonts/radii) — same cascade
    # bin/theme-switch uses: defaults -> palette -> theme's own tokens.sh, last one wins.
    # shellcheck disable=SC1090
    if [ -r "$REPO_ROOT/themes/$theme/tokens.sh" ]; then . "$REPO_ROOT/themes/$theme/tokens.sh"; fi
    # shellcheck source=lib/plasma-theme.sh
    . "$REPO_ROOT/lib/plasma-theme.sh"
    plasma_paint
  )
  ok "Plasma theme painted from '$theme' (color scheme, icons, cursor, fonts; wallpaper best-effort)"
}

# ---- idempotent package install ------------------------------------------
# Installs only what's missing so the script is safe to re-run.
pac_install() {            # pac_install pkg1 pkg2 ...
  local p missing=()
  for p in "$@"; do
    pacman -Q "$p" &>/dev/null || missing+=("$p")
  done
  [ ${#missing[@]} -eq 0 ] && { ok "already present: $*"; return; }
  substep "installing ${#missing[@]} package(s): ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
}

aur_install() {           # aur_install pkg1 pkg2 ...  — per-package + NON-FATAL
  # These are the cosmetic AUR layer (themes/icons/cursors/fonts/dock). AUR builds are inherently
  # fragile (upstream PKGBUILD drift, checksum changes), so one failing build must NOT abort the whole
  # first-boot resume — the core desktop is already installed. Build each on its own; warn + continue.
  local p failed=()
  for p in "$@"; do
    pacman -Q "$p" &>/dev/null && continue
    substep "building/installing AUR package: $p"
    # timeout: an AUR build is network (source fetch) + compile — 30min is generous for either, and
    # a genuinely-stuck build fails exactly like any other build failure here (warn + continue).
    timeout 1800 paru -S --needed --noconfirm "$p" || { warn "AUR build failed (continuing): $p"; failed+=("$p"); }
  done
  [ ${#failed[@]} -eq 0 ] && { ok "AUR layer OK"; return 0; }
  warn "AUR package(s) that did NOT build: ${failed[*]} — the desktop still works."
  warn "retry later:  paru -S ${failed[*]}"
  return 0
}

# ---- package-list parsing (single source of truth) ------------------------
# Strips inline AND whole-line comments, trims whitespace, dies loudly on an
# unreadable or empty list. Returns the result via nameref (avoids the
# `local x=$(...)` exit-status masking trap). Reads with a real redirect so a
# read failure is not hidden inside a process substitution.
read_pkg_list() {                 # read_pkg_list <file> <array-name>
  local __rpl_f="$1"; local -n __rpl_out="$2"; __rpl_out=()
  [ -r "$__rpl_f" ] || die "package list not readable: $__rpl_f"
  local __rpl_line __rpl_pkg
  while IFS= read -r __rpl_line || [ -n "$__rpl_line" ]; do
    __rpl_pkg="${__rpl_line%%#*}"                                  # drop inline + whole-line comment
    __rpl_pkg="${__rpl_pkg#"${__rpl_pkg%%[![:space:]]*}"}"        # ltrim
    __rpl_pkg="${__rpl_pkg%"${__rpl_pkg##*[![:space:]]}"}"        # rtrim
    [ -n "$__rpl_pkg" ] || continue
    __rpl_out+=("$__rpl_pkg")
  done < "$__rpl_f"
  [ "${#__rpl_out[@]}" -gt 0 ] || die "no packages in $__rpl_f (all comments/blank?)"
}

pac_install_file() { local pkgs; read_pkg_list "$1" pkgs; pac_install "${pkgs[@]}"; }
aur_install_file() { local pkgs; read_pkg_list "$1" pkgs; aur_install "${pkgs[@]}"; }

# ---- recurrence-prevention checks ----------------------------------------
# Assert every entry in the pacman-installed lists resolves in a binary repo,
# BEFORE any state changes. Catches a misfiled AUR-only pkg or a typo (the
# class that let ghostty go missing). Warn by default; ARCHFRICAN_STRICT_PREFLIGHT=1
# makes it fatal; ARCHFRICAN_SKIP_PREFLIGHT=1 disables it. aur.txt is paru's job.
preflight_pkgs() {
  [ "${ARCHFRICAN_SKIP_PREFLIGHT:-0}" = 1 ] && { warn "preflight skipped (ARCHFRICAN_SKIP_PREFLIGHT=1)"; return 0; }
  local f base pkgs p bad=()
  for f in "$REPO_ROOT"/packages/*.txt; do
    base="$(basename "$f")"
    [ "$base" = aur.txt ] && continue
    read_pkg_list "$f" pkgs
    sudo pacman -Sp --print-format '%n' "${pkgs[@]}" &>/dev/null && continue
    for p in "${pkgs[@]}"; do
      sudo pacman -Sp "$p" &>/dev/null || bad+=("$base:$p")
    done
  done
  [ "${#bad[@]}" -eq 0 ] && { ok "preflight: all pacman lists resolve"; return 0; }
  [ "${ARCHFRICAN_STRICT_PREFLIGHT:-0}" = 1 ] \
    && die "preflight: unresolved/AUR pkg in a pacman list -> ${bad[*]}"
  warn "preflight: these will likely fail to install (move to aur.txt or fix): ${bad[*]}"
}

# Every binary niri is told to spawn must resolve to something installed.
# Resolves binary -> owner via PATH / absolute-path test (not string-matching
# the lists), so awww-daemon, wpctl, the absolute polkit path, etc. are handled.
verify_spawns() {                 # verify_spawns <niri-config.kdl> — WM-coupled (parses niri spawn-at-startup); docs/WM-INTEGRATION.md
  local cfg="$1" t missing=()
  [ -r "$cfg" ] || { warn "verify_spawns: no config at $cfg"; return 0; }
  while IFS= read -r t; do
    case "$t" in sh|bash) continue;; esac
    if [[ "$t" == /* ]]; then [ -x "$t" ] || missing+=("$t")
    else have "$t" || missing+=("$t"); fi
  done < <(grep -oE 'spawn(-at-startup)? +"[^"]+"' "$cfg" | sed -E 's/.*"([^"]+)"/\1/')
  [ "${#missing[@]}" -eq 0 ] && { ok "all niri spawns resolve"; return 0; }
  die "config spawns binaries no package installs: ${missing[*]}"
}

enable_service()      { sudo systemctl enable "$1"; ok "enabled $1"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
