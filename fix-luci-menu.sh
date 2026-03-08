#!/bin/sh
# Fix LuCI admin menu registration for PisoWiFi

echo "Fixing PisoWiFi LuCI admin menu..."
echo "=================================="
echo ""

# 1. Clear LuCI cache
echo "1. Clearing LuCI cache..."
rm -f /tmp/luci-*
echo "✓ LuCI cache cleared"

# 2. Restart uhttpd
echo "2. Restarting web server..."
/etc/init.d/uhttpd restart
echo "✓ Web server restarted"

# 3. Check if controller file exists
echo "3. Checking controller file..."
if [ -f "/usr/lib/lua/luci/controller/pisowifi/pisowifi.lua" ]; then
    echo "✓ Controller file exists"
else
    echo "✗ Controller file missing"
fi

# 4. Check if model file exists
echo "4. Checking model file..."
if [ -f "/usr/lib/lua/luci/model/pisowifi/pisowifi.lua" ]; then
    echo "✓ Model file exists"
else
    echo "✗ Model file missing"
fi

# 5. Test admin access
echo "5. Testing admin access..."
sleep 2  # Wait for uhttpd to fully restart
if wget -O- -q "http://localhost/cgi-bin/luci/admin/pisowifi" 2>/dev/null | grep -q "404"; then
    echo "⚠ Admin menu still not accessible"
    echo ""
    echo "Try these manual steps:"
    echo "1. Check LuCI logs: logread | grep luci"
    echo "2. Verify file permissions: ls -la /usr/lib/lua/luci/controller/pisowifi/"
    echo "3. Test basic LuCI: http://192.168.1.1/cgi-bin/luci"
else
    echo "✓ Admin menu appears to be working"
fi

echo ""
echo "🎯 Test these URLs:"
echo "   LuCI: http://192.168.1.1/cgi-bin/luci"
echo "   PisoWiFi Admin: http://192.168.1.1/cgi-bin/luci/admin/pisowifi"
echo "   Portal: http://192.168.1.1/cgi-bin/pisowifi-portal"