#!/bin/sh
# OpenWrt PisoWiFi API - Shell version that actually works
# This replaces the broken ucode version

echo "Content-Type: application/json"
echo ""

# Get action from query string
ACTION=""
if [ -n "$QUERY_STRING" ]; then
    ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')
fi

case "$ACTION" in
    "get_hotspot_status")
        # Real hotspot status using available OpenWrt commands
        SERVICE_STATUS="unknown"
        INTERFACE_STATUS="unknown" 
        USERS_COUNT=0
        SIGNAL_STRENGTH="N/A"
        
        # Check dnsmasq service
        if /etc/init.d/dnsmasq status >/dev/null 2>&1; then
            SERVICE_STATUS="running"
        else
            SERVICE_STATUS="stopped"
        fi
        
        # Check wireless interface with fallback
        if [ -f /sys/class/net/wlan0/operstate ]; then
            INTERFACE_STATUS=$(cat /sys/class/net/wlan0/operstate)
        elif [ -f /sys/class/net/wlan1/operstate ]; then  
            INTERFACE_STATUS=$(cat /sys/class/net/wlan1/operstate)
        else
            INTERFACE_STATUS="down"
        fi
        
        echo "{"
        echo "  \"success\": true,"
        echo "  \"status\": {"
        echo "    \"service\": \"$SERVICE_STATUS\","
        echo "    \"interface\": \"$INTERFACE_STATUS\","
        echo "    \"users\": $USERS_COUNT,"
        echo "    \"signal\": \"$SIGNAL_STRENGTH\""
        echo "  }"
        echo "}"
        ;;
        
    "get_hotspot_settings")
        # Basic settings from UCI if available
        SSID="PisoWiFi_Free"
        IP="10.0.0.1"
        
        # Try to get real settings from UCI
        if command -v uci >/dev/null 2>&1; then
            UCI_SSID=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null)
            if [ -n "$UCI_SSID" ]; then
                SSID="$UCI_SSID"
            fi
        fi
        
        echo "{"
        echo "  \"success\": true,"
        echo "  \"settings\": {"
        echo "    \"enabled\": \"1\","
        echo "    \"ssid\": \"$SSID\","
        echo "    \"ip\": \"$IP\""
        echo "  }"
        echo "}"
        ;;
        
    *)
        echo "{"
        echo "  \"success\": false,"
        echo "  \"error\": \"Invalid action: $ACTION\""
        echo "}"
        ;;
esac