#!/bin/sh

echo "Creating PisoWifi directories..."
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/view/pisowifi
mkdir -p /usr/bin
mkdir -p /etc/rc.button
mkdir -p /etc/config
mkdir -p /www/luci-static/resources

echo "Writing Controller..."
cat << 'EOF' > /usr/lib/lua/luci/controller/pisowifi.lua
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
	sys.call(FIREWALL_SCRIPT .. " init")
end

local function read_coin_count()
	local f = io.open(COIN_FILE, "r")
	if not f then return 0 end
	local count = tonumber(f:read("*all"))
	f:close()
	return count or 0
end

local function reset_coin_count()
	local f = io.open(COIN_FILE, "w")
	if f then f:write("0"); f:close() end
end

local function load_sessions()
	local sessions = {}
	local f = io.open(SESSION_FILE, "r")
	if f then
		for line in f:lines() do
			local mac, expiry = line:match("([%x:]+) (%d+)")
			if mac and expiry then sessions[mac] = tonumber(expiry) end
		end
		f:close()
	end
	return sessions
end

local function save_sessions(sessions)
	local f = io.open(SESSION_FILE, "w")
	if f then
		for mac, expiry in pairs(sessions) do f:write(mac .. " " .. expiry .. "\n") end
		f:close()
	end
end

function api_start_coin()
	reset_coin_count()
	init_firewall()
	http.prepare_content("application/json")
	http.write_json({status = "started"})
end

function api_check_coin()
	local count = read_coin_count()
	http.prepare_content("application/json")
	http.write_json({count = count, minutes = count * MINUTES_PER_PESO})
end

function api_connect()
	local mac = get_client_mac()
	if not mac then return end
	local count = read_coin_count()
	if count <= 0 then return end
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

function api_login()
	local mac = get_client_mac()
	if mac then init_firewall(); firewall_allow(mac); http.write_json({status = "success"}) end
end

function api_logout()
	local mac = get_client_mac()
	if mac then firewall_deny(mac); local sessions = load_sessions(); sessions[mac] = nil; save_sessions(sessions); http.write_json({status = "success"}) end
end

function api_status()
	local mac = get_client_mac()
	local authenticated = false
	local time_remaining = 0
	local check = sys.call("iptables -C FORWARD -j " .. CHAIN_NAME .. " 2>/dev/null")
	if check ~= 0 then init_firewall() end
	if mac then
		local sessions = load_sessions()
		local expiry = sessions[mac]
		local now = os.time()
		if expiry and expiry > now then
			local check_mac = sys.call("iptables -C " .. CHAIN_NAME .. " -m mac --mac-source " .. mac .. " -j ACCEPT 2>/dev/null")
			if check_mac == 0 then authenticated = true; time_remaining = expiry - now
			else firewall_allow(mac); authenticated = true; time_remaining = expiry - now end
		elseif expiry and expiry <= now then
			firewall_deny(mac); sessions[mac] = nil; save_sessions(sessions)
		end
	end
	http.prepare_content("application/json")
	http.write_json({authenticated = authenticated, time_remaining = time_remaining, mac = mac, ip = http.getenv("REMOTE_ADDR")})
end

function get_active_users()
	local sessions = load_sessions()
	local users = {}
	local now = os.time()
	for mac, expiry in pairs(sessions) do
		if expiry > now then table.insert(users, {mac = mac, expiry = expiry, remaining = expiry - now}) end
	end
	return users
end

function action_kick()
	local mac = http.formvalue("mac")
	if mac then firewall_deny(mac); local sessions = load_sessions(); sessions[mac] = nil; save_sessions(sessions) end
	http.redirect(luci.dispatcher.build_url("admin", "pisowifi", "dashboard"))
end

_G.get_active_users = get_active_users
EOF

