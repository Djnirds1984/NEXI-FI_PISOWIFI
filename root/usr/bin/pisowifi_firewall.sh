#!/bin/sh

CMD=$1
MAC=$2
IP="10.0.0.1"
IFACE="br-lan"

init() {
    # CLEANUP
    iptables -D FORWARD -j PISOWIFI_AUTH 2>/dev/null
    iptables -F PISOWIFI_AUTH 2>/dev/null
    iptables -X PISOWIFI_AUTH 2>/dev/null

    iptables -t nat -D PREROUTING -j PISOWIFI_NAT 2>/dev/null
    iptables -t nat -F PISOWIFI_NAT 2>/dev/null
    iptables -t nat -X PISOWIFI_NAT 2>/dev/null

    # FILTER CHAIN (Controls Access)
    iptables -N PISOWIFI_AUTH
    iptables -I FORWARD -j PISOWIFI_AUTH
    
    # Allow DNS (Critical for Captive Portal Detection)
    iptables -A PISOWIFI_AUTH -p udp --dport 53 -j ACCEPT
    iptables -A PISOWIFI_AUTH -p tcp --dport 53 -j ACCEPT
    
    # Allow DHCP
    iptables -A PISOWIFI_AUTH -p udp --dport 67:68 -j ACCEPT
    
    # NAT CHAIN (Redirects HTTP)
    iptables -t nat -N PISOWIFI_NAT
    # Only intercept LAN traffic
    iptables -t nat -I PREROUTING -i $IFACE -j PISOWIFI_NAT
    
    # Redirect HTTP (80) to Captive Portal
    # Authenticated users will RETURN before this rule
    iptables -t nat -A PISOWIFI_NAT -p tcp --dport 80 -j DNAT --to-destination $IP:80
    
    # Block everything else in FORWARD for unauthenticated
    # Authenticated users will ACCEPT before this rule
    iptables -A PISOWIFI_AUTH -j DROP
}

allow() {
    [ -z "$MAC" ] && return
    # Insert at top to bypass blocking/redirect
    iptables -I PISOWIFI_AUTH 1 -m mac --mac-source $MAC -j ACCEPT
    iptables -t nat -I PISOWIFI_NAT 1 -m mac --mac-source $MAC -j RETURN
}

deny() {
    [ -z "$MAC" ] && return
    iptables -D PISOWIFI_AUTH -m mac --mac-source $MAC -j ACCEPT 2>/dev/null
    iptables -t nat -D PISOWIFI_NAT -m mac --mac-source $MAC -j RETURN 2>/dev/null
}

case "$CMD" in
    init) init ;;
    allow) allow ;;
    deny) deny ;;
esac
