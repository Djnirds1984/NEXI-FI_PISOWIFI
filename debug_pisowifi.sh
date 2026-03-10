#!/bin/sh

echo "=== DEBUG PISOWIFI INSTALLATION ==="

# 1. Check Files
echo "[*] Checking files..."
if [ -f "/usr/lib/lua/luci/controller/pisowifi.lua" ]; then
    echo "  [OK] Controller found."
else
    echo "  [MISSING] /usr/lib/lua/luci/controller/pisowifi.lua"
fi

if [ -f "/usr/lib/lua/luci/view/pisowifi/index.htm" ]; then
    echo "  [OK] Index View found."
else
    echo "  [MISSING] /usr/lib/lua/luci/view/pisowifi/index.htm"
fi

# 2. Check Lua
echo "[*] Checking Lua..."
LUA_BIN=""
if command -v lua5.1 >/dev/null; then
    LUA_BIN="lua5.1"
elif command -v lua >/dev/null; then
    LUA_BIN="lua"
fi

if [ -n "$LUA_BIN" ]; then
    echo "  [OK] Found Lua: $LUA_BIN"
    echo "  [*] Testing Controller Syntax..."
    $LUA_BIN -e "local f,e = loadfile('/usr/lib/lua/luci/controller/pisowifi.lua'); if not f then print('SYNTAX ERROR: '..e) else print('Syntax OK') end"
else
    echo "  [WARNING] Lua not found in PATH."
fi

# 3. Force Re-index
echo "[*] Forcing LuCI Re-index..."
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/

echo "=== DONE ==="
