#!/bin/sh

# PisoWiFi Configuration Script - Fixed Version 3
# This script sets up the PisoWiFi system on OpenWrt/LUCI with improved error handling

echo "Setting up PisoWiFi system..."

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Function to safely delete UCI sections
safe_delete_uci() {
    local config="$1"
    local section="$2"
    
    # Check if section exists before trying to delete
    if uci show "$config.$section" >/dev/null 2>&1; then
        uci -q delete "$config.$section" 2>/dev/null
        return 0
    else
        return 1
    fi
}

# Function to check if wireless interface exists
check_wireless_interface() {
    local iface_index="$1"
    
    # Check if wireless configuration exists and has the specified interface
    if uci show wireless 2>/dev/null | grep -q "wireless.@wifi-iface\[$iface_index\]"; then
        return 0
    else
        return 1
    fi
}

# Function to safely add firewall rules
safe_add_firewall_rule() {
    local rule_name="$1"
    local rule_type="$2"
    local rule_params="$3"
    
    # Check if rule already exists
    if uci show firewall 2>/dev/null | grep -q "firewall.*name='$rule_name'"; then
        echo "Firewall rule '$rule_name' already exists, skipping..."
        return 0
    fi
    
    # Add the rule
    uci add firewall "$rule_type"
    eval "$rule_params"
    echo "Added firewall rule: $rule_name"
    return 0
}

# Create UCI configuration
echo "Creating PisoWiFi configuration..."

# Delete existing configuration sections (with error suppression)
safe_delete_uci "pisowifi" "hotspot"
safe_delete_uci "pisowifi" "network" 
safe_delete_uci "pisowifi" "vouchers"

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

# Configure wireless interface with safety checks
echo "Configuring wireless interface..."
if uci show wireless 2>/dev/null | grep -q "wireless"; then
    # Check if we have at least one wifi-iface
    if check_wireless_interface 0; then
        echo "Configuring wireless interface 0..."
        uci set wireless.@wifi-iface[0].ssid='PisoWiFi_Free'
        uci set wireless.@wifi-iface[0].encryption='none'
        uci set wireless.@wifi-iface[0].mode='ap'
        uci commit wireless
    else
        echo "Warning: No wireless interface found at index 0. Please configure wireless manually."
        echo "Available wireless interfaces:"
        uci show wireless 2>/dev/null | grep "wifi-iface" || echo "No wifi-iface sections found"
    fi
else
    echo "Warning: No wireless configuration found. Please configure wireless manually."
fi

# Configure firewall
echo "Configuring firewall..."

# Check if nftables is available (OpenWrt 22.03+)
if command -v nft >/dev/null 2>&1; then
    echo "Using nftables (fw4) for firewall configuration..."
    
    # Add firewall rules with safety checks
    safe_add_firewall_rule "Allow-PisoWiFi-DNS" "rule" "uci set firewall.@rule[-1].src='lan'; uci set firewall.@rule[-1].proto='udp'; uci set firewall.@rule[-1].dest_port='53'; uci set firewall.@rule[-1].target='ACCEPT'"
    
    safe_add_firewall_rule "Allow-PisoWiFi-DHCP" "rule" "uci set firewall.@rule[-1].src='lan'; uci set firewall.@rule[-1].proto='udp'; uci set firewall.@rule[-1].src_port='68'; uci set firewall.@rule[-1].dest_port='67'; uci set firewall.@rule[-1].target='ACCEPT'"
    
    safe_add_firewall_rule "Allow-PisoWifi-Portal" "rule" "uci set firewall.@rule[-1].src='lan'; uci set firewall.@rule[-1].proto='tcp'; uci set firewall.@rule[-1].dest_port='80 443'; uci set firewall.@rule[-1].target='ACCEPT'"
    
    # Note: For traffic marking, we'll use a different approach
    safe_add_firewall_rule "Block-PisoWiFi-Internet" "rule" "uci set firewall.@rule[-1].src='lan'; uci set firewall.@rule[-1].proto='all'; uci set firewall.@rule[-1].dest='wan'; uci set firewall.@rule[-1].target='DROP'"
    
else
    echo "Using iptables for firewall configuration..."
    
    # Traditional iptables approach with safety checks
    if command -v iptables >/dev/null 2>&1; then
        # Check if rules already exist before adding
        if ! iptables -t nat -C PREROUTING -s 10.0.0.0/24 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1:80 2>/dev/null; then
            iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.1:80
        fi
        
        if ! iptables -t nat -C PREROUTING -s 10.0.0.0/24 -p tcp --dport 443 -j DNAT --to-destination 10.0.0.1:443 2>/dev/null; then
            iptables -t nat -A PREROUTING -s 10.0.0.0/24 -p tcp --dport 443 -j DNAT --to-destination 10.0.0.1:443
        fi

        # Mark authenticated users
        if ! iptables -t mangle -C PREROUTING -s 10.0.0.0/24 -m mark ! --mark 0x1/0x1 -j MARK --set-mark 0x1 2>/dev/null; then
            iptables -t mangle -A PREROUTING -s 10.0.0.0/24 -m mark ! --mark 0x1/0x1 -j MARK --set-mark 0x1
        fi
        
        echo "iptables rules configured successfully"
    else
        echo "Warning: Neither nftables nor iptables found. Firewall rules not configured."
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
if [ -d "./pisowifi" ]; then
    echo "Installing PisoWiFi web files from current directory..."
    cp -r ./pisowifi/* /www/pisowifi/
else
    echo "Warning: PisoWiFi files not found in current directory."
    echo "Please copy PisoWiFi files to /www/pisowifi/ manually."
fi

# Configure web server
echo "Configuring web server..."
uci set uhttpd.main.index_page='index.html'
uci commit uhttpd

# Create sample vouchers with safety checks
echo "Creating sample vouchers..."

# Safely delete existing vouchers first
safe_delete_uci "pisowifi" "voucher_1"
safe_delete_uci "pisowifi" "voucher_2"

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

# Restart services with error handling
echo "Restarting services..."
services_to_restart="network dnsmasq firewall uhttpd"

for service in $services_to_restart; do
    if [ -f "/etc/init.d/$service" ]; then
        echo "Restarting $service..."
        /etc/init.d/$service restart
        if [ $? -eq 0 ]; then
            echo "$service restarted successfully"
        else
            echo "Warning: Failed to restart $service"
        fi
    else
        echo "Warning: Service $service not found"
    fi
done

# Reload WiFi configuration
if command -v wifi >/dev/null 2>&1; then
    echo "Reloading WiFi configuration..."
    wifi reload
fi

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
echo "Setup completed with improved error handling. Check the logs above for any warnings."