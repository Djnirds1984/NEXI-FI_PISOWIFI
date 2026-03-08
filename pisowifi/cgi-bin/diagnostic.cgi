#!/bin/sh
# Critical diagnostic script - tests CGI execution
# This will help identify exactly why you're getting 502

echo "Content-type: application/json"
echo ""

# Test 1: Check if script is executing
echo "{"
echo "  \"success\": true,"
echo "  \"diagnostic\": {"
echo "    \"script_executed\": true,"
echo "    \"timestamp\": \"$(date)\","
echo "    \"working_directory\": \"$(pwd)\","
echo "    \"script_path\": \"$0\","
echo "    \"query_string\": \"$QUERY_STRING\","
echo "    \"request_method\": \"$REQUEST_METHOD\","
echo "    \"server_software\": \"$SERVER_SOFTWARE\""
echo "  },"
echo "  \"system_checks\": {"

# Test 2: Check if dnsmasq exists
if command -v dnsmasq >/dev/null 2>&1; then
    echo "    \"dnsmasq_available\": true,"
else
    echo "    \"dnsmasq_available\": false,"
fi

# Test 3: Check if uci exists  
if command -v uci >/dev/null 2>&1; then
    echo "    \"uci_available\": true,"
else
    echo "    \"uci_available\": false,"
fi

# Test 4: Check network interfaces
echo "    \"network_interfaces\": ["
for iface in wlan0 wlan1 eth0; do
    if [ -d "/sys/class/net/$iface" ]; then
        STATE=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
        echo "      {\"name\": \"$iface\", \"state\": \"$STATE\"},"
    fi
done
echo "    ]"
echo "  },"
echo "  \"message\": \"CGI diagnostic complete\""
echo "}"