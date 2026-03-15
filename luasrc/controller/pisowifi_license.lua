module("luci.controller.pisowifi_license", package.seeall)

local sys = require "luci.sys"
local http = require "luci.http"
local json = require "luci.jsonc"
local license_model = require "luci.model.pisowifi_license"

function index()
    -- License API endpoints
    entry({"pisowifi", "api", "license_check"}, call("api_license_check"), nil).sysauth = false
    entry({"pisowifi", "api", "license_activate"}, call("api_license_activate"), nil).sysauth = false
    entry({"pisowifi", "api", "license_status"}, call("api_license_status"), nil).sysauth = false
    
    -- License management integrated into settings
    entry({"admin", "pisowifi", "settings"}, cbi("pisowifi/settings"), "Settings", 2)
end

-- API: Check license and create trial if needed
function api_license_check()
    local hardware_id = license_model.get_hardware_id()
    local ip_address = http.getenv("REMOTE_ADDR")
    
    if not hardware_id then
        http.status(500, "Internal Server Error")
        http.write_json({error = "Could not determine hardware ID"})
        return
    end
    
    -- Check existing license
    local license_data = license_model.get_license_status(hardware_id)
    
    if not license_data then
        -- No license found, create trial
        local trial_result = license_model.create_trial_license(hardware_id, ip_address)
        if trial_result and not trial_result.error then
            http.prepare_content("application/json")
            http.write_json({
                status = "trial_created",
                hardware_id = hardware_id,
                message = "7-day trial license created",
                trial_days = 7,
                expires_at = trial_result[1] and trial_result[1].expires_at
            })
        else
            http.status(500, "Internal Server Error")
            http.write_json({
                error = "Failed to create trial license",
                details = trial_result and trial_result.error or "Unknown error"
            })
        end
        return
    end
    
    -- License found, check if valid
    local is_valid, message = license_model.is_license_valid(license_data)
    
    http.prepare_content("application/json")
    http.write_json({
        status = is_valid and "valid" or "invalid",
        hardware_id = hardware_id,
        license_data = {
            status = license_data.status,
            expires_at = license_data.expires_at,
            trial_days = license_data.trial_days,
            activated_at = license_data.activated_at,
            vendor_uuid = license_data.vendor_uuid
        },
        message = message
    })
end

-- API: Activate license with key
function api_license_activate()
    local hardware_id = license_model.get_hardware_id()
    local license_key = http.formvalue("license_key")
    local ip_address = http.getenv("REMOTE_ADDR")
    
    if not hardware_id then
        http.status(500, "Internal Server Error")
        http.write_json({error = "Could not determine hardware ID"})
        return
    end
    
    if not license_key then
        http.status(400, "Bad Request")
        http.write_json({error = "License key is required"})
        return
    end
    
    -- Activate license
    local result = license_model.activate_license(hardware_id, license_key, ip_address)
    
    if result and not result.error then
        http.prepare_content("application/json")
        http.write_json({
            status = "activated",
            hardware_id = hardware_id,
            message = "License activated successfully",
            vendor_uuid = result[1] and result[1].vendor_uuid
        })
    else
        http.status(400, "Bad Request")
        http.write_json({
            error = "Failed to activate license",
            details = result and result.error or "Invalid license key"
        })
    end
end

-- API: Get current license status
function api_license_status()
    local hardware_id = license_model.get_hardware_id()
    
    if not hardware_id then
        http.status(500, "Internal Server Error")
        http.write_json({error = "Could not determine hardware ID"})
        return
    end
    
    local license_data = license_model.get_license_status(hardware_id)
    
    if not license_data then
        http.prepare_content("application/json")
        http.write_json({
            status = "no_license",
            hardware_id = hardware_id,
            message = "No license found"
        })
        return
    end
    
    local is_valid, message = license_model.is_license_valid(license_data)
    
    http.prepare_content("application/json")
    http.write_json({
        status = is_valid and "valid" or "invalid",
        hardware_id = hardware_id,
        license_data = {
            status = license_data.status,
            expires_at = license_data.expires_at,
            trial_days = license_data.trial_days,
            activated_at = license_data.activated_at,
            vendor_uuid = license_data.vendor_uuid,
            license_key = license_data.license_key
        },
        message = message
    })
end