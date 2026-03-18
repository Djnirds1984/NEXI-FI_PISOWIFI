#!/bin/sh

# FIX SYNC FUNCTIONALITY - Single file solution
echo "=== FIXING SYNC FUNCTIONALITY ==="
echo "Fixing centralized key detection for sync..."

# Get current directory
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Configuration
CGI_FILE="/www/admin"
[ -f "$CGI_FILE" ] || CGI_FILE="/www/cgi-bin/admin"
BACKUP_FILE="${CGI_FILE}.backup.syncfix.$(date +%s)"
SYNC_SCRIPT="/usr/bin/wifi_devices_sync_auto.sh"

# Check if CGI file exists
if [ ! -f "$CGI_FILE" ]; then
    echo "❌ CGI file not found at $CGI_FILE"
    echo "Please ensure the system is installed first"
    exit 1
fi

# Create backup
echo "Creating backup..."
cp "$CGI_FILE" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# Fix the sync_devices function to properly detect centralized key
echo "Fixing sync_devices function..."

# Create temporary file
TEMP_FILE="/tmp/admin_sync_fix.tmp"

# Find and replace the sync_devices function
grep -n "elif \[ \"\$ACTION\" = \"sync_devices\" \]; then" "$CGI_FILE" | head -1 | cut -d: -f1 > /tmp/sync_start_line.txt
SYNC_START=$(cat /tmp/sync_start_line.txt)

