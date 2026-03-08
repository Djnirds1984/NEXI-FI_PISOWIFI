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
			uci.load('wireless'),
			uci.load('network'),
			uci.load('firewall'),
			uci.load('uhttpd'),
			uci.load('dhcp')
		]);
	},

	render: function() {
		var m, s, o;
		var ssid_2g = '', ssid_5g = '';
		
		var wireless_sections = uci.sections('wireless', 'wifi-iface');
		for (var i = 0; i < wireless_sections.length; i++) {
			var iface = wireless_sections[i];
			if (iface.mode == 'ap') {
				if (iface.device && iface.device.indexOf('radio0') !== -1) {
					ssid_2g = iface.ssid || '';
				} else if (iface.device && iface.device.indexOf('radio1') !== -1) {
					ssid_5g = iface.ssid || '';
				}
			}
		}

		m = new form.Map('pisowifi', 'PisoWiFi Captive Portal', 'Configure captive portal settings for 2.4G and 5G WiFi networks');
		
		s = m.section(form.TypedSection, 'general', 'General Settings');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', 'Enable Captive Portal');
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'portal_url', 'Portal URL', 'URL where users will be redirected for authentication');
		o.default = 'http://192.168.1.1/cgi-bin/pisowifi-portal';
		o.rmempty = false;

		o = s.option(form.Value, 'session_timeout', 'Session Timeout (minutes)', 'Time before user needs to re-authenticate');
		o.datatype = 'uinteger';
		o.default = '60';
		o.rmempty = false;

		o = s.option(form.Value, 'price_per_hour', 'Price per Hour (PHP)', 'Cost for 1 hour of internet access');
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		s = m.section(form.TypedSection, 'wifi_2g', '2.4G WiFi Settings');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'wifi_2g_enabled', 'Enable 2.4G Portal');
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'wifi_2g_ssid', '2.4G SSID', 'Current: ' + (ssid_2g || 'Not configured'));
		o.rmempty = true;

		o = s.option(form.Flag, 'wifi_2g_password_required', 'Require Password for 2.4G');
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'wifi_2g_password', '2.4G Password', 'Leave empty to use current WiFi password');
		o.password = true;
		o.depends('wifi_2g_password_required', '1');

		s = m.section(form.TypedSection, 'wifi_5g', '5G WiFi Settings');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'wifi_5g_enabled', 'Enable 5G Portal');
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'wifi_5g_ssid', '5G SSID', 'Current: ' + (ssid_5g || 'Not configured'));
		o.rmempty = true;

		o = s.option(form.Flag, 'wifi_5g_password_required', 'Require Password for 5G');
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'wifi_5g_password', '5G Password', 'Leave empty to use current WiFi password');
		o.password = true;
		o.depends('wifi_5g_password_required', '1');

		s = m.section(form.TypedSection, 'landing_page', 'Landing Page Settings');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, 'landing_title', 'Landing Page Title');
		o.default = 'Welcome to PisoWiFi';
		o.rmempty = false;

		o = s.option(form.TextValue, 'landing_message', 'Landing Page Message');
		o.default = 'Please insert coin or pay to access the internet';
		o.rmempty = false;
		o.rows = 3;

		o = s.option(form.Value, 'landing_background', 'Background Image URL', 'Optional background image for landing page');
		o.rmempty = true;

		o = s.option(form.Value, 'landing_logo', 'Logo Image URL', 'Optional logo for landing page');
		o.rmempty = true;

		s = m.section(form.TypedSection, 'payment', 'Payment Settings');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.ListValue, 'payment_method', 'Payment Method');
		o.value('coinslot', 'Coin Slot');
		o.value('qr_code', 'QR Code');
		o.value('gcash', 'GCash');
		o.value('both', 'Coin Slot + QR Code');
		o.default = 'coinslot';
		o.rmempty = false;

		o = s.option(form.Value, 'qr_code_image', 'QR Code Image URL', 'QR code image for payment');
		o.rmempty = true;
		o.depends('payment_method', 'qr_code');
		o.depends('payment_method', 'both');

		o = s.option(form.Value, 'gcash_number', 'GCash Number', 'GCash number for payments');
		o.rmempty = true;
		o.depends('payment_method', 'gcash');
		o.depends('payment_method', 'both');

		return m.render();
	}
});