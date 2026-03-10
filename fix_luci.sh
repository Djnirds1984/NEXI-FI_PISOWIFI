#!/bin/sh

CONTROLLER="/usr/lib/lua/luci/controller/pisowifi.lua"

echo "Checking for Lua syntax errors..."
if command -v luac >/dev/null 2>&1; then
    luac -p "$CONTROLLER"
    if [ $? -eq 0 ]; then
        echo "Syntax OK: $CONTROLLER"
    else
        echo "Syntax Error in $CONTROLLER"
    fi
elif command -v lua >/dev/null 2>&1; then
    lua -e "local f,err = loadfile('$CONTROLLER'); if not f then print(err); os.exit(1) end"
    if [ $? -eq 0 ]; then
        echo "Syntax OK: $CONTROLLER"
    else
        echo "Syntax Error in $CONTROLLER"
    fi
else
    echo "Warning: 'luac' or 'lua' not found. Skipping syntax check."
fi

echo "Clearing LuCI cache..."
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo "Restarting uhttpd..."
/etc/init.d/uhttpd restart

echo "Setting permissions..."
[ -f /usr/bin/pisowifi_firewall.sh ] && chmod +x /usr/bin/pisowifi_firewall.sh
[ -f /etc/rc.button/wps ] && chmod +x /etc/rc.button/wps

echo "Done! Try accessing http://10.0.0.1/cgi-bin/luci/pisowifi again."