echo "Writing Landing Page..."
cat << 'EOF' > /usr/lib/lua/luci/view/pisowifi/index.htm
<%+header%>
<link rel="stylesheet" href="/luci-static/resources/pisowifi.css">
<div class="pisowifi-container">
    <h1>Welcome to NEXI-FI PISOWIFI</h1>
    <div id="loading">Checking status...</div>
    <div id="login-section" style="display:none;">
        <p>Please insert coin to access the internet.</p>
        <button id="insert-coin-btn" class="pisowifi-btn coin-btn">INSERT COIN</button>
    </div>
    <div id="connected-section" style="display:none;">
        <h2>You are connected!</h2>
        <p>IP: <span id="client-ip"></span> | MAC: <span id="client-mac"></span></p>
        <p>Time Remaining: <span id="time-remaining" style="font-weight:bold; font-size:1.2em;"></span></p>
        <button id="logout-btn" class="pisowifi-btn" style="background-color: #dc3545;">Logout</button>
    </div>
    <div id="coin-modal" class="modal">
        <div class="modal-content">
            <h2>Insert Coin Now</h2>
            <p>Please press the WPS button on the router.</p>
            <p>1 Press = 1 Peso = 12 Minutes</p>
            <div id="coin-display" style="font-size: 24px; margin: 20px;">
                Total: <span id="coin-count">0</span> Pesos<br>
                Time: <span id="coin-time">0</span> Minutes
            </div>
            <button id="connect-btn" class="pisowifi-btn" style="display:none;">Done & Start Internet</button>
            <br>
            <button id="cancel-btn" style="margin-top: 10px; background:none; border:none; color:red; cursor:pointer;">Cancel</button>
        </div>
    </div>
    <hr><a href="<%=luci.dispatcher.build_url("admin", "pisowifi", "dashboard")%>" class="admin-link">Access Admin Dashboard</a>
</div>
<script type="text/javascript">
(function() {
    var apiUrl = "<%=luci.dispatcher.build_url('pisowifi', 'api')%>";
    var coinInterval = null;
    function formatTime(s) { if (s <= 0) return "Expired"; var h = Math.floor(s / 3600); var m = Math.floor((s % 3600) / 60); var sec = s % 60; return h + "h " + m + "m " + sec + "s"; }
    function checkStatus() {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', apiUrl + '/status', true);
        xhr.onload = function() {
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText);
                document.getElementById('loading').style.display = 'none';
                if (data.authenticated) {
                    document.getElementById('login-section').style.display = 'none';
                    document.getElementById('connected-section').style.display = 'block';
                    document.getElementById('client-ip').innerText = data.ip;
                    document.getElementById('client-mac').innerText = data.mac;
                    document.getElementById('time-remaining').innerText = formatTime(data.time_remaining);
                    setTimeout(checkStatus, 10000);
                } else {
                    document.getElementById('login-section').style.display = 'block';
                    document.getElementById('connected-section').style.display = 'none';
                }
            }
        };
        xhr.send();
    }
    document.getElementById('insert-coin-btn').addEventListener('click', function() {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', apiUrl + '/start_coin', true);
        xhr.onload = function() {
            if (xhr.status === 200) {
                document.getElementById('coin-modal').style.display = 'block';
                if (coinInterval) clearInterval(coinInterval);
                coinInterval = setInterval(function() {
                    var x = new XMLHttpRequest();
                    x.open('GET', apiUrl + '/check_coin', true);
                    x.onload = function() {
                        if (x.status === 200) {
                            var d = JSON.parse(x.responseText);
                            document.getElementById('coin-count').innerText = d.count;
                            document.getElementById('coin-time').innerText = d.minutes;
                            if (d.count > 0) document.getElementById('connect-btn').style.display = 'inline-block';
                        }
                    };
                    x.send();
                }, 1000);
            }
        };
        xhr.send();
    });
    document.getElementById('connect-btn').addEventListener('click', function() {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', apiUrl + '/connect', true);
        xhr.onload = function() { if (xhr.status === 200) { document.getElementById('coin-modal').style.display = 'none'; clearInterval(coinInterval); checkStatus(); } };
        xhr.send();
    });
    document.getElementById('cancel-btn').addEventListener('click', function() { document.getElementById('coin-modal').style.display = 'none'; clearInterval(coinInterval); });
    document.getElementById('logout-btn').addEventListener('click', function() {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', apiUrl + '/logout', true);
        xhr.onload = function() { if (xhr.status === 200) checkStatus(); };
        xhr.send();
    });
    checkStatus();
})();
</script>
<%+footer%>
EOF

