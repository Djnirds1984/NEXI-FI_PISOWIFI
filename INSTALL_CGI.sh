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
uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci commit dhcp
/etc/init.d/dnsmasq reload

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
    uci set firewall.@zone[0].forward='ACCEPT'
    # Disable Flow Offloading (Can bypass captive portal rules)
    uci set firewall.@defaults[0].flow_offloading='0'
    uci commit firewall
    /etc/init.d/firewall reload 2>/dev/null || true

    # --- BLOCKING LOGIC (Bottom of Chain) ---
    
    # 1. Allow DNS/DHCP/Portal Access to Router
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
    # We allow forwarding for everyone, relying on OUR filter chain to drop unauths.
    nft insert rule inet fw4 forward ip saddr 10.0.0.0/8 accept 2>/dev/null || true
    # Also try 'firewall' table (older OpenWrt)
    nft insert rule inet firewall forward ip saddr 10.0.0.0/8 accept 2>/dev/null || true
    
    logger -t pisowifi "Firewall initialization complete."
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
        nft insert rule inet $TABLE $CHAIN_FILTER ip saddr $IP_ARG accept comment \"MAC:$MAC\"
        nft insert rule inet $TABLE $CHAIN_FILTER ip daddr $IP_ARG accept comment \"MAC:$MAC\"
        
        # Masquerade (Specific - ensure NAT works)
        nft insert rule inet $TABLE postrouting ip saddr $IP_ARG masquerade comment \"MAC:$MAC\"
        
        # FW4/Firewall Forwarding (External Tables) - CRITICAL
        # We must allow BOTH directions for forwarding to work properly
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
    nft insert rule inet $TABLE $CHAIN_FILTER ether saddr $MAC accept comment \"MAC:$MAC\"
    nft insert rule inet $TABLE $CHAIN_FILTER ether daddr $MAC accept comment \"MAC:$MAC\"
    
    # FW4 Fallback (MAC)
    nft insert rule inet fw4 forward ether saddr $MAC accept comment \"MAC:$MAC\" 2>/dev/null || true
    nft insert rule inet fw4 forward ether daddr $MAC accept comment \"MAC:$MAC\" 2>/dev/null || true
    
    logger -t pisowifi "Allow process complete for $MAC / $IP_ARG"
}

