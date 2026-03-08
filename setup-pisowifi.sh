#!/bin/sh

# PisoWiFi Configuration Script
# This script sets up the PisoWiFi system on OpenWrt/LUCI

echo "Setting up PisoWiFi system..."

# Create UCI configuration if it doesn't exist
if ! uci show pisowifi >/dev/null 2>&1; then
    echo "Creating PisoWiFi configuration..."
    
    # Create main configuration
    uci set pisowifi.hotspot=hotspot
    uci set pisowifi.hotspot.enabled='1'
    uci set pisowifi.hotspot.ssid='PisoWiFi_Free'
    uci set pisowifi.hotspot.ip='10.0.0.1'
    uci set pisowifi.hotspot.password=''
    uci set pisowifi.hotspot.max_users='50'
    uci set pisowifi.hotspot.session_timeout='60'
    uci set pisowifi.hotspot.bandwidth_limit='2'
    uci set pisowifi.hotspot.captive_portal='1'
    
    # Create network configuration
    uci set pisowifi.network=network
    uci set pisowifi.network.interface='wlan0'
    uci set pisowifi.network.channel='auto'
    uci set pisowifi.network.tx_power='80'
    uci set pisowifi.network.dhcp_start='10.0.0.10'
    uci set pisowifi.network.dhcp_end='10.0.0.250'
    
    # Create vouchers section
    uci set pisowifi.vouchers=vouchers
    
    uci commit pisowifi
fi

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

# Configure firewall to allow PisoWiFi traffic
echo "Configuring firewall..."
# Allow DNS
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-PisoWiFi-DNS'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].target='ACCEPT'

# Allow DHCP
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-PisoWiFi-DHCP'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].src_port='68'
uci set firewall.@rule[-1].dest_port='67'
uci set firewall.@rule[-1].target='ACCEPT'

# Allow HTTP/HTTPS to captive portal
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-PisoWifi-Portal'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='80 443'
uci set firewall.@rule[-1].target='ACCEPT'

# Block internet access for unauthenticated users
uci add firewall rule
uci set firewall.@rule[-1].name='Block-PisoWiFi-Internet'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='all'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].extra='-m mark ! --mark 0x1/0x1'
uci set firewall.@rule[-1].target='DROP'

uci commit firewall

# Create web directory structure
echo "Creating web directories..."
mkdir -p /www/pisowifi
mkdir -p /www/pisowifi/static/css
mkdir -p /www/pisowifi/static/js
mkdir -p /www/pisowifi/static/images
mkdir -p /www/pisowifi/cgi-bin

# Copy PisoWiFi files to web directory
echo "Installing PisoWiFi web files..."
if [ -d /tmp/pisowifi ]; then
    cp -r /tmp/pisowifi/* /www/pisowifi/
fi

# Make CGI scripts executable
chmod +x /www/pisowifi/cgi-bin/*.cgi

# Configure uHTTPd for PisoWiFi
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

# Create iptables rules for captive portal
echo "Setting up captive portal..."
# Redirect HTTP traffic to captive portal
iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1:80
iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp --dport 443 -j DNAT --to-destination 10.0.0.1:443

# Mark authenticated users
iptables -t mangle -A PREROUTING -s 10.0.0.0/24 -m mark ! --mark 0x1/0x1 -j MARK --set-mark 0x1

# Save iptables rules
/etc/init.d/firewall restart

# Create sample vouchers
echo "Creating sample vouchers..."
ucode -e '
    const config = {
        vouchers = {
            "1": {
                code: "PISO2024001",
                duration: 60,
                price: 10.00,
                status: "active",
                created: "2024-01-15T10:00:00Z",
                expiry: "2024-02-15T23:59:59Z",
                maxDevices: 1,
                notes: "Sample voucher"
            },
            "2": {
                code: "PISO2024002", 
                duration: 180,
                price: 25.00,
                status: "active",
                created: "2024-01-14T15:30:00Z",
                expiry: "2024-02-14T23:59:59Z",
                maxDevices: 2,
                notes: "Sample voucher"
            }
        }
    };
    
    const cursor = uci.cursor();
    cursor.load("pisowifi");
    
    for (let id, voucher in config.vouchers) {
        cursor.set("pisowifi", "voucher_" + id, null, "voucher");
        for (let key, value in voucher) {
            cursor.set("pisowifi", "voucher_" + id, key, value);
        }
    }
    
    cursor.commit("pisowifi");
'

# Restart services
echo "Restarting services..."
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
wifi reload

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