#!/usr/bin/env bash
# Unit test for lib/nsswitch.sh — nsswitch_with_mdns, the filter that puts nss-mdns in `hosts:`.
# Pure text in/out: no root, no Avahi, runs in CI.
#
# The regression it locks down: Avahi was installed and advertising, `avahi-resolve` found the
# printer, yet glibc could not resolve `Canonb1649f.local` because `hosts:` never named mdns — so
# CUPS's dnssd:// queue sat forever on "Unable to locate printer".
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
# shellcheck source=../../lib/nsswitch.sh
source "$ROOT/lib/nsswitch.sh"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
eq(){ if [ "$1" = "$2" ]; then _ok "$3"; else _no "$3"; printf '       want: %s\n       got:  %s\n' "$2" "$1"; fi; }
hosts_of(){ printf '%s\n' "$1" | nsswitch_with_mdns | grep -m1 '^[[:space:]]*hosts:'; }

# ---- 1. the Arch default (systemd-resolved): mdns goes BEFORE resolve --------------------------
eq "$(hosts_of 'hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns')" \
   'hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns' \
   "inserted before resolve (the Arch default line)"

# ---- 2. no resolved: before dns ------------------------------------------------------------------
eq "$(hosts_of 'hosts: files myhostname dns')" \
   'hosts: files myhostname mdns_minimal [NOTFOUND=return] dns' \
   "inserted before dns when resolve is absent"

# ---- 3. neither: appended, trailing whitespace not doubled ---------------------------------------
eq "$(hosts_of 'hosts: files myhostname   ')" \
   'hosts: files myhostname mdns_minimal [NOTFOUND=return]' \
   "appended when neither resolve nor dns is present"

# ---- 4. idempotent: any mdns flavour already present is left alone --------------------------------
for line in 'hosts: files mdns_minimal [NOTFOUND=return] resolve dns' \
            'hosts: files mdns4_minimal [NOTFOUND=return] dns' \
            'hosts: files mdns dns' \
            'hosts: files dns mdns4'; do
  eq "$(hosts_of "$line")" "$line" "untouched: ${line#hosts: }"
done
once="$(printf 'hosts: files resolve dns\n' | nsswitch_with_mdns)"
eq "$(printf '%s\n' "$once" | nsswitch_with_mdns)" "$once" "running twice == running once"

# ---- 5. word boundaries: `dnsmasq`/`resolver`-like tokens are NOT anchors ------------------------
eq "$(hosts_of 'hosts: files resolver dnsx')" \
   'hosts: files resolver dnsx mdns_minimal [NOTFOUND=return]' \
   "partial-word matches (resolver, dnsx) are not treated as resolve/dns"

# ---- 6. the rest of the file survives byte-for-byte ----------------------------------------------
src=$'# Name Service Switch\npasswd: files systemd\n#hosts: files dns\nhosts: files resolve dns\nnetworks: files\n'
want=$'# Name Service Switch\npasswd: files systemd\n#hosts: files dns\nhosts: files mdns_minimal [NOTFOUND=return] resolve dns\nnetworks: files'
eq "$(printf '%s' "$src" | nsswitch_with_mdns)" "$want" "comments (incl. a commented hosts:) and other databases preserved"

# ---- 7. no hosts: line at all → output identical (caller decides; we never invent one) -----------
src=$'passwd: files\ngroup: files'
eq "$(printf '%s\n' "$src" | nsswitch_with_mdns)" "$src" "file without hosts: passes through unchanged"

printf '\nnsswitch-mdns: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
