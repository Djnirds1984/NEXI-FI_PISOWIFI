#!/bin/sh

echo "=== INSTALLING PISOWIFI (CGI VERSION) ==="

# 1. Ensure Firewall Script is Present
# Force overwrite to ensure fixes are applied
echo "Creating Firewall Script..."
cat << 'EOF' > /usr/bin/pisowifi_nftables.sh
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

    # 3. Postrouting (Masquerade)
    # Hook: postrouting, Priority: 100
    nft add chain inet $TABLE postrouting { type nat hook postrouting priority 100 \; }
    # Try generic masquerade for non-lan interfaces
    # Simpler: just masquerade everything leaving the WAN/Uplink
    # If we don't know the WAN name, we can masquerade everything NOT going to LAN.
    nft add rule inet $TABLE postrouting ip saddr 10.0.0.0/8 masquerade
    
    # 4. Input Chain (Allow access to Router Services)
    # We need to explicitly allow traffic to 10.0.0.1:80 (Portal) and 53 (DNS)
    nft add chain inet $TABLE input { type filter hook input priority 0 \; policy accept \; }
    nft add rule inet $TABLE input tcp dport 80 accept
    nft add rule inet $TABLE input udp dport 53 accept
    nft add rule inet $TABLE input udp dport 67-68 accept

    # --- BLOCKING LOGIC ---
    # Allow DNS/DHCP/Portal Access (Always)
    # Use chain names explicitly, variables can sometimes be empty if context is lost
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
EOF
    chmod +x /usr/bin/pisowifi_nftables.sh

# 2. Ensure Button Script is Present
if [ ! -f "/etc/rc.button/wps" ]; then
    echo "Creating Button Script..."
    cat << 'EOF' > /etc/rc.button/wps
#!/bin/sh
[ "$ACTION" = "pressed" ] || exit 0
FILE="/tmp/pisowifi_coins"
if [ ! -f "$FILE" ]; then echo "0" > "$FILE"; fi
COUNT=$(cat "$FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$FILE"
logger -t pisowifi "Coin inserted via WPS button. Total: $COUNT"
EOF
    chmod +x /etc/rc.button/wps
fi

# 3. Create Main CGI Script (The Controller)
# This handles ALL logic: Serving the page, API requests, Coin checks.
cat << 'EOF' > /www/cgi-bin/pisowifi
#!/bin/sh

# Set Content-Type
echo "Content-type: text/html"
echo ""

# Helper Variables
COIN_FILE="/tmp/pisowifi_coins"
SESSION_FILE="/tmp/pisowifi.sessions"
MINUTES_PER_PESO=12
FIREWALL_SCRIPT="/usr/bin/pisowifi_nftables.sh"

# Get Query String
QUERY_STRING="$QUERY_STRING"

# Get Request Method (GET/POST)
REQUEST_METHOD="$REQUEST_METHOD"

# Helper Functions
get_client_mac() {
    # Try to find MAC from ARP table using REMOTE_ADDR
    grep "$REMOTE_ADDR " /proc/net/arp | awk '{print $4}' | tr 'a-z' 'A-Z'
}

handle_api() {
    MAC=$(get_client_mac)
    
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
            
            if [ -n "$MAC" ] && [ -f "$SESSION_FILE" ]; then
                EXPIRY=$(grep "^$MAC " "$SESSION_FILE" | awk '{print $2}')
                NOW=$(date +%s)
                
                # Check for integer overflow or empty expiry
                # Using string comparison for basic validation
                if [ -n "$EXPIRY" ] && [ "$EXPIRY" -eq "$EXPIRY" ] 2>/dev/null; then
                     if [ "$EXPIRY" -gt "$NOW" ]; then
                        AUTH="true"
                        TIME_REMAINING=$((EXPIRY - NOW))
                        # Ensure rule exists in NFT
                        # Add error suppression to prevent log noise if chain missing
                        nft list chain inet pisowifi pisowifi_filter >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            nft list chain inet pisowifi pisowifi_filter | grep -q "$MAC" || $FIREWALL_SCRIPT allow "$MAC"
                        else
                            $FIREWALL_SCRIPT init
                            $FIREWALL_SCRIPT allow "$MAC"
                        fi
                     fi
                fi
            fi
            json_response "{\"authenticated\": $AUTH, \"time_remaining\": $TIME_REMAINING, \"mac\": \"$MAC\", \"ip\": \"$REMOTE_ADDR\"}"
            ;;
            
        "action=start_coin")
            echo "0" > "$COIN_FILE"
            $FIREWALL_SCRIPT init
            json_response "{\"status\": \"started\"}"
            ;;
            
        "action=check_coin")
            COUNT=0
            [ -f "$COIN_FILE" ] && COUNT=$(cat "$COIN_FILE")
            MINUTES=$((COUNT * MINUTES_PER_PESO))
            json_response "{\"count\": $COUNT, \"minutes\": $MINUTES}"
            ;;
            
        "action=connect")
            COUNT=0
            [ -f "$COIN_FILE" ] && COUNT=$(cat "$COIN_FILE")
            
            if [ "$COUNT" -gt 0 ]; then
                ADDED_MINUTES=$((COUNT * MINUTES_PER_PESO))
                NOW=$(date +%s)
                
                # Load current expiry
                EXPIRY=$NOW
                if [ -f "$SESSION_FILE" ]; then
                    EXISTING=$(grep "^$MAC " "$SESSION_FILE" | awk '{print $2}')
                    if [ -n "$EXISTING" ] && [ "$EXISTING" -gt "$NOW" ]; then
                        EXPIRY=$EXISTING
                    fi
                fi
                
                NEW_EXPIRY=$((EXPIRY + (ADDED_MINUTES * 60)))
                
                # Save session (Remove old entry, add new)
                grep -v "^$MAC " "$SESSION_FILE" > "$SESSION_FILE.tmp" 2>/dev/null
                echo "$MAC $NEW_EXPIRY" >> "$SESSION_FILE.tmp"
                mv "$SESSION_FILE.tmp" "$SESSION_FILE"
                
                # Reset Coin
                echo "0" > "$COIN_FILE"
                
                # Allow Access
                $FIREWALL_SCRIPT allow "$MAC"
                logger -t pisowifi "User $MAC connected successfully. Time added: $ADDED_MINUTES mins. New Expiry: $NEW_EXPIRY"
                
                json_response "{\"status\": \"connected\", \"expiry\": $NEW_EXPIRY}"
            else
                json_response "{\"error\": \"No coins\"}"
            fi
            ;;
            
        "action=logout")
            $FIREWALL_SCRIPT deny "$MAC"
            grep -v "^$MAC " "$SESSION_FILE" > "$SESSION_FILE.tmp" 2>/dev/null
            mv "$SESSION_FILE.tmp" "$SESSION_FILE"
            json_response "{\"status\": \"success\"}"
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
    esac
}

