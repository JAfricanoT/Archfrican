#!/usr/bin/env bash
# nsswitch_with_mdns — make `.local` names resolvable by glibc, which Avahi alone does NOT do.
#
# Avahi answers DNS-SD browses, but getaddrinfo()/getent only see `.local` hosts when nss-mdns sits
# in the `hosts:` line. Without it CUPS's dnssd:// queues fail with "Unable to locate printer
# \"Foo.local\"" even though `avahi-resolve` finds the device fine — every network printer breaks.
#
# Pure text filter (stdin → stdout) so it is testable without root. Placement follows the Arch Wiki:
# before `resolve` (systemd-resolved would otherwise answer, or time out, first), else before `dns`,
# else appended. `[NOTFOUND=return]` stops a missing .local name from leaking to unicast DNS.
# Idempotent: a `hosts:` line already naming any mdns module is left exactly as it is.
nsswitch_with_mdns() {
  awk '
    !done && /^[[:space:]]*hosts:/ {
      done = 1
      if ($0 ~ /[[:space:]]mdns(4|6)?(_minimal)?([[:space:]]|$)/) { print; next }
      entry = "mdns_minimal [NOTFOUND=return]"
      if (sub(/[[:space:]]resolve([[:space:]]|$)/, " " entry "&")) { print; next }
      if (sub(/[[:space:]]dns([[:space:]]|$)/,     " " entry "&")) { print; next }
      sub(/[[:space:]]+$/, ""); print $0 " " entry; next
    }
    { print }
  '
}
