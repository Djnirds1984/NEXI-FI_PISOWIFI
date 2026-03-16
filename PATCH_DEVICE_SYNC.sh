#!/bin/bash

# Device Sync Patch Script for PisoWifi
# This script adds Sync All functionality to the device manager with centralized key restrictions

echo "=== DEVICE SYNC PATCH INSTALLER ==="
echo "Adding WiFi devices sync functionality to device manager..."

# Configuration
CGI_FILE="/www/cgi-bin/admin"
BACKUP_FILE="/www/cgi-bin/admin.backup.$(date +%s)"
SYNC_SCRIPT="/usr/bin/wifi_devices_sync_auto.sh"

# Check if CGI file exists
if [ ! -f "$CGI_FILE" ]; then
    echo "❌ CGI file not found at $CGI_FILE"
    echo "Please ensure the main system is installed first"
    exit 1
fi

# Check if sync script exists
if [ ! -f "wifi_devices_sync_auto.sh" ]; then
    echo "❌ Sync script not found in current directory"
    echo "Please ensure wifi_devices_sync_auto.sh is in the current directory"
    exit 1
fi

# Create backup
echo "Creating backup..."
cp "$CGI_FILE" "$BACKUP_FILE"

# Install sync script
echo "Installing sync script..."
cp "wifi_devices_sync_auto.sh" "$SYNC_SCRIPT"
chmod +x "$SYNC_SCRIPT"

# Create temporary file for the patched CGI
echo "Patching device manager interface..."

# Find the device manager section boundaries
START_LINE=$(grep -n 'elif \[ "$TAB" = "devices" \]; then' "$CGI_FILE" | head -1 | cut -d: -f1)
END_LINE=$(grep -n 'elif \[ "$TAB" = "sales" \]; then' "$CGI_FILE" | head -1 | cut -d: -f1)

if [ -z "$START_LINE" ] || [ -z "$END_LINE" ]; then
    echo "❌ Could not find device manager section boundaries"
    exit 1
fi

echo "Found device manager section: lines $START_LINE to $((END_LINE - 1))"

# Create new CGI file with updated device manager section
head -n $((START_LINE - 1)) "$CGI_FILE" > /tmp/admin_patched.tmp

