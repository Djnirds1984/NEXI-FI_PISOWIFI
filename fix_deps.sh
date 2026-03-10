#!/bin/sh

echo "=== FIXING PISOWIFI DEPENDENCIES ==="

# 1. Check LuCI Installation Path
# Some OpenWrt versions (newer) use /usr/lib/lua/luci, older use /usr/lib/lua/luci
# We need to find where 'sys.lua' is located.

LUA_PATH=$(find /usr/lib/lua -name "sys.lua" 2>/dev/null)
if [ -z "$LUA_PATH" ]; then
    echo "[ERROR] Cannot find 'luci.sys' anywhere!"
    echo "Is LuCI installed properly?"
    opkg list-installed | grep luci-base
    exit 1
fi

echo "[INFO] Found 'sys.lua' at: $LUA_PATH"

# 2. Re-write Controller with Correct Require Logic
# If sys.lua is found but not loading, it might be a path issue or we are running in ucode environment.
# Let's try to make a simpler controller that doesn't depend heavily on external libs immediately.

cat << 'EOF' > /usr/lib/lua/luci/controller/pisowifi.lua
module("luci.controller.pisowifi", package.seeall)

function index()
    entry({"pisowifi"}, template("pisowifi/index"), "PisoWifi", 1).sysauth = false
    entry({"pisowifi", "api", "login"}, call("api_login"), nil).sysauth = false
    entry({"pisowifi", "api", "logout"}, call("api_logout"), nil).sysauth = false
    entry({"pisowifi", "api", "status"}, call("api_status"), nil).sysauth = false
    entry({"pisowifi", "api", "start_coin"}, call("api_start_coin"), nil).sysauth = false
    entry({"pisowifi", "api", "check_coin"}, call("api_check_coin"), nil).sysauth = false
    entry({"pisowifi", "api", "connect"}, call("api_connect"), nil).sysauth = false
    entry({"admin", "pisowifi"}, alias("admin", "pisowifi", "dashboard"), "PisoWifi Admin", 60)
    entry({"admin", "pisowifi", "dashboard"}, template("pisowifi/admin"), "Dashboard", 1)
    entry({"admin", "pisowifi", "kick"}, call("action_kick"), nil)
end

-- Lazy load dependencies inside functions to avoid load-time errors
local function get_deps()
    local sys = require "luci.sys"
    local http = require "luci.http"
    local json = require "luci.jsonc"
    return sys, http, json
end

local CHAIN_NAME = "PISOWIFI_AUTH"
local COIN_FILE = "/tmp/pisowifi_coins"
local SESSION_FILE = "/tmp/pisowifi.sessions"
local MINUTES_PER_PESO = 12
local FIREWALL_SCRIPT = "/usr/bin/pisowifi_firewall.sh"

function api_status()
    local sys, http, json = get_deps()
    local ip = http.getenv("REMOTE_ADDR")
    local mac = ip and sys.net.ip4mac(ip) or nil
    if mac then mac = mac:upper() end
    
    local authenticated = false
    local time_remaining = 0
    
    -- Check firewall status
    if sys.call("iptables -C FORWARD -j " .. CHAIN_NAME .. " 2>/dev/null") ~= 0 then
        sys.call(FIREWALL_SCRIPT .. " init")
    end
    
    if mac then
        -- Simple session check
        local f = io.open(SESSION_FILE, "r")
        if f then
            for line in f:lines() do
                local m, exp = line:match("([%x:]+) (%d+)")
                if m == mac then
                    local now = os.time()
                    local expiry = tonumber(exp)
                    if expiry > now then
                        authenticated = true
                        time_remaining = expiry - now
                        -- Ensure firewall rule exists
                        if sys.call("iptables -C " .. CHAIN_NAME .. " -m mac --mac-source " .. mac .. " -j ACCEPT 2>/dev/null") ~= 0 then
                             sys.call(FIREWALL_SCRIPT .. " allow " .. mac)
                        end
                    end
                    break
                end
            end
            f:close()
        end
    end
    
    http.prepare_content("application/json")
    http.write_json({authenticated = authenticated, time_remaining = time_remaining, mac = mac, ip = ip})
