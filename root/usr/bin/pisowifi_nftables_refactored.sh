#!/bin/sh

CMD=$1
MAC=$2
IP="10.0.0.1"

# --- CONFIGURATION ---
TABLE="pisowifi"
CHAIN_FILTER="pisowifi_filter"
CHAIN_NAT="pisowifi_nat"

# 0. Disable DNS Rebind Protection (Critical for Captive Portals)
# The portal domain usually resolves to a local IP (10.0.0.1) which dnsmasq blocks by default.
uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci commit dhcp
/etc/init.d/dnsmasq reload

# 1. FLUSH EVERYTHING FIRST (Crucial for re-declaring chains)
# We ignore errors here in case table doesn't exist
nft delete table inet $TABLE 2>/dev/null

init() {
    logger -t pisowifi "Initializing nftables rules..."
    
    # Create Table
    nft add table inet $TABLE
    
    # 1. Filter Chain (Forwarding Control)
    # Hook: forward, Priority: -5 (Before OpenWrt default filtering)
    nft add chain inet $TABLE $CHAIN_FILTER { type filter hook forward priority -5 \; policy accept \; }
    
    # 2. NAT Chain (Redirection)
    # Hook: prerouting, Priority: -100 (Before routing)
    nft add chain inet $TABLE $CHAIN_NAT { type nat hook prerouting priority -100 \; }

    # 3. Postrouting (Masquerade)
    # Hook: postrouting, Priority: 100
    nft add chain inet $TABLE postrouting { type nat hook postrouting priority 100 \; }
    # Try generic masquerade for non-lan interfaces
    nft add rule inet $TABLE postrouting ip saddr 10.0.0.0/8 masquerade
    
    # 4. Input Chain (Allow access to Router Services)
    nft add chain inet $TABLE input { type filter hook input priority 0 \; policy accept \; }
    nft add rule inet $TABLE input tcp dport 80 accept
    nft add rule inet $TABLE input udp dport 53 accept
    nft add rule inet $TABLE input udp dport 67-68 accept

    # --- BLOCKING LOGIC ---
    # These rules are for UNauthenticated users (who don't have early return rules)
    
    # 1. Allow DNS/DHCP/Portal Access (Always)
    # This is the *target* of our hijacking, so it must be allowed.
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 53 ip daddr $IP accept
    nft add rule inet $TABLE $CHAIN_FILTER tcp dport 53 ip daddr $IP accept
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 67-68 accept
    nft add rule inet $TABLE $CHAIN_FILTER ip daddr $IP accept
    
    # 2. DNS HIJACKING FOR UNAUTHENTICATED USERS
    # Redirect all DNS queries to local router (10.0.0.1)
    logger -t pisowifi "Adding DNS Hijack rules..."
    nft add rule inet $TABLE $CHAIN_NAT udp dport 53 dnat ip to $IP
    nft add rule inet $TABLE $CHAIN_NAT tcp dport 53 dnat ip to $IP
    
    # 3. Redirect Unauth HTTP to Portal
    # Only redirect traffic destined to port 80 that is NOT going to the portal itself
    logger -t pisowifi "Adding HTTP Redirect rule..."
    nft add rule inet $TABLE $CHAIN_NAT ip daddr != $IP meta l4proto tcp th dport 80 dnat ip to $IP:80
    
    # 4. Force Redirect HTTPS to Portal (or reject)
    # Most modern devices detect captive portal by trying HTTP first.
    # But if they try HTTPS, we should reject it so they fail fast and fallback to HTTP check.
    # ALSO, block QUIC (UDP 443) because Chrome uses it and it bypasses captive portal checks often.
    logger -t pisowifi "Adding HTTPS/QUIC Reject rules..."
    nft add rule inet $TABLE $CHAIN_FILTER tcp dport 443 reject with tcp reset
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 443 reject
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 80 reject
    
    # 5. Block everything else for unauthenticated users
    # This rule sits at the bottom.
    # DROP traffic that is NOT from authenticated users (who return early)
    logger -t pisowifi "Adding final DROP rule for unauth users..."
    nft add rule inet $TABLE $CHAIN_FILTER drop
    
    logger -t pisowifi "Firewall initialization complete."
}

