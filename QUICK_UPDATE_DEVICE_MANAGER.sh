#!/bin/bash

# Quick Device Manager Update Script
# This script applies only the device manager changes without reinstalling everything

echo "=== QUICK DEVICE MANAGER UPDATE ==="
echo "Updating device manager functionality only..."

# Configuration
CGI_FILE="/www/cgi-bin/admin"
BACKUP_FILE="/www/cgi-bin/admin.backup.$(date +%s)"

# Check if CGI file exists
if [ ! -f "$CGI_FILE" ]; then
    echo "❌ CGI file not found at $CGI_FILE"
    echo "Please run the full installer first"
    exit 1
fi

# Create backup
echo "Creating backup..."
cp "$CGI_FILE" "$BACKUP_FILE"

# Extract the current CGI script and find the device manager section
echo "Extracting device manager section..."

# Find the line numbers for the device manager section
START_LINE=$(grep -n 'elif \[ "$TAB" = "devices" \]; then' "$CGI_FILE" | head -1 | cut -d: -f1)
END_LINE=$(grep -n 'elif \[ "$TAB" = "sales" \]; then' "$CGI_FILE" | head -1 | cut -d: -f1)

if [ -z "$START_LINE" ] || [ -z "$END_LINE" ]; then
    echo "❌ Could not find device manager section boundaries"
    exit 1
fi

echo "Found device manager section: lines $START_LINE to $((END_LINE - 1))"

# Create new CGI file with updated device manager section
echo "Creating updated CGI script..."

# Copy everything before the device manager section
head -n $((START_LINE - 1)) "$CGI_FILE" > /tmp/admin_new.tmp

# Add the updated device manager section
cat >> /tmp/admin_new.tmp << 'EOF'
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

# Copy everything after the device manager section
tail -n +$END_LINE "$CGI_FILE" >> /tmp/admin_new.tmp

# Replace the original file
mv /tmp/admin_new.tmp "$CGI_FILE"
chmod +x "$CGI_FILE"

echo "✅ Device manager updated successfully!"
echo ""
echo "Changes applied:"
echo "  - Removed redundant 'Connected Devices' section"
echo "  - Enhanced automatic device saving with counters"
echo "  - Added connection status detection (Online/Offline)"
echo "  - Implemented status color coding"
echo "  - Added auto-save summary notifications"
echo "  - Unified device management interface"
echo ""
echo "Backup saved at: $BACKUP_FILE"
echo "✅ Update complete!"

# Cleanup
rm -f /tmp/admin_new.tmp