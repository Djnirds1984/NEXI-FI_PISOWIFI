#!/bin/sh
# PisoWiFi Installation Script
# This script sets up the PisoWiFi system on OpenWrt/LuCI

echo "Installing PisoWiFi Management System..."

# Create necessary directories
echo "Creating directories..."
mkdir -p /etc/pisowifi
mkdir -p /usr/lib/lua/luci/model/pisowifi
mkdir -p /usr/lib/lua/luci/controller/pisowifi
mkdir -p /www/luci-static/resources/view/pisowifi
mkdir -p /www/cgi-bin
mkdir -p /var/log

# Create default configuration files if they don't exist
echo "Creating default configuration files..."
if [ ! -f "/etc/config/pisowifi" ]; then
    cat > /etc/config/pisowifi << 'EOF'
config general 'general'
	option enabled '0'
	option portal_url 'http://192.168.1.1/cgi-bin/pisowifi-portal'
	option session_timeout '60'
	option price_per_hour '5'
	option currency 'PHP'
	option payment_methods 'coinslot,qr_code'
	option landing_title 'Welcome to PisoWiFi'
	option landing_message 'Please insert coin or pay to access the internet'
	option landing_background ''
	option landing_logo ''

config wifi_2g 'wifi_2g'
	option wifi_2g_enabled '1'
	option wifi_2g_ssid ''
	option wifi_2g_password_required '0'
	option wifi_2g_password ''

config wifi_5g 'wifi_5g'
	option wifi_5g_enabled '1'
	option wifi_5g_ssid ''
	option wifi_5g_password_required '0'
	option wifi_5g_password ''

config landing_page 'landing_page'
	option landing_title 'Welcome to PisoWiFi'
	option landing_message 'Please insert coin or pay to access the internet'
	option landing_background ''
	option landing_logo ''

config payment 'payment'
	option payment_method 'coinslot'
	option qr_code_image ''
	option gcash_number ''

config admin 'admin'
	option username 'admin'
	option password '$1$admin$1$'
	option enable_brute_force_protection '1'
	option max_login_attempts '5'
	option block_duration '30'
	option enable_session_timeout '1'
	option session_timeout '30'

config security 'security'
	option enable_brute_force_protection '1'
	option max_login_attempts '5'
	option block_duration '30'
	option enable_session_timeout '1'
	option session_timeout '30'
	option enable_2fa '0'
	option _2fa_secret ''

config access_control 'access_control'
	list allowed_ips ''
	list blocked_ips ''

config hotspot_segments 'segments'
	option enabled '1'
	option segment_name 'Default'
	option ssid_suffix ''
	option vlan_id ''
	option ip_range '192.168.1.100-192.168.1.200'
	option bandwidth_limit_down '0'
	option bandwidth_limit_up '0'
	option session_timeout '60'
	option price_per_hour '5'
	option auth_method 'voucher'
	option landing_page ''
	list allowed_domains 'google.com,facebook.com'
	option enable_logging '1'
	option enable_qos '1'
EOF
    chmod 644 /etc/config/pisowifi
fi

if [ ! -f "/etc/config/pisowifi_segments" ]; then
    cat > /etc/config/pisowifi_segments << 'EOF'
config segment 'default'
	option name 'Default Segment'
	option enabled '1'
	option vlan_id ''
	option ip_range '192.168.1.100-192.168.1.200'
	option bandwidth_down '0'
	option bandwidth_up '0'
	option session_timeout '60'
	option price_per_hour '5'
	option auth_method 'voucher'
	option landing_page ''
	option description 'Default PisoWiFi segment'
EOF
    chmod 644 /etc/config/pisowifi_segments
fi

# Create CGI portal script if it doesn't exist
echo "Creating CGI portal script..."
if [ ! -f "/www/cgi-bin/pisowifi-portal" ]; then
    cat > /www/cgi-bin/pisowifi-portal << 'EOF'
#!/usr/bin/env ucode
'use strict';