# Check if it's an API call
echo "$QUERY_STRING" | grep -q "action=" && handle_api

# If not API, serve HTML Landing Page
cat << 'HTML'
<!DOCTYPE html>
<html>
<head>
<title>PisoWifi Portal</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font-family: sans-serif; text-align: center; padding: 20px; background: #f4f4f4; }
.container { background: white; max-width: 500px; margin: 0 auto; padding: 20px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
button { padding: 15px 30px; font-size: 1.2em; color: white; border: none; border-radius: 5px; cursor: pointer; margin: 10px; width: 100%; }
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
    
    <div id="login-section" style="display:none;">
        <p>Insert Coin to Connect</p>
        <button onclick="startCoin()" class="btn-green">INSERT COIN</button>
    </div>
    
    <div id="connected-section" style="display:none;">
        <h2>Connected!</h2>
        <p>MAC: <span id="client-mac"></span></p>
        <p>Time Remaining: <strong id="time-remaining"></strong></p>
        <p id="internet-status" style="font-size: 0.8em; color: gray;">Checking internet...</p>
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
        <button id="connect-btn" onclick="connect()" class="btn-blue" style="display:none;">START INTERNET</button>
        <button onclick="closeModal()" style="background:none; color:red; margin-top:10px;">Cancel</button>
    </div>
</div>

<script>
var apiUrl = "/cgi-bin/pisowifi";
var interval;

function formatTime(s) {
    if(s<=0) return "Expired";
    var h = Math.floor(s/3600);
    var m = Math.floor((s%3600)/60);
    var sec = s%60;
    return h+"h "+m+"m "+sec+"s";
}

function checkInternet() {
    var img = new Image();
    var now = new Date().getTime();
    // Use a reliable image source. Google Logo is good.
    // We add a random query param to prevent caching.
    img.src = "https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?t=" + now;
    
    img.onload = function() {
        var el = document.getElementById("internet-status");
        if(el) {
            el.innerText = "Internet: ONLINE ✅";
            el.style.color = "green";
        }
        // Send status back to server for logging
        fetch(apiUrl + "?action=log_internet&status=ONLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN"));
    };
    
    img.onerror = function() {
        var el = document.getElementById("internet-status");
        if(el) {
            el.innerText = "Internet: OFFLINE ❌ (Check Connection)";
            el.style.color = "red";
        }
        // Send status back to server for logging
        fetch(apiUrl + "?action=log_internet&status=OFFLINE&mac=" + encodeURIComponent(document.getElementById("client-mac") ? document.getElementById("client-mac").innerText : "UNKNOWN"));
    };
}

function checkStatus() {
    fetch(apiUrl + "?action=status")
    .then(r => r.json())
    .then(data => {
        document.getElementById("loading").style.display = "none";
        if(data.authenticated) {
            document.getElementById("login-section").style.display = "none";
            document.getElementById("connected-section").style.display = "block";
            document.getElementById("time-remaining").innerText = formatTime(data.time_remaining);
            if(data.mac) document.getElementById("client-mac").innerText = data.mac;
            
            // Check internet status every time we update status (every 5s)
            checkInternet();
            
            setTimeout(checkStatus, 5000);
        } else {
            document.getElementById("login-section").style.display = "block";
            document.getElementById("connected-section").style.display = "none";
        }
    });
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
            });
        }, 1000);
    });
}

function connect() {
    fetch(apiUrl + "?action=connect")
    .then(r => r.json())
    .then(data => {
        closeModal();
        checkStatus();
    });
}

function logout() {
    fetch(apiUrl + "?action=logout").then(() => checkStatus());
}

function closeModal() {
    document.getElementById("coin-modal").style.display = "none";
    if(interval) clearInterval(interval);
}

checkStatus();
</script>

</body>
</html>
HTML
EOF
chmod +x /www/cgi-bin/pisowifi

# 4. Redirect Root to CGI
echo "Setting up redirect..."
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

echo "=== CGI INSTALLATION COMPLETE ==="
echo "Access at http://10.0.0.1/cgi-bin/pisowifi"
