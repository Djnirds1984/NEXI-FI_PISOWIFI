module("luci.controller.pisowifi", package.seeall)

local sys = require "luci.sys"
local http = require "luci.http"
local util = require "luci.util"
local json = require "luci.jsonc"
local license_model = require "luci.model.pisowifi_license"

-- Define constants
local CHAIN_NAME = "PISOWIFI_AUTH"
local COIN_FILE = "/tmp/pisowifi_coins"
local SESSION_FILE = "/tmp/pisowifi.sessions"
local MINUTES_PER_PESO = 12
local FIREWALL_SCRIPT = "/usr/bin/pisowifi_firewall.sh"

function index()
	-- Public Landing Page
	-- Ensure the path matches the one requested: /cgi-bin/luci/pisowifi
	entry({"pisowifi"}, template("pisowifi/index"), "PisoWifi", 1).sysauth = false
	
	-- API Endpoints (Public)
	entry({"pisowifi", "api", "login"}, call("api_login"), nil).sysauth = false -- Legacy/Free login
	entry({"pisowifi", "api", "logout"}, call("api_logout"), nil).sysauth = false
	entry({"pisowifi", "api", "status"}, call("api_status"), nil).sysauth = false
	
	-- Coin Logic Endpoints
	entry({"pisowifi", "api", "start_coin"}, call("api_start_coin"), nil).sysauth = false
	entry({"pisowifi", "api", "check_coin"}, call("api_check_coin"), nil).sysauth = false
	entry({"pisowifi", "api", "connect"}, call("api_connect"), nil).sysauth = false
	
	-- License API endpoints
	entry({"pisowifi", "api", "license_check"}, call("api_license_check"), nil).sysauth = false
	entry({"pisowifi", "api", "license_activate"}, call("api_license_activate"), nil).sysauth = false
	entry({"pisowifi", "api", "license_status"}, call("api_license_status"), nil).sysauth = false
	
	-- Admin Dashboard (Protected)
	entry({"admin", "pisowifi"}, alias("admin", "pisowifi", "dashboard"), "PisoWifi Admin", 60)
	entry({"admin", "pisowifi", "dashboard"}, template("pisowifi/admin"), "Dashboard", 1)
	entry({"admin", "pisowifi", "settings"}, cbi("pisowifi/settings"), "Settings", 2)
	entry({"admin", "pisowifi", "users"}, call("action_users"), "Users", 3)
	entry({"admin", "pisowifi", "kick"}, call("action_kick"), nil)
	entry({"admin", "pisowifi", "sync_centralized"}, call("action_sync_centralized"), nil)
	entry({"admin", "pisowifi", "sync_devices"}, call("action_sync_devices"), nil)
end

-- Helpers
local function get_client_mac()
	local ip = http.getenv("REMOTE_ADDR")
	if not ip then return nil end
	local mac = sys.net.ip4mac(ip)
	return mac and mac:upper() or nil
end

local function firewall_allow(mac)
	if not mac then return false end
	sys.call(FIREWALL_SCRIPT .. " allow " .. mac)
	return true
end

local function firewall_deny(mac)
	if not mac then return false end
	sys.call(FIREWALL_SCRIPT .. " deny " .. mac)
	return true
end

local function init_firewall()
	-- Check if chain exists or just run init to be safe/idempotent
	-- The script handles idempotency
	sys.call(FIREWALL_SCRIPT .. " init")
end

-- Coin & Session Helpers
local function read_coin_count()
	local f = io.open(COIN_FILE, "r")
	if not f then return 0 end
	local count = tonumber(f:read("*all"))
	f:close()
	return count or 0
end

local function reset_coin_count()
	local f = io.open(COIN_FILE, "w")
	if f then
		f:write("0")
		f:close()
	end
end

local function load_sessions()
	local sessions = {}
	-- Use SQLite database instead of file
	local db_file = "/etc/pisowifi/pisowifi.db"
	local current_time = os.time()
	local cmd = string.format("sqlite3 %s 'SELECT mac, session_end FROM users WHERE session_end > %d'", db_file, current_time)
	
	sys.exec("logger -t pisowifi 'load_sessions: Executing command: " .. cmd .. "'")
	local result = sys.exec(cmd)
	sys.exec("logger -t pisowifi 'load_sessions: Raw result: " .. (result or "nil") .. "'")
	
	local count = 0
	for line in result:gmatch("[^\n]+") do
		local mac, expiry = line:match("([%x:]+)|(%d+)")
		if mac and expiry then
			sessions[mac] = tonumber(expiry)
			count = count + 1
			sys.exec("logger -t pisowifi 'load_sessions: Found session - MAC: " .. mac .. " expiry: " .. expiry .. "'")
		else
			sys.exec("logger -t pisowifi 'load_sessions: Failed to parse line: " .. line .. "'")
		end
	end
	
	sys.exec("logger -t pisowifi 'load_sessions: Total sessions loaded: " .. count .. "'")
	return sessions