import { getenv, exit } from 'env';
import { stdin, stdout } from 'fs';
import { uci } from 'uci';
import { cursor } from 'uci';

const c = cursor();
c.load('pisowifi');
c.load('wireless');
c.load('network');

const content_type = 'text/html';
stdout.write(`Content-Type: ${content_type}\r\n\r\n`);

function get_client_ip() {
    const remote_addr = getenv('REMOTE_ADDR') || '192.168.1.100';
    return remote_addr;
}

function get_mac_address(ip) {
    return '00:11:22:33:44:55';
}

function generate_session_id() {
    return Math.random().toString(36).substr(2, 9);
}

function get_current_time() {
    return Math.floor(Date.now() / 1000);
}

function is_session_valid(session_id) {
    return false;
}

function create_session(mac_address, ip_address, duration) {
    const session_id = generate_session_id();
    const start_time = get_current_time();
    const end_time = start_time + (duration * 60);
    
    return {
        session_id: session_id,
        mac_address: mac_address,
        ip_address: ip_address,
        start_time: start_time,
        end_time: end_time,
        active: true
    };
}

const client_ip = get_client_ip();
const mac_address = get_mac_address(client_ip);

const portal_enabled = c.get('pisowifi', 'general', 'enabled') || '0';
const portal_url = c.get('pisowifi', 'general', 'portal_url') || 'http://192.168.1.1/cgi-bin/pisowifi-portal';
const session_timeout = c.get('pisowifi', 'general', 'session_timeout') || '60';
const price_per_hour = c.get('pisowifi', 'general', 'price_per_hour') || '5';
const landing_title = c.get('pisowifi', 'landing_page', 'landing_title') || 'Welcome to PisoWiFi';
const landing_message = c.get('pisowifi', 'landing_page', 'landing_message') || 'Please insert coin or pay to access the internet';

print(`<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${landing_title}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-align: center; }
        .container { max-width: 600px; margin: 0 auto; background: rgba(255,255,255,0.1); padding: 30px; border-radius: 15px; backdrop-filter: blur(10px); }
        .logo { font-size: 2.5em; margin-bottom: 20px; }
        .price { font-size: 1.5em; color: #ffd700; margin: 20px 0; }
        .payment-methods { display: flex; justify-content: center; gap: 20px; margin: 30px 0; }
        .payment-btn { padding: 15px 30px; border: none; border-radius: 25px; font-size: 1.1em; cursor: pointer; transition: all 0.3s ease; }
        .coin-btn { background: linear-gradient(45deg, #ffd700, #ffed4e); color: #333; }
        .qr-btn { background: linear-gradient(45deg, #4CAF50, #45a049); color: white; }
        .gcash-btn { background: linear-gradient(45deg, #0066cc, #004499); color: white; }
        .payment-btn:hover { transform: translateY(-2px); box-shadow: 0 5px 15px rgba(0,0,0,0.3); }
        .info { margin-top: 30px; font-size: 0.9em; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🌐 ${landing_title}</div>
        <h2>${landing_message}</h2>
        <div class="price">₱${price_per_hour} per hour</div>
        
        <div class="payment-methods">
            <button class="payment-btn coin-btn" onclick="payWithCoin()">💰 Insert Coin</button>
            <button class="payment-btn qr-btn" onclick="payWithQR()">📱 Scan QR Code</button>
            <button class="payment-btn gcash-btn" onclick="payWithGCash()">💳 GCash</button>
        </div>
        
        <div class="info">
            <p>Session Duration: ${session_timeout} minutes</p>
            <p>IP Address: ${client_ip}</p>
            <p>MAC Address: ${mac_address}</p>
        </div>
    </div>
    
    <script>
        function payWithCoin() {
            alert('Please insert ₱${price_per_hour} coin to start your session.');
            // In a real implementation, this would communicate with coin slot hardware
            createSession('coin');
        }
        
        function payWithQR() {
            alert('Please scan the QR code to pay via GCash or other payment apps.');
            // In a real implementation, this would show a QR code for payment
            createSession('qr');
        }
        
        function payWithGCash() {
            alert('Please send ₱${price_per_hour} to the GCash number displayed.');
            // In a real implementation, this would show GCash details
            createSession('gcash');
        }
        
        function createSession(paymentMethod) {
            // In a real implementation, this would make an API call to create a session
            // For now, we'll simulate a successful payment
            alert('Payment successful! Your session will start in a few moments...');
            
            // Simulate session creation
            setTimeout(function() {
                window.location.href = 'http://google.com';
            }, 2000);
        }
    </script>
</body>
</html>`);
EOF
    chmod 755 /www/cgi-bin/pisowifi-portal
