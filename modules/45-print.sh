#!/usr/bin/env bash
# Phase 2, step: printing & scanning — the "just works" expectation. Driverless IPP Everywhere
# (printers) + driverless eSCL/WSD (scanners) via CUPS + SANE, discovered over Avahi/DNS-SD. mDNS
# (5353/udp) is already allowed by the firewall (modules/60-security.sh), so nothing to open here.
source "$(dirname "$0")/../lib/common.sh"

substep "installing printing + scanning (CUPS, SANE, driverless discovery)"
pac_install_file "$REPO_ROOT/packages/print.txt"

substep "enabling the print + discovery daemons"
resilient_enable cups.socket            # socket-activated CUPS (starts on first use)
resilient_enable avahi-daemon.service   # DNS-SD: auto-discovers network printers/scanners
resilient_enable ipp-usb.service        # driverless IPP-over-USB for modern USB printers/MFPs

ok "print module done — add a printer in system-config-printer; scan with simple-scan"
