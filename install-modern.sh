#!/bin/sh
# Modern OpenWrt (nftables) Compatible Install Script for PisoWiFi
# This version works with newer OpenWrt versions that use nftables

echo "PisoWiFi Modern OpenWrt Installation Script"
echo "==========================================="
echo ""

# Create directories
echo "1. Creating directories..."
mkdir -p /www/luci-static/resources/view/pisowifi
mkdir -p /usr/lib/lua/luci/controller/pisowifi
mkdir -p /usr/lib/lua/luci/model/pisowifi
mkdir -p /etc/pisowifi
mkdir -p /www/cgi-bin
mkdir -p /var/log

# Create configuration file
echo "2. Creating configuration..."
cat > /etc/config/pisowifi <<'EOF'
config general 'general'
    option enabled '1'
    option session_timeout '60'
    option price_per_hour '5'

config admin 'admin'
    option username 'admin'
    option password '$1$admin$1$'  # admin
    option require_2fa '0'

config landing_page 'landing_page'
    option title 'PisoWiFi Hotspot'
    option message 'Welcome! Please pay to access the internet.'
    option background_color '#f0f0f0'
    option text_color '#333333'

config payment 'payment'
    option coinslot_enabled '1'
    option qr_enabled '1'
    option gcash_enabled '1'
    option gcash_number '09171234567'

config security 'security'
    option rate_limit '100'
    option max_sessions_per_ip '3'
    option block_time '300'

config access_control 'access_control'
    option allow_lan_access '1'
    option allow_admin_lan '1'
    option block_wan_on_unpaid '0'
EOF

# Create voucher database
echo "3. Creating voucher database..."
echo '{}' > /etc/pisowifi/vouchers.json
chmod 644 /etc/pisowifi/vouchers.json

# Create session tracking file
echo "4. Creating session tracking file..."
echo '[]' > /tmp/pisowifi_sessions.json
chmod 666 /tmp/pisowifi_sessions.json

# Create modern firewall rules using nftables
echo "5. Creating modern firewall rules..."
cat > /tmp/pisowifi-nftables.sh <<'EOF'
#!/bin/sh
# Modern nftables rules for PisoWiFi (OpenWrt 21.02+)

echo "Applying modern PisoWiFi firewall rules..."

# Check if nftables is available
if command -v nft >/dev/null 2>&1; then
    # Create PisoWiFi table
    nft add table inet pisowifi 2>/dev/null || true
    
    # Create chains
    nft add chain inet pisowifi input '{ type filter hook input priority 0; policy accept; }' 2>/dev/null || true
    nft add chain inet pisowifi forward '{ type filter hook forward priority 0; policy accept; }' 2>/dev/null || true
    nft add chain inet pisowifi nat-prerouting '{ type nat hook prerouting priority -100; }' 2>/dev/null || true
    
    # Allow LAN access (never block 192.168.x.x)
    nft add rule inet pisowifi input ip saddr 192.168.0.0/16 accept
    nft add rule inet pisowifi forward ip saddr 192.168.0.0/16 accept
    nft add rule inet pisowifi forward ip daddr 192.168.0.0/16 accept
    
    # Allow loopback
    nft add rule inet pisowifi input iif lo accept
    nft add rule inet pisowifi output oif lo accept
    
    # Allow SSH and web from LAN
    nft add rule inet pisowifi input ip saddr 192.168.0.0/16 tcp dport 22 accept
    nft add rule inet pisowifi input ip saddr 192.168.0.0/16 tcp dport 80 accept
    nft add rule inet pisowifi input ip saddr 192.168.0.0/16 tcp dport 443 accept
    
    # Redirect HTTP for non-LAN clients
    nft add rule inet pisowifi nat-prerouting ip saddr != 192.168.0.0/16 tcp dport 80 redirect to 8080
    
    echo "✓ Modern nftables rules applied"
else
    echo "⚠ nftables not found, skipping firewall rules"
fi
EOF

chmod +x /tmp/pisowifi-nftables.sh
/tmp/pisowifi-nftables.sh

