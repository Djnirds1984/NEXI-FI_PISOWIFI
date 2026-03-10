#!/bin/sh

echo "=== FIXING REBOOT ISSUE & CLEANING UP ==="

# 1. Fix the Button (The "Reboot" Issue)
# The router reboots because the button you are pressing is likely mapped as 'reset'.
# Standard OpenWrt 'reset' script reboots on a short press (< 1s).
# We will change this to: Short Press = INSERT COIN.

if [ -f "/etc/rc.button/reset" ]; then
    echo "Backing up original reset script..."
    cp /etc/rc.button/reset /etc/rc.button/reset.bak
    
    echo "Patching reset button..."
    cat << 'EOF' > /etc/rc.button/reset
#!/bin/sh

[ "${ACTION}" = "released" ] || exit 0

. /lib/functions.sh

logger "$BUTTON pressed for $SEEN seconds"

if [ "$SEEN" -lt 2 ]; then
    # Short press (less than 2 seconds) -> INSERT COIN
    FILE="/tmp/pisowifi_coins"
    if [ ! -f "$FILE" ]; then echo "0" > "$FILE"; fi
    COUNT=$(cat "$FILE")
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$FILE"
    logger -t pisowifi "Coin inserted via RESET button. Total: $COUNT"
    
elif [ "$SEEN" -gt 5 ]; then
    # Long press (more than 5 seconds) -> FACTORY RESET (Keep this for safety)
    echo "FACTORY RESET" > /dev/console
    jffs2reset -y && reboot &
fi
EOF
    chmod +x /etc/rc.button/reset
    echo "[OK] Reset button repurposed: Short Press = Coin, Long Press = Reset"
fi

# Also update WPS button just in case it is separate
cat << 'EOF' > /etc/rc.button/wps
#!/bin/sh
[ "${ACTION}" = "pressed" ] || exit 0
FILE="/tmp/pisowifi_coins"
if [ ! -f "$FILE" ]; then echo "0" > "$FILE"; fi
COUNT=$(cat "$FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$FILE"
logger -t pisowifi "Coin inserted via WPS button. Total: $COUNT"
EOF
chmod +x /etc/rc.button/wps


# 2. Fix the 404 / Cleanup Old Files
# Remove the broken LuCI controller so you don't accidentally hit it.
echo "Removing broken LuCI controller files..."
rm -f /usr/lib/lua/luci/controller/pisowifi.lua
rm -f /usr/lib/lua/luci/view/pisowifi/index.htm
rm -f /usr/lib/lua/luci/view/pisowifi/admin.htm

# 3. Ensure Redirect is Correct
echo "Ensuring redirect points to CGI..."
cat << 'EOF' > /www/index.html
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="0; URL=/cgi-bin/pisowifi" />
</head>
<body>
<a href="/cgi-bin/pisowifi">Click here to enter PisoWifi...</a>
</body>
</html>
EOF

echo "=== FIX COMPLETE ==="
echo "1. The Router should NO LONGER reboot on short press."
echo "2. Use http://10.0.0.1/ to access the portal."