end

function api_start_coin()
    local sys, http, json = get_deps()
    local f = io.open(COIN_FILE, "w")
    if f then f:write("0"); f:close() end
    sys.call(FIREWALL_SCRIPT .. " init")
    http.prepare_content("application/json")
    http.write_json({status = "started"})
end

function api_check_coin()
    local sys, http, json = get_deps()
    local count = 0
    local f = io.open(COIN_FILE, "r")
    if f then count = tonumber(f:read("*all")) or 0; f:close() end
    http.prepare_content("application/json")
    http.write_json({count = count, minutes = count * MINUTES_PER_PESO})
end

function api_connect()
    local sys, http, json = get_deps()
    local ip = http.getenv("REMOTE_ADDR")
    local mac = ip and sys.net.ip4mac(ip) or nil
    if not mac then return end
    mac = mac:upper()
    
    local count = 0
    local f = io.open(COIN_FILE, "r")
    if f then count = tonumber(f:read("*all")) or 0; f:close() end
    
    if count > 0 then
        local added_minutes = count * MINUTES_PER_PESO
        local now = os.time()
        
        -- Load sessions
        local sessions = {}
        local f = io.open(SESSION_FILE, "r")
        if f then
            for line in f:lines() do
                local m, e = line:match("([%x:]+) (%d+)")
                if m then sessions[m] = tonumber(e) end
            end
            f:close()
        end
        
        local current_expiry = sessions[mac] or now
        if current_expiry < now then current_expiry = now end
        local new_expiry = current_expiry + (added_minutes * 60)
        sessions[mac] = new_expiry
        
        -- Save sessions
        f = io.open(SESSION_FILE, "w")
        if f then
            for m, e in pairs(sessions) do f:write(m .. " " .. e .. "\n") end
            f:close()
        end
        
        -- Reset coin
        f = io.open(COIN_FILE, "w")
        if f then f:write("0"); f:close() end
        
        -- Allow
        sys.call(FIREWALL_SCRIPT .. " allow " .. mac)
        
        http.prepare_content("application/json")
        http.write_json({status = "connected", expiry = new_expiry})
    else
        http.prepare_content("application/json")
        http.write_json({error = "No coins"})
    end
end

function api_logout()
    local sys, http, json = get_deps()
    local ip = http.getenv("REMOTE_ADDR")
    local mac = ip and sys.net.ip4mac(ip) or nil
    if mac then 
        mac = mac:upper()
        sys.call(FIREWALL_SCRIPT .. " deny " .. mac)
        
        -- Remove from sessions
        local sessions = {}
        local f = io.open(SESSION_FILE, "r")
        if f then
            for line in f:lines() do
                local m, e = line:match("([%x:]+) (%d+)")
                if m and m ~= mac then sessions[m] = tonumber(e) end
            end
            f:close()
        end
        
        f = io.open(SESSION_FILE, "w")
        if f then
            for m, e in pairs(sessions) do f:write(m .. " " .. e .. "\n") end
            f:close()
        end
        
        http.write_json({status = "success"}) 
    end
end

function get_active_users()
    local sessions = {}
    local users = {}
    local now = os.time()
    local f = io.open(SESSION_FILE, "r")
    if f then
        for line in f:lines() do
            local mac, expiry = line:match("([%x:]+) (%d+)")
            if mac then
                expiry = tonumber(expiry)
                if expiry > now then
                    table.insert(users, {mac = mac, expiry = expiry, remaining = expiry - now})
                end
            end
        end
        f:close()
    end
    return users
end

function action_kick()
    local sys, http, json = get_deps()
    local mac = http.formvalue("mac")
    if mac then
        sys.call(FIREWALL_SCRIPT .. " deny " .. mac)
        -- Update session file logic same as logout
    end
    http.redirect(luci.dispatcher.build_url("admin", "pisowifi", "dashboard"))
end

_G.get_active_users = get_active_users
EOF

# 3. Clear Cache and Restart
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/
/etc/init.d/uhttpd restart

echo "=== FIX COMPLETE ==="