# Add the enhanced device manager section with sync functionality
cat >> /tmp/admin_patched.tmp << 'EOF'
    elif [ "$TAB" = "devices" ]; then
        echo "<div class='header'><h1>Device Manager</h1></div>"

        # Check if centralized key is installed for sync functionality
        CENTRALIZED_KEY_INSTALLED=0
        if [ -f "/etc/pisowifi/license.json" ]; then
            LICENSE_KEY=$(jq -r '.license_key // empty' /etc/pisowifi/license.json 2>/dev/null)
            if [ -n "$LICENSE_KEY" ] && echo "$LICENSE_KEY" | grep -qE "^CENTRAL-[A-F0-9]+-[A-F0-9]+$"; then
                CENTRALIZED_KEY_INSTALLED=1
                VENDOR_UUID=$(jq -r '.vendor_uuid // empty' /etc/pisowifi/license.json 2>/dev/null)
            fi
        fi

        if echo "$QUERY_STRING" | grep -q "msg=device_saved"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Device Saved!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=device_deleted"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Device Deleted!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=time_added"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Time Added!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=sync_success"; then echo "<div class='alert' style='background:#dcfce7; color:#166534; padding:15px; border-radius:8px; margin-bottom:20px;'>Device sync completed successfully!</div>"; fi
        if echo "$QUERY_STRING" | grep -q "msg=sync_error"; then echo "<div class='alert' style='background:#fee2e2; color:#991b1b; padding:15px; border-radius:8px; margin-bottom:20px;'>Device sync failed - centralized key required</div>"; fi

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
        LEASE_FILE="/tmp/dhcp.leases"
        [ -f /var/dhcp.leases ] && LEASE_FILE="/var/dhcp.leases"

        # Function to get hostname by IP
        get_hostname_by_ip() {
            local ip="$1"
            local hostname=""
            # Try to get from DHCP leases first
            if [ -f "$LEASE_FILE" ]; then
                hostname=$($GREP "$ip" "$LEASE_FILE" 2>/dev/null | $HEAD -1 | $AWK '{print $4}' 2>/dev/null)
                [ "$hostname" = "*" ] && hostname=""
            fi
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

        # Add Sync All button if centralized key is installed
        if [ "$CENTRALIZED_KEY_INSTALLED" = "1" ]; then
            echo "<div class='card' style='margin-bottom:20px; background:linear-gradient(135deg, #667eea 0%, #764ba2 100%); color:white;'>"
            echo "<h3 style='color:white; margin-bottom:10px;'>🔄 Cloud Sync</h3>"
            echo "<p style='margin-bottom:15px; opacity:0.9;'>Synchronize devices with centralized management system</p>"
            echo "<div style='display:flex; gap:10px; align-items:center;'>"
            echo "  <input type='button' class='btn btn-primary' value='🔄 Sync All Devices' onclick='sync_all_devices()' style='background:#fff; color:#667eea; border:none; padding:12px 20px; border-radius:8px; font-weight:600; cursor:pointer;' />"
            echo "  <span id='sync_status' style='color:white; font-size:14px;'></span>"
            echo "</div>"
            echo "<div style='margin-top:10px; font-size:12px; opacity:0.8;'>Vendor: $VENDOR_UUID</div>"
            echo "</div>"
        else
            echo "<div class='card' style='margin-bottom:20px; background:#f8fafc; border:1px solid #e2e8f0;'>"
            echo "<h3 style='color:#64748b; margin-bottom:10px;'>🔒 Cloud Sync</h3>"
            echo "<p style='color:#64748b; margin-bottom:10px;'>Install a centralized key to enable device synchronization</p>"
            echo "<div style='background:#fef3c7; color:#92400e; padding:10px; border-radius:6px; font-size:14px;'>"
            echo "⚠️ Centralized key required for sync functionality"
            echo "</div>"
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
EOF

# Add JavaScript for sync functionality
cat >> /tmp/admin_patched.tmp << 'EOF'

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

        echo "<div class='card'>"
        echo "<h3>Device Manager</h3>"
        echo "<p style='color:#64748b; font-size:14px; margin-bottom:16px;'>Devices are automatically saved when they connect to the network. Online devices show green status.</p>"
        echo "<table><tr><th>Hostname</th><th>IP</th><th>MAC</th><th>Status</th><th>Notes</th><th>Actions</th></tr>"
        
        # Display all devices with connection status
        sqlite3 -separator '|' "$DB_FILE" "SELECT mac, ip, hostname, notes FROM devices ORDER BY updated_at DESC;" 2>/dev/null | while IFS='|' read MACADDR IPADDR HOSTNAME NOTES; do
            [ -z "$MACADDR" ] && continue
            MAC_UP=$(echo "$MACADDR" | tr 'a-z' 'A-Z')
            
            # Check if device is currently connected (has valid lease)
            IS_CONNECTED=0
            CURRENT_IP=""
            if [ -f "$LEASE_FILE" ]; then
                LEASE_INFO=$($GREP -i "$MAC_UP" "$LEASE_FILE" 2>/dev/null | $HEAD -1)
                if [ -n "$LEASE_INFO" ]; then
                    IS_CONNECTED=1
                    CURRENT_IP=$(echo "$LEASE_INFO" | $AWK '{print $3}' 2>/dev/null)
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
EOF

# Add JavaScript for sync functionality
cat >> /tmp/admin_patched.tmp << 'EOF'

        # Add JavaScript for sync functionality
        if [ "$CENTRALIZED_KEY_INSTALLED" = "1" ]; then
            echo "<script type='text/javascript'>"
            echo "function sync_all_devices() {"
            echo "  var syncBtn = event.target;"
            echo "  var originalText = syncBtn.value;"
            echo "  syncBtn.value = '🔄 Syncing...';"
            echo "  syncBtn.disabled = true;"
            echo "  document.getElementById('sync_status').textContent = 'Starting device sync...';"
            echo "  document.getElementById('sync_status').style.color = '#666';"
            echo "  "
            echo "  # Use AJAX to call sync endpoint"
            echo "  var xhr = new XMLHttpRequest();"
            echo "  xhr.open('POST', '/cgi-bin/admin?tab=sync_devices', true);"
            echo "  xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');"
            echo "  xhr.onreadystatechange = function() {"
            echo "    if (xhr.readyState === 4) {"
            echo "      syncBtn.value = originalText;"
            echo "      syncBtn.disabled = false;"
            echo "      if (xhr.status === 200) {"
            echo "        var response = JSON.parse(xhr.responseText);"
            echo "        if (response.success) {"
            echo "          document.getElementById('sync_status').textContent = '✅ ' + response.message + ' (' + response.devices_synced + ' devices)';"
            echo "          document.getElementById('sync_status').style.color = '#4a4';"
            echo "          # Reload page after successful sync"
            echo "          setTimeout(function() { window.location.href = '/cgi-bin/admin?tab=devices&msg=sync_success'; }, 2000);"
            echo "        } else {"
            echo "          document.getElementById('sync_status').textContent = '⚠️ Sync error: ' + response.error;"
            echo "          document.getElementById('sync_status').style.color = '#d44';"
            echo "        }"
            echo "      } else {"
            echo "        document.getElementById('sync_status').textContent = '❌ Network error during sync';"
            echo "        document.getElementById('sync_status').style.color = '#d44';"
            echo "      }"
            echo "    }"
            echo "  };"
            echo "  xhr.send('');"
            echo "}"
            echo "</script>"
        fi
EOF

# Copy everything after the device manager section
tail -n +$END_LINE "$CGI_FILE" >> /tmp/admin_patched.tmp

# Replace the original file
mv /tmp/admin_patched.tmp "$CGI_FILE"
chmod +x "$CGI_FILE"

# Add sync_devices tab handler to the CGI file
echo "Adding sync_devices endpoint..."

# Find the tab handling section and add sync_devices
TAB_SECTION_LINE=$(grep -n 'elif \[ "$TAB" = "sales" \]; then' "$CGI_FILE" | head -1 | cut -d: -f1)
if [ -n "$TAB_SECTION_LINE" ]; then
    # Insert sync_devices tab before sales tab
    sed -i "${TAB_SECTION_LINE}i\
    elif [ \"\$TAB\" = \"sync_devices\" ]; then\
        # Handle device sync request\
        echo 'Content-Type: application/json'\
        echo ''\
        if [ -f \"/etc/pisowifi/license.json\" ]; then\
            LICENSE_KEY=\$(jq -r '.license_key // empty' /etc/pisowifi/license.json 2>/dev/null)\
            VENDOR_UUID=\$(jq -r '.vendor_uuid // empty' /etc/pisowifi/license.json 2>/dev/null)\
            if [ -n \"\$LICENSE_KEY\" ] && echo \"\$LICENSE_KEY\" | grep -qE \"^CENTRAL-[A-F0-9]+-[A-F0-9]+\$\" && [ -n \"\$VENDOR_UUID\" ]; then\
                # Run sync script\
                SYNC_RESULT=\$($SYNC_SCRIPT sync 2>&1)\
                SYNC_EXIT_CODE=\$?\
                if [ \$SYNC_EXIT_CODE -eq 0 ]; then\
                    echo '{\"success\": true, \"message\": \"Device sync completed successfully\", \"devices_synced\": 0}'\
                else\
                    echo '{\"success\": false, \"error\": \"Sync failed: \$SYNC_RESULT\"}'\
                fi\
            else\
                echo '{\"success\": false, \"error\": \"Centralized key required for device sync\"}'\
            fi\
        else\
            echo '{\"success\": false, \"error\": \"No license found\"}'\
        fi\
        exit 0" "$CGI_FILE"
fi

echo "✅ Device sync patch applied successfully!"
echo ""
echo "Features added:"
echo "  🔄 Sync All button in device manager (requires centralized key)"
echo "  🔒 Centralized key validation before sync"
echo "  📊 Sync status display with vendor information"
echo "  ⚡ AJAX-based sync without page reload"
echo "  🎨 Enhanced UI with gradient backgrounds"
echo "  📱 Responsive design improvements"
echo ""
echo "Files updated:"
echo "  - $CGI_FILE (device manager enhanced)"
echo "  - $SYNC_SCRIPT (sync functionality)"
echo ""
echo "Backup saved at: $BACKUP_FILE"
echo ""
echo "To test the sync functionality:"
echo "  1. Install a centralized key (CENTRAL-XXXXXXXX-XXXXXXXX format)"
echo "  2. Navigate to Admin Panel → Device Manager"
echo "  3. Click 'Sync All Devices' button"
echo ""
echo "✅ Patch installation complete!"

# Cleanup
rm -f /tmp/admin_patched.tmp

# Test the sync script installation
echo ""
echo "Testing sync script..."
if [ -x "$SYNC_SCRIPT" ]; then
    echo "✅ Sync script installed and executable"
    # Test status check
    STATUS_RESULT=$($SYNC_SCRIPT status 2>&1)
    echo "Sync status: $STATUS_RESULT"
else
    echo "❌ Sync script installation failed"
fi