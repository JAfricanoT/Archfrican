#!/usr/bin/env bash
# Shared helpers for all modules. Sourced, never executed directly.

set -euo pipefail

# ---- pretty logging -------------------------------------------------------
c_reset=$'\e[0m'; c_blue=$'\e[34m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'
log()   { printf '%s==>%s %s\n' "$c_blue"  "$c_reset" "$*"; }
ok()    { printf '%s  ✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn()  { printf '%s  !%s %s\n' "$c_yellow" "$c_reset" "$*"; }
die()   { printf '%s  ✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

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
# Use plain `enable_service` for units that MUST succeed (greetd, docker).
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

# ---- idempotent package install ------------------------------------------
# Installs only what's missing so the script is safe to re-run.
pac_install() {            # pac_install pkg1 pkg2 ...
  local p missing=()
  for p in "$@"; do
    pacman -Q "$p" &>/dev/null || missing+=("$p")
  done
  [ ${#missing[@]} -eq 0 ] && { ok "already present: $*"; return; }
  sudo pacman -S --needed --noconfirm "${missing[@]}"
}

aur_install() {           # aur_install pkg1 pkg2 ...
  local p missing=()
  for p in "$@"; do
    pacman -Q "$p" &>/dev/null || missing+=("$p")
  done
  [ ${#missing[@]} -eq 0 ] && { ok "already present (aur): $*"; return; }
  paru -S --needed --noconfirm "${missing[@]}"
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
# the lists), so swww-daemon, wpctl, the absolute polkit path, etc. are handled.
verify_spawns() {                 # verify_spawns <niri-config.kdl>
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
enable_user_service() { systemctl --user enable "$1"; ok "enabled (user) $1"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