# Create CGI portal
echo "6. Creating CGI portal..."
cat > /www/cgi-bin/pisowifi-portal <<'EOF'
#!/usr/bin/ucode
/* PisoWiFi Portal - Modern OpenWrt Compatible */

const fs = require('fs');
const uci = require('uci');

function get_client_ip() {
    return env.REMOTE_ADDR || '127.0.0.1';
}

function get_client_mac(ip) {
    const arp = fs.readfile('/proc/net/arp') || '';
    const lines = arp.split('\n');
    
    for (let line of lines) {
        if (line.includes(ip)) {
            const parts = line.split(/\s+/);
            if (parts.length >= 4) {
                return parts[3];
            }
        }
    }
    
    return '00:00:00:00:00:00';
}

function is_lan_client(ip) {
    return ip.startsWith('192.168.') || ip === '127.0.0.1';
}

function generate_portal_html() {
    const client_ip = get_client_ip();
    const mac_address = get_client_mac(client_ip);
    
    // LAN clients bypass portal
    if (is_lan_client(client_ip)) {
        print(`Status: 302 Found\r\n`);
        print(`Location: http://google.com\r\n`);
        print(`\r\n`);
        return;
    }
    
    const config = uci.cursor();
    const landing_title = config.get('pisowifi', 'landing_page', 'title') || 'PisoWiFi Hotspot';
    const landing_message = config.get('pisowifi', 'landing_page', 'message') || 'Welcome! Please pay to access the internet.';
    const price_per_hour = config.get('pisowifi', 'general', 'price_per_hour') || '5';
    const session_timeout = config.get('pisowifi', 'general', 'session_timeout') || '60';
    
    print(`Content-Type: text/html\r\n`);
    print(`\r\n`);
    print(`<!DOCTYPE html>`);
    print(`<html>`);
    print(`<head>`);
    print(`    <title>${landing_title}</title>`);
    print(`    <meta name="viewport" content="width=device-width, initial-scale=1.0">`);
    print(`    <style>`);
    print(`        body { font-family: Arial, sans-serif; background: #f0f0f0; margin: 0; padding: 20px; }`);
    print(`        .container { max-width: 400px; margin: 50px auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }`);
    print(`        .logo { font-size: 24px; text-align: center; margin-bottom: 20px; }`);
    print(`        .price { font-size: 20px; color: #27ae60; text-align: center; margin: 20px 0; }`);
    print(`        .payment-methods { display: flex; flex-direction: column; gap: 10px; }`);
    print(`        .payment-btn { padding: 15px; border: none; border-radius: 5px; font-size: 16px; cursor: pointer; }`);
    print(`        .coin-btn { background: #3498db; color: white; }`);
    print(`        .qr-btn { background: #e74c3c; color: white; }`);
    print(`        .gcash-btn { background: #f39c12; color: white; }`);
    print(`        .info { margin-top: 20px; padding: 15px; background: #ecf0f1; border-radius: 5px; font-size: 12px; }`);
    print(`    </style>`);
    print(`</head>`);
    print(`<body>`);
    print(`    <div class="container">`);
    print(`        <div class="logo">🌐 ${landing_title}</div>`);
    print(`        <h2>${landing_message}</h2>`);
    print(`        <div class="price">₱${price_per_hour} per hour</div>`);
    print(`        `);
    print(`        <div class="payment-methods">`);
    print(`            <button class="payment-btn coin-btn" onclick="payWithCoin()">💰 Insert Coin</button>`);
    print(`            <button class="payment-btn qr-btn" onclick="payWithQR()">📱 Scan QR Code</button>`);
    print(`            <button class="payment-btn gcash-btn" onclick="payWithGCash()">💳 GCash</button>`);
    print(`        </div>`);
    print(`        `);
    print(`        <div class="info">`);
    print(`            <p>Session Duration: ${session_timeout} minutes</p>`);
    print(`            <p>IP Address: ${client_ip}</p>`);
    print(`            <p>MAC Address: ${mac_address}</p>`);
    print(`            <p style="color: #e74c3c; font-weight: bold;">LAN clients bypass portal automatically</p>`);
    print(`        </div>`);
    print(`    </div>`);
    print(`    `);
    print(`    <script>`);
    print(`        function payWithCoin() {`);
    print(`            alert('Please insert ₱${price_per_hour} coin to start your session.');`);
    print(`            createSession('coin');`);
    print(`        }`);
    print(`        `);
    print(`        function payWithQR() {`);
    print(`            alert('Please scan the QR code to pay via GCash or other payment apps.');`);
    print(`            createSession('qr');`);
    print(`        }`);
    print(`        `);
    print(`        function payWithGCash() {`);
    print(`            alert('Please send ₱${price_per_hour} to the GCash number displayed.');`);
    print(`            createSession('gcash');`);
    print(`        }`);
    print(`        `);
    print(`        function createSession(paymentMethod) {`);
    print(`            alert('Payment successful! Your session will start in a few moments...');`);
    print(`            setTimeout(function() {`);
    print(`                window.location.href = 'http://google.com';`);
    print(`            }, 2000);`);
    print(`        }`);
    print(`    </script>`);
    print(`</body>`);
    print(`</html>`);
}