if [ -n "$SYNC_START" ]; then
    # Find the end of sync_devices function (next elif)
    SYNC_END=$(grep -n "elif \[ \"\$ACTION\" = " "$CGI_FILE" | grep -A1 "sync_devices" | tail -1 | cut -d: -f1)
    
    # Extract everything before sync function
    head -n $((SYNC_START - 1)) "$CGI_FILE" > "$TEMP_FILE"
    
    # Add fixed sync function
    cat >> "$TEMP_FILE" << 'EOF'
        elif [ "$ACTION" = "sync_devices" ]; then
             UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
             CENTRALIZED_KEY="$($UCI_BIN -q get pisowifi.license.centralized_key 2>/dev/null)"
             CENTRAL_STATUS="$($UCI_BIN -q get pisowifi.license.centralized_status 2>/dev/null)"
             CENTRAL_STATUS_LC="$(echo "$CENTRAL_STATUS" | tr 'A-Z' 'a-z')"
             if [ -n "$CENTRAL_STATUS_LC" ] && [ "$CENTRAL_STATUS_LC" != "active" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Centralized key is not active. Please activate it first."}'
                 exit 0
             fi
             if [ -z "$CENTRALIZED_KEY" ] || [ "$CENTRALIZED_KEY" = "none" ]; then
                 if [ -f "/etc/pisowifi/license.json" ]; then
                     CENTRALIZED_KEY="$(sed -n 's/.*\"license_key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' /etc/pisowifi/license.json | head -n1)"
                 fi
             fi
             if [ -z "$CENTRALIZED_KEY" ] || [ "$CENTRALIZED_KEY" = "none" ]; then
                 if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
                     CENTRALIZED_KEY="$(sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='centralized_key' LIMIT 1;" 2>/dev/null)"
                     if [ -z "$CENTRALIZED_KEY" ] || [ "$CENTRALIZED_KEY" = "none" ]; then
                         CENTRALIZED_KEY="$(sqlite3 "$DB_FILE" "SELECT centralized_key FROM settings LIMIT 1;" 2>/dev/null)"
                     fi
                 fi
             fi
             if ! echo "$CENTRALIZED_KEY" | grep -Eq '^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$'; then
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
                     SYNC_SAFE="$(printf '%s' "$SYNC_RESULT" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
                     if [ -n "$SYNC_SAFE" ]; then
                         echo "{\"status\":\"success\",\"message\":\"Device sync completed: $SYNC_SAFE\"}"
                     else
                         echo '{"status":"success","message":"Device sync completed successfully."}'
                     fi
                 else
                     SYNC_SAFE="$(printf '%s' "$SYNC_RESULT" | tr '\r\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
                     echo "{\"status\":\"error\",\"message\":\"Sync failed: $SYNC_SAFE\"}"
                 fi
             else
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Sync script not found. Please reinstall device sync functionality."}'
             fi
             exit 0

        elif [ "$ACTION" = "sync_get_interval" ]; then
             UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
             MIN="$($UCI_BIN -q get pisowifi.license.auto_sync_minutes 2>/dev/null)"
             [ -z "$MIN" ] && MIN="30"
             case "$MIN" in
                 ''|*[!0-9]*) MIN="30" ;;
             esac
             echo "Content-type: application/json"
             echo ""
             echo "{\"status\":\"success\",\"minutes\":$MIN}"
             exit 0

        elif [ "$ACTION" = "sync_set_interval" ]; then
             UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
             MIN="$(get_post_var "minutes")"
             case "$MIN" in
                 ''|*[!0-9]*) MIN="" ;;
             esac
             if [ -z "$MIN" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Invalid minutes value"}'
                 exit 0
             fi

             CRON_EXPR=""
             if [ "$MIN" = "0" ]; then
                 CRON_EXPR=""
             else
                 case "$MIN" in
                     15) CRON_EXPR="*/15 * * * *" ;;
                     30) CRON_EXPR="*/30 * * * *" ;;
                     60) CRON_EXPR="0 * * * *" ;;
                     120) CRON_EXPR="0 */2 * * *" ;;
                     360) CRON_EXPR="0 */6 * * *" ;;
                     720) CRON_EXPR="0 */12 * * *" ;;
                     1440) CRON_EXPR="0 0 * * *" ;;
                     *) CRON_EXPR="" ;;
                 esac
             fi

             if [ "$MIN" != "0" ] && [ -z "$CRON_EXPR" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Unsupported interval. Use 0, 15, 30, 60, 120, 360, 720, or 1440."}'
                 exit 0
             fi

             $UCI_BIN set pisowifi.license.auto_sync_minutes="$MIN" 2>/dev/null || true
             $UCI_BIN commit pisowifi 2>/dev/null || true

             CRON_FILE="/etc/crontabs/root"
             [ -d /etc/crontabs ] || mkdir -p /etc/crontabs
             TMP_CRON="/tmp/pisowifi_cron_root_$$"
             if [ -f "$CRON_FILE" ]; then
                 $CAT "$CRON_FILE" | $GREP -v "pisowifi_auto_sync" > "$TMP_CRON" 2>/dev/null
             else
                 $CAT /dev/null > "$TMP_CRON" 2>/dev/null
             fi

             if [ "$MIN" != "0" ]; then
                 echo "$CRON_EXPR sh /usr/bin/wifi_devices_sync_auto.sh >/tmp/pisowifi_auto_sync.log 2>&1 # pisowifi_auto_sync" >> "$TMP_CRON"
             fi

             mv "$TMP_CRON" "$CRON_FILE" 2>/dev/null || true
             chmod 600 "$CRON_FILE" 2>/dev/null || true
             [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1 || true

             echo "Content-type: application/json"
             echo ""
             echo "{\"status\":\"success\",\"minutes\":$MIN}"
             exit 0
EOF
    
    # Add everything after sync function
    tail -n +$SYNC_END "$CGI_FILE" >> "$TEMP_FILE"
    
    # Replace original file
    mv "$TEMP_FILE" "$CGI_FILE"
    chmod +x "$CGI_FILE"
    
    echo "✅ Sync function fixed"
else
    echo "⚠️  sync_devices function not found, adding it..."
    
    # Find where to insert the sync function (after device_add_time)
    INSERT_LINE=$(grep -n "elif \[ \"\$ACTION\" = \"device_add_time\" \]; then" "$CGI_FILE" | head -1 | cut -d: -f1)
    
    if [ -n "$INSERT_LINE" ]; then
        # Find the end of device_add_time function
        INSERT_END=$(grep -n -A20 "device_add_time" "$CGI_FILE" | grep -m1 "exit 0" | cut -d: -f1)
        
        # Create new file with sync function inserted
        head -n $INSERT_END "$CGI_FILE" > "$TEMP_FILE"
        
        # Add sync function
        cat >> "$TEMP_FILE" << 'EOF'

        elif [ "$ACTION" = "sync_devices" ]; then
             UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
             CENTRALIZED_KEY="$($UCI_BIN -q get pisowifi.license.centralized_key 2>/dev/null)"
             CENTRAL_STATUS="$($UCI_BIN -q get pisowifi.license.centralized_status 2>/dev/null)"
             CENTRAL_STATUS_LC="$(echo "$CENTRAL_STATUS" | tr 'A-Z' 'a-z')"
             if [ -n "$CENTRAL_STATUS_LC" ] && [ "$CENTRAL_STATUS_LC" != "active" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Centralized key is not active. Please activate it first."}'
                 exit 0
             fi
             if [ -z "$CENTRALIZED_KEY" ] || [ "$CENTRALIZED_KEY" = "none" ]; then
                 if [ -f "/etc/pisowifi/license.json" ]; then
                     CENTRALIZED_KEY="$(sed -n 's/.*\"license_key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' /etc/pisowifi/license.json | head -n1)"
                 fi
             fi
             if [ -z "$CENTRALIZED_KEY" ] || [ "$CENTRALIZED_KEY" = "none" ]; then
                 if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
                     CENTRALIZED_KEY="$(sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='centralized_key' LIMIT 1;" 2>/dev/null)"
                     if [ -z "$CENTRALIZED_KEY" ] || [ "$CENTRALIZED_KEY" = "none" ]; then
                         CENTRALIZED_KEY="$(sqlite3 "$DB_FILE" "SELECT centralized_key FROM settings LIMIT 1;" 2>/dev/null)"
                     fi
                 fi
             fi
             if ! echo "$CENTRALIZED_KEY" | grep -Eq '^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$'; then
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
                     SYNC_SAFE="$(printf '%s' "$SYNC_RESULT" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
                     if [ -n "$SYNC_SAFE" ]; then
                         echo "{\"status\":\"success\",\"message\":\"Device sync completed: $SYNC_SAFE\"}"
                     else
                         echo '{"status":"success","message":"Device sync completed successfully."}'
                     fi
                 else
                     SYNC_SAFE="$(printf '%s' "$SYNC_RESULT" | tr '\r\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
                     echo "{\"status\":\"error\",\"message\":\"Sync failed: $SYNC_SAFE\"}"
                 fi
             else
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Sync script not found. Please reinstall device sync functionality."}'
             fi
             exit 0

        elif [ "$ACTION" = "sync_get_interval" ]; then
             UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
             MIN="$($UCI_BIN -q get pisowifi.license.auto_sync_minutes 2>/dev/null)"
             [ -z "$MIN" ] && MIN="30"
             case "$MIN" in
                 ''|*[!0-9]*) MIN="30" ;;
             esac
             echo "Content-type: application/json"
             echo ""
             echo "{\"status\":\"success\",\"minutes\":$MIN}"
             exit 0

        elif [ "$ACTION" = "sync_set_interval" ]; then
             UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
             MIN="$(get_post_var "minutes")"
             case "$MIN" in
                 ''|*[!0-9]*) MIN="" ;;
             esac
             if [ -z "$MIN" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Invalid minutes value"}'
                 exit 0
             fi

             CRON_EXPR=""
             if [ "$MIN" = "0" ]; then
                 CRON_EXPR=""
             else
                 case "$MIN" in
                     15) CRON_EXPR="*/15 * * * *" ;;
                     30) CRON_EXPR="*/30 * * * *" ;;
                     60) CRON_EXPR="0 * * * *" ;;
                     120) CRON_EXPR="0 */2 * * *" ;;
                     360) CRON_EXPR="0 */6 * * *" ;;
                     720) CRON_EXPR="0 */12 * * *" ;;
                     1440) CRON_EXPR="0 0 * * *" ;;
                     *) CRON_EXPR="" ;;
                 esac
             fi

             if [ "$MIN" != "0" ] && [ -z "$CRON_EXPR" ]; then
                 echo "Content-type: application/json"
                 echo ""
                 echo '{"status":"error","message":"Unsupported interval. Use 0, 15, 30, 60, 120, 360, 720, or 1440."}'
                 exit 0
             fi

             $UCI_BIN set pisowifi.license.auto_sync_minutes="$MIN" 2>/dev/null || true
             $UCI_BIN commit pisowifi 2>/dev/null || true

             CRON_FILE="/etc/crontabs/root"
             [ -d /etc/crontabs ] || mkdir -p /etc/crontabs
             TMP_CRON="/tmp/pisowifi_cron_root_$$"
             if [ -f "$CRON_FILE" ]; then
                 $CAT "$CRON_FILE" | $GREP -v "pisowifi_auto_sync" > "$TMP_CRON" 2>/dev/null
             else
                 $CAT /dev/null > "$TMP_CRON" 2>/dev/null
             fi

             if [ "$MIN" != "0" ]; then
                 echo "$CRON_EXPR sh /usr/bin/wifi_devices_sync_auto.sh >/tmp/pisowifi_auto_sync.log 2>&1 # pisowifi_auto_sync" >> "$TMP_CRON"
             fi

             mv "$TMP_CRON" "$CRON_FILE" 2>/dev/null || true
             chmod 600 "$CRON_FILE" 2>/dev/null || true
             [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1 || true

             echo "Content-type: application/json"
             echo ""
             echo "{\"status\":\"success\",\"minutes\":$MIN}"
             exit 0
EOF
        
        # Add remaining content
        tail -n +$((INSERT_END + 1)) "$CGI_FILE" >> "$TEMP_FILE"
        
        # Replace original file
        mv "$TEMP_FILE" "$CGI_FILE"
        chmod +x "$CGI_FILE"
        
        echo "✅ Sync function added"
    fi
fi

# Install sync script if not exists
echo "Fixing sql_escape for GET requests..."
POST_LINE="$(grep -n "# --- POST REQUEST HANDLER ---" "$CGI_FILE" | head -1 | cut -d: -f1)"
SQL_LINE="$(grep -n "^[[:space:]]*sql_escape()[[:space:]]*{" "$CGI_FILE" | head -1 | cut -d: -f1)"
if [ -n "$POST_LINE" ] && [ -n "$SQL_LINE" ] && [ "$SQL_LINE" -gt "$POST_LINE" ]; then
    awk "
    BEGIN { inserted = 0 }
    /# --- POST REQUEST HANDLER ---/ && inserted == 0 {
        print \"\"
        print \"sql_escape() {\"
        print \"    printf \\\"%s\\\" \\\"\\\\\\\$1\\\" | \\\\\$SED \\\"s/'/''/g\\\"\"
        print \"}\"
        print \"\"
        inserted = 1
        print
        next
    }
    { print }
    " "$CGI_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CGI_FILE"
    chmod +x "$CGI_FILE"
    echo "✅ sql_escape fixed"
else
    echo "✅ sql_escape already OK"
fi

echo "Checking sync script..."
NEED_INSTALL_SYNC="0"
if [ ! -f "$SYNC_SCRIPT" ]; then
    NEED_INSTALL_SYNC="1"
else
    SHEBANG_LINE="$(head -n1 "$SYNC_SCRIPT" 2>/dev/null | tr -d '\r')"
    echo "$SHEBANG_LINE" | grep -q "/bin/bash"
    if [ "$?" = "0" ]; then
        NEED_INSTALL_SYNC="1"
    else
        grep -q "machine_id" "$SYNC_SCRIPT" 2>/dev/null || NEED_INSTALL_SYNC="1"
        grep -q "last_heartbeat" "$SYNC_SCRIPT" 2>/dev/null || NEED_INSTALL_SYNC="1"
        grep -q "source=leases" "$SYNC_SCRIPT" 2>/dev/null || NEED_INSTALL_SYNC="1"
        grep -q "vendors?select=id" "$SYNC_SCRIPT" 2>/dev/null || NEED_INSTALL_SYNC="1"
        grep -q "\"status\":\"active\"" "$SYNC_SCRIPT" 2>/dev/null && NEED_INSTALL_SYNC="1"
    fi
fi

if [ "$NEED_INSTALL_SYNC" = "1" ]; then
    cat > "$SYNC_SCRIPT" << 'EOS'
#!/bin/sh
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
UCI_BIN="$(command -v uci 2>/dev/null || echo /sbin/uci)"
DB_FILE="/etc/pisowifi/pisowifi.db"
VENDOR_ID="$($UCI_BIN -q get pisowifi.license.centralized_vendor_id 2>/dev/null)"
MACHINE_ID="$($UCI_BIN -q get pisowifi.license.vendor_uuid 2>/dev/null)"
if [ -z "$MACHINE_ID" ] && [ -f /etc/pisowifi/machine_id ]; then
    MACHINE_ID="$(head -n1 /etc/pisowifi/machine_id 2>/dev/null | tr -d '\r')"
fi
HARDWARE_ID="$($UCI_BIN -q get pisowifi.license.hardware_id 2>/dev/null)"
CENTRAL_KEY="$($UCI_BIN -q get pisowifi.license.centralized_key 2>/dev/null)"
HOSTNAME_VAL="$($UCI_BIN -q get system.@system[0].hostname 2>/dev/null)"
[ -z "$HOSTNAME_VAL" ] && HOSTNAME_VAL="$(hostname 2>/dev/null)"
[ -z "$HARDWARE_ID" ] && [ -f /etc/pisowifi/hardware_id ] && HARDWARE_ID="$(head -n1 /etc/pisowifi/hardware_id 2>/dev/null | tr -d '\r')"
[ -z "$HARDWARE_ID" ] && [ -f /etc/machine-id ] && HARDWARE_ID="$(head -n1 /etc/machine-id 2>/dev/null | tr -d '\r')"
if [ -z "$MACHINE_ID" ] && [ -f /etc/pisowifi/license.json ]; then
    MACHINE_ID="$(sed -n 's/.*\"vendor_uuid\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' /etc/pisowifi/license.json | head -n1)"
fi
if [ -z "$MACHINE_ID" ] && command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB_FILE" ]; then
    MACHINE_ID="$(sqlite3 -separator '|' "$DB_FILE" "SELECT vendor_uuid FROM license LIMIT 1;" 2>/dev/null | head -n1)"
fi
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
fi
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
if [ -z "$MACHINE_ID" ]; then
    echo "missing_required_config machine_id=empty vendor_id=$VENDOR_ID"
    exit 2
fi
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
SRC="none"
STATUS_VAL="pending"
SQL_ERR="/tmp/wifi_devices_sync_sqlerr.$$"

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
    STATUS_VAL="known"
elif try_query "$QUERY_DEV_2"; then
    SRC="devices"
    STATUS_VAL="known"
elif try_query "$QUERY_DEV_3"; then
    SRC="devices"
    STATUS_VAL="known"
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
        STATUS_VAL="active"
    elif try_query "$QUERY_USERS_2"; then
        SRC="users"
        STATUS_VAL="active"
    elif try_query "$QUERY_USERS_3"; then
        SRC="users"
        STATUS_VAL="active"
    elif try_query "$QUERY_USERS_4"; then
        SRC="users"
        STATUS_VAL="active"
    elif try_query "$QUERY_USERS_5"; then
        SRC="users"
        STATUS_VAL="active"
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
        STATUS_VAL="pending"
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
LEASE_FILES="/tmp/dhcp.leases /tmp/dnsmasq.leases /var/dhcp.leases"
while IFS='|' read -r MAC IP DEV SSTART SEND; do
    [ -z "$MAC" ] && continue
    SYNC_TOTAL=$((SYNC_TOTAL + 1))
    MAC_UP="$(printf '%s' "$MAC" | tr 'a-z' 'A-Z')"
    MAC_ESC="$(printf '%s' "$MAC_UP" | sed 's/"/\\"/g')"
    IP_ESC="$(printf '%s' "$IP" | sed 's/"/\\"/g')"
    DEV_ESC="$(printf '%s' "$DEV" | sed 's/"/\\"/g')"
    END_TS=0
    PAUSED_TS=0
    SESSION_ROW="$(sqlite3 -separator '|' "$DB_FILE" "SELECT session_end, paused_time FROM users WHERE mac='$MAC_UP' LIMIT 1;" 2>/dev/null)"
    END_TS="$(printf '%s' "$SESSION_ROW" | cut -d'|' -f1)"
    PAUSED_TS="$(printf '%s' "$SESSION_ROW" | cut -d'|' -f2)"
    [ -z "$END_TS" ] && END_TS=0
    [ -z "$PAUSED_TS" ] && PAUSED_TS=0
    REM=0
    if [ "$PAUSED_TS" -gt 0 ] 2>/dev/null; then
        REM="$PAUSED_TS"
    elif [ "$END_TS" -gt "$NOW_EPOCH" ] 2>/dev/null; then
        REM=$((END_TS - NOW_EPOCH))
    fi

    IS_CONN_JSON=false
    for lf in $LEASE_FILES; do
        if [ -f "$lf" ]; then
            LEASE_INFO="$(grep -i "$MAC_UP" "$lf" 2>/dev/null | head -n1)"
            if [ -n "$LEASE_INFO" ]; then
                set -- $LEASE_INFO
                LEASE_IP="$3"
                LEASE_NAME="$4"
                [ -n "$LEASE_IP" ] && IP_ESC="$(printf '%s' "$LEASE_IP" | sed 's/"/\\"/g')"
                if [ -n "$LEASE_NAME" ] && [ "$LEASE_NAME" != "*" ]; then
                    DEV_ESC="$(printf '%s' "$LEASE_NAME" | sed 's/"/\\"/g')"
                fi
                IS_CONN_JSON=true
                break
            fi
        fi
    done
    if [ "$IS_CONN_JSON" = "false" ] && command -v iw >/dev/null 2>&1; then
        for ifc in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
            iw dev "$ifc" station dump 2>/dev/null | grep -qi "$MAC_UP" && IS_CONN_JSON=true && break
        done
    fi
    if [ "$IS_CONN_JSON" = "false" ] && [ -f /proc/net/arp ]; then
        ARP_LINE="$(grep -i "$MAC_UP" /proc/net/arp 2>/dev/null | head -n1)"
        if [ -n "$ARP_LINE" ]; then
            ARP_IP="$(echo "$ARP_LINE" | awk '{print $1}')"
            [ -n "$ARP_IP" ] && IP_ESC="$(printf '%s' "$ARP_IP" | sed 's/"/\\"/g')"
            IS_CONN_JSON=true
        fi
    fi

    TOKEN="$(sqlite3 -separator '|' "$DB_FILE" "SELECT session_token FROM users WHERE mac='$MAC_UP' LIMIT 1;" 2>/dev/null | head -n1)"
    TOKEN_ESC="$(printf '%s' "$TOKEN" | sed 's/\"/\\\"/g')"
    BODY="{\"vendor_id\":\"$VENDOR_ID\",\"machine_id\":\"$MACHINE_ID\",\"mac_address\":\"$MAC_ESC\",\"ip_address\":\"$IP_ESC\",\"device_name\":\"$DEV_ESC\",\"remaining_seconds\":$REM"
    if [ -n "$TOKEN_ESC" ]; then
        BODY="$BODY,\"session_token\":\"$TOKEN_ESC\""
    fi
    BODY="$BODY,\"last_heartbeat\":\"$NOW_ISO\",\"last_sync_attempt\":\"$NOW_ISO\",\"sync_status\":\"success\",\"is_connected\":$IS_CONN_JSON}"
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
COUNT_LINE="$(cat "$H" 2>/dev/null | tr -d '\r' | grep -i '^Content-Range:' | head -1)"
TOTAL_COUNT="$(echo "$COUNT_LINE" | sed -n 's/.*\/\([0-9][0-9]*\)$/\1/p')"
rm -f "$H" "$T" 2>/dev/null
echo "source=$SRC total=$SYNC_TOTAL updated=$SYNC_UPDATED inserted=$SYNC_INSERTED supabase_count=${TOTAL_COUNT:-unknown} http=$CODEC"
exit 0
EOS
    sed -i 's/\r$//' "$SYNC_SCRIPT" 2>/dev/null || true
    chmod +x "$SYNC_SCRIPT"
    echo "✅ Sync script installed"
else
    sed -i 's/\r$//' "$SYNC_SCRIPT" 2>/dev/null || true
    chmod +x "$SYNC_SCRIPT" 2>/dev/null || true
    echo "✅ Sync script already exists"
fi

# Add Sync All button to device manager if not exists
echo "Adding Sync All button to device manager..."

# Check if button already exists
if ! grep -q "sync-all-btn" "$CGI_FILE"; then
    # Create a simple replacement using awk instead of sed
    awk '
    /<h3>Device Manager<\/h3>/ {
        print
        print "        echo \"<div style=\\\"margin-bottom:16px;\\\">\""
        print "        echo \"<p style=\\\"color:#64748b; font-size:14px; margin-bottom:8px;\\\">Devices are automatically saved when they connect to the network. Online devices show green status.</p>\""
        print "        echo \"<button id=\\\"sync-all-btn\\\" class=\\\"btn btn-primary\\\" style=\\\"background:linear-gradient(135deg, #667eea 0%, #764ba2 100%); border:none; padding:8px 16px; border-radius:6px; color:white; cursor:pointer;\\\">Sync All Devices</button>\""
        print "        echo \"<div style=\\\"margin-top:10px; display:flex; gap:10px; align-items:center; flex-wrap:wrap;\\\">\""
        print "        echo \"<label style=\\\"font-size:13px; color:#475569;\\\">Auto Sync</label>\""
        print "        echo \"<select id=\\\"auto-sync-select\\\" style=\\\"padding:6px 10px; border:1px solid #cbd5e1; border-radius:6px;\\\">\""
        print "        echo \"  <option value=\\\"0\\\">Disabled</option>\""
        print "        echo \"  <option value=\\\"15\\\">Every 15 minutes</option>\""
        print "        echo \"  <option value=\\\"30\\\">Every 30 minutes</option>\""
        print "        echo \"  <option value=\\\"60\\\">Every 1 hour</option>\""
        print "        echo \"  <option value=\\\"120\\\">Every 2 hours</option>\""
        print "        echo \"  <option value=\\\"360\\\">Every 6 hours</option>\""
        print "        echo \"  <option value=\\\"720\\\">Every 12 hours</option>\""
        print "        echo \"  <option value=\\\"1440\\\">Every 24 hours</option>\""
        print "        echo \"</select>\""
        print "        echo \"<button id=\\\"auto-sync-save\\\" class=\\\"btn btn-secondary\\\" style=\\\"padding:6px 12px; border-radius:6px; border:1px solid #cbd5e1; background:#f8fafc; cursor:pointer;\\\">Save</button>\""
        print "        echo \"</div>\""
        print "        echo \"</div>\""
        next
    }
    { print }
    ' "$CGI_FILE" > "$TEMP_FILE"
    
    mv "$TEMP_FILE" "$CGI_FILE"
    chmod +x "$CGI_FILE"
    
    echo "✅ Sync All button added"
else
    echo "✅ Sync All button already exists"
fi

echo "Adding Auto Sync selector to device manager..."
if grep -q "sync-all-btn" "$CGI_FILE" && ! grep -q "auto-sync-select" "$CGI_FILE"; then
    awk '
    /id=\\"sync-all-btn\\"/ {
        print
        print "        echo \"<div style=\\\"margin-top:10px; display:flex; gap:10px; align-items:center; flex-wrap:wrap;\\\">\""
        print "        echo \"<label style=\\\"font-size:13px; color:#475569;\\\">Auto Sync</label>\""
        print "        echo \"<select id=\\\"auto-sync-select\\\" style=\\\"padding:6px 10px; border:1px solid #cbd5e1; border-radius:6px;\\\">\""
        print "        echo \"  <option value=\\\"0\\\">Disabled</option>\""
        print "        echo \"  <option value=\\\"15\\\">Every 15 minutes</option>\""
        print "        echo \"  <option value=\\\"30\\\">Every 30 minutes</option>\""
        print "        echo \"  <option value=\\\"60\\\">Every 1 hour</option>\""
        print "        echo \"  <option value=\\\"120\\\">Every 2 hours</option>\""
        print "        echo \"  <option value=\\\"360\\\">Every 6 hours</option>\""
        print "        echo \"  <option value=\\\"720\\\">Every 12 hours</option>\""
        print "        echo \"  <option value=\\\"1440\\\">Every 24 hours</option>\""
        print "        echo \"</select>\""
        print "        echo \"<button id=\\\"auto-sync-save\\\" class=\\\"btn btn-secondary\\\" style=\\\"padding:6px 12px; border-radius:6px; border:1px solid #cbd5e1; background:#f8fafc; cursor:pointer;\\\">Save</button>\""
        print "        echo \"</div>\""
        next
    }
    { print }
    ' "$CGI_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CGI_FILE"
    chmod +x "$CGI_FILE"
    echo "✅ Auto Sync selector added"
else
    echo "✅ Auto Sync selector already exists"
fi

# Add JavaScript for sync functionality if not exists
echo "Adding sync JavaScript..."
if ! grep -q "sync-all-btn.*addEventListener" "$CGI_FILE"; then
    # Add JavaScript at the end of device manager section
    awk '
    /echo "<\/table>"/ {
        print
        in_device_manager = 1
        next
    }
    /echo "<\/div>"/ && in_device_manager {
        print
        print "        echo \"<script>\""
        print "        echo \"document.getElementById(\\\"sync-all-btn\\\").addEventListener(\\\"click\\\", function() {\""
        print "        echo \"  var btn = this;\""
        print "        echo \"  var originalText = btn.textContent;\""
        print "        echo \"  btn.textContent = \\\"Syncing...\\\";\""
        print "        echo \"  btn.disabled = true;\""
        print "        echo \"  \""
        print "        echo \"  fetch(\\\"/cgi-bin/admin\\\", {\""
        print "        echo \"    method: \\\"POST\\\",\""
        print "        echo \"    headers: {\\\"Content-Type\\\": \\\"application/x-www-form-urlencoded\\\"},\""
        print "        echo \"    body: \\\"action=sync_devices\\\"\""
        print "        echo \"  })\""
        print "        echo \"  .then(response => response.json())\""
        print "        echo \"  .then(data => {\""
        print "        echo \"    if(data.status === \\\"success\\\") {\""
        print "        echo \"      alert(\\\"✅ \\\" + data.message);\""
        print "        echo \"      location.reload();\""
        print "        echo \"    } else {\""
        print "        echo \"      alert(\\\"❌ \\\" + data.message);\""
        print "        echo \"      btn.textContent = originalText;\""
        print "        echo \"      btn.disabled = false;\""
        print "        echo \"    }\""
        print "        echo \"  })\""
        print "        echo \"  .catch(error => {\""
        print "        echo \"    alert(\\\"❌ Sync failed: \\\" + error);\""
        print "        echo \"    btn.textContent = originalText;\""
        print "        echo \"    btn.disabled = false;\""
        print "        echo \"  });\""
        print "        echo \"});\""
        print "        echo \"</script>\""
        in_device_manager = 0
        next
    }
    { print }
    ' "$CGI_FILE" > "$TEMP_FILE"
    
    mv "$TEMP_FILE" "$CGI_FILE"
    chmod +x "$CGI_FILE"
    
    echo "✅ Sync JavaScript added"
else
    echo "✅ Sync JavaScript already exists"
fi

echo "Hardening Sync All JSON handling..."
if grep -q "echo \"  \\.then(response => response\\.json())\"" "$CGI_FILE" 2>/dev/null; then
    sed -i 's/echo \"  \\.then(response => response\\.json())\"/echo \"  .then(response => response.text())\"/g' "$CGI_FILE" 2>/dev/null || true
    if ! grep -q "JSON.parse(text)" "$CGI_FILE" 2>/dev/null; then
        sed -i '/echo \"  \\.then(response => response\\.text())\"/a\        echo \"  .then(function(text){ var data; try { data = JSON.parse(text); } catch(e){ throw new Error(text.slice(0,120)); } return data; })\"' "$CGI_FILE" 2>/dev/null || true
    fi
fi
if ! grep -q "credentials:" "$CGI_FILE" 2>/dev/null; then
    sed -i '/echo \"    method: \\\\\"POST\\\\\",\\\"/a\        echo \"    credentials: \\\\\"same-origin\\\\\",\\\"' "$CGI_FILE" 2>/dev/null || true
    sed -i '/echo \"    method: '\\''POST'\\''\",/a\        echo \"    credentials: '\\''same-origin'\\''\",' "$CGI_FILE" 2>/dev/null || true
fi

echo "Updating Device Manager status/time columns..."
if grep -q "<th>Status</th>" "$CGI_FILE" && ! grep -q "<th>Session Time</th>" "$CGI_FILE"; then
    awk '
    /echo "<table><tr><th>Hostname<\/th><th>IP<\/th><th>MAC<\/th><th>Token<\/th><th>Status<\/th><th>Notes<\/th><th>Actions<\/th><\/tr>"/ {
        print "        echo \"<table><tr><th>Hostname</th><th>IP</th><th>MAC</th><th>Token</th><th>Online</th><th>Session Time</th><th>Notes</th><th>Actions</th></tr>\""
        next
    }
    { print }
    ' "$CGI_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CGI_FILE"
    chmod +x "$CGI_FILE"
    echo "✅ Columns updated"
else
    echo "✅ Columns already updated"
fi

echo "Updating Device Manager session timer logic..."
if grep -q "# Use current IP if device is connected" "$CGI_FILE" && ! grep -q "SESSION_TEXT=" "$CGI_FILE"; then
    sed -i '/# Use current IP if device is connected/ i\
            ONLINE_STATUS="Offline"\
            ONLINE_COLOR="#6b7280"\
            if [ "$IS_CONNECTED" = "1" ]; then\
                ONLINE_STATUS="Online"\
                ONLINE_COLOR="#22c55e"\
            fi\
            SESSION_SECS=0\
            SESSION_PAUSED=0\
            if [ "$PAUSED_TS" -gt 0 ]; then\
                SESSION_SECS="$PAUSED_TS"\
                SESSION_PAUSED=1\
            elif [ "$END_TS" -gt "$NOW" ]; then\
                SESSION_SECS=$((END_TS - NOW))\
            fi\
            SH=$((SESSION_SECS / 3600))\
            SM=$(((SESSION_SECS % 3600) / 60))\
            SS=$((SESSION_SECS % 60))\
            SESSION_TEXT=$(printf "%02d:%02d:%02d" "$SH" "$SM" "$SS")\
' "$CGI_FILE"
    echo "✅ Session variables added"
else
    echo "✅ Session variables already exist"
fi

echo "Adding Session Token display to Device Manager..."
if grep -q "<th>MAC</th><th>Online</th>" "$CGI_FILE" && ! grep -q "<th>Token</th>" "$CGI_FILE"; then
    sed -i 's/<th>MAC<\/th><th>Online<\/th>/<th>MAC<\/th><th>Token<\/th><th>Online<\/th>/' "$CGI_FILE"
fi
if grep -q 'EM=$(esc "$MAC_UP")' "$CGI_FILE" && ! grep -q 'ETOKEN=' "$CGI_FILE"; then
    sed -i '/EM=$(esc "\$MAC_UP")/a\
            TOKEN=$(sqlite3 "$DB_FILE" "SELECT session_token FROM users WHERE mac='\''$MAC_UP'\'' LIMIT 1;" 2>/dev/null)\
            [ -z "$TOKEN" ] && TOKEN="None"\
            ETOKEN=$(esc "$TOKEN")\
' "$CGI_FILE"
fi
if grep -q "session-timer" "$CGI_FILE" && grep -q "ONLINE_STATUS" "$CGI_FILE" && ! grep -q "\\$ETOKEN" "$CGI_FILE"; then
    sed -i 's|<td>\$EM</td><td><span style='\''color:\$ONLINE_COLOR; font-weight:600;'\''>\$ONLINE_STATUS</span>|<td>\$EM</td><td style='\''font-size:11px; color:#64748b;'\''>\$ETOKEN</td><td><span style='\''color:\$ONLINE_COLOR; font-weight:600;'\''>\$ONLINE_STATUS</span>|' "$CGI_FILE"
fi
echo "✅ Token column updated"

if grep -q "STATUS_COLOR" "$CGI_FILE" && grep -q "font-weight:600" "$CGI_FILE" && ! grep -q "session-timer" "$CGI_FILE"; then
    sed -i '/STATUS_COLOR; font-weight:600.*\$STATUS<\/span><\/td><td>\$EN<\/td><td>"/c\            echo "<tr><td>$EH</td><td>$EIP</td><td>$EM</td><td style='\''font-size:11px; color:#64748b;'\''>$ETOKEN</td><td><span style='\''color:$ONLINE_COLOR; font-weight:600;'\''>$ONLINE_STATUS</span></td><td><span class='\''session-timer'\'' data-remaining='\''$SESSION_SECS'\'' data-paused='\''$SESSION_PAUSED'\'' style='\''font-weight:600;'\''>$SESSION_TEXT</span></td><td>$EN</td><td>"' "$CGI_FILE"
    echo "✅ Row output updated"
else
    echo "✅ Row output already updated"
fi

echo "Adding Session Time animation..."
if ! grep -q "session-timer" "$CGI_FILE" || ! grep -q "setInterval" "$CGI_FILE" || ! grep -q "data-remaining" "$CGI_FILE"; then
    if grep -q "setInterval(t,1000)" "$CGI_FILE" 2>/dev/null; then
        echo "✅ Session Time animation already exists"
    else
        sed -i '/elif \[ "\$TAB" = "sales" \]; then/i\
        echo "<script>"\
        echo "(function(){function f(s){s=Math.max(0,parseInt(s||0,10));var h=Math.floor(s/3600),m=Math.floor((s%3600)/60),ss=s%60;var hh=(h<10?\"0\":\"\")+h,mm=(m<10?\"0\":\"\")+m,sc=(ss<10?\"0\":\"\")+ss;return hh+\":\"+mm+\":\"+sc;}function t(){var els=document.querySelectorAll(\".session-timer\");for(var i=0;i<els.length;i++){var el=els[i];var p=(el.getAttribute(\"data-paused\")===\"1\");var r=parseInt(el.getAttribute(\"data-remaining\")||\"0\",10);if(!p&&r>0){r=r-1;el.setAttribute(\"data-remaining\",String(r));}el.textContent=f(r);}}t();setInterval(t,1000);})();"\
        echo "</script>"\
' "$CGI_FILE"
        echo "✅ Session Time animation added"
    fi
fi

echo "Adding auto sync JavaScript..."
if grep -q "auto-sync-select" "$CGI_FILE" && ! grep -q "action=sync_set_interval&minutes=" "$CGI_FILE"; then
    sed -i '/elif \[ "\$TAB" = "sales" \]; then/i\
        echo "<script>"\
        echo "(function(){function post(b){return fetch(\"/cgi-bin/admin\",{method:\"POST\",headers:{\"Content-Type\":\"application/x-www-form-urlencoded\"},body:b});}var sel=document.getElementById(\"auto-sync-select\");var save=document.getElementById(\"auto-sync-save\");if(!sel||!save){return;}post(\"action=sync_get_interval\").then(function(r){return r.json();}).then(function(d){if(d&&d.minutes!==undefined){sel.value=String(d.minutes);}}).catch(function(){});save.addEventListener(\"click\",function(){var m=sel.value;save.disabled=true;post(\"action=sync_set_interval&minutes=\"+encodeURIComponent(m)).then(function(r){return r.json();}).then(function(d){alert(((d.status===\"success\")?\"✅ \":\"❌ \")+(d.message||(\"Auto Sync set to \"+m+\" minutes\")));}).catch(function(e){alert(\"❌ Auto Sync failed: \"+e);}).then(function(){save.disabled=false;});});})();"\
        echo "</script>"\
' "$CGI_FILE"
    echo "✅ Auto Sync JavaScript added"
else
    echo "✅ Auto Sync JavaScript already exists"
fi

echo "Configuring auto sync schedule..."
UCI_BIN_LOCAL="$(command -v uci 2>/dev/null || echo /sbin/uci)"
CUR_AUTO_MIN="$($UCI_BIN_LOCAL -q get pisowifi.license.auto_sync_minutes 2>/dev/null)"
AUTO_MIN="$CUR_AUTO_MIN"
[ -z "$AUTO_MIN" ] && AUTO_MIN="30"
if [ "$AUTO_MIN" = "60" ]; then
    AUTO_MIN="30"
fi
case "$AUTO_MIN" in
    ''|*[!0-9]*) AUTO_MIN="30" ;;
