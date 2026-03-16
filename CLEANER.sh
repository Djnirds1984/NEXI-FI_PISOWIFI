#!/bin/sh

echo "=== STARTING CLEANUP ==="

# 1. Clean up unused LuCI files
# LuCI takes up a lot of space. If you're purely CGI-based, you can remove these.
# BE CAREFUL: Removing opkg packages can be risky if dependencies are shared.
# Instead of full removal, we delete the web interface files which are safe to remove.

if [ -d "/www/luci-static" ]; then
    echo "Removing LuCI Static Files..."
    rm -rf /www/luci-static
fi

if [ -d "/usr/lib/lua/luci" ]; then
    echo "Removing LuCI Lua Files..."
    rm -rf /usr/lib/lua/luci
fi

# Remove old/unused CGI scripts if any
echo "Cleaning up /www/cgi-bin..."
find /www/cgi-bin -name "luci*" -exec rm -f {} \;

# 2. Clean up temporary files
echo "Cleaning up /tmp..."
rm -f /tmp/pisowifi_button.sh
rm -f /tmp/post_data_*

# 3. Clean up installation artifacts
# Remove the scripts used to install this system
echo "Removing installation scripts..."
rm -f /root/INSTALL_CGI.sh
rm -f /root/FULL_INSTALL.sh
rm -f /root/install.sh
rm -f /root/fix_deps.sh

# 4. Clear Package Cache
echo "Clearing OPKG cache..."
rm -f /var/opkg-lists/*

echo "=== CLEANUP COMPLETE ==="
echo "You can now reboot to reclaim /tmp memory."