deny() {
    [ -z "$MAC" ] && return
    
    logger -t pisowifi "Denying MAC: $MAC"
    
    # Remove rules specifically for this MAC (using comment tag)
    # This cleans up both MAC and IP rules associated with this user
    
    # Helper to delete by handle
    delete_by_comment() {
        CHAIN=$1
        # List handles with this comment
        HANDLES=$(nft -a list chain inet $TABLE $CHAIN 2>/dev/null | grep "MAC:$MAC" | awk '{print $NF}')
        for h in $HANDLES; do nft delete rule inet $TABLE $CHAIN handle $h; done
    }
    
    delete_by_comment "$CHAIN_FILTER"
    delete_by_comment "$CHAIN_NAT"
    delete_by_comment "postrouting"
    
    # Also clean up fw4 fallback
    HANDLES=$(nft -a list chain inet fw4 forward 2>/dev/null | grep "MAC:$MAC" | awk '{print $NF}')
    for h in $HANDLES; do nft delete rule inet fw4 forward handle $h; done
    
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
EOF
    chmod +x /usr/bin/pisowifi_nftables.sh

# 1.5 Create Init Script to Restore Firewall on Boot
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
                    [ -n "$m" ] && $FIREWALL_SCRIPT deny "$m" >/dev/null 2>&1
                done

                sqlite3 "$DB_FILE" "SELECT mac FROM users WHERE session_end > 0 AND session_end <= $NOW" 2>/dev/null | while read m; do
                    [ -n "$m" ] && $FIREWALL_SCRIPT deny "$m" >/dev/null 2>&1
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
uci set pisowifi.settings=settings
uci set pisowifi.settings.minutes_per_peso='12'
uci set pisowifi.settings.admin_password='admin'
uci commit pisowifi

# Install sqlite3 if not available (OpenWrt)
opkg list-installed | grep -q sqlite3-cli || opkg install sqlite3-cli

# Create database schema
cat << 'EOF' | sqlite3 $DB_FILE
CREATE TABLE IF NOT EXISTS users (
    mac TEXT PRIMARY KEY,
    ip TEXT,
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

CREATE INDEX IF NOT EXISTS idx_users_mac ON users(mac);
CREATE INDEX IF NOT EXISTS idx_sessions_mac ON sessions(mac);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
EOF

# Update existing table (Outside heredoc)
sqlite3 $DB_FILE "ALTER TABLE rates ADD COLUMN expiration INTEGER DEFAULT 0;" 2>/dev/null || true
sqlite3 $DB_FILE "ALTER TABLE rates ADD COLUMN is_pausable INTEGER DEFAULT 1;" 2>/dev/null || true

# Insert default 1 Peso rate if not exists (Outside heredoc)
sqlite3 $DB_FILE "INSERT INTO rates (amount, minutes) SELECT 1, 12 WHERE NOT EXISTS (SELECT 1 FROM rates WHERE amount=1);" 2>/dev/null

# Attempt to add paused_time column to existing installations (ignore error if exists)
# This is done OUTSIDE the heredoc block because it is a shell command
sqlite3 $DB_FILE "ALTER TABLE users ADD COLUMN paused_time INTEGER DEFAULT 0;" 2>/dev/null || true

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
echo "Content-type: text/html"
echo ""

# Helper Variables
DB_FILE="/etc/pisowifi/pisowifi.db"
COIN_FILE="/tmp/pisowifi_coins"
SESSION_FILE="/tmp/pisowifi.sessions"
MINUTES_PER_PESO=$(uci get pisowifi.settings.minutes_per_peso 2>/dev/null || echo 12)
FIREWALL_SCRIPT="/usr/bin/pisowifi_nftables.sh"

# Log Captive Portal Triggers
# Log ANY request that is not an API call as a potential captive portal trigger
if ! echo "$QUERY_STRING" | grep -q "action="; then
    # Get client MAC
    CLIENT_MAC=$(grep "$REMOTE_ADDR " /proc/net/arp | awk '{print $4}' | tr 'a-z' 'A-Z' | head -1)
    [ -z "$CLIENT_MAC" ] && CLIENT_MAC="UNKNOWN"
    logger -t pisowifi "CAPTIVE PORTAL TRIGGERED: Device $CLIENT_MAC at $REMOTE_ADDR is accessing '$REQUEST_URI' -> Serving Portal Page"
fi

# Ensure database exists
if [ ! -f "$DB_FILE" ]; then
    echo "Warning: Database not found at $DB_FILE, creating default database" >&2
    # Create minimal database schema
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS users (mac TEXT PRIMARY KEY, ip TEXT, session_end INTEGER, coins_inserted INTEGER DEFAULT 0);"
    sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS coins (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, coins INTEGER, timestamp INTEGER DEFAULT (strftime('%s', 'now')));"
fi
chmod 666 $DB_FILE

# Database Helper Functions
query_db() {
    sqlite3 $DB_FILE "$1" 2>/dev/null || echo ""
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
    
    query_db "INSERT OR REPLACE INTO users (mac, ip, session_end, coins_inserted) VALUES ('$mac', '$ip', $session_end, $coins)"
}

insert_coin_record() {
    local mac="$1"
    local coins="$2"
    query_db "INSERT INTO coins (mac, coins) VALUES ('$mac', $coins)"
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
    
    # Debug logging
    logger -t pisowifi "API request: $QUERY_STRING from MAC: $MAC IP: $REMOTE_ADDR"
    
    # Simple JSON Response Wrapper
    json_response() {
        echo "$1"
        exit 0
    }
    
    case "$QUERY_STRING" in
        "action=status")
            # Check firewall status
            # Use nft to check if table exists, if not init
            nft list table inet pisowifi >/dev/null 2>&1 || $FIREWALL_SCRIPT init
            
            AUTH="false"
            TIME_REMAINING=0
            PAUSED_TIME=0
            
            logger -t pisowifi "Status check - MAC: $MAC, IP: $REMOTE_ADDR"
            
            if [ -n "$MAC" ]; then
                # Check database for active session
                # Fetch both expiry and paused_time
                RESULT=$(sqlite3 $DB_FILE "SELECT session_end, paused_time FROM users WHERE mac='$MAC' LIMIT 1")
                EXPIRY=$(echo "$RESULT" | cut -d'|' -f1)
                PAUSED_TIME=$(echo "$RESULT" | cut -d'|' -f2)
                
                [ -z "$EXPIRY" ] && EXPIRY=0
                [ -z "$PAUSED_TIME" ] && PAUSED_TIME=0
                
                NOW=$(date +%s)
                
                # Check if paused time exists (higher priority than expired session)
                if [ "$PAUSED_TIME" -gt 0 ]; then
                    AUTH="paused"
                    TIME_REMAINING=$PAUSED_TIME
                    logger -t pisowifi "User $MAC is PAUSED. Remaining: $PAUSED_TIME"
                    $FIREWALL_SCRIPT deny "$MAC" >/dev/null 2>&1
                elif [ "$EXPIRY" -gt "$NOW" ]; then
                    AUTH="true"
                    TIME_REMAINING=$((EXPIRY - NOW))
                    logger -t pisowifi "User $MAC authenticated, time remaining: $TIME_REMAINING"
                    # Ensure rule exists in NFT
                    $FIREWALL_SCRIPT allow "$MAC" "$REMOTE_ADDR"
                else
                    logger -t pisowifi "Session expired for $MAC"
                    $FIREWALL_SCRIPT deny "$MAC" >/dev/null 2>&1
                fi
            else
                logger -t pisowifi "No MAC address found for IP: $REMOTE_ADDR"
            fi
            json_response "{\"authenticated\": \"$AUTH\", \"time_remaining\": $TIME_REMAINING, \"mac\": \"$MAC\", \"ip\": \"$REMOTE_ADDR\"}"
            ;;
            
        "action=start_coin")
            # Clear coins from database for this user
            query_db "DELETE FROM coins WHERE mac='$MAC'"
            
            # REMOVED AUTO-INIT.
            # We assume firewall is ready. This prevents disconnecting other users.
            
            json_response "{\"status\": \"started\"}"
            ;;
            
        "action=check_coin")
            COUNT=$(get_coin_count "$MAC")
            [ -z "$COUNT" ] && COUNT=0
            logger -t pisowifi "Coin check for $MAC: $COUNT coins"
            MINUTES=$((COUNT * MINUTES_PER_PESO))
            json_response "{\"count\": $COUNT, \"minutes\": $MINUTES}"
            ;;
            
        "action=connect")
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
                update_user_session "$MAC" "$REMOTE_ADDR" $NEW_EXPIRY $COUNT
                
                # Allow Access
                $FIREWALL_SCRIPT allow "$MAC" "$REMOTE_ADDR"
                logger -t pisowifi "User $MAC connected successfully. Time added: $ADDED_MINUTES mins. New Expiry: $NEW_EXPIRY"
                
                json_response "{\"status\": \"connected\", \"expiry\": $NEW_EXPIRY, \"redirect_url\": \"https://www.google.com\"}"
            else
                json_response "{\"error\": \"No coins\"}"
            fi
            ;;
            
        "action=pause")
            # Get current expiry
            EXPIRY=$(get_user_session "$MAC")
            NOW=$(date +%s)
            
            if [ -n "$EXPIRY" ] && [ "$EXPIRY" -gt "$NOW" ]; then
                REMAINING=$((EXPIRY - NOW))
                # Save remaining time, clear session end
                query_db "UPDATE users SET paused_time=$REMAINING, session_end=0 WHERE mac='$MAC'"
                # Cut internet
                $FIREWALL_SCRIPT deny "$MAC"
                json_response "{\"status\": \"paused\", \"remaining\": $REMAINING}"
            else
                json_response "{\"error\": \"No active session to pause\"}"
            fi
            ;;

        "action=resume")
            # Get paused time
            PAUSED=$(query_db "SELECT paused_time FROM users WHERE mac='$MAC'")
            [ -z "$PAUSED" ] && PAUSED=0
            
            if [ "$PAUSED" -gt 0 ]; then
                NOW=$(date +%s)
                NEW_END=$((NOW + PAUSED))
                # Restore session, clear paused time
                query_db "UPDATE users SET session_end=$NEW_END, paused_time=0 WHERE mac='$MAC'"
                # Restore internet
                $FIREWALL_SCRIPT allow "$MAC" "$REMOTE_ADDR"
                json_response "{\"status\": \"resumed\", \"expiry\": $NEW_END}"
            else
                json_response "{\"error\": \"No paused session found\"}"
            fi
            ;;

        "action=logout")
            $FIREWALL_SCRIPT deny "$MAC"
            # Remove user session from database
            query_db "UPDATE users SET session_end=0 WHERE mac='$MAC'"
            json_response "{\"status\": \"success\"}"
            ;;
            
        "action=insert_coin")
            # Manual coin insertion for testing
            sqlite3 $DB_FILE "INSERT INTO coins (mac, coins) VALUES ('00:00:00:00:00:00', 1)"
            COUNT=$(sqlite3 $DB_FILE "SELECT SUM(coins) FROM coins WHERE mac='00:00:00:00:00:00'")
            logger -t pisowifi "Manual coin inserted. Total: $COUNT"
            json_response "{\"status\": \"coin_inserted\", \"total\": $COUNT}"
            ;;
            
        "action=log_internet")
            # Log client internet status
            STATUS=$(echo "$QUERY_STRING" | grep -o "status=[^&]*" | cut -d= -f2)
            CLIENT_MAC=$(echo "$QUERY_STRING" | grep -o "mac=[^&]*" | cut -d= -f2 | sed 's/%3A/:/g')
            
            # Simple rate limiting: Only log if status changed or every few minutes?
            # For now, just log it. Use logger so it shows in logread.
            if [ "$STATUS" = "ONLINE" ]; then
                logger -t pisowifi "INTERNET CHECK: Client $CLIENT_MAC is ONLINE ✅"
            else
                logger -t pisowifi "INTERNET CHECK: Client $CLIENT_MAC is OFFLINE ❌"
            fi
            json_response "{\"status\": \"logged\"}"
            ;;
            
        "action=test_dns")
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
    </div>
    
    <div id="resume-section" style="display:none;">
        <h2>Session Paused</h2>
        <p>Time Remaining: <strong id="paused-time"></strong></p>
        <button onclick="resumeTime()" class="btn-blue">RESUME TIME</button>
    </div>
    
    <div id="connected-section" style="display:none;">
        <h2>Connected!</h2>
        <p>MAC: <span id="client-mac"></span></p>
        <p>Time Remaining: <strong id="time-remaining"></strong></p>
        <p id="internet-status" style="font-size: 0.8em; color: gray;">Checking internet...</p>
        
        <div style="display:flex; gap:10px; margin-bottom:10px;">
             <!-- Add Time Button (Green) -->
             <button onclick="playAudio('insert'); startCoin()" class="btn-green">ADD TIME</button>
             <!-- Pause Button (Yellow) -->
             <button onclick="pauseTime()" class="btn-blue" style="background:#f59e0b;">PAUSE</button>
        </div>
        
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

