#!/bin/sh

echo "=== CHECKING LUCI-NG (UCODE) PATHS ==="

# Check for menu.d
if [ -d "/usr/share/luci/menu.d" ]; then
    echo "[OK] Found /usr/share/luci/menu.d"
    ls /usr/share/luci/menu.d
else
    echo "[MISSING] /usr/share/luci/menu.d"
fi

# Check for template path
if [ -d "/usr/lib/ucode/luci" ]; then
    echo "[OK] Found /usr/lib/ucode/luci"
else
    echo "[MISSING] /usr/lib/ucode/luci"
fi

# Check for installed luci packages
echo "[*] Installed LuCI packages:"
opkg list-installed | grep luci

echo "=== DONE ==="