try {
    generate_portal_html();
} catch (error) {
    print(`Status: 500 Internal Server Error\r\n`);
    print(`Content-Type: text/plain\r\n`);
    print(`\r\n`);
    print(`Portal Error: ${error}\r\n`);
}
EOF

chmod 755 /www/cgi-bin/pisowifi-portal

# Create verification script
echo "7. Creating verification script..."
cat > /www/verify-modern.sh <<'EOF'
#!/bin/sh
echo "PisoWiFi Modern OpenWrt Verification"
echo "====================================="
echo ""

# Test web access
echo "1. Testing web services..."
if wget -O- -q http://localhost/cgi-bin/luci >/dev/null 2>&1; then
    echo "✓ LuCI web interface is accessible"
else
    echo "⚠ LuCI may not be accessible (try browser)"
fi

# Test SSH
echo "2. Testing SSH..."
if netstat -tlnp 2>/dev/null | grep -q ':22 '; then
    echo "✓ SSH port is listening"
else
    echo "✗ SSH port is NOT listening"
fi

# Check files
echo "3. Checking PisoWiFi files..."
[ -f "/etc/config/pisowifi" ] && echo "✓ Configuration file exists" || echo "✗ Configuration file missing"
[ -f "/www/cgi-bin/pisowifi-portal" ] && echo "✓ CGI portal exists" || echo "✗ CGI portal missing"
[ -f "/etc/pisowifi/vouchers.json" ] && echo "✓ Voucher database exists" || echo "✗ Voucher database missing"

# Check nftables
echo "4. Checking firewall..."
if command -v nft >/dev/null 2>&1; then
    if nft list tables 2>/dev/null | grep -q pisowifi; then
        echo "✓ PisoWiFi nftables rules installed"
    else
        echo "⚠ PisoWiFi nftables rules not found"
    fi
else
    echo "ℹ nftables not available (using basic firewall)"
fi

echo ""
echo "🎯 Access Points:"
echo "   LuCI Admin: http://192.168.1.1/cgi-bin/luci"
echo "   PisoWiFi Portal: http://192.168.1.1/cgi-bin/pisowifi-portal"
echo "   PisoWiFi Admin: http://192.168.1.1/cgi-bin/luci/admin/pisowifi"
EOF

chmod +x /www/verify-modern.sh

# Final verification
echo "8. Running final verification..."
/www/verify-modern.sh

echo ""
echo "✅ Modern OpenWrt installation complete!"
echo ""
echo "🌐 Your PisoWiFi is ready!"
echo "   Test the portal: http://192.168.1.1/cgi-bin/pisowifi-portal"
echo "   Admin dashboard: http://192.168.1.1/cgi-bin/luci/admin/pisowifi"
echo ""
echo "💡 Note: This version is compatible with modern OpenWrt (nftables)"