end

local function save_sessions(sessions)
	-- No longer needed since we use SQLite database
	-- Sessions are saved directly to database via update_user_session
end

-- API Implementations
function api_start_coin()
	reset_coin_count()
	-- Ensure firewall is initialized when someone tries to use it
	init_firewall()
	http.prepare_content("application/json")
	http.write_json({status = "started"})
end

function api_check_coin()
	local count = read_coin_count()
	http.prepare_content("application/json")
	http.write_json({
		count = count,
		minutes = count * MINUTES_PER_PESO
	})
end

function api_connect()
	local mac = get_client_mac()
	if not mac then
		http.status(400, "Bad Request")
		http.write_json({error = "No MAC"})
		return
	end
	
	-- Check license first
	local hardware_id = license_model.get_hardware_id()
	local license_data = license_model.get_license_status(hardware_id)
	local is_license_valid, license_message = license_model.is_license_valid(license_data)
	
	if not is_license_valid then
		http.status(403, "Forbidden")
		http.write_json({error = "License invalid: " .. license_message})
		return
	end
	
	local count = read_coin_count()
	if count <= 0 then
		http.status(400, "Bad Request")
		http.write_json({error = "No coins inserted"})
		return
	end
	
	local added_minutes = count * MINUTES_PER_PESO
	local now = os.time()
	local sessions = load_sessions()
	
	local current_expiry = sessions[mac] or now
	if current_expiry < now then current_expiry = now end
	
	local new_expiry = current_expiry + (added_minutes * 60)
	sessions[mac] = new_expiry
	save_sessions(sessions)
	
	reset_coin_count()
	
	init_firewall()
	firewall_allow(mac)
	
	http.prepare_content("application/json")
	http.write_json({status = "connected", expiry = new_expiry})
end

-- Legacy/Free login (Optional, can be removed if strictly coin-only)
function api_login()
	-- For testing purposes or if you want free access option
	local mac = get_client_mac()
	if mac then
		init_firewall()
		firewall_allow(mac)
		http.write_json({status = "success"})
	end
end

function api_logout()
	local mac = get_client_mac()
	if mac then
		firewall_deny(mac)
		-- Remove from database instead of file
		local db_file = "/etc/pisowifi/pisowifi.db"
		sys.exec(string.format("sqlite3 %s 'UPDATE users SET session_end=0 WHERE mac=\"%s\"'", db_file, mac))
		http.write_json({status = "success"})
	end
end

function api_status()
	local mac = get_client_mac()
	local authenticated = false
	local time_remaining = 0
	
	-- Check license first
	local hardware_id = license_model.get_hardware_id()
	local license_data = license_model.get_license_status(hardware_id)
	local is_license_valid, license_message = license_model.is_license_valid(license_data)
	
	if not is_license_valid then
		-- License is invalid or expired
		http.prepare_content("application/json")
		http.write_json({
			authenticated = false,
			time_remaining = 0,
			mac = mac,
			ip = http.getenv("REMOTE_ADDR"),
			license_status = "invalid",
			license_message = license_message
		})
		return
	end
	
	-- Check if firewall initialized, if not init it (for status check from captive portal)
	-- init_firewall() -- Maybe too heavy to call on every status check?
	-- Let's check if chain exists using iptables -C
	local check = sys.call("iptables -C FORWARD -j " .. CHAIN_NAME .. " 2>/dev/null")
	if check ~= 0 then
		-- Only init if not exists
		init_firewall()
	end
	
	if mac then
		local sessions = load_sessions()
		local expiry = sessions[mac]
		local now = os.time()
		
		if expiry and expiry > now then
			-- Check if allowed in firewall
			local check_mac = sys.call("iptables -C " .. CHAIN_NAME .. " -m mac --mac-source " .. mac .. " -j ACCEPT 2>/dev/null")
			if check_mac == 0 then
				authenticated = true
				time_remaining = expiry - now
			else
				-- Session valid but firewall rule missing (maybe rebooted)
				-- Restore rule
				firewall_allow(mac)
				authenticated = true
				time_remaining = expiry - now
			end
		elseif expiry and expiry <= now then
			if expiry then
				firewall_deny(mac)
				sessions[mac] = nil
				save_sessions(sessions)
			end
		end
	end
	
	http.prepare_content("application/json")
	http.write_json({
		authenticated = authenticated,
		time_remaining = time_remaining,
		mac = mac,
		ip = http.getenv("REMOTE_ADDR"),
		license_status = "valid",
		license_message = license_message
	})
end