allow() {
    [ -z "$MAC" ] && return
    
    logger -t pisowifi "Allowing MAC: $MAC"
    
    # Check if table/chain exists before listing
    nft list table inet $TABLE >/dev/null 2>&1 || init
    
    # Check if rule already exists (case insensitive) to prevent duplicates
    if nft list chain inet $TABLE $CHAIN_FILTER | grep -i -q "$MAC"; then
        logger -t pisowifi "MAC $MAC already allowed, skipping."
        return 0
    fi
    
    # Insert rule at TOP to bypass the drop rule and all hijacking
    # This ensures authenticated users have full access.
    logger -t pisowifi "Inserting allow rules for $MAC at top of filter chain..."
    nft insert rule inet $TABLE $CHAIN_FILTER ether saddr $MAC accept
    nft insert rule inet $TABLE $CHAIN_FILTER ether daddr $MAC accept
    
    # Insert rule at TOP to bypass redirect in NAT chain
    logger -t pisowifi "Inserting NAT bypass for $MAC..."
    nft insert rule inet $TABLE $CHAIN_NAT ether saddr $MAC return
    
    # Also explicitly masquerade outgoing traffic for this MAC in our own table
    # This ensures that even if fw4 fails to masquerade, we do it.
    logger -t pisowifi "Adding masquerade rule for $MAC..."
    local IP_ADDR=$(grep -i "$MAC" /proc/net/arp | awk '{print $1}')
    if [ -n "$IP_ADDR" ]; then
        nft insert rule inet $TABLE postrouting ip saddr $IP_ADDR masquerade
        logger -t pisowifi "Masquerade rule added for IP $IP_ADDR (MAC: $MAC)."
    else
        logger -t pisowifi "Could not find IP for MAC $MAC in ARP table for masquerade."
    fi
    
    # FORCE AUTHENTICATED USERS TO USE 8.8.8.8 (Google DNS)
    # We DNAT their DNS queries to 8.8.8.8
    logger -t pisowifi "Forcing DNS to 8.8.8.8 for $MAC..."
    # This gets inserted at the very top (index 0), pushing the 'return' rule down to index 1.
    nft insert rule inet $TABLE $CHAIN_NAT udp dport 53 ether saddr $MAC dnat ip to 8.8.8.8
    nft insert rule inet $TABLE $CHAIN_NAT tcp dport 53 ether saddr $MAC dnat ip to 8.8.8.8
    
    # EXPLICITLY ALLOW LAN TO WAN FORWARDING IN FW4 (OpenWrt default firewall)
    # This is a fallback to ensure traffic isn't dropped by the main firewall
    logger -t pisowifi "Adding fallback allow rule in fw4 for $MAC..."
    nft insert rule inet fw4 forward ether saddr $MAC accept 2>/dev/null || logger -t pisowifi "Failed to add fw4 rule for $MAC (might not exist)."
    
    logger -t pisowifi "Allow process complete for MAC: $MAC"
}

deny() {
    [ -z "$MAC" ] && return
    
    logger -t pisowifi "Denying MAC: $MAC"
    
    # Check if table/chain exists before listing
    nft list table inet $TABLE >/dev/null 2>&1 || return
    
    # Get handles for rules involving this MAC and delete them
    logger -t pisowifi "Removing rules for MAC: $MAC..."
    # Filter Chain
    HANDLES=$(nft -a list chain inet $TABLE $CHAIN_FILTER | grep "$MAC" | awk '{print $NF}')
    for h in $HANDLES; do 
        logger -t pisowifi "Deleting filter rule handle $h for $MAC"
        nft delete rule inet $TABLE $CHAIN_FILTER handle $h
    done
    
    # NAT Chain
    HANDLES=$(nft -a list chain inet $TABLE $CHAIN_NAT | grep "$MAC" | awk '{print $NF}')
    for h in $HANDLES; do 
        logger -t pisowifi "Deleting NAT rule handle $h for $MAC"
        nft delete rule inet $TABLE $CHAIN_NAT handle $h
    done
    
    # Postrouting Chain (Masquerade)
    HANDLES=$(nft -a list chain inet $TABLE postrouting | grep "$MAC" | awk '{print $NF}')
    for h in $HANDLES; do 
        logger -t pisowifi "Deleting postrouting rule handle $h for $MAC"
        nft delete rule inet $TABLE postrouting handle $h
    done
    
    logger -t pisowifi "Deny process complete for MAC: $MAC"
}

case "$CMD" in
    init) init ;;
    allow) allow ;;
    deny) deny ;;
    list) 
        echo "=== Current nftables rules ==="
        nft list table inet $TABLE 2>/dev/null || echo "Table $TABLE not found"
        ;;
esac