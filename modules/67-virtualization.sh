#!/usr/bin/env bash
# Phase 2, optional step: native virtualization — KVM/QEMU + libvirt + virt-manager. OPT-IN
# (exit 3 when not selected), same pattern as 65-gaming/25-plasma-desktop/55-multiboot. KVM is the
# Linux-native hypervisor (hardware-accelerated via VT-x/AMD-V — the same tech behind most cloud
# providers); there's no serious "more native/stable/performant" alternative on Linux.
# Re-selectable later:  ~/.archfrican/install.sh 67-virtualization yes
source "$(dirname "$0")/../lib/common.sh"

# Opt-in gate: the wizard arg ("yes"/"no") or ARCHFRICAN_ENABLE_VIRTUALIZATION=1. Exit 3 = not
# selected (no .done stamp, so a later opt-in isn't masked) — the 55-multiboot/65-gaming pattern.
if [ "${1:-no}" != yes ] && [ "${ARCHFRICAN_ENABLE_VIRTUALIZATION:-0}" != 1 ]; then
  ok "virtualization not selected (opt-in: the wizard, ARCHFRICAN_ENABLE_VIRTUALIZATION=1, or install.sh 67-virtualization yes)"
  exit 3
fi

# Hardware check: NON-FATAL (fails open) — VT-x/AMD-V absent (nested VM, old CPU, or disabled in
# firmware) still leaves software emulation, just slow. Warn, don't block the install.
if grep -qE '(vmx|svm)' /proc/cpuinfo; then
  ok "CPU virtualization extensions present (VT-x/AMD-V) — KVM hardware acceleration available"
else
  warn "no vmx/svm CPU flag detected — KVM hardware acceleration unavailable (VMs will be slow, software-only). Check firmware settings if this is unexpected."
fi

substep "installing KVM/QEMU + libvirt + virt-manager"
pac_install_file "$REPO_ROOT/packages/virtualization.txt"

# This repo's firewall is nftables-only (modules/60-security.sh — no iptables/iptables-nft
# anywhere), so libvirt should talk to nftables directly for its own NAT/DHCP rules instead of
# needing an iptables compatibility layer installed just for this. modules/60-security.sh's forward
# chain already scopes `ct state new iifname/oifname "virbr*" accept` for exactly this network
# (virbr0), so no firewall changes are needed here — just point libvirt at the right backend.
substep "configuring libvirt's default network to use the nftables backend directly"
write_system_file /etc/libvirt/network.conf 0644 <<'CONF'
# Managed by modules/67-virtualization.sh. This repo's firewall is nftables-only (no iptables/
# iptables-nft anywhere) — libvirt talks to nftables directly instead of needing that layer.
firewall_backend = "nftables"
CONF

substep "adding you to the libvirt group (manage VMs without sudo every time)"
best_effort sudo usermod -aG libvirt "$USER"

# Unlike most modules (resilient_enable, never --now — see 15-desktop-services.sh), libvirtd isn't
# already providing anything the running install/update session depends on, so starting it now
# (not just enabling it for next boot) is safe — and it's what lets the default NAT network's
# autostart flag get set below, so virt-manager works the FIRST time you open it, not just after
# a reboot.
resilient_enable libvirtd.service
best_effort sudo systemctl start libvirtd.service

substep "starting + autostarting the default NAT network (virbr0 — DHCP/internet access for VMs)"
best_effort sudo virsh net-autostart default
best_effort sudo virsh net-start default

ok "virtualization module done — open virt-manager to create your first VM."
warn "Log out/in for the libvirt group to take effect (or 'sudo virt-manager' meanwhile)."
