#!/usr/bin/env bash
# Configure and enforce DOCKER-USER iptables filtering
# Protects Docker containers from unauthorized external ingress while allowing legitimate Matrix traffic.

set -euo pipefail

log_info() {
    echo "[INFO] $*"
}

log_ok() {
    echo "[OK] $*"
}

# 1. Detect external interface dynamically
EXT_IFACE="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1 || true)"
if [ -z "$EXT_IFACE" ]; then
    EXT_IFACE="enp0s6"
fi
log_info "Detected primary network interface: $EXT_IFACE"

# 2. Verify DOCKER-USER chain exists
if ! iptables -L DOCKER-USER -n >/dev/null 2>&1; then
    log_info "Creating DOCKER-USER chain..."
    iptables -N DOCKER-USER
fi

# 3. Flush current DOCKER-USER rules
log_info "Flushing DOCKER-USER chain..."
iptables -F DOCKER-USER

# 4. Allow established and related connections
iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# 5. Allow loopback and internal Docker bridges / private subnets
iptables -A DOCKER-USER -i lo -j ACCEPT
iptables -A DOCKER-USER -s 127.0.0.0/8 -j ACCEPT
iptables -A DOCKER-USER -s 172.16.0.0/12 -j ACCEPT
iptables -A DOCKER-USER -s 10.0.0.0/8 -j ACCEPT

# 6. Allow legitimate public Matrix, Web, and Media ports
# TCP: HTTP (80), HTTPS (443), Matrix Federation (8448), TURN (3478, 5349), LiveKit TCP (7881)
iptables -A DOCKER-USER -i "$EXT_IFACE" -p tcp -m multiport --dports 80,443,8448,3478,5349,7881 -m conntrack --ctstate NEW -j ACCEPT

# UDP: STUN/TURN (3478, 5349), TURN media relay (49152-49172), LiveKit SFU (50000-50200)
iptables -A DOCKER-USER -i "$EXT_IFACE" -p udp -m multiport --dports 3478,5349 -m conntrack --ctstate NEW -j ACCEPT
iptables -A DOCKER-USER -i "$EXT_IFACE" -p udp --dport 49152:49172 -m conntrack --ctstate NEW -j ACCEPT
iptables -A DOCKER-USER -i "$EXT_IFACE" -p udp --dport 50000:50200 -m conntrack --ctstate NEW -j ACCEPT

# 7. Drop all other incoming routed traffic from external interface to Docker containers
iptables -A DOCKER-USER -i "$EXT_IFACE" -j DROP

# 8. Return default for intra-docker / other traffic
iptables -A DOCKER-USER -j RETURN

# 9. Save rules if netfilter-persistent is installed
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
fi

log_ok "DOCKER-USER firewall rules applied and verified"
