#!/bin/sh
# Quick CGI Fix Script for PisoWiFi
# This script fixes common CGI configuration issues

echo "=== PisoWiFi CGI Quick Fix ==="
echo ""

# 1. Check current uhttpd configuration
echo "1. Current uhttpd configuration:"
uci show uhttpd 2>/dev/null | grep -E "(cgi|home|listen)" || echo "No CGI configuration found"

# 2. Clean up conflicting uhttpd configurations
echo ""
echo "2. Cleaning up uhttpd configurations..."

# Remove all but the main uhttpd configuration
while [ $(uci show uhttpd 2>/dev/null | grep -c "^uhttpd.@uhttpd\[") -gt 1 ]; do
    uci delete uhttpd.@uhttpd[-1]
done

# 3. Configure main uhttpd for CGI
echo ""
echo "3. Configuring main uhttpd for CGI..."
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci set uhttpd.main.script_timeout='60'
uci set uhttpd.main.home='/www'

# Remove existing interpreter list and add fresh one
uci delete uhttpd.main.interpreter
uci add_list uhttpd.main.interpreter='.cgi=/usr/bin/ucode'

# 4. Commit configuration
echo ""
echo "4. Committing configuration..."
uci commit uhttpd

# 5. Restart uhttpd
echo ""
echo "5. Restarting uhttpd service..."
if [ -f "/etc/init.d/uhttpd" ]; then
    /etc/init.d/uhttpd restart
    if [ $? -eq 0 ]; then
        echo "✓ uhttpd restarted successfully"
    else
        echo "✗ Failed to restart uhttpd"
    fi
fi

# 6. Test CGI
echo ""
echo "6. Testing CGI configuration..."

# Create simple test CGI
cat > /www/cgi-bin/test.cgi << 'EOF'
#!/usr/bin/ucode
print("Content-Type: application/json\n")
print('{"success": true, "message": "CGI is working!"}')
EOF

chmod 755 /www/cgi-bin/test.cgi

# Test with curl if available
if command -v curl >/dev/null 2>&1; then
    echo "Testing CGI with curl..."
    result=$(curl -s "http://localhost/cgi-bin/test.cgi" 2>/dev/null)
    if echo "$result" | grep -q "CGI is working"; then
        echo "✓ Basic CGI is working"
    else
        echo "✗ Basic CGI test failed"
        echo "Response: $result"
    fi
    
    # Test PisoWiFi API
    if [ -f "/www/pisowifi/cgi-bin/api-real.cgi" ]; then
        echo "Testing PisoWiFi API..."
        result=$(curl -s "http://localhost/pisowifi/cgi-bin/api-real.cgi?action=get_hotspot_settings" 2>/dev/null)
        if echo "$result" | grep -q "success"; then
            echo "✓ PisoWiFi API is working"
        else
            echo "✗ PisoWiFi API test failed"
            echo "Response: $result"
        fi
    fi
fi

# 7. Cleanup
echo ""
echo "7. Cleaning up test files..."
rm -f /www/cgi-bin/test.cgi

echo ""
echo "=== Fix Complete ==="
echo "Try accessing: http://10.0.0.1/pisowifi/cgi-bin/api-real.cgi?action=get_hotspot_settings"