module("luci.controller.pisowifi", package.seeall)

local sys = require "luci.sys"
local http = require "luci.http"
local util = require "luci.util"
local json = require "luci.jsonc"

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
	
	-- Admin Dashboard (Protected)
	entry({"admin", "pisowifi"}, alias("admin", "pisowifi", "dashboard"), "PisoWifi Admin", 60)
	entry({"admin", "pisowifi", "dashboard"}, template("pisowifi/admin"), "Dashboard", 1)
	entry({"admin", "pisowifi", "users"}, call("action_users"), "Users", 2)
	entry({"admin", "pisowifi", "kick"}, call("action_kick"), nil)
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
	local f = io.open(SESSION_FILE, "r")
	if f then
		for line in f:lines() do
			local mac, expiry = line:match("([%x:]+) (%d+)")
			if mac and expiry then
				sessions[mac] = tonumber(expiry)
			end
		end
		f:close()
	end
	return sessions
end

local function save_sessions(sessions)
	local f = io.open(SESSION_FILE, "w")
	if f then
		for mac, expiry in pairs(sessions) do
			f:write(mac .. " " .. expiry .. "\n")
		end
		f:close()
	end
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
		local sessions = load_sessions()
		sessions[mac] = nil
		save_sessions(sessions)
		http.write_json({status = "success"})
	end
end

function api_status()
	local mac = get_client_mac()
	local authenticated = false
	local time_remaining = 0
	
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
		ip = http.getenv("REMOTE_ADDR")
	})
end

function get_active_users()
	local sessions = load_sessions()
	local users = {}
	local now = os.time()
	for mac, expiry in pairs(sessions) do
		if expiry > now then
			table.insert(users, {mac = mac, expiry = expiry, remaining = expiry - now})
		end
	end
	return users
end

function action_kick()
	local mac = http.formvalue("mac")
	if mac then
		firewall_deny(mac)
		local sessions = load_sessions()
		sessions[mac] = nil
		save_sessions(sessions)
	end
	http.redirect(luci.dispatcher.build_url("admin", "pisowifi", "dashboard"))
end

_G.get_active_users = get_active_users
