local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local json = require "luci.jsonc"

local M = {}

function M.get_config()
    local config = {}
    
    -- Load general settings
    config.general = uci:get_all("pisowifi", "general") or {}
    config.wifi_2g = uci:get_all("pisowifi", "wifi_2g") or {}
    config.wifi_5g = uci:get_all("pisowifi", "wifi_5g") or {}
    config.landing_page = uci:get_all("pisowifi", "landing_page") or {}
    config.payment = uci:get_all("pisowifi", "payment") or {}
    config.admin = uci:get_all("pisowifi", "admin") or {}
    config.security = uci:get_all("pisowifi", "security") or {}
    config.access_control = uci:get_all("pisowifi", "access_control") or {}
    config.hotspot_segments = uci:get_all("pisowifi", "segments") or {}
    
    return config
end

function M.save_config(section, options)
    local success = true
    
    -- Create section if it doesn't exist
    if not uci:get("pisowifi", section) then
        uci:section("pisowifi", "config", section)
    end
    
    -- Set options
    for key, value in pairs(options) do
        uci:set("pisowifi", section, key, value)
    end
    
    -- Commit changes
    success = uci:commit("pisowifi")
    
    return success
end

function M.get_sessions()
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
    
    return sessions
end

function M.save_sessions(sessions)
    local sessions_file = "/tmp/pisowifi_sessions.json"
    local success = fs.writefile(sessions_file, json.stringify(sessions))
    return success
end

function M.create_session(session_data)
    local sessions = M.get_sessions()
    
    local session = {
        id = session_data.id or sys.uniqueid(16),
        mac_address = session_data.mac_address,
        ip_address = session_data.ip_address,
        start_time = os.time(),
        duration = tonumber(session_data.duration) or 60,
        end_time = os.time() + (tonumber(session_data.duration) or 60) * 60,
        active = true,
        payment_method = session_data.payment_method or "unknown",
        amount = tonumber(session_data.amount) or 0
    }
    
    table.insert(sessions, session)
    M.save_sessions(sessions)
    
    return session
end

function M.end_session(session_id)
    local sessions = M.get_sessions()
    
    for i, session in ipairs(sessions) do
        if session.id == session_id then
            session.active = false
            session.end_time = os.time()
            M.save_sessions(sessions)
            return true
        end
    end
    
    return false
end

function M.get_active_sessions()
    local sessions = M.get_sessions()
    local active_sessions = {}
    local current_time = os.time()
    
    for i, session in ipairs(sessions) do
        if session.active and session.end_time > current_time then
            table.insert(active_sessions, session)
        end
    end
    
    return active_sessions
end

function M.get_vouchers()
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

function M.save_vouchers(vouchers)
    local vouchers_file = "/etc/pisowifi/vouchers.json"
    local success = fs.writefile(vouchers_file, json.stringify(vouchers))
    return success
end

function M.create_voucher(voucher_data)
    local vouchers = M.get_vouchers()
    
    local voucher = {
        code = voucher_data.code or sys.uniqueid(8):upper(),
        duration = tonumber(voucher_data.duration) or 60,
        price = tonumber(voucher_data.price) or 0,
        created_at = os.time(),
        used = false,
        used_at = nil,
        used_by = nil
    }
    
    vouchers[voucher.code] = voucher
    M.save_vouchers(vouchers)
    
    return voucher
end

function M.use_voucher(code, mac_address, ip_address)
    local vouchers = M.get_vouchers()
    
    if vouchers[code] and not vouchers[code].used then
        -- Mark voucher as used
        vouchers[code].used = true
        vouchers[code].used_at = os.time()
        vouchers[code].used_by = mac_address
        
        -- Create session
        local session_data = {
            mac_address = mac_address,
            ip_address = ip_address,
            duration = vouchers[code].duration,
            payment_method = "voucher",
            amount = vouchers[code].price
        }
        
        local session = M.create_session(session_data)
        
        M.save_vouchers(vouchers)
        
        return {
            success = true,
            session = session,
            voucher = vouchers[code]
        }
    end
    
    return {
        success = false,
        error = "Voucher not found or already used"
    }
end

