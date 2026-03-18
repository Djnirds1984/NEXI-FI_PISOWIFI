#!/bin/sh

echo "=== INSTALLING PISOWIFI (CGI VERSION) ==="

# 1. Ensure Firewall Script is Present
# Force overwrite to ensure fixes are applied
echo "Creating Firewall Script..."
cat << 'EOF' > /usr/bin/pisowifi_nftables.sh
#!/bin/sh

CMD=$1
MAC=$2
IP_ARG=$3
IP="10.0.0.1"

# --- CONFIGURATION ---
TABLE="pisowifi"
CHAIN_FILTER="pisowifi_filter"
CHAIN_NAT="pisowifi_nat"

# 0. Disable DNS Rebind Protection (Critical for Captive Portals)
    # Only if not already set
    REBIND=$(uci get dhcp.@dnsmasq[0].rebind_protection 2>/dev/null)
    if [ "$REBIND" != "0" ]; then
        uci set dhcp.@dnsmasq[0].rebind_protection='0'
        uci commit dhcp
        /etc/init.d/dnsmasq reload
    fi

init() {
    logger -t pisowifi "Initializing nftables rules..."
    
    # Clean up old table
    nft delete table inet $TABLE 2>/dev/null
    
    # Create Table
    nft add table inet $TABLE
    
    # 1. Filter Chain (Forwarding Control)
    # Hook: forward, Priority: -5 (Before fw4)
    nft add chain inet $TABLE $CHAIN_FILTER { type filter hook forward priority -5 \; policy accept \; }
    
    # 2. NAT Chain (Redirection)
    # Hook: prerouting, Priority: -100 (Before routing)
    nft add chain inet $TABLE $CHAIN_NAT { type nat hook prerouting priority -100 \; }

    # 3. Postrouting (Masquerade)
    # Hook: postrouting, Priority: 100
    nft add chain inet $TABLE postrouting { type nat hook postrouting priority 100 \; }
    
    # GLOBAL MASQUERADE - CRITICAL FOR INTERNET ACCESS
    # Ensure 10.0.0.0/8 traffic is NAT'd when leaving
    nft add rule inet $TABLE postrouting ip saddr 10.0.0.0/8 masquerade
    
    # 4. Input Chain (Allow access to Router Services)
    nft add chain inet $TABLE input { type filter hook input priority 0 \; policy accept \; }
    nft add rule inet $TABLE input tcp dport 80 accept
    nft add rule inet $TABLE input udp dport 53 accept
    nft add rule inet $TABLE input udp dport 67-68 accept
    
    # FW4/Firewall Zone Forwarding
    # Ensure LAN zone allows forwarding (Critical for OpenWrt)
    uci set firewall.@zone[0].forward='ACCEPT' 2>/dev/null || true
    # Disable Flow Offloading (Can bypass captive portal rules)
    uci set firewall.@defaults[0].flow_offloading='0' 2>/dev/null || true
    uci commit firewall 2>/dev/null || true
    /etc/init.d/firewall reload 2>/dev/null || true

    # --- BLOCKING LOGIC (Bottom of Chain) ---
    
    # 1. Allow DNS/DHCP/Portal Access to Router
    # Add rules only if not exists (prevent duplicates on reload)
    # Actually, init flushes table so no need to check
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 53 ip daddr $IP accept
    nft add rule inet $TABLE $CHAIN_FILTER tcp dport 53 ip daddr $IP accept
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 67-68 accept
    nft add rule inet $TABLE $CHAIN_FILTER ip daddr $IP accept
    
    # 2. DNS HIJACKING (Unauth -> 10.0.0.1)
    nft add rule inet $TABLE $CHAIN_NAT udp dport 53 dnat ip to $IP
    nft add rule inet $TABLE $CHAIN_NAT tcp dport 53 dnat ip to $IP
    
    # 3. Redirect HTTP to Portal
    nft add rule inet $TABLE $CHAIN_NAT ip daddr != $IP meta l4proto tcp th dport 80 dnat ip to $IP:80
    
    # 4. Reject HTTPS/QUIC (Force them to use HTTP or fail fast)
    nft add rule inet $TABLE $CHAIN_FILTER tcp dport 443 reject with tcp reset
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 443 reject
    nft add rule inet $TABLE $CHAIN_FILTER udp dport 80 reject
    
    # 5. Drop everything else for unauth users
    # This prevents unauthenticated users from reaching WAN
    nft add rule inet $TABLE $CHAIN_FILTER drop
    
    # 6. FW4 Compatibility (Try to insert a rule into fw4 forward chain just in case)
    # Check if rule exists before inserting to avoid duplicates/errors
    if nft list chain inet fw4 forward 2>/dev/null | grep -q "10.0.0.0/8"; then
        true
    else
        nft insert rule inet fw4 forward ip saddr 10.0.0.0/8 accept 2>/dev/null || true
    fi
    # Also try 'firewall' table (older OpenWrt)
    if nft list chain inet firewall forward 2>/dev/null | grep -q "10.0.0.0/8"; then
        true
    else
        nft insert rule inet firewall forward ip saddr 10.0.0.0/8 accept 2>/dev/null || true
    fi
    
    logger -t pisowifi "Firewall initialization complete."
}

reload_qos() {
    # Called when QoS settings change
    logger -t pisowifi "Reloading QoS settings..."
    
    # Get active users
    DB_FILE="/etc/pisowifi/pisowifi.db"
    NOW=$(date +%s)
    
    # Re-allow active users (this will apply new limits)
    sqlite3 $DB_FILE "SELECT mac, ip FROM users WHERE session_end > $NOW AND paused_time = 0" 2>/dev/null | while read line; do
        MAC=$(echo "$line" | cut -d'|' -f1)
        IP=$(echo "$line" | cut -d'|' -f2)
        allow "$MAC" "$IP"
    done
}

allow() {
    [ -z "$MAC" ] && return
    
    logger -t pisowifi "Allowing MAC: $MAC IP: $IP_ARG"
    
    # Check if table exists
    if ! nft list tables | grep -q "$TABLE"; then
        init
    fi
    
    # CLEAN UP FIRST (Force fresh rules for this user)
    # This ensures we don't have stale rules causing loops or conflicts.
    deny "$MAC"
    
    # --- INSERT RULES AT THE TOP (Unique per User) ---
    # We use 'insert' (index 0)
    
    # We tag rules with comment "MAC:$MAC" so we can find/delete them later
    
    # 1. IP-BASED ALLOW (Primary Reliability Layer)
    if [ -n "$IP_ARG" ]; then
        # NAT Bypass (Portal Bypass)
        nft insert rule inet $TABLE $CHAIN_NAT ip saddr $IP_ARG return comment \"MAC:$MAC\"
        
        # Filter Accept (Internet Access - BOTH DIRECTIONS)
        # Apply QoS if Per-User Mode is enabled
        QOS_MODE=$(uci get pisowifi.qos.mode 2>/dev/null || echo "global")
        
        if [ "$QOS_MODE" = "per_user" ]; then
             USER_DOWN=$(uci get pisowifi.qos.user_down 2>/dev/null || echo 0)
             USER_UP=$(uci get pisowifi.qos.user_up 2>/dev/null || echo 0)
             
             # Convert Mbps to Bytes/sec roughly for NFT limit
             # 1 Mbps = 125,000 bytes/sec
             [ "$USER_DOWN" -gt 0 ] && LIMIT_DOWN="limit rate $((USER_DOWN * 125)) kbytes/second burst 100 kbytes"
             [ "$USER_UP" -gt 0 ] && LIMIT_UP="limit rate $((USER_UP * 125)) kbytes/second burst 100 kbytes"
             
             # Apply Limits
             if [ -n "$LIMIT_UP" ]; then
                 nft insert rule inet $TABLE $CHAIN_FILTER ip saddr $IP_ARG $LIMIT_UP accept comment \"MAC:$MAC\"
             else
                 nft insert rule inet $TABLE $CHAIN_FILTER ip saddr $IP_ARG accept comment \"MAC:$MAC\"
             fi
             
             if [ -n "$LIMIT_DOWN" ]; then
                 nft insert rule inet $TABLE $CHAIN_FILTER ip daddr $IP_ARG $LIMIT_DOWN accept comment \"MAC:$MAC\"
             else
                 nft insert rule inet $TABLE $CHAIN_FILTER ip daddr $IP_ARG accept comment \"MAC:$MAC\"
             fi
        else
             # No per-user limit, just accept
             nft insert rule inet $TABLE $CHAIN_FILTER ip saddr $IP_ARG accept comment \"MAC:$MAC\"
             nft insert rule inet $TABLE $CHAIN_FILTER ip daddr $IP_ARG accept comment \"MAC:$MAC\"
        fi
        
        # Masquerade (Specific - ensure NAT works)
        nft insert rule inet $TABLE postrouting ip saddr $IP_ARG masquerade comment \"MAC:$MAC\"
        
        # FW4/Firewall Forwarding (External Tables) - CRITICAL
    # We must allow BOTH directions for forwarding to work properly
    # Apply QoS limits here too if possible? 
    # No, fw4 rules are harder to manage dynamically with complex matches in simple inserts.
    # We rely on our CHAIN_FILTER which has higher priority (-5) than fw4.
    # So if our chain accepts with limit, fw4 won't even see it? 
    # Wait, if we ACCEPT in priority -5, it stops traversing? Yes.
    # So we don't need fw4 rules if our chain works.
    # But just in case, we add simple accept to fw4 as backup (without limits).
    # This might bypass QoS if our chain is skipped?
    # Actually, if we accept in -5, fw4 (priority 0) is skipped.
    # So QoS WORKS in our chain.
    
    nft insert rule inet fw4 forward ip saddr $IP_ARG accept comment \"MAC:$MAC\" 2>/dev/null || true
    nft insert rule inet fw4 forward ip daddr $IP_ARG accept comment \"MAC:$MAC\" 2>/dev/null || true
    nft insert rule inet firewall forward ip saddr $IP_ARG accept comment \"MAC:$MAC\" 2>/dev/null || true
    nft insert rule inet firewall forward ip daddr $IP_ARG accept comment \"MAC:$MAC\" 2>/dev/null || true
    fi

    # 2. MAC-BASED ALLOW (Secondary/Roaming Layer)
    # NAT Bypass
    nft insert rule inet $TABLE $CHAIN_NAT ether saddr $MAC return comment \"MAC:$MAC\"
    
    # DNS: STOP HIJACKING (Most Reliable for "No Internet" complaints)
    # We explicitly RETURN (accept) DNS traffic for allowed users.
    # This means they can use 8.8.8.8, 10.0.0.1, or whatever they want.
    # If we force D-NAT, some devices fail if the target is unreachable.
    nft insert rule inet $TABLE $CHAIN_NAT udp dport 53 ether saddr $MAC return comment \"MAC:$MAC\"
    nft insert rule inet $TABLE $CHAIN_NAT tcp dport 53 ether saddr $MAC return comment \"MAC:$MAC\"
    
    # Filter Accept
    # Apply QoS if Per-User Mode is enabled (MAC-based fallback)
    # Note: MAC-based limits are harder to enforce directionally if IP is unknown, 
    # but usually traffic has both. We apply same limits here to be safe.
    
    QOS_MODE=$(uci get pisowifi.qos.mode 2>/dev/null || echo "global")
    if [ "$QOS_MODE" = "per_user" ]; then
         USER_DOWN=$(uci get pisowifi.qos.user_down 2>/dev/null || echo 0)
         USER_UP=$(uci get pisowifi.qos.user_up 2>/dev/null || echo 0)
         
         [ "$USER_DOWN" -gt 0 ] && LIMIT_DOWN="limit rate $((USER_DOWN * 125)) kbytes/second burst 100 kbytes"
         [ "$USER_UP" -gt 0 ] && LIMIT_UP="limit rate $((USER_UP * 125)) kbytes/second burst 100 kbytes"
         
         if [ -n "$LIMIT_UP" ]; then
             nft insert rule inet $TABLE $CHAIN_FILTER ether saddr $MAC $LIMIT_UP accept comment \"MAC:$MAC\"
         else
             nft insert rule inet $TABLE $CHAIN_FILTER ether saddr $MAC accept comment \"MAC:$MAC\"
         fi
         
         if [ -n "$LIMIT_DOWN" ]; then
             nft insert rule inet $TABLE $CHAIN_FILTER ether daddr $MAC $LIMIT_DOWN accept comment \"MAC:$MAC\"
         else
             nft insert rule inet $TABLE $CHAIN_FILTER ether daddr $MAC accept comment \"MAC:$MAC\"
         fi
    else
         nft insert rule inet $TABLE $CHAIN_FILTER ether saddr $MAC accept comment \"MAC:$MAC\"
         nft insert rule inet $TABLE $CHAIN_FILTER ether daddr $MAC accept comment \"MAC:$MAC\"
    fi
    
    # FW4 Fallback (MAC)
    nft insert rule inet fw4 forward ether saddr $MAC accept comment \"MAC:$MAC\" 2>/dev/null || true
    nft insert rule inet fw4 forward ether daddr $MAC accept comment \"MAC:$MAC\" 2>/dev/null || true
    
    logger -t pisowifi "Allow process complete for $MAC / $IP_ARG"
}

deny() {
    [ -z "$MAC" ] && return

    if ! nft list table inet $TABLE 2>/dev/null | grep -q "MAC:$MAC"; then
        return
    fi
    [ -f /tmp/pisowifi_verbose ] && logger -t pisowifi "Denying MAC: $MAC"
    
    # Remove rules specifically for this MAC (using comment tag)
    # This cleans up both MAC and IP rules associated with this user
    
    # Helper to delete by handle
    delete_by_comment() {
        CHAIN=$1
        # Check if rule exists before calling delete loop to save CPU
        # nft list is still somewhat expensive, but less than for-loop calls if many rules
        # Actually, let's just grep the handle list once.
        HANDLES=$(nft -a list chain inet $TABLE $CHAIN 2>/dev/null | grep "MAC:$MAC" | awk '{print $NF}')
        if [ -n "$HANDLES" ]; then
             # logger -t pisowifi "Denying MAC: $MAC"
             for h in $HANDLES; do nft delete rule inet $TABLE $CHAIN handle $h 2>/dev/null || true; done
        fi
    }
    
    delete_by_comment "$CHAIN_FILTER"
    delete_by_comment "$CHAIN_NAT"
    delete_by_comment "postrouting"
    
    # Also clean up fw4 fallback
    HANDLES=$(nft -a list chain inet fw4 forward 2>/dev/null | grep "MAC:$MAC" | awk '{print $NF}')
    for h in $HANDLES; do nft delete rule inet fw4 forward handle $h 2>/dev/null || true; done
    
    # logger -t pisowifi "Deny process complete for MAC: $MAC"
}

case "$CMD" in
    init) init ;;
    allow) allow ;;
    deny) deny ;;
    list) 
        echo "=== Current nftables rules ==="
        nft list table inet $TABLE 2>/dev/null || echo "Table $TABLE not found"
        ;;
    reload_qos)
        reload_qos
        ;;
    *)
        echo "Usage: $0 {init|allow|deny|reload_qos} [mac] [ip]"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/bin/pisowifi_nftables.sh

# 1.5 Create Init Script to Restore Firewall on Boot
echo "Creating QoS Script..."
cat << 'EOF' > /usr/bin/pisowifi_qos.sh
#!/bin/sh

# PisoWifi QoS Manager
# Handles Bandwidth Limiting (Global CAKE or Per-User Policing)

MODE=$(uci get pisowifi.qos.mode 2>/dev/null || echo "global")
GLOBAL_DOWN=$(uci get pisowifi.qos.global_down 2>/dev/null || echo 0)
GLOBAL_UP=$(uci get pisowifi.qos.global_up 2>/dev/null || echo 0)

pick_wan_if() {
    # If user explicitly requests ifb0 (Intermediate Functional Block), prioritize it
    # This assumes the user has set up ingress redirection to ifb0 manually or via other scripts
    if [ -d "/sys/class/net/ifb0" ]; then
        echo "ifb0"
        return 0
    fi
    
    # If user explicitly requests br-lan (LAN-side shaping)
    if [ -d "/sys/class/net/br-lan" ]; then
        echo "br-lan"
        return 0
    fi

    CANDIDATES=""
    CAND=$(uci get network.wan.device 2>/dev/null); [ -n "$CAND" ] && CANDIDATES="$CANDIDATES $CAND"
    CAND=$(uci get network.wan.ifname 2>/dev/null); [ -n "$CAND" ] && CANDIDATES="$CANDIDATES $CAND"
    CAND=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null); [ -n "$CAND" ] && CANDIDATES="$CANDIDATES $CAND"
    CANDIDATES="$CANDIDATES pppoe-wan wan eth1 eth0 br-wan"

    for i in $CANDIDATES; do
        if [ -d "/sys/class/net/$i" ]; then
            echo "$i"
            return 0
        fi
    done
    echo "eth0"
}

WAN_IF=$(pick_wan_if)

# Determine IFB Interface (for Ingress/Download shaping)
# Requires kmod-ifb and tc-tiny
# If not present, we can only shape upload effectively on WAN.
# For download shaping without IFB, we rely on policing or LAN-side shaping (less accurate for NAT).

init() {
    echo "Initializing QoS ($MODE)..."

    if ! command -v tc >/dev/null 2>&1; then
        echo "tc not found - skipping CAKE shaping. Install: opkg update && opkg install tc"
        # Even if TC is missing, we MUST reload nftables to apply Per-User limits
        /usr/bin/pisowifi_nftables.sh reload_qos 2>/dev/null || true
        return 0
    fi
    
    # 1. Clear existing qdiscs
    tc qdisc del dev $WAN_IF root 2>/dev/null
    
    # 2. Apply Global Shaper (CAKE) on WAN Upload
    if [ "$GLOBAL_UP" -gt 0 ]; then
        # Convert Mbps to Kbit
        UP_KBIT=$((GLOBAL_UP * 1024))
        if tc qdisc add dev $WAN_IF root cake bandwidth ${UP_KBIT}kbit besteffort nat 2>/dev/null; then
            echo "Global Upload Limit: ${UP_KBIT}kbit (CAKE)"
        else
            echo "CAKE not available - skipping global shaping. Install: opkg install kmod-sched-cake"
        fi
    else
        # Just use CAKE without limit for bufferbloat control
        if tc qdisc add dev $WAN_IF root cake besteffort nat 2>/dev/null; then
            echo "Global Upload: Unlimited (CAKE)"
        else
            echo "CAKE not available - skipping global shaping. Install: opkg install kmod-sched-cake"
        fi
    fi
    
    # 3. Apply Global Download Shaper (requires IFB)
    # We will skip IFB setup for simplicity in this CGI version as it requires extra kernel modules.
    # Instead, we will assume the user mainly cares about Per-User limits or basic Upload shaping.
    
    # 4. Handle Per-User Limits via NFTables
    # We call the firewall script to reload rules based on the new QoS settings
    /usr/bin/pisowifi_nftables.sh reload_qos
}

stop() {
    tc qdisc del dev $WAN_IF root 2>/dev/null
}

case "$1" in
    start|init|reload)
        init
        ;;
    stop)
        stop
        ;;
    *)
        echo "Usage: $0 {start|stop|reload}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/bin/pisowifi_qos.sh

echo "Creating Init Script..."
cat << 'EOF' > /etc/init.d/pisowifi
#!/bin/sh /etc/rc.common

START=99
STOP=10

FIREWALL_SCRIPT="/usr/bin/pisowifi_nftables.sh"
SESSIOND="/usr/bin/pisowifi_sessiond.sh"
PIDFILE="/var/run/pisowifi_sessiond.pid"

boot() {
    start
}

start() {
    logger -t pisowifi "Starting PisoWifi Firewall..."
    $FIREWALL_SCRIPT init
    /usr/bin/pisowifi_qos.sh init
    
    # Ensure DB exists and has tables (Basic check)
    DB_FILE="/etc/pisowifi/pisowifi.db"
    if [ ! -f "$DB_FILE" ]; then
        mkdir -p /etc/pisowifi
        sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS coins (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, coins INTEGER, timestamp INTEGER DEFAULT (strftime('%s', 'now')));"
        sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (mac TEXT PRIMARY KEY, ip TEXT, session_end INTEGER, coins_inserted INTEGER DEFAULT 0, total_time INTEGER DEFAULT 0, created_at INTEGER DEFAULT (strftime('%s', 'now')), paused_time INTEGER DEFAULT 0);"
        sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS rates (id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER, minutes INTEGER, is_pausable INTEGER DEFAULT 1, expiration INTEGER DEFAULT 0);"
        sqlite3 $DB_FILE "INSERT INTO rates (amount, minutes) SELECT 1, 12 WHERE NOT EXISTS (SELECT 1 FROM rates WHERE amount=1);"
        chmod 666 $DB_FILE
    fi

     if [ -x "$SESSIOND" ]; then
         mkdir -p /var/run
         $SESSIOND start
     fi
}

stop() {
    logger -t pisowifi "Stopping PisoWifi Firewall..."
    if [ -x "$SESSIOND" ]; then
        $SESSIOND stop
    fi
    nft delete table inet pisowifi 2>/dev/null
}
EOF
chmod +x /etc/init.d/pisowifi
/etc/init.d/pisowifi enable
/etc/init.d/pisowifi start

# 1.6 Create Session Enforcer (Auto-expire users and restore access)
cat << 'EOF' > /usr/bin/pisowifi_sessiond.sh
#!/bin/sh

DB_FILE="/etc/pisowifi/pisowifi.db"
FIREWALL_SCRIPT="/usr/bin/pisowifi_nftables.sh"
PIDFILE="/var/run/pisowifi_sessiond.pid"

is_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

start_daemon() {
    is_running && exit 0
    mkdir -p /var/run
    (
        echo $$ > "$PIDFILE"
        while true; do
            NOW=$(date +%s)

            if [ -f "$DB_FILE" ]; then
                sqlite3 "$DB_FILE" "SELECT mac FROM users WHERE paused_time > 0" 2>/dev/null | while read m; do
                    [ -z "$m" ] && continue
                    $FIREWALL_SCRIPT deny "$m" >/dev/null 2>&1
                done

                sqlite3 "$DB_FILE" "SELECT mac FROM users WHERE session_end > 0 AND session_end <= $NOW" 2>/dev/null | while read m; do
                    [ -z "$m" ] && continue
                    $FIREWALL_SCRIPT deny "$m" >/dev/null 2>&1
                    sqlite3 "$DB_FILE" "UPDATE users SET session_end=0, paused_time=0 WHERE mac='$m' AND session_end <= $NOW" 2>/dev/null || true
                done

                sqlite3 -separator '|' "$DB_FILE" "SELECT mac, ip FROM users WHERE session_end > $NOW AND paused_time = 0" 2>/dev/null | while IFS='|' read m ip; do
                    [ -z "$m" ] && continue
                    if ! nft list chain inet pisowifi pisowifi_filter 2>/dev/null | grep -q "MAC:$m"; then
                        $FIREWALL_SCRIPT allow "$m" "$ip" >/dev/null 2>&1
                    fi
                done
            fi

            sleep 5
        done
    ) >/dev/null 2>&1 &
}

stop_daemon() {
    if is_running; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
    fi
    rm -f "$PIDFILE"
}

case "$1" in
    start) start_daemon ;;
    stop) stop_daemon ;;
    restart) stop_daemon; start_daemon ;;
esac
EOF
chmod +x /usr/bin/pisowifi_sessiond.sh

# 2. Ensure Button Script is Present
# Always overwrite to ensure we use the SQLite version compatible with this CGI script
# Installing for BOTH WPS and RESET buttons to cover all bases
echo "Creating Button Scripts (WPS & RESET)..."

# Common script content
cat << 'EOF' > /tmp/pisowifi_button.sh
#!/bin/sh
[ "$ACTION" = "pressed" ] || exit 0
DB_FILE="/etc/pisowifi/pisowifi.db"
mkdir -p /etc/pisowifi
chmod 777 /etc/pisowifi

# Insert coin into database for any user (global coin counter)
sqlite3 $DB_FILE "INSERT INTO coins (mac, coins) VALUES ('00:00:00:00:00:00', 1)"
COUNT=$(sqlite3 $DB_FILE "SELECT SUM(coins) FROM coins WHERE mac='00:00:00:00:00:00'")
logger -t pisowifi "Coin inserted via $BUTTON button. Total: $COUNT"

# Ensure permissions are correct just in case they were reset
chmod 666 $DB_FILE
EOF

# Install for WPS
cp /tmp/pisowifi_button.sh /etc/rc.button/wps
chmod +x /etc/rc.button/wps

# Install for RESET (handling the case where user uses reset button)
cp /tmp/pisowifi_button.sh /etc/rc.button/reset
chmod +x /etc/rc.button/reset

# 2.5 Create Local Database for User Records
echo "Setting up local database..."
mkdir -p /etc/pisowifi
chmod 777 /etc/pisowifi
DB_FILE="/etc/pisowifi/pisowifi.db"

# 2.6 Setup Configuration (UCI)
echo "Setting up configuration..."
touch /etc/config/pisowifi

# Define GREP command to use
GREP="/bin/grep"
[ -x "/usr/bin/grep" ] && GREP="/usr/bin/grep"
[ -x "/bin/busybox" ] && GREP="/bin/busybox grep"

uci set pisowifi.settings=settings
uci set pisowifi.settings.minutes_per_peso='12'
uci set pisowifi.settings.admin_password='admin'

# Initialize QoS config
uci set pisowifi.qos=qos
uci set pisowifi.qos.mode='global'
uci set pisowifi.qos.global_down='0'
uci set pisowifi.qos.global_up='0'
uci set pisowifi.qos.user_down='0'
uci set pisowifi.qos.user_up='0'

