#!/bin/sh
# PisoWiFi Post-Installation Verification Script

echo "=== PisoWiFi System Verification ==="
echo ""

# Check if we're on OpenWrt
if [ -f "/etc/openwrt_release" ]; then
    echo "✓ OpenWrt system detected"
    cat /etc/openwrt_release | grep "DISTRIB_DESCRIPTION" | sed 's/DISTRIB_DESCRIPTION=//'
else
    echo "⚠ This script is designed for OpenWrt systems"
fi

echo ""
echo "=== File System Check ==="

# Check directories
echo "Checking directories..."
for dir in "/etc/pisowifi" "/www/cgi-bin" "/usr/lib/lua/luci/model/pisowifi" "/usr/lib/lua/luci/controller/pisowifi" "/www/luci-static/resources/view/pisowifi"; do
    if [ -d "$dir" ]; then
        echo "✓ $dir exists"
    else
        echo "✗ $dir missing"
    fi
done

echo ""
echo "=== Configuration Files ==="

# Check configuration files
for file in "/etc/config/pisowifi" "/etc/config/pisowifi_segments" "/etc/pisowifi/vouchers.json" "/tmp/pisowifi_sessions.json"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists ($(wc -l < "$file") lines)"
    else
        echo "✗ $file missing"
    fi
done

echo ""
echo "=== CGI Portal ==="

# Check CGI portal
if [ -f "/www/cgi-bin/pisowifi-portal" ]; then
    echo "✓ CGI portal script exists"
    if [ -x "/www/cgi-bin/pisowifi-portal" ]; then
        echo "✓ CGI portal script is executable"
    else
        echo "✗ CGI portal script is not executable"
        echo "  Run: chmod 755 /www/cgi-bin/pisowifi-portal"
    fi
else
    echo "✗ CGI portal script missing"
fi

echo ""
echo "=== LuCI Integration ==="

# Check LuCI files
for file in "/usr/lib/lua/luci/controller/pisowifi/pisowifi.lua" "/usr/lib/lua/luci/model/pisowifi/pisowifi.lua"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing"
    fi
done

echo ""
echo "=== Web Interface Files ==="

# Check web interface files
js_files="/www/luci-static/resources/view/pisowifi/"
if [ -d "$js_files" ]; then
    echo "✓ LuCI view directory exists"
    file_count=$(find "$js_files" -name "*.js" | wc -l)
    echo "  Found $file_count JavaScript files"
else
    echo "✗ LuCI view directory missing"
fi

echo ""
echo "=== Service Status ==="

# Check services
echo "Checking service status..."
if /etc/init.d/uhttpd status >/dev/null 2>&1; then
    echo "✓ uhttpd service is running"
else
    echo "✗ uhttpd service is not running"
    echo "  Run: /etc/init.d/uhttpd start"
fi

if /etc/init.d/firewall status >/dev/null 2>&1; then
    echo "✓ firewall service is running"
else
    echo "✗ firewall service is not running"
    echo "  Run: /etc/init.d/firewall start"
fi

echo ""
echo "=== Network Configuration ==="

# Check network interfaces
echo "Network interfaces:"
ip addr show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/://' | while read iface; do
    if [ "$iface" != "lo" ]; then
        ip_addr=$(ip addr show "$iface" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$ip_addr" ]; then
            echo "  $iface: $ip_addr"
        fi
    fi
done

echo ""
echo "=== Firewall Rules ==="

# Check iptables rules
echo "Checking iptables rules..."
if iptables -L | grep -q "pisowifi"; then
    echo "✓ PisoWiFi iptables chains found"
    iptables -L | grep "pisowifi" | head -5
else
    echo "✗ PisoWiFi iptables chains not found"
fi

echo ""
echo "=== Testing Web Access ==="

# Test web access
router_ip=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$router_ip" ]; then
    echo "Router IP detected: $router_ip"
    echo "Testing web interface access..."
    
    # Test LuCI interface
    if wget -q -O /dev/null "http://$router_ip/cgi-bin/luci/" 2>/dev/null; then
        echo "✓ LuCI web interface accessible"
    else
        echo "✗ LuCI web interface not accessible"
    fi
    
    # Test PisoWiFi portal
    if wget -q -O /dev/null "http://$router_ip/cgi-bin/pisowifi-portal" 2>/dev/null; then
        echo "✓ PisoWiFi portal accessible"
    else
        echo "✗ PisoWiFi portal not accessible"
    fi
else
    echo "✗ Could not detect router IP address"
fi

echo ""
echo "=== Quick Fix Commands ==="
echo "If you see any ✗ errors above, run these commands:"
echo ""
echo "1. Fix file permissions:"
echo "   chmod 755 /www/cgi-bin/pisowifi-portal"
echo "   chmod 644 /etc/config/pisowifi*"
echo "   chmod 644 /etc/pisowifi/vouchers.json"
echo ""
echo "2. Restart services:"
echo "   /etc/init.d/uhttpd restart"
echo "   /etc/init.d/firewall restart"
echo ""
echo "3. Check logs:"
echo "   logread | grep pisowifi"
echo "   tail -f /var/log/messages"
echo ""
echo "=== Installation Complete ==="
echo "For full documentation, see the README.md file"
echo "Access the management interface at: http://$router_ip/cgi-bin/luci/admin/pisowifi"
echo "Test the captive portal at: http://$router_ip/cgi-bin/pisowifi-portal"