echo "Writing Admin Page..."
cat << 'EOF' > /usr/lib/lua/luci/view/pisowifi/admin.htm
<%+header%>
<h2 name="content">PisoWifi Dashboard</h2>
<div class="cbi-map">
	<fieldset class="cbi-section">
		<legend>System Status</legend>
		<table class="cbi-section-table">
			<tr class="cbi-section-table-row"><th class="cbi-section-table-cell">Hostname</th><td class="cbi-section-table-cell"><%=luci.sys.hostname()%></td></tr>
			<tr class="cbi-section-table-row"><th class="cbi-section-table-cell">Uptime</th><td class="cbi-section-table-cell"><%=luci.sys.uptime()%></td></tr>
		</table>
	</fieldset>
	<fieldset class="cbi-section">
		<legend>Active Sessions</legend>
		<table class="cbi-section-table">
			<tr class="cbi-section-table-titles"><th class="cbi-section-table-cell">MAC Address</th><th class="cbi-section-table-cell">Remaining Time</th><th class="cbi-section-table-cell">Action</th></tr>
			<% 
			local users = {}
			if get_active_users then users = get_active_users() else require "luci.controller.pisowifi"; if get_active_users then users = get_active_users() end end
			for i, v in ipairs(users) do 
                local m = math.floor(v.remaining / 60)
			%>
			<tr class="cbi-section-table-row">
				<td class="cbi-section-table-cell"><%=v.mac%></td>
				<td class="cbi-section-table-cell"><%=m%> minutes</td>
				<td class="cbi-section-table-cell">
					<form action="<%=luci.dispatcher.build_url("admin", "pisowifi", "kick")%>" method="post">
						<input type="hidden" name="mac" value="<%=v.mac%>" /><input type="submit" class="cbi-button cbi-button-remove" value="Kick" />
					</form>
				</td>
			</tr>
			<% end %>
		</table>
	</fieldset>
</div>
<%+footer%>
EOF

echo "Writing Firewall Script..."
cat << 'EOF' > /usr/bin/pisowifi_firewall.sh
#!/bin/sh
CMD=$1
MAC=$2
IP="10.0.0.1"
IFACE="br-lan"
init() {
    iptables -D FORWARD -j PISOWIFI_AUTH 2>/dev/null
    iptables -F PISOWIFI_AUTH 2>/dev/null
    iptables -X PISOWIFI_AUTH 2>/dev/null
    iptables -t nat -D PREROUTING -j PISOWIFI_NAT 2>/dev/null
    iptables -t nat -F PISOWIFI_NAT 2>/dev/null
    iptables -t nat -X PISOWIFI_NAT 2>/dev/null
    iptables -N PISOWIFI_AUTH
    iptables -I FORWARD -j PISOWIFI_AUTH
    iptables -A PISOWIFI_AUTH -p udp --dport 53 -j ACCEPT
    iptables -A PISOWIFI_AUTH -p tcp --dport 53 -j ACCEPT
    iptables -A PISOWIFI_AUTH -p udp --dport 67:68 -j ACCEPT
    iptables -t nat -N PISOWIFI_NAT
    iptables -t nat -I PREROUTING -i $IFACE -j PISOWIFI_NAT
    iptables -t nat -A PISOWIFI_NAT -p tcp --dport 80 -j DNAT --to-destination $IP:80
    iptables -A PISOWIFI_AUTH -j DROP
}
allow() {
    [ -z "$MAC" ] && return
    iptables -I PISOWIFI_AUTH 1 -m mac --mac-source $MAC -j ACCEPT
    iptables -t nat -I PISOWIFI_NAT 1 -m mac --mac-source $MAC -j RETURN
}
deny() {
    [ -z "$MAC" ] && return
    iptables -D PISOWIFI_AUTH -m mac --mac-source $MAC -j ACCEPT 2>/dev/null
    iptables -t nat -D PISOWIFI_NAT -m mac --mac-source $MAC -j RETURN 2>/dev/null
}
case "$CMD" in
    init) init ;;
    allow) allow ;;
    deny) deny ;;
esac
EOF

echo "Writing Button Script..."
cat << 'EOF' > /etc/rc.button/wps
#!/bin/sh
[ "$ACTION" = "pressed" ] || exit 0
FILE="/tmp/pisowifi_coins"
if [ ! -f "$FILE" ]; then echo "0" > "$FILE"; fi
COUNT=$(cat "$FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$FILE"
logger -t pisowifi "Coin inserted via WPS button. Total: $COUNT"
EOF

echo "Writing CSS..."
cat << 'EOF' > /www/luci-static/resources/pisowifi.css
.pisowifi-container { text-align: center; margin-top: 50px; font-family: Arial; }
.pisowifi-btn { display: inline-block; padding: 15px 30px; font-size: 20px; color: white; background: #007bff; border: none; border-radius: 5px; margin: 10px; cursor: pointer; }
.coin-btn { background: #28a745; }
.modal { display: none; position: fixed; z-index: 1; left: 0; top: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.4); }
.modal-content { background: #fff; margin: 15% auto; padding: 20px; width: 80%; max-width: 500px; border-radius: 10px; }
EOF

echo "Setting permissions..."
chmod +x /usr/bin/pisowifi_firewall.sh
chmod +x /etc/rc.button/wps

echo "Finalizing LuCI..."
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/
/etc/init.d/uhttpd restart

echo "SUCCESS! All files installed."
echo "Access at http://10.0.0.1/cgi-bin/luci/pisowifi"
