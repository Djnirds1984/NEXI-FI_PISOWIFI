#!/bin/sh

# Backup existing configs
cp /etc/config/network /etc/config/network.bak
cp /etc/config/wireless /etc/config/wireless.bak

echo "Configuring LAN..."
# Set LAN IP to 10.0.0.1
uci set network.lan.ipaddr='10.0.0.1'
uci commit network

echo "Configuring Wireless..."
# Enable wifi device (radio0)
uci set wireless.radio0.disabled='0'

# Configure the default wifi interface
# We try to find the first interface on radio0, usually default_radio0
# If not found, we create a new one, but let's assume default exists or modify the first one found.

# Delete existing wifi-iface to be clean or just modify? 
# Safer to modify the first iface attached to radio0 to avoid duplicates if run multiple times
# But UCI is tricky with anonymous sections.
# Let's try to set the first wifi-iface section found.

uci set wireless.@wifi-iface[0].device='radio0'
uci set wireless.@wifi-iface[0].network='lan'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].ssid='NEXI-FI PISOWIFI'
uci set wireless.@wifi-iface[0].encryption='none'

# Ensure it's not disabled
uci set wireless.@wifi-iface[0].disabled='0'

uci commit wireless

echo "Restarting Network and WiFi..."
/etc/init.d/network restart
/sbin/wifi reload

echo "Configuration updated!"
echo "1. LAN IP is now 10.0.0.1"
echo "2. WiFi SSID is 'NEXI-FI PISOWIFI'"
echo "3. WiFi is Open (No Password) for Captive Portal"
echo "Please reconnect to the new WiFi or LAN IP."
