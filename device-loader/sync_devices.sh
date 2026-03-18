#!/bin/sh
# Lightweight Ruijie Device Sync Script
# Runs purely in RAM (/tmp), sends active DHCP leases to Supabase

# Configuration
SUPABASE_URL="https://fuiabtdflbodglfexvln.supabase.co"
URL="$SUPABASE_URL/rest/v1/wifi_devices"
KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo"

# Auto-detect MACHINE_ID if not set
MACHINE_ID="${MACHINE_ID:-$(cat /etc/machine-id 2>/dev/null || echo "machine_$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)")}"

# Parse DHCP leases and send to Supabase
while read -r expires mac ip name clid; do
    # Skip empty mac or generic placeholders
    [ -z "$mac" ] && continue
    [ "$mac" = "*" ] && continue

    # Ensure device_name has a fallback if empty
    [ -z "$name" ] && name="Unknown Device"
    [ "$name" = "*" ] && name="Unknown Device"

    # Send upsert request to Supabase
    curl -sS -X POST "$URL" \
        -H "apikey: $KEY" \
        -H "Authorization: Bearer $KEY" \
        -H "Content-Type: application/json" \
        -H "Prefer: resolution=merge-duplicates" \
        -d "{
            \"machine_id\": \"$MACHINE_ID\",
            \"mac_address\": \"$mac\",
            \"device_name\": \"$name\",
            \"ip_address\": \"$ip\",
            \"is_connected\": true,
            \"last_seen\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }" >/dev/null 2>&1

done < /tmp/dhcp.leases
