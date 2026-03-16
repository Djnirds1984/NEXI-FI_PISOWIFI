#!/bin/bash

# WiFi Devices Sync System for PisoWifi
# This script handles bidirectional synchronization with Supabase wifi_devices table
# Automatically retrieves credentials from license system

# Configuration - Auto-detected from license system
LICENSE_FILE="/etc/pisowifi/license.json"
DB_FILE="/etc/pisowifi/pisowifi.db"
SYNC_LOG="/var/log/pisowifi_sync.log"
SUPABASE_URL="https://fuiabtdflbodglfexvln.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo"

# Create sync log if it doesn't exist
touch "$SYNC_LOG" 2>/dev/null || true

# Logging function
log_sync() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SYNC_LOG"
    logger -t pisowifi_sync "$1"
}

# Function to get license data from local JSON file
get_license_data() {
    if [ -f "$LICENSE_FILE" ]; then
        local license_data=$(cat "$LICENSE_FILE" 2>/dev/null)
        if [ -n "$license_data" ]; then
            echo "$license_data"
            return 0
        fi
    fi
    return 1
}

# Function to check if centralized key is installed
check_centralized_key() {
    local license_data=$(get_license_data)
    if [ $? -ne 0 ]; then
        log_sync "No license file found"
        return 1
    fi
    
    # Check if license key exists and is centralized format
    local license_key=$(echo "$license_data" | jq -r '.license_key // empty' 2>/dev/null)
    if [ -n "$license_key" ] && echo "$license_key" | grep -qE "^CENTRAL-[A-F0-9]+-[A-F0-9]+$"; then
        # Get vendor UUID from license
        local vendor_uuid=$(echo "$license_data" | jq -r '.vendor_uuid // empty' 2>/dev/null)
        if [ -n "$vendor_uuid" ]; then
            log_sync "Centralized key detected: $license_key, Vendor: $vendor_uuid"
            return 0
        fi
    fi
    
    log_sync "No centralized key installed or invalid format"
    return 1
}

# Function to get vendor UUID from license
get_vendor_uuid() {
    local license_data=$(get_license_data)
    if [ $? -eq 0 ]; then
        echo "$license_data" | jq -r '.vendor_uuid // empty' 2>/dev/null
    fi
}

# Function to get hardware ID from license
get_hardware_id() {
    local license_data=$(get_license_data)
    if [ $? -eq 0 ]; then
        echo "$license_data" | jq -r '.hardware_id // empty' 2>/dev/null
    fi
}

# HTTP request function
supabase_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    curl -s -X "$method" \
        -H "apikey: $SUPABASE_KEY" \
        -H "Authorization: Bearer $SUPABASE_KEY" \
        -H "Content-Type: application/json" \
        -H "Prefer: return=representation" \
        ${data:+-d "$data"} \
        "${SUPABASE_URL}/rest/v1/${endpoint}"
}

# Function to sync local devices to Supabase
sync_local_to_supabase() {
    log_sync "Starting local to Supabase sync..."
    
    local vendor_uuid=$(get_vendor_uuid)
    local hardware_id=$(get_hardware_id)
    
    if [ -z "$vendor_uuid" ] || [ -z "$hardware_id" ]; then
        log_sync "Missing vendor UUID or hardware ID from license"
        return 1
    fi
    
    local sync_count=0
    local error_count=0
    
    # Get all local devices that haven't been synced or need update
    sqlite3 "$DB_FILE" "SELECT mac, ip, hostname, notes, updated_at FROM devices WHERE notes != 'Synced' OR updated_at > (SELECT COALESCE(MAX(last_sync_attempt), 0) FROM sync_status WHERE direction='upload')" 2>/dev/null | while IFS='|' read MAC IP HOST NOTES UPDATED; do
        [ -z "$MAC" ] && continue
        
        # Prepare device data
        local device_data=$(jq -n \
            --arg mac "$MAC" \
            --arg ip "$IP" \
            --arg hostname "$HOST" \
            --arg vendor_id "$vendor_uuid" \
            --arg machine_id "$hardware_id" \
            --arg device_type "other" \
            --arg is_connected "true" \
            '{
                mac_address: $mac,
                ip_address: $ip,
                device_name: $hostname,
                vendor_id: $vendor_id,
                machine_id: $machine_id,
                device_type: $device_type,
                is_connected: $is_connected | test("true"),
                sync_status: "success",
                last_sync_attempt: now | todate
            }')
        
        # Check if device exists in Supabase
        local existing=$(supabase_request "GET" "wifi_devices?select=id&mac_address=eq.$MAC&machine_id=eq.$hardware_id&limit=1")
        
        if [ "$existing" = "[]" ] || [ -z "$existing" ]; then
            # Insert new device
            local response=$(supabase_request "POST" "wifi_devices" "$device_data")
            if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
                sqlite3 "$DB_FILE" "UPDATE devices SET notes='Synced' WHERE mac='$MAC'" 2>/dev/null
                sync_count=$((sync_count + 1))
                log_sync "✓ Synced new device: $MAC ($HOST)"
            else
                error_count=$((error_count + 1))
                log_sync "✗ Failed to sync device: $MAC - $response"
            fi
        else
            # Update existing device
            local device_id=$(echo "$existing" | jq -r '.[0].id')
            local response=$(supabase_request "PATCH" "wifi_devices?id=eq.$device_id" "$device_data")
            if [ "$response" != "null" ] && [ -n "$response" ]; then
                sqlite3 "$DB_FILE" "UPDATE devices SET notes='Synced' WHERE mac='$MAC'" 2>/dev/null
                sync_count=$((sync_count + 1))
                log_sync "✓ Updated synced device: $MAC ($HOST)"
            else
                error_count=$((error_count + 1))
                log_sync "✗ Failed to update device: $MAC - $response"
            fi
        fi
    done
    
    log_sync "Local to Supabase sync complete: $sync_count devices synced, $error_count errors"
    return $error_count
}

