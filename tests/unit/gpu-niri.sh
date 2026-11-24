#!/usr/bin/env bash
# Unit test for per-GPU niri workarounds (lib/gpu-niri.sh + config.kdl.tmpl + converge.sh).
# Guards the live-confirmed nouveau/Kepler (GeForce GT 730 / GK208B) flicker fix so it survives
# fresh installs, `chezmoi apply`, and `archfrican-update --converge` without risking config.kdl:
#   1. Splicing the nouveau debug block into the rendered config.kdl.tmpl passes `niri validate`.
#   2. Splicing twice is idempotent (exactly one `debug {` block).
#   3. Removing the sidecar clears the managed block cleanly (non-nouveau / GPU upgrade path).
#   4. Validate-or-revert: a block rejected by `niri validate` leaves config.kdl rolled back.
#   5. Missing config.kdl (fresh install before chezmoi) is a clean no-op (exit 0).
#   6. Native Wayland env for Orca IDE (`ORCA_IDE_OZONE_PLATFORM "wayland"`) stays in config.kdl.tmpl.
#   7. Editing lib/gpu-niri.sh drifts 10-gpu in lib/converge.sh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/gpu-niri.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
has()  { if grep -qF "$2" "$1"; then _ok "$3"; else _no "$3"; fi; }
hasnt(){ if grep -qF "$2" "$1"; then _no "$3"; else _ok "$3"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME/niri" "$XDG_CONFIG_HOME/archfrican"

KDL="$XDG_CONFIG_HOME/niri/config.kdl"
SIDE="$XDG_CONFIG_HOME/archfrican/gpu-niri.kdl"

render_tmpl() {
  sed -e "s#{{ \.chezmoi\.homeDir }}#$HOME#g" -e 's#"{{[^}]*}}"#"us"#g' \
      "$ROOT/home/dot_config/niri/config.kdl.tmpl" > "$KDL"
}

# ---- 1. fresh install before chezmoi: missing config.kdl is a clean no-op ------------------------
cat > "$SIDE" <<'EOF'
debug {
    disable-cursor-plane
    disable-direct-scanout
    wait-for-frame-completion-before-queueing
}
EOF
if splice_niri_gpu_block "$KDL" "$SIDE"; then
  _ok "missing config.kdl (pre-chezmoi fresh install) -> clean no-op"
else
  _no "missing config.kdl failed instead of no-op"
fi

# ---- 2. splice into rendered config.kdl.tmpl + real niri validate (when installed) ---------------
render_tmpl
has "$KDL" 'ORCA_IDE_OZONE_PLATFORM "wayland"' "config.kdl.tmpl sets ORCA_IDE_OZONE_PLATFORM=wayland"
has "$KDL" 'numlock'                           "config.kdl.tmpl enables NumLock on session start"
has "$KDL" 'ARCHFRICAN-GPU-START'              "config.kdl.tmpl carries ARCHFRICAN-GPU-START marker"
has "$ROOT/modules/10-gpu.sh"            'nouveau-kms.done' "10-gpu.sh enables early KMS for nouveau (clean GRUB -> Plymouth)"
has "$ROOT/modules/15-desktop-services.sh" 'Numlock=on'     "15-desktop-services.sh enables NumLock in SDDM"
has "$ROOT/modules/15-desktop-services.sh" 'numlock-on=true' "15-desktop-services.sh enables NumLock in Weston greeter"

if splice_niri_gpu_block "$KDL" "$SIDE"; then
  _ok "splice_niri_gpu_block succeeded with nouveau debug sidecar"
else
  _no "splice_niri_gpu_block failed on valid nouveau debug sidecar"
fi
has "$KDL" 'disable-cursor-plane'                     "spliced disable-cursor-plane"
has "$KDL" 'disable-direct-scanout'                   "spliced disable-direct-scanout"
has "$KDL" 'wait-for-frame-completion-before-queueing' "spliced wait-for-frame-completion-before-queueing"

if command -v niri >/dev/null 2>&1; then
  if niri validate -c "$KDL" >/dev/null 2>&1; then
    _ok "spliced config.kdl passes real niri validate"
  else
    _no "spliced config.kdl REJECTED by real niri validate"
  fi
else
  _ok "niri absent (CI) — real validate skipped"
fi

# ---- 3. idempotency: splicing twice keeps exactly one debug block --------------------------------
splice_niri_gpu_block "$KDL" "$SIDE"
cnt="$(grep -cE '^debug \{$' "$KDL")"
if [ "$cnt" = 1 ]; then _ok "idempotent: splicing twice leaves a single debug block"
else _no "idempotent: expected 1 debug block, got $cnt"; fi

# ---- 4. clearing sidecar removes stale debug block cleanly ---------------------------------------
rm -f "$SIDE"
splice_niri_gpu_block "$KDL" "$SIDE"
hasnt "$KDL" 'disable-cursor-plane' "clearing sidecar removes disable-cursor-plane"
has   "$KDL" 'ARCHFRICAN-GPU-START' "clearing sidecar preserves managed markers"

# ---- 5. validate-or-revert: malformed sidecar must roll config.kdl back --------------------------
good="$(cat "$KDL")"
MOCK="$WORK/mockbin"; mkdir -p "$MOCK"
printf '#!/bin/sh\nexit 1\n' > "$MOCK/niri"
chmod +x "$MOCK/niri"
printf 'debug { totally-invalid-directive }\n' > "$SIDE"
if PATH="$MOCK:$PATH" splice_niri_gpu_block "$KDL" "$SIDE"; then
  _no "validate fail: splice_niri_gpu_block should return nonzero"
else
  _ok "validate fail: splice_niri_gpu_block returned nonzero"
fi
if [ "$(cat "$KDL")" = "$good" ]; then
  _ok "validate fail: config.kdl rolled back untouched"
else
  _no "validate fail: config.kdl was NOT reverted"
fi

# ---- 6. converge.sh tracks lib/gpu-niri.sh for 10-gpu --------------------------------------------
REPO_TMP="$WORK/repo"
mkdir -p "$REPO_TMP/lib" "$REPO_TMP/modules"
printf 'echo common\n' > "$REPO_TMP/lib/common.sh"
printf 'echo detect\n' > "$REPO_TMP/lib/detect-gpu.sh"
printf 'echo grub\n'   > "$REPO_TMP/lib/grub.sh"
printf 'echo gpu-niri v1\n' > "$REPO_TMP/lib/gpu-niri.sh"
printf 'echo 10-gpu\n' > "$REPO_TMP/modules/10-gpu.sh"
h1="$(REPO_ROOT="$REPO_TMP" bash -c 'source "'"$ROOT"'/lib/converge.sh"; module_hash 10-gpu')"
printf 'echo gpu-niri v2\n' > "$REPO_TMP/lib/gpu-niri.sh"
h2="$(REPO_ROOT="$REPO_TMP" bash -c 'source "'"$ROOT"'/lib/converge.sh"; module_hash 10-gpu')"
if [ "$h1" != "$h2" ]; then
  _ok "converge.sh: editing lib/gpu-niri.sh changes 10-gpu module_hash"
else
  _no "converge.sh: 10-gpu module_hash ignored lib/gpu-niri.sh"
fi

printf '\ngpu-niri unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
