#!/bin/ash

# PisoWiFi LuCI Replacement Script
# This script configures uHTTPd to replace LuCI with PisoWiFi interface

echo "=== PisoWiFi LuCI Replacement Script ==="
echo "This script will configure your router to use PisoWiFi instead of LuCI"
echo ""

# Backup current uHTTPd configuration
echo "Backing up current uHTTPd configuration..."
cp /etc/config/uhttpd /etc/config/uhttpd.backup.$(date +%Y%m%d_%H%M%S)

# Create redirect configuration for LuCI paths
cat > /www/cgi-bin/luci << 'EOF'
#!/bin/ash
echo "Status: 302 Found"
echo "Location: /index.html"
echo "Content-Type: text/html"
echo ""
echo "<html><head><meta http-equiv=\"refresh\" content=\"0; url=/index.html\"></head><body>Redirecting to PisoWiFi...</body></html>"
EOF

chmod +x /www/cgi-bin/luci

# Create index.php redirect (if PHP is installed)
if [ -f /www/index.php ]; then
    mv /www/index.php /www/index.php.backup
fi

cat > /www/index.php << 'EOF'
<?php
header("Location: /index.html");
die();
?>
EOF

# Create .htaccess for additional redirects
cat > /www/.htaccess << 'EOF'
RewriteEngine On
RewriteRule ^cgi-bin/luci(/.*)?$ /index.html [R=302,L]
RewriteRule ^luci(/.*)?$ /index.html [R=302,L]
EOF

# Create main redirect page
cat > /www/redirect.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=/index.html">
    <title>Redirecting to PisoWiFi</title>
</head>
<body>
    <p>Redirecting to PisoWiFi Management System...</p>
    <p><a href="/index.html">Click here if not redirected</a></p>
</body>
</html>
EOF

# Configure uHTTPd to serve PisoWiFi as default
echo "Configuring uHTTPd to serve PisoWiFi as default..."

# Add PisoWiFi configuration to uhttpd
if ! grep -q "pisowifi" /etc/config/uhttpd; then
    cat >> /etc/config/uhttpd << 'EOF'

config uhttpd pisowifi
    option listen_http 80
    option home /www
    option index_page index.html
    option error_page redirect.html
    option cgi_prefix /cgi-bin
    option script_timeout 60
    option network_timeout 30
    option max_requests 3
    list index_page 'index.html'
EOF
fi

# Restart uHTTPd to apply changes
echo "Restarting uHTTPd service..."
/etc/init.d/uhttpd restart

# Create backup script
cat > /www/backup-luci.sh << 'EOF'
#!/bin/ash
echo "Creating backup of current configuration..."
tar -czf /tmp/pisowifi-backup-$(date +%Y%m%d_%H%M%S).tar.gz /www /etc/config/uhttpd
echo "Backup created: /tmp/pisowifi-backup-*.tar.gz"
EOF
chmod +x /www/backup-luci.sh

# Create restore script
cat > /www/restore-luci.sh << 'EOF'
#!/bin/ash
echo "Restoring LuCI interface..."
# Remove redirects
rm -f /www/cgi-bin/luci
rm -f /www/index.php
rm -f /www/.htaccess
rm -f /www/redirect.html

# Restore original uHTTPd config
if [ -f /etc/config/uhttpd.backup.* ]; then
    latest_backup=$(ls -t /etc/config/uhttpd.backup.* | head -1)
    cp "$latest_backup" /etc/config/uhttpd
fi

# Restart uHTTPd
/etc/init.d/uhttpd restart
echo "LuCI interface restored. Access via http://192.168.1.1/cgi-bin/luci"
EOF
chmod +x /www/restore-luci.sh

echo ""
echo "=== Installation Complete ==="
echo "PisoWiFi interface is now available at:"
echo "  http://192.168.1.1/index.html"
echo "  http://192.168.1.1/"
echo ""
echo "LuCI interface redirects have been created."
echo "To restore LuCI, run: /www/restore-luci.sh"
echo "To backup current config, run: /www/backup-luci.sh"
echo ""
echo "Make sure your PisoWiFi files are in:"
echo "  /www/index.html"
echo "  /www/cgi-bin/api"
echo ""
echo "The router web interface has been successfully replaced!"