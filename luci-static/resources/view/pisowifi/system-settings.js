'use strict';
'require view';
'require ui';
'require form';
'require uci';
'require rpc';
'require network';
'require firewall';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('system'),
			uci.load('network'),
			uci.load('wireless'),
			uci.load('firewall'),
			uci.load('dhcp'),
			uci.load('uhttpd'),
			uci.load('rpcd'),
			network.getDevices(),
			network.getNetworks(),
			firewall.getZones()
		]);
	},

	render: function() {
		var m, s, o, ss;
		var devices = this.devices = arguments[7];
		var networks = this.networks = arguments[8];
		var zones = this.zones = arguments[9];

		// System Settings
		m = new form.Map('system', 'System Settings', 'Configure system-wide settings and parameters');
		
		s = m.section(form.TypedSection, 'system', 'System Configuration');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, 'hostname', 'Hostname');
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (!value || value.length < 1) return ['Hostname is required'];
			if (!/^[a-zA-Z0-9.-]+$/.test(value)) return ['Invalid hostname format'];
			return true;
		};

		o = s.option(form.Value, 'timezone', 'Timezone');
		o.value('Asia/Manila', 'Asia/Manila (UTC+8)');
		o.value('UTC', 'UTC');
		o.value('EST', 'Eastern Standard Time');
		o.value('PST', 'Pacific Standard Time');
		o.default = 'Asia/Manila';
		o.rmempty = false;

		o = s.option(form.Value, 'zonename', 'Zone Name');
		o.default = 'Asia/Manila';
		o.rmempty = true;

		o = s.option(form.TextValue, 'description', 'System Description');
		o.rmempty = true;
		o.rows = 3;

		o = s.option(form.Flag, 'log_ip', 'Log IP Addresses');
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'log_port', 'Log Port Numbers');
		o.default = '1';
		o.rmempty = false;

		// Network Settings
		m = new form.Map('network', 'Network Settings', 'Configure network interfaces and settings');
		
		s = m.section(form.GridSection, 'interface', 'Network Interfaces');
		s.anonymous = false;
		s.addremove = true;
		s.nodescriptions = true;
		s.modaltitle = 'Network Interface Configuration';

		o = s.option(form.Flag, 'auto', 'Auto Start');
		o.default = '1';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.ListValue, 'proto', 'Protocol');
		o.value('static', 'Static');
		o.value('dhcp', 'DHCP');
		o.value('pppoe', 'PPPoE');
		o.value('none', 'None');
		o.default = 'dhcp';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'ipaddr', 'IP Address');
		o.datatype = 'ip4addr';
		o.rmempty = true;
		o.depends('proto', 'static');
		o.editable = true;

		o = s.option(form.Value, 'netmask', 'Netmask');
		o.datatype = 'ip4addr';
		o.value('255.255.255.0', '255.255.255.0 (/24)');
		o.value('255.255.0.0', '255.255.0.0 (/16)');
		o.value('255.0.0.0', '255.0.0.0 (/8)');
		o.default = '255.255.255.0';
		o.rmempty = true;
		o.depends('proto', 'static');
		o.editable = true;

		o = s.option(form.Value, 'gateway', 'Gateway');
		o.datatype = 'ip4addr';
		o.rmempty = true;
		o.depends('proto', 'static');
		o.editable = true;

		o = s.option(form.DynamicList, 'dns', 'DNS Servers');
		o.datatype = 'ip4addr';
		o.placeholder = '8.8.8.8';
		o.rmempty = true;
		o.depends('proto', 'static');
		o.editable = true;

		// Wireless Settings
		m = new form.Map('wireless', 'Wireless Settings', 'Configure WiFi networks and parameters');
		
		s = m.section(form.GridSection, 'wifi-device', 'Wireless Devices');
		s.anonymous = false;
		s.addremove = false;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'disabled', 'Disable Device');
		o.default = '0';
		o.rmempty = false;
		o.editable = true;
		o.enabled = '0';
		o.disabled = '1';

		o = s.option(form.Value, 'channel', 'Channel');
		o.datatype = 'uinteger';
		o.placeholder = 'auto';
		o.rmempty = true;
		o.editable = true;

		o = s.option(form.Value, 'txpower', 'Transmit Power (dBm)');
		o.datatype = 'uinteger';
		o.placeholder = 'auto';
		o.rmempty = true;
		o.editable = true;

		o = s.option(form.ListValue, 'hwmode', 'Hardware Mode');
		o.value('11g', '802.11g');
		o.value('11n', '802.11n');
		o.value('11ac', '802.11ac');
		o.value('11ax', '802.11ax');
		o.rmempty = true;
		o.editable = true;

		s = m.section(form.GridSection, 'wifi-iface', 'WiFi Networks');
		s.anonymous = false;
		s.addremove = true;
		s.nodescriptions = true;
		s.modaltitle = 'WiFi Network Configuration';

		o = s.option(form.Flag, 'disabled', 'Disable Network');
		o.default = '0';
		o.rmempty = false;
		o.editable = true;
		o.enabled = '0';
		o.disabled = '1';

		o = s.option(form.Value, 'ssid', 'SSID');
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.ListValue, 'mode', 'Mode');
		o.value('ap', 'Access Point');
		o.value('sta', 'Client');
		o.value('adhoc', 'Ad-Hoc');
		o.value('monitor', 'Monitor');
		o.default = 'ap';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.ListValue, 'encryption', 'Encryption');
		o.value('none', 'None');
		o.value('psk', 'WPA-PSK');
		o.value('psk2', 'WPA2-PSK');
		o.value('psk-mixed', 'WPA/WPA2 Mixed');
		o.value('sae', 'WPA3-SAE');
		o.default = 'psk2';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'key', 'Password');
		o.password = true;
		o.rmempty = true;
		o.depends('encryption', 'psk');
		o.depends('encryption', 'psk2');
		o.depends('encryption', 'psk-mixed');
		o.depends('encryption', 'sae');
		o.editable = true;

		o = s.option(form.DynamicList, 'macfilter', 'MAC Filter');
		o.rmempty = true;
		o.editable = true;

		o = s.option(form.ListValue, 'macfilter_mode', 'MAC Filter Mode');
		o.value('disable', 'Disable');
		o.value('allow', 'Allow List');
		o.value('deny', 'Deny List');
		o.default = 'disable';
		o.rmempty = false;
		o.editable = true;

		// DHCP Settings
		m = new form.Map('dhcp', 'DHCP Settings', 'Configure DHCP server settings');
		
		s = m.section(form.GridSection, 'dhcp', 'DHCP Pools');
		s.anonymous = false;
		s.addremove = true;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'ignore', 'Ignore Interface');
		o.default = '0';
		o.rmempty = false;
		o.editable = true;
		o.enabled = '1';
		o.disabled = '0';

		o = s.option(form.Value, 'start', 'Start Address');
		o.datatype = 'uinteger';
		o.placeholder = '100';
		o.default = '100';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'limit', 'Address Limit');
		o.datatype = 'uinteger';
		o.placeholder = '150';
		o.default = '150';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'leasetime', 'Lease Time');
		o.placeholder = '12h';
		o.default = '12h';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.DynamicList, 'dhcp_option', 'DHCP Options');
		o.placeholder = '3,192.168.1.1';
		o.rmempty = true;
		o.editable = true;

		// Firewall Settings
		m = new form.Map('firewall', 'Firewall Settings', 'Configure firewall rules and zones');
		
		s = m.section(form.GridSection, 'zone', 'Firewall Zones');
		s.anonymous = false;
		s.addremove = true;
		s.nodescriptions = true;

		o = s.option(form.Value, 'name', 'Zone Name');
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Flag, 'input', 'Input Policy');
		o.value('ACCEPT', 'Accept');
		o.value('DROP', 'Drop');
		o.value('REJECT', 'Reject');
		o.default = 'ACCEPT';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Flag, 'output', 'Output Policy');
		o.value('ACCEPT', 'Accept');
		o.value('DROP', 'Drop');
		o.value('REJECT', 'Reject');
		o.default = 'ACCEPT';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Flag, 'forward', 'Forward Policy');
		o.value('ACCEPT', 'Accept');
		o.value('DROP', 'Drop');
		o.value('REJECT', 'Reject');
		o.default = 'DROP';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.DynamicList, 'network', 'Associated Networks');
		o.rmempty = true;
		o.editable = true;

		s = m.section(form.GridSection, 'rule', 'Firewall Rules');
		s.anonymous = false;
		s.addremove = true;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'enabled', 'Enable Rule');
		o.default = '1';
		o.rmempty = false;
		o.editable = true;
		o.enabled = '1';
		o.disabled = '0';

		o = s.option(form.Value, 'name', 'Rule Name');
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.ListValue, 'target', 'Target');
		o.value('ACCEPT', 'Accept');
		o.value('DROP', 'Drop');
		o.value('REJECT', 'Reject');
		o.value('MASQUERADE', 'Masquerade');
		o.default = 'ACCEPT';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.ListValue, 'proto', 'Protocol');
		o.value('tcp', 'TCP');
		o.value('udp', 'UDP');
		o.value('icmp', 'ICMP');
		o.value('all', 'All');
		o.default = 'tcp';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.Value, 'src', 'Source');
		o.placeholder = 'wan';
		o.rmempty = true;
		o.editable = true;

		o = s.option(form.Value, 'dest', 'Destination');
		o.placeholder = 'lan';
		o.rmempty = true;
		o.editable = true;

		o = s.option(form.Value, 'dest_port', 'Destination Port');
		o.datatype = 'port';
		o.placeholder = '80';
		o.rmempty = true;
		o.editable = true;

		// Web Server Settings
		m = new form.Map('uhttpd', 'Web Server Settings', 'Configure HTTP server settings');
		
		s = m.section(form.TypedSection, 'uhttpd', 'HTTP Server');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'disabled', 'Disable Server');
		o.default = '0';
		o.rmempty = false;
		o.enabled = '1';
		o.disabled = '0';

		o = s.option(form.Value, 'listen_http', 'HTTP Port');
		o.datatype = 'port';
		o.placeholder = '80';
		o.default = '80';
		o.rmempty = false;

		o = s.option(form.Value, 'listen_https', 'HTTPS Port');
		o.datatype = 'port';
		o.placeholder = '443';
		o.default = '443';
		o.rmempty = true;

		o = s.option(form.Value, 'redirect_https', 'Redirect to HTTPS');
		o.datatype = 'port';
		o.placeholder = '0';
		o.default = '0';
		o.rmempty = true;

		o = s.option(form.TextValue, 'index_page', 'Index Page');
		o.placeholder = 'index.html';
		o.default = 'index.html';
		o.rmempty = true;
		o.rows = 2;

		o = s.option(form.Flag, 'rfc1918_filter', 'RFC1918 Filter');
		o.default = '1';
		o.rmempty = false;

		// RPC Settings
		m = new form.Map('rpcd', 'RPC Settings', 'Configure RPC daemon settings');
		
		s = m.section(form.TypedSection, 'rpcd', 'RPC Daemon');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'disabled', 'Disable RPC');
		o.default = '0';
		o.rmempty = false;
		o.enabled = '1';
		o.disabled = '0';

		o = s.option(form.Value, 'socket', 'Socket Path');
		o.placeholder = '/var/run/ubus.sock';
		o.default = '/var/run/ubus.sock';
		o.rmempty = false;

		o = s.option(form.Value, 'timeout', 'Timeout');
		o.datatype = 'uinteger';
		o.placeholder = '30';
		o.default = '30';
		o.rmempty = false;

		o = s.option(form.Flag, 'syslog', 'Enable Syslog');
		o.default = '1';
		o.rmempty = false;

		return m.render();
	}
});