function get_active_users()
	local sessions = load_sessions()
	local users = {}
	local now = os.time()
	
	-- Debug logging
	sys.exec("logger -t pisowifi 'get_active_users: Found ' .. tostring(#sessions) .. ' sessions in load_sessions()'")
	
	for mac, expiry in pairs(sessions) do
		if expiry > now then
			-- Get hostname from dnsmasq
			local hostname = "Unknown"
			local hostname_cmd = "cat /tmp/dhcp.leases 2>/dev/null | grep -i '" .. mac .. "' | awk '{print $4}' | head -1"
			local hostname_result = sys.exec(hostname_cmd)
			if hostname_result and hostname_result:gsub("%s+", "") ~= "" then
				hostname = hostname_result:gsub("%s+", "")
			end
			
			-- Get session token from database
			local token = ""
			local db_file = "/etc/pisowifi/pisowifi.db"
			local token_cmd = "sqlite3 " .. db_file .. " 'SELECT token FROM users WHERE mac=\"" .. mac .. "\" AND session_end > " .. now .. " LIMIT 1'"
			local token_result = sys.exec(token_cmd)
			if token_result and token_result:gsub("%s+", "") ~= "" then
				token = token_result:gsub("%s+", "")
			end
			
			table.insert(users, {
				mac = mac, 
				expiry = expiry, 
				remaining = expiry - now,
				hostname = hostname,
				token = token
			})
			sys.exec("logger -t pisowifi 'Active user: ' .. mac .. ' (' .. hostname .. ') expires in ' .. tostring(expiry - now) .. ' seconds'")
		end
	end
	
	sys.exec("logger -t pisowifi 'get_active_users: Returning ' .. tostring(#users) .. ' active users'")
	return users
end

-- Test function to check database connectivity
function test_db_connection()
	local db_file = "/etc/pisowifi/pisowifi.db"
	local test_cmd = "sqlite3 " .. db_file .. " 'SELECT COUNT(*) FROM users'"
	local result = sys.exec(test_cmd)
	sys.exec("logger -t pisowifi 'DB Test: users table count = " .. (result or "nil") .. "'")
	
	local test_cmd2 = "sqlite3 " .. db_file .. " 'SELECT mac, session_end FROM users WHERE session_end > " .. os.time() .. " LIMIT 5'"
	local result2 = sys.exec(test_cmd2)
	sys.exec("logger -t pisowifi 'DB Test: active sessions = " .. (result2 or "nil") .. "'")
	
	return result, result2
end

-- Sync with centralized vendor system
function sync_with_centralized_vendor()
	local hardware_id = license_model.get_hardware_id()
	if not hardware_id then
		return false, "No hardware ID available"
	end
	
	-- Get current license status
	local license_data = license_model.get_license_status(hardware_id)
	if not license_data or not license_data.vendor_uuid then
		return false, "No vendor UUID available"
	end
	
	-- Prepare vendor sync data
	local machine_name = sys.hostname() or "PisoWifi-Machine"
	local vendor_body = {
		hardware_id = hardware_id,
		machine_name = machine_name,
		vendor_id = license_data.vendor_uuid,
		license_key = license_data.license_key or "",
		is_licensed = (license_data.status == "active"),
		activated_at = license_data.activated_at or os.date("!%Y-%m-%dT%H:%M:%SZ"),
		status = "online"
	}
	
	-- Convert to JSON
	local json_body = json.stringify(vendor_body)
	
	-- Sync to centralized vendor system
	local curl_cmd = string.format(
		"curl -s -X POST '%s/rest/v1/vendors' " ..
		"-H 'apikey: %s' " ..
		"-H 'Authorization: Bearer %s' " ..
		"-H 'Content-Type: application/json' " ..
		"-H 'Prefer: return=representation' " ..
		"-d '%s'",
		"https://fuiabtdflbodglfexvln.supabase.co",
		"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo",
		"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo",
		json_body
	)
	
	local result = sys.exec(curl_cmd)
	local response_data = json.parse(result)
	
	if response_data and response_data.error then
		return false, response_data.error
	elseif response_data and response_data[1] then
		-- Sync WiFi devices to centralized system
		sync_wifi_devices_to_centralized(license_data.vendor_uuid)
		return true, "Successfully synced with centralized vendor system"
	else
		return false, "Unknown error during vendor sync"
	end
end

