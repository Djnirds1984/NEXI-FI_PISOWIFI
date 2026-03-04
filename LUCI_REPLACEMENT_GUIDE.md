# Complete PisoWiFi LuCI Replacement Guide

## Problem: LuCI Still Shows After Copying Files

Even after copying the PisoWiFi files, the original LuCI interface still appears at `http://192.168.1.1/cgi-bin/luci/` because:

1. **uHTTPd is still configured to serve LuCI by default**
2. **The CGI paths are still pointing to LuCI scripts**
3. **No redirect rules are in place**

## Complete Replacement Solution

### Step 1: Copy Files to Router

```bash
# Copy files to router (run from your computer)
scp index.html root@192.168.1.1:/www/
scp cgi-bin/api root@192.168.1.1:/www/cgi-bin/

# Make CGI script executable
ssh root@192.168.1.1 "chmod +x /www/cgi-bin/api"
```

### Step 2: Run the Installation Script

```bash
# Copy and run the installation script
scp install-pisowifi.sh root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "sh /tmp/install-pisowifi.sh"
```

### Step 3: Manual Configuration (Alternative Method)

If the script doesn't work, manually configure uHTTPd:

```bash
# SSH to router
ssh root@192.168.1.1

# Backup current uHTTPd config
cp /etc/config/uhttpd /etc/config/uhttpd.backup

# Edit uHTTPd configuration
vi /etc/config/uhttpd
```

Add this to the uHTTPd config:
```
config uhttpd pisowifi
    option listen_http 80
    option home /www
    option index_page index.html
    option cgi_prefix /cgi-bin
    option script_timeout 60
    option network_timeout 30
```

### Step 4: Create Redirect Rules

```bash
# Create redirect for LuCI paths
cat > /www/cgi-bin/luci << 'EOF'
#!/bin/ash
echo "Status: 302 Found"
echo "Location: /index.html"
echo "Content-Type: text/html"
echo ""
echo "<html><head><meta http-equiv=\"refresh\" content=\"0; url=/index.html\"></head><body>Redirecting to PisoWiFi...</body></html>"
EOF

chmod +x /www/cgi-bin/luci

# Create redirect for root path
cat > /www/index.php << 'EOF'
<?php
header("Location: /index.html");
die();
?>
EOF
```

### Step 5: Restart uHTTPd

```bash
# Restart the web server
/etc/init.d/uhttpd restart

# Check status
/etc/init.d/uhttpd status
```

### Step 6: Verify the Replacement

Test these URLs:
- `http://192.168.1.1/` → Should show PisoWiFi
- `http://192.168.1.1/index.html` → Should show PisoWiFi
- `http://192.168.1.1/cgi-bin/luci` → Should redirect to PisoWiFi

## Troubleshooting

### If LuCI Still Appears

1. **Clear browser cache** completely
2. **Try different browser** or incognito mode
3. **Check uHTTPd logs**:
   ```bash
   logread | grep uhttpd
   ```

4. **Verify file permissions**:
   ```bash
   ls -la /www/index.html
   ls -la /www/cgi-bin/api
   ```

5. **Check uHTTPd is running**:
   ```bash
   ps | grep uhttpd
   netstat -tlnp | grep :80
   ```

### Complete Manual Override

If automatic methods fail, manually override the configuration:

```bash
# Stop LuCI service
/etc/init.d/uhttpd stop

# Create simple redirect in index.html
cat > /www/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=/index.html">
</head>
<body>
    <p>Loading PisoWiFi...</p>
    <script>window.location.href = '/index.html';</script>
</body>
</html>
EOF

# Start uHTTPd
/etc/init.d/uhttpd start
```

## Restore LuCI (If Needed)

```bash
# Run the restore script
sh /www/restore-luci.sh

# Or manually restore
mv /etc/config/uhttpd.backup /etc/config/uhttpd
/etc/init.d/uhttpd restart
```

## Alternative: Port-Based Solution

If you want to keep both interfaces:

```bash
# Configure PisoWiFi on port 8080
uci set uhttpd.pisowifi.listen_http='0.0.0.0:8080'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

Now access:
- **PisoWiFi**: `http://192.168.1.1:8080/`
- **LuCI**: `http://192.168.1.1/cgi-bin/luci`

## Final Verification

After successful replacement:

1. **PisoWiFi should load** at `http://192.168.1.1/`
2. **No LuCI login page** should appear
3. **All PisoWiFi features** should work (Status, WiFi, License, Sales, Settings)
4. **API calls** should respond correctly

## Security Note

The replacement is now complete! Your router will:
- ✅ Show PisoWiFi interface by default
- ✅ Redirect all LuCI requests to PisoWiFi
- ✅ Maintain all PisoWiFi functionality
- ✅ Allow easy restoration if needed