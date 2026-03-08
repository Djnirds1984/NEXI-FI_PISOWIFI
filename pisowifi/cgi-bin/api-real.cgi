#!/bin/sh
echo "Content-Type: application/json"
echo ""

get_param() {
    echo "$QUERY_STRING" | sed -n "s/.*$1=\([^&]*\).*/\1/p"
}

ACTION=$(get_param "action")

case "$ACTION" in
    "get_hotspot_status")
        # Check dnsmasq
        SERV="stopped"
        pgrep dnsmasq >/dev/null && SERV="running"
        
        # Detect if ANY wireless interface is UP
        INT="down"
        # Checks br-lan (common for bridges) or any wlan interface
        for iface in br-lan wlan0 wlan1 eth0; do
            if [ -f "/sys/class/net/$iface/operstate" ]; then
                [ "$(cat /sys/class/net/$iface/operstate)" = "up" ] && INT="up" && break
            fi
        done

        # Get actual connected user count from DHCP leases
        USERS=$(grep -c "^" /var/lib/misc/dnsmasq.leases 2>/dev/null || echo 0)

        cat <<EOT
{
  "success": true,
  "status": {
    "service": "$SERV",
    "interface": "$INT",
    "users": $USERS,
    "signal": "N/A"
  }
}
EOT
        ;;

    "get_hotspot_settings")
        SSID=$(uci get wireless.@wifi-iface[0].ssid 2>/dev/null || echo "PisoWiFi_Free")
        cat <<EOT
{
  "success": true,
  "settings": {
    "enabled": "1",
    "ssid": "$SSID",
    "ip": "10.0.0.1"
  }
}
EOT
        ;;

    *)
        echo "{\"success\": false, \"error\": \"Invalid action\"}"
        ;;
esac