uci set pisowifi.license=license
uci set pisowifi.license.enabled='0'
uci set pisowifi.license.supabase_url=''
uci set pisowifi.license.supabase_key=''
uci set pisowifi.license.vendor_id=''
uci set pisowifi.license.vendor_name=''
uci set pisowifi.license.license_key=''
uci set pisowifi.license.license_id=''
uci set pisowifi.license.last_check='0'
uci set pisowifi.license.valid='0'
uci set pisowifi.license.expires_at=''
uci set pisowifi.license.hardware_id=''
uci set pisowifi.license.hardware_match='0'

    if [ -f /etc/pisowifi/supabase.env ]; then
        SUPA_URL=$($GREP -m1 '^SUPABASE_URL=' /etc/pisowifi/supabase.env 2>/dev/null | cut -d= -f2- | tr -d '\r')
        SUPA_KEY=$($GREP -m1 '^SUPABASE_ANON_KEY=' /etc/pisowifi/supabase.env 2>/dev/null | cut -d= -f2- | tr -d '\r')
        SUPA_SERVICE_KEY=$($GREP -m1 '^SUPABASE_SERVICE_ROLE_KEY=' /etc/pisowifi/supabase.env 2>/dev/null | cut -d= -f2- | tr -d '\r')
        SUPA_URL=$(echo "$SUPA_URL" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')
        SUPA_KEY=$(echo "$SUPA_KEY" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')
        SUPA_SERVICE_KEY=$(echo "$SUPA_SERVICE_KEY" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')
        [ -n "$SUPA_URL" ] && uci set pisowifi.license.supabase_url="$SUPA_URL"
        [ -n "$SUPA_KEY" ] && uci set pisowifi.license.supabase_key="$SUPA_KEY"
        [ -n "$SUPA_SERVICE_KEY" ] && uci set pisowifi.license.supabase_service_key="$SUPA_SERVICE_KEY"
    fi

uci commit pisowifi

# Install sqlite3 if not available (OpenWrt)
opkg list-installed | $GREP -q sqlite3-cli || opkg install sqlite3-cli

# Create database schema
cat << 'EOF' | sqlite3 $DB_FILE
CREATE TABLE IF NOT EXISTS users (
    mac TEXT PRIMARY KEY,
    ip TEXT,
    session_token TEXT,
    session_start INTEGER,
    session_end INTEGER,
    coins_inserted INTEGER DEFAULT 0,
    total_time INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    paused_time INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT,
    start_time INTEGER,
    end_time INTEGER,
    coins_used INTEGER,
    status TEXT DEFAULT 'active',
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS coins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT,
    coins INTEGER,
    timestamp INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS rates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    amount INTEGER,
    minutes INTEGER,
    is_pausable INTEGER DEFAULT 1,
    expiration INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS devices (
    mac TEXT PRIMARY KEY,
    ip TEXT,
    hostname TEXT,
    notes TEXT,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_users_mac ON users(mac);
CREATE INDEX IF NOT EXISTS idx_sessions_mac ON sessions(mac);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
CREATE INDEX IF NOT EXISTS idx_devices_mac ON devices(mac);
EOF

# Update existing table (Outside heredoc)
sqlite3 $DB_FILE "ALTER TABLE rates ADD COLUMN expiration INTEGER DEFAULT 0;" 2>/dev/null || true
sqlite3 $DB_FILE "ALTER TABLE rates ADD COLUMN is_pausable INTEGER DEFAULT 1;" 2>/dev/null || true

# Insert default 1 Peso rate if not exists (Outside heredoc)
sqlite3 $DB_FILE "INSERT INTO rates (amount, minutes) SELECT 1, 12 WHERE NOT EXISTS (SELECT 1 FROM rates WHERE amount=1);" 2>/dev/null

# Attempt to add paused_time column to existing installations (ignore error if exists)
# This is done OUTSIDE the heredoc block because it is a shell command
sqlite3 $DB_FILE "ALTER TABLE users ADD COLUMN paused_time INTEGER DEFAULT 0;" 2>/dev/null || true
sqlite3 $DB_FILE "ALTER TABLE users ADD COLUMN session_token TEXT;" 2>/dev/null || true
sqlite3 $DB_FILE "CREATE INDEX IF NOT EXISTS idx_users_session_token ON users(session_token);" 2>/dev/null || true

# Ensure database is writable by everyone (so CGI and Button scripts can both access it)
chmod 666 $DB_FILE
# Also ensure the directory is writable (for journal files)
chmod 777 /tmp

# 3. Create Main CGI Script (The Controller)
# This handles ALL logic: Serving the page, API requests, Coin checks.
# Stop uhttpd temporarily to avoid "Text file busy" error
echo "Stopping web server temporarily..."
/etc/init.d/uhttpd stop 2>/dev/null
sleep 2

cat << 'EOF' > /www/cgi-bin/pisowifi
#!/bin/sh

# Simple captive portal detection - only check for specific known detection URLs
REQUEST_URI="${REQUEST_URI:-}"

# Check for common captive portal detection URLs and return success
# This prevents devices from thinking they have internet when they don't
# REMOVED: We WANT them to think they have NO internet so they pop up the portal.
# If we return 204 or Success here, the device stays connected but shows "Connected / No Internet" or just "Connected"
# and DOES NOT show the popup.
# By removing these checks, we fall through to the HTML response, which triggers the popup.

# Auth-aware connectivity checks to avoid needing WiFi reconnect after buying time
DB_FILE="/etc/pisowifi/pisowifi.db"
mkdir -p /etc/pisowifi
chmod 777 /etc/pisowifi

NOW=$(date +%s)
CLIENT_MAC=$(grep "$REMOTE_ADDR " /proc/net/arp | awk '{print $4}' | tr 'a-z' 'A-Z' | head -1)
[ -z "$CLIENT_MAC" ] && CLIENT_MAC="UNKNOWN"
AUTH_OK=0
if [ "$CLIENT_MAC" != "UNKNOWN" ] && [ -f "$DB_FILE" ]; then
    RES=$(sqlite3 "$DB_FILE" "SELECT session_end, paused_time FROM users WHERE mac='$CLIENT_MAC' LIMIT 1" 2>/dev/null)
    EXP=$(echo "$RES" | cut -d'|' -f1)
    PAU=$(echo "$RES" | cut -d'|' -f2)
    [ -z "$EXP" ] && EXP=0
    [ -z "$PAU" ] && PAU=0
    if [ "$PAU" -eq 0 ] && [ "$EXP" -gt "$NOW" ]; then
        AUTH_OK=1
    fi
fi

if echo "$REQUEST_URI" | grep -Eq "(generate_204|connecttest\.txt|ncsi\.txt|hotspot-detect\.html|success\.html)"; then
    if [ "$AUTH_OK" -eq 1 ]; then
        if echo "$REQUEST_URI" | grep -q "generate_204"; then
            echo "Status: 204 No Content"
            echo "Content-type: text/plain"
            echo ""
            exit 0
        fi
        echo "Status: 200 OK"
        echo "Content-type: text/plain"
        echo ""
        echo "OK"
        exit 0
    fi
fi

# if echo "$REQUEST_URI" | grep -q "generate_204"; then
#    # Android/Google connectivity check - return 204 to indicate no internet
#    echo "Status: 204 No Content"
#    echo "Content-type: text/plain"
#    echo ""
#    exit 0
# fi

# if echo "$REQUEST_URI" | grep -q "connecttest.txt"; then
#    # Microsoft Windows connectivity check - return success but no real content
#    echo "HTTP/1.1 200 OK"
#    echo "Content-Type: text/plain"
#    echo ""
#    echo "Microsoft Connect Test - No Internet"
#    exit 0
# fi

# if echo "$REQUEST_URI" | grep -q "ncsi.txt"; then
#    # Microsoft NCSI check - return success but no real content
#    echo "HTTP/1.1 200 OK"
#    echo "Content-Type: text/plain"
#    echo ""
#    echo "Microsoft NCSI - No Internet"
#    exit 0
# fi

# Set Content-Type for normal requests
echo "Status: 200 OK"
echo "Content-type: text/html; charset=utf-8"
echo ""

# Helper Variables
DB_FILE="/etc/pisowifi/pisowifi.db"
COIN_FILE="/tmp/pisowifi_coins"
SESSION_FILE="/tmp/pisowifi.sessions"
MINUTES_PER_PESO=$(uci get pisowifi.settings.minutes_per_peso 2>/dev/null || echo 12)
FIREWALL_SCRIPT="/usr/bin/pisowifi_nftables.sh"

# Log Captive Portal Triggers
    # Reduced logging: Only log unique triggers occasionally?
    # Or just rely on the session log.
    if ! echo "$QUERY_STRING" | grep -q "action="; then
        # CLIENT_MAC=$(grep "$REMOTE_ADDR " /proc/net/arp | awk '{print $4}' | tr 'a-z' 'A-Z' | head -1)
        # logger -t pisowifi "CAPTIVE PORTAL: $REMOTE_ADDR -> $REQUEST_URI"
        true
    fi

# Ensure database exists
if [ ! -f "$DB_FILE" ]; then
    echo "Warning: Database not found at $DB_FILE, creating default database" >&2
    # Create minimal database schema
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (mac TEXT PRIMARY KEY, ip TEXT, session_token TEXT, session_end INTEGER, coins_inserted INTEGER DEFAULT 0);"
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS coins (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, coins INTEGER, timestamp INTEGER DEFAULT (strftime('%s', 'now')));"
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS coinslot_locks (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT UNIQUE NOT NULL, locked_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')), session_token TEXT, created_at INTEGER DEFAULT (strftime('%s', 'now')));"
    sqlite3 $DB_FILE "CREATE INDEX IF NOT EXISTS idx_coinslot_locks_mac ON coinslot_locks(mac);"
fi
sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS coinslot_locks (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT UNIQUE NOT NULL, locked_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')), session_token TEXT, created_at INTEGER DEFAULT (strftime('%s', 'now')));" 2>/dev/null || true
sqlite3 $DB_FILE "CREATE INDEX IF NOT EXISTS idx_coinslot_locks_mac ON coinslot_locks(mac);" 2>/dev/null || true
chmod 666 $DB_FILE

# Database Helper Functions
query_db() {
    sqlite3 "$DB_FILE" -cmd ".timeout 2000" "$1" 2>/dev/null || echo ""
}

get_user_session() {
    local mac="$1"
    local result=$(query_db "SELECT session_end FROM users WHERE mac='$mac' AND session_end > $(date +%s) LIMIT 1")
    echo "$result"
}

update_user_session() {
    local mac="$1"
    local ip="$2"
    local session_end="$3"
    local coins="$4"
    local token="$5"
    
    sqlite3 $DB_FILE "INSERT OR REPLACE INTO users (mac, ip, session_end, coins_inserted, session_token) VALUES ('$mac', '$ip', $session_end, $coins, '$token');" 2>/dev/null \
    || sqlite3 $DB_FILE "INSERT OR REPLACE INTO users (mac, ip, session_end, coins_inserted) VALUES ('$mac', '$ip', $session_end, $coins);" 2>/dev/null || true
}

insert_coin_record() {
    local mac="$1"
    local coins="$2"
    query_db "INSERT INTO coins (mac, coins) VALUES ('$mac', $coins)"
}

# Coinslot Lock Functions (No Timeout)
get_coinslot_lock() {
    local mac="$1"
    local result=$(query_db "SELECT mac, locked_at, session_token FROM coinslot_locks WHERE mac='$mac' LIMIT 1")
    echo "$result"
}

get_active_coinslot_lock() {
    # Get any existing lock (no expiration check)
    local result=$(query_db "SELECT mac, locked_at, session_token FROM coinslot_locks ORDER BY locked_at DESC LIMIT 1")
    if [ -n "$result" ]; then
        local locked_mac=$(echo "$result" | cut -d'|' -f1)
        if ! echo "$locked_mac" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'; then
            logger -t pisowifi "[LOCK_DEBUG] Invalid lock row detected (mac=$locked_mac). Removing."
            query_db "DELETE FROM coinslot_locks WHERE mac='$locked_mac'"
            echo ""
            return
        fi
    fi
    echo "$result"
}

acquire_coinslot_lock() {
    local mac="$1"
    local session_token="$2"
    local now=$(date +%s)

    local sqlite_out rc owner_mac
    sqlite_out=$(sqlite3 "$DB_FILE" -batch -noheader -cmd ".timeout 2000" "BEGIN IMMEDIATE;
DELETE FROM coinslot_locks WHERE rowid NOT IN (SELECT rowid FROM coinslot_locks ORDER BY locked_at DESC LIMIT 1);
INSERT INTO coinslot_locks (mac, locked_at, session_token)
SELECT '$mac', $now, '$session_token'
WHERE NOT EXISTS (SELECT 1 FROM coinslot_locks);
UPDATE coinslot_locks SET locked_at=$now, session_token='$session_token' WHERE mac='$mac';
SELECT mac FROM coinslot_locks ORDER BY locked_at DESC LIMIT 1;
COMMIT;" 2>&1)
    rc=$?
    owner_mac=$(printf "%s" "$sqlite_out" | tail -n 1 | tr -d '\r')

    if [ $rc -ne 0 ] || [ -z "$owner_mac" ]; then
        logger -t pisowifi "[LOCK_DEBUG] Failed to acquire lock - sqlite transaction error (rc=$rc)"
        logger -t pisowifi "[LOCK_DEBUG] sqlite output: $(printf "%s" "$sqlite_out" | tr '\n' ' ' | cut -c1-300)"
        return 1
    fi

    if ! echo "$owner_mac" | grep -Eq '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'; then
        logger -t pisowifi "[LOCK_DEBUG] Failed to acquire lock - invalid lock owner value: $owner_mac"
        return 1
    fi

    if [ "$owner_mac" = "$mac" ]; then
        logger -t pisowifi "[LOCK_DEBUG] Device $mac acquired coinslot lock"
        return 0
    fi

    logger -t pisowifi "[LOCK_DEBUG] Device $mac denied - lock owned by $owner_mac"
    return 1
}

release_coinslot_lock() {
    local mac="$1"
    sqlite3 "$DB_FILE" -cmd ".timeout 2000" "BEGIN IMMEDIATE;
DELETE FROM coinslot_locks WHERE rowid NOT IN (SELECT rowid FROM coinslot_locks ORDER BY locked_at DESC LIMIT 1);
DELETE FROM coinslot_locks WHERE mac='$mac';
COMMIT;" 2>/dev/null || true
}

cleanup_expired_locks() {
    # No-op - locks don't expire
    return 0
}

# Supabase Helper Functions
supa_request() {
    local url="$1" key="$2" path="$3"
    SUPA_HTTP_CODE="" SUPA_BODY=""
    local curl_bin="/usr/bin/curl"
    [ -x "$curl_bin" ] || curl_bin="/bin/curl"
    [ -x "$curl_bin" ] || return
    local tmp="/tmp/supa_$$"
    SUPA_HTTP_CODE=$("$curl_bin" -sS -o "$tmp" -w "%{http_code}" -H "apikey: $key" -H "Authorization: Bearer $key" -H "Accept: application/json" "$url/rest/v1/$path")
    SUPA_BODY=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
}

supa_patch() {
    local url="$1" key="$2" path="$3" body="$4"
    SUPA_HTTP_CODE="" SUPA_BODY=""
    local curl_bin="/usr/bin/curl"
    [ -x "$curl_bin" ] || curl_bin="/bin/curl"
    [ -x "$curl_bin" ] || return
    local tmp="/tmp/supa_$$"
    SUPA_HTTP_CODE=$("$curl_bin" -sS -o "$tmp" -w "%{http_code}" -X PATCH -H "apikey: $key" -H "Authorization: Bearer $key" -H "Content-Type: application/json" -d "$body" "$url/rest/v1/$path")
    SUPA_BODY=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
}

supa_insert() {
    local url="$1" key="$2" path="$3" body="$4"
    SUPA_HTTP_CODE="" SUPA_BODY=""
    local curl_bin="/usr/bin/curl"
    [ -x "$curl_bin" ] || curl_bin="/bin/curl"
    [ -x "$curl_bin" ] || return
    local tmp="/tmp/supa_$$"
    SUPA_HTTP_CODE=$("$curl_bin" -sS -o "$tmp" -w "%{http_code}" -X POST -H "apikey: $key" -H "Authorization: Bearer $key" -H "Content-Type: application/json" -d "$body" "$url/rest/v1/$path")
    SUPA_BODY=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
}

get_coin_count() {
    local mac="$1"
    # Get coins from global counter (mac 00:00:00:00:00:00)
    local result=$(query_db "SELECT SUM(coins) FROM coins WHERE mac='00:00:00:00:00:00'")
    echo "$result" | head -1
}

transfer_coins_to_user() {
    local mac="$1"
    local global_coins=$(get_coin_count)
    [ -z "$global_coins" ] && global_coins=0
    
    if [ "$global_coins" -gt 0 ]; then
        # Transfer coins from global counter to user
        query_db "INSERT INTO coins (mac, coins) VALUES ('$mac', $global_coins)"
        # Clear global counter
        query_db "DELETE FROM coins WHERE mac='00:00:00:00:00:00'"
        echo $global_coins
    else
        echo 0
    fi
}

# Get Query String
QUERY_STRING="$QUERY_STRING"

# Get Request Method (GET/POST)
REQUEST_METHOD="$REQUEST_METHOD"

# Helper Functions
get_client_mac() {
    # Try to find MAC from ARP table using REMOTE_ADDR
    local mac=$(grep "$REMOTE_ADDR " /proc/net/arp | awk '{print $4}' | tr 'a-z' 'A-Z' | head -1)
    if [ -n "$mac" ]; then
        echo "$mac"
    else
        # Fallback: generate a fake MAC based on IP for testing
        echo "00:00:00:$(echo $REMOTE_ADDR | awk -F. '{printf "%02X:%02X:%02X", $2, $3, $4}')"
    fi
}

handle_api() {
    MAC=$(get_client_mac)
    
    SID=$(echo "$QUERY_STRING" | grep -o "sid=[^&]*" | cut -d= -f2 | sed 's/%3A/:/g; s/%2D/-/g; s/%2d/-/g')
    [ "$SID" = "UNKNOWN" ] && SID=""
    
    # Supabase Config for Roaming
    SUPA_URL=$(uci get pisowifi.supabase.url 2>/dev/null)
    SUPA_KEY=$(uci get pisowifi.supabase.key 2>/dev/null)
    SUPA_SERVICE_KEY=$(uci get pisowifi.license.supabase_service_key 2>/dev/null)
    
    [ -f /tmp/pisowifi_verbose ] && logger -t pisowifi "API request: $QUERY_STRING from MAC: $MAC IP: $REMOTE_ADDR SID: $SID"
    
    # Simple JSON Response Wrapper
    json_response() {
        echo "$1"
        exit 0
    }

    gen_sid() {
        if [ -r /dev/urandom ] && command -v hexdump >/dev/null 2>&1; then
            hexdump -n 16 -e '16/1 "%02x"' /dev/urandom 2>/dev/null
            return
        fi
        if [ -r /proc/sys/kernel/random/uuid ]; then
            cat /proc/sys/kernel/random/uuid | tr -d '\r\n-' | tr 'A-F' 'a-f' | cut -c1-32
            return
        fi
        if command -v md5sum >/dev/null 2>&1; then
            echo -n "$(date +%s)-$$-${RANDOM:-0}" | md5sum 2>/dev/null | awk '{print $1}' | cut -c1-32
            return
        fi
        echo "$(date +%s)$$${RANDOM:-0}" | tr -cd '0-9' | cut -c1-32
    }
    
    case "$QUERY_STRING" in
        "action=status"*)
            # Check firewall status
            # Use nft to check if table exists, if not init
            nft list table inet pisowifi >/dev/null 2>&1 || $FIREWALL_SCRIPT init
            
            AUTH="false"
            TIME_REMAINING=0
            PAUSED_TIME=0
            
            # logger -t pisowifi "Status check - MAC: $MAC, IP: $REMOTE_ADDR"
            
            if [ -n "$MAC" ]; then
                NOW=$(date +%s)
                TOKEN_FOUND=0
                if [ -n "$SID" ]; then
                    TOKEN_ROW=$(sqlite3 $DB_FILE "SELECT mac, session_end, paused_time FROM users WHERE session_token='$SID' LIMIT 1" 2>/dev/null)
                    TOKEN_MAC=$(echo "$TOKEN_ROW" | cut -d'|' -f1)
                    TOKEN_EXPIRY=$(echo "$TOKEN_ROW" | cut -d'|' -f2)
                    TOKEN_PAUSED=$(echo "$TOKEN_ROW" | cut -d'|' -f3)
                    [ -z "$TOKEN_EXPIRY" ] && TOKEN_EXPIRY=0
                    [ -z "$TOKEN_PAUSED" ] && TOKEN_PAUSED=0
                    if [ -n "$TOKEN_MAC" ]; then
                        TOKEN_FOUND=1
                        if [ "$TOKEN_MAC" != "$MAC" ]; then
                            sqlite3 $DB_FILE "DELETE FROM users WHERE mac='$MAC' AND session_token!='$SID';" 2>/dev/null || true
                            sqlite3 $DB_FILE "UPDATE users SET mac='$MAC', ip='$REMOTE_ADDR' WHERE session_token='$SID';" 2>/dev/null || true
                        else
                            sqlite3 $DB_FILE "UPDATE users SET ip='$REMOTE_ADDR' WHERE session_token='$SID';" 2>/dev/null || true
                        fi
                        EXPIRY="$TOKEN_EXPIRY"
                        PAUSED_TIME="$TOKEN_PAUSED"
                    fi
                fi

                if [ "$TOKEN_FOUND" = "0" ]; then
                    RESULT=$(sqlite3 $DB_FILE "SELECT session_end, paused_time FROM users WHERE mac='$MAC' LIMIT 1" 2>/dev/null)
                    EXPIRY=$(echo "$RESULT" | cut -d'|' -f1)
                    PAUSED_TIME=$(echo "$RESULT" | cut -d'|' -f2)
                    [ -z "$EXPIRY" ] && EXPIRY=0
                    [ -z "$PAUSED_TIME" ] && PAUSED_TIME=0
                    if [ -n "$SID" ] && { [ "$PAUSED_TIME" -gt 0 ] 2>/dev/null || [ "$EXPIRY" -gt "$NOW" ] 2>/dev/null; }; then
                        sqlite3 $DB_FILE "UPDATE users SET session_token='$SID' WHERE mac='$MAC' AND (session_token IS NULL OR session_token='');" 2>/dev/null || true
                    fi
                fi

                if [ "$PAUSED_TIME" -gt 0 ] 2>/dev/null; then
                    AUTH="paused"
                    TIME_REMAINING=$PAUSED_TIME
                elif [ "$EXPIRY" -gt "$NOW" ] 2>/dev/null; then
                    AUTH="true"
                    TIME_REMAINING=$((EXPIRY - NOW))
                else
                    if [ -n "$SUPA_URL" ] && [ -n "$SID" ]; then
                        supa_request "$SUPA_URL" "$SUPA_KEY" "sessions?select=remaining_seconds,connected_at,is_paused&session_uuid=eq.$SID&limit=1"
                        if [ "$SUPA_HTTP_CODE" = "200" ] && [ -n "$SUPA_BODY" ] && [ "$SUPA_BODY" != "[]" ]; then
                            REM_SEC=$(echo "$SUPA_BODY" | grep -o '"remaining_seconds":[0-9]*' | cut -d: -f2)
                            IS_PAUSED=$(echo "$SUPA_BODY" | grep -o '"is_paused":[^,}]*' | cut -d: -f2)
                            [ -z "$REM_SEC" ] && REM_SEC=0
                            if [ "$IS_PAUSED" = "true" ]; then
                                AUTH="paused"
                                TIME_REMAINING=$REM_SEC
                                sqlite3 $DB_FILE "INSERT OR REPLACE INTO users (mac, ip, session_end, paused_time, session_token) VALUES ('$MAC', '$REMOTE_ADDR', 0, $REM_SEC, '$SID');" 2>/dev/null \
                                || sqlite3 $DB_FILE "INSERT OR REPLACE INTO users (mac, ip, session_end, paused_time) VALUES ('$MAC', '$REMOTE_ADDR', 0, $REM_SEC);" 2>/dev/null || true
                            elif [ "$REM_SEC" -gt 0 ] 2>/dev/null; then
                                NEW_EXPIRY=$((NOW + REM_SEC))
                                AUTH="true"
                                TIME_REMAINING=$REM_SEC
                                sqlite3 $DB_FILE "INSERT OR REPLACE INTO users (mac, ip, session_end, paused_time, session_token) VALUES ('$MAC', '$REMOTE_ADDR', $NEW_EXPIRY, 0, '$SID');" 2>/dev/null \
                                || sqlite3 $DB_FILE "INSERT OR REPLACE INTO users (mac, ip, session_end, paused_time) VALUES ('$MAC', '$REMOTE_ADDR', $NEW_EXPIRY, 0);" 2>/dev/null || true
                                $FIREWALL_SCRIPT allow "$MAC" "$REMOTE_ADDR"
                            fi
                        fi
                    fi
                fi
            fi
            json_response "{\"authenticated\": \"$AUTH\", \"time_remaining\": $TIME_REMAINING, \"mac\": \"$MAC\", \"ip\": \"$REMOTE_ADDR\"}"
            ;;
            
        "action=start_coin"*)
            # Check if coinslot is available and acquire lock (no timeout)
            [ -z "$SID" ] && SID="$(gen_sid)"
            
            local microtime=$(date +%s%N)
            logger -t pisowifi "[LOCK_DEBUG] === START_COIN REQUEST START ==="
            logger -t pisowifi "[LOCK_DEBUG] Device $MAC attempting to acquire coinslot lock (microtime: $microtime)"
            logger -t pisowifi "[LOCK_DEBUG] Session Token: $SID"
            
            # Check current lock status first
            logger -t pisowifi "[LOCK_DEBUG] Checking current lock status..."
            local current_lock=$(get_active_coinslot_lock)
            if [ -n "$current_lock" ]; then
                local locked_mac=$(echo "$current_lock" | cut -d'|' -f1)
                local locked_at=$(echo "$current_lock" | cut -d'|' -f2)
                logger -t pisowifi "[LOCK_DEBUG] Found existing lock: MAC=$locked_mac, locked_at=$locked_at"
                
                if [ "$locked_mac" != "$MAC" ]; then
                    logger -t pisowifi "[LOCK_DEBUG] ❌ DEVICE DENIED - Coinslot already locked by $locked_mac"
                    logger -t pisowifi "[LOCK_DEBUG] === START_COIN REQUEST DENIED ==="
                    json_response "{\"status\": \"failed\", \"error\": \"Coinslot is currently in use by another device\", \"locked_by_mac\": \"$locked_mac\", \"button_disabled\": true}"
                    return
                else
                    logger -t pisowifi "[LOCK_DEBUG] ✅ Device $MAC already has the lock - proceeding"
                fi
            else
                logger -t pisowifi "[LOCK_DEBUG] ✅ No existing lock found - coinslot is available"
            fi
            
            # Try to acquire lock atomically
            logger -t pisowifi "[LOCK_DEBUG] Attempting atomic lock acquisition..."
            if acquire_coinslot_lock "$MAC" "$SID"; then
                logger -t pisowifi "[LOCK_DEBUG] ✅ SUCCESS - Device $MAC successfully acquired coinslot lock"
                logger -t pisowifi "[LOCK_DEBUG] Clearing coins from database for this user..."
                
                # Clear coins from database for this user
                query_db "DELETE FROM coins WHERE mac='$MAC'"
                
                logger -t pisowifi "[LOCK_DEBUG] === START_COIN REQUEST SUCCESS ==="
                json_response "{\"status\": \"started\", \"lock_acquired\": true, \"session_token\": \"$SID\", \"mac\": \"$MAC\", \"button_enabled\": true}"
            else
                logger -t pisowifi "[LOCK_DEBUG] ❌ FAILED - Device $MAC failed to acquire coinslot lock"
                # Check who has the lock (should be someone else now)
                local active_lock=$(get_active_coinslot_lock)
                if [ -n "$active_lock" ]; then
                    local locked_mac=$(echo "$active_lock" | cut -d'|' -f1)
                    logger -t pisowifi "[LOCK_DEBUG] Coinslot now locked by $locked_mac (race condition detected)"
                    logger -t pisowifi "[LOCK_DEBUG] === START_COIN REQUEST FAILED ==="
                    json_response "{\"status\": \"failed\", \"error\": \"Coinslot is currently in use by another device\", \"locked_by_mac\": \"$locked_mac\", \"button_disabled\": true}"
                else
                    logger -t pisowifi "[LOCK_DEBUG] === START_COIN REQUEST FAILED ==="
                    json_response "{\"status\": \"failed\", \"error\": \"Failed to acquire coinslot lock\", \"button_disabled\": true}"
                fi
            fi
            ;;
            
        "action=check_coin"*)
            COUNT=$(get_coin_count "$MAC")
            [ -z "$COUNT" ] && COUNT=0
            MINUTES=$((COUNT * MINUTES_PER_PESO))
            json_response "{\"count\": $COUNT, \"minutes\": $MINUTES}"
            ;;
            
        "action=connect"*)
            # Release coinslot lock before connecting
            release_coinslot_lock "$MAC"
            
            # Transfer coins from global counter to user
            COUNT=$(transfer_coins_to_user "$MAC")
            [ -z "$COUNT" ] && COUNT=0
            
            if [ "$COUNT" -gt 0 ]; then
                # Check for Custom Rate first
                CUSTOM_MIN=$(query_db "SELECT minutes FROM rates WHERE amount=$COUNT LIMIT 1")
                
                if [ -n "$CUSTOM_MIN" ] && [ "$CUSTOM_MIN" -gt 0 ]; then
                    ADDED_MINUTES=$CUSTOM_MIN
                    logger -t pisowifi "Using CUSTOM rate for $COUNT Pesos: $ADDED_MINUTES minutes"
                else
                    # Fallback to standard rate
                    MINUTES_PER_PESO=$(uci get pisowifi.settings.minutes_per_peso 2>/dev/null || echo 12)
                    ADDED_MINUTES=$((COUNT * MINUTES_PER_PESO))
                    logger -t pisowifi "Using STANDARD rate for $COUNT Pesos: $ADDED_MINUTES minutes"
                fi
                
                NOW=$(date +%s)
                
                # Load current expiry from database
                EXPIRY=$NOW
                EXISTING=$(get_user_session "$MAC")
                if [ -n "$EXISTING" ] && [ "$EXISTING" -gt "$NOW" ]; then
                    EXPIRY=$EXISTING
                fi
                
                NEW_EXPIRY=$((EXPIRY + (ADDED_MINUTES * 60)))
                
                # Update user session in database
                [ -z "$SID" ] && SID="$(gen_sid)"
                update_user_session "$MAC" "$REMOTE_ADDR" $NEW_EXPIRY $COUNT "$SID"
                
                # Sync to Supabase for Roaming
                if [ -n "$SUPA_URL" ] && [ -n "$SID" ]; then
                    REM_SEC=$((NEW_EXPIRY - NOW))
                    # Check if session exists in Supabase
                    supa_request "$SUPA_URL" "$SUPA_KEY" "sessions?select=id&session_uuid=eq.$SID&limit=1"
                    if [ "$SUPA_HTTP_CODE" = "200" ] && [ -n "$SUPA_BODY" ] && [ "$SUPA_BODY" != "[]" ]; then
                        # Update existing
                        SID_BODY="{\"mac\": \"$MAC\", \"remaining_seconds\": $REM_SEC, \"is_paused\": false, \"updated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
                        supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?session_uuid=eq.$SID" "$SID_BODY"
                    else
                        # Insert new
                        SID_BODY="{\"mac\": \"$MAC\", \"remaining_seconds\": $REM_SEC, \"session_uuid\": \"$SID\", \"connected_at\": $NOW, \"is_paused\": false}"
                        supa_insert "$SUPA_URL" "$SUPA_KEY" "sessions" "$SID_BODY"
                    fi
                fi
                
                # Allow Access
                $FIREWALL_SCRIPT allow "$MAC" "$REMOTE_ADDR"
                logger -t pisowifi "User $MAC connected successfully. Time added: $ADDED_MINUTES mins. New Expiry: $NEW_EXPIRY"
                
                json_response "{\"status\": \"connected\", \"expiry\": $NEW_EXPIRY, \"sid\": \"$SID\", \"redirect_url\": \"https://www.google.com\"}"
            else
                json_response "{\"error\": \"No coins\"}"
            fi
            ;;
            
        "action=pause"*)
            # Release coinslot lock when pausing
            release_coinslot_lock "$MAC"
            
            TARGET_MAC="$MAC"
            if [ -n "$SID" ]; then
                TM=$(sqlite3 $DB_FILE "SELECT mac FROM users WHERE session_token='$SID' LIMIT 1" 2>/dev/null)
                [ -n "$TM" ] && TARGET_MAC="$TM"
            fi
            EXPIRY=$(get_user_session "$TARGET_MAC")
            NOW=$(date +%s)
            
            if [ -n "$EXPIRY" ] && [ "$EXPIRY" -gt "$NOW" ]; then
                REMAINING=$((EXPIRY - NOW))
                # Save remaining time, clear session end
                query_db "UPDATE users SET paused_time=$REMAINING, session_end=0 WHERE mac='$TARGET_MAC'"
                
                # Sync to Supabase
                if [ -n "$SUPA_URL" ]; then
                    SID_BODY="{\"remaining_seconds\": $REMAINING, \"is_paused\": true, \"updated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
                    if [ -n "$SID" ]; then
                        supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?session_uuid=eq.$SID" "$SID_BODY"
                    else
                        supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?mac=eq.$TARGET_MAC" "$SID_BODY"
                    fi
                fi
                
                # Cut internet
                $FIREWALL_SCRIPT deny "$TARGET_MAC"
                json_response "{\"status\": \"paused\", \"remaining\": $REMAINING}"
            else
                json_response "{\"error\": \"No active session to pause\"}"
            fi
            ;;

        "action=resume"*)
            TARGET_MAC="$MAC"
            if [ -n "$SID" ]; then
                TM=$(sqlite3 $DB_FILE "SELECT mac FROM users WHERE session_token='$SID' LIMIT 1" 2>/dev/null)
                [ -n "$TM" ] && TARGET_MAC="$TM"
            fi
            PAUSED=$(query_db "SELECT paused_time FROM users WHERE mac='$TARGET_MAC'")
            [ -z "$PAUSED" ] && PAUSED=0
            
            if [ "$PAUSED" -gt 0 ]; then
                NOW=$(date +%s)
                NEW_END=$((NOW + PAUSED))
                # Restore session, clear paused time
                query_db "UPDATE users SET session_end=$NEW_END, paused_time=0 WHERE mac='$TARGET_MAC'"
                
                # Sync to Supabase
                if [ -n "$SUPA_URL" ]; then
                    SID_BODY="{\"remaining_seconds\": $PAUSED, \"is_paused\": false, \"updated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
                    if [ -n "$SID" ]; then
                        supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?session_uuid=eq.$SID" "$SID_BODY"
                    else
                        supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?mac=eq.$TARGET_MAC" "$SID_BODY"
                    fi
                fi
                
                # Restore internet
                $FIREWALL_SCRIPT allow "$TARGET_MAC" "$REMOTE_ADDR"
                json_response "{\"status\": \"resumed\", \"expiry\": $NEW_END}"
            else
                json_response "{\"error\": \"No paused session found\"}"
            fi
            ;;

        "action=logout"*)
            # Release coinslot lock when logging out
            release_coinslot_lock "$MAC"
            
            TARGET_MAC="$MAC"
            if [ -n "$SID" ]; then
                TM=$(sqlite3 $DB_FILE "SELECT mac FROM users WHERE session_token='$SID' LIMIT 1" 2>/dev/null)
                [ -n "$TM" ] && TARGET_MAC="$TM"
            fi
            $FIREWALL_SCRIPT deny "$TARGET_MAC"
            # Remove user session from database
            query_db "UPDATE users SET session_end=0, paused_time=0 WHERE mac='$TARGET_MAC'"
            
            # Sync to Supabase
            if [ -n "$SUPA_URL" ]; then
                SID_BODY="{\"remaining_seconds\": 0, \"is_paused\": false, \"updated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
                if [ -n "$SID" ]; then
                    supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?session_uuid=eq.$SID" "$SID_BODY"
                else
                    supa_patch "$SUPA_URL" "$SUPA_KEY" "sessions?mac=eq.$TARGET_MAC" "$SID_BODY"
                fi
            fi
            
            json_response "{\"status\": \"success\"}"
            ;;
            
        "action=insert_coin"*)
            # Manual coin insertion for testing
            sqlite3 $DB_FILE "INSERT INTO coins (mac, coins) VALUES ('00:00:00:00:00:00', 1)"
            COUNT=$(sqlite3 $DB_FILE "SELECT SUM(coins) FROM coins WHERE mac='00:00:00:00:00:00'")
            logger -t pisowifi "Manual coin inserted. Total: $COUNT"
            json_response "{\"status\": \"coin_inserted\", \"total\": $COUNT}"
            ;;
            
        "action=log_internet"*)
            # Log client internet status
            STATUS=$(echo "$QUERY_STRING" | grep -o "status=[^&]*" | cut -d= -f2)
            CLIENT_MAC=$(echo "$QUERY_STRING" | grep -o "mac=[^&]*" | cut -d= -f2 | sed 's/%3A/:/g')
            
            # Simple rate limiting: Only log if status changed or every few minutes?
            # For now, just log it. Use logger so it shows in logread.
            if [ "$STATUS" = "ONLINE" ]; then
        # Only log online status if verbose logging is enabled (to save CPU)
        [ -f /tmp/pisowifi_verbose ] && logger -t pisowifi "INTERNET CHECK: Client $CLIENT_MAC is ONLINE ✅"
    else
        # Always log offline status as it is an error condition
        logger -t pisowifi "INTERNET CHECK: Client $CLIENT_MAC is OFFLINE ❌"
    fi
            json_response "{\"status\": \"logged\"}"
            ;;

        "action=rates"*)
            RATES_JSON=$(sqlite3 -separator '|' "$DB_FILE" "SELECT amount, minutes, is_pausable, expiration FROM rates ORDER BY amount ASC;" 2>/dev/null | awk -F'|' 'BEGIN{printf "["} {a=$1+0; m=$2+0; p=($3==""?1:$3)+0; e=($4==""?0:$4)+0; if(NR>1) printf ","; printf "{\"amount\":%d,\"minutes\":%d,\"pausable\":%d,\"expiration\":%d}", a,m,p,e} END{printf "]"}')
            [ -z "$RATES_JSON" ] && RATES_JSON="[]"
            json_response "{\"rates\": $RATES_JSON}"
            ;;
            
        "action=test_dns"*)
            # Test DNS resolution for debugging
            MAC=$(get_client_mac)
            AUTH="false"
            if [ -n "$MAC" ]; then
                EXPIRY=$(get_user_session "$MAC")
                NOW=$(date +%s)
                if [ -n "$EXPIRY" ] && [ "$EXPIRY" -gt "$NOW" ]; then
                    AUTH="true"
                fi
            fi
            
            # Test DNS resolution
            DNS_TEST=$(nslookup google.com 8.8.8.8 2>/dev/null | grep -c "Address")
            DNS_LOCAL=$(nslookup google.com 10.0.0.1 2>/dev/null | grep -c "Address")
            
            json_response "{\"authenticated\": \"$AUTH\", \"dns_external\": $DNS_TEST, \"dns_local\": $DNS_LOCAL, \"mac\": \"$MAC\"}"
            ;;
            
        "action=check_coinslot_lock"*)
            # Check if coinslot is locked and by whom (no expiration)
            MAC=$(get_client_mac)

            local active_lock=$(get_active_coinslot_lock)
            if [ -z "$active_lock" ]; then
                json_response "{\"locked\": false, \"mac\": \"$MAC\"}"
                return
            fi

            local locked_mac=$(echo "$active_lock" | cut -d'|' -f1)
            local locked_at=$(echo "$active_lock" | cut -d'|' -f2)

            if [ "$locked_mac" = "$MAC" ]; then
                json_response "{\"locked\": true, \"locked_by_me\": true, \"locked_at\": $locked_at, \"mac\": \"$MAC\"}"
                return
            fi

            json_response "{\"locked\": true, \"locked_by_me\": false, \"locked_by_mac\": \"$locked_mac\", \"locked_at\": $locked_at, \"mac\": \"$MAC\"}"
            ;;
            
        "action=acquire_coinslot_lock"*)
            # Try to acquire coinslot lock (no timeout)
            MAC=$(get_client_mac)
            [ -z "$SID" ] && SID="$(gen_sid)"
            
            if acquire_coinslot_lock "$MAC" "$SID"; then
                json_response "{\"success\": true, \"locked\": true, \"mac\": \"$MAC\", \"session_token\": \"$SID\"}"
            else
                # Check who has the lock
                local active_lock=$(get_active_coinslot_lock)
                if [ -n "$active_lock" ]; then
                    local locked_mac=$(echo "$active_lock" | cut -d'|' -f1)
                    json_response "{\"success\": false, \"error\": \"Coinslot is currently in use by another device\", \"locked_by_mac\": \"$locked_mac\"}"
                else
                    json_response "{\"success\": false, \"error\": \"Failed to acquire lock\"}"
                fi
            fi
            ;;
            
        "action=release_coinslot_lock"*)
            # Release coinslot lock
            MAC=$(get_client_mac)
            release_coinslot_lock "$MAC"
            json_response "{\"success\": true, \"released\": true, \"mac\": \"$MAC\"}"
            ;;
    esac
}

# Check if it's an API call
echo "$QUERY_STRING" | grep -q "action=" && handle_api

# If not API, serve HTML Landing Page
# Refactored to serve from external file for easier editing
if [ -f /www/portal.html ]; then
    cat /www/portal.html
