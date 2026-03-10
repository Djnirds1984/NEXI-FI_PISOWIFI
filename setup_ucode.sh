#!/bin/sh

echo "=== INSTALLING PISOWIFI (LUCI-NG / UCODE) ==="

# 1. Create Directories for ucode implementation
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /www/luci-static/resources/view/pisowifi
mkdir -p /usr/libexec/rpcd

# 2. Define Menu Entry (JSON)
# This registers the menu in the new system
cat << 'EOF' > /usr/share/luci/menu.d/pisowifi.json
{
	"admin/pisowifi": {
		"title": "PisoWifi",
		"order": 60,
		"action": {
			"type": "view",
			"path": "pisowifi/dashboard"
		},
		"depends": {
			"acl": [ "luci-app-pisowifi" ]
		}
	},
	"pisowifi": {
		"title": "PisoWifi Portal",
		"order": 1,
		"action": {
			"type": "template",
			"path": "pisowifi/index"
		},
		"public": true
	}
}
EOF

# 3. Define ACL (Access Control List)
# Required for the menu to show up and actions to be allowed
cat << 'EOF' > /usr/share/rpcd/acl.d/luci-app-pisowifi.json
{
	"luci-app-pisowifi": {
		"description": "Grant access to PisoWifi",
		"read": {
			"file": {
				"/tmp/pisowifi_coins": [ "read" ],
				"/tmp/pisowifi.sessions": [ "read" ]
			},
			"ubus": {
				"pisowifi": [ "*" ]
			}
		},
		"write": {
			"file": {
				"/tmp/pisowifi_coins": [ "write" ],
				"/tmp/pisowifi.sessions": [ "write" ]
			},
			"ubus": {
				"pisowifi": [ "*" ]
			}
		}
	}
}
EOF

# 4. Create RPCD Plugin (The Backend Logic)
# This replaces the Lua controller. It exposes ubus methods.
cat << 'EOF' > /usr/libexec/rpcd/pisowifi
#!/bin/sh

. /usr/share/libubox/jshn.sh

case "$1" in
	list)
		json_init
		json_add_object "status"
		json_close_object
		json_add_object "login"
			json_add_string "mac" "mac"
		json_close_object
		json_add_object "logout"
			json_add_string "mac" "mac"
		json_close_object
		json_add_object "kick"
			json_add_string "mac" "mac"
		json_close_object
		json_dump
		json_cleanup
		;;
	call)
		case "$2" in
			status)
				# TODO: Implement status check logic here using shell or call helper
				echo '{ "authenticated": false }'
				;;
			login)
				# TODO: Implement login
				echo '{ "status": "success" }'
				;;
			logout)
				# TODO: Implement logout
				echo '{ "status": "success" }'
				;;
			kick)
				read input
				# Parse input JSON to get mac
				echo '{ "status": "kicked" }'
				;;
		esac
		;;
esac
EOF
chmod +x /usr/libexec/rpcd/pisowifi

# 5. Create View (JavaScript/OpenWrt JS API)
# This replaces the HTML template
cat << 'EOF' > /www/luci-static/resources/view/pisowifi/dashboard.js
'use strict';
'require view';
'require fs';
'require ui';

return view.extend({
	render: function() {
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, 'PisoWifi Dashboard'),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, 'System Status'),
				E('p', {}, 'Welcome to the new JS-based Dashboard')
			])
		]);
	}
});
EOF

# 6. Create Landing Page Template (Legacy HTML fallback for public page)
# LuCI-NG still supports HTML templates for public pages if configured right, 
# but usually it prefers JS views.
# For the captive portal landing page, we might need a raw HTML file in /www
# that talks to ubus via ubus-http or a custom CGI.

# Let's keep the Lua controller for the PUBLIC part if possible, 
# but since you said "404", Lua might be completely disabled for web.

# Workaround: Use a static HTML file for the landing page that calls ubus-http (json-rpc)
# This bypasses LuCI controller requirements.

cat << 'EOF' > /www/pisowifi.html
<!DOCTYPE html>
<html>
<head>
<title>PisoWifi Portal</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font-family: sans-serif; text-align: center; padding: 20px; }
button { padding: 10px 20px; font-size: 1.2em; background: #007bff; color: white; border: none; border-radius: 5px; }
</style>
</head>
<body>
<h1>Welcome to PisoWifi</h1>
<div id="status">Loading...</div>
<button id="coinBtn" onclick="insertCoin()">Insert Coin</button>

<script>
// We need to implement ubus call via HTTP (JSON-RPC) here
// Or simple CGI script if ubus is too complex for raw JS without auth
</script>
</body>
</html>
EOF

echo "Reloading RPCD..."
/etc/init.d/rpcd reload

echo "=== LUCI-NG SETUP DONE ==="
