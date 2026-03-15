local json = require "luci.jsonc"
local http = require "luci.http"
local sys = require "luci.sys"

local SUPABASE_URL = "https://fuiabtdflbodglfexvln.supabase.co"
local SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo"

local M = {}

-- Get hardware ID from system
function M.get_hardware_id()
    -- Try to get MAC address from br-lan first, then eth0, then fallback
    local mac = sys.exec("cat /sys/class/net/br-lan/address 2>/dev/null || cat /sys/class/net/eth0/address 2>/dev/null || echo 'unknown'")
    mac = mac:gsub("%s+", "") -- Remove whitespace
    
    if mac == "unknown" or mac == "" then
        -- Fallback to generating a unique ID based on hostname and random
        local hostname = sys.hostname()
        local random = sys.exec("head -c 16 /dev/urandom | md5sum | cut -d' ' -f1")
        mac = hostname .. "-" .. random:gsub("%s+", "")
    end
    
    return mac:upper()
end

-- Check license with Supabase
function M.check_license(hardware_id)
    if not hardware_id then
        return {error = "No hardware ID provided"}
    end
    
    local curl_cmd = string.format(
        "curl -s -X POST '%s/rest/v1/rpc/check_license' " ..
        "-H 'apikey: %s' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-H 'Content-Type: application/json' " ..
        "-d '{\"hardware_id\": \"%s\"}'",
        SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_ANON_KEY, hardware_id
    )
    
    local result = sys.exec(curl_cmd)
    local data = json.parse(result)
    
    return data
end

-- Create trial license
function M.create_trial_license(hardware_id, ip_address)
    if not hardware_id then
        return {error = "No hardware ID provided"}
    end
    
    local expires_at = os.time() + (7 * 24 * 60 * 60) -- 7 days from now
    
    local curl_cmd = string.format(
        "curl -s -X POST '%s/rest/v1/pisowifi_openwrt' " ..
        "-H 'apikey: %s' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-H 'Content-Type: application/json' " ..
        "-H 'Prefer: return=representation' " ..
        "-d '{\"hardware_id\": \"%s\", \"status\": \"trial\", \"trial_days\": 7, \"expires_at\": \"%s\"}'",
        SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_ANON_KEY, hardware_id, os.date("!%Y-%m-%dT%H:%M:%SZ", expires_at)
    )
    
    local result = sys.exec(curl_cmd)
    local data = json.parse(result)
    
    return data
end

-- Activate license
function M.activate_license(hardware_id, license_key, ip_address)
    if not hardware_id or not license_key then
        return {error = "Hardware ID and license key required"}
    end
    
    -- Check if this is a centralized key format (CENTRAL-XXXXXXXX-XXXXXXXX)
    local is_centralized_key = license_key:match("^CENTRAL%-[a-f0-9]+%-[a-f0-9]+$")
    
    -- For centralized keys, validate format and activate as centralized license
    if is_centralized_key then
        local curl_cmd = string.format(
            "curl -s -X POST '%s/rest/v1/rpc/activate_centralized_license' " ..
            "-H 'apikey: %s' " ..
            "-H 'Authorization: Bearer %s' " ..
            "-H 'Content-Type: application/json' " ..
            "-d '{\"hardware_id\": \"%s\", \"centralized_key\": \"%s\", \"ip_address\": \"%s\"}'",
            SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_ANON_KEY, hardware_id, license_key, ip_address or ""
        )
        
        local result = sys.exec(curl_cmd)
        local data = json.parse(result)
        
        return data
    end
    
    -- For regular license keys, use the existing activation logic
    -- Validate regular license key format (can be any format except centralized)
    if license_key:match("^CENTRAL%-") then
        return {error = "Invalid license key format. Centralized keys should use the CENTRAL-XXXXXXXX-XXXXXXXX format"}
    end
    
    local curl_cmd = string.format(
        "curl -s -X POST '%s/rest/v1/rpc/activate_license' " ..
        "-H 'apikey: %s' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-H 'Content-Type: application/json' " ..
        "-d '{\"hardware_id\": \"%s\", \"license_key\": \"%s\", \"ip_address\": \"%s\"}'",
        SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_ANON_KEY, hardware_id, license_key, ip_address or ""
    )
    
    local result = sys.exec(curl_cmd)
    local data = json.parse(result)
    
    -- For regular license keys, use the existing activation logic
    local curl_cmd = string.format(
        "curl -s -X POST '%s/rest/v1/rpc/activate_license' " ..
        "-H 'apikey: %s' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-H 'Content-Type: application/json' " ..
        "-d '{\"hardware_id\": \"%s\", \"license_key\": \"%s\", \"ip_address\": \"%s\"}'",
        SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_ANON_KEY, hardware_id, license_key, ip_address or ""
    )
    
    local result = sys.exec(curl_cmd)
    local data = json.parse(result)
    
    return data
end

-- Get license status
function M.get_license_status(hardware_id)
    if not hardware_id then
        return {error = "No hardware ID provided"}
    end
    
    local curl_cmd = string.format(
        "curl -s -X GET '%s/rest/v1/pisowifi_openwrt?hardware_id=eq.%s' " ..
        "-H 'apikey: %s' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-H 'Content-Type: application/json'",
        SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_ANON_KEY, hardware_id
    )
    
    local result = sys.exec(curl_cmd)
    local data = json.parse(result)
    
    if data and #data > 0 then
        return data[1]
    else
        return nil
    end
end

-- Check if license is valid
function M.is_license_valid(license_data)
    if not license_data then
        return false, "No license found"
    end
    
    if license_data.status == "active" then
        return true, "License is active"
    elseif license_data.status == "trial" then
        if license_data.expires_at then
            local expires_at = os.time(license_data.expires_at)
            if expires_at > os.time() then
                return true, "Trial license is valid"
            else
                return false, "Trial license has expired"
            end
        else
            return true, "Trial license (no expiry)"
        end
    elseif license_data.status == "expired" then
        return false, "License has expired"
    else
        return false, "License is inactive"
    end
end

return M