else
    # Fallback default portal if file missing
    cat << 'HTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>PisoWifi Portal</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font-family: sans-serif; text-align: center; padding: 20px; background: #f4f4f4; background-image: url('/bg.jpg'); background-size: cover; background-position: center; min-height: 100vh; }
.container { background: rgba(255,255,255,0.95); max-width: 500px; margin: 0 auto; padding: 20px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.3); }
button { padding: 15px 30px; font-size: 1.2em; color: white; border: none; border-radius: 5px; cursor: pointer; margin: 10px; width: 100%; transition: transform 0.1s; }
button:active { transform: scale(0.98); }
.btn-blue { background: #007bff; }
.btn-green { background: #28a745; }
.btn-red { background: #dc3545; }
.modal { display: none; position: fixed; z-index: 1; left: 0; top: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); }
.modal-content { background: #fff; margin: 20% auto; padding: 20px; width: 80%; max-width: 400px; border-radius: 10px; }
</style>
</head>
<body>

<div class="container">
    <h1>NEXI-FI PISOWIFI</h1>
    <div id="loading">Loading...</div>
    
    <!-- Permanent Device Info -->
    <div id="device-info" style="background:#e9ecef; padding:10px; margin-bottom:15px; border-radius:5px; font-size:0.9em; text-align:left;">
        <strong>Device Info:</strong><br>
        MAC: <span id="info-mac">Loading...</span><br>
        IP: <span id="info-ip">Loading...</span>
    </div>

    <div id="login-section" style="display:none;">
        <p>Insert Coin to Connect</p>
        <button onclick="playAudio('insert'); startCoin()" class="btn-green">INSERT COIN</button>
        <button onclick="openRates()" class="btn-blue">RATES</button>
    </div>
    
    <div id="resume-section" style="display:none;">
        <h2>Session Paused</h2>
        <p>Time Remaining: <strong id="paused-time"></strong></p>
        <button onclick="resumeTime()" class="btn-blue">RESUME TIME</button>
    </div>
    
    <div id="connected-section" style="display:none;">
        <h2>Connected!</h2>
        <p>MAC: <span id="client-mac"></span></p>
        <p>Time Remaining: <strong id="time-remaining">Loading...</strong></p>
        <p id="internet-status" style="font-size: 0.8em; color: gray;">Checking internet...</p>
        
        <div style="display:flex; gap:10px; margin-bottom:10px;">
             <!-- Add Time Button (Green) -->
             <button onclick="playAudio('insert'); startCoin()" class="btn-green">ADD TIME</button>
             <!-- Pause Button (Yellow) -->
             <button onclick="pauseTime()" class="btn-blue" style="background:#f59e0b;">PAUSE</button>
        </div>

        <button onclick="openRates()" class="btn-blue">RATES</button>
        
        <button onclick="logout()" class="btn-red">Logout</button>
    </div>
</div>

<div id="coin-modal" class="modal">
    <div class="modal-content">
        <h2>Insert Coin</h2>
        <p>Press WPS Button on Router</p>
        <div style="font-size: 1.5em; margin: 20px;">
            <span id="coin-count">0</span> Pesos<br>
            <span id="coin-time">0</span> Minutes
        </div>
        <button id="connect-btn" onclick="playAudio('connect'); connect()" class="btn-blue" style="display:none;">START INTERNET</button>
        <button onclick="closeModal()" style="background:none; color:red; margin-top:10px;">Cancel</button>
    </div>
</div>

<div id="rates-modal" class="modal">
    <div class="modal-content">
        <h2>Rates</h2>
        <div id="rates-body">Loading...</div>
        <button onclick="closeRates()" style="background:none; color:red; margin-top:10px;">Close</button>
    </div>
</div>

<!-- Audio Elements -->
<audio id="audio-insert" src="/insert.mp3"></audio>
<audio id="audio-connect" src="/connected.mp3"></audio>

<script>
var apiUrl = "/cgi-bin/pisowifi";
var interval;
var timerInterval;
var timeLeft = 0;

function getSessionId() {
    var sid = localStorage.getItem('pisowifi_sid');
    var expiry = localStorage.getItem('pisowifi_sid_expiry');
    var now = Date.now();
    if (!sid || !expiry) return "";
    if (now > parseInt(expiry)) {
        localStorage.removeItem('pisowifi_sid');
        localStorage.removeItem('pisowifi_sid_expiry');
        return "";
    }
    return sid;
}

function generateSessionId() {
    return 'SID-' + Math.random().toString(36).substr(2, 9) + '-' + Date.now();
}

function saveSessionId(sid) {
    var now = Date.now();
    var oneYear = 365 * 24 * 60 * 60 * 1000;
    localStorage.setItem('pisowifi_sid', sid);
    localStorage.setItem('pisowifi_sid_expiry', (now + oneYear).toString());
}

function getSidParam() {
    var sid = getSessionId();
    return sid ? ("&sid=" + encodeURIComponent(sid)) : "";
}

function openRates() {
    document.getElementById("rates-modal").style.display = "block";
    loadRates();
}

function closeRates() {
    document.getElementById("rates-modal").style.display = "none";
}

function loadRates() {
    fetch(apiUrl + "?action=rates" + getSidParam())
    .then(r => r.json())
    .then(d => {
        var el = document.getElementById("rates-body");
        if(!el) return;
        if(!d || !d.rates || !d.rates.length) { el.innerHTML = "<div>No rates set.</div>"; return; }
        var html = "<div style='margin-top:10px; text-align:left;'>";
        d.rates.forEach(function(x){
            html += "<div style='display:flex; justify-content:space-between; padding:10px; background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px; margin-bottom:8px;'><strong>₱" + x.amount + "</strong><span>" + x.minutes + " minutes</span></div>";
        });
        html += "</div>";
        el.innerHTML = html;
    })
    .catch(() => {
        var el = document.getElementById("rates-body");
        if(el) el.innerHTML = "<div>Failed to load rates.</div>";
    });
}

function playAudio(type) {
    try {
        // Stop any currently playing audio first
        stopAudio();
        
        var audio = document.getElementById("audio-" + type);
        if(audio) {
            audio.currentTime = 0; // Reset to start
            audio.play().catch(e => console.log("Audio play failed", e));
        }
    } catch(e) { console.error(e); }
}

function stopAudio() {
    try {
        var sounds = document.querySelectorAll('audio');
        sounds.forEach(function(sound) {
            sound.pause();
            sound.currentTime = 0;
        });
    } catch(e) { console.error(e); }
}

function formatTime(s) {
    if(s<=0) return "Expired";
    
    var d = Math.floor(s/86400); // Days
    var h = Math.floor((s%86400)/3600); // Hours
    var m = Math.floor((s%3600)/60); // Minutes
    var sec = s%60; // Seconds
    
    var timeStr = "";
    if(d > 0) timeStr += d + "d ";
    if(h > 0) timeStr += h + "h ";
    if(m > 0) timeStr += m + "m ";
    timeStr += sec + "s";
    
    return timeStr.trim();
}

function startTimer() {
    if(timerInterval) clearInterval(timerInterval);
    
    timerInterval = setInterval(function() {
        if(timeLeft > 0) {
            timeLeft--;
            document.getElementById("time-remaining").innerText = formatTime(timeLeft);
            if(document.getElementById("paused-time")) {
                 // Only update paused time if actively paused? No, paused time is static.
                 // This timer is for connected state.
            }
        } else {
            clearInterval(timerInterval);
            checkStatus(); // Refresh status when time expires
        }
    }, 1000);
}

function checkInternet() {
    var img = new Image();
    var now = new Date().getTime();
    img.src = "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?t=" + now;
    
    img.onload = function() {
        var el = document.getElementById("internet-status");
        if(el) {
            el.innerText = "Internet: ONLINE ✅";
            el.style.color = "green";
        }
        fetch(apiUrl + "?action=log_internet&status=ONLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN") + getSidParam());
    };
    
    img.onerror = function() {
        var el = document.getElementById("internet-status");
        if(el) {
            el.innerText = "Internet: OFFLINE ❌ (Check Connection)";
            el.style.color = "red";
        }
        fetch(apiUrl + "?action=log_internet&status=OFFLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN") + getSidParam());
    };
}

function checkStatus() {
    fetch(apiUrl + "?action=status" + getSidParam())
    .then(r => {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
    })
    .then(data => {
        if(data.mac) document.getElementById("info-mac").innerText = data.mac;
        if(data.ip) document.getElementById("info-ip").innerText = data.ip;
        
        document.getElementById("loading").style.display = "none";
        
        if(data.authenticated === "true") {
            document.getElementById("login-section").style.display = "none";
            document.getElementById("resume-section").style.display = "none";
            document.getElementById("connected-section").style.display = "block";
            
            // Update global timeLeft variable
            timeLeft = parseInt(data.time_remaining);
            document.getElementById("time-remaining").innerText = formatTime(timeLeft);
            if(data.mac) document.getElementById("client-mac").innerText = data.mac;
            
            // Start the countdown
            startTimer();
            
            checkInternet();
            setTimeout(checkStatus, 5000); 
            
        } else if(data.authenticated === "paused") {
            document.getElementById("login-section").style.display = "none";
            document.getElementById("connected-section").style.display = "none";
            document.getElementById("resume-section").style.display = "block";
            
            // Paused time is static
            document.getElementById("paused-time").innerText = formatTime(data.time_remaining);
            if(timerInterval) clearInterval(timerInterval); // Stop timer if paused
            
            setTimeout(checkStatus, 10000);
            
        } else {
            document.getElementById("login-section").style.display = "block";
            document.getElementById("resume-section").style.display = "none";
            document.getElementById("connected-section").style.display = "none";
            if(timerInterval) clearInterval(timerInterval);
        }
    })
    .catch(err => {
        console.error("Status check failed:", err);
        document.getElementById("loading").style.display = "none";
        document.getElementById("login-section").style.display = "block";
    });
}

function pauseTime() {
    if(!confirm("Pause Internet? You can resume later.")) return;
    fetch(apiUrl + "?action=pause" + getSidParam())
    .then(r => r.json())
    .then(data => {
        if(data.status === "paused") {
            alert("Internet Paused. Time saved: " + formatTime(data.remaining));
            checkStatus();
        } else {
            alert("Error: " + (data.error || "Failed to pause"));
        }
    })
    .catch(err => console.error(err));
}

function resumeTime() {
    fetch(apiUrl + "?action=resume" + getSidParam())
    .then(r => r.json())
    .then(data => {
        if(data.status === "resumed") {
            checkStatus();
        } else {
            alert("Error: " + (data.error || "Failed to resume"));
        }
    })
    .catch(err => console.error(err));
}

function startCoin() {
    // Try to acquire lock and start coin session in one atomic operation
    fetch(apiUrl + "?action=start_coin" + getSidParam())
    .then(r => r.json())
    .then(data => {
        if(data.status === "started" && data.lock_acquired) {
            // Successfully acquired lock - show modal
            document.getElementById("coin-modal").style.display = "block";
            document.getElementById("coin-count").innerText = "0";
            document.getElementById("coin-time").innerText = "0";
            document.getElementById("connect-btn").style.display = "none";
                
                if(interval) clearInterval(interval);
                interval = setInterval(() => {
                    fetch(apiUrl + "?action=check_coin" + getSidParam())
                    .then(r => r.json())
                    .then(d => {
                        document.getElementById("coin-count").innerText = d.count;
                        document.getElementById("coin-time").innerText = d.minutes;
                        if(d.count > 0) document.getElementById("connect-btn").style.display = "block";
                    })
                    .catch(err => console.error("Coin check failed:", err));
                }, 1000);
            } else if(data.error && data.error.includes("locked by another device")) {
                // Coinslot is locked by another device
                alert("Coinslot is currently in use by another device. Please try again later.");
            } else if(data.error) {
                alert(data.error + " (Device: " + data.locked_by_mac + ")");
            } else {
                alert("Failed to start coin session. Please try again.");
            }
        })
        .catch(err => {
            console.error("Start coin failed:", err);
            alert("Failed to start coin session. Please refresh the page.");
        });
}

function connect() {
    // Stop Insert Coin Audio immediately
    stopAudio();
    playAudio('connect');

    var existingSid = getSessionId();
    var candidateSid = existingSid || generateSessionId();
    var sidParam = "&sid=" + encodeURIComponent(candidateSid);

    fetch(apiUrl + "?action=connect" + sidParam)
    .then(r => r.json())
    .then(data => {
        closeModal();
        if (data.status === "connected") {
            if (!existingSid) saveSessionId(data.sid || candidateSid);
            checkStatus();
            if (data.redirect_url) {
                setTimeout(() => {
                    window.location.href = data.redirect_url;
                }, 2000);
            }
        } else {
            alert(data.error || "Connection failed");
        }
    })
    .catch(err => {
        console.error("Connect failed:", err);
        alert("Failed to connect. Please try again.");
    });
}

function logout() {
    fetch(apiUrl + "?action=logout" + getSidParam())
    .then(r => r.json())
    .then(() => checkStatus())
    .catch(err => {
        console.error("Logout failed:", err);
        checkStatus();
    });
}

function closeModal() {
    document.getElementById("coin-modal").style.display = "none";
    if(interval) clearInterval(interval);
    stopAudio(); // Stop audio when closing modal
    
    // Release coinslot lock when closing modal
    fetch(apiUrl + "?action=release_coinslot_lock" + getSidParam())
    .then(r => r.json())
    .then(data => {
        console.log("Coinslot lock released:", data);
    })
    .catch(err => console.error("Failed to release lock:", err));
}

function checkCoinCount() {
    fetch(apiUrl + "?action=check_coin")
    .then(r => r.json())
    .then(data => {
        document.getElementById("coin-count").innerText = data.count;
        document.getElementById("coin-time").innerText = data.minutes;
        if(data.count > 0) {
            document.getElementById("connect-btn").style.display = "block";
        }
    })
    .catch(err => console.error("Coin check failed:", err));
}

function testDNS() {
    fetch(apiUrl + "?action=test_dns")
    .then(r => r.json())
    .then(data => {
        console.log("DNS Test Results:", data);
    })
    .catch(err => console.error("DNS test failed:", err));
}

setTimeout(testDNS, 3000);
checkStatus();
</script>

</body>
</html>
HTML
fi
EOF
chmod +x /www/cgi-bin/pisowifi

# 3.5 Create Admin Panel CGI
echo "Creating Admin Panel..."
cat << 'EOF' > /www/cgi-bin/admin
#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
BB="/bin/busybox"
[ -x "$BB" ] || BB=$(command -v busybox)

# Define robust command aliases
if [ -x "$BB" ]; then
    HEAD="$BB head"
    CUT="$BB cut"
    GREP="$BB grep"
    SED="$BB sed"
    TR="$BB tr"
    CAT="$BB cat"
    AWK="$BB awk"
    DATE="$BB date"
    LOGGER="$BB logger"
else
    HEAD="head"
    CUT="cut"
    GREP="grep"
    SED="sed"
    TR="tr"
    CAT="cat"
    AWK="awk"
    DATE="date"
    LOGGER="logger"
fi

UCI="/sbin/uci"
log_license() {
    $LOGGER -t pisowifi_license "$@"
}

sql_escape() {
    printf "%s" "$1" | $SED "s/'/''/g"
}

# Enable debugging to log errors to system log
# set -x

# --- RAW UPLOAD HANDLER (Bypass generic POST processing for speed/RAM) ---
# Check if query string contains upload_raw action
if [ "$REQUEST_METHOD" = "POST" ] && echo "$QUERY_STRING" | $GREP -q "action=upload_raw"; then
    # Extract filename safely
    FILENAME=$(echo "$QUERY_STRING" | $GREP -o "filename=[^&]*" | $CUT -d= -f2)
    
    # Security Validation: Only allow specific files
    if [ "$FILENAME" = "bg.jpg" ] || [ "$FILENAME" = "insert.mp3" ] || [ "$FILENAME" = "connected.mp3" ]; then
        
        # Stream stdin directly to file (Low RAM usage)
        if [ -n "$CONTENT_LENGTH" ]; then
            # If head -c is available (BusyBox usually has it)
            if [ -x "$BB" ]; then
                "$BB" head -c "$CONTENT_LENGTH" > "/www/$FILENAME" 2>/dev/null || cat > "/www/$FILENAME"
            else
                head -c "$CONTENT_LENGTH" > "/www/$FILENAME" 2>/dev/null || cat > "/www/$FILENAME"
            fi
        else
            cat > "/www/$FILENAME"
        fi
        
        # Return success
        echo "Status: 200 OK"
        echo "Content-type: application/json"
        echo ""
        echo "{\"success\": true}"
        exit 0
    else
        echo "Status: 400 Bad Request"
        echo ""
        echo "Invalid filename"
        exit 0
    fi
fi

# Session Helper
SESSION_COOKIE=$(echo "$HTTP_COOKIE" | $GREP -o "session=[^;]*" | $CUT -d= -f2)
ADMIN_PASS=$($UCI get pisowifi.settings.admin_password 2>/dev/null || echo "admin")
DB_FILE="/etc/pisowifi/pisowifi.db"

# Initialize SQLite Database Tables
[ -d /etc/pisowifi ] || mkdir -p /etc/pisowifi
if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS license (id INTEGER PRIMARY KEY, status TEXT, license_key TEXT, expires_at TEXT, vendor_uuid TEXT, hardware_id TEXT, valid INTEGER, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null
fi

# Simple Login Check
check_auth() {
    if [ "$SESSION_COOKIE" != "logged_in_secret_token" ]; then
        return 1
    fi
    return 0
}

# --- POST REQUEST HANDLER ---
if [ "$REQUEST_METHOD" = "POST" ]; then
    # Use temporary file instead of variable to handle large uploads
    POST_FILE="/tmp/post_data_$$"
    
    if [ -n "$CONTENT_LENGTH" ]; then
        # Read exactly CONTENT_LENGTH bytes
        if [ -x "$BB" ]; then
            "$BB" head -c "$CONTENT_LENGTH" > "$POST_FILE"
        else
            head -c "$CONTENT_LENGTH" > "$POST_FILE"
        fi
    else
        cat > "$POST_FILE"
    fi
    
    # Helper to get POST var from file
    # Uses grep and cut, handles basic URL decoding
    get_post_var() {
        # Grep for var name, then decode
        # Using grep -a (text mode) in case of binary data
        # We look for $1= then characters that are NOT & (param separator)
        VAL=$($GREP -a -o "$1=[^&]*" "$POST_FILE" 2>/dev/null | $HEAD -1 | $CUT -d= -f2-)
        [ -z "$VAL" ] && return
        
        # Decode URL encoding:
        # 1. Replace + with space
        # 2. Replace %XX with \xXX for printf %b
        DECODED=$(echo "$VAL" | $SED 's/+/ /g; s/%\([0-9a-fA-F]\{2\}\)/\\x\1/g')
        # Use printf %b to interpret \xXX as characters
        printf "%b" "$DECODED"
    }

    sql_escape() {
        printf "%s" "$1" | $SED "s/'/''/g"
    }

    cleanup_old_supa_tmp() {
        command -v find >/dev/null 2>&1 || return 0
        find /tmp -maxdepth 1 -type f \( -name 'pisowifi_supa_*' -o -name 'pisowifi_supa_err_*' \) -mmin +60 -delete 2>/dev/null || true
    }

    supa_request() {
        cleanup_old_supa_tmp
        URL="$1"
        KEY="$2"
        PATH="$3"
        SUPA_HTTP_CODE=""
        SUPA_CURL_EXIT="0"
        SUPA_CURL_ERR=""
        SUPA_BODY=""
        CURL_BIN="/usr/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN="/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN=""
        if [ -z "$CURL_BIN" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_EXIT="127"
            SUPA_CURL_ERR="curl_missing"
            return
        fi
        TMP="/tmp/pisowifi_supa_$$"
        ERR="/tmp/pisowifi_supa_err_$$"
        SUPA_HTTP_CODE=$("$CURL_BIN" -sS -o "$TMP" -w "%{http_code}" --connect-timeout 8 --max-time 15 -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Accept: application/json" -H "Accept-Encoding: identity" "$URL/rest/v1/$PATH" 2>"$ERR")
        SUPA_CURL_EXIT="$?"
        if [ "$SUPA_CURL_EXIT" != "0" ] || [ -z "$SUPA_HTTP_CODE" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_ERR=$($HEAD -1 "$ERR" 2>/dev/null | $TR -d '\r' | $TR '\n' ' ')
            [ -z "$SUPA_CURL_ERR" ] && SUPA_CURL_ERR="curl_failed"
        fi
        SUPA_BODY=$($CAT "$TMP" 2>/dev/null)
        $CAT /dev/null > "$TMP" 2>/dev/null
        rm -f "$TMP" "$ERR" 2>/dev/null || true
    }

    supa_patch() {
        cleanup_old_supa_tmp
        URL="$1"
        KEY="$2"
        PATH="$3"
        BODY="$4"
        SUPA_HTTP_CODE=""
        SUPA_CURL_EXIT="0"
        SUPA_CURL_ERR=""
        SUPA_BODY=""
        CURL_BIN="/usr/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN="/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN=""
        if [ -z "$CURL_BIN" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_EXIT="127"
            SUPA_CURL_ERR="curl_missing"
            return
        fi
        TMP="/tmp/pisowifi_supa_$$"
        ERR="/tmp/pisowifi_supa_err_$$"
        SUPA_HTTP_CODE=$("$CURL_BIN" -sS -o "$TMP" -w "%{http_code}" --connect-timeout 8 --max-time 15 -X PATCH -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Accept: application/json" -H "Accept-Encoding: identity" -H "Content-Type: application/json" -H "Prefer: return=representation" --data "$BODY" "$URL/rest/v1/$PATH" 2>"$ERR")
        SUPA_CURL_EXIT="$?"
        if [ "$SUPA_CURL_EXIT" != "0" ] || [ -z "$SUPA_HTTP_CODE" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_ERR=$($HEAD -1 "$ERR" 2>/dev/null | $TR -d '\r' | $TR '\n' ' ')
            [ -z "$SUPA_CURL_ERR" ] && SUPA_CURL_ERR="curl_failed"
        fi
        SUPA_BODY=$($CAT "$TMP" 2>/dev/null)
        $CAT /dev/null > "$TMP" 2>/dev/null
        rm -f "$TMP" "$ERR" 2>/dev/null || true
    }

    supa_rpc() {
        cleanup_old_supa_tmp
        URL="$1"
        KEY="$2"
        FN="$3"
        BODY="$4"
        SUPA_HTTP_CODE=""
        SUPA_CURL_EXIT="0"
        SUPA_CURL_ERR=""
        SUPA_BODY=""
        CURL_BIN="/usr/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN="/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN=""
        if [ -z "$CURL_BIN" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_EXIT="127"
            SUPA_CURL_ERR="curl_missing"
            return
        fi
        TMP="/tmp/pisowifi_supa_$$"
        ERR="/tmp/pisowifi_supa_err_$$"
        SUPA_HTTP_CODE=$("$CURL_BIN" -sS -o "$TMP" -w "%{http_code}" --connect-timeout 8 --max-time 15 -X POST -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Accept: application/json" -H "Accept-Encoding: identity" -H "Content-Type: application/json" --data "$BODY" "$URL/rest/v1/rpc/$FN" 2>"$ERR")
        SUPA_CURL_EXIT="$?"
        if [ "$SUPA_CURL_EXIT" != "0" ] || [ -z "$SUPA_HTTP_CODE" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_ERR=$($HEAD -1 "$ERR" 2>/dev/null | $TR -d '\r' | $TR '\n' ' ')
            [ -z "$SUPA_CURL_ERR" ] && SUPA_CURL_ERR="curl_failed"
        fi
        SUPA_BODY=$($CAT "$TMP" 2>/dev/null)
        $CAT /dev/null > "$TMP" 2>/dev/null
        rm -f "$TMP" "$ERR" 2>/dev/null || true
    }

    supa_insert() {
        cleanup_old_supa_tmp
        URL="$1"
        KEY="$2"
        PATH="$3"
        BODY="$4"
        SUPA_HTTP_CODE=""
        SUPA_CURL_EXIT="0"
        SUPA_CURL_ERR=""
        SUPA_BODY=""
        CURL_BIN="/usr/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN="/bin/curl"
        [ -x "$CURL_BIN" ] || CURL_BIN=""
        if [ -z "$CURL_BIN" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_EXIT="127"
            SUPA_CURL_ERR="curl_missing"
            return
        fi
        TMP="/tmp/pisowifi_supa_$$"
        ERR="/tmp/pisowifi_supa_err_$$"
        SUPA_HTTP_CODE=$("$CURL_BIN" -sS -o "$TMP" -w "%{http_code}" --connect-timeout 8 --max-time 15 -X POST -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Accept: application/json" -H "Accept-Encoding: identity" -H "Content-Type: application/json" -H "Prefer: return=representation" --data "$BODY" "$URL/rest/v1/$PATH" 2>"$ERR")
        SUPA_CURL_EXIT="$?"
        if [ "$SUPA_CURL_EXIT" != "0" ] || [ -z "$SUPA_HTTP_CODE" ]; then
            SUPA_HTTP_CODE="0"
            SUPA_CURL_ERR=$($HEAD -1 "$ERR" 2>/dev/null | $TR -d '\r' | $TR '\n' ' ')
            [ -z "$SUPA_CURL_ERR" ] && SUPA_CURL_ERR="curl_failed"
        fi
        SUPA_BODY=$($CAT "$TMP" 2>/dev/null)
        $CAT /dev/null > "$TMP" 2>/dev/null
        rm -f "$TMP" "$ERR" 2>/dev/null || true
    }

    json_first() {
        FIELD="$1"
        if command -v jsonfilter >/dev/null 2>&1; then
            jsonfilter -e "@[0].$FIELD" 2>/dev/null
        else
            # Direct extraction using grep and sed
            # For boolean true/false values
            if echo "$SUPA_BODY" | $GREP -q "\"$FIELD\":true"; then
                echo "true"
                return
            elif echo "$SUPA_BODY" | $GREP -q "\"$FIELD\":false"; then
                echo "false"
                return
            fi
            
            # For null values
            if echo "$SUPA_BODY" | $GREP -q "\"$FIELD\":null"; then
                echo "null"
                return
            fi
            
            # For string values (quoted)
            STRING_VALUE=$(echo "$SUPA_BODY" | $SED -n "s/.*\"$FIELD\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" | $HEAD -1)
            if [ -n "$STRING_VALUE" ]; then
                echo "$STRING_VALUE"
                return
            fi
            
            # For numeric values
            NUMBER_VALUE=$(echo "$SUPA_BODY" | $SED -n "s/.*\"$FIELD\":[[:space:]]*\([0-9]*\).*/\1/p" | $HEAD -1)
            if [ -n "$NUMBER_VALUE" ]; then
                echo "$NUMBER_VALUE"
                return
            fi
        fi
    }

    load_supabase_env() {
        [ -f /etc/pisowifi/supabase.env ] || return 1
        FILE_URL=$($GREP -m1 '^SUPABASE_URL=' /etc/pisowifi/supabase.env 2>/dev/null | $CUT -d= -f2- | $TR -d '\r')
        FILE_KEY=$($GREP -m1 '^SUPABASE_ANON_KEY=' /etc/pisowifi/supabase.env 2>/dev/null | $CUT -d= -f2- | $TR -d '\r')
        FILE_URL=$(echo "$FILE_URL" | $SED 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')
        FILE_KEY=$(echo "$FILE_KEY" | $SED 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')
        [ -z "$FILE_URL" ] && return 1
        [ -z "$FILE_KEY" ] && return 1
        "$UCI" set pisowifi.license=license
        "$UCI" set pisowifi.license.supabase_url="$FILE_URL"
        "$UCI" set pisowifi.license.supabase_key="$FILE_KEY"
        "$UCI" commit pisowifi
        return 0
    }

    ACTION=$(get_post_var "action")
    PASS=$(get_post_var "password")
    
    # Cleanup trap
    trap "[ -x \"$BB\" ] && \"$BB\" rm -f \"$POST_FILE\" 2>/dev/null; rm -f \"$POST_FILE\" 2>/dev/null" EXIT
    
    if [ -n "$PASS" ]; then
        if [ "$PASS" = "$ADMIN_PASS" ]; then
            echo "Set-Cookie: session=logged_in_secret_token; Path=/; Max-Age=3600"
            echo "Status: 302 Found"
            echo "Location: /cgi-bin/admin?tab=dashboard"
            echo ""
            exit 0
        else
            echo "Status: 302 Found"
            echo "Location: /cgi-bin/admin?error=invalid"
            echo ""
            exit 0
        fi
    fi
    
    if [ "$ACTION" = "logout" ]; then
        echo "Set-Cookie: session=; Path=/; Max-Age=0"
        echo "Status: 302 Found"
        echo "Location: /cgi-bin/admin"
        echo ""
        exit 0
    fi
    
    if check_auth; then
        if [ "$ACTION" = "activate_license" ] || [ "$ACTION" = "license_check" ]; then
             SUPA_URL=$("$UCI" get pisowifi.license.supabase_url 2>/dev/null)
             SUPA_KEY=$("$UCI" get pisowifi.license.supabase_key 2>/dev/null)
             NOW_TS=$($DATE +%s)
             OPENWRT_TABLE="pisowifi_openwrt"

             # Get Device ID
             HW_MAC=$($CAT /sys/class/net/br-lan/address 2>/dev/null || $CAT /sys/class/net/eth0/address 2>/dev/null || echo "")
             HW_MAC=$(printf "%s" "$HW_MAC" | $TR -d ':' | $TR 'a-z' 'A-Z')
             
             HW_HEX="$HW_MAC"
             if command -v md5sum >/dev/null 2>&1 && [ -n "$HW_MAC" ]; then
                 HW_HEX=$(echo -n "$HW_MAC" | md5sum 2>/dev/null | awk '{print toupper(substr($1,1,16))}')
             fi
             HARDWARE_ID="CPU-$HW_HEX"

             if [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ]; then
                 load_supabase_env >/dev/null 2>&1 || true
                 SUPA_URL=$("$UCI" get pisowifi.license.supabase_url 2>/dev/null)
                 SUPA_KEY=$("$UCI" get pisowifi.license.supabase_key 2>/dev/null)
             fi

             if [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ]; then
                 echo "Status: 302 Found"
                 echo "Location: /cgi-bin/admin?tab=settings&msg=license_missing_supabase"
                 echo ""
                 exit 0
             fi

             # First, check by hardware_id
             supa_request "$SUPA_URL" "$SUPA_KEY" "$OPENWRT_TABLE?select=id,status,expires_at,vendor_uuid,vendor_id,license_key&hardware_id=eq.$HARDWARE_ID&limit=1"
             RESP="$SUPA_BODY"
             LAST_CODE="$SUPA_HTTP_CODE"
             log_license "Check HW: $HARDWARE_ID code=$LAST_CODE"

             FOUND_BY_HW=0
             if [ "$LAST_CODE" = "200" ] && echo "$RESP" | $GREP -q '"id"'; then
                 FOUND_BY_HW=1
                 log_license "Found license for HW"
             fi

             if [ "$FOUND_BY_HW" = "0" ] && [ "$ACTION" = "license_check" ]; then
                 # No license for this HW, initiate 7-day trial
                 NOW_SEC=$($DATE +%s)
                 EXP_SEC=$((NOW_SEC + 604800)) # 7 days
                 EXP_DATE=$($DATE -u -d "@$EXP_SEC" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || $DATE -u -r "$EXP_SEC" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
                 
                 # Fallback if date command fails to format
                 [ -z "$EXP_DATE" ] && EXP_DATE=$(printf "%s" "$EXP_SEC")
                 
                 TRIAL_BODY=$(printf '{"hardware_id":"%s","status":"trial","expires_at":"%s"}' "$HARDWARE_ID" "$EXP_DATE")
                 log_license "Creating trial: $TRIAL_BODY"
                 supa_insert "$SUPA_URL" "$SUPA_KEY" "$OPENWRT_TABLE" "$TRIAL_BODY"
                 RESP="$SUPA_BODY"
                 LAST_CODE="$SUPA_HTTP_CODE"
                 log_license "Trial creation code: $LAST_CODE"
                 if [ "$LAST_CODE" = "201" ] || [ "$LAST_CODE" = "200" ]; then
                     FOUND_BY_HW=1
                 fi
             fi

             # If activating, and not found by HW, check by License Key
             if [ "$ACTION" = "activate_license" ] && [ "$FOUND_BY_HW" = "0" ]; then
                 LIC_KEY=$(get_post_var "license_key")
                 if [ -n "$LIC_KEY" ]; then
                     supa_request "$SUPA_URL" "$SUPA_KEY" "$OPENWRT_TABLE?select=id,status,expires_at,vendor_uuid,vendor_id,license_key,hardware_id&license_key=ilike.$LIC_KEY&limit=1"
                     RESP="$SUPA_BODY"
                     LAST_CODE="$SUPA_HTTP_CODE"
                     if [ "$LAST_CODE" = "200" ] && echo "$RESP" | $GREP -q '"id"'; then
                         # Found license key, check if already bound
                         BOUND_HW=$(echo "$RESP" | json_first "hardware_id")
                         if [ -z "$BOUND_HW" ] || [ "$BOUND_HW" = "null" ]; then
                             # Bind it
                             PATCH_BODY=$(printf '{"hardware_id":"%s","activated_at":"%s","status":"active"}' "$HARDWARE_ID" "$($DATE -Iseconds 2>/dev/null || $DATE +%Y-%m-%dT%H:%M:%SZ)")
                             supa_patch "$SUPA_URL" "$SUPA_KEY" "$OPENWRT_TABLE?license_key=ilike.$LIC_KEY" "$PATCH_BODY"
                             # Refresh data
                             supa_request "$SUPA_URL" "$SUPA_KEY" "$OPENWRT_TABLE?select=id,status,expires_at,vendor_uuid,vendor_id,license_key,hardware_id&license_key=ilike.$LIC_KEY&limit=1"
                             RESP="$SUPA_BODY"
                             FOUND_BY_HW=1
                         else
                             if [ "$BOUND_HW" != "$HARDWARE_ID" ]; then
                                 echo "Status: 302 Found"
                                 echo "Location: /cgi-bin/admin?tab=settings&msg=license_hw_mismatch"
                                 echo ""
                                 exit 0
                             fi
                             FOUND_BY_HW=1
                         fi
                     fi
                 fi
             fi

             if [ "$FOUND_BY_HW" = "1" ]; then
                 # Extract data and save to UCI
                 L_STATUS=$(echo "$RESP" | json_first "status")
                 L_EXPIRES=$(echo "$RESP" | json_first "expires_at")
                 L_VENDOR=$(echo "$RESP" | json_first "vendor_id")
                 [ -z "$L_VENDOR" ] || [ "$L_VENDOR" = "null" ] && L_VENDOR=$(echo "$RESP" | json_first "vendor_uuid")
                 L_KEY=$(echo "$RESP" | json_first "license_key")
                 
                 "$UCI" set pisowifi.license=license
                 "$UCI" set pisowifi.license.status="$L_STATUS"
                 "$UCI" set pisowifi.license.expires_at="$L_EXPIRES"
                 "$UCI" set pisowifi.license.vendor_id="$L_VENDOR"
                 "$UCI" set pisowifi.license.license_key="$L_KEY"
                 "$UCI" set pisowifi.license.hardware_id="$HARDWARE_ID"
                 "$UCI" set pisowifi.license.valid=1
                 [ "$L_STATUS" = "expired" ] && "$UCI" set pisowifi.license.valid=0
                 "$UCI" commit pisowifi

                 # Save to SQLite for persistence
                 L_VALID_INT=1
                 [ "$L_STATUS" = "expired" ] && L_VALID_INT=0
                 sqlite3 "$DB_FILE" "DELETE FROM license; INSERT INTO license (status, license_key, expires_at, vendor_uuid, hardware_id, valid) VALUES ('$L_STATUS', '$L_KEY', '$L_EXPIRES', '$L_VENDOR', '$HARDWARE_ID', $L_VALID_INT);" 2>/dev/null

                 # Update/Insert into vendors table in Supabase
                 if [ "$L_STATUS" = "active" ]; then
                     MACHINE_NAME=$(cat /tmp/sysinfo/model 2>/dev/null || echo "PisoWifi-Machine")
                     
                     # Ensure valid UUID for vendor_id, or send null
                     V_ID_JSON="null"
                     if [ -n "$L_VENDOR" ] && [ "$L_VENDOR" != "null" ]; then
                         V_ID_JSON=$(printf "\"%s\"" "$L_VENDOR")
                     fi

                     VENDOR_BODY=$(printf '{"hardware_id":"%s","machine_name":"%s","vendor_id":%s,"license_key":"%s","is_licensed":true,"activated_at":"%s","status":"online"}' "$HARDWARE_ID" "$MACHINE_NAME" "$V_ID_JSON" "$L_KEY" "$($DATE -u +"%Y-%m-%dT%H:%M:%SZ")")
                     
                     log_license "Syncing to vendors: $VENDOR_BODY"
                     
                     # First check if exists
                     supa_request "$SUPA_URL" "$SUPA_KEY" "vendors?select=id&hardware_id=eq.$HARDWARE_ID&limit=1"
                     V_EXIST_RESP="$SUPA_BODY"
                     V_EXIST_CODE="$SUPA_HTTP_CODE"
                     
                     if [ "$V_EXIST_CODE" = "200" ] && echo "$V_EXIST_RESP" | $GREP -q '"id"'; then
                         log_license "Machine exists in vendors, patching..."
                         supa_patch "$SUPA_URL" "$SUPA_KEY" "vendors?hardware_id=eq.$HARDWARE_ID" "$VENDOR_BODY"
                     else
                         log_license "Machine missing in vendors, inserting..."
                         supa_insert "$SUPA_URL" "$SUPA_KEY" "vendors" "$VENDOR_BODY"
                     fi
                     log_license "Sync result code: $SUPA_HTTP_CODE"
                 fi
                 
                 echo "Status: 302 Found"
                 echo "Location: /cgi-bin/admin?tab=settings&msg=license_ok"
                 echo ""
                 exit 0
             else
                 echo "Status: 302 Found"
                 echo "Location: /cgi-bin/admin?tab=settings&msg=license_not_found"
                 echo ""
                 exit 0
             fi

        elif [ "$ACTION" = "clear_license" ]; then
             "$UCI" set pisowifi.license=license
             "$UCI" set pisowifi.license.status='inactive'
             "$UCI" set pisowifi.license.valid='0'
             "$UCI" set pisowifi.license.license_key=''
             "$UCI" set pisowifi.license.vendor_uuid=''
             "$UCI" set pisowifi.license.vendor_id=''
             "$UCI" set pisowifi.license.expires_at=''
             "$UCI" set pisowifi.license.hardware_id=''
             "$UCI" commit pisowifi

             # Clear SQLite
             sqlite3 "$DB_FILE" "DELETE FROM license;" 2>/dev/null

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=settings&msg=license_cleared"
             echo ""
             exit 0

        elif [ "$ACTION" = "clear_centralized_license" ]; then
             "$UCI" set pisowifi.license.centralized_key=''
             "$UCI" set pisowifi.license.centralized_vendor_id=''
             "$UCI" set pisowifi.license.centralized_status=''
             "$UCI" commit pisowifi

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_cleared"
             echo ""
             exit 0

        elif [ "$ACTION" = "activate_centralized_license" ]; then
             SUPA_URL=$("$UCI" get pisowifi.license.supabase_url 2>/dev/null)
             SUPA_KEY=$("$UCI" get pisowifi.license.supabase_key 2>/dev/null)
             SUPA_SERVICE_KEY=$("$UCI" get pisowifi.license.supabase_service_key 2>/dev/null)
             
             # DEBUG LOGGING
             echo "<!-- DEBUG: SUPA_URL=$SUPA_URL -->" >&2
             echo "<!-- DEBUG: SUPA_KEY length=${#SUPA_KEY} -->" >&2
             echo "<!-- DEBUG: SUPA_SERVICE_KEY available: $([ -n "$SUPA_SERVICE_KEY" ] && echo "YES" || echo "NO") -->" >&2
             
             HW_MAC=$($CAT /sys/class/net/br-lan/address 2>/dev/null || $CAT /sys/class/net/eth0/address 2>/dev/null || echo "")
             HW_MAC=$(printf "%s" "$HW_MAC" | $TR -d ':' | $TR 'a-z' 'A-Z')
             HW_HEX="$HW_MAC"
             if command -v md5sum >/dev/null 2>&1 && [ -n "$HW_MAC" ]; then
                 HW_HEX=$(echo -n "$HW_MAC" | md5sum 2>/dev/null | awk '{print toupper(substr($1,1,16))}')
             fi
             HARDWARE_ID="CPU-$HW_HEX"
             
             C_KEY=$(get_post_var "centralized_key")
             
             # DEBUG LOGGING
             echo "<!-- DEBUG: Received C_KEY=$C_KEY -->" >&2
             echo "<!-- DEBUG: HARDWARE_ID=$HARDWARE_ID -->" >&2
             
             if [ -n "$C_KEY" ]; then
                 # DEBUG: Test the regex pattern
                 echo "<!-- DEBUG: Testing regex pattern -->" >&2
                 if echo "$C_KEY" | $GREP -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
                     echo "<!-- DEBUG: Regex MATCHED -->" >&2
                     
                     # DEBUG: Log the database query
                     echo "<!-- DEBUG: Querying database with key: $C_KEY -->" >&2
                     echo "<!-- DEBUG: SUPA_URL=$SUPA_URL -->" >&2
                     echo "<!-- DEBUG: SUPA_KEY exists: $([ -n "$SUPA_KEY" ] && echo "YES" || echo "NO") -->" >&2
                     
                     # DEBUG: Show the exact REST API URL being called
                     FULL_QUERY="centralized_keys?select=id,vendor_id,is_active&key_value=ilike.$C_KEY&limit=1"
                     echo "<!-- DEBUG: FULL_QUERY=$FULL_QUERY -->" >&2
                     echo "<!-- DEBUG: ENCODED_QUERY=$(echo "$FULL_QUERY" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/?/%3F/g') -->" >&2
                     
                     supa_request "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id,vendor_id,is_active&key_value=ilike.$C_KEY&limit=1"
                     
                     # DEBUG: Log the response
                     echo "<!-- DEBUG: HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                     echo "<!-- DEBUG: RESPONSE_BODY=$SUPA_BODY -->" >&2
                     
                     # DEBUG: Enhanced JSON parsing test
                     echo "<!-- DEBUG: Testing JSON parsing... -->" >&2
                     echo "<!-- DEBUG: Raw SUPA_BODY: $SUPA_BODY -->" >&2
                     
                     # If anon key fails, try with service role key (if available)
                     if [ "$SUPA_HTTP_CODE" != "200" ] || ! echo "$SUPA_BODY" | $GREP -q '"id"'; then
                         if [ -n "$SUPA_SERVICE_KEY" ]; then
                             echo "<!-- DEBUG: Trying with service role key -->" >&2
                             supa_request "$SUPA_URL" "$SUPA_SERVICE_KEY" "centralized_keys?select=id,vendor_id,is_active&key_value=ilike.$C_KEY&limit=1"
                             echo "<!-- DEBUG: Service role HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                             echo "<!-- DEBUG: Service role RESPONSE_BODY=$SUPA_BODY -->" >&2
                         fi
                     fi
                     
                     if [ "$SUPA_HTTP_CODE" = "200" ] && echo "$SUPA_BODY" | $GREP -q '"id"'; then
                         # DEBUG: Test individual field parsing
                         C_VENDOR=$(echo "$SUPA_BODY" | json_first "vendor_id")
                         C_ACTIVE=$(echo "$SUPA_BODY" | json_first "is_active")
                         
                         echo "<!-- DEBUG: Parsed C_VENDOR='$C_VENDOR' -->" >&2
                         echo "<!-- DEBUG: Parsed C_ACTIVE='$C_ACTIVE' -->" >&2
                         
                         # Handle null vendor_id - convert to empty string
                         if [ "$C_VENDOR" = "null" ] || [ -z "$C_VENDOR" ]; then
                             C_VENDOR=""
                             echo "<!-- DEBUG: C_VENDOR was null, converted to empty string -->" >&2
                         fi
                         
                         # Handle boolean true/false properly
                         if [ "$C_ACTIVE" = "true" ]; then
                             # Accept key regardless of vendor_id value (even if null/empty)
                             "$UCI" set pisowifi.license.centralized_key="$C_KEY"
                             "$UCI" set pisowifi.license.centralized_vendor_id="$C_VENDOR"
                             "$UCI" set pisowifi.license.centralized_status="active"
                             "$UCI" commit pisowifi
                             
                             echo "Status: 302 Found"
                             echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_ok"
                             echo ""
                             exit 0
                         else
                             # DEBUG: Log why it failed
                             echo "<!-- DEBUG: Key found but not active or invalid response -->" >&2
                             echo "<!-- DEBUG: C_ACTIVE=$C_ACTIVE -->" >&2
                             echo "Status: 302 Found"
                             echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_failed"
                             echo ""
                             exit 0
                         fi
                     else
                         # DEBUG: Log database query failure
                         echo "<!-- DEBUG: Primary database query failed -->" >&2
                         echo "<!-- DEBUG: HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                         echo "<!-- DEBUG: Checking fallback table... -->" >&2
                         
                         # DEBUG: Show fallback query
                        FALLBACK_QUERY="pisowifi_openwrt?select=id,status,vendor_uuid&license_key=ilike.$C_KEY&limit=1"
                        echo "<!-- DEBUG: FALLBACK_QUERY=$FALLBACK_QUERY -->" >&2
                        
                        # Fallback: check pisowifi_openwrt table just in case they used that for centralized keys
                       supa_request "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id,status,vendor_uuid&license_key=ilike.$C_KEY&limit=1"
                       
                       # DEBUG: Log fallback response
                       echo "<!-- DEBUG: Fallback HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                       echo "<!-- DEBUG: Fallback RESPONSE_BODY=$SUPA_BODY -->" >&2
                       
                       # If anon key fails, try with service role key (if available)
                       if [ "$SUPA_HTTP_CODE" != "200" ] || ! echo "$SUPA_BODY" | $GREP -q '"id"'; then
                           if [ -n "$SUPA_SERVICE_KEY" ]; then
                               echo "<!-- DEBUG: Trying fallback with service role key -->" >&2
                               supa_request "$SUPA_URL" "$SUPA_SERVICE_KEY" "pisowifi_openwrt?select=id,status,vendor_uuid&license_key=ilike.$C_KEY&limit=1"
                               echo "<!-- DEBUG: Service role fallback HTTP_CODE=$SUPA_HTTP_CODE -->" >&2
                               echo "<!-- DEBUG: Service role fallback RESPONSE_BODY=$SUPA_BODY -->" >&2
                           fi
                       fi
                       
                       # DEBUG: Test if we can get ANY records from the tables
                       echo "<!-- DEBUG: Testing if tables exist... -->" >&2
                       supa_request "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id&limit=1"
                       echo "<!-- DEBUG: centralized_keys test: HTTP_CODE=$SUPA_HTTP_CODE, BODY=$SUPA_BODY -->" >&2
                       
                       # If anon key fails for table test, try service role
                       if [ "$SUPA_HTTP_CODE" != "200" ] && [ -n "$SUPA_SERVICE_KEY" ]; then
                           echo "<!-- DEBUG: Testing centralized_keys with service role -->" >&2
                           supa_request "$SUPA_URL" "$SUPA_SERVICE_KEY" "centralized_keys?select=id&limit=1"
                           echo "<!-- DEBUG: centralized_keys service role test: HTTP_CODE=$SUPA_HTTP_CODE, BODY=$SUPA_BODY -->" >&2
                       fi
                       
                       supa_request "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id&limit=1"
                       echo "<!-- DEBUG: pisowifi_openwrt test: HTTP_CODE=$SUPA_HTTP_CODE, BODY=$SUPA_BODY -->" >&2
                       
                       # If anon key fails for table test, try service role
                       if [ "$SUPA_HTTP_CODE" != "200" ] && [ -n "$SUPA_SERVICE_KEY" ]; then
                           echo "<!-- DEBUG: Testing pisowifi_openwrt with service role -->" >&2
                           supa_request "$SUPA_URL" "$SUPA_SERVICE_KEY" "pisowifi_openwrt?select=id&limit=1"
                           echo "<!-- DEBUG: pisowifi_openwrt service role test: HTTP_CODE=$SUPA_HTTP_CODE, BODY=$SUPA_BODY -->" >&2
                       fi
                        
                         if [ "$SUPA_HTTP_CODE" = "200" ] && echo "$SUPA_BODY" | $GREP -q '"id"'; then
                             C_VENDOR=$(echo "$SUPA_BODY" | json_first "vendor_uuid")
                             C_STATUS=$(echo "$SUPA_BODY" | json_first "status")
                             
                             if [ "$C_STATUS" = "active" ]; then
                                 "$UCI" set pisowifi.license.centralized_key="$C_KEY"
                                 "$UCI" set pisowifi.license.centralized_vendor_id="$C_VENDOR"
                                 "$UCI" set pisowifi.license.centralized_status="active"
                                 "$UCI" commit pisowifi
                                 
                                 echo "Status: 302 Found"
                                 echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_ok"
                                 echo ""
                                 exit 0
                             fi
                         fi
                         
                         # DEBUG: Log final failure
                         echo "<!-- DEBUG: Both database queries failed -->" >&2
                         echo "<!-- DEBUG: Final failure - key not found or connection error -->" >&2
                         
                         echo "Status: 302 Found"
                         echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_failed"
                         echo ""
                         exit 0
                     fi
                 else
                     echo "<!-- DEBUG: Regex FAILED for key: $C_KEY -->" >&2
                     echo "<!-- DEBUG: Expected format: CENTRAL-XXXXXXXX-XXXXXXXX -->" >&2
                     echo "Status: 302 Found"
                     echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_format_error"
                     echo ""
                     exit 0
                 fi
             else
                 echo "Status: 302 Found"
                 echo "Location: /cgi-bin/admin?tab=settings&msg=centralized_invalid_format"
                 echo ""
                 exit 0
             fi

        elif [ "$ACTION" = "add_device" ] || [ "$ACTION" = "save_connected_device" ]; then
             MAC=$(get_post_var "mac" | tr 'a-z' 'A-Z')
             IP_ADDR=$(get_post_var "ip")
             HOSTNAME=$(get_post_var "hostname")
             NOTES=$(get_post_var "notes")

             MAC_SQL=$(sql_escape "$MAC")
             IP_SQL=$(sql_escape "$IP_ADDR")
             HOST_SQL=$(sql_escape "$HOSTNAME")
             NOTES_SQL=$(sql_escape "$NOTES")

             sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO devices (mac, created_at, updated_at) VALUES ('$MAC_SQL', strftime('%s','now'), strftime('%s','now')); UPDATE devices SET ip='$IP_SQL', hostname='$HOST_SQL', notes='$NOTES_SQL', updated_at=strftime('%s','now') WHERE mac='$MAC_SQL';" 2>/dev/null

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=devices&msg=device_saved"
             echo ""
             exit 0

        elif [ "$ACTION" = "update_device" ]; then
             MAC=$(get_post_var "mac" | tr 'a-z' 'A-Z')
             IP_ADDR=$(get_post_var "ip")
             HOSTNAME=$(get_post_var "hostname")
             NOTES=$(get_post_var "notes")

             MAC_SQL=$(sql_escape "$MAC")
             IP_SQL=$(sql_escape "$IP_ADDR")
             HOST_SQL=$(sql_escape "$HOSTNAME")
             NOTES_SQL=$(sql_escape "$NOTES")

             sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO devices (mac, created_at, updated_at) VALUES ('$MAC_SQL', strftime('%s','now'), strftime('%s','now')); UPDATE devices SET ip='$IP_SQL', hostname='$HOST_SQL', notes='$NOTES_SQL', updated_at=strftime('%s','now') WHERE mac='$MAC_SQL';" 2>/dev/null

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=devices&msg=device_saved"
             echo ""
             exit 0

        elif [ "$ACTION" = "delete_device" ]; then
             MAC=$(get_post_var "mac" | tr 'a-z' 'A-Z')
             MAC_SQL=$(sql_escape "$MAC")
             sqlite3 "$DB_FILE" "DELETE FROM devices WHERE mac='$MAC_SQL';" 2>/dev/null

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=devices&msg=device_deleted"
             echo ""
             exit 0

        elif [ "$ACTION" = "device_add_time" ]; then
             MAC=$(get_post_var "mac" | tr 'a-z' 'A-Z')
             IP_ADDR=$(get_post_var "ip")
             ADD_MIN=$(get_post_var "add_minutes")

             case "$ADD_MIN" in
                 ''|*[!0-9]*) ADD_MIN=0 ;;
             esac

             if [ "$ADD_MIN" -gt 0 ]; then
                 NOW_TS=$($DATE +%s)
                 MAC_SQL=$(sql_escape "$MAC")
                 IP_SQL=$(sql_escape "$IP_ADDR")

                 USER_ROW=$(sqlite3 -separator '|' "$DB_FILE" "SELECT session_end FROM users WHERE mac='$MAC_SQL' LIMIT 1;" 2>/dev/null)
                 CUR_END=$(echo "$USER_ROW" | $CUT -d'|' -f1)
                 [ -z "$CUR_END" ] && CUR_END=0

                 BASE_TS=$NOW_TS
                 if [ "$CUR_END" -gt "$NOW_TS" ]; then
                     BASE_TS=$CUR_END
                 fi

                 ADD_SEC=$((ADD_MIN * 60))
                 NEW_END=$((BASE_TS + ADD_SEC))

                 sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO users (mac, ip, session_start, session_end, paused_time) VALUES ('$MAC_SQL', '$IP_SQL', $NOW_TS, $NEW_END, 0); UPDATE users SET ip='$IP_SQL', session_end=$NEW_END, paused_time=0 WHERE mac='$MAC_SQL';" 2>/dev/null

                 /usr/bin/pisowifi_nftables.sh allow "$MAC" "$IP_ADDR" >/dev/null 2>&1 &
             fi

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=devices&msg=time_added"
             echo ""
             exit 0

        elif [ "$ACTION" = "sync_devices" ]; then
             CENTRALIZED_KEY=$($UCI -q get pisowifi.license.centralized_key 2>/dev/null)
             CENTRAL_STATUS=$($UCI -q get pisowifi.license.centralized_status 2>/dev/null)
             CENTRAL_STATUS_LC=$(echo "$CENTRAL_STATUS" | $TR 'A-Z' 'a-z')
             if [ -n "$CENTRAL_STATUS_LC" ] && [ "$CENTRAL_STATUS_LC" != "active" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Centralized key is not active. Please activate it first."}'
                 exit 0
             fi
             if ! echo "$CENTRALIZED_KEY" | $GREP -Eq '^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$'; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"No active centralized key found. Please activate a centralized key first."}'
                 exit 0
             fi
             
             # Run sync script
             if [ -f "/usr/bin/wifi_devices_sync_auto.sh" ]; then
                 SYNC_RESULT=$(sh /usr/bin/wifi_devices_sync_auto.sh 2>&1)
                 SYNC_STATUS=$?
                 
                 echo "Content-type: application/json"
                 echo ""
                 if [ $SYNC_STATUS -eq 0 ]; then
                     SYNC_SAFE=$(printf '%s' "$SYNC_RESULT" | $TR '\r\n' ' ' | $SED 's/\\/\\\\/g; s/"/\\"/g')
                     if [ -n "$SYNC_SAFE" ]; then
                         echo "{\"status\":\"success\",\"message\":\"Device sync completed: $SYNC_SAFE\"}"
                     else
                         echo '{"status":"success","message":"Device sync completed successfully."}'
                     fi
                 else
                     SYNC_SAFE=$(printf '%s' "$SYNC_RESULT" | $TR '\r\n' ' ' | $SED 's/\\/\\\\/g; s/"/\\"/g')
                     echo "{\"status\":\"error\",\"message\":\"Sync failed: $SYNC_SAFE\"}"
                 fi
             else
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Sync script not found. Please reinstall device sync functionality."}'
             fi
             exit 0

        elif [ "$ACTION" = "update_wifi" ]; then
             SSID=$(get_post_var "ssid")
             ENC=$(get_post_var "encryption")
             KEY=$(get_post_var "key")
             DISABLED=$(get_post_var "disabled")
             
             # Apply to ALL wifi interfaces
             # Iterate through all sections that are 'wifi-iface'
             # uci show wireless returns: wireless.default_radio0=wifi-iface ...
             
             IFACES=$(uci show wireless | grep "=wifi-iface" | cut -d= -f1)
             for iface in $IFACES; do
                 # Check if iface string is valid
                 if [ -n "$iface" ]; then
                     uci set $iface.ssid="$SSID" 2>/dev/null
                     uci set $iface.encryption="$ENC" 2>/dev/null
                     if [ "$ENC" != "none" ]; then
                         uci set $iface.key="$KEY" 2>/dev/null
                     else
                         uci delete $iface.key 2>/dev/null
                     fi
                     uci set $iface.disabled="$DISABLED" 2>/dev/null
                 fi
             done
             
             uci commit wireless
             /sbin/wifi reload
             
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=hotspot&msg=wifi_saved"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "update_settings" ]; then
             NEW_PASS=$(get_post_var "new_pass")
             
             if [ -n "$NEW_PASS" ]; then
                 uci set pisowifi.settings.admin_password="$NEW_PASS"
                 uci commit pisowifi
             fi
             
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=settings&msg=saved"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "update_standard_rate" ]; then
             RATE=$(get_post_var "rate")
             uci set pisowifi.settings.minutes_per_peso="$RATE"
             uci commit pisowifi
             # Also update in DB for consistency
             sqlite3 $DB_FILE "UPDATE rates SET minutes=$RATE WHERE amount=1"
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=rates&msg=rate_saved"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "add_custom_rate" ]; then
             AMOUNT=$(get_post_var "amount")
             
             # Duration Calculation
             D_VAL=$(get_post_var "d_val")
             D_UNIT=$(get_post_var "d_unit")
             [ -z "$D_VAL" ] && D_VAL=0
             [ -z "$D_UNIT" ] && D_UNIT=1
             MINUTES=$((D_VAL * D_UNIT))
             
             MODE=$(get_post_var "mode") # 1=Pausable, 0=Continuous
             
             # Expiration Calculation
             E_VAL=$(get_post_var "e_val")
             E_UNIT=$(get_post_var "e_unit")
             [ -z "$E_VAL" ] && E_VAL=0
             [ -z "$E_UNIT" ] && E_UNIT=1
             EXPIRATION=$((E_VAL * E_UNIT))
             
             if [ "$MODE" = "0" ]; then
                 EXPIRATION=0 # Continuous has no separate expiration logic usually
             fi
             
             sqlite3 $DB_FILE "INSERT OR REPLACE INTO rates (amount, minutes, is_pausable, expiration) VALUES ($AMOUNT, $MINUTES, $MODE, $EXPIRATION)"
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=rates&msg=rate_saved"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "delete_rate" ]; then
             ID=$(get_post_var "rate_id")
             sqlite3 $DB_FILE "DELETE FROM rates WHERE id=$ID"
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=rates&msg=rate_deleted"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "update_qos" ]; then
             QOS_MODE=$(get_post_var "qos_mode")
             GLOBAL_DOWN=$(get_post_var "global_down")
             GLOBAL_UP=$(get_post_var "global_up")
             USER_DOWN=$(get_post_var "user_down")
             USER_UP=$(get_post_var "user_up")
             
             # Robust fallbacks for empty values
             [ -z "$QOS_MODE" ] && QOS_MODE="global"
             [ -z "$GLOBAL_DOWN" ] && GLOBAL_DOWN=0
             [ -z "$GLOBAL_UP" ] && GLOBAL_UP=0
             [ -z "$USER_DOWN" ] && USER_DOWN=0
             [ -z "$USER_UP" ] && USER_UP=0
             
             # Log the received values for debugging
             logger -t pisowifi "ACTION: update_qos | MODE: $QOS_MODE | G_DOWN: $GLOBAL_DOWN | G_UP: $GLOBAL_UP | U_DOWN: $USER_DOWN | U_UP: $USER_UP"
             
             # Create the section if it doesn't exist and set values
             uci set pisowifi.qos=qos
             uci set pisowifi.qos.mode="$QOS_MODE"
             uci set pisowifi.qos.global_down="$GLOBAL_DOWN"
             uci set pisowifi.qos.global_up="$GLOBAL_UP"
             uci set pisowifi.qos.user_down="$USER_DOWN"
             uci set pisowifi.qos.user_up="$USER_UP"
             
             # Commit explicitly to the file
             uci commit pisowifi
             
             # Re-read to confirm (optional, but good for debug)
             SAVED_MODE=$(uci get pisowifi.qos.mode 2>/dev/null)
             logger -t pisowifi "SAVED QoS MODE: $SAVED_MODE"
             
             # Apply QoS Settings Immediately
             /usr/bin/pisowifi_qos.sh reload >/dev/null 2>&1 &
             /usr/bin/pisowifi_nftables.sh reload_qos >/dev/null 2>&1 &
             
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=qos&msg=qos_saved"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "save_portal" ]; then
             HTML_CONTENT=$(get_post_var "html_content")
             # Write to file
             echo "$HTML_CONTENT" > /www/portal.html
             
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=portal&msg=portal_saved"
             echo ""
             exit 0

        elif [ "$ACTION" = "save_theme" ]; then
             THEME_NAME=$(get_post_var "theme_name")
             THEME_NAME=$(echo "$THEME_NAME" | $TR ' ' '_' )
             SLUG=$(echo "$THEME_NAME" | $TR -cd 'A-Za-z0-9_-')
             [ -z "$SLUG" ] && SLUG=$($DATE +%s)
             HTML_CONTENT=$(get_post_var "html_content")
             mkdir -p /www/portal_themes
             echo "$HTML_CONTENT" > "/www/portal_themes/custom_${SLUG}.html"

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=portal&msg=theme_saved"
             echo ""
             exit 0

        elif [ "$ACTION" = "delete_theme" ]; then
             THEME_ID=$(get_post_var "theme_id")
             THEME_ID=$(echo "$THEME_ID" | $TR -cd 'A-Za-z0-9_-')
             case "$THEME_ID" in custom_*) ;; *) THEME_ID="custom_$THEME_ID" ;; esac
             rm -f "/www/portal_themes/${THEME_ID}.html" 2>/dev/null || true

             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=portal&msg=theme_deleted"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "upload_file" ]; then
             # Get filename safely
             FILENAME=$(get_post_var "filename")
             
             # For filedata, grep directly from file to avoid variable limits
             # This is a bit tricky with URL encoding. 
             # We assume the client sends 'filedata=BASE64...'
             # Grep the content, strip 'filedata=', then decode
             
             # Validate filename
             if [ "$FILENAME" = "bg.jpg" ] || [ "$FILENAME" = "insert.mp3" ] || [ "$FILENAME" = "connected.mp3" ]; then
                 # Extract base64 content
                 # Warning: This sed might still be slow on huge files but better than var
                 $GREP -a -o "filedata=[^&]*" "$POST_FILE" | $CUT -d= -f2- | $SED 's/%2B/+/g; s/%2F/\//g; s/%3D/=/g' | base64 -d > "/www/$FILENAME"
                 
                 echo "Status: 302 Found"
                echo "Location: /cgi-bin/admin?tab=portal&msg=upload_success"
                echo ""
            else
                echo "Status: 400 Bad Request"
                 echo "Content-type: text/plain"
                 echo ""
                 echo "Invalid filename"
             fi
             exit 0
        fi
    fi
fi


# Check Auth for View
if ! check_auth; then
    echo "Status: 200 OK"
    echo "Content-type: text/html; charset=utf-8"
    echo ""
    echo "<!DOCTYPE html><html><head><title>Admin Login</title>"
    echo "<meta name='viewport' content='width=device-width, initial-scale=1'>"
    echo "<style>body{font-family:sans-serif; background:#f1f5f9; display:flex; justify-content:center; align-items:center; height:100vh; margin:0;} .card{background:white; padding:30px; border-radius:12px; box-shadow:0 4px 6px rgba(0,0,0,0.1); width:100%; max-width:400px;} h1{text-align:center; color:#1e293b; margin-bottom:24px;} input{width:100%; padding:12px; margin-bottom:16px; border:1px solid #cbd5e1; border-radius:8px; box-sizing:border-box;} .btn{width:100%; padding:12px; background:#2563eb; color:white; border:none; border-radius:8px; font-weight:700; cursor:pointer;}</style></head><body>"
    echo "<div class='card'>"
    echo "<h1>Admin Login</h1>"
    if echo "$QUERY_STRING" | grep -q "error=invalid"; then echo "<p style='color:red; text-align: center;'>Invalid Password</p>"; fi
    echo "<form method='POST'><input type='password' name='password' placeholder='Password' required><button class='btn'>Login</button></form>"
    echo "</div></body></html>"
    exit 0
fi

# License Enforcement: Redirect to settings if license is not valid
TAB=$(echo "$QUERY_STRING" | $GREP -o "tab=[^&]*" | $CUT -d= -f2)
[ -z "$TAB" ] && TAB="dashboard"
LIC_VALID=$($UCI get pisowifi.license.valid 2>/dev/null || echo 0)

# SQLite Fallback: If UCI says invalid, check SQLite
if [ "$LIC_VALID" != "1" ]; then
    SQL_LIC=$(sqlite3 -separator '|' "$DB_FILE" "SELECT valid, status, license_key, expires_at, vendor_uuid, hardware_id FROM license LIMIT 1;" 2>/dev/null)
    if [ -n "$SQL_LIC" ]; then
        LIC_VALID=$(echo "$SQL_LIC" | $CUT -d'|' -f1)
        # Restore to UCI for faster future access
        if [ "$LIC_VALID" = "1" ]; then
            "$UCI" set pisowifi.license=license
            "$UCI" set pisowifi.license.valid=1
            "$UCI" set pisowifi.license.status=$(echo "$SQL_LIC" | $CUT -d'|' -f2)
            "$UCI" set pisowifi.license.license_key=$(echo "$SQL_LIC" | $CUT -d'|' -f3)
            "$UCI" set pisowifi.license.expires_at=$(echo "$SQL_LIC" | $CUT -d'|' -f4)
            V_SQL=$(echo "$SQL_LIC" | $CUT -d'|' -f5)
            "$UCI" set pisowifi.license.vendor_id="$V_SQL"
            "$UCI" set pisowifi.license.vendor_uuid="$V_SQL"
            "$UCI" set pisowifi.license.hardware_id=$(echo "$SQL_LIC" | $CUT -d'|' -f6)
            "$UCI" commit pisowifi
        fi
    fi
fi

if [ "$LIC_VALID" != "1" ] && [ "$TAB" != "settings" ]; then
    echo "Status: 302 Found"
    echo "Location: /cgi-bin/admin?tab=settings&msg=license_required"
    echo ""
    exit 0
fi

# Render Page Headers
echo "Status: 200 OK"
echo "Content-type: text/html; charset=utf-8"
echo ""

# HTML Start
echo "<!DOCTYPE html><html><head><title>NEXI-FI Admin Dashboard</title><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
echo "<style>"
echo "  :root { --primary: #2563eb; --secondary: #64748b; --success: #22c55e; --danger: #ef4444; --bg: #f1f5f9; --sidebar-bg: #1e293b; --sidebar-text: #e2e8f0; }"
echo "  body { font-family: 'Inter', sans-serif; background: var(--bg); color: #1e293b; margin: 0; padding: 0; display: flex; min-height: 100vh; }"
echo "  .sidebar { width: 250px; background: var(--sidebar-bg); color: var(--sidebar-text); padding: 20px; display: flex; flex-direction: column; flex-shrink: 0; }"
echo "  .sidebar h2 { color: white; margin-bottom: 30px; font-size: 1.25rem; text-transform: uppercase; letter-spacing: 0.1em; text-align: center; }"
echo "  .nav-link { display: block; padding: 12px 16px; color: var(--sidebar-text); text-decoration: none; border-radius: 8px; margin-bottom: 8px; transition: all 0.2s; }"
echo "  .nav-link:hover, .nav-link.active { background: rgba(255,255,255,0.1); color: white; }"
echo "  .nav-link.active { background: var(--primary); }"
echo "  .main-content { flex-grow: 1; padding: 30px; overflow-y: auto; }"
echo "  .container { max-width: 1200px; margin: 0 auto; }"
echo "  .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }"
echo "  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 24px; }"
echo "  .card { background: white; padding: 20px; border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }"
echo "  .card h3 { margin: 0 0 10px 0; font-size: 0.875rem; color: var(--secondary); text-transform: uppercase; letter-spacing: 0.05em; }"
echo "  .card .value { font-size: 1.5rem; font-weight: 700; color: #0f172a; }"
echo "  .card .sub { font-size: 0.75rem; color: var(--secondary); margin-top: 4px; }"
echo "  .progress-bg { background: #e2e8f0; height: 8px; border-radius: 4px; margin-top: 10px; overflow: hidden; }"
echo "  .progress-fill { background: var(--primary); height: 100%; transition: width 0.3s ease; }"
echo "  table { width: 100%; border-collapse: collapse; }"
echo "  th { text-align: left; padding: 12px; border-bottom: 2px solid #f1f5f9; color: var(--secondary); font-size: 0.875rem; }"
echo "  td { padding: 12px; border-bottom: 1px solid #f1f5f9; font-size: 0.875rem; }"
echo "  .btn { padding: 8px 16px; border-radius: 6px; border: none; font-weight: 600; cursor: pointer; transition: all 0.2s; }"
echo "  .btn-primary { background: var(--primary); color: white; }"
echo "  .btn-danger { background: var(--danger); color: white; }"
echo "  .chart-container { height: 200px; width: 100%; margin-top: 10px; position: relative; }"
echo "  canvas { width: 100% !important; height: 100% !important; }"
echo "  .sidebar-toggle { display: none; position: fixed; top: 12px; left: 12px; z-index: 1002; background: var(--sidebar-bg); color: white; border: 0; border-radius: 10px; padding: 10px 12px; font-size: 18px; line-height: 1; }"
echo "  .sidebar-overlay { display: none; position: fixed; inset: 0; background: rgba(15,23,42,0.45); z-index: 1000; }"
echo "  body.sidebar-open .sidebar { transform: translateX(0); }"
echo "  body.sidebar-open .sidebar-overlay { display: block; }"
echo "  @media (max-width: 768px) { body { display: block; } .sidebar { position: fixed; top: 0; left: 0; height: 100vh; width: 260px; max-width: 85vw; padding: 16px; box-sizing: border-box; transform: translateX(-110%); transition: transform .2s ease; z-index: 1001; overflow-y: auto; } .main-content { padding: 16px; } .sidebar-toggle { display: inline-flex; align-items: center; justify-content: center; } .header { padding-left: 44px; } table { display: block; overflow-x: auto; -webkit-overflow-scrolling: touch; } th, td { white-space: nowrap; } }"
echo "</style></head><body>"

# Render Sidebar
echo "<button class='sidebar-toggle' type='button' onclick='toggleSidebar()' aria-label='Menu'>☰</button>"
echo "<div id='sidebar-overlay' class='sidebar-overlay' onclick='toggleSidebar(false)'></div>"
echo "<div class='sidebar'>"
echo "  <h2>NEXI-FI ADMIN</h2>"
echo "  <nav>"
if [ "$LIC_VALID" = "1" ]; then
    echo "    <a href='?tab=dashboard' class='nav-link $([ "$TAB" = "dashboard" ] && echo "active")'>Dashboard</a>"
    echo "    <a href='?tab=rates' class='nav-link $([ "$TAB" = "rates" ] && echo "active")'>Rates Manager</a>"
    echo "    <a href='?tab=hotspot' class='nav-link $([ "$TAB" = "hotspot" ] && echo "active")'>Hotspot Manager</a>"
    echo "    <a href='?tab=devices' class='nav-link $([ "$TAB" = "devices" ] && echo "active")'>Device Manager</a>"
    echo "    <a href='?tab=sales' class='nav-link $([ "$TAB" = "sales" ] && echo "active")'>Sales Report</a>"
    echo "    <a href='?tab=qos' class='nav-link $([ "$TAB" = "qos" ] && echo "active")'>Bandwidth Manager</a>"
    echo "    <a href='?tab=portal' class='nav-link $([ "$TAB" = "portal" ] && echo "active")'>Portal Editor</a>"
fi
echo "    <a href='?tab=settings' class='nav-link $([ "$TAB" = "settings" ] && echo "active")'>Settings</a>"
echo "  </nav>"
echo "  <div style='margin-top: auto; padding-top: 20px; border-top: 1px solid rgba(255,255,255,0.1);'>"
echo "    <form method='POST'><input type='hidden' name='action' value='logout'><button class='btn btn-danger' style='width: 100%'>Logout</button></form>"
echo "  </div>"
echo "</div>"

echo "<div class='main-content'><div class='container'>"
echo "<script>function toggleSidebar(force){var open=document.body.classList.contains('sidebar-open');var next=(typeof force==='boolean')?force:!open;if(next){document.body.classList.add('sidebar-open');}else{document.body.classList.remove('sidebar-open');}}window.addEventListener('resize',function(){if(window.innerWidth>768)document.body.classList.remove('sidebar-open');});document.addEventListener('keydown',function(e){if(e.key==='Escape')document.body.classList.remove('sidebar-open');});document.addEventListener('click',function(e){var t=e.target;if(t&&t.classList&&t.classList.contains('nav-link')&&window.innerWidth<=768){document.body.classList.remove('sidebar-open');}});</script>"

    if [ "$TAB" = "dashboard" ]; then
        # Dashboard Content
        MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Generic OpenWrt Router")
        CORES=$(grep -c ^processor /proc/cpuinfo)
        MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
        MEM_USED=$((MEM_TOTAL - MEM_FREE))
        MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
        
        # Overlay Storage
        OVERLAY_TOTAL=$(df /overlay | tail -1 | awk '{print $2}')
        OVERLAY_USED=$(df /overlay | tail -1 | awk '{print $3}')
        OVERLAY_PCT=$(df /overlay | tail -1 | awk '{print $5}' | tr -d '%')
        
        # Users
        NOW=$($DATE +%s)
        ACTIVE_USERS=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM users WHERE session_end > $NOW" 2>/dev/null || echo 0)
        TOTAL_USERS=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM users" 2>/dev/null || echo 0)
        DISCONNECTED_USERS=$((TOTAL_USERS - ACTIVE_USERS))
        [ $DISCONNECTED_USERS -lt 0 ] && DISCONNECTED_USERS=0

        echo "<div class='header'><h1>Dashboard</h1></div>"
        
        # System Stats Grid
        echo "<div class='grid'>"
        echo "  <div class='card'><h3>Router Model</h3><div class='value' style='font-size:1.1rem'>$MODEL</div><div class='sub'>$CORES CPU Cores</div></div>"
        echo "  <div class='card'><h3>RAM Usage</h3><div class='value'>$MEM_PCT%</div><div class='progress-bg'><div class='progress-fill' style='width:$MEM_PCT%'></div></div><div class='sub'>$((MEM_USED/1024))MB / $((MEM_TOTAL/1024))MB</div></div>"
        echo "  <div class='card'><h3>Storage (Overlay)</h3><div class='value'>$OVERLAY_PCT%</div><div class='progress-bg'><div class='progress-fill' style='width:$OVERLAY_PCT%'></div></div><div class='sub'>$((OVERLAY_USED/1024))MB Used</div></div>"
        echo "  <div class='card'><h3>Users</h3><div class='value'>$ACTIVE_USERS / $TOTAL_USERS</div><div class='sub'><span style='color:var(--success)'>● $ACTIVE_USERS Online</span> | <span style='color:var(--secondary)'>○ $DISCONNECTED_USERS Offline</span></div></div>"
        echo "</div>"

        # Traffic Chart
        echo "<div class='card' style='margin-bottom:24px;'><h3>WAN Traffic (Real-time)</h3><div class='chart-container' style='height:150px;'><canvas id='trafficChart'></canvas></div></div>"

        # JS for Chart
        echo "<script>"
        echo "  const canvas = document.getElementById('trafficChart');"
        echo "  const ctx = canvas.getContext('2d');"
        echo "  function resizeCanvas() {"
        echo "     canvas.width = canvas.parentElement.clientWidth;"
        echo "     canvas.height = canvas.parentElement.clientHeight;"
        echo "  }"
        echo "  window.addEventListener('resize', resizeCanvas); resizeCanvas();"
        echo "  "
        echo "  let rxData = [], txData = [], labels = [];"
        echo "  let lastRx = 0, lastTx = 0;"
        echo "  function updateChart() {"
        echo "    fetch('/cgi-bin/admin?action=get_traffic').then(r => r.json()).then(data => {"
        echo "      const now = new Date().toLocaleTimeString();"
        echo "      if(lastRx > 0) {"
        echo "        const rxSpeed = (data.rx - lastRx) / 1024; // KB/s"
        echo "        const txSpeed = (data.tx - lastTx) / 1024; // KB/s"
        echo "        rxData.push(rxSpeed); txData.push(txSpeed); labels.push(now);"
        echo "        if(rxData.length > 30) { rxData.shift(); txData.shift(); labels.shift(); }"
        echo "        drawChart();"
        echo "      }"
        echo "      lastRx = data.rx; lastTx = data.tx;"
        echo "    });"
        echo "  }"
        echo "  function drawChart() {"
        echo "    const w = canvas.width; const h = canvas.height;"
        echo "    const max = Math.max(...rxData, ...txData, 1024);"
        echo "    ctx.clearRect(0, 0, w, h);"
        echo "    ctx.strokeStyle = '#f1f5f9'; ctx.lineWidth = 1;"
        echo "    ctx.beginPath();"
        echo "    for(let i=1; i<5; i++) { const y = h - (i/5)*h; ctx.moveTo(0, y); ctx.lineTo(w, y); }"
        echo "    ctx.stroke();"
        echo "    ctx.beginPath(); ctx.strokeStyle = '#2563eb'; ctx.lineWidth = 2;"
        echo "    rxData.forEach((d, i) => { const x = (i/(rxData.length-1))*w; const y = h - (d/max)*h; i==0 ? ctx.moveTo(x,y) : ctx.lineTo(x,y); });"
        echo "    ctx.stroke();"
        echo "    ctx.beginPath(); ctx.strokeStyle = '#ef4444'; ctx.lineWidth = 2;"
        echo "    txData.forEach((d, i) => { const x = (i/(txData.length-1))*w; const y = h - (d/max)*h; i==0 ? ctx.moveTo(x,y) : ctx.lineTo(x,y); });"
        echo "    ctx.stroke();"
        echo "    ctx.fillStyle = '#64748b'; ctx.font = '10px sans-serif';"
        echo "    ctx.fillText(Math.round(max/1024) + ' MB/s', 5, 12);"
        echo "    ctx.fillStyle = '#2563eb'; ctx.fillText('RX: ' + Math.round(rxData[rxData.length-1]||0) + ' KB/s', w-120, 12);"
        echo "    ctx.fillStyle = '#ef4444'; ctx.fillText('TX: ' + Math.round(txData[txData.length-1]||0) + ' KB/s', w-60, 12);"
        echo "  }"
        echo "  setInterval(updateChart, 2000); updateChart();"
        echo "</script>"

    elif [ "$TAB" = "rates" ]; then
        echo "<div class='header'><h1>Rates Manager</h1></div>"
        
        if echo "$QUERY_STRING" | grep -q "msg=rate_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Rate Saved!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=rate_deleted"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Rate Deleted!</div>"; fi
        
        # Global Rate
        CURRENT_RATE=$(uci get pisowifi.settings.minutes_per_peso 2>/dev/null || echo 12)
        
        echo "<div class='grid'>"
        echo "  <div class='card'>"
        echo "    <h3>Standard Rate</h3>"
        echo "    <form method='POST'>"
        echo "      <input type='hidden' name='action' value='update_standard_rate'>"
        echo "      <div style='margin-bottom: 15px;'>"
        echo "        <label style='display:block; margin-bottom:5px; font-weight:600;'>Minutes per 1 Peso</label>"
        echo "        <input type='number' name='rate' value='$CURRENT_RATE' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; box-sizing:border-box;'>"
        echo "      </div>"
        echo "      <button class='btn btn-primary' style='width:100%'>Update Standard Rate</button>"
        echo "    </form>"
        echo "  </div>"
        
        echo "  <div class='card' style='grid-column: span 2;'>"
        echo "    <h3>Create Rate Definition</h3>"
        echo "    <form method='POST' style='display:flex; flex-wrap:wrap; gap:15px; align-items:end;'>"
        echo "      <input type='hidden' name='action' value='add_custom_rate'>"
        
        echo "      <div style='flex:1; min-width:100px;'>"
        echo "        <label style='display:block; margin-bottom:5px; font-weight:600;'>Currency (₱)</label>"
        echo "        <input type='number' name='amount' placeholder='1' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; box-sizing:border-box;' required>"
        echo "      </div>"
        
        echo "      <div style='flex:2; min-width:200px;'>"
        echo "        <label style='display:block; margin-bottom:5px; font-weight:600;'>Duration</label>"
        echo "        <div style='display:flex;'>"
        echo "          <input type='number' name='d_val' placeholder='10' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px 0 0 6px; box-sizing:border-box;' required>"
        echo "          <select name='d_unit' style='padding:10px; border:1px solid #cbd5e1; border-left:none; border-radius:0 6px 6px 0; background:#f8fafc;'>"
        echo "            <option value='1'>Minutes</option>"
        echo "            <option value='60'>Hours</option>"
        echo "            <option value='1440'>Days</option>"
        echo "          </select>"
        echo "        </div>"
        echo "      </div>"
        
        echo "      <div style='flex:1; min-width:150px;'>"
        echo "        <label style='display:block; margin-bottom:5px; font-weight:600;'>Mode</label>"
        echo "        <select name='mode' onchange=\"document.getElementById('exp-group').style.display = this.value=='1' ? 'block' : 'none'\" style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; box-sizing:border-box;'>"
        echo "          <option value='1'>Pausable</option>"
        echo "          <option value='0'>Continuous</option>"
        echo "        </select>"
        echo "      </div>"
        
        echo "      <div id='exp-group' style='flex:2; min-width:200px;'>"
        echo "        <label style='display:block; margin-bottom:5px; font-weight:600;'>Expiration (Optional)</label>"
        echo "        <div style='display:flex;'>"
        echo "          <input type='number' name='e_val' placeholder='e.g. 24' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px 0 0 6px; box-sizing:border-box;'>"
        echo "          <select name='e_unit' style='padding:10px; border:1px solid #cbd5e1; border-left:none; border-radius:0 6px 6px 0; background:#f8fafc;'>"
        echo "            <option value='60'>Hours</option>"
        echo "            <option value='1440'>Days</option>"
        echo "            <option value='1'>Minutes</option>"
        echo "          </select>"
        echo "        </div>"
        echo "      </div>"
        
        echo "      <button class='btn btn-primary' style='padding: 10px 30px; width:100%;'>Add Rate</button>"
        echo "    </form>"
        echo "    <div class='alert' style='background:#fffbeb; color:#92400e; margin-top:10px; font-size:0.8rem;'>⚠️ Limits are in the Bandwidth section</div>"
        echo "  </div>"
        echo "</div>"
        
        echo "<div class='card' style='margin-top:20px;'>"
        echo "  <h3>Active Rate Definitions</h3>"
        echo "  <table>"
        echo "    <tr><th>Denomination</th><th>Duration</th><th>Expiration</th><th>Action</th></tr>"
        # List Standard Rate (₱1)
        echo "    <tr><td>₱1</td><td>$CURRENT_RATE Minutes</td><td>-</td><td>-</td></tr>"
        # List Custom Rates
        # Need complex SQL to format output nicely or do it in shell
        sqlite3 -separator '|' $DB_FILE "SELECT amount, minutes, is_pausable, expiration, id FROM rates WHERE amount != 1 ORDER BY amount ASC" 2>/dev/null | while read line; do
            ID=$(echo "$line" | cut -d'|' -f5)
            AMT=$(echo "$line" | cut -d'|' -f1)
            MIN=$(echo "$line" | cut -d'|' -f2)
            PAUSE=$(echo "$line" | cut -d'|' -f3)
            EXP=$(echo "$line" | cut -d'|' -f4)
            
            # Format Duration
            if [ "$MIN" -ge 1440 ] && [ $((MIN % 1440)) -eq 0 ]; then DUR="$((MIN / 1440))d";
            elif [ "$MIN" -ge 60 ] && [ $((MIN % 60)) -eq 0 ]; then DUR="$((MIN / 60))h";
            else DUR="${MIN}m"; fi
            
            # Format Expiration
            if [ "$PAUSE" = "0" ]; then EXP_TXT="Continuous";
            elif [ "$EXP" -eq 0 ]; then EXP_TXT="No Expiry";
            else
                if [ "$EXP" -ge 1440 ] && [ $((EXP % 1440)) -eq 0 ]; then EXP_TXT="$((EXP / 1440))d";
                elif [ "$EXP" -ge 60 ] && [ $((EXP % 60)) -eq 0 ]; then EXP_TXT="$((EXP / 60))h";
                else EXP_TXT="${EXP}m"; fi
            fi
            
            echo "    <tr><td>₱$AMT</td><td>$DUR</td><td>$EXP_TXT</td><td>"
            echo "      <form method='POST' style='display:inline;'><input type='hidden' name='action' value='delete_rate'><input type='hidden' name='rate_id' value='$ID'><button class='btn btn-danger' style='padding:4px 8px; font-size:11px;'>DELETE</button></form>"
            echo "    </td></tr>"
        done
        echo "  </table>"
        echo "</div>"

    elif [ "$TAB" = "hotspot" ]; then
        echo "<div class='header'><h1>Hotspot Manager</h1></div>"
        
        # WiFi Config Form
        SSID=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null)
        KEY=$(uci get wireless.@wifi-iface[0].key 2>/dev/null)
        ENCRYPTION=$(uci get wireless.@wifi-iface[0].encryption 2>/dev/null)
        DISABLED=$(uci get wireless.@wifi-iface[0].disabled 2>/dev/null)
        
        if echo "$QUERY_STRING" | grep -q "msg=wifi_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>WiFi Settings Saved! (Applied to All Radios)</div>"; fi

        echo "<div class='card' style='max-width: 600px;'>"
        echo "<h3>WiFi Configuration (2.4GHz / 5GHz)</h3>"
        echo "<form method='POST'>"
        echo "<input type='hidden' name='action' value='update_wifi'>"
        echo "<input type='hidden' name='device' value='radio0'>"
        
        echo "<div style='margin-bottom: 20px;'>"
        echo "  <label style='display:block; margin-bottom:8px; font-weight:600;'>SSID Name</label>"
        echo "  <input type='text' name='ssid' value='$SSID' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;' required>"
        echo "</div>"
        
        echo "<div style='margin-bottom: 20px;'>"
        echo "  <label style='display:block; margin-bottom:8px; font-weight:600;'>Encryption</label>"
        echo "  <select name='encryption' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        echo "    <option value='none' $([ "$ENCRYPTION" = "none" ] && echo "selected")>Open (No Password)</option>"
        echo "    <option value='psk2' $([ "$ENCRYPTION" = "psk2" ] && echo "selected")>WPA2-PSK</option>"
        echo "  </select>"
        echo "</div>"
        
        echo "<div style='margin-bottom: 20px;'>"
        echo "  <label style='display:block; margin-bottom:8px; font-weight:600;'>Password (if WPA2)</label>"
        echo "  <input type='text' name='key' value='$KEY' placeholder='WiFi Password' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        echo "</div>"
        
        echo "<div style='margin-bottom: 20px;'>"
        echo "  <label style='display:block; margin-bottom:8px; font-weight:600;'>Status</label>"
        echo "  <select name='disabled' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        echo "    <option value='0' $([ "$DISABLED" = "0" ] && echo "selected")>Enabled</option>"
        echo "    <option value='1' $([ "$DISABLED" = "1" ] && echo "selected")>Disabled</option>"
        echo "  </select>"
        echo "</div>"
        
        echo "<button class='btn btn-primary' style='width:100%; padding: 12px;'>Save & Apply to ALL Radios</button>"
        echo "</form>"
        echo "</div>"

    elif [ "$TAB" = "devices" ]; then
        echo "<div class='header'><h1>Device Manager</h1></div>"

        if echo "$QUERY_STRING" | grep -q "msg=device_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Device Saved!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=device_deleted"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Device Deleted!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=time_added"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Time Added!</div>"; fi

        esc() { printf "%s" "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
        fmt_time() {
            SEC=$1
            [ -z "$SEC" ] && SEC=0
            if [ "$SEC" -le 0 ]; then
                echo "0s"
                return
            fi
            M=$((SEC / 60))
            S=$((SEC % 60))
            if [ "$M" -ge 60 ]; then
                H=$((M / 60))
                M2=$((M % 60))
                echo "${H}h ${M2}m"
            else
                echo "${M}m ${S}s"
            fi
        }

        NOW=$($DATE +%s)
        LEASE_FILES="/tmp/dhcp.leases /tmp/dnsmasq.leases /var/dhcp.leases"
        LEASE_FILE=""
        for lf in $LEASE_FILES; do
            if [ -f "$lf" ] && $GREP -q '.' "$lf" 2>/dev/null; then
                LEASE_FILE="$lf"
                break
            fi
        done

        # Function to get hostname by IP
        get_hostname_by_ip() {
            local ip="$1"
            local hostname=""
            # Try to get from DHCP leases first
            for lf in $LEASE_FILES; do
                if [ -f "$lf" ]; then
                    hostname=$($GREP "$ip" "$lf" 2>/dev/null | $HEAD -1 | $AWK '{print $4}' 2>/dev/null)
                    [ "$hostname" = "*" ] && hostname=""
                    [ -n "$hostname" ] && break
                fi
            done
            # If not found, try reverse DNS lookup
            if [ -z "$hostname" ]; then
                hostname=$(nslookup "$ip" 2>/dev/null | $GREP "name =" | $HEAD -1 | $AWK -F'=' '{print $2}' | $SED 's/\.$//' 2>/dev/null)
            fi
            # If still not found, generate default
            if [ -z "$hostname" ]; then
                hostname="Device-$(echo "$ip" | $SED 's/\./-/g')"
            fi
            echo "$hostname"
        }

        # Auto-save connected devices from DHCP leases
        AUTO_SAVED_COUNT=0
        UPDATED_COUNT=0
        if [ -f "$LEASE_FILE" ]; then
            while read EXP MACADDR IPADDR HOSTNAME CLIENTID; do
                [ -z "$MACADDR" ] && continue
                MAC_UP=$(echo "$MACADDR" | $TR 'a-z' 'A-Z')
                HOST="$HOSTNAME"
                [ "$HOST" = "*" ] && HOST=""
                [ -z "$HOST" ] && HOST=$(get_hostname_by_ip "$IPADDR")
                
                # Check if device already exists
                EXISTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM devices WHERE mac='$MAC_UP';" 2>/dev/null)
                if [ "$EXISTS" = "0" ]; then
                    # Auto-save new device
                    MAC_SQL=$(sql_escape "$MAC_UP")
                    IP_SQL=$(sql_escape "$IPADDR")
                    HOST_SQL=$(sql_escape "$HOST")
                    if sqlite3 "$DB_FILE" "INSERT INTO devices (mac, ip, hostname, notes, created_at, updated_at) VALUES ('$MAC_SQL', '$IP_SQL', '$HOST_SQL', 'Auto-detected', strftime('%s','now'), strftime('%s','now'));" 2>/dev/null; then
                        AUTO_SAVED_COUNT=$((AUTO_SAVED_COUNT + 1))
                        logger -t pisowifi "Auto-saved new device: $MAC_UP ($HOST) at $IPADDR"
                    else
                        logger -t pisowifi "Failed to auto-save device: $MAC_UP ($HOST)"
                    fi
                else
                    # Update IP if changed
                    MAC_SQL=$(sql_escape "$MAC_UP")
                    IP_SQL=$(sql_escape "$IPADDR")
                    if sqlite3 "$DB_FILE" "UPDATE devices SET ip='$IP_SQL', updated_at=strftime('%s','now') WHERE mac='$MAC_SQL' AND ip!='$IP_SQL';" 2>/dev/null; then
                        if [ $(sqlite3 "$DB_FILE" "SELECT changes();") -gt 0 ]; then
                            UPDATED_COUNT=$((UPDATED_COUNT + 1))
                            logger -t pisowifi "Updated IP for device: $MAC_UP to $IPADDR"
                        fi
                    fi
                fi
            done < "$LEASE_FILE"
        fi
        
        # Show auto-save summary if any devices were processed
        if [ "$AUTO_SAVED_COUNT" -gt 0 ] || [ "$UPDATED_COUNT" -gt 0 ]; then
            echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>"
            echo "Auto-detection complete: $AUTO_SAVED_COUNT new devices saved, $UPDATED_COUNT IP addresses updated."
            echo "</div>"
        fi

        echo "<div class='card' style='margin-bottom:20px;'>"
        echo "<h3>Add Device</h3>"
        echo "<form method='POST' style='display:grid; grid-template-columns: 1fr 1fr; gap:12px;'>"
        echo "  <input type='hidden' name='action' value='add_device'>"
        echo "  <div><label style='display:block; margin-bottom:6px; font-weight:600;'>MAC</label><input name='mac' placeholder='AA:BB:CC:DD:EE:FF' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;' required></div>"
        echo "  <div><label style='display:block; margin-bottom:6px; font-weight:600;'>IP</label><input name='ip' placeholder='10.0.0.x' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'></div>"
        echo "  <div><label style='display:block; margin-bottom:6px; font-weight:600;'>Hostname</label><input name='hostname' placeholder='Device name' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'></div>"
        echo "  <div><label style='display:block; margin-bottom:6px; font-weight:600;'>Notes</label><input name='notes' placeholder='Optional' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'></div>"
        echo "  <div style='grid-column: span 2;'><button class='btn btn-primary' style='width:100%; padding:12px;'>Save Device</button></div>"
        echo "</form>"
        echo "</div>"

        # Auto-save connected devices from DHCP leases
        AUTO_SAVED=0
        if [ -f "$LEASE_FILE" ]; then
            $CAT "$LEASE_FILE" 2>/dev/null | while read EXP MACADDR IPADDR HOSTNAME CLIENTID; do
                [ -z "$MACADDR" ] && continue
                MAC_UP=$(echo "$MACADDR" | $TR 'a-z' 'A-Z')
                HOST="$HOSTNAME"
                [ "$HOST" = "*" ] && HOST=""
                [ -z "$HOST" ] && HOST="$(gethostbyip "$IPADDR" 2>/dev/null || echo "Device-$MAC_UP")"
                
                # Check if device already exists
                EXISTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM devices WHERE mac='$MAC_UP';" 2>/dev/null)
                if [ "$EXISTS" = "0" ]; then
                    # Auto-save new device
                    MAC_SQL=$(sql_escape "$MAC_UP")
                    IP_SQL=$(sql_escape "$IPADDR")
                    HOST_SQL=$(sql_escape "$HOST")
                    sqlite3 "$DB_FILE" "INSERT INTO devices (mac, ip, hostname, notes, created_at, updated_at) VALUES ('$MAC_SQL', '$IP_SQL', '$HOST_SQL', 'Auto-detected', strftime('%s','now'), strftime('%s','now'));" 2>/dev/null
                    logger -t pisowifi "Auto-saved new device: $MAC_UP ($HOST)"
                fi
            done
        fi

        echo "<div class='card'>"
        echo "<h3>Device Manager</h3>"
        echo "<div style='margin-bottom:16px;'>"
        echo "<p style='color:#64748b; font-size:14px; margin-bottom:8px;'>Devices are automatically saved when they connect to the network. Online devices show green status.</p>"
        echo "<button id='sync-all-btn' class='btn btn-primary' style='background:linear-gradient(135deg, #667eea 0%, #764ba2 100%); border:none; padding:8px 16px; border-radius:6px; color:white; cursor:pointer;'>Sync All Devices</button>"
        echo "</div>"
        echo "<table><tr><th>Hostname</th><th>IP</th><th>MAC</th><th>Status</th><th>Notes</th><th>Actions</th></tr>"
        
        # Display all devices with connection status
        sqlite3 -separator '|' "$DB_FILE" "SELECT mac, ip, hostname, notes FROM devices ORDER BY updated_at DESC;" 2>/dev/null | while IFS='|' read MACADDR IPADDR HOSTNAME NOTES; do
            [ -z "$MACADDR" ] && continue
            MAC_UP=$(echo "$MACADDR" | tr 'a-z' 'A-Z')
            
            # Check if device is currently connected (has valid lease)
            IS_CONNECTED=0
            CURRENT_IP=""
            for lf in $LEASE_FILES; do
                if [ -f "$lf" ]; then
                    LEASE_INFO=$($GREP -i "$MAC_UP" "$lf" 2>/dev/null | $HEAD -1)
                    if [ -n "$LEASE_INFO" ]; then
                        IS_CONNECTED=1
                        CURRENT_IP=$(echo "$LEASE_INFO" | $AWK '{print $3}' 2>/dev/null)
                        break
                    fi
                fi
            done
            if [ "$IS_CONNECTED" = "0" ] && command -v iw >/dev/null 2>&1; then
                for ifc in $(iw dev 2>/dev/null | $AWK '/Interface/ {print $2}'); do
                    iw dev "$ifc" station dump 2>/dev/null | $GREP -qi "$MAC_UP" && IS_CONNECTED=1 && break
                done
            fi
            if [ "$IS_CONNECTED" = "0" ] && [ -f /proc/net/arp ]; then
                ARP_LINE=$($GREP -i "$MAC_UP" /proc/net/arp 2>/dev/null | $HEAD -1)
                if [ -n "$ARP_LINE" ]; then
                    IS_CONNECTED=1
                    ARP_IP=$(echo "$ARP_LINE" | $AWK '{print $1}' 2>/dev/null)
                    [ -n "$ARP_IP" ] && CURRENT_IP="$ARP_IP"
                fi
            fi
            
            # Get user session info
            USER_ROW=$(sqlite3 -separator '|' "$DB_FILE" "SELECT session_end, paused_time FROM users WHERE mac='$MAC_UP' LIMIT 1;" 2>/dev/null)
            END_TS=$(echo "$USER_ROW" | cut -d'|' -f1)
            PAUSED_TS=$(echo "$USER_ROW" | cut -d'|' -f2)
            [ -z "$END_TS" ] && END_TS=0
            [ -z "$PAUSED_TS" ] && PAUSED_TS=0
            
            # Determine status and color
            if [ "$PAUSED_TS" -gt 0 ]; then
                STATUS="Paused"
                STATUS_COLOR="#ef4444"
            elif [ "$END_TS" -gt "$NOW" ]; then
                REM=$((END_TS - NOW))
                STATUS="Active ($(fmt_time "$REM"))"
                STATUS_COLOR="#10b981"
            elif [ "$IS_CONNECTED" = "1" ]; then
                STATUS="Online"
                STATUS_COLOR="#22c55e"
            else
                STATUS="Offline"
                STATUS_COLOR="#6b7280"
            fi
            
            # Use current IP if device is connected, otherwise use stored IP
            DISPLAY_IP="$CURRENT_IP"
            [ -z "$DISPLAY_IP" ] && DISPLAY_IP="$IPADDR"

            EH=$(esc "$HOSTNAME")
            [ -z "$EH" ] && EH="(unknown)"
            EIP=$(esc "$DISPLAY_IP")
            EM=$(esc "$MAC_UP")
            EN=$(esc "$NOTES")
            
            echo "<tr><td>$EH</td><td>$EIP</td><td>$EM</td><td><span style='color:$STATUS_COLOR; font-weight:600;'>$STATUS</span></td><td>$EN</td><td>"
            echo "  <form method='POST' style='display:inline-flex; gap:8px; align-items:center; margin-bottom:6px;'>"
            echo "    <input type='hidden' name='action' value='update_device'>"
            echo "    <input type='hidden' name='mac' value='$MAC_UP'>"
            echo "    <input name='ip' value='$EIP' placeholder='IP' style='width:120px; padding:8px; border:1px solid #cbd5e1; border-radius:6px;'>"
            echo "    <input name='hostname' value='$EH' placeholder='Hostname' style='width:160px; padding:8px; border:1px solid #cbd5e1; border-radius:6px;'>"
            echo "    <input name='notes' value='$EN' placeholder='Notes' style='width:160px; padding:8px; border:1px solid #cbd5e1; border-radius:6px;'>"
            echo "    <button class='btn btn-primary' style='padding:8px 10px;'>Update</button>"
            echo "  </form>"
            echo "  <form method='POST' style='display:inline-flex; gap:8px; align-items:center;'>"
            echo "    <input type='hidden' name='action' value='device_add_time'>"
            echo "    <input type='hidden' name='mac' value='$MAC_UP'>"
            echo "    <input type='hidden' name='ip' value='$DISPLAY_IP'>"
            echo "    <input type='number' name='add_minutes' min='1' placeholder='+min' style='width:90px; padding:8px; border:1px solid #cbd5e1; border-radius:6px;'>"
            echo "    <button class='btn btn-primary' style='padding:8px 10px;'>Add Time</button>"
            echo "  </form>"
            echo "  <form method='POST' style='display:inline; margin-left:10px;'>"
            echo "    <input type='hidden' name='action' value='delete_device'>"
            echo "    <input type='hidden' name='mac' value='$MAC_UP'>"
            echo "    <button class='btn btn-danger' style='padding:8px 10px;'>Delete</button>"
            echo "  </form>"
            echo "</td></tr>"
        done
        echo "</table>"
        echo "</div>"
        
        # Add sync functionality JavaScript
        echo "<script>"
        echo "document.getElementById('sync-all-btn').addEventListener('click', function() {"
        echo "  var btn = this;"
        echo "  var originalText = btn.textContent;"
        echo "  btn.textContent = 'Syncing...';"
        echo "  btn.disabled = true;"
        echo "  "
        echo "  fetch('/cgi-bin/admin', {"
        echo "    method: 'POST',"
        echo "    headers: {'Content-Type': 'application/x-www-form-urlencoded'},"
        echo "    body: 'action=sync_devices'"
        echo "  })"
        echo "  .then(response => response.json())"
        echo "  .then(data => {"
        echo "    if(data.status === 'success') {"
        echo "      alert('✅ ' + data.message);"
        echo "      location.reload();"
        echo "    } else {"
        echo "      alert('❌ ' + data.message);"
        echo "      btn.textContent = originalText;"
        echo "      btn.disabled = false;"
        echo "    }"
        echo "  })"
        echo "  .catch(error => {"
        echo "    alert('❌ Sync failed: ' + error);"
        echo "    btn.textContent = originalText;"
        echo "    btn.disabled = false;"
        echo "  });"
        echo "});"
        echo "</script>"

    elif [ "$TAB" = "sales" ]; then
        echo "<div class='header'><h1>Sales Report</h1></div>"
        
        # Sales Stats
        TOTAL_SALES=$(sqlite3 $DB_FILE "SELECT SUM(coins) FROM coins WHERE mac != '00:00:00:00:00:00'" 2>/dev/null || echo 0)
        [ -z "$TOTAL_SALES" ] && TOTAL_SALES=0
        
        TODAY_SALES=$(sqlite3 $DB_FILE "SELECT SUM(coins) FROM coins WHERE mac != '00:00:00:00:00:00' AND timestamp >= strftime('%s', 'now', 'start of day')" 2>/dev/null || echo 0)
        [ -z "$TODAY_SALES" ] && TODAY_SALES=0

        echo "<div class='grid'>"
        echo "  <div class='card'><h3>Total Revenue</h3><div class='value'>₱$TOTAL_SALES</div></div>"
        echo "  <div class='card'><h3>Today's Revenue</h3><div class='value'>₱$TODAY_SALES</div></div>"
        echo "</div>"

        # Sales History Table
        echo "<div class='card'>"
        echo "<h3>Transaction History</h3>"
        echo "<table><tr><th>ID</th><th>Time</th><th>MAC</th><th>Amount</th></tr>"
        sqlite3 -separator '</td><td>' $DB_FILE "SELECT id, datetime(timestamp, 'unixepoch', 'localtime'), mac, '₱'||coins FROM coins WHERE mac != '00:00:00:00:00:00' ORDER BY id DESC LIMIT 50;" 2>/dev/null | awk '{print "<tr><td>" $0 "</td></tr>"}'
        echo "</table>"
        echo "</div>"
    
    elif [ "$TAB" = "qos" ]; then
        echo "<div class='header'><h1>Bandwidth Manager</h1></div>"
        
        if echo "$QUERY_STRING" | grep -q "msg=qos_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Bandwidth Settings Saved!</div>"; fi
        
        QOS_MODE=$(uci get pisowifi.qos.mode 2>/dev/null || echo "global")
        GLOBAL_DOWN=$(uci get pisowifi.qos.global_down 2>/dev/null || echo 0)
        GLOBAL_UP=$(uci get pisowifi.qos.global_up 2>/dev/null || echo 0)
        USER_DOWN=$(uci get pisowifi.qos.user_down 2>/dev/null || echo 0)
        USER_UP=$(uci get pisowifi.qos.user_up 2>/dev/null || echo 0)
        
        echo "<div class='card'>"
        echo "  <h3>Bandwidth Control Policy</h3>"
        echo "  <form method='POST'>"
        echo "    <input type='hidden' name='action' value='update_qos'>"
        
        echo "    <div style='margin-bottom: 20px;'>"
        echo "      <label style='display:block; margin-bottom:8px; font-weight:600;'>Control Mode</label>"
        echo "      <select name='qos_mode' onchange=\"this.value=='global' ? (document.getElementById('global-sec').style.display='block', document.getElementById('user-sec').style.display='none') : (document.getElementById('global-sec').style.display='none', document.getElementById('user-sec').style.display='block')\" style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        if [ "$QOS_MODE" = "per_user" ]; then
             echo "        <option value='global'>Global Fairness (CAKE)</option>"
             echo "        <option value='per_user' selected>Per-User Limiting</option>"
        else
             echo "        <option value='global' selected>Global Fairness (CAKE)</option>"
             echo "        <option value='per_user'>Per-User Limiting</option>"
        fi
        echo "      </select>"
        echo "      <p class='sub'><strong>Global Fairness:</strong> Uses CAKE queue management to automatically share bandwidth fairly among all users. No hard limits per user.</p>"
        echo "      <p class='sub'><strong>Per-User Limiting:</strong> Sets a hard speed limit for every user. Recommended if you sell fixed speeds.</p>"
        echo "    </div>"
        
        echo "    <div id='global-sec' style='display:$([ "$QOS_MODE" = "global" ] && echo "block" || echo "none"); border-top:1px solid #eee; padding-top:20px;'>"
        echo "      <h4>Global Total Bandwidth (ISP Speed)</h4>"
        echo "      <div style='display:grid; grid-template-columns: 1fr 1fr; gap:15px;'>"
        echo "        <div>"
        echo "          <label style='display:block; margin-bottom:5px; font-weight:600;'>Download (Mbps)</label>"
        echo "          <input type='number' name='global_down' value='$GLOBAL_DOWN' placeholder='0 = Unlimited' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'>"
        echo "        </div>"
        echo "        <div>"
        echo "          <label style='display:block; margin-bottom:5px; font-weight:600;'>Upload (Mbps)</label>"
        echo "          <input type='number' name='global_up' value='$GLOBAL_UP' placeholder='0 = Unlimited' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'>"
        echo "        </div>"
        echo "      </div>"
        echo "    </div>"
        
        echo "    <div id='user-sec' style='display:$([ "$QOS_MODE" = "per_user" ] && echo "block" || echo "none"); border-top:1px solid #eee; padding-top:20px;'>"
        echo "      <h4>Per-User Limits</h4>"
        echo "      <div style='display:grid; grid-template-columns: 1fr 1fr; gap:15px;'>"
        echo "        <div>"
        echo "          <label style='display:block; margin-bottom:5px; font-weight:600;'>Max Download (Mbps)</label>"
        echo "          <input type='number' name='user_down' value='$USER_DOWN' placeholder='e.g. 5' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'>"
        echo "        </div>"
        echo "        <div>"
        echo "          <label style='display:block; margin-bottom:5px; font-weight:600;'>Max Upload (Mbps)</label>"
        echo "          <input type='number' name='user_up' value='$USER_UP' placeholder='e.g. 1' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'>"
        echo "        </div>"
        echo "      </div>"
        echo "    </div>"
        
        echo "    <div style='margin-top:20px;'>"
        echo "      <button class='btn btn-primary' style='width:100%; padding:12px;'>Save & Apply Bandwidth Rules</button>"
        echo "    </div>"
        echo "  </form>"
        echo "</div>"

    elif [ "$TAB" = "portal" ]; then
        echo "<div class='header'><h1>Portal Editor</h1></div>"
        
        if echo "$QUERY_STRING" | grep -q "msg=portal_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Portal HTML Saved Successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=upload_success"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>File Uploaded Successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=theme_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Theme Saved Successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=theme_deleted"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Theme Deleted!</div>"; fi
        
        # HTML Editor
        # Read current portal html
        # We need to be careful with escaping HTML inside HTML
        # Using a simple cat might break the layout if it contains closing tags.
        # But since we are inside an echo block, we can just cat it? 
        # No, because we are generating the admin page via echo.
        # Safest way: Read file content and escape special chars for textarea.
        
        # FIX: Explicitly specify UTF-8 charset when reading/handling content
        PORTAL_CONTENT=$(cat /www/portal.html 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        
        echo "<div style='display:grid; grid-template-columns: 2fr 1fr; gap:20px; align-items:start;'>"
        echo "  <div class='card'>"
        echo "    <h3>HTML Source Code</h3>"
        echo "    <div style='display:flex; flex-wrap:wrap; gap:10px; margin-bottom:10px;'>"
        echo "      <button type='button' class='btn btn-primary' style='padding:8px 10px;' onclick=\"loadInstalledPortal()\">Load Installed</button>"
        echo "      <button type='button' class='btn btn-primary' style='padding:8px 10px; background:#0f172a;' onclick=\"applyTheme('theme_glass')\">Glass</button>"
        echo "      <button type='button' class='btn btn-primary' style='padding:8px 10px; background:#111827;' onclick=\"applyTheme('theme_dark_neon')\">Dark Neon</button>"
        echo "      <button type='button' class='btn btn-primary' style='padding:8px 10px; background:#334155;' onclick=\"applyTheme('theme_minimal')\">Minimal</button>"
        echo "      <button type='button' class='btn btn-primary' style='padding:8px 10px; background:#be123c;' onclick=\"applyTheme('theme_sunset')\">Sunset</button>"
        echo "    </div>"
        THEME_FILES=$(ls /www/portal_themes/custom_*.html 2>/dev/null)
        if [ -n "$THEME_FILES" ]; then
            echo "    <div style='border:1px solid #e2e8f0; border-radius:10px; padding:10px; margin-bottom:10px;'>"
            echo "      <div style='font-weight:700; margin-bottom:8px;'>Custom Themes</div>"
            for f in $THEME_FILES; do
                NAME=$(basename "$f" .html)
                LABEL=$(echo "$NAME" | sed 's/^custom_//' | tr '_' ' ')
                echo "      <div style='display:flex; gap:8px; align-items:center; margin-bottom:8px;'>"
                echo "        <button type='button' class='btn btn-primary' style='padding:8px 10px; background:#0f172a;' onclick=\"applyTheme('$NAME')\">$LABEL</button>"
                echo "        <form method='POST' style='margin:0;'>"
                echo "          <input type='hidden' name='action' value='delete_theme'>"
                echo "          <input type='hidden' name='theme_id' value='$NAME'>"
                echo "          <button class='btn btn-danger' type='submit' style='padding:8px 10px;'>Delete</button>"
                echo "        </form>"
                echo "      </div>"
            done
            echo "    </div>"
        fi

        echo "    <form id='portal-form' method='POST' accept-charset='UTF-8'>"
        echo "      <input type='hidden' id='portal-action' name='action' value='save_portal'>"
        echo "      <div style='display:flex; gap:10px; margin-bottom:10px; align-items:center;'>"
        echo "        <input id='theme-name' name='theme_name' placeholder='Theme name (e.g. MyTheme)' style='flex:1; padding:10px; border:1px solid #cbd5e1; border-radius:6px;'>"
        echo "        <button type='button' class='btn btn-primary' style='padding:10px 12px;' onclick=\"submitPortal('save_theme')\">Save as Theme</button>"
        echo "      </div>"
        echo "      <textarea id='portal-editor' name='html_content' style='width:100%; height:520px; font-family:monospace; padding:10px; border:1px solid #cbd5e1; border-radius:6px; box-sizing:border-box;' spellcheck='false'>$PORTAL_CONTENT</textarea>"
        echo "      <div style='margin-top:10px; display:flex; justify-content:flex-end; gap:10px;'>"
        echo "        <button type='button' class='btn btn-primary' onclick=\"submitPortal('save_portal')\">Save HTML Changes</button>"
        echo "      </div>"
        echo "    </form>"
        echo "  </div>"

        echo "  <div>"
        echo "    <div class='card' style='margin-bottom:20px;'>"
        echo "      <h3>Phone Preview</h3>"
        echo "      <div style='display:flex; justify-content:center;'>"
        echo "        <div style='width:320px; height:640px; background:#0f172a; border-radius:42px; padding:14px; box-shadow: 0 18px 40px rgba(0,0,0,0.25);'>"
        echo "          <div style='width:100%; height:100%; background:#fff; border-radius:30px; overflow:hidden;'>"
        echo "            <iframe id='portal-preview' style='width:100%; height:100%; border:0; background:#fff;'></iframe>"
        echo "          </div>"
        echo "        </div>"
        echo "      </div>"
        echo "      <p class='sub' style='margin-top:10px;'>Live preview habang nag-e-edit.</p>"
        echo "    </div>"

        echo "    <div class='card'>"
        echo "      <h3>Media Manager</h3>"
        echo "      <p class='sub'>Upload images or audio files for your portal.</p>"
        echo "      <div style='margin-bottom:20px; border-bottom:1px solid #eee; padding-bottom:20px;'>"
        echo "        <h4>Background Image</h4>"
        echo "        <p class='sub'>Replaces <code>bg.jpg</code></p>"
        echo "        <input type='file' id='file-bg' accept='image/*' style='margin-bottom:10px;'>"
        echo "        <button onclick=\"uploadFile('file-bg', 'bg.jpg')\" class='btn btn-primary' style='width:100%'>Upload Background</button>"
        echo "      </div>"
        echo "      <div style='margin-bottom:20px; border-bottom:1px solid #eee; padding-bottom:20px;'>"
        echo "        <h4>Insert Coin Audio</h4>"
        echo "        <p class='sub'>Replaces <code>insert.mp3</code></p>"
        echo "        <input type='file' id='file-insert' accept='audio/*' style='margin-bottom:10px;'>"
        echo "        <button onclick=\"uploadFile('file-insert', 'insert.mp3')\" class='btn btn-primary' style='width:100%'>Upload Audio</button>"
        echo "      </div>"
        echo "      <div>"
        echo "        <h4>Connected Audio</h4>"
        echo "        <p class='sub'>Replaces <code>connected.mp3</code></p>"
        echo "        <input type='file' id='file-connect' accept='audio/*' style='margin-bottom:10px;'>"
        echo "        <button onclick=\"uploadFile('file-connect', 'connected.mp3')\" class='btn btn-primary' style='width:100%'>Upload Audio</button>"
        echo "      </div>"
        echo "    </div>"
        echo "  </div>"
        echo "</div>"
        
        echo "<script>"
        echo "var _previewTimer = null;"
        echo "function _withBase(html) {"
        echo "  if(!html) return '';"
        echo "  if(html.toLowerCase().indexOf('<base ') !== -1) return html;"
        echo "  if(/<head[^>]*>/i.test(html)) { return html.replace(/<head[^>]*>/i, function(m){ return m + '<base href=\"/\">'; }); }"
        echo "  return '<base href=\"/\">' + html;"
        echo "}"
        echo "function updatePreviewNow() {"
        echo "  var ta = document.getElementById('portal-editor');"
        echo "  var fr = document.getElementById('portal-preview');"
        echo "  if(!ta || !fr) return;"
        echo "  fr.srcdoc = _withBase(ta.value);"
        echo "}"
        echo "function queuePreview() {"
        echo "  if(_previewTimer) clearTimeout(_previewTimer);"
        echo "  _previewTimer = setTimeout(updatePreviewNow, 250);"
        echo "}"
        echo "function loadInstalledPortal() {"
        echo "  fetch('/portal.html?ts=' + Date.now())"
        echo "    .then(function(r){ return r.text(); })"
        echo "    .then(function(html){ var ta=document.getElementById('portal-editor'); if(ta){ ta.value = html; } updatePreviewNow(); })"
        echo "    .catch(function(){ updatePreviewNow(); });"
        echo "}"
        echo "function applyTheme(name) {"
        echo "  fetch('/portal_themes/' + name + '.html?ts=' + Date.now())"
        echo "    .then(function(r){ return r.text(); })"
        echo "    .then(function(html){ var ta=document.getElementById('portal-editor'); if(ta){ ta.value = html; } updatePreviewNow(); })"
        echo "    .catch(function(){ alert('Failed to load theme.'); });"
        echo "}"
        echo "function submitPortal(actionName) {"
        echo "  var act = document.getElementById('portal-action');"
        echo "  var form = document.getElementById('portal-form');"
        echo "  if(!act || !form) return;"
        echo "  if(actionName === 'save_theme') {"
        echo "    var tn = document.getElementById('theme-name');"
        echo "    if(!tn || !tn.value) { alert('Enter theme name'); return; }"
        echo "  }"
        echo "  act.value = actionName;"
        echo "  form.submit();"
        echo "}"
        echo "function uploadFile(inputId, filename) {"
        echo "  var input = document.getElementById(inputId);"
        echo "  if(!input.files[0]) { alert('Please select a file first'); return; }"
        echo "  var file = input.files[0];"
        echo "  "
        echo "  var btn = input.nextElementSibling;"
        echo "  var originalText = btn.innerText;"
        echo "  btn.innerText = 'Uploading...';"
        echo "  btn.disabled = true;"
        echo "  "
        echo "  // Use Raw Binary Upload to avoid RAM limits"
        echo "  fetch('/cgi-bin/admin?action=upload_raw&filename=' + filename, {"
        echo "    method: 'POST',"
        echo "    body: file"
        echo "  })"
        echo "  .then(r => {"
        echo "      if(r.ok) {"
        echo "          alert('Upload Successful!');"
        echo "          window.location.reload();"
        echo "      } else {"
        echo "          alert('Upload Failed: ' + r.statusText);"
        echo "      }"
        echo "  })"
        echo "  .catch(e => alert('Error: ' + e))"
        echo "  .finally(() => {"
        echo "      btn.innerText = originalText;"
        echo "      btn.disabled = false;"
        echo "  });"
        echo "}"
        echo "document.addEventListener('DOMContentLoaded', function() {"
        echo "  var ta = document.getElementById('portal-editor');"
        echo "  if(ta){ ta.addEventListener('input', queuePreview); }"
        echo "  loadInstalledPortal();"
        echo "});"
        echo "</script>"

    elif [ "$TAB" = "settings" ]; then
        echo "<div class='header'><h1>Settings</h1></div>"
        
        if echo "$QUERY_STRING" | $GREP -q "msg=license_required"; then 
            echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px; font-weight:700;'>LICENSE REQUIRED: Access to other features is restricted until a valid license is activated.</div>"
        fi

        if echo "$QUERY_STRING" | $GREP -q "msg=saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Settings Saved Successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_env_loaded"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Supabase Credentials Loaded!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_env_missing"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Missing /etc/pisowifi/supabase.env</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_ok"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>License Activated!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_hw_mismatch"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>License is bound to a different device.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_not_found"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>License key not found.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_fetch_failed"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Could not reach Supabase.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_rls_denied"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Supabase denied access (RLS/permissions).</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_rls_empty"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Supabase returned no rows for anon key (check RLS/policies/grants).</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_bind_failed"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Could not bind license to this device.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_invalid"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Invalid License.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_missing_supabase"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Missing Supabase URL/Key.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_missing_key"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Missing License Key.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=license_cleared"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>License Cleared.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=centralized_ok"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Centralized Key Activated Successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=centralized_failed"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Failed to activate Centralized Key. Check format or connection.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=centralized_format_error"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Invalid Centralized Key Format. Must be CENTRAL-XXXXXXXX-XXXXXXXX.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=centralized_invalid_format"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Invalid Centralized Key Format. Must be CENTRAL-XXXXXXXX-XXXXXXXX.</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=centralized_cleared"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Centralized Key Cleared.</div>"; fi
        
        echo "<div class='grid' style='grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));'>"

        echo "  <div class='card'>"
        echo "    <h3>General Configuration</h3>"
        echo "    <form method='POST'>"
        echo "      <input type='hidden' name='action' value='update_settings'>"
        echo "      <div style='margin-bottom: 20px;'>"
        echo "        <label style='display:block; margin-bottom:8px; font-weight:600;'>New Admin Password</label>"
        echo "        <input type='password' name='new_pass' placeholder='Leave blank to keep current' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        echo "      </div>"
        echo "      <button class='btn btn-primary' style='width:100%; padding: 12px;'>Save Settings</button>"
        echo "    </form>"
        echo "  </div>"

        LIC_ENABLED=$("$UCI" get pisowifi.license.enabled 2>/dev/null || echo 0)
        LIC_VALID=$("$UCI" get pisowifi.license.valid 2>/dev/null || echo 0)
        LIC_VENDOR=$("$UCI" get pisowifi.license.vendor_id 2>/dev/null)
        [ -z "$LIC_VENDOR" ] || [ "$LIC_VENDOR" = "null" ] && LIC_VENDOR=$("$UCI" get pisowifi.license.vendor_uuid 2>/dev/null)
        [ -z "$LIC_VENDOR" ] && LIC_VENDOR=""
        LIC_VENDOR_NAME=$("$UCI" get pisowifi.license.vendor_name 2>/dev/null || echo "")
        LIC_KEY=$("$UCI" get pisowifi.license.license_key 2>/dev/null || echo "")
        LIC_EXPIRES=$("$UCI" get pisowifi.license.expires_at 2>/dev/null || echo "")
        LIC_LAST=$("$UCI" get pisowifi.license.last_check 2>/dev/null || echo 0)
        LIC_HW=$("$UCI" get pisowifi.license.hardware_id 2>/dev/null || echo "")
        LIC_HW_MATCH=$("$UCI" get pisowifi.license.hardware_match 2>/dev/null || echo 0)
        SUPA_URL=$("$UCI" get pisowifi.license.supabase_url 2>/dev/null || echo "")
        SUPA_KEY=$("$UCI" get pisowifi.license.supabase_key 2>/dev/null || echo "")

        ROUTER_MAC=$(cat /sys/class/net/br-lan/address 2>/dev/null || cat /sys/class/net/eth0/address 2>/dev/null || echo "unknown")
        if [ -x "$BB" ]; then
            ROUTER_HEX=$(printf "%s" "$ROUTER_MAC" | "$BB" tr -d ':' | "$BB" tr 'a-z' 'A-Z')
        else
            ROUTER_HEX=$(printf "%s" "$ROUTER_MAC" | tr -d ':' | tr 'a-z' 'A-Z')
        fi
        ROUTER_ID="$ROUTER_MAC"
        if command -v md5sum >/dev/null 2>&1 && [ "$ROUTER_HEX" != "UNKNOWN" ]; then
            HW_HEX=$(echo -n "$ROUTER_HEX" | md5sum 2>/dev/null | awk '{print toupper(substr($1,1,16))}')
            [ -n "$HW_HEX" ] && ROUTER_ID="CPU-$HW_HEX"
        fi
        [ -n "$LIC_KEY" ] && LIC_DISPLAY="$LIC_KEY" || LIC_DISPLAY="Not set"
        [ -f /etc/pisowifi/supabase.env ] && ENV_STATUS="Found" || ENV_STATUS="Missing"
        [ -n "$SUPA_URL" ] && URL_STATUS="Configured" || URL_STATUS="Not set"
        [ -n "$SUPA_KEY" ] && KEY_STATUS="Configured" || KEY_STATUS="Not set"

        echo "  <div class='card'>"
        echo "    <h3>OpenWrt License</h3>"
        echo "    <div class='sub' style='margin-top:-6px; margin-bottom:10px;'>PisoWifi OpenWrt License Management</div>"
        
        echo "    <div style='background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px; padding:14px; margin-bottom:16px;'>"
        echo "      <div style='margin-bottom:10px;'>"
        echo "        <div style='font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;'>Status</div>"
        echo "        <div style='font-weight:900; font-size:1.1rem; color:#0f172a;'>$([ "$LIC_VALID" = "1" ] && echo "<span style='color:#16a34a;'>ACTIVE</span>" || echo "<span style='color:#dc2626;'>INACTIVE</span>")</div>"
        echo "      </div>"
        echo "      <div>"
        echo "        <div style='font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;'>Hardware ID</div>"
        echo "        <div style='font-weight:900; font-size:0.95rem; word-break:break-all; font-family:monospace; color:#0f172a;'>$ROUTER_ID</div>"
        echo "      </div>"
        if [ -n "$LIC_VENDOR" ] && [ "$LIC_VENDOR" != "null" ]; then
            echo "      <div style='margin-top:10px;'>"
            echo "        <div style='font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;'>Vendor UUID</div>"
            echo "        <div style='font-weight:700; font-size:0.85rem; word-break:break-all; font-family:monospace; color:#475569;'>$LIC_VENDOR</div>"
            echo "      </div>"
        fi
        [ -n "$LIC_EXPIRES" ] && [ "$LIC_VALID" = "0" ] && [ "$LIC_STATUS" = "trial" ] && echo "      <div style='margin-top:10px; font-size:12px; color:#0369a1; font-weight:600;'>Trial expires: $LIC_EXPIRES</div>"
        echo "    </div>"

        echo "    <form method='POST' style='margin-bottom:12px;'>"
        echo "      <input type='hidden' name='action' value='activate_license'>"
        echo "      <div style='margin-bottom:10px;'>"
        echo "        <label style='display:block; margin-bottom:6px; font-weight:700; font-size:0.9rem;'>Activation Key</label>"
        echo "        <input type='text' name='license_key' placeholder='Enter license key' style='width:100%; padding:12px; border:1px solid #cbd5e1; border-radius:8px; font-size:1rem;'> "
        echo "      </div>"
        echo "      <button class='btn btn-primary' style='width:100%; padding:14px; font-weight:700;'>Activate License</button>"
        echo "    </form>"

        echo "    <div style='display:flex; gap:10px;'>"
        echo "      <form method='POST' style='flex:1;'><input type='hidden' name='action' value='license_check'><button class='btn btn-primary' style='width:100%; padding:12px; background:#0f172a; font-size:0.9rem;'>Check License</button></form>"
        echo "      <form method='POST' style='flex:1;'><input type='hidden' name='action' value='clear_license'><button class='btn btn-danger' style='width:100%; padding:12px; font-size:0.9rem;'>Clear</button></form>"
        echo "    </div>"
        echo "  </div>"

        CENTRAL_KEY=$("$UCI" get pisowifi.license.centralized_key 2>/dev/null || echo "")
        CENTRAL_VENDOR=$("$UCI" get pisowifi.license.centralized_vendor_id 2>/dev/null || echo "")
        CENTRAL_STATUS=$("$UCI" get pisowifi.license.centralized_status 2>/dev/null || echo "")

        echo "  <div class='card' id='centralized-card' style='display:block !important;'>"
        echo "    <h3>Centralized Key</h3>"
        echo "    <div class='sub' style='margin-top:-6px; margin-bottom:10px;'>Centralized License Management</div>"
        
        echo "    <div style='background:#f8fafc; border:1px solid #e2e8f0; border-radius:10px; padding:14px; margin-bottom:16px;'>"
        echo "      <div style='margin-bottom:10px;'>"
        echo "        <div style='font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;'>Status</div>"
        if [ "$CENTRAL_STATUS" = "active" ]; then
            echo "        <div style='font-weight:900; font-size:1.1rem; color:#16a34a;'>ACTIVE</div>"
        else
            echo "        <div style='font-weight:900; font-size:1.1rem; color:#dc2626;'>INACTIVE</div>"
        fi
        echo "      </div>"
        echo "      <div>"
        echo "        <div style='font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;'>Centralized Key</div>"
        if [ -n "$CENTRAL_KEY" ]; then
            echo "        <div style='font-weight:900; font-size:0.95rem; word-break:break-all; font-family:monospace; color:#0f172a;'>$CENTRAL_KEY</div>"
        else
            echo "        <div style='font-weight:900; font-size:0.95rem; word-break:break-all; font-family:monospace; color:#64748b;'>Not Assigned</div>"
        fi
        echo "      </div>"
        if [ -n "$CENTRAL_VENDOR" ]; then
            echo "      <div style='margin-top:10px;'>"
            echo "        <div style='font-size:12px; color:#64748b; font-weight:700; text-transform:uppercase; letter-spacing:0.5px;'>Vendor UUID</div>"
            echo "        <div style='font-weight:700; font-size:0.85rem; word-break:break-all; font-family:monospace; color:#475569;'>$CENTRAL_VENDOR</div>"
            echo "      </div>"
        fi
        echo "    </div>"

        echo "    <form method='POST' style='margin-bottom:12px;'>"
        echo "      <input type='hidden' name='action' value='activate_centralized_license'>"
        echo "      <div style='margin-bottom:10px;'>"
        echo "        <label style='display:block; margin-bottom:6px; font-weight:700; font-size:0.9rem;'>Centralized Key</label>"
        echo "        <input type='text' name='centralized_key' placeholder='CENTRAL-XXXXXXXX-XXXXXXXX' style='width:100%; padding:12px; border:1px solid #cbd5e1; border-radius:8px; font-size:1rem;'> "
        echo "      </div>"
        echo "      <button class='btn btn-primary' style='width:100%; padding:14px; font-weight:700; background:linear-gradient(135deg, #8b5cf6, #d946ef); border:none;'>Activate Centralized Key</button>"
        echo "    </form>"
        
        echo "    <div style='display:flex; gap:10px;'>"
        echo "      <form method='POST' style='flex:1;'><input type='hidden' name='action' value='clear_centralized_license'><button class='btn btn-danger' style='width:100%; padding:12px; font-size:0.9rem;'>Clear Centralized Key</button></form>"
        echo "    </div>"
        
        echo "  </div>"

        echo "</div>"
    fi

    echo "</div>" # End Container
    echo "</div>" # End Main Content

echo "</body></html>"
EOF
chmod +x /www/cgi-bin/admin

mkdir -p /www/portal_themes

cat << 'HTML' > /www/portal_themes/theme_glass.html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>NEXI-FI PISOWIFI</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { --bg1:#0ea5e9; --bg2:#a855f7; --card:rgba(255,255,255,0.18); --text:#0b1220; --muted:rgba(15,23,42,0.65); --stroke:rgba(255,255,255,0.35); --shadow: rgba(0,0,0,0.25); --primary:#2563eb; --success:#16a34a; --danger:#dc2626; --warn:#f59e0b; }
*{box-sizing:border-box}
body{margin:0; font-family: system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif; color:var(--text); min-height:100vh; display:flex; align-items:center; justify-content:center; padding:22px; background: radial-gradient(1200px 700px at 20% 10%, rgba(255,255,255,0.35), transparent 50%), radial-gradient(900px 600px at 90% 20%, rgba(255,255,255,0.28), transparent 55%), linear-gradient(135deg, var(--bg1), var(--bg2));}
.shell{width:100%; max-width:520px;}
.brand{display:flex; align-items:center; justify-content:space-between; margin-bottom:14px; color:white}
.brand h1{font-size:18px; margin:0; letter-spacing:.08em; text-transform:uppercase}
.pill{font-size:12px; padding:6px 10px; border:1px solid rgba(255,255,255,0.35); border-radius:999px; background:rgba(255,255,255,0.14); backdrop-filter: blur(10px);}
.card{background:var(--card); border:1px solid var(--stroke); border-radius:18px; box-shadow: 0 20px 50px var(--shadow); padding:18px; backdrop-filter: blur(14px);}
.device{display:flex; gap:10px; align-items:flex-start; padding:12px; border-radius:14px; background:rgba(255,255,255,0.12); border:1px solid rgba(255,255,255,0.22); margin-bottom:12px}
.device strong{color:rgba(255,255,255,0.9)}
.device div{color:rgba(255,255,255,0.85); font-size:13px; line-height:1.4}
.title{color:white; margin:0 0 12px 0; font-size:20px}
.sub{color:rgba(255,255,255,0.85); font-size:13px; margin:0 0 10px 0}
button{width:100%; padding:14px 14px; font-size:15px; font-weight:700; border:0; border-radius:14px; cursor:pointer; color:white; box-shadow: 0 10px 20px rgba(0,0,0,0.18); transition: transform .08s ease;}
button:active{transform: scale(0.99);}
.btn-primary{background:linear-gradient(135deg, rgba(37,99,235,0.95), rgba(14,165,233,0.95));}
.btn-success{background:linear-gradient(135deg, rgba(22,163,74,0.95), rgba(34,197,94,0.95));}
.btn-danger{background:linear-gradient(135deg, rgba(220,38,38,0.95), rgba(244,63,94,0.95));}
.btn-warn{background:linear-gradient(135deg, rgba(245,158,11,0.95), rgba(251,191,36,0.95));}
.row{display:flex; gap:10px}
.row button{width:100%}
.muted{font-size:12px; color:rgba(255,255,255,0.8); margin-top:10px; text-align:center}
.modal{display:none; position:fixed; z-index:10; left:0; top:0; width:100%; height:100%; background: rgba(0,0,0,0.55); padding:20px;}
.modal-content{background:rgba(255,255,255,0.9); margin:12vh auto 0; padding:18px; width:100%; max-width:420px; border-radius:16px; box-shadow: 0 20px 50px rgba(0,0,0,0.25);}
.modal-content h2{margin:0 0 8px 0}
.modal-content p{margin:0 0 14px 0; color:#334155}
.modal-content .stats{font-size:18px; margin:14px 0; color:#0f172a}
.link-btn{background:none; color:#dc2626; box-shadow:none; padding:10px; font-weight:700}
</style>
</head>
<body>
<div class="shell">
  <div class="brand">
    <h1>NEXI-FI</h1>
    <div class="pill">PISOWIFI PORTAL</div>
  </div>
  <div class="card">
    <h2 class="title">Welcome</h2>
    <p class="sub">Insert coin to connect. Manage your time anytime.</p>
    <div class="device">
      <div style="flex:1">
        <strong>Device Info</strong>
        <div>MAC: <span id="info-mac">Loading...</span></div>
        <div>IP: <span id="info-ip">Loading...</span></div>
      </div>
    </div>

    <div id="loading" class="sub">Loading...</div>

    <div id="login-section" style="display:none;">
      <button onclick="playAudio('insert'); startCoin()" class="btn-success">INSERT COIN</button>
      <button onclick="openRates()" class="btn-primary" style="margin-top:10px; background:rgba(255,255,255,0.18); border:1px solid rgba(255,255,255,0.30);">RATES</button>
      <div class="muted">Press WPS button on router when prompted.</div>
    </div>

    <div id="resume-section" style="display:none;">
      <h3 class="title" style="font-size:18px">Session Paused</h3>
      <p class="sub">Time Remaining: <strong id="paused-time"></strong></p>
      <button onclick="resumeTime()" class="btn-primary">RESUME TIME</button>
    </div>

    <div id="connected-section" style="display:none;">
      <h3 class="title" style="font-size:18px">Connected</h3>
      <p class="sub">MAC: <span id="client-mac"></span></p>
      <p class="sub">Time Remaining: <strong id="time-remaining">Loading...</strong></p>
      <p id="internet-status" class="sub">Checking internet...</p>
      <div style="margin-top:10px">
        <button onclick="openRates()" class="btn-primary" style="background:rgba(255,255,255,0.18); border:1px solid rgba(255,255,255,0.30);">RATES</button>
      </div>
      <div class="row" style="margin-top:10px">
        <button onclick="playAudio('insert'); startCoin()" class="btn-success">ADD TIME</button>
        <button onclick="pauseTime()" class="btn-warn">PAUSE</button>
      </div>
      <div style="margin-top:10px">
        <button onclick="logout()" class="btn-danger">LOGOUT</button>
      </div>
    </div>
  </div>
</div>

<div id="coin-modal" class="modal">
  <div class="modal-content">
    <h2>Insert Coin</h2>
    <p>Press WPS button on router</p>
    <div class="stats">
      <div><span id="coin-count">0</span> Pesos</div>
      <div><span id="coin-time">0</span> Minutes</div>
    </div>
    <button id="connect-btn" onclick="playAudio('connect'); connect()" class="btn-primary" style="display:none;">START INTERNET</button>
    <button onclick="closeModal()" class="link-btn">Cancel</button>
  </div>
</div>

<div id="rates-modal" class="modal">
  <div class="modal-content">
    <h2>Rates</h2>
    <div id="rates-body" class="sub" style="color:#0f172a;">Loading...</div>
    <button onclick="closeRates()" class="link-btn">Close</button>
  </div>
</div>

<audio id="audio-insert" src="/insert.mp3"></audio>
<audio id="audio-connect" src="/connected.mp3"></audio>

<script>
var apiUrl = "/cgi-bin/pisowifi";
var interval;
var timerInterval;
var timeLeft = 0;

function openRates() {
  var m = document.getElementById("rates-modal");
  if(m) m.style.display = "block";
  loadRates();
}

function closeRates() {
  var m = document.getElementById("rates-modal");
  if(m) m.style.display = "none";
}

function loadRates() {
  fetch(apiUrl + "?action=rates")
    .then(function(r){ return r.json(); })
    .then(function(d){
      var el = document.getElementById("rates-body");
      if(!el) return;
      if(!d || !d.rates || !d.rates.length) { el.innerHTML = "<div>No rates set.</div>"; return; }
      var html = "<div style='display:grid; gap:8px; margin-top:10px;'>";
      d.rates.forEach(function(x){
        html += "<div style='display:flex; justify-content:space-between; padding:10px; border-radius:12px; background:rgba(2,6,23,0.06);'>";
        html += "<div style='font-weight:800;'>₱" + x.amount + "</div>";
        html += "<div>" + x.minutes + " min</div>";
        html += "</div>";
      });
      html += "</div>";
      el.innerHTML = html;
    })
    .catch(function(){
      var el = document.getElementById("rates-body");
      if(el) el.innerHTML = "<div>Failed to load rates.</div>";
    });
}

function playAudio(type) {
  try {
    stopAudio();
    var audio = document.getElementById("audio-" + type);
    if (audio) { audio.currentTime = 0; audio.play().catch(() => {}); }
  } catch(e) {}
}

function stopAudio() {
  try {
    var sounds = document.querySelectorAll('audio');
    sounds.forEach(function(sound) { sound.pause(); sound.currentTime = 0; });
  } catch(e) {}
}

function formatTime(s) {
  if (s <= 0) return "Expired";
  var d = Math.floor(s/86400);
  var h = Math.floor((s%86400)/3600);
  var m = Math.floor((s%3600)/60);
  var sec = s%60;
  var timeStr = "";
  if(d > 0) timeStr += d + "d ";
  if(h > 0) timeStr += h + "h ";
  if(m > 0) timeStr += m + "m ";
  timeStr += sec + "s";
  return timeStr.trim();
}

function startTimer() {
  if (timerInterval) clearInterval(timerInterval);
  timerInterval = setInterval(function() {
    if(timeLeft > 0) {
      timeLeft--;
      var el = document.getElementById("time-remaining");
      if (el) el.innerText = formatTime(timeLeft);
    } else {
      clearInterval(timerInterval);
      checkStatus();
    }
  }, 1000);
}

function checkInternet() {
  var img = new Image();
  var now = new Date().getTime();
  img.src = "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?t=" + now;
  img.onload = function() {
    var el = document.getElementById("internet-status");
    if(el) { el.innerText = "Internet: ONLINE"; }
    fetch(apiUrl + "?action=log_internet&status=ONLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN"));
  };
  img.onerror = function() {
    var el = document.getElementById("internet-status");
    if(el) { el.innerText = "Internet: OFFLINE"; }
    fetch(apiUrl + "?action=log_internet&status=OFFLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN"));
  };
}

function checkStatus() {
  fetch(apiUrl + "?action=status")
    .then(r => { if(!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(data => {
      if(data.mac) { var a=document.getElementById("info-mac"); if(a) a.innerText=data.mac; }
      if(data.ip) { var b=document.getElementById("info-ip"); if(b) b.innerText=data.ip; }
      var loading = document.getElementById("loading"); if(loading) loading.style.display="none";
      if(data.authenticated === "true") {
        document.getElementById("login-section").style.display="none";
        document.getElementById("resume-section").style.display="none";
        document.getElementById("connected-section").style.display="block";
        timeLeft = parseInt(data.time_remaining);
        document.getElementById("time-remaining").innerText = formatTime(timeLeft);
        if(data.mac) document.getElementById("client-mac").innerText = data.mac;
        startTimer();
        checkInternet();
        setTimeout(checkStatus, 5000);
      } else if(data.authenticated === "paused") {
        document.getElementById("login-section").style.display="none";
        document.getElementById("connected-section").style.display="none";
        document.getElementById("resume-section").style.display="block";
        document.getElementById("paused-time").innerText = formatTime(data.time_remaining);
        if(timerInterval) clearInterval(timerInterval);
        setTimeout(checkStatus, 10000);
      } else {
        document.getElementById("login-section").style.display="block";
        document.getElementById("resume-section").style.display="none";
        document.getElementById("connected-section").style.display="none";
        if(timerInterval) clearInterval(timerInterval);
      }
    })
    .catch(() => {
      var loading = document.getElementById("loading"); if(loading) loading.style.display="none";
      document.getElementById("login-section").style.display="block";
    });
}

function pauseTime() {
  if(!confirm("Pause Internet? You can resume later.")) return;
  fetch(apiUrl + "?action=pause").then(r => r.json()).then(data => {
    if(data.status === "paused") { alert("Internet Paused. Time saved: " + formatTime(data.remaining)); checkStatus(); }
    else { alert("Error: " + (data.error || "Failed to pause")); }
  }).catch(() => {});
}

function resumeTime() {
  fetch(apiUrl + "?action=resume").then(r => r.json()).then(data => {
    if(data.status === "resumed") checkStatus();
    else alert("Error: " + (data.error || "Failed to resume"));
  }).catch(() => {});
}

function startCoin() {
  // Try to acquire lock and start coin session in one atomic operation
  fetch(apiUrl + "?action=start_coin").then(r => r.json()).then(data => {
    if(data.status === "started" && data.lock_acquired) {
      // Successfully acquired lock - show modal
      document.getElementById("coin-modal").style.display="block";
      document.getElementById("coin-count").innerText="0";
      document.getElementById("coin-time").innerText="0";
      document.getElementById("connect-btn").style.display="none";
        if(interval) clearInterval(interval);
        interval = setInterval(() => {
          fetch(apiUrl + "?action=check_coin").then(r => r.json()).then(d => {
            document.getElementById("coin-count").innerText = d.count;
            document.getElementById("coin-time").innerText = d.minutes;
            if(d.count > 0) document.getElementById("connect-btn").style.display="block";
          }).catch(() => {});
        }, 1000);
      } else if(data.error && data.error.includes("locked by another device")) {
        // Coinslot is locked by another device
        alert("Coinslot is currently in use by another device. Please try again later.");
      } else if(data.error) {
        alert(data.error + " (Device: " + data.locked_by_mac + ")");
      } else {
        alert("Failed to start coin session. Please try again.");
      }
    })
    .catch(() => { alert("Failed to start coin session. Please refresh the page."); });
}

function connect() {
  stopAudio();
  playAudio('connect');
  fetch(apiUrl + "?action=connect").then(r => r.json()).then(data => {
    closeModal();
    if(data.status === "connected") {
      checkStatus();
      if(data.redirect_url) setTimeout(() => { window.location.href = data.redirect_url; }, 2000);
    } else {
      alert(data.error || "Connection failed");
    }
  }).catch(() => { alert("Failed to connect. Please try again."); });
}

function logout() {
  fetch(apiUrl + "?action=logout").then(r => r.json()).then(() => checkStatus()).catch(() => checkStatus());
}

function closeModal() {
  document.getElementById("coin-modal").style.display="none";
  if(interval) clearInterval(interval);
  stopAudio();
  
  // Release coinslot lock when closing modal
  fetch(apiUrl + "?action=release_coinslot_lock")
  .then(r => r.json())
  .then(data => {
    console.log("Coinslot lock released:", data);
  })
  .catch(err => console.error("Failed to release lock:", err));
}

setTimeout(function() {
  fetch(apiUrl + "?action=test_dns").then(r => r.json()).then(() => {}).catch(() => {});
}, 3000);
checkStatus();
</script>
</body>
</html>
HTML

cat << 'HTML' > /www/portal_themes/theme_dark_neon.html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>NEXI-FI PISOWIFI</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { --bg:#070a12; --card:#0b1020; --stroke:#1f2a44; --text:#e5e7eb; --muted:#94a3b8; --neon:#22c55e; --blue:#38bdf8; --pink:#fb7185; --warn:#fbbf24; }
*{box-sizing:border-box}
body{margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; padding:22px; background:
 radial-gradient(800px 500px at 15% 10%, rgba(56,189,248,0.18), transparent 60%),
 radial-gradient(700px 500px at 90% 20%, rgba(251,113,133,0.16), transparent 55%),
 radial-gradient(1000px 700px at 50% 110%, rgba(34,197,94,0.10), transparent 60%),
 var(--bg);
 color:var(--text); font-family: system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;}
.shell{width:100%; max-width:520px}
.top{display:flex; align-items:center; justify-content:space-between; margin-bottom:12px}
.logo{display:flex; flex-direction:column}
.logo strong{letter-spacing:.12em; text-transform:uppercase; font-size:14px}
.logo span{color:var(--muted); font-size:12px}
.badge{border:1px solid rgba(56,189,248,0.35); background: rgba(56,189,248,0.10); padding:6px 10px; border-radius:999px; font-size:12px; color:#e0f2fe}
.card{background: linear-gradient(180deg, rgba(11,16,32,0.85), rgba(11,16,32,0.70)); border:1px solid rgba(31,42,68,0.85); border-radius:18px; padding:18px; box-shadow: 0 20px 60px rgba(0,0,0,0.55); backdrop-filter: blur(10px);}
.h1{margin:0 0 6px 0; font-size:20px}
.sub{margin:0 0 12px 0; color:var(--muted); font-size:13px}
.info{display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin-bottom:12px}
.chip{border:1px solid rgba(31,42,68,0.85); background: rgba(2,6,23,0.35); border-radius:14px; padding:10px}
.chip b{display:block; font-size:11px; color:var(--muted); margin-bottom:4px; text-transform:uppercase; letter-spacing:.08em}
.chip span{font-size:12px}
button{width:100%; padding:14px; border-radius:14px; border:1px solid rgba(31,42,68,0.85); background: rgba(2,6,23,0.25); color:var(--text); font-weight:800; cursor:pointer; transition: transform .08s ease, box-shadow .2s ease; box-shadow: 0 10px 24px rgba(0,0,0,0.35);}
button:active{transform:scale(0.99)}
.primary{background: linear-gradient(135deg, rgba(56,189,248,0.25), rgba(56,189,248,0.10)); border-color: rgba(56,189,248,0.45)}
.success{background: linear-gradient(135deg, rgba(34,197,94,0.25), rgba(34,197,94,0.10)); border-color: rgba(34,197,94,0.45)}
.danger{background: linear-gradient(135deg, rgba(251,113,133,0.25), rgba(251,113,133,0.10)); border-color: rgba(251,113,133,0.45)}
.warn{background: linear-gradient(135deg, rgba(251,191,36,0.25), rgba(251,191,36,0.10)); border-color: rgba(251,191,36,0.45)}
.row{display:flex; gap:10px}
.row button{width:100%}
.note{margin-top:10px; font-size:12px; color:var(--muted); text-align:center}
.modal{display:none; position:fixed; z-index:10; left:0; top:0; width:100%; height:100%; background: rgba(0,0,0,0.65); padding:20px;}
.modal-content{background: #0b1020; border:1px solid rgba(31,42,68,0.85); margin:12vh auto 0; padding:18px; width:100%; max-width:420px; border-radius:16px;}
.modal-content h2{margin:0 0 8px 0}
.modal-content p{margin:0 0 12px 0; color:var(--muted)}
.stats{display:flex; gap:12px; margin:14px 0}
.stats div{flex:1; border:1px solid rgba(31,42,68,0.85); border-radius:14px; padding:12px; background: rgba(2,6,23,0.35);}
.stats div b{display:block; font-size:11px; color:var(--muted); margin-bottom:4px; text-transform:uppercase; letter-spacing:.08em}
.link{background:none; border:none; box-shadow:none; color:#fb7185; padding:10px; font-weight:800}
</style>
</head>
<body>
<div class="shell">
  <div class="top">
    <div class="logo"><strong>NEXI-FI</strong><span>Neon Portal</span></div>
    <div class="badge">Secure Access</div>
  </div>
  <div class="card">
    <div class="h1">Connect to WiFi</div>
    <p class="sub">Insert coin to start. Pause and resume anytime.</p>
    <div class="info">
      <div class="chip"><b>MAC</b><span id="info-mac">Loading...</span></div>
      <div class="chip"><b>IP</b><span id="info-ip">Loading...</span></div>
    </div>
    <div id="loading" class="sub">Loading...</div>

    <div id="login-section" style="display:none;">
      <button onclick="playAudio('insert'); startCoin()" class="success">INSERT COIN</button>
      <button onclick="openRates()" class="primary" style="margin-top:10px;">RATES</button>
      <div class="note">Press WPS button on router when prompted.</div>
    </div>

    <div id="resume-section" style="display:none;">
      <div class="h1" style="font-size:18px">Session Paused</div>
      <p class="sub">Time Remaining: <strong id="paused-time"></strong></p>
      <button onclick="resumeTime()" class="primary">RESUME TIME</button>
    </div>

    <div id="connected-section" style="display:none;">
      <div class="h1" style="font-size:18px">Connected</div>
      <p class="sub">MAC: <span id="client-mac"></span></p>
      <p class="sub">Time Remaining: <strong id="time-remaining">Loading...</strong></p>
      <p id="internet-status" class="sub">Checking internet...</p>
      <div style="margin-top:10px">
        <button onclick="openRates()" class="primary">RATES</button>
      </div>
      <div class="row" style="margin-top:10px">
        <button onclick="playAudio('insert'); startCoin()" class="success">ADD TIME</button>
        <button onclick="pauseTime()" class="warn">PAUSE</button>
      </div>
      <div style="margin-top:10px">
        <button onclick="logout()" class="danger">LOGOUT</button>
      </div>
    </div>
  </div>
</div>

<div id="coin-modal" class="modal">
  <div class="modal-content">
    <h2>Insert Coin</h2>
    <p>Press WPS button on router</p>
    <div class="stats">
      <div><b>Coins</b><span id="coin-count">0</span></div>
      <div><b>Minutes</b><span id="coin-time">0</span></div>
    </div>
    <button id="connect-btn" onclick="playAudio('connect'); connect()" class="primary" style="display:none;">START INTERNET</button>
    <button onclick="closeModal()" class="link">Cancel</button>
  </div>
</div>

<div id="rates-modal" class="modal">
  <div class="modal-content">
    <h2>Rates</h2>
    <p class="sub" style="margin-top:-6px;">Current rates</p>
    <div id="rates-body" class="sub">Loading...</div>
    <button onclick="closeRates()" class="link">Close</button>
  </div>
</div>

<audio id="audio-insert" src="/insert.mp3"></audio>
<audio id="audio-connect" src="/connected.mp3"></audio>

<script>
var apiUrl = "/cgi-bin/pisowifi";
var interval;
var timerInterval;
var timeLeft = 0;

function openRates(){var m=document.getElementById("rates-modal");if(m)m.style.display="block";loadRates();}
function closeRates(){var m=document.getElementById("rates-modal");if(m)m.style.display="none";}
function loadRates(){fetch(apiUrl+"?action=rates").then(r=>r.json()).then(function(d){var el=document.getElementById("rates-body");if(!el)return;if(!d||!d.rates||!d.rates.length){el.innerHTML="<div>No rates set.</div>";return;}var html="<div style='display:grid; gap:8px; margin-top:10px;'>";d.rates.forEach(function(x){html+="<div style='display:flex; justify-content:space-between; padding:10px; border-radius:12px; border:1px solid rgba(31,42,68,0.85); background: rgba(2,6,23,0.35);'><div style='font-weight:800;'>₱"+x.amount+"</div><div>"+x.minutes+" min</div></div>";});html+="</div>";el.innerHTML=html;}).catch(function(){var el=document.getElementById("rates-body");if(el)el.innerHTML="<div>Failed to load rates.</div>";});}

function playAudio(type){try{stopAudio();var a=document.getElementById("audio-"+type);if(a){a.currentTime=0;a.play().catch(()=>{});}}catch(e){}}
function stopAudio(){try{document.querySelectorAll("audio").forEach(function(s){s.pause();s.currentTime=0;});}catch(e){}}
function formatTime(s){if(s<=0)return"Expired";var d=Math.floor(s/86400),h=Math.floor((s%86400)/3600),m=Math.floor((s%3600)/60),sec=s%60,t="";if(d>0)t+=d+"d ";if(h>0)t+=h+"h ";if(m>0)t+=m+"m ";t+=sec+"s";return t.trim();}
function startTimer(){if(timerInterval)clearInterval(timerInterval);timerInterval=setInterval(function(){if(timeLeft>0){timeLeft--;var el=document.getElementById("time-remaining");if(el)el.innerText=formatTime(timeLeft);}else{clearInterval(timerInterval);checkStatus();}},1000);}
function checkInternet(){var img=new Image();var now=new Date().getTime();img.src="https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?t="+now;img.onload=function(){var el=document.getElementById("internet-status");if(el){el.innerText="Internet: ONLINE";}fetch(apiUrl+"?action=log_internet&status=ONLINE&mac="+encodeURIComponent(document.getElementById("client-mac")?document.getElementById("client-mac").innerText:"UNKNOWN"));};img.onerror=function(){var el=document.getElementById("internet-status");if(el){el.innerText="Internet: OFFLINE";}fetch(apiUrl+"?action=log_internet&status=OFFLINE&mac="+encodeURIComponent(document.getElementById("client-mac")?document.getElementById("client-mac").innerText:"UNKNOWN"));};}
function checkStatus(){fetch(apiUrl+"?action=status").then(r=>{if(!r.ok)throw new Error("HTTP "+r.status);return r.json();}).then(data=>{if(data.mac){var a=document.getElementById("info-mac");if(a)a.innerText=data.mac;}if(data.ip){var b=document.getElementById("info-ip");if(b)b.innerText=data.ip;}var loading=document.getElementById("loading");if(loading)loading.style.display="none";if(data.authenticated==="true"){document.getElementById("login-section").style.display="none";document.getElementById("resume-section").style.display="none";document.getElementById("connected-section").style.display="block";timeLeft=parseInt(data.time_remaining);document.getElementById("time-remaining").innerText=formatTime(timeLeft);if(data.mac)document.getElementById("client-mac").innerText=data.mac;startTimer();checkInternet();setTimeout(checkStatus,5000);}else if(data.authenticated==="paused"){document.getElementById("login-section").style.display="none";document.getElementById("connected-section").style.display="none";document.getElementById("resume-section").style.display="block";document.getElementById("paused-time").innerText=formatTime(data.time_remaining);if(timerInterval)clearInterval(timerInterval);setTimeout(checkStatus,10000);}else{document.getElementById("login-section").style.display="block";document.getElementById("resume-section").style.display="none";document.getElementById("connected-section").style.display="none";if(timerInterval)clearInterval(timerInterval);}}).catch(()=>{var loading=document.getElementById("loading");if(loading)loading.style.display="none";document.getElementById("login-section").style.display="block";});}
function pauseTime(){if(!confirm("Pause Internet? You can resume later."))return;fetch(apiUrl+"?action=pause").then(r=>r.json()).then(d=>{if(d.status==="paused"){alert("Internet Paused. Time saved: "+formatTime(d.remaining));checkStatus();}else{alert("Error: "+(d.error||"Failed to pause"));}}).catch(()=>{});}
function resumeTime(){fetch(apiUrl+"?action=resume").then(r=>r.json()).then(d=>{if(d.status==="resumed")checkStatus();else alert("Error: "+(d.error||"Failed to resume"));}).catch(()=>{});}
function startCoin(){// Try to acquire lock and start coin session in one atomic operation
fetch(apiUrl+"?action=start_coin").then(r=>r.json()).then(data=>{if(data.status==="started"&&data.lock_acquired){// Successfully acquired lock - show modal
document.getElementById("coin-modal").style.display="block";document.getElementById("coin-count").innerText="0";document.getElementById("coin-time").innerText="0";document.getElementById("connect-btn").style.display="none";if(interval)clearInterval(interval);interval=setInterval(()=>{fetch(apiUrl+"?action=check_coin").then(r=>r.json()).then(d=>{document.getElementById("coin-count").innerText=d.count;document.getElementById("coin-time").innerText=d.minutes;if(d.count>0)document.getElementById("connect-btn").style.display="block";}).catch(()=>{});},1000);}else if(data.error&&data.error.includes("locked by another device")){// Coinslot is locked by another device
alert("Coinslot is currently in use by another device. Please try again later.");}else if(data.error){alert(data.error+" (Device: "+data.locked_by_mac+")");}else{alert("Failed to start coin session. Please try again.");}}).catch(()=>{alert("Failed to start coin session. Please refresh the page.");});}
function connect(){stopAudio();playAudio("connect");fetch(apiUrl+"?action=connect").then(r=>r.json()).then(d=>{closeModal();if(d.status==="connected"){checkStatus();if(d.redirect_url)setTimeout(()=>{window.location.href=d.redirect_url;},2000);}else{alert(d.error||"Connection failed");}}).catch(()=>{alert("Failed to connect. Please try again.");});}
function logout(){fetch(apiUrl+"?action=logout").then(r=>r.json()).then(()=>checkStatus()).catch(()=>checkStatus());}
function closeModal(){document.getElementById("coin-modal").style.display="none";if(interval)clearInterval(interval);stopAudio();// Release coinslot lock when closing modal
fetch(apiUrl+"?action=release_coinslot_lock").then(r=>r.json()).then(data=>{console.log("Coinslot lock released:",data);}).catch(err=>console.error("Failed to release lock:",err));}
setTimeout(function(){fetch(apiUrl+"?action=test_dns").then(r=>r.json()).then(()=>{}).catch(()=>{});},3000);
checkStatus();
</script>
</body>
</html>
HTML

cat << 'HTML' > /www/portal_themes/theme_minimal.html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>NEXI-FI PISOWIFI</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{--bg:#f8fafc;--card:#ffffff;--text:#0f172a;--muted:#64748b;--border:#e2e8f0;--primary:#2563eb;--success:#16a34a;--danger:#dc2626;--warn:#f59e0b;}
*{box-sizing:border-box}
body{margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; padding:18px; background: radial-gradient(1000px 600px at 20% 0%, rgba(37,99,235,0.08), transparent 55%), radial-gradient(900px 500px at 90% 15%, rgba(22,163,74,0.06), transparent 55%), var(--bg); font-family: system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif; color:var(--text);}
.shell{width:100%; max-width:520px}
.card{background:var(--card); border:1px solid var(--border); border-radius:16px; padding:18px; box-shadow: 0 10px 25px rgba(2,6,23,0.08);}
.top{display:flex; align-items:center; justify-content:space-between; margin-bottom:12px}
.top h1{font-size:16px; margin:0; letter-spacing:.08em; text-transform:uppercase}
.top span{font-size:12px; color:var(--muted)}
.info{display:grid; grid-template-columns: 1fr 1fr; gap:10px; margin:12px 0}
.chip{border:1px solid var(--border); border-radius:12px; padding:10px}
.chip b{display:block; font-size:11px; color:var(--muted); margin-bottom:4px; text-transform:uppercase; letter-spacing:.08em}
.chip span{font-size:12px}
.h2{margin:0; font-size:18px}
.sub{margin:6px 0 0 0; color:var(--muted); font-size:13px}
button{width:100%; padding:14px; border-radius:12px; border:1px solid var(--border); background:#f1f5f9; font-weight:800; cursor:pointer; transition: transform .08s ease;}
button:active{transform:scale(0.99)}
.primary{background:var(--primary); border-color:var(--primary); color:white}
.success{background:var(--success); border-color:var(--success); color:white}
.danger{background:var(--danger); border-color:var(--danger); color:white}
.warn{background:var(--warn); border-color:var(--warn); color:white}
.row{display:flex; gap:10px; margin-top:10px}
.row button{width:100%}
.note{margin-top:12px; font-size:12px; color:var(--muted); text-align:center}
.modal{display:none; position:fixed; z-index:10; left:0; top:0; width:100%; height:100%; background: rgba(2,6,23,0.5); padding:18px;}
.modal-content{background:var(--card); border:1px solid var(--border); margin:12vh auto 0; padding:18px; width:100%; max-width:420px; border-radius:14px;}
.modal-content h2{margin:0 0 8px 0}
.modal-content p{margin:0 0 12px 0; color:var(--muted)}
.stats{display:flex; gap:12px; margin:14px 0}
.stats div{flex:1; border:1px solid var(--border); border-radius:12px; padding:12px; background:#f8fafc}
.stats div b{display:block; font-size:11px; color:var(--muted); margin-bottom:4px; text-transform:uppercase; letter-spacing:.08em}
.link{background:none; border:none; color:var(--danger); padding:10px; font-weight:800}
</style>
</head>
<body>
<div class="shell">
  <div class="card">
    <div class="top">
      <h1>NEXI-FI</h1>
      <span>Simple Portal</span>
    </div>
    <div class="h2">Connect</div>
    <p class="sub">Insert coin to start your session.</p>
    <div class="info">
      <div class="chip"><b>MAC</b><span id="info-mac">Loading...</span></div>
      <div class="chip"><b>IP</b><span id="info-ip">Loading...</span></div>
    </div>
    <div id="loading" class="sub">Loading...</div>
    <div id="login-section" style="display:none;">
      <button onclick="playAudio('insert'); startCoin()" class="success">INSERT COIN</button>
      <button onclick="openRates()" class="primary" style="margin-top:10px;">RATES</button>
      <div class="note">Press WPS button on router when prompted.</div>
    </div>
    <div id="resume-section" style="display:none;">
      <div class="h2" style="font-size:16px">Session Paused</div>
      <p class="sub">Time Remaining: <strong id="paused-time"></strong></p>
      <button onclick="resumeTime()" class="primary">RESUME TIME</button>
    </div>
    <div id="connected-section" style="display:none;">
      <div class="h2" style="font-size:16px">Connected</div>
      <p class="sub">MAC: <span id="client-mac"></span></p>
      <p class="sub">Time Remaining: <strong id="time-remaining">Loading...</strong></p>
      <p id="internet-status" class="sub">Checking internet...</p>
      <div style="margin-top:10px">
        <button onclick="openRates()" class="primary">RATES</button>
      </div>
      <div class="row">
        <button onclick="playAudio('insert'); startCoin()" class="success">ADD TIME</button>
        <button onclick="pauseTime()" class="warn">PAUSE</button>
      </div>
      <div style="margin-top:10px">
        <button onclick="logout()" class="danger">LOGOUT</button>
      </div>
    </div>
  </div>
</div>

<div id="coin-modal" class="modal">
  <div class="modal-content">
    <h2>Insert Coin</h2>
    <p>Press WPS button on router</p>
    <div class="stats">
      <div><b>Coins</b><span id="coin-count">0</span></div>
      <div><b>Minutes</b><span id="coin-time">0</span></div>
    </div>
    <button id="connect-btn" onclick="playAudio('connect'); connect()" class="primary" style="display:none;">START INTERNET</button>
    <button onclick="closeModal()" class="link">Cancel</button>
  </div>
</div>

<div id="rates-modal" class="modal">
  <div class="modal-content">
    <h2>Rates</h2>
    <p>Current rates</p>
    <div id="rates-body" class="sub">Loading...</div>
    <button onclick="closeRates()" class="link">Close</button>
  </div>
</div>

<audio id="audio-insert" src="/insert.mp3"></audio>
<audio id="audio-connect" src="/connected.mp3"></audio>

<script>
var apiUrl="/cgi-bin/pisowifi";var interval;var timerInterval;var timeLeft=0;
function openRates(){var m=document.getElementById("rates-modal");if(m)m.style.display="block";loadRates();}
function closeRates(){var m=document.getElementById("rates-modal");if(m)m.style.display="none";}
function loadRates(){fetch(apiUrl+"?action=rates").then(r=>r.json()).then(function(d){var el=document.getElementById("rates-body");if(!el)return;if(!d||!d.rates||!d.rates.length){el.innerHTML="<div>No rates set.</div>";return;}var html="<div style='display:grid; gap:8px; margin-top:10px;'>";d.rates.forEach(function(x){html+="<div style='display:flex; justify-content:space-between; padding:10px; border-radius:12px; border:1px solid #e2e8f0; background:#f8fafc;'><div style='font-weight:800;'>₱"+x.amount+"</div><div>"+x.minutes+" min</div></div>";});html+="</div>";el.innerHTML=html;}).catch(function(){var el=document.getElementById("rates-body");if(el)el.innerHTML="<div>Failed to load rates.</div>";});}
function playAudio(t){try{stopAudio();var a=document.getElementById("audio-"+t);if(a){a.currentTime=0;a.play().catch(()=>{});}}catch(e){}}
function stopAudio(){try{document.querySelectorAll("audio").forEach(function(s){s.pause();s.currentTime=0;});}catch(e){}}
function formatTime(s){if(s<=0)return"Expired";var d=Math.floor(s/86400),h=Math.floor((s%86400)/3600),m=Math.floor((s%3600)/60),sec=s%60,t="";if(d>0)t+=d+"d ";if(h>0)t+=h+"h ";if(m>0)t+=m+"m ";t+=sec+"s";return t.trim();}
function startTimer(){if(timerInterval)clearInterval(timerInterval);timerInterval=setInterval(function(){if(timeLeft>0){timeLeft--;var el=document.getElementById("time-remaining");if(el)el.innerText=formatTime(timeLeft);}else{clearInterval(timerInterval);checkStatus();}},1000);}
function checkInternet(){var img=new Image();var now=new Date().getTime();img.src="https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?t="+now;img.onload=function(){var el=document.getElementById("internet-status");if(el){el.innerText="Internet: ONLINE";el.style.color="#16a34a";}fetch(apiUrl+"?action=log_internet&status=ONLINE&mac="+encodeURIComponent(document.getElementById("client-mac")?document.getElementById("client-mac").innerText:"UNKNOWN"));};img.onerror=function(){var el=document.getElementById("internet-status");if(el){el.innerText="Internet: OFFLINE";el.style.color="#dc2626";}fetch(apiUrl+"?action=log_internet&status=OFFLINE&mac="+encodeURIComponent(document.getElementById("client-mac")?document.getElementById("client-mac").innerText:"UNKNOWN"));};}
function checkStatus(){fetch(apiUrl+"?action=status").then(r=>{if(!r.ok)throw new Error("HTTP "+r.status);return r.json();}).then(d=>{if(d.mac){var a=document.getElementById("info-mac");if(a)a.innerText=d.mac;}if(d.ip){var b=document.getElementById("info-ip");if(b)b.innerText=d.ip;}var loading=document.getElementById("loading");if(loading)loading.style.display="none";if(d.authenticated==="true"){document.getElementById("login-section").style.display="none";document.getElementById("resume-section").style.display="none";document.getElementById("connected-section").style.display="block";timeLeft=parseInt(d.time_remaining);document.getElementById("time-remaining").innerText=formatTime(timeLeft);if(d.mac)document.getElementById("client-mac").innerText=d.mac;startTimer();checkInternet();setTimeout(checkStatus,5000);}else if(d.authenticated==="paused"){document.getElementById("login-section").style.display="none";document.getElementById("connected-section").style.display="none";document.getElementById("resume-section").style.display="block";document.getElementById("paused-time").innerText=formatTime(d.time_remaining);if(timerInterval)clearInterval(timerInterval);setTimeout(checkStatus,10000);}else{document.getElementById("login-section").style.display="block";document.getElementById("resume-section").style.display="none";document.getElementById("connected-section").style.display="none";if(timerInterval)clearInterval(timerInterval);}}).catch(()=>{var loading=document.getElementById("loading");if(loading)loading.style.display="none";document.getElementById("login-section").style.display="block";});}
function pauseTime(){if(!confirm("Pause Internet? You can resume later."))return;fetch(apiUrl+"?action=pause").then(r=>r.json()).then(d=>{if(d.status==="paused"){alert("Internet Paused. Time saved: "+formatTime(d.remaining));checkStatus();}else{alert("Error: "+(d.error||"Failed to pause"));}}).catch(()=>{});}
function resumeTime(){fetch(apiUrl+"?action=resume").then(r=>r.json()).then(d=>{if(d.status==="resumed")checkStatus();else alert("Error: "+(d.error||"Failed to resume"));}).catch(()=>{});}
function startCoin(){// First check if coinslot is available
fetch(apiUrl+"?action=check_coinslot_lock").then(r=>r.json()).then(lockData=>{if(lockData.locked&&!lockData.locked_by_me){alert("Coinslot is currently in use by another device. Please try again later.");return;}// Try to acquire lock and start coin session
fetch(apiUrl+"?action=start_coin").then(r=>r.json()).then(data=>{if(data.status==="started"&&data.lock_acquired){document.getElementById("coin-modal").style.display="block";document.getElementById("coin-count").innerText="0";document.getElementById("coin-time").innerText="0";document.getElementById("connect-btn").style.display="none";if(interval)clearInterval(interval);interval=setInterval(()=>{fetch(apiUrl+"?action=check_coin").then(r=>r.json()).then(d=>{document.getElementById("coin-count").innerText=d.count;document.getElementById("coin-time").innerText=d.minutes;if(d.count>0)document.getElementById("connect-btn").style.display="block";}).catch(()=>{});},1000);}else if(data.error){alert(data.error+" (Device: "+data.locked_by_mac+")");}else{alert("Failed to start coin session. Please try again.");}}).catch(()=>{alert("Failed to start coin session. Please refresh the page.");});}).catch(()=>{alert("Failed to check coinslot lock. Please try again.");});}
function connect(){stopAudio();playAudio("connect");fetch(apiUrl+"?action=connect").then(r=>r.json()).then(d=>{closeModal();if(d.status==="connected"){checkStatus();if(d.redirect_url)setTimeout(()=>{window.location.href=d.redirect_url;},2000);}else{alert(d.error||"Connection failed");}}).catch(()=>{alert("Failed to connect. Please try again.");});}
function logout(){fetch(apiUrl+"?action=logout").then(r=>r.json()).then(()=>checkStatus()).catch(()=>checkStatus());}
function closeModal(){document.getElementById("coin-modal").style.display="none";if(interval)clearInterval(interval);stopAudio();// Release coinslot lock when closing modal
fetch(apiUrl+"?action=release_coinslot_lock").then(r=>r.json()).then(data=>{console.log("Coinslot lock released:",data);}).catch(err=>console.error("Failed to release lock:",err));}
setTimeout(function(){fetch(apiUrl+"?action=test_dns").then(r=>r.json()).then(()=>{}).catch(()=>{});},3000);
checkStatus();
</script>
</body>
</html>
HTML

cat << 'HTML' > /www/portal_themes/theme_sunset.html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>NEXI-FI PISOWIFI</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { --bg1:#fb7185; --bg2:#f59e0b; --bg3:#22c55e; --card:rgba(255,255,255,0.92); --text:#0f172a; --muted:#475569; --primary:#2563eb; --success:#16a34a; --danger:#dc2626; --warn:#f59e0b; }
*{box-sizing:border-box}
body{margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; padding:22px; font-family: system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;
background: radial-gradient(1100px 700px at 10% 0%, rgba(255,255,255,0.45), transparent 55%),
linear-gradient(135deg, var(--bg1), var(--bg2) 55%, var(--bg3));}
.shell{width:100%; max-width:520px}
.card{background:var(--card); border-radius:18px; padding:18px; box-shadow: 0 18px 50px rgba(0,0,0,0.25);}
.hero{display:flex; align-items:center; justify-content:space-between; margin-bottom:10px}
.hero h1{margin:0; font-size:16px; text-transform:uppercase; letter-spacing:.08em}
.hero span{font-size:12px; color:var(--muted)}
.banner{border-radius:14px; padding:12px; background: linear-gradient(135deg, rgba(37,99,235,0.10), rgba(34,197,94,0.10)); border:1px solid rgba(15,23,42,0.08); margin-bottom:12px}
.banner strong{display:block; margin-bottom:4px}
.banner div{font-size:12px; color:var(--muted); line-height:1.4}
.h2{margin:0; font-size:18px}
.sub{margin:6px 0 0 0; color:var(--muted); font-size:13px}
button{width:100%; padding:14px; border-radius:14px; border:0; color:white; font-weight:900; cursor:pointer; transition: transform .08s ease;}
button:active{transform:scale(0.99)}
.primary{background: linear-gradient(135deg, rgba(37,99,235,0.95), rgba(14,165,233,0.95));}
.success{background: linear-gradient(135deg, rgba(22,163,74,0.95), rgba(34,197,94,0.95));}
.danger{background: linear-gradient(135deg, rgba(220,38,38,0.95), rgba(244,63,94,0.95));}
.warn{background: linear-gradient(135deg, rgba(245,158,11,0.95), rgba(251,191,36,0.95));}
.row{display:flex; gap:10px; margin-top:10px}
.row button{width:100%}
.note{margin-top:10px; font-size:12px; color:var(--muted); text-align:center}
.modal{display:none; position:fixed; z-index:10; left:0; top:0; width:100%; height:100%; background: rgba(2,6,23,0.6); padding:18px;}
.modal-content{background:var(--card); margin:12vh auto 0; padding:18px; width:100%; max-width:420px; border-radius:16px;}
.modal-content h2{margin:0 0 8px 0}
.modal-content p{margin:0 0 12px 0; color:var(--muted)}
.stats{display:flex; gap:12px; margin:14px 0}
.stats div{flex:1; border-radius:14px; padding:12px; background: rgba(15,23,42,0.04); border:1px solid rgba(15,23,42,0.08);}
.stats div b{display:block; font-size:11px; color:var(--muted); margin-bottom:4px; text-transform:uppercase; letter-spacing:.08em}
.link{background:none; border:none; color:var(--danger); padding:10px; font-weight:900}
</style>
</head>
<body>
<div class="shell">
  <div class="card">
    <div class="hero">
      <h1>NEXI-FI</h1>
      <span>Sunset Theme</span>
    </div>
    <div class="banner">
      <strong>Device Info</strong>
      <div>MAC: <span id="info-mac">Loading...</span></div>
      <div>IP: <span id="info-ip">Loading...</span></div>
    </div>
    <div class="h2">Get Connected</div>
    <p class="sub">Insert coin to start. Pause and resume anytime.</p>
    <div id="loading" class="sub">Loading...</div>
    <div id="login-section" style="display:none;">
      <button onclick="playAudio('insert'); startCoin()" class="success">INSERT COIN</button>
      <button onclick="openRates()" class="primary" style="margin-top:10px;">RATES</button>
      <div class="note">Press WPS button on router when prompted.</div>
    </div>
    <div id="resume-section" style="display:none;">
      <div class="h2" style="font-size:16px">Session Paused</div>
      <p class="sub">Time Remaining: <strong id="paused-time"></strong></p>
      <button onclick="resumeTime()" class="primary">RESUME TIME</button>
    </div>
    <div id="connected-section" style="display:none;">
      <div class="h2" style="font-size:16px">Connected</div>
      <p class="sub">MAC: <span id="client-mac"></span></p>
      <p class="sub">Time Remaining: <strong id="time-remaining">Loading...</strong></p>
      <p id="internet-status" class="sub">Checking internet...</p>
      <div style="margin-top:10px">
        <button onclick="openRates()" class="primary">RATES</button>
      </div>
      <div class="row">
        <button onclick="playAudio('insert'); startCoin()" class="success">ADD TIME</button>
        <button onclick="pauseTime()" class="warn">PAUSE</button>
      </div>
      <div style="margin-top:10px">
        <button onclick="logout()" class="danger">LOGOUT</button>
      </div>
    </div>
  </div>
</div>

<div id="coin-modal" class="modal">
  <div class="modal-content">
    <h2>Insert Coin</h2>
    <p>Press WPS button on router</p>
    <div class="stats">
      <div><b>Coins</b><span id="coin-count">0</span></div>
      <div><b>Minutes</b><span id="coin-time">0</span></div>
    </div>
    <button id="connect-btn" onclick="playAudio('connect'); connect()" class="primary" style="display:none;">START INTERNET</button>
    <button onclick="closeModal()" class="link">Cancel</button>
  </div>
</div>

<div id="rates-modal" class="modal">
  <div class="modal-content">
    <h2>Rates</h2>
    <p>Current rates</p>
    <div id="rates-body" class="sub">Loading...</div>
    <button onclick="closeRates()" class="link">Close</button>
  </div>
</div>

<audio id="audio-insert" src="/insert.mp3"></audio>
<audio id="audio-connect" src="/connected.mp3"></audio>

<script>
var apiUrl="/cgi-bin/pisowifi";var interval;var timerInterval;var timeLeft=0;
function openRates(){var m=document.getElementById("rates-modal");if(m)m.style.display="block";loadRates();}
function closeRates(){var m=document.getElementById("rates-modal");if(m)m.style.display="none";}
function loadRates(){fetch(apiUrl+"?action=rates").then(r=>r.json()).then(function(d){var el=document.getElementById("rates-body");if(!el)return;if(!d||!d.rates||!d.rates.length){el.innerHTML="<div>No rates set.</div>";return;}var html="<div style='display:grid; gap:8px; margin-top:10px;'>";d.rates.forEach(function(x){html+="<div style='display:flex; justify-content:space-between; padding:10px; border-radius:14px; background: rgba(15,23,42,0.04); border:1px solid rgba(15,23,42,0.08);'><div style='font-weight:900;'>₱"+x.amount+"</div><div>"+x.minutes+" min</div></div>";});html+="</div>";el.innerHTML=html;}).catch(function(){var el=document.getElementById("rates-body");if(el)el.innerHTML="<div>Failed to load rates.</div>";});}
function playAudio(t){try{stopAudio();var a=document.getElementById("audio-"+t);if(a){a.currentTime=0;a.play().catch(()=>{});}}catch(e){}}
function stopAudio(){try{document.querySelectorAll("audio").forEach(function(s){s.pause();s.currentTime=0;});}catch(e){}}
function formatTime(s){if(s<=0)return"Expired";var d=Math.floor(s/86400),h=Math.floor((s%86400)/3600),m=Math.floor((s%3600)/60),sec=s%60,t="";if(d>0)t+=d+"d ";if(h>0)t+=h+"h ";if(m>0)t+=m+"m ";t+=sec+"s";return t.trim();}
function startTimer(){if(timerInterval)clearInterval(timerInterval);timerInterval=setInterval(function(){if(timeLeft>0){timeLeft--;var el=document.getElementById("time-remaining");if(el)el.innerText=formatTime(timeLeft);}else{clearInterval(timerInterval);checkStatus();}},1000);}
function checkInternet(){var img=new Image();var now=new Date().getTime();img.src="https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?t="+now;img.onload=function(){var el=document.getElementById("internet-status");if(el){el.innerText="Internet: ONLINE";el.style.color="#16a34a";}fetch(apiUrl+"?action=log_internet&status=ONLINE&mac="+encodeURIComponent(document.getElementById("client-mac")?document.getElementById("client-mac").innerText:"UNKNOWN"));};img.onerror=function(){var el=document.getElementById("internet-status");if(el){el.innerText="Internet: OFFLINE";el.style.color="#dc2626";}fetch(apiUrl+"?action=log_internet&status=OFFLINE&mac="+encodeURIComponent(document.getElementById("client-mac")?document.getElementById("client-mac").innerText:"UNKNOWN"));};}
function checkStatus(){fetch(apiUrl+"?action=status").then(r=>{if(!r.ok)throw new Error("HTTP "+r.status);return r.json();}).then(d=>{if(d.mac){var a=document.getElementById("info-mac");if(a)a.innerText=d.mac;}if(d.ip){var b=document.getElementById("info-ip");if(b)b.innerText=d.ip;}var loading=document.getElementById("loading");if(loading)loading.style.display="none";if(d.authenticated==="true"){document.getElementById("login-section").style.display="none";document.getElementById("resume-section").style.display="none";document.getElementById("connected-section").style.display="block";timeLeft=parseInt(d.time_remaining);document.getElementById("time-remaining").innerText=formatTime(timeLeft);if(d.mac)document.getElementById("client-mac").innerText=d.mac;startTimer();checkInternet();setTimeout(checkStatus,5000);}else if(d.authenticated==="paused"){document.getElementById("login-section").style.display="none";document.getElementById("connected-section").style.display="none";document.getElementById("resume-section").style.display="block";document.getElementById("paused-time").innerText=formatTime(d.time_remaining);if(timerInterval)clearInterval(timerInterval);setTimeout(checkStatus,10000);}else{document.getElementById("login-section").style.display="block";document.getElementById("resume-section").style.display="none";document.getElementById("connected-section").style.display="none";if(timerInterval)clearInterval(timerInterval);}}).catch(()=>{var loading=document.getElementById("loading");if(loading)loading.style.display="none";document.getElementById("login-section").style.display="block";});}
function pauseTime(){if(!confirm("Pause Internet? You can resume later."))return;fetch(apiUrl+"?action=pause").then(r=>r.json()).then(d=>{if(d.status==="paused"){alert("Internet Paused. Time saved: "+formatTime(d.remaining));checkStatus();}else{alert("Error: "+(d.error||"Failed to pause"));}}).catch(()=>{});}
function resumeTime(){fetch(apiUrl+"?action=resume").then(r=>r.json()).then(d=>{if(d.status==="resumed")checkStatus();else alert("Error: "+(d.error||"Failed to resume"));}).catch(()=>{});}
function startCoin(){fetch(apiUrl+"?action=start_coin").then(r=>r.json()).then(()=>{document.getElementById("coin-modal").style.display="block";document.getElementById("coin-count").innerText="0";document.getElementById("coin-time").innerText="0";document.getElementById("connect-btn").style.display="none";if(interval)clearInterval(interval);interval=setInterval(()=>{fetch(apiUrl+"?action=check_coin").then(r=>r.json()).then(d=>{document.getElementById("coin-count").innerText=d.count;document.getElementById("coin-time").innerText=d.minutes;if(d.count>0)document.getElementById("connect-btn").style.display="block";}).catch(()=>{});},1000);}).catch(()=>{alert("Failed to start coin session. Please refresh the page.");});}
function connect(){stopAudio();playAudio("connect");fetch(apiUrl+"?action=connect").then(r=>r.json()).then(d=>{closeModal();if(d.status==="connected"){checkStatus();if(d.redirect_url)setTimeout(()=>{window.location.href=d.redirect_url;},2000);}else{alert(d.error||"Connection failed");}}).catch(()=>{alert("Failed to connect. Please try again.");});}
function logout(){fetch(apiUrl+"?action=logout").then(r=>r.json()).then(()=>checkStatus()).catch(()=>checkStatus());}
function closeModal(){document.getElementById("coin-modal").style.display="none";if(interval)clearInterval(interval);stopAudio();}
setTimeout(function(){fetch(apiUrl+"?action=test_dns").then(r=>r.json()).then(()=>{}).catch(()=>{});},3000);
checkStatus();
</script>
</body>
</html>
HTML

if [ ! -f /www/portal.html ]; then
    cat /www/portal_themes/theme_glass.html > /www/portal.html
fi

# 4. Redirect Root to CGI
echo "Setting up redirect..."

# Configure uhttpd to handle 404 errors by serving the CGI script
# This is crucial for captive portal detection (e.g. /generate_204)
uci set uhttpd.main.error_page='/cgi-bin/pisowifi'
uci commit uhttpd

cat << 'EOF' > /www/index.html
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="0; URL=/cgi-bin/pisowifi" />
</head>
<body>
<a href="/cgi-bin/pisowifi">Click here if not redirected...</a>
</body>
</html>
EOF

# Restart uhttpd after CGI script creation
echo "Restarting web server..."
/etc/init.d/uhttpd restart 2>/dev/null || /etc/init.d/uhttpd start 2>/dev/null

echo "=== CGI INSTALLATION COMPLETE ==="
echo "Access at http://10.0.0.1/cgi-bin/pisowifi"

# 5. SETUP NETWORK & WIFI (SSID: NEXI-FI PISOWIFI)
echo "Configuring Network and WiFi..."

# Disable LuCI if present to prevent conflicts
if [ -f /www/cgi-bin/luci ]; then
    echo "Disabling LuCI to prevent conflicts..."
    mv /www/cgi-bin/luci /www/cgi-bin/luci.bak
fi

# Set LAN IP to 10.0.0.1
uci set network.lan.ipaddr='10.0.0.1'
uci commit network

# Enable all WiFi radios (avoid hardcoding radio0)
RADIOS=$(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1)
for r in $RADIOS; do
    uci set wireless."$r".disabled='0' 2>/dev/null || true
done

# Configure all AP interfaces (avoid hardcoding @wifi-iface[0])
IFACES=$(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1)
if [ -z "$IFACES" ]; then
    FIRST_RADIO=$(echo "$RADIOS" | awk '{print $1}')
    [ -z "$FIRST_RADIO" ] && FIRST_RADIO="radio0"
    NEW_IF=$(uci add wireless wifi-iface 2>/dev/null || true)
    IFACES="$NEW_IF"
    uci set wireless."$NEW_IF".device="$FIRST_RADIO" 2>/dev/null || true
fi

for i in $IFACES; do
    MODE=$(uci get wireless."$i".mode 2>/dev/null)
    [ -z "$MODE" ] && MODE="ap"
    if [ "$MODE" = "ap" ]; then
        uci set wireless."$i".network='lan' 2>/dev/null || true
        uci set wireless."$i".mode='ap' 2>/dev/null || true
        uci set wireless."$i".ssid='NEXI-FI PISOWIFI' 2>/dev/null || true
        uci set wireless."$i".encryption='none' 2>/dev/null || true
        uci set wireless."$i".disabled='0' 2>/dev/null || true
    fi
done
uci commit wireless 2>/dev/null || true

echo "Restarting Network..."
# Use reload_config if available (Modern OpenWrt), otherwise fallback
if [ -x /sbin/reload_config ]; then
    /sbin/reload_config
else
    /etc/init.d/network restart 2>/dev/null || true
fi

# Reload WiFi (Ignore errors if radio busy)
/sbin/wifi reload 2>/dev/null || true

echo "Network Configured: IP 10.0.0.1, SSID 'NEXI-FI PISOWIFI'"

echo "Installing device sync script..."
cat > /usr/bin/wifi_devices_sync_auto.sh << 'EOS'
#!/bin/sh
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
DB_FILE="/etc/pisowifi/pisowifi.db"

VENDOR_ID="$($UCI_BIN -q get pisowifi.license.centralized_vendor_id 2>/dev/null)"
MACHINE_ID="$($UCI_BIN -q get pisowifi.license.vendor_uuid 2>/dev/null)"
[ -z "$MACHINE_ID" ] && [ -f /etc/pisowifi/machine_id ] && MACHINE_ID="$(head -n1 /etc/pisowifi/machine_id 2>/dev/null | tr -d '\r')"
[ -z "$MACHINE_ID" ] && [ -f /etc/pisowifi/license.json ] && MACHINE_ID="$(sed -n 's/.*\"vendor_uuid\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' /etc/pisowifi/license.json | head -n1)"
[ -z "$MACHINE_ID" ] && command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB_FILE" ] && MACHINE_ID="$(sqlite3 -separator '|' "$DB_FILE" "SELECT vendor_uuid FROM license LIMIT 1;" 2>/dev/null | head -n1)"

HARDWARE_ID="$($UCI_BIN -q get pisowifi.license.hardware_id 2>/dev/null)"
[ -z "$HARDWARE_ID" ] && [ -f /etc/pisowifi/hardware_id ] && HARDWARE_ID="$(head -n1 /etc/pisowifi/hardware_id 2>/dev/null | tr -d '\r')"
[ -z "$HARDWARE_ID" ] && [ -f /etc/machine-id ] && HARDWARE_ID="$(head -n1 /etc/machine-id 2>/dev/null | tr -d '\r')"

CENTRAL_KEY="$($UCI_BIN -q get pisowifi.license.centralized_key 2>/dev/null)"
HOSTNAME_VAL="$($UCI_BIN -q get system.@system[0].hostname 2>/dev/null)"
[ -z "$HOSTNAME_VAL" ] && HOSTNAME_VAL="$(hostname 2>/dev/null)"

SUPA_URL="$($UCI_BIN -q get pisowifi.license.supabase_url 2>/dev/null)"
SUPA_KEY="$($UCI_BIN -q get pisowifi.license.supabase_service_key 2>/dev/null)"
[ -z "$SUPA_KEY" ] && SUPA_KEY="$($UCI_BIN -q get pisowifi.license.supabase_key 2>/dev/null)"

if [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ]; then
    if [ -f /etc/pisowifi/supabase.env ]; then
        SUPA_URL="$(grep -m1 '^SUPABASE_URL=' /etc/pisowifi/supabase.env 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')"
        SUPA_KEY="$(grep -m1 '^SUPABASE_SERVICE_ROLE_KEY=' /etc/pisowifi/supabase.env 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')"
        [ -z "$SUPA_KEY" ] && SUPA_KEY="$(grep -m1 '^SUPABASE_ANON_KEY=' /etc/pisowifi/supabase.env 2>/dev/null | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["`'"'"']//; s/["`'"'"']$//')"
    fi
fi

if [ -z "$VENDOR_ID" ] || [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ]; then
    echo "missing_required_config vendor_id=${VENDOR_ID:-empty} supabase_url_or_key=empty"
    exit 2
fi

if [ -z "$MACHINE_ID" ]; then
    if [ -z "$HARDWARE_ID" ]; then
        echo "missing_required_config machine_id=empty hardware_id=empty"
        exit 2
    fi

    T="/tmp/wifi_devices_vendor_lookup.$$"
    CODE="$(curl -sS -o "$T" -w "%{http_code}" --connect-timeout 8 --max-time 15 \
        -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" -H "Accept: application/json" \
        "$SUPA_URL/rest/v1/vendors?select=id&hardware_id=eq.$HARDWARE_ID&limit=1" 2>/dev/null)"
    if [ "$CODE" = "200" ]; then
        MACHINE_ID="$(sed -n 's/.*\"id\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' "$T" | head -n1)"
    else
        echo "vendors_lookup_failed_http_$CODE: $(cat "$T" 2>/dev/null)" 1>&2
    fi
    rm -f "$T" 2>/dev/null

    if [ -z "$MACHINE_ID" ]; then
        T="/tmp/wifi_devices_vendor_create.$$"
        NAME_ESC="$(printf '%s' "$HOSTNAME_VAL" | sed 's/\"/\\\"/g')"
        KEY_ESC="$(printf '%s' "$CENTRAL_KEY" | sed 's/\"/\\\"/g')"
        BODY="{\"hardware_id\":\"$HARDWARE_ID\",\"machine_name\":\"$NAME_ESC\",\"vendor_id\":\"$VENDOR_ID\",\"license_key\":\"$KEY_ESC\",\"is_licensed\":true,\"activated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
        CODE="$(curl -sS -o "$T" -w "%{http_code}" --connect-timeout 8 --max-time 15 \
            -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" -H "Accept: application/json" \
            -H "Content-Type: application/json" -H "Prefer: return=representation" \
            -X POST -d "$BODY" \
            "$SUPA_URL/rest/v1/vendors" 2>/dev/null)"
        if [ "$CODE" = "201" ] || [ "$CODE" = "200" ]; then
            MACHINE_ID="$(sed -n 's/.*\"id\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' "$T" | head -n1)"
        else
            echo "vendors_create_failed_http_$CODE: $(cat "$T" 2>/dev/null)" 1>&2
        fi
        rm -f "$T" 2>/dev/null
    fi
fi

if [ -z "$MACHINE_ID" ]; then
    echo "missing_required_config machine_id=empty vendor_id=$VENDOR_ID"
    exit 2
fi

mkdir -p /etc/pisowifi 2>/dev/null || true
echo "$MACHINE_ID" > /etc/pisowifi/machine_id 2>/dev/null || true
$UCI_BIN set pisowifi.license.vendor_uuid="$MACHINE_ID" 2>/dev/null || true
$UCI_BIN commit pisowifi 2>/dev/null || true

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3_missing"
    exit 3
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "curl_missing"
    exit 4
fi

NOW_EPOCH="$(date +%s)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TMP_ROWS="/tmp/wifi_devices_sync_rows.$$"
SQL_ERR="/tmp/wifi_devices_sync_sqlerr.$$"
SRC="none"

try_query() {
    Q="$1"
    sqlite3 -separator '|' "$DB_FILE" "$Q" > "$TMP_ROWS" 2>"$SQL_ERR"
    RC="$?"
    if [ "$RC" != "0" ]; then
        : > "$TMP_ROWS" 2>/dev/null || true
    fi
    return "$RC"
}

QUERY_DEV_1="SELECT mac, ip, COALESCE(hostname,''), 0, 0 FROM devices;"
QUERY_DEV_2="SELECT mac, ip, '', 0, 0 FROM devices;"
QUERY_DEV_3="SELECT mac, ip_address, '', 0, 0 FROM devices;"

if try_query "$QUERY_DEV_1"; then
    SRC="devices"
elif try_query "$QUERY_DEV_2"; then
    SRC="devices"
elif try_query "$QUERY_DEV_3"; then
    SRC="devices"
else
    : > "$TMP_ROWS" 2>/dev/null || true
fi

if [ "$SRC" = "devices" ] && ! grep -q '.' "$TMP_ROWS" 2>/dev/null; then
    SRC="none"
fi

if [ "$SRC" = "none" ]; then
    QUERY_USERS_1="SELECT mac, ip, '', COALESCE(session_start, 0), COALESCE(session_end, 0) FROM users WHERE session_end > $NOW_EPOCH AND COALESCE(paused_time,0)=0;"
    QUERY_USERS_2="SELECT mac, ip, '', 0, COALESCE(session_end, 0) FROM users WHERE session_end > $NOW_EPOCH;"
    QUERY_USERS_3="SELECT mac, ip_address, '', 0, COALESCE(session_end, 0) FROM users WHERE session_end > $NOW_EPOCH;"
    QUERY_USERS_4="SELECT mac, ip, '', 0, session_end FROM users WHERE session_end > $NOW_EPOCH;"
    QUERY_USERS_5="SELECT mac, ip_address, '', 0, session_end FROM users WHERE session_end > $NOW_EPOCH;"

    if try_query "$QUERY_USERS_1"; then
        SRC="users"
    elif try_query "$QUERY_USERS_2"; then
        SRC="users"
    elif try_query "$QUERY_USERS_3"; then
        SRC="users"
    elif try_query "$QUERY_USERS_4"; then
        SRC="users"
    elif try_query "$QUERY_USERS_5"; then
        SRC="users"
    else
        echo "sqlite_query_failed: $(cat "$SQL_ERR" 2>/dev/null | head -n1)" 1>&2
        rm -f "$TMP_ROWS" "$SQL_ERR" 2>/dev/null
        exit 5
    fi
fi
rm -f "$SQL_ERR" 2>/dev/null

if [ "$SRC" = "none" ] || ! grep -q '.' "$TMP_ROWS" 2>/dev/null; then
    LEASES_FILE=""
    for f in /tmp/dhcp.leases /tmp/dnsmasq.leases /var/dhcp.leases; do
        if [ -f "$f" ] && grep -q '.' "$f" 2>/dev/null; then
            LEASES_FILE="$f"
            break
        fi
    done
    if [ -n "$LEASES_FILE" ]; then
        SRC="leases"
        awk 'NF>=3 { mac=$2; ip=$3; name=$4; if(name=="*"||name=="") name=""; if(mac ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) print mac "|" ip "|" name "|0|0" }' "$LEASES_FILE" > "$TMP_ROWS" 2>/dev/null || true
    fi
fi

if [ "$SRC" = "none" ] || ! grep -q '.' "$TMP_ROWS" 2>/dev/null; then
    echo "source=none total=0 updated=0 inserted=0 supabase_count=unknown http=0"
    rm -f "$TMP_ROWS" 2>/dev/null
    exit 0
fi

SYNC_TOTAL=0
SYNC_UPDATED=0
SYNC_INSERTED=0

while IFS='|' read -r MAC IP DEV SSTART SEND; do
    [ -z "$MAC" ] && continue
    SYNC_TOTAL=$((SYNC_TOTAL + 1))

    MAC_UP="$(printf '%s' "$MAC" | tr 'a-z' 'A-Z')"
    MAC_ESC="$(printf '%s' "$MAC_UP" | sed 's/"/\\"/g')"
    IP_ESC="$(printf '%s' "$IP" | sed 's/"/\\"/g')"
    DEV_ESC="$(printf '%s' "$DEV" | sed 's/"/\\"/g')"

    REM=0
    if [ -n "$SEND" ] && [ "$SEND" -gt "$NOW_EPOCH" ] 2>/dev/null; then
        REM=$((SEND - NOW_EPOCH))
    fi

    TOKEN="$(sqlite3 -separator '|' "$DB_FILE" "SELECT session_token FROM users WHERE mac='$MAC_UP' LIMIT 1;" 2>/dev/null | head -n1)"
    TOKEN_ESC="$(printf '%s' "$TOKEN" | sed 's/\"/\\\"/g')"
    BODY="{\"vendor_id\":\"$VENDOR_ID\",\"machine_id\":\"$MACHINE_ID\",\"mac_address\":\"$MAC_ESC\",\"ip_address\":\"$IP_ESC\",\"device_name\":\"$DEV_ESC\",\"remaining_seconds\":$REM"
    if [ -n "$TOKEN_ESC" ]; then
        BODY="$BODY,\"session_token\":\"$TOKEN_ESC\""
    fi
    BODY="$BODY,\"last_heartbeat\":\"$NOW_ISO\",\"last_sync_attempt\":\"$NOW_ISO\",\"sync_status\":\"success\",\"is_connected\":true}"

    T="/tmp/wifi_devices_sync_resp.$$"
    CODE="$(curl -sS -o "$T" -w "%{http_code}" --connect-timeout 8 --max-time 15 \
        -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" -H "Accept: application/json" \
        "$SUPA_URL/rest/v1/wifi_devices?select=id&machine_id=eq.$MACHINE_ID&mac_address=eq.$MAC_ESC&limit=1" 2>/dev/null)"
    if [ "$CODE" != "200" ]; then
        echo "wifi_devices_select_failed_http_$CODE: $(cat "$T" 2>/dev/null)" 1>&2
        rm -f "$T" "$TMP_ROWS"
        exit 20
    fi

    cat "$T" | grep -q "\"id\"" 2>/dev/null
    if [ "$?" = "0" ]; then
        CODE2="$(curl -sS -o "$T" -w "%{http_code}" --connect-timeout 8 --max-time 15 \
            -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" \
            -H "Content-Type: application/json" -H "Prefer: return=minimal" \
            -X PATCH -d "$BODY" \
            "$SUPA_URL/rest/v1/wifi_devices?machine_id=eq.$MACHINE_ID&mac_address=eq.$MAC_ESC" 2>/dev/null)"
        if [ "$CODE2" != "204" ] && [ "$CODE2" != "200" ]; then
            echo "wifi_devices_patch_failed_http_$CODE2: $(cat "$T" 2>/dev/null)" 1>&2
            rm -f "$T" "$TMP_ROWS"
            exit 21
        fi
        SYNC_UPDATED=$((SYNC_UPDATED + 1))
    else
        CODE3="$(curl -sS -o "$T" -w "%{http_code}" --connect-timeout 8 --max-time 15 \
            -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" \
            -H "Content-Type: application/json" -H "Prefer: return=minimal" \
            -X POST -d "$BODY" \
            "$SUPA_URL/rest/v1/wifi_devices" 2>/dev/null)"
        if [ "$CODE3" != "201" ] && [ "$CODE3" != "200" ]; then
            echo "wifi_devices_post_failed_http_$CODE3: $(cat "$T" 2>/dev/null)" 1>&2
            rm -f "$T" "$TMP_ROWS"
            exit 22
        fi
        SYNC_INSERTED=$((SYNC_INSERTED + 1))
    fi

    rm -f "$T" 2>/dev/null
done < "$TMP_ROWS"
rm -f "$TMP_ROWS" 2>/dev/null

H="/tmp/wifi_devices_sync_hdr.$$"
T="/tmp/wifi_devices_sync_chk.$$"
CODEC="$(curl -sS -D "$H" -o "$T" -w "%{http_code}" --connect-timeout 8 --max-time 15 \
    -H "apikey: $SUPA_KEY" -H "Authorization: Bearer $SUPA_KEY" -H "Accept: application/json" -H "Prefer: count=exact" \
    "$SUPA_URL/rest/v1/wifi_devices?select=id&machine_id=eq.$MACHINE_ID&limit=1" 2>/dev/null)"
COUNT_LINE="$(cat "$H" 2>/dev/null | tr -d '\r' | grep -i '^Content-Range:' | head -n1)"
TOTAL_COUNT="$(echo "$COUNT_LINE" | sed -n 's/.*\/\([0-9][0-9]*\)$/\1/p')"
rm -f "$H" "$T" 2>/dev/null

echo "source=$SRC total=$SYNC_TOTAL updated=$SYNC_UPDATED inserted=$SYNC_INSERTED supabase_count=${TOTAL_COUNT:-unknown} http=$CODEC"
exit 0
EOS
chmod +x /usr/bin/wifi_devices_sync_auto.sh
echo "✅ Device sync script installed"
