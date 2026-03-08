#!/bin/sh
# Modern OpenWrt Verification Script (nftables compatible)

echo "PisoWiFi Modern OpenWrt Verification"
echo "====================================="
echo ""

# Test web access (using wget instead of curl)
echo "1. Testing web services..."
if wget -O- -q http://localhost/cgi-bin/luci >/dev/null 2>&1; then
    echo "✓ LuCI web interface is accessible"
else
    echo "⚠ LuCI may not be accessible (try browser at http://192.168.1.1/cgi-bin/luci)"
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
[ -f "/tmp/pisowifi_sessions.json" ] && echo "✓ Session tracking exists" || echo "✗ Session tracking missing"

# Check nftables (modern OpenWrt)
echo "4. Checking firewall..."
if command -v nft >/dev/null 2>&1; then
    if nft list tables 2>/dev/null | grep -q pisowifi; then
        echo "✓ PisoWiFi nftables rules installed"
    else
        echo "ℹ PisoWiFi nftables rules not found (LAN access preserved by default)"
    fi
else
    echo "ℹ nftables not available (using basic firewall)"
fi

echo ""
echo "🎯 Your PisoWiFi Access Points:"
echo "   Portal: http://192.168.1.1/cgi-bin/pisowifi-portal"
echo "   Admin: http://192.168.1.1/cgi-bin/luci/admin/pisowifi"
echo "   LuCI: http://192.168.1.1/cgi-bin/luci"
echo ""
echo "💡 Note: LAN access is preserved on modern OpenWrt by default"
echo "🌐 Test the captive portal from a different network/device"