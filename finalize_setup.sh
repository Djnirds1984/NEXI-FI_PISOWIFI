#!/bin/sh

echo "=== FINALIZING PISOWIFI SETUP ==="

# 1. Verify Controller Installation
if [ -s "/usr/lib/lua/luci/controller/pisowifi.lua" ]; then
    echo "[OK] Controller file exists and is not empty."
else
    echo "[ERROR] Controller file is missing or empty!"
    exit 1
fi

# 2. Set Main Page Redirect (Make Captive Portal the Landing Page)
echo "Setting up landing page redirect..."
cat << 'EOF' > /www/index.html
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate" />
<meta http-equiv="refresh" content="0; URL=/cgi-bin/luci/pisowifi" />
<style>body{background:white;font-family:sans-serif;}</style>
</head>
<body>
<a href="/cgi-bin/luci/pisowifi">Redirecting to PisoWifi...</a>
</body>
</html>
EOF

# 3. Ensure Permissions
chmod +x /usr/bin/pisowifi_firewall.sh
chmod +x /etc/rc.button/wps

# 4. Final Service Restart
echo "Restarting web server..."
/etc/init.d/uhttpd restart

echo "=== SETUP COMPLETE ==="
echo "You can now access the portal at: http://10.0.0.1/"
