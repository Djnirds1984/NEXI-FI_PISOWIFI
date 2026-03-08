module("luci.controller.pisowifi.pisowifi", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"
local http = require "luci.http"

function index()
    if not nixio.fs.access("/etc/config/pisowifi") then
        return
    end

    local page = entry({"admin", "pisowifi"}, firstchild(), _("PisoWiFi"), 60)
    page.dependent = false

    entry({"admin", "pisowifi", "dashboard"}, cbi("pisowifi/dashboard"), _("Dashboard"), 1)
    entry({"admin", "pisowifi", "wifi-setup"}, cbi("pisowifi/wifi-setup"), _("WiFi Setup"), 2)
    entry({"admin", "pisowifi", "hotspot-segments"}, cbi("pisowifi/hotspot-segments"), _("Hotspot Segments"), 3)
    entry({"admin", "pisowifi", "captive-portal"}, cbi("pisowifi/captive-portal"), _("Captive Portal"), 4)
    entry({"admin", "pisowifi", "admin-panel"}, cbi("pisowifi/admin-panel"), _("Admin Panel"), 5)
    entry({"admin", "pisowifi", "system-settings"}, cbi("pisowifi/system-settings"), _("System Settings"), 6)

    -- RPC endpoints for AJAX calls
    entry({"admin", "pisowifi", "rpc"}, call("rpc_handler")).leaf = true
end

function rpc_handler()
    local action = http.formvalue("action")
    local response = {}

    if action == "get_sessions" then
        response = get_sessions()
    elseif action == "get_stats" then
        response = get_system_stats()
    elseif action == "create_voucher" then
        response = create_voucher(http.formvalue())
    elseif action == "get_vouchers" then
        response = get_vouchers()
    elseif action == "delete_voucher" then
        response = delete_voucher(http.formvalue("code"))
    elseif action == "enable_voucher" then
        response = enable_voucher(http.formvalue("code"))
    elseif action == "disable_voucher" then
        response = disable_voucher(http.formvalue("code"))
    else
        response = { error = "Invalid action" }
    end

    http.prepare_content("application/json")
    http.write(json.stringify(response))
end

function get_sessions()
    local sessions_file = "/tmp/pisowifi_sessions.json"
    local sessions = {}

    if fs.access(sessions_file) then
        local content = fs.readfile(sessions_file)
        if content and content ~= "" then
            local ok, data = pcall(json.parse, content)
            if ok and data then
                sessions = data
            end
        end
    end

    return {
        success = true,
        sessions = sessions,
        count = #sessions
    }
end

function get_system_stats()
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

    -- Active sessions
    local sessions = get_sessions()
    stats.active_sessions = sessions.count or 0

    -- Revenue (simulated)
    stats.revenue_today = math.random(100, 500)
    stats.revenue_total = math.random(1000, 5000)

    -- WiFi clients
    local wifi_clients = sys.exec("iw dev | grep -c 'station' 2>/dev/null") or "0"
    stats.wifi_clients = tonumber(wifi_clients) or 0

    return {
        success = true,
        stats = stats
    }
end

function create_voucher(form_data)
    local duration = tonumber(form_data.duration) or 60
    local price = tonumber(form_data.price) or 0
    local code = form_data.code or sys.uniqueid(8):upper()

    local voucher = {
        code = code,
        duration = duration,
        price = price,
        created_at = os.time(),
        used = false,
        used_at = nil,
        used_by = nil
    }

    local vouchers = get_vouchers_raw()
    vouchers[code] = voucher

    local vouchers_file = "/etc/pisowifi/vouchers.json"
    local success = fs.writefile(vouchers_file, json.stringify(vouchers))

    if success then
        return {
            success = true,
            voucher = voucher
        }
    end

    return {
        success = false,
        error = "Failed to save voucher"
    }
end

function get_vouchers()
    local vouchers = get_vouchers_raw()
    local voucher_list = {}

    for code, voucher in pairs(vouchers) do
        table.insert(voucher_list, voucher)
    end

    return {
        success = true,
        vouchers = voucher_list,
        count = #voucher_list
    }
end

function get_vouchers_raw()
    local vouchers_file = "/etc/pisowifi/vouchers.json"
    local vouchers = {}

    if fs.access(vouchers_file) then
        local content = fs.readfile(vouchers_file)
        if content and content ~= "" then
            local ok, data = pcall(json.parse, content)
            if ok and data then
                vouchers = data
            end
        end
    end

    return vouchers
end

function delete_voucher(code)
    local vouchers = get_vouchers_raw()
    
    if vouchers[code] then
        vouchers[code] = nil
        
        local vouchers_file = "/etc/pisowifi/vouchers.json"
        local success = fs.writefile(vouchers_file, json.stringify(vouchers))

        if success then
            return {
                success = true,
                message = "Voucher deleted successfully"
            }
        end
    end

    return {
        success = false,
        error = "Voucher not found"
    }
end

function enable_voucher(code)
    local vouchers = get_vouchers_raw()
    
    if vouchers[code] then
        vouchers[code].used = false
        vouchers[code].used_at = nil
        vouchers[code].used_by = nil
        
        local vouchers_file = "/etc/pisowifi/vouchers.json"
        local success = fs.writefile(vouchers_file, json.stringify(vouchers))

        if success then
            return {
                success = true,
                message = "Voucher enabled successfully"
            }
        end
    end

    return {
        success = false,
        error = "Voucher not found"
    }
end

function disable_voucher(code)
    local vouchers = get_vouchers_raw()
    
    if vouchers[code] then
        vouchers[code].used = true
        vouchers[code].used_at = os.time()
        
        local vouchers_file = "/etc/pisowifi/vouchers.json"
        local success = fs.writefile(vouchers_file, json.stringify(vouchers))

        if success then
            return {
                success = true,
                message = "Voucher disabled successfully"
            }
        end
    end

    return {
        success = false,
        error = "Voucher not found"
    }
end