fi

# Create log files
echo "Creating log files..."
touch /var/log/pisowifi.log
touch /var/log/pisowifi_revenue.log
chmod 644 /var/log/pisowifi*

# Create voucher database file
echo "Creating voucher database..."
echo '{}' > /etc/pisowifi/vouchers.json
chmod 644 /etc/pisowifi/vouchers.json

# Create session tracking file
echo "Creating session tracking file..."
echo '[]' > /tmp/pisowifi_sessions.json
chmod 666 /tmp/pisowifi_sessions.json

# Add firewall rules for PisoWiFi (OpenWrt fw4 compatible)
echo "Configuring firewall rules..."

# Clean up any existing PisoWiFi firewall rules first
uci show firewall | grep -i pisowifi | cut -d'.' -f1-2 | while read rule; do
    uci delete "$rule" 2>/dev/null || true
done
uci commit firewall 2>/dev/null || true

# Add HTTP/HTTPS access rules (using nftables-compatible syntax)
uci -q batch <<EOF
add firewall rule
set firewall.@rule[-1].name='PisoWiFi-HTTP'
set firewall.@rule[-1].src='wan'
set firewall.@rule[-1].proto='tcp'
set firewall.@rule[-1].dest_port='80'
set firewall.@rule[-1].target='ACCEPT'
commit firewall
add firewall rule
set firewall.@rule[-1].name='PisoWiFi-HTTPS'
set firewall.@rule[-1].src='wan'
set firewall.@rule[-1].proto='tcp'
set firewall.@rule[-1].dest_port='443'
set firewall.@rule[-1].target='ACCEPT'
commit firewall
EOF

# Create custom iptables chains for PisoWiFi (using direct iptables commands)
echo "Setting up PisoWiFi authentication chains..."
iptables -N pisowifi_auth 2>/dev/null || true
iptables -N pisowifi_block 2>/dev/null || true

# Add rules to redirect HTTP traffic to portal (port 80)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || true

# Add rules for authenticated users
iptables -A FORWARD -j pisowifi_auth 2>/dev/null || true
iptables -A FORWARD -j pisowifi_block 2>/dev/null || true

# Commit firewall changes
uci commit firewall

# Restart services
echo "Restarting services..."
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart

# Verify installation
echo "Verifying installation..."
if [ -f "/etc/config/pisowifi" ]; then
    echo "✓ Configuration file created"
else
    echo "✗ Configuration file missing"
fi

if [ -f "/www/cgi-bin/pisowifi-portal" ]; then
    echo "✓ CGI portal script created"
else
    echo "✗ CGI portal script missing"
fi

if [ -f "/etc/pisowifi/vouchers.json" ]; then
    echo "✓ Voucher database created"
else
    echo "✗ Voucher database missing"
fi

echo ""
echo "PisoWiFi installation completed!"
echo "Access the management interface at: http://your-router-ip/cgi-bin/luci/admin/pisowifi"
echo "Default admin credentials: admin/admin"
echo ""
echo "Important: Please change the default admin password immediately!"
echo "Configure your WiFi settings and enable the captive portal in the PisoWiFi menu."
echo ""
echo "To test the captive portal, visit: http://your-router-ip/cgi-bin/pisowifi-portal"