function M.delete_voucher(code)
    local vouchers = M.get_vouchers()
    
    if vouchers[code] then
        vouchers[code] = nil
        M.save_vouchers(vouchers)
        return true
    end
    
    return false
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
    
    -- Active sessions
    local active_sessions = M.get_active_sessions()
    stats.active_sessions = #active_sessions
    
    -- Revenue (calculated from sessions)
    local sessions = M.get_sessions()
    local revenue_today = 0
    local revenue_total = 0
    local today_start = os.time() - (os.time() % 86400) -- Start of today
    
    for i, session in ipairs(sessions) do
        if session.amount then
            revenue_total = revenue_total + session.amount
            if session.start_time >= today_start then
                revenue_today = revenue_today + session.amount
            end
        end
    end
    
    stats.revenue_today = revenue_today
    stats.revenue_total = revenue_total
    
    -- WiFi clients
    local wifi_clients = sys.exec("iw dev | grep -c 'station' 2>/dev/null") or "0"
    stats.wifi_clients = tonumber(wifi_clients) or 0
    
    -- Uptime
    stats.uptime = sys.exec("uptime | awk '{print $3,$4}' | sed 's/,//' 2>/dev/null") or "unknown"
    
    return stats
end

function M.get_wifi_info()
    local wifi_info = {}
    
    -- Get wireless configuration
    local wireless_config = uci:get_all("wireless")
    if wireless_config then
        for section_name, section in pairs(wireless_config) do
            if section[".type"] == "wifi-device" then
                wifi_info.devices = wifi_info.devices or {}
                wifi_info.devices[section_name] = {
                    type = section.type,
                    channel = section.channel,
                    hwmode = section.hwmode,
                    htmode = section.htmode,
                    disabled = section.disabled
                }
            elseif section[".type"] == "wifi-iface" then
                wifi_info.interfaces = wifi_info.interfaces or {}
                wifi_info.interfaces[section_name] = {
                    device = section.device,
                    network = section.network,
                    mode = section.mode,
                    ssid = section.ssid,
                    encryption = section.encryption,
                    key = section.key,
                    disabled = section.disabled
                }
            end
        end
    end
    
    return wifi_info
end

function M.save_wifi_info(wifi_data)
    local success = true
    
    -- Update wireless configuration
    if wifi_data.devices then
        for device_name, device_config in pairs(wifi_data.devices) do
            for key, value in pairs(device_config) do
                uci:set("wireless", device_name, key, value)
            end
        end
    end
    
    if wifi_data.interfaces then
        for iface_name, iface_config in pairs(wifi_data.interfaces) do
            for key, value in pairs(iface_config) do
                uci:set("wireless", iface_name, key, value)
            end
        end
    end
    
    -- Commit changes
    success = uci:commit("wireless")
    
    if success then
        -- Restart wireless service
        sys.call("/etc/init.d/wireless restart")
    end
    
    return success
end

function M.authenticate_admin(username, password)
    local config = M.get_config()
    local admin_config = config.admin or {}
    
    -- Default credentials
    local default_username = admin_config.username or "admin"
    local default_password = admin_config.password or "$1$admin$1$" -- admin
    
    if username == default_username then
        -- Simple password check (in production, use proper password hashing)
        if password == "admin" then
            return true
        end
    end
    
    return false
end

function M.get_admin_sessions()
    local sessions_file = "/tmp/pisowifi_admin_sessions.json"
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
    
    return sessions
end

function M.save_admin_sessions(sessions)
    local sessions_file = "/tmp/pisowifi_admin_sessions.json"
    local success = fs.writefile(sessions_file, json.stringify(sessions))
    return success
end

function M.create_admin_session(username)
    local sessions = M.get_admin_sessions()
    
    local session = {
        id = sys.uniqueid(32),
        username = username,
        created_at = os.time(),
        last_activity = os.time(),
        ip_address = os.getenv("REMOTE_ADDR") or "unknown"
    }
    
    table.insert(sessions, session)
    M.save_admin_sessions(sessions)
    
    return session
end

function M.validate_admin_session(session_id)
    local sessions = M.get_admin_sessions()
    local current_time = os.time()
    local session_timeout = 1800 -- 30 minutes
    
    for i, session in ipairs(sessions) do
        if session.id == session_id then
            -- Check if session is still valid
            if (current_time - session.last_activity) < session_timeout then
                -- Update last activity
                session.last_activity = current_time
                M.save_admin_sessions(sessions)
                return session
            else
                -- Session expired, remove it
                table.remove(sessions, i)
                M.save_admin_sessions(sessions)
                return nil
            end
        end
    end
    
    return nil
end

function M.delete_admin_session(session_id)
    local sessions = M.get_admin_sessions()
    
    for i, session in ipairs(sessions) do
        if session.id == session_id then
            table.remove(sessions, i)
            M.save_admin_sessions(sessions)
            return true
        end
    end
    
    return false
end

return M