-- Sync WiFi devices to centralized wifi_devices table
function sync_wifi_devices_to_centralized(vendor_uuid)
	if not vendor_uuid then
		return false, "No vendor UUID provided"
	end
	
	-- Get all active WiFi devices from local database
	local db_file = "/etc/pisowifi/pisowifi.db"
	local devices_query = string.format(
		"sqlite3 %s 'SELECT mac, session_start, session_end, ip_address FROM users WHERE session_end > %d'",
		db_file, os.time()
	)
	
	local devices_result = sys.exec(devices_query)
	if not devices_result or devices_result == "" then
		return true, "No active devices to sync"
	end
	
	-- Parse devices and sync each one
	local devices_synced = 0
	for line in devices_result:gmatch("[^\r\n]+") do
		local mac, session_start, session_end, ip_address = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)")
		if mac then
			-- Get hostname from dnsmasq
			local hostname = "Unknown"
			local hostname_cmd = string.format("grep '%s' /tmp/dhcp.leases | awk '{print $4}' | head -1", mac:lower())
			local hostname_result = sys.exec(hostname_cmd)
			if hostname_result and hostname_result ~= "" then
				hostname = hostname_result:gsub("%s+", "")
			end
			
			-- Prepare device sync data
			local device_body = {
				vendor_id = vendor_uuid,
				mac_address = mac:upper(),
				device_name = hostname,
				ip_address = ip_address or "Unknown",
				session_start = tonumber(session_start) or os.time(),
				session_end = tonumber(session_end) or (os.time() + 3600),
				last_seen = os.date("!%Y-%m-%dT%H:%M:%SZ"),
				status = "active"
			}
			
			-- Convert to JSON
			local json_body = json.stringify(device_body)
			
			-- Sync device to centralized wifi_devices table
			local device_curl_cmd = string.format(
				"curl -s -X POST '%s/rest/v1/wifi_devices' " ..
				"-H 'apikey: %s' " ..
				"-H 'Authorization: Bearer %s' " ..
				"-H 'Content-Type: application/json' " ..
				"-H 'Prefer: return=representation' " ..
				"-d '%s'",
				"https://fuiabtdflbodglfexvln.supabase.co",
				"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo",
				"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo",
				json_body
			)
			
			local device_result = sys.exec(device_curl_cmd)
			local device_response = json.parse(device_result)
			
			if device_response and not device_response.error then
				devices_synced = devices_synced + 1
			end
		end
	end
	
	return true, string.format("Successfully synced %d devices to centralized system", devices_synced), devices_synced
end

function action_kick()
	local mac = http.formvalue("mac")
	if mac then
		firewall_deny(mac)
		-- Remove from database instead of file
		local db_file = "/etc/pisowifi/pisowifi.db"
		sys.exec(string.format("sqlite3 %s 'UPDATE users SET session_end=0 WHERE mac=\"%s\"'", db_file, mac))
	end
	http.redirect(luci.dispatcher.build_url("admin", "pisowifi", "dashboard"))
end

function action_sync_centralized()
	local success, message = sync_with_centralized_vendor()
	
	http.prepare_content("application/json")
	if success then
		http.write_json({
			success = true,
			message = message
		})
	else
		http.status(400, "Bad Request")
		http.write_json({
			success = false,
			error = message
		})
	end
end

-- Sync only WiFi devices to centralized system
function action_sync_devices()
	local hardware_id = license_model.get_hardware_id()
	if not hardware_id then
		http.status(500, "Internal Server Error")
		http.write_json({error = "Could not determine hardware ID"})
		return
	end
	
	-- Get current license status
	local license_data = license_model.get_license_status(hardware_id)
	if not license_data or not license_data.vendor_uuid then
		http.status(400, "Bad Request")
		http.write_json({error = "No vendor UUID available - please activate license first"})
		return
	end
	
	-- Sync devices to centralized system
	local success, message, devices_synced = sync_wifi_devices_to_centralized(license_data.vendor_uuid)
	
	http.prepare_content("application/json")
	if success then
		http.write_json({
			success = true,
			message = message,
			devices_synced = devices_synced or 0
		})
	else
		http.status(400, "Bad Request")
		http.write_json({
			success = false,
			error = message
		})
	end
end

-- New License API endpoints
function api_license_check()
	local hardware_id = license_model.get_hardware_id()
	local result = license_model.check_license(hardware_id)
	http.prepare_content("application/json")
	http.write_json(result)
end

function api_license_activate()
	local hardware_id = license_model.get_hardware_id()
	local license_key = http.formvalue("license_key")
	local ip_address = http.getenv("REMOTE_ADDR")
	
	local result = license_model.activate_license(hardware_id, license_key, ip_address)
	http.prepare_content("application/json")
	http.write_json(result)
end

function api_license_status()
	local hardware_id = license_model.get_hardware_id()
	local license_data = license_model.get_license_status(hardware_id)
	local is_valid, message = license_model.is_license_valid(license_data)
	
	http.prepare_content("application/json")
	http.write_json({
		status = is_valid and "valid" or (license_data and "invalid" or "no_license"),
		message = message,
		hardware_id = hardware_id,
		license_data = license_data
	})
end

_G.get_active_users = get_active_users
