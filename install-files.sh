#!/bin/sh
# Copy PisoWiFi files to correct locations on OpenWrt

echo "Copying PisoWiFi files to router..."
echo "=================================="
echo ""

# Create directories
echo "1. Creating directories..."
mkdir -p /usr/lib/lua/luci/controller/pisowifi
mkdir -p /usr/lib/lua/luci/model/pisowifi
mkdir -p /www/luci-static/resources/view/pisowifi
mkdir -p /etc/pisowifi
mkdir -p /www/cgi-bin

echo "✓ Directories created"

# Create controller file
echo "2. Creating controller file..."
cat > /usr/lib/lua/luci/controller/pisowifi/pisowifi.lua <<'EOF'
module("luci.controller.pisowifi.pisowifi", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/pisowifi") then
        return
    end

    local page = entry({"admin", "pisowifi"}, firstchild(), _("PisoWiFi"), 60)
    page.dependent = false

    entry({"admin", "pisowifi", "dashboard"}, template("pisowifi/dashboard"), _("Dashboard"), 1)
    entry({"admin", "pisowifi", "wifi-setup"}, template("pisowifi/wifi-setup"), _("WiFi Setup"), 2)
    entry({"admin", "pisowifi", "hotspot-segments"}, template("pisowifi/hotspot-segments"), _("Hotspot Segments"), 3)
    entry({"admin", "pisowifi", "captive-portal"}, template("pisowifi/captive-portal"), _("Captive Portal"), 4)
    entry({"admin", "pisowifi", "admin-panel"}, template("pisowifi/admin-panel"), _("Admin Panel"), 5)
    entry({"admin", "pisowifi", "system-settings"}, template("pisowifi/system-settings"), _("System Settings"), 6)
end
EOF

echo "✓ Controller file created"

# Create model file
echo "3. Creating model file..."
cat > /usr/lib/lua/luci/model/pisowifi/pisowifi.lua <<'EOF'
local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local M = {}

function M.get_config()
    return uci:get_all("pisowifi")
end

function M.save_config(config)
    for section, options in pairs(config) do
        for option, value in pairs(options) do
            uci:set("pisowifi", section, option, value)
        end
    end
    uci:commit("pisowifi")
    return true
end

function M.get_system_stats()
    local stats = {}
    
    -- CPU usage
    local cpu_info = sys.exec("top -bn1 | grep 'CPU:' | awk '{print $2}' | sed 's/%//' 2>/dev/null") or "0"
    stats.cpu_usage = tonumber(cpu_info) or 0
    
    -- Memory usage
    local mem_info = sys.exec("free | grep Mem | awk '{print $3/$2 * 100.0}' 2>/dev/null") or "0"
    stats.memory_usage = tonumber(mem_info) or 0
    
    -- Disk usage
    local disk_info = sys.exec("df / | tail -1 | awk '{print $3/$2 * 100.0}' 2>/dev/null") or "0"
    stats.disk_usage = tonumber(disk_info) or 0
    
    -- WiFi clients
    local wifi_clients = sys.exec("iw dev | grep -c 'station' 2>/dev/null") or "0"
    stats.wifi_clients = tonumber(wifi_clients) or 0
    
    return stats
end

return M
EOF

echo "✓ Model file created"

# Create basic view files
echo "4. Creating basic view files..."
cat > /www/luci-static/resources/view/pisowifi/dashboard.htm <<'EOF'
<%+header%>
<div class="cbi-map">
    <h2>PisoWiFi Dashboard</h2>
    <div class="cbi-map-descr">Welcome to PisoWiFi Management</div>
    <div class="cbi-section">
        <p>Dashboard content will appear here.</p>
    </div>
</div>
<%+footer%>
EOF

cat > /www/luci-static/resources/view/pisowifi/admin-panel.htm <<'EOF'
<%+header%>
<div class="cbi-map">
    <h2>PisoWiFi Admin Panel</h2>
    <div class="cbi-map-descr">Admin Panel</div>
    <div class="cbi-section">
        <p>Admin panel content will appear here.</p>
    </div>
</div>
<%+footer%>
EOF

cat > /www/luci-static/resources/view/pisowifi/system-settings.htm <<'EOF'
<%+header%>
<div class="cbi-map">
    <h2>PisoWiFi System Settings</h2>
    <div class="cbi-map-descr">System Settings</div>
    <div class="cbi-section">
        <p>System settings content will appear here.</p>
    </div>
</div>
<%+footer%>
EOF

echo "✓ Basic view files created"

# Clear LuCI cache
echo "5. Clearing LuCI cache..."
rm -f /tmp/luci-*
echo "✓ LuCI cache cleared"

# Restart uhttpd
echo "6. Restarting web server..."
/etc/init.d/uhttpd restart
echo "✓ Web server restarted"

echo ""
echo "✅ PisoWiFi files installed!"
echo ""
echo "🎯 Test these URLs:"
echo "   LuCI: http://192.168.1.1/cgi-bin/luci"
echo "   PisoWiFi Admin: http://192.168.1.1/cgi-bin/luci/admin/pisowifi"
echo "   Portal: http://192.168.1.1/cgi-bin/pisowifi-portal"