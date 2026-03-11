#!/bin/sh

CMD=$1
MAC=$2
IP="10.0.0.1"

# --- CONFIGURATION ---
TABLE="pisowifi"
CHAIN_FILTER="pisowifi_filter"
CHAIN_NAT="pisowifi_nat"

init() {
    # 1. FLUSH EVERYTHING
    nft delete table inet $TABLE 2>/dev/null
    
    # 2. Create Table (So the CGI script doesn't keep trying to init)
    nft add table inet $TABLE
    
    # 3. Create Chains with ACCEPT Policy (OPEN INTERNET)
    # We explicitly set policy to accept so traffic flows freely.
    nft add chain inet $TABLE $CHAIN_FILTER { type filter hook forward priority -5 \; policy accept \; }
    nft add chain inet $TABLE $CHAIN_NAT { type nat hook prerouting priority -100 \; }
    nft add chain inet $TABLE input { type filter hook input priority 0 \; policy accept \; }
    
    # 4. Masquerade (NAT) - Keep this just in case it's needed for connectivity
    nft add chain inet $TABLE postrouting { type nat hook postrouting priority 100 \; }
    nft add rule inet $TABLE postrouting ip saddr 10.0.0.0/8 masquerade
    
    # --- NO BLOCKING RULES ---
    # --- NO REDIRECT RULES ---
    # --- NO DNS HIJACKING ---
    # The system is now completely open.
}

allow() {
    # No-op in open mode
    return 0
}

deny() {
    # No-op in open mode
    return 0
}

case "$CMD" in
    init) init ;;
    allow) allow ;;
    deny) deny ;;
esac