<!-- Audio Elements -->
<audio id="audio-insert" src="/insert.mp3"></audio>
<audio id="audio-connect" src="/connected.mp3"></audio>

<script>
var apiUrl = "/cgi-bin/pisowifi";
var interval;

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
        fetch(apiUrl + "?action=log_internet&status=ONLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN"));
    };
    
    img.onerror = function() {
        var el = document.getElementById("internet-status");
        if(el) {
            el.innerText = "Internet: OFFLINE ❌ (Check Connection)";
            el.style.color = "red";
        }
        fetch(apiUrl + "?action=log_internet&status=OFFLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN"));
    };
}

function checkStatus() {
    fetch(apiUrl + "?action=status")
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
            
            document.getElementById("time-remaining").innerText = formatTime(data.time_remaining);
            if(data.mac) document.getElementById("client-mac").innerText = data.mac;
            
            checkInternet();
            setTimeout(checkStatus, 5000); 
            
        } else if(data.authenticated === "paused") {
            document.getElementById("login-section").style.display = "none";
            document.getElementById("connected-section").style.display = "none";
            document.getElementById("resume-section").style.display = "block";
            
            document.getElementById("paused-time").innerText = formatTime(data.time_remaining);
            setTimeout(checkStatus, 10000);
            
        } else {
            document.getElementById("login-section").style.display = "block";
            document.getElementById("resume-section").style.display = "none";
            document.getElementById("connected-section").style.display = "none";
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
    fetch(apiUrl + "?action=pause")
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
    fetch(apiUrl + "?action=resume")
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
    fetch(apiUrl + "?action=start_coin")
    .then(r => r.json())
    .then(data => {
        document.getElementById("coin-modal").style.display = "block";
        document.getElementById("coin-count").innerText = "0";
        document.getElementById("coin-time").innerText = "0";
        document.getElementById("connect-btn").style.display = "none";
        
        if(interval) clearInterval(interval);
        interval = setInterval(() => {
            fetch(apiUrl + "?action=check_coin")
            .then(r => r.json())
            .then(d => {
                document.getElementById("coin-count").innerText = d.count;
                document.getElementById("coin-time").innerText = d.minutes;
                if(d.count > 0) document.getElementById("connect-btn").style.display = "block";
            })
            .catch(err => console.error("Coin check failed:", err));
        }, 1000);
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
    
    fetch(apiUrl + "?action=connect")
    .then(r => r.json())
    .then(data => {
        closeModal();
        if (data.status === "connected") {
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
    fetch(apiUrl + "?action=logout")
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

# Enable debugging to log errors to system log
# set -x

# --- RAW UPLOAD HANDLER (Bypass generic POST processing for speed/RAM) ---
# Check if query string contains upload_raw action
if [ "$REQUEST_METHOD" = "POST" ] && echo "$QUERY_STRING" | grep -q "action=upload_raw"; then
    # Extract filename safely
    FILENAME=$(echo "$QUERY_STRING" | grep -o "filename=[^&]*" | cut -d= -f2)
    
    # Security Validation: Only allow specific files
    if [ "$FILENAME" = "bg.jpg" ] || [ "$FILENAME" = "insert.mp3" ] || [ "$FILENAME" = "connected.mp3" ]; then
        
        # Stream stdin directly to file (Low RAM usage)
        if [ -n "$CONTENT_LENGTH" ]; then
            # If head -c is available (BusyBox usually has it)
            head -c "$CONTENT_LENGTH" > "/www/$FILENAME" 2>/dev/null || cat > "/www/$FILENAME"
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
SESSION_COOKIE=$(echo "$HTTP_COOKIE" | grep -o "session=[^;]*" | cut -d= -f2)
ADMIN_PASS=$(uci get pisowifi.settings.admin_password 2>/dev/null || echo "admin")
DB_FILE="/etc/pisowifi/pisowifi.db"

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
        head -c "$CONTENT_LENGTH" > "$POST_FILE"
    else
        cat > "$POST_FILE"
    fi
    
    # Helper to get POST var from file
    # Uses grep and cut, handles basic URL decoding
    get_post_var() {
        # Grep for var name, then decode
        # Using grep -a (text mode) in case of binary data
        VAL=$(grep -a -o "$1=[^&]*" "$POST_FILE" | head -1 | cut -d= -f2-)
        # Decode URL encoding (limited support for huge binaries via sed)
        # For huge files, we should avoid full decode here if possible
        echo -e $(echo "$VAL" | sed 's/+/ /g; s/%/\\x/g')
    }

    ACTION=$(get_post_var "action")
    PASS=$(get_post_var "password")
    
    # Cleanup trap
    trap "rm -f $POST_FILE" EXIT
    
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
        if [ "$ACTION" = "update_wifi" ]; then
             SSID=$(get_post_var "ssid")
             ENC=$(get_post_var "encryption")
             KEY=$(get_post_var "key")
             DISABLED=$(get_post_var "disabled")
             
             # Apply to ALL wifi interfaces
             # Iterate through all sections that are 'wifi-iface'
             # uci show wireless returns: wireless.default_radio0=wifi-iface ...
             
             # Robust loop:
             # Get all config names for wifi-iface
             IFACES=$(uci show wireless | grep "=wifi-iface" | cut -d= -f1)
             for iface in $IFACES; do
                 uci set $iface.ssid="$SSID"
                 uci set $iface.encryption="$ENC"
                 uci set $iface.key="$KEY"
                 uci set $iface.disabled="$DISABLED"
             done
             
             uci commit wireless
             /sbin/wifi reload
             
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=hotspot&msg=wifi_saved"
             echo ""
             exit 0
             
        elif [ "$ACTION" = "update_settings" ]; then
             RATE=$(get_post_var "rate")
             NEW_PASS=$(get_post_var "new_pass")
             
             uci set pisowifi.settings.minutes_per_peso="$RATE"
             if [ -n "$NEW_PASS" ]; then
                 uci set pisowifi.settings.admin_password="$NEW_PASS"
             fi
             uci commit pisowifi
             
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
             
        elif [ "$ACTION" = "save_portal" ]; then
             HTML_CONTENT=$(get_post_var "html_content")
             # Write to file
             echo "$HTML_CONTENT" > /www/portal.html
             
             echo "Status: 302 Found"
             echo "Location: /cgi-bin/admin?tab=portal&msg=portal_saved"
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
                 grep -a -o "filedata=[^&]*" "$POST_FILE" | cut -d= -f2- | sed 's/%2B/+/g; s/%2F/\//g; s/%3D/=/g' | base64 -d > "/www/$FILENAME"
                 
                 echo "Status: 302 Found"
                 echo "Location: /cgi-bin/admin?tab=portal&msg=upload_success"
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


# Handle API Actions (for Dashboard Charts/Stats)
if [ "$QUERY_STRING" = "action=get_traffic" ]; then
    check_auth || exit 0
    echo "Status: 200 OK"
    echo "Content-type: application/json"
    echo ""
    # Get RX/TX bytes for WAN interface (usually eth0 or eth1, we'll try to find it)
    WAN_IF=$(uci get network.wan.device 2>/dev/null || uci get network.wan.ifname 2>/dev/null || echo "eth0")
    RX=$(cat /sys/class/net/$WAN_IF/statistics/rx_bytes 2>/dev/null || echo 0)
    TX=$(cat /sys/class/net/$WAN_IF/statistics/tx_bytes 2>/dev/null || echo 0)
    echo "{\"rx\": $RX, \"tx\": $TX, \"time\": $(date +%s)}"
    exit 0
fi

# Render Page
echo "Status: 200 OK"
echo "Content-type: text/html; charset=utf-8"
echo ""

# Use echo for HTML header to avoid nested heredoc issues
echo "<!DOCTYPE html>"
echo "<html>"
echo "<head>"
echo "<title>NEXI-FI Admin Dashboard</title>"
echo "<meta charset='UTF-8'>"
echo "<meta name='viewport' content='width=device-width, initial-scale=1'>"
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
echo "  @media (max-width: 768px) { body { flex-direction: column; } .sidebar { width: 100%; padding: 10px; box-sizing: border-box; } .main-content { padding: 15px; } }"
echo "</style>"
echo "</head>"
echo "<body>"

# Check Auth for View
if ! check_auth; then
    echo "<div style='width: 100%; height: 100vh; display: flex; justify-content: center; align-items: center;'>"
    echo "<div style='max-width: 400px; width: 100%;' class='card'>"
    echo "<h1 style='text-align: center; margin-bottom: 20px;'>Admin Login</h1>"
    if echo "$QUERY_STRING" | grep -q "error=invalid"; then echo "<p style='color:red; text-align: center;'>Invalid Password</p>"; fi
    echo "<form method='POST'><input type='password' name='password' placeholder='Password' style='width:100%; padding:12px; margin:10px 0; border:1px solid #ddd; border-radius:6px; box-sizing: border-box;' required><button class='btn btn-primary' style='width:100%; padding: 12px;'>Login</button></form>"
    echo "</div></div>"
else
    # Determine Active Tab
    TAB=$(echo "$QUERY_STRING" | grep -o "tab=[^&]*" | cut -d= -f2)
    [ -z "$TAB" ] && TAB="dashboard"

    # Sidebar
    echo "<div class='sidebar'>"
    echo "  <h2>NEXI-FI ADMIN</h2>"
    echo "  <nav>"
    echo "    <a href='?tab=dashboard' class='nav-link $([ "$TAB" = "dashboard" ] && echo "active")'>Dashboard</a>"
    echo "    <a href='?tab=rates' class='nav-link $([ "$TAB" = "rates" ] && echo "active")'>Rates Manager</a>"
    echo "    <a href='?tab=hotspot' class='nav-link $([ "$TAB" = "hotspot" ] && echo "active")'>Hotspot Manager</a>"
    echo "    <a href='?tab=sales' class='nav-link $([ "$TAB" = "sales" ] && echo "active")'>Sales Report</a>"
    echo "    <a href='?tab=portal' class='nav-link $([ "$TAB" = "portal" ] && echo "active")'>Portal Editor</a>"
    echo "    <a href='?tab=settings' class='nav-link $([ "$TAB" = "settings" ] && echo "active")'>Settings</a>"
    echo "  </nav>"
    echo "  <div style='margin-top: auto; padding-top: 20px; border-top: 1px solid rgba(255,255,255,0.1);'>"
    echo "    <form method='POST'><input type='hidden' name='action' value='logout'><button class='btn btn-danger' style='width: 100%'>Logout</button></form>"
    echo "  </div>"
    echo "</div>"

    echo "<div class='main-content'>"
    echo "<div class='container'>"

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
        NOW=$(date +%s)
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
    
    elif [ "$TAB" = "portal" ]; then
        echo "<div class='header'><h1>Portal Editor</h1></div>"
        
        if echo "$QUERY_STRING" | grep -q "msg=portal_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Portal HTML Saved Successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=upload_success"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>File Uploaded Successfully!</div>"; fi
        
        # HTML Editor
        # Read current portal html
        # We need to be careful with escaping HTML inside HTML
        # Using a simple cat might break the layout if it contains closing tags.
        # But since we are inside an echo block, we can just cat it? 
        # No, because we are generating the admin page via echo.
        # Safest way: Read file content and escape special chars for textarea.
        
        PORTAL_CONTENT=$(cat /www/portal.html 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        
        echo "<div class='grid'>"
        echo "  <div class='card' style='grid-column: span 2;'>"
        echo "    <h3>HTML Source Code</h3>"
        echo "    <form method='POST'>"
        echo "      <input type='hidden' name='action' value='save_portal'>"
        echo "      <textarea name='html_content' style='width:100%; height:400px; font-family:monospace; padding:10px; border:1px solid #cbd5e1; border-radius:6px; box-sizing:border-box;' spellcheck='false'>$PORTAL_CONTENT</textarea>"
        echo "      <div style='margin-top:10px; text-align:right;'>"
        echo "        <button class='btn btn-primary'>Save HTML Changes</button>"
        echo "      </div>"
        echo "    </form>"
        echo "  </div>"
        
        echo "  <div class='card'>"
        echo "    <h3>Media Manager</h3>"
        echo "    <p class='sub'>Upload images or audio files for your portal.</p>"
        
        echo "    <div style='margin-bottom:20px; border-bottom:1px solid #eee; padding-bottom:20px;'>"
        echo "      <h4>Background Image</h4>"
        echo "      <p class='sub'>Replaces <code>bg.jpg</code></p>"
        echo "      <input type='file' id='file-bg' accept='image/*' style='margin-bottom:10px;'>"
        echo "      <button onclick=\"uploadFile('file-bg', 'bg.jpg')\" class='btn btn-primary' style='width:100%'>Upload Background</button>"
        echo "    </div>"
        
        echo "    <div style='margin-bottom:20px; border-bottom:1px solid #eee; padding-bottom:20px;'>"
        echo "      <h4>Insert Coin Audio</h4>"
        echo "      <p class='sub'>Replaces <code>insert.mp3</code> (Plays when Insert Coin clicked)</p>"
        echo "      <input type='file' id='file-insert' accept='audio/*' style='margin-bottom:10px;'>"
        echo "      <button onclick=\"uploadFile('file-insert', 'insert.mp3')\" class='btn btn-primary' style='width:100%'>Upload Audio</button>"
        echo "    </div>"
        
        echo "    <div>"
        echo "      <h4>Connected Audio</h4>"
        echo "      <p class='sub'>Replaces <code>connected.mp3</code> (Plays when Internet Starts)</p>"
        echo "      <input type='file' id='file-connect' accept='audio/*' style='margin-bottom:10px;'>"
        echo "      <button onclick=\"uploadFile('file-connect', 'connected.mp3')\" class='btn btn-primary' style='width:100%'>Upload Audio</button>"
        echo "    </div>"
        
        echo "  </div>"
        echo "</div>"
        
        # JS for Upload
        echo "<script>"
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
        echo "</script>"

    elif [ "$TAB" = "settings" ]; then
        echo "<div class='header'><h1>Settings</h1></div>"
        
        if echo "$QUERY_STRING" | grep -q "msg=saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Settings Saved Successfully!</div>"; fi
        
        CURRENT_RATE=$(uci get pisowifi.settings.minutes_per_peso 2>/dev/null || echo 12)
        
        echo "<div class='card' style='max-width: 600px;'>"
        echo "<h3>General Configuration</h3>"
        echo "<form method='POST'>"
        echo "<input type='hidden' name='action' value='update_settings'>"
        
        echo "<div style='margin-bottom: 20px;'>"
        echo "  <label style='display:block; margin-bottom:8px; font-weight:600;'>Minutes per 1 Peso</label>"
        echo "  <input type='number' name='rate' value='$CURRENT_RATE' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        echo "  <p class='sub'>How many minutes of internet access for every 1 Peso coin.</p>"
        echo "</div>"
        
        echo "<div style='margin-bottom: 20px;'>"
        echo "  <label style='display:block; margin-bottom:8px; font-weight:600;'>New Admin Password</label>"
        echo "  <input type='password' name='new_pass' placeholder='Leave blank to keep current' style='width:100%; padding:10px; border:1px solid #cbd5e1; border-radius:6px; font-size:1rem; box-sizing: border-box;'>"
        echo "</div>"
        
        echo "<button class='btn btn-primary' style='width:100%; padding: 12px;'>Save Settings</button>"
        echo "</form>"
        echo "</div>"
    fi

    echo "</div>" # End Container
    echo "</div>" # End Main Content
fi

echo "</body></html>"
EOF
chmod +x /www/cgi-bin/admin

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

# Enable WiFi Radio
uci set wireless.radio0.disabled='0'

# Configure WiFi Interface (SSID: NEXI-FI PISOWIFI, Open)
uci set wireless.@wifi-iface[0].device='radio0'
uci set wireless.@wifi-iface[0].network='lan'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].ssid='NEXI-FI PISOWIFI'
uci set wireless.@wifi-iface[0].encryption='none'
uci set wireless.@wifi-iface[0].disabled='0'
uci commit wireless

echo "Restarting Network..."
/etc/init.d/network restart
/sbin/wifi reload

echo "Network Configured: IP 10.0.0.1, SSID 'NEXI-FI PISOWIFI'"
