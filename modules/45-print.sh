#!/usr/bin/env bash
# Phase 2, step: printing & scanning — the "just works" expectation. Driverless IPP Everywhere
# (printers) + driverless eSCL/WSD (scanners) via CUPS + SANE, discovered over Avahi/DNS-SD. mDNS
# (5353/udp) is already allowed by the firewall (modules/60-security.sh), so nothing to open here.
source "$(dirname "$0")/../lib/common.sh"
source "$REPO_ROOT/lib/nsswitch.sh"

substep "installing printing + scanning (CUPS, SANE, driverless discovery)"
pac_install_file "$REPO_ROOT/packages/print.txt"

substep "enabling the print + discovery daemons"
resilient_enable cups.socket            # socket-activated CUPS (starts on first use)
resilient_enable avahi-daemon.service   # DNS-SD: auto-discovers network printers/scanners
resilient_enable ipp-usb.service        # driverless IPP-over-USB for modern USB printers/MFPs

# Avahi discovers `Foo.local`, but glibc can't RESOLVE it until nss-mdns is in `hosts:` — without
# this every dnssd:// queue fails with "Unable to locate printer". See lib/nsswitch.sh.
substep "letting the system resolve .local hosts (nss-mdns)"
_nss_new="$(mktemp)"
nsswitch_with_mdns < /etc/nsswitch.conf > "$_nss_new"
if ! grep -q '^[[:space:]]*hosts:' "$_nss_new"; then
  warn "/etc/nsswitch.conf has no hosts: line — .local printers won't resolve; add mdns_minimal by hand"
elif cmp -s /etc/nsswitch.conf "$_nss_new"; then
  ok "nsswitch already resolves .local"
else
  sudo install -m 0644 "$_nss_new" /etc/nsswitch.conf
  ok "nsswitch: $(grep -m1 '^[[:space:]]*hosts:' /etc/nsswitch.conf)"
fi
rm -f "$_nss_new"


ok "print module done — add a printer in system-config-printer; scan with simple-scan"