esac
if [ -z "$CUR_AUTO_MIN" ] || [ "$CUR_AUTO_MIN" = "60" ]; then
    $UCI_BIN_LOCAL set pisowifi.license.auto_sync_minutes="$AUTO_MIN" 2>/dev/null || true
    $UCI_BIN_LOCAL commit pisowifi 2>/dev/null || true
fi
CRON_EXPR=""
if [ "$AUTO_MIN" = "0" ]; then
    CRON_EXPR=""
else
    case "$AUTO_MIN" in
        15) CRON_EXPR="*/15 * * * *" ;;
        30) CRON_EXPR="*/30 * * * *" ;;
        60) CRON_EXPR="0 * * * *" ;;
        120) CRON_EXPR="0 */2 * * *" ;;
        360) CRON_EXPR="0 */6 * * *" ;;
        720) CRON_EXPR="0 */12 * * *" ;;
        1440) CRON_EXPR="0 0 * * *" ;;
        *) CRON_EXPR="0 * * * *" ;;
    esac
fi
[ -d /etc/crontabs ] || mkdir -p /etc/crontabs
CRON_FILE="/etc/crontabs/root"
TMP_CRON="/tmp/pisowifi_cron_root_fix_$$"
if [ -f "$CRON_FILE" ]; then
    grep -v "pisowifi_auto_sync" "$CRON_FILE" > "$TMP_CRON" 2>/dev/null
