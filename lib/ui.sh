#!/usr/bin/env bash
# Comfortable wizard/modal primitives. Sourced after lib/common.sh (inherits
# set -euo pipefail + log/ok/warn/die/have/best_effort/pac_install).
#
# Backend resolved ONCE: gum (pretty) if present, else plain read/read -s.
# Contract for every wrapper: the chosen VALUE goes to stdout; all prompts,
# headers and spinners go to stderr — so `x="$(ui_input …)"` stays clean under
# errexit. Plain reads come from </dev/tty so a piped stdin (curl|sh) can't be
# mistaken for the keyboard.

if have gum; then UI_BACKEND=gum; else UI_BACKEND=plain; fi
export UI_BACKEND

# Upgrade plain -> gum on a booted base only (gum is in extra/x86_64). Best-effort.
ui_install_gum() {
  [ "$UI_BACKEND" = gum ] && return 0
  have pacman || return 0
  best_effort pac_install gum
  have gum && { UI_BACKEND=gum; export UI_BACKEND; }
  return 0
}

# Is an interactive terminal available for prompts?
ui_interactive() { [ -t 0 ] || [ -e /dev/tty ]; }

ui_header() { printf '\n\e[1;34m══ %s ══\e[0m\n' "$*" >&2; }
ui_note()   { printf '   %s\n' "$*" >&2; }

ui_input() {                       # ui_input "label" "default"
  local label="$1" def="${2:-}" ans
  if [ "$UI_BACKEND" = gum ]; then
    gum input --prompt "$label: " --value "$def"
  else
    read -rp "$label [$def]: " ans </dev/tty >&2 || true
    printf '%s' "${ans:-$def}"
  fi
}

ui_password() {                    # ui_password "label"  -> hidden, confirm twice
  local label="$1" p1 p2 tries=0
  while :; do
    if [ "$UI_BACKEND" = gum ]; then
      p1="$(gum input --password --prompt "$label: ")"
      p2="$(gum input --password --prompt "confirm $label: ")"
    else
      read -rsp "$label: " p1 </dev/tty >&2; printf '\n' >&2
      read -rsp "confirm $label: " p2 </dev/tty >&2; printf '\n' >&2
    fi
    [ -n "$p1" ] && [ "$p1" = "$p2" ] && { printf '%s' "$p1"; return 0; }
    tries=$((tries + 1)); [ "$tries" -ge 3 ] && die "password entry failed (empty/mismatch x3)"
    printf '   passwords empty or do not match — try again\n' >&2
  done
}

ui_choose() {                      # ui_choose "label" opt1 opt2 ...
  local label="$1"; shift
  local opts=("$@") i sel
  if [ "$UI_BACKEND" = gum ]; then
    printf '%s\n' "${opts[@]}" | gum choose --header "$label"
  else
    for i in "${!opts[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${opts[$i]}" >&2; done
    while :; do
      read -rp "$label [1-${#opts[@]}]: " sel </dev/tty >&2 || true
      sel="${sel:-1}"
      [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#opts[@]}" ] && break
    done
    printf '%s' "${opts[$((sel - 1))]}"
  fi
}

ui_filter() {                      # <options on stdin>  ui_filter "label" [default]  -> picked value
  local label="$1" def="${2:-}" sel
  if [ "$UI_BACKEND" = gum ]; then
    sel="$(gum filter --placeholder "$label — type to search, Enter to pick" --height 15)"
    printf '%s' "${sel:-$def}"
  else
    cat >/dev/null                 # no fuzzy UI without gum: drain the list, fall back to free text
    read -rp "$label [$def]: " sel </dev/tty >&2 || true
    printf '%s' "${sel:-$def}"
  fi
}

ui_confirm() {                     # ui_confirm "question" [default:yes|no]  -> rc 0 (yes) / 1 (no)
  local a def="${2:-yes}"          # default yes unless explicitly "no" (e.g. the REAL-install gate)
  if [ "$UI_BACKEND" = gum ]; then
    if [ "$def" = no ]; then gum confirm --default=false "$1"; else gum confirm --default=true "$1"; fi
  elif [ "$def" = no ]; then
    read -rp "$1 [y/N]: " a </dev/tty >&2 || true; [[ "${a:-n}" =~ ^[Yy]$ ]]
  else
    read -rp "$1 [Y/n]: " a </dev/tty >&2 || true; [[ "${a:-y}" =~ ^[Yy]$ ]]
  fi
}

