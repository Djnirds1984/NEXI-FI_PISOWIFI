#!/bin/sh
# PisoWiFi Installation Script
# This script sets up the PisoWiFi system on OpenWrt/LuCI

echo "Installing PisoWiFi Management System..."

# Create necessary directories
mkdir -p /etc/pisowifi
mkdir -p /usr/lib/lua/luci/model/pisowifi
mkdir -p /usr/lib/lua/luci/controller/pisowifi
mkdir -p /www/luci-static/resources/view/pisowifi

# Set proper permissions
chmod 755 /cgi-bin/pisowifi-portal
chmod 644 /etc/config/pisowifi*

# Create log files
touch /var/log/pisowifi.log
touch /var/log/pisowifi_revenue.log
chmod 644 /var/log/pisowifi*

# Create voucher database file
echo '{}' > /etc/pisowifi/vouchers.json
chmod 644 /etc/pisowifi/vouchers.json

# Create session tracking file
echo '[]' > /tmp/pisowifi_sessions.json
chmod 666 /tmp/pisowifi_sessions.json

# Add firewall rules for PisoWiFi
uci add firewall rule
uci set firewall.@rule[-1].name='PisoWiFi-HTTP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='80'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='PisoWiFi-HTTPS'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='443'
uci set firewall.@rule[-1].target='ACCEPT'

# Add custom chains for PisoWiFi
uci add firewall rule
uci set firewall.@rule[-1].name='PisoWiFi-Auth-Chain'
uci set firewall.@rule[-1].src='*'
uci set firewall.@rule[-1].extra='-j pisowifi_auth'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='PisoWiFi-Block-Chain'
uci set firewall.@rule[-1].src='*'
uci set firewall.@rule[-1].extra='-j pisowifi_block'
uci set firewall.@rule[-1].target='DROP'

# Commit firewall changes
uci commit firewall

# Restart services
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart

echo "PisoWiFi installation completed!"
echo "Access the management interface at: http://your-router-ip/cgi-bin/luci/admin/pisowifi"
echo "Default admin credentials: admin/admin"
echo ""
echo "Important: Please change the default admin password immediately!"
echo "Configure your WiFi settings and enable the captive portal in the PisoWiFi menu."