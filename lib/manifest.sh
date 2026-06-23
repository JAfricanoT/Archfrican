#!/usr/bin/env bash
# Desired-state manifest + managed ledger — the basis for SAFE pruning. Two files under
# $ARCHFRICAN_STATE_DIR (root-owned):
#   manifest.txt  the package set Archfrican DECLARES it wants right now (union of the applicable
#                 packages/*.txt, opt-ins included only when chosen). Rewritten every converge.
#   managed.txt   the cumulative (append-only) union of everything Archfrican has EVER declared —
#                 "ours". A package you installed by hand is never in here, so it can never be a
#                 prune candidate.
# Prune candidate = explicitly-installed (pacman -Qe) ∩ managed.txt − manifest.txt − has-dependents.
# Sourced (never executed) by install.sh (write_manifest, in converge) + bin/archfrican-update
# (prune_candidates). Needs REPO_ROOT + read_pkg_list/ok (lib/common.sh).

ARCHFRICAN_STATE_DIR="${ARCHFRICAN_STATE_DIR:-/var/lib/archfrican}"
ARCHFRICAN_MANIFEST="$ARCHFRICAN_STATE_DIR/manifest.txt"
ARCHFRICAN_MANAGED="$ARCHFRICAN_STATE_DIR/managed.txt"

# The package lists that apply, given the run's opt-in choices. The always-on layers plus the
# opt-in ones only when enabled. (GPU/snapshots/hygiene declare no list — their packages are
# computed and intentionally NOT prune-managed, so a needed driver is never a removal candidate.)
_manifest_lists() {               # _manifest_lists <multiboot yes|no>
  printf '%s\n' base niri-desktop dev theming security aur
  [ "${1:-no}" = yes ] && printf '%s\n' multiboot
}

# Write manifest.txt (current desired set) + fold it into managed.txt (cumulative). Called at the
# end of every converge so drift/prune always reflect the latest applied state.
write_manifest() {                # write_manifest <multiboot yes|no>
  local mb="${1:-no}" l pkgs tmp
  tmp="$(mktemp)"
  while IFS= read -r l; do
    [ -r "$REPO_ROOT/packages/$l.txt" ] || continue
    read_pkg_list "$REPO_ROOT/packages/$l.txt" pkgs
    printf '%s\n' "${pkgs[@]}"
  done < <(_manifest_lists "$mb") | LC_ALL=C sort -u > "$tmp"
  sudo install -d -m 0755 "$ARCHFRICAN_STATE_DIR"
  sudo install -m 0644 "$tmp" "$ARCHFRICAN_MANIFEST"
  { sudo cat "$ARCHFRICAN_MANAGED" 2>/dev/null; cat "$tmp"; } | LC_ALL=C sort -u | sudo tee "$ARCHFRICAN_MANAGED" >/dev/null
  rm -f "$tmp"
  ok "recorded desired-state manifest ($(grep -c . "$ARCHFRICAN_MANIFEST") pkgs) + managed ledger"
}

# Packages that ARE Archfrican-managed, still explicitly installed, but no longer desired and not
# depended upon. Prints one per line (empty if none / no manifest yet). Read-only.
prune_candidates() {
  [ -r "$ARCHFRICAN_MANAGED" ] && [ -r "$ARCHFRICAN_MANIFEST" ] || return 0
  command -v pacman >/dev/null 2>&1 || return 0
  local p reqby
  # explicit installs that are NOT in the desired manifest … (LC_ALL=C so both inputs collate identically;
  # a mismatched collation could make comm mis-pair and skip/keep the wrong package)
  comm -23 <(pacman -Qeq 2>/dev/null | LC_ALL=C sort -u) <(LC_ALL=C sort -u "$ARCHFRICAN_MANIFEST") | while IFS= read -r p; do
    grep -qxF "$p" "$ARCHFRICAN_MANAGED" || continue          # … only if Archfrican ever declared it
    reqby="$(pacman -Qi "$p" 2>/dev/null | awk -F': *' '/^Required By/{print $2; exit}')"
    [ "$reqby" = "None" ] || continue                          # … and nothing still depends on it
    printf '%s\n' "$p"
  done
}