else
    : > "$TMP_CRON" 2>/dev/null || true
fi
if [ "$AUTO_MIN" != "0" ]; then
    echo "$CRON_EXPR sh /usr/bin/wifi_devices_sync_auto.sh >/tmp/pisowifi_auto_sync.log 2>&1 # pisowifi_auto_sync" >> "$TMP_CRON"
fi
mv "$TMP_CRON" "$CRON_FILE" 2>/dev/null || true
chmod 600 "$CRON_FILE" 2>/dev/null || true
[ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1 || true
echo "✅ Auto Sync schedule configured ($AUTO_MIN minutes)"

echo "Fixing admin CGI exec format..."
if [ -f "$CGI_FILE" ]; then
    sed -i 's/\r$//' "$CGI_FILE" 2>/dev/null || true
    FIRST_LINE="$(head -n 1 "$CGI_FILE" 2>/dev/null | tr -d '\r')"
    if [ "$FIRST_LINE" != "#!/bin/sh" ]; then
        TMP_ADMIN="/tmp/admin_fix_exec_$$"
        echo '#!/bin/sh' > "$TMP_ADMIN"
        cat "$CGI_FILE" >> "$TMP_ADMIN"
        mv "$TMP_ADMIN" "$CGI_FILE"
        sed -i 's/\r$//' "$CGI_FILE" 2>/dev/null || true
    fi
    chmod +x "$CGI_FILE" 2>/dev/null || true
fi

echo ""
echo "=== FIX COMPLETE ==="
echo "✅ Sync functionality fixed!"
echo "✅ Centralized key detection improved!"
echo "✅ Sync All button and JavaScript added!"
echo ""
echo "You can now use the 'Sync All Devices' button in Device Manager."
echo "If you still have issues, check that your centralized key is properly stored in the database."
