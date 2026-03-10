#!/bin/sh

CMD=$1
MAC=$2
IP="10.0.0.1"

# --- CONFIGURATION ---
TABLE="pisowifi"
CHAIN_FILTER="pisowifi_filter"
CHAIN_NAT="pisowifi_nat"

init() {
    # 0. Disable DNS Rebind Protection (Critical for Captive Portals)
    # The portal domain usually resolves to a local IP (10.0.0.1) which dnsmasq blocks by default.
    # We only do this on INIT to avoid reloading dnsmasq on every client connect.
    uci set dhcp.@dnsmasq[0].rebind_protection='0'
    uci commit dhcp
    /etc/init.d/dnsmasq reload

    # 1. FLUSH EVERYTHING FIRST (Crucial for re-declaring chains)
    # We ignore errors here in case table doesn't exist
    nft delete table inet $TABLE 2>/dev/null
    
    # 2. Check and Create Table (if missing)
    # The 'add table' command is idempotent in nftables (it won't error if exists),
    # BUT if we flushed it before, we must ensure it's created properly.
    nft add table inet $TABLE
    
    # 3. Filter Chain (Forwarding Control)
    # Hook: forward, Priority: -5 (Before OpenWrt default filtering)
    nft add chain inet $TABLE $CHAIN_FILTER { type filter hook forward priority -5 \; policy accept \; }
    
    # Allow established/related traffic globally in this chain
    # This is CRITICAL: It allows return traffic from the internet back to the client.
    # Without this, "ether daddr" matching fails for routed traffic (NAT).
    nft add rule inet $TABLE $CHAIN_FILTER ct state established,related accept
    
    # 4. NAT Chain (Redirection)
    # Hook: prerouting, Priority: -100 (Before routing)
    nft add chain inet $TABLE $CHAIN_NAT { type nat hook prerouting priority -100 \; }

    # 5. Postrouting (Masquerade)
    # Hook: postrouting, Priority: 100
    nft add chain inet $TABLE postrouting { type nat hook postrouting priority 100 \; }
    # Try generic masquerade for non-lan interfaces
    # Simpler: just masquerade everything leaving the WAN/Uplink
    # If we don't know the WAN name, we can masquerade everything NOT going to LAN.
    nft add rule inet $TABLE postrouting ip saddr 10.0.0.0/8 masquerade
    
    # 6. Input Chain (Allow access to Router Services)
    # We need to explicitly allow traffic to 10.0.0.1:80 (Portal) and 53 (DNS)
    nft add chain inet $TABLE input { type filter hook input priority 0 \; policy accept \; }
    nft add rule inet $TABLE input tcp dport 80 accept
    nft add rule inet $TABLE input udp dport 53 accept
    nft add rule inet $TABLE input udp dport 67-68 accept

    # --- BLOCKING LOGIC ---
    # Allow DHCP (Always)
    # NOTE: We ONLY allow local services here. External access is BLOCKED by default below.
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 67-68 accept
    nft add rule inet $TABLE $CHAIN_FILTER ip daddr $IP accept
    
    # DNS HIJACKING (For Unauthenticated Users)
    # Redirect all DNS queries (UDP/TCP 53) to the local router (10.0.0.1)
    # This prevents users from using 8.8.8.8 until they are authenticated.
    nft add rule inet $TABLE $CHAIN_NAT udp dport 53 dnat ip to $IP
    nft add rule inet $TABLE $CHAIN_NAT tcp dport 53 dnat ip to $IP
    
    # Redirect Unauth HTTP to Portal
    nft add rule inet $TABLE $CHAIN_NAT tcp dport 80 dnat ip to $IP:80
    
    # Block everything else for unauthenticated users
    # We add a rule at the BOTTOM of the filter chain to DROP everything
    # Authenticated users will have rules inserted ABOVE this.
    nft add rule inet $TABLE $CHAIN_FILTER drop
}

allow() {
    [ -z "$MAC" ] && return
    
    # Check if table/chain exists before listing
    nft list table inet $TABLE >/dev/null 2>&1 || init
    
    # Insert rule at TOP to bypass the drop rule
    # Using 'accept' instead of 'return' to force permit immediately
    nft insert rule inet $TABLE $CHAIN_FILTER ether saddr $MAC accept
    
    # Insert rule at TOP to bypass redirect
    nft insert rule inet $TABLE $CHAIN_NAT ether saddr $MAC return
}

deny() {
    [ -z "$MAC" ] && return
    
    # Check if table/chain exists before listing
    nft list table inet $TABLE >/dev/null 2>&1 || return
    
    # Get handles for rules involving this MAC and delete them
    # Filter Chain
    HANDLES=$(nft -a list chain inet $TABLE $CHAIN_FILTER | grep "$MAC" | awk '{print $NF}')
    for h in $HANDLES; do nft delete rule inet $TABLE $CHAIN_FILTER handle $h; done
    
    # NAT Chain
    HANDLES=$(nft -a list chain inet $TABLE $CHAIN_NAT | grep "$MAC" | awk '{print $NF}')
    for h in $HANDLES; do nft delete rule inet $TABLE $CHAIN_NAT handle $h; done
}

case "$CMD" in
    init) init ;;
    allow) allow ;;
    deny) deny ;;
esac
