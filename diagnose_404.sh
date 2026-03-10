#!/bin/sh

echo "=== DIAGNOSING PISOWIFI CONTROLLER ==="
CONTROLLER="/usr/lib/lua/luci/controller/pisowifi.lua"

# 1. Check if file exists
if [ -f "$CONTROLLER" ]; then
    echo "[OK] File exists."
    ls -l "$CONTROLLER"
else
    echo "[ERROR] File is MISSING!"
    exit 1
fi

# 2. Check Syntax and Runtime Loading
echo "[*] Attempting to load module..."
lua -e "
    -- Mock LuCI environment to test loading
    package.path = '/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;' .. package.path
    _G.luci = {
        sys = { hostname = function() return 'test' end },
        http = { getenv = function() return '' end },
        util = {},
        jsonc = {},
        dispatcher = {}
    }
    
    -- Try loading the file
    local f, err = loadfile('$CONTROLLER')
    if not f then
        print('[ERROR] Syntax Error: ' .. err)
        os.exit(1)
    end
    
    -- Try executing the chunk
    local status, err = pcall(f)
    if not status then
        print('[ERROR] Runtime Error during load: ' .. err)
        os.exit(1)
    else
        print('[OK] Module loaded successfully.')
    end
"

# 3. Force Re-index
echo "[*] Clearing LuCI Index Cache..."
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/

# 4. Restart Web Server
echo "[*] Restarting uhttpd..."
/etc/init.d/uhttpd restart

echo "=== DIAGNOSIS COMPLETE ==="
