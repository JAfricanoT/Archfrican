#!/usr/bin/env bash
# Phase 2, step: printing & scanning — the "just works" expectation. Driverless IPP Everywhere
# (printers) + driverless eSCL/WSD (scanners) via CUPS + SANE, discovered over Avahi/DNS-SD. mDNS
# (5353/udp) is already allowed by the firewall (modules/60-security.sh), so nothing to open here.
# Host-based printers with no IPP at all get their vendor driver from pkgbuilds/print/ (see below).
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

# Vendor drivers for host-based printers, as local PKGBUILDs that repackage the vendor's own binaries:
# the AUR equivalents compile decade-old C that modern GCC rejects. makepkg -s pulls their deps.
# Non-fatal — a missing vendor driver must not abort the install.
substep "installing vendor drivers for host-based printers (pkgbuilds/print, non-fatal)"
for _pb in "$REPO_ROOT"/pkgbuilds/print/*/PKGBUILD; do
  _name="$(basename "$(dirname "$_pb")")"
  if pacman -Q "$_name" &>/dev/null; then ok "$_name already installed"; continue; fi
  _build="$(mktemp -d)"; cp "$_pb" "$_build/"
  if (cd "$_build" && with_heartbeat "empaquetando $_name" timeout 900 makepkg -si --needed --noconfirm); then
    ok "$_name installed"
  else
    warn "vendor driver $_name did not install (continuing) — retry: cd pkgbuilds/print/$_name && makepkg -si"
  fi
  rm -rf "$_build"
done

ok "print module done — add a printer in system-config-printer; scan with simple-scan"