# Function to sync Supabase devices to local
sync_supabase_to_local() {
    log_sync "Starting Supabase to local sync..."
    
    local vendor_uuid=$(get_vendor_uuid)
    local hardware_id=$(get_hardware_id)
    
    if [ -z "$vendor_uuid" ] || [ -z "$hardware_id" ]; then
        log_sync "Missing vendor UUID or hardware ID from license"
        return 1
    fi
    
    local sync_count=0
    local error_count=0
    
    # Get devices from Supabase for this vendor and machine
    local devices=$(supabase_request "GET" "wifi_devices?select=*&vendor_id=eq.$vendor_uuid&machine_id=eq.$hardware_id")
    
    if [ "$devices" = "[]" ] || [ -z "$devices" ]; then
        log_sync "No devices found in Supabase for this vendor/machine"
        return 0
    fi
    
    echo "$devices" | jq -r '.[] | @tsv' 2>/dev/null | while IFS=$'\t' read -r id mac_address ip_address device_name device_type is_connected last_heartbeat; do
        [ -z "$mac_address" ] && continue
        
        # Check if device exists locally
        local exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM devices WHERE mac='$mac_address'" 2>/dev/null)
        
        if [ "$exists" = "0" ]; then
            # Insert new device
            sqlite3 "$DB_FILE" "INSERT INTO devices (mac, ip, hostname, notes, created_at, updated_at) VALUES ('$mac_address', '$ip_address', '$device_name', 'Synced from cloud', strftime('%s','now'), strftime('%s','now'))" 2>/dev/null
            if [ $? -eq 0 ]; then
                sync_count=$((sync_count + 1))
                log_sync "✓ Downloaded new device: $mac_address ($device_name)"
            else
                error_count=$((error_count + 1))
                log_sync "✗ Failed to download device: $mac_address"
            fi
        else
            # Update existing device
            sqlite3 "$DB_FILE" "UPDATE devices SET ip='$ip_address', hostname='$device_name', notes='Synced from cloud', updated_at=strftime('%s','now') WHERE mac='$mac_address'" 2>/dev/null
            if [ $? -eq 0 ]; then
                sync_count=$((sync_count + 1))
                log_sync "✓ Updated local device: $mac_address ($device_name)"
            else
                error_count=$((error_count + 1))
                log_sync "✗ Failed to update local device: $mac_address"
            fi
        fi
    done
    
    log_sync "Supabase to local sync complete: $sync_count devices synced, $error_count errors"
    return $error_count
}

# Function to perform bidirectional sync
sync_all_devices() {
    log_sync "=== Starting bidirectional device sync ==="
    
    # Check if centralized key is installed
    if ! check_centralized_key; then
        log_sync "❌ Device sync blocked: No centralized key installed"
        echo "ERROR: Device sync requires centralized key installation"
        return 1
    fi
    
    # Sync local to Supabase first
    sync_local_to_supabase
    local upload_errors=$?
    
    # Then sync Supabase to local
    sync_supabase_to_local
    local download_errors=$?
    
    # Update sync status
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO sync_status (direction, last_sync_attempt, status) VALUES ('bidirectional', strftime('%s','now'), 'completed')" 2>/dev/null
    
    local total_errors=$((upload_errors + download_errors))
    
    if [ $total_errors -eq 0 ]; then
        log_sync "✅ All devices synchronized successfully"
        echo "SUCCESS: Device sync completed successfully"
        return 0
    else
        log_sync "⚠️  Device sync completed with $total_errors errors"
        echo "PARTIAL: Device sync completed with some errors"
        return 1
    fi
}

# Function to get sync status
get_sync_status() {
    local last_sync=$(sqlite3 "$DB_FILE" "SELECT datetime(last_sync_attempt, 'unixepoch') FROM sync_status ORDER BY last_sync_attempt DESC LIMIT 1" 2>/dev/null)
    local device_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM devices" 2>/dev/null)
    local vendor_uuid=$(get_vendor_uuid)
    local hardware_id=$(get_hardware_id)
    local centralized_status="Not Installed"
    
    if check_centralized_key; then
        centralized_status="Installed"
    fi
    
    echo "Centralized Key: $centralized_status"
    echo "Last sync: ${last_sync:-Never}"
    echo "Local devices: $device_count"
    echo "Vendor UUID: ${vendor_uuid:-Not Available}"
    echo "Machine ID: ${hardware_id:-Not Available}"
}

# Main execution
case "${1:-sync}" in
    sync)
        sync_all_devices
        ;;
    upload)
        if check_centralized_key; then
            sync_local_to_supabase
        else
            log_sync "❌ Upload blocked: No centralized key installed"
            echo "ERROR: Upload requires centralized key installation"
            return 1
        fi
        ;;
    download)
        if check_centralized_key; then
            sync_supabase_to_local
        else
            log_sync "❌ Download blocked: No centralized key installed"
            echo "ERROR: Download requires centralized key installation"
            return 1
        fi
        ;;
    status)
        get_sync_status
        ;;
    check-key)
        if check_centralized_key; then
            echo "✅ Centralized key is installed"
            return 0
        else
            echo "❌ No centralized key installed"
            return 1
        fi
        ;;
    *)
        echo "Usage: $0 {sync|upload|download|status|check-key}"
        echo "  sync      - Bidirectional sync (requires centralized key)"
        echo "  upload    - Upload local devices to Supabase (requires centralized key)"
        echo "  download  - Download devices from Supabase (requires centralized key)"
        echo "  status    - Show sync status"
        echo "  check-key - Check if centralized key is installed"
        exit 1
        ;;
esac