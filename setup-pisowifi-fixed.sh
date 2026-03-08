#!/bin/sh

# PisoWiFi Configuration Script - Fixed Version
# This script sets up the PisoWiFi system on OpenWrt/LUCI

echo "Setting up PisoWiFi system..."

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Create UCI configuration
echo "Creating PisoWiFi configuration..."

# Create main configuration section
uci set pisowifi.hotspot=hotspot
uci set pisowifi.hotspot.enabled='1'
uci set pisowifi.hotspot.ssid='PisoWiFi_Free'
uci set pisowifi.hotspot.ip='10.0.0.1'
uci set pisowifi.hotspot.password=''
uci set pisowifi.hotspot.max_users='50'
uci set pisowifi.hotspot.session_timeout='60'
uci set pisowifi.hotspot.bandwidth_limit='2'
uci set pisowifi.hotspot.captive_portal='1'

# Create network configuration section
uci set pisowifi.network=network
uci set pisowifi.network.interface='wlan0'
uci set pisowifi.network.channel='auto'
uci set pisowifi.network.tx_power='80'
uci set pisowifi.network.dhcp_start='10.0.0.10'
uci set pisowifi.network.dhcp_end='10.0.0.250'

# Create vouchers section
uci set pisowifi.vouchers=vouchers

# Commit the configuration
uci commit pisowifi

# Configure network interface
echo "Configuring network interface..."
uci set network.lan.ipaddr='10.0.0.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

# Configure DHCP
echo "Configuring DHCP..."
uci set dhcp.lan.start='10'
uci set dhcp.lan.limit='240'
uci set dhcp.lan.leasetime='1h'
uci commit dhcp

# Configure wireless interface
echo "Configuring wireless interface..."
uci set wireless.@wifi-iface[0].ssid='PisoWiFi_Free'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].network='lan'
uci set wireless.@wifi-iface[0].encryption='none'
uci commit wireless

# Configure firewall
echo "Configuring firewall..."

# Check if nftables is available (OpenWrt 22.03+)
if command -v nft >/dev/null 2>&1; then
    echo "Using nftables (fw4) for firewall configuration..."
    
    # Add firewall rules using UCI for fw4
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-PisoWiFi-DNS'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].dest_port='53'
    uci set firewall.@rule[-1].target='ACCEPT'

    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-PisoWiFi-DHCP'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].src_port='68'
    uci set firewall.@rule[-1].dest_port='67'
    uci set firewall.@rule[-1].target='ACCEPT'

    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-PisoWifi-Portal'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].dest_port='80 443'
    uci set firewall.@rule[-1].target='ACCEPT'

    # Note: For traffic marking, we'll use a different approach
    uci add firewall rule
    uci set firewall.@rule[-1].name='Block-PisoWiFi-Internet'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].proto='all'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].target='DROP'
    
else
    echo "Using iptables for firewall configuration..."
    
    # Traditional iptables approach
    if command -v iptables >/dev/null 2>&1; then
        # Redirect HTTP traffic to captive portal
        iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1:80
        iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp --dport 443 -j DNAT --to-destination 10.0.0.1:443

        # Mark authenticated users
        iptables -t mangle -A PREROUTING -s 10.0.0.0/24 -m mark ! --mark 0x1/0x1 -j MARK --set-mark 0x1
        
        # Save iptables rules
        /etc/init.d/firewall restart
    fi
fi

uci commit firewall

# Create web directory structure
echo "Creating web directories..."
mkdir -p /www/pisowifi
mkdir -p /www/pisowifi/static/css
mkdir -p /www/pisowifi/static/js
mkdir -p /www/pisowifi/static/images
mkdir -p /www/pisowifi/cgi-bin

# Check if PisoWiFi files exist in current directory
if [ -d "/tmp/pisowifi" ]; then
    echo "Installing PisoWiFi web files from /tmp/pisowifi..."
    cp -r /tmp/pisowifi/* /www/pisowifi/
elif [ -d "./pisowifi" ]; then
    echo "Installing PisoWiFi web files from current directory..."
    cp -r ./pisowifi/* /www/pisowifi/
else
    echo "Warning: PisoWiFi web files not found. Please copy them manually to /www/pisowifi/"
fi

# Make CGI scripts executable if they exist
if [ -d "/www/pisowifi/cgi-bin" ]; then
    chmod +x /www/pisowifi/cgi-bin/*.cgi 2>/dev/null || true
fi

# Configure uHTTPd
echo "Configuring web server..."
uci set uhttpd.main.listen_http='0.0.0.0:80'
uci set uhttpd.main.listen_https='0.0.0.0:443'
uci set uhttpd.main.home='/www'
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci set uhttpd.main.script_timeout='60'
uci set uhttpd.main.network_timeout='30'
uci set uhttpd.main.index_page='index.html'

# Add PisoWiFi configuration
uci set uhttpd.pisowifi=uhttpd
uci set uhttpd.pisowifi.listen_http='10.0.0.1:80'
uci set uhttpd.pisowifi.listen_https='10.0.0.1:443'
uci set uhttpd.pisowifi.home='/www/pisowifi'
uci set uhttpd.pisowifi.cgi_prefix='/cgi-bin'
uci set uhttpd.pisowifi.script_timeout='60'
uci set uhttpd.pisowifi.network_timeout='30'
uci set uhttpd.pisowifi.index_page='index.html'

uci commit uhttpd

# Create sample vouchers using a simpler approach
echo "Creating sample vouchers..."
cat > /tmp/create_vouchers.sh << 'EOF'
#!/bin/sh
# Create sample vouchers

# Create voucher 1
uci set pisowifi.voucher_1=voucher
uci set pisowifi.voucher_1.code="PISO2024001"
uci set pisowifi.voucher_1.duration="60"
uci set pisowifi.voucher_1.price="10.00"
uci set pisowifi.voucher_1.status="active"
uci set pisowifi.voucher_1.created="2024-01-15T10:00:00Z"
uci set pisowifi.voucher_1.expiry="2024-02-15T23:59:59Z"
uci set pisowifi.voucher_1.maxDevices="1"
uci set pisowifi.voucher_1.notes="Sample voucher"

# Create voucher 2
uci set pisowifi.voucher_2=voucher
uci set pisowifi.voucher_2.code="PISO2024002"
uci set pisowifi.voucher_2.duration="180"
uci set pisowifi.voucher_2.price="25.00"
uci set pisowifi.voucher_2.status="active"
uci set pisowifi.voucher_2.created="2024-01-14T15:30:00Z"
uci set pisowifi.voucher_2.expiry="2024-02-14T23:59:59Z"
uci set pisowifi.voucher_2.maxDevices="2"
uci set pisowifi.voucher_2.notes="Sample voucher"

uci commit pisowifi
EOF

chmod +x /tmp/create_vouchers.sh
/tmp/create_vouchers.sh
rm /tmp/create_vouchers.sh

# Restart services
echo "Restarting services..."
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
wifi reload

echo ""
echo "PisoWiFi setup completed!"
echo ""
echo "Access your PisoWiFi portal at:"
echo "  Admin: http://10.0.0.1/pisowifi/"
echo "  Captive Portal: http://10.0.0.1 (for connected clients)"
echo ""
echo "Default settings:"
echo "  SSID: PisoWiFi_Free"
echo "  IP: 10.0.0.1"
echo "  DHCP Range: 10.0.0.10 - 10.0.0.250"
echo ""
echo "Sample vouchers:"
echo "  PISO2024001 (60 minutes, ₱10)"
echo "  PISO2024002 (180 minutes, ₱25)"
echo ""
echo "LAN access is preserved - you can still access via SSH and web interface."
echo ""
echo "Note: If you encounter issues with the captive portal, check:"
echo "  1. Firewall rules are applied correctly"
echo "  2. Web files are copied to /www/pisowifi/"
echo "  3. CGI scripts have proper permissions"