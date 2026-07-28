#!/usr/bin/env bash
# Unit test for bin/archfrican-multicast-route — the NetworkManager dispatcher helper that pins
# 224.0.0.0/4 to the LAN interface so LAN discovery (LocalSend 224.0.0.167, mDNS 224.0.0.251,
# SSDP 239.255.255.250) is not swallowed by a full-tunnel VPN's policy routing.
# Fixture-based: stubs `ip` on PATH and asserts on the recorded argv, so it needs NO root, NO VPN
# and NO real interfaces, and runs in CI.
#
# The regression it locks down: with Mullvad connected, `ip route get 224.0.0.167` resolved to
# `dev wg0-mullvad`, so every multicast announcement left through the tunnel with the tunnel's
# source address and no LAN peer ever saw this box.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SUT="$ROOT/bin/archfrican-multicast-route"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export IP_LOG="$TMP/ip.log"

# ---- stub `ip` -----------------------------------------------------------------------------------
# Records every invocation, and answers `route show default dev <if>` for the two fixture uplinks:
# enp3s0 carries an explicit metric, wlan0 deliberately carries none (metric-less default routes are
# real — the helper must fall back instead of emitting a garbage `metric` argument).
cat > "$TMP/ip" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$IP_LOG"
case "$*" in
  "-4 route show default dev enp3s0")
    echo "default via 192.168.1.1 dev enp3s0 proto dhcp src 192.168.1.108 metric 100" ;;
  "-4 route show default dev wlan0")
    echo "default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.77" ;;
  # Any other device has no default route: `ip route show` prints nothing and still exits 0.
esac
exit 0
STUB
chmod +x "$TMP/ip"
export PATH="$TMP:$PATH"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }
run(){ : > "$IP_LOG"; bash "$SUT" "$@" >/dev/null 2>&1; }
logged(){    if grep -qF "$1" "$IP_LOG"; then _ok "$2"; else _no "$2 (not in ip log: $(tr '\n' '|' < "$IP_LOG"))"; fi; }
notlogged(){ if grep -qF "$1" "$IP_LOG"; then _no "$2 (unexpectedly ran: $1)"; else _ok "$2"; fi; }

# ---- 1. the fix itself: a LAN uplink gets 224.0.0.0/4 pinned to it, in `main` ---------------------
# `table main` is the whole point: a VPN's `suppress_prefixlength 0` rule hides only DEFAULT routes
# from the main lookup, so a /4 there wins over the VPN table.
run enp3s0 up
logged 'route replace 224.0.0.0/4 dev enp3s0 table main metric 100' "pins 224.0.0.0/4 to the LAN uplink in table main"
logged 'route del 224.0.0.0/4 dev enp3s0 table main'                "clears a stale route first (idempotent re-runs)"

# The metric mirrors the interface's own default-route metric, so with Ethernet AND Wi-Fi up
# multicast follows the same uplink NetworkManager already prefers.
run wlan0 up
logged 'route replace 224.0.0.0/4 dev wlan0 table main metric 1000' "falls back to metric 1000 when the default route has none"

# ---- 2. never a tunnel or a container/VM bridge ---------------------------------------------------
# Pinning multicast to the tunnel is the bug; pinning it to docker0/virbr0 is the LAN-visible
# equivalent (announcements would leave on a bridge no peer is on).
for dev in wg0-mullvad tun0 tailscale0 nordlynx proton0 docker0 podman0 virbr0 br-ea7110454990 veth4ed6dd8 lo; do
  run "$dev" up
  notlogged 'route replace' "skips $dev (never a tunnel or a container/VM bridge)"
done

# ---- 3. only uplinks, only real actions -----------------------------------------------------------
run eno1 up                                     # a physical NIC with no default route (unplugged)
notlogged 'route replace' "skips a LAN interface that carries no default route"
run enp3s0 pre-up
notlogged 'route replace' "ignores dispatcher actions other than up/dhcp4-change/down"
run enp3s0 dhcp4-change
logged 'route replace 224.0.0.0/4 dev enp3s0 table main metric 100' "re-pins on dhcp4-change (lease renewal keeps the route)"

# ---- 4. down removes only this interface's route ---------------------------------------------------
run enp3s0 down
logged 'route del 224.0.0.0/4 dev enp3s0 table main' "removes the route when the interface goes down"
notlogged 'route replace' "down never re-adds the route"

# ---- 5. never invoked without an interface ---------------------------------------------------------
run "" up
notlogged 'route' "no interface argument is a no-op"

printf '\narchfrican-multicast-route unit test: %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
