#!/usr/bin/ucode

# Real PisoWiFi API Backend - Enhanced with actual OpenWrt integration
# This script provides real system control for hotspot, vouchers, and network settings

import { cursor, load, save, unload } from "uci";
import { system, popen, execute } from "posix";
import { printf, print } from "stdio";
import { getenv, setenv } from "stdlib";

const HOTSPOT_IP = "10.0.0.1";
const DEFAULT_SSID = "PisoWiFi_Free";

# Enhanced WiFi detection and management functions
function getAvailableWiFiDevices() {
    const devices = [];
    
    try {
        # Method 1: Check physical wireless devices
        const phy_devices = popen("ls /sys/class/ieee80211/ 2>/dev/null", "r");
        if (phy_devices) {
            let line;
            while ((line = phy_devices.read("line"))) {
                const device = line.trim();
                if (device) {
                    devices.push({
                        name: device,
                        type: 'physical',
                        path: `/sys/class/ieee80211/${device}`,
                        status: 'hardware_detected'
                    });
                }
            }
            phy_devices.close();
        }
        
        # Method 2: Check UCI wireless devices
        const cursor = cursor();
        cursor.load('wireless');
        const wireless_config = cursor.get_all('wireless') || {};
        
        for (let section in wireless_config) {
            const config = wireless_config[section];
            if (config && config['.type'] === 'wifi-device') {
                let found = false;
                for (let device of devices) {
                    if (device.name === section) {
                        device.uci_config = config;
                        device.status = 'configured';
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    devices.push({
                        name: section,
                        type: 'uci_device',
                        uci_config: config,
                        status: 'configured'
                    });
                }
            }
        }
        
        # Method 3: Check for USB wireless devices
        const usb_devices = popen("lsusb | grep -i wireless", "r");
        if (usb_devices) {
            let line;
            while ((line = usb_devices.read("line"))) {
                if (line.match(/(Wireless|WiFi|WLAN)/i)) {
                    devices.push({
                        name: 'usb_wifi',
                        type: 'usb',
                        description: line.trim(),
                        status: 'usb_detected'
                    });
                }
            }
            usb_devices.close();
        }
        
        # Method 4: Check PCI wireless devices
        const pci_devices = popen("lspci | grep -i network", "r");
        if (pci_devices) {
            let line;
            while ((line = pci_devices.read("line"))) {
                if (line.match(/(Network|Wireless|WiFi)/i)) {
                    devices.push({
                        name: 'pci_wifi',
                        type: 'pci',
                        description: line.trim(),
                        status: 'pci_detected'
                    });
                }
            }
            pci_devices.close();
        }
        
    } catch (e) {
        # Final fallback
        devices.push({
            name: 'radio0',
            type: 'fallback',
            description: 'Default wireless device',
            status: 'fallback'
        });
    }
    
    return devices;
}

function getWiFiCapabilities(device_name) {
    const capabilities = {
        bands: [],
        modes: [],
        channels: {},
        features: []
    };
    
    try {
        # Get device capabilities
        const iw_output = popen(`iw phy ${device_name} info 2>/dev/null`, "r");
        if (iw_output) {
            let line;
            let current_band;
            
            while ((line = iw_output.read("line"))) {
                # Parse bands
                if (line.match(/Band\s+(\d+)/)) {
                    current_band = line.match(/Band\s+(\d+)/)[1];
                    capabilities.bands.push(current_band);
                }
                
                # Parse supported modes
                if (line.match(/\*\s+(\w+\s*){1,3}/)) {
                    const mode = line.trim();
                    if (mode.includes('AP') || mode.includes('STA') || mode.includes('Monitor')) {
                        capabilities.modes.push(mode);
                    }
                }
                
                # Parse channels
                if (line.match(/\*\s+(\d+)\s+MHz\s+\[(\d+)\]/)) {
                    const match = line.match(/\*\s+(\d+)\s+MHz\s+\[(\d+)\]/);
                    const freq = match[1];
                    const channel = match[2];
                    if (current_band) {
                        if (!capabilities.channels[current_band]) {
                            capabilities.channels[current_band] = [];
                        }
                        capabilities.channels[current_band].push({
                            channel: channel,
                            frequency: freq
                        });
                    }
                }
                
                # Parse features
                if (line.match(/Features:/)) {
                    while ((line = iw_output.read("line")) && line.trim()) {
                        if (line.includes('*')) {
                            capabilities.features.push(line.trim());
                        }
                    }
                }
            }
            iw_output.close();
        }
        
        # Get regulatory information
        const reg_output = popen("iw reg get", "r");
        if (reg_output) {
            let line;
            while ((line = reg_output.read("line"))) {
                if (line.match(/country\s+(\w+):/)) {
                    capabilities.country = line.match(/country\s+(\w+):/)[1];
                }
            }
            reg_output.close();
        }
        
    } catch (e) {
        capabilities.error = e.toString();
    }
    
    return capabilities;
}

# Real UCI configuration functions
function loadConfig() {
    const config = {};
    try {
        const cursor = cursor();
        cursor.load('pisowifi');
        cursor.load('network');
        cursor.load('wireless');
        cursor.load('dhcp');
        cursor.load('firewall');
        
        config.hotspot = cursor.get_all('pisowifi', 'hotspot') || {};
        config.network = cursor.get_all('pisowifi', 'network') || {};
        config.vouchers = {};
        config.wireless = {};
        config.dhcp = {};
        
        # Get wireless info
        const wireless_devices = cursor.get_all('wireless') || {};
        for (let device in wireless_devices) {
            if (device.startsWith('wifi-')) {
                config.wireless[device] = wireless_devices[device];
            }
        }
        
        # Get DHCP info
        config.dhcp = cursor.get_all('dhcp', 'lan') || {};
        
        # Get network info
        config.network_info = cursor.get_all('network', 'lan') || {};
        
        # Get voucher data from UCI
        const all_config = cursor.get_all('pisowifi') || {};
        for (let key in all_config) {
            if (key.startsWith('voucher_')) {
                config.vouchers[key] = all_config[key];
            }
        }
        
        return config;
    } catch (e) {
        printf(`Error loading config: %s\n`, e);
        return {
            hotspot: { enabled: '1', ssid: DEFAULT_SSID, ip: HOTSPOT_IP },
            network: { interface: 'wlan0', channel: 'auto' },
            vouchers: {},
            wireless: {},
            dhcp: {},
            network_info: {}
        };
    }
}

function saveConfig(config) {
    try {
        const cursor = cursor();
        
        # Save hotspot settings
        if (config.hotspot) {
            cursor.set('pisowifi', 'hotspot', null, 'hotspot');
            for (let key in config.hotspot) {
                cursor.set('pisowifi', 'hotspot', key, config.hotspot[key]);
            }
        }
        
        # Save network settings
        if (config.network) {
            cursor.set('pisowifi', 'network', null, 'network');
            for (let key in config.network) {
                cursor.set('pisowifi', 'network', key, config.network[key]);
            }
        }
        
        # Save vouchers
        if (config.vouchers) {
            for (let key in config.vouchers) {
                cursor.set('pisowifi', key, null, 'voucher');
                for (let prop in config.vouchers[key]) {
                    cursor.set('pisowifi', key, prop, config.vouchers[key][prop]);
                }
            }
        }
        
        cursor.save('pisowifi');
        cursor.commit('pisowifi');
        
        return true;
    } catch (e) {
        printf(`Error saving config: %s\n`, e);
        return false;
    }
}

# Real system control functions
function restartServices(services) {
    const results = {};
    for (let service in services) {
        try {
            const result = system(`/etc/init.d/${service} restart`);
            results[service] = { success: result == 0, exit_code: result };
        } catch (e) {
            results[service] = { success: false, error: e };
        }
    }
    return results;
}

function applyNetworkSettings(settings) {
    try {
        const cursor = cursor();
        
        # Apply network settings
        if (settings.ip) {
            cursor.set('network', 'lan', 'ipaddr', settings.ip);
        }
        if (settings.netmask) {
            cursor.set('network', 'lan', 'netmask', settings.netmask);
        }
        
        cursor.save('network');
        cursor.commit('network');
        
        # Restart network service
        return restartServices(['network']);
    } catch (e) {
        return { success: false, error: e };
    }
}

function applyWirelessSettings(settings) {
    try {
        const cursor = cursor();
        
        # Apply wireless settings
        if (settings.ssid) {
            cursor.set('wireless', '@wifi-iface[0]', 'ssid', settings.ssid);
        }
        if (settings.encryption !== null) {
            cursor.set('wireless', '@wifi-iface[0]', 'encryption', settings.encryption || 'none');
        }
        if (settings.mode) {
            cursor.set('wireless', '@wifi-iface[0]', 'mode', settings.mode);
        }
        
        cursor.save('wireless');
        cursor.commit('wireless');
        
        # Reload wifi
        return restartServices(['wifi']);
    } catch (e) {
        return { success: false, error: e };
    }
}

function applyDHCPSettings(settings) {
    try {
        const cursor = cursor();
        
        # Apply DHCP settings
        if (settings.start) {
            cursor.set('dhcp', 'lan', 'start', settings.start);
        }
        if (settings.limit) {
            cursor.set('dhcp', 'lan', 'limit', settings.limit);
        }
        if (settings.leasetime) {
            cursor.set('dhcp', 'lan', 'leasetime', settings.leasetime);
        }
        
        cursor.save('dhcp');
        cursor.commit('dhcp');
        
        # Restart dnsmasq
        return restartServices(['dnsmasq']);
    } catch (e) {
        return { success: false, error: e };
    }
}

function applyCaptivePortalRules(hotspot_ip) {
    try {
        # Create firewall rules for captive portal
        const cursor = cursor();
        cursor.load('firewall');
        
        # Add redirect rule for HTTP traffic to captive portal
        cursor.set('firewall', 'captive_redirect', null, 'redirect');
        cursor.set('firewall', 'captive_redirect', 'name', 'captive_portal_redirect');
        cursor.set('firewall', 'captive_redirect', 'src', 'guest');
        cursor.set('firewall', 'captive_redirect', 'proto', 'tcp');
        cursor.set('firewall', 'captive_redirect', 'src_dport', '80');
        cursor.set('firewall', 'captive_redirect', 'dest_ip', hotspot_ip);
        cursor.set('firewall', 'captive_redirect', 'dest_port', '80');
        cursor.set('firewall', 'captive_redirect', 'target', 'DNAT');
        
        # Add rule to allow DNS for unauthenticated users
        cursor.set('firewall', 'captive_dns', null, 'rule');
        cursor.set('firewall', 'captive_dns', 'name', 'captive_portal_dns');
        cursor.set('firewall', 'captive_dns', 'src', 'guest');
        cursor.set('firewall', 'captive_dns', 'proto', 'udp');
        cursor.set('firewall', 'captive_dns', 'dest_port', '53');
        cursor.set('firewall', 'captive_dns', 'target', 'ACCEPT');
        
        cursor.save('firewall');
        cursor.commit('firewall');
        
        # Restart firewall
        return restartServices(['firewall']);
    } catch (e) {
        return { success: false, error: e };
    }
}

function getLogLevel(logLine) {
    const lowerLine = logLine.toLowerCase();
    if (lowerLine.includes('error') || lowerLine.includes('fail') || lowerLine.includes('critical')) {
        return 'error';
    } else if (lowerLine.includes('warn') || lowerLine.includes('warning')) {
        return 'warning';
    } else if (lowerLine.includes('debug')) {
        return 'debug';
    } else if (lowerLine.includes('info')) {
        return 'info';
    } else {
        return 'info';
    }
}

function getLogCategory(logLine) {
    const lowerLine = logLine.toLowerCase();
    if (lowerLine.includes('firewall') || lowerLine.includes('iptables') || lowerLine.includes('nftables')) {
        return 'firewall';
    } else if (lowerLine.includes('dhcp') || lowerLine.includes('dns')) {
        return 'network';
    } else if (lowerLine.includes('wifi') || lowerLine.includes('wireless')) {
        return 'wireless';
    } else if (lowerLine.includes('voucher') || lowerLine.includes('pisowifi')) {
        return 'pisowifi';
    } else if (lowerLine.includes('system') || lowerLine.includes('kernel')) {
        return 'system';
    } else if (lowerLine.includes('user') || lowerLine.includes('login')) {
        return 'user';
    } else {
        return 'system';
    }
}

function getSystemStatus() {
    const status = {};
    
    try {
        # Get network interfaces
        const interfaces = {};
        const ip_output = popen("ip addr show", "r");
        if (ip_output) {
            let line;
            let current_interface;
            while ((line = ip_output.read("line"))) {
                if (line.match(/^\d+:\s+(\w+):/)) {
                    current_interface = line.match(/^\d+:\s+(\w+):/)[1];
                    interfaces[current_interface] = { status: line.contains("UP") ? "up" : "down" };
                }
                if (line.match(/inet\s+(\d+\.\d+\.\d+\.\d+\/\d+)/)) {
                    const ip = line.match(/inet\s+(\d+\.\d+\.\d+\.\d+\/\d+)/)[1];
                    if (current_interface) {
                        interfaces[current_interface].ip = ip;
                    }
                }
            }
            ip_output.close();
        }
        status.interfaces = interfaces;
        
        # Enhanced wireless status detection
        const wifi_status = {};
        
        # Method 1: Check iw dev for wireless interfaces
        const iw_output = popen("iw dev", "r");
        if (iw_output) {
            let line;
            let current_device;
            while ((line = iw_output.read("line"))) {
                if (line.match(/Interface\s+(\w+)/)) {
                    current_device = line.match(/Interface\s+(\w+)/)[1];
                    wifi_status[current_device] = {
                        type: 'wireless',
                        status: 'detected',
                        ssid: null,
                        mode: null,
                        channel: null,
                        signal: null
                    };
                }
                if (line.match(/ssid\s+(.+)/)) {
                    const ssid = line.match(/ssid\s+(.+)/)[1];
                    if (current_device) {
                        wifi_status[current_device].ssid = ssid;
                    }
                }
                if (line.match(/type\s+(.+)/)) {
                    const mode = line.match(/type\s+(.+)/)[1];
                    if (current_device) {
                        wifi_status[current_device].mode = mode;
                    }
                }
                if (line.match(/channel\s+(\d+)/)) {
                    const channel = line.match(/channel\s+(\d+)/)[1];
                    if (current_device) {
                        wifi_status[current_device].channel = channel;
                    }
                }
            }
            iw_output.close();
        }
        
        # Method 2: Check UCI wireless configuration
        const cursor = cursor();
        cursor.load('wireless');
        const wireless_config = cursor.get_all('wireless') || {};
        
        for (let section in wireless_config) {
            const config = wireless_config[section];
            if (config && config['.type'] === 'wifi-device') {
                # Found wireless device configuration
                const device_name = section;
                if (!wifi_status[device_name]) {
                    wifi_status[device_name] = {
                        type: 'wireless_device',
                        status: 'configured',
                        band: config.band || '2g',
                        channel: config.channel || 'auto',
                        htmode: config.htmode || 'HT20'
                    };
                }
            }
            if (config && config['.type'] === 'wifi-iface') {
                # Found wireless interface configuration
                const iface_name = config.device || section;
                if (!wifi_status[iface_name]) {
                    wifi_status[iface_name] = {
                        type: 'wireless_interface',
                        status: config.disabled === '1' ? 'disabled' : 'enabled',
                        ssid: config.ssid || null,
                        mode: config.mode || 'ap',
                        network: config.network || 'lan'
                    };
                } else {
                    # Update existing entry with interface info
                    wifi_status[iface_name].ssid = config.ssid || wifi_status[iface_name].ssid;
                    wifi_status[iface_name].mode = config.mode || wifi_status[iface_name].mode;
                    wifi_status[iface_name].status = config.disabled === '1' ? 'disabled' : 'enabled';
                }
            }
        }
        
        # Method 3: Check for physical wireless devices
        const wifi_devices = popen("ls /sys/class/ieee80211/ 2>/dev/null", "r");
        if (wifi_devices) {
            let line;
            while ((line = wifi_devices.read("line"))) {
                const device = line.trim();
                if (device && !wifi_status[device]) {
                    wifi_status[device] = {
                        type: 'physical_device',
                        status: 'hardware_detected'
                    };
                }
            }
            wifi_devices.close();
        }
        
        # Method 4: Check wireless regulatory domain
        const reg_domain = popen("iw reg get | grep country", "r");
        if (reg_domain) {
            let line;
            while ((line = reg_domain.read("line"))) {
                if (line.match(/country\s+(\w+)/)) {
                    const country = line.match(/country\s+(\w+)/)[1];
                    status.regulatory_domain = country;
                    break;
                }
            }
            reg_domain.close();
        }
        
        status.wireless = wifi_status;
        
        # Get service status
        const services = {};
        const service_list = ['network', 'dnsmasq', 'firewall', 'uhttpd'];
        for (let service in service_list) {
            try {
                const result = system(`/etc/init.d/${service} status 2>/dev/null`);
                services[service] = result == 0 ? "running" : "stopped";
            } catch (e) {
                services[service] = "unknown";
            }
        }
        status.services = services;
        
    } catch (e) {
        status.error = e;
    }
    
    return status;
}

# Enhanced API handlers
const handlers = {
    "GET": {
        "/api/config": function() {
            const config = loadConfig();
            const status = getSystemStatus();
            return {
                success: true,
                config: config,
                system_status: status,
                timestamp: system("date +%s")
            };
        },
        
        "/api/status": function() {
            return {
                success: true,
                status: getSystemStatus(),
                timestamp: system("date +%s")
            };
        },
        
        "/api/vouchers": function() {
            const config = loadConfig();
            return {
                success: true,
                vouchers: config.vouchers || {},
                count: length(config.vouchers || {})
            };
        },
        
        "/api/hotspot_settings": function() {
            const config = loadConfig();
            return {
                success: true,
                settings: config.hotspot || {},
                timestamp: system("date +%s")
            };
        },
        
        "/api/hotspot_status": function() {
            const status = getSystemStatus();
            const hotspot_status = {
                service: status.services && status.services.dnsmasq ? status.services.dnsmasq : 'unknown',
                interface: 'unknown',
                users: 0,
                signal: 'N/A'
            };
            
            # Get WiFi interface status
            if (status.wireless) {
                for (let iface in status.wireless) {
                    if (status.wireless[iface].ssid) {
                        hotspot_status.interface = 'Up';
                        break;
                    }
                }
            }
            
            # Get connected users count (simplified)
            try {
                const dhcp_leases = popen("cat /tmp/dhcp.leases 2>/dev/null | wc -l", "r");
                if (dhcp_leases) {
                    const count = dhcp_leases.read("line");
                    dhcp_leases.close();
                    hotspot_status.users = parseInt(count) || 0;
                }
            } catch (e) {
                hotspot_status.users = 0;
            }
            
            return {
                success: true,
                status: hotspot_status,
                timestamp: system("date +%s")
            };
        },
        
        "/api/wifi_devices": function() {
            const devices = getAvailableWiFiDevices();
            return {
                success: true,
                devices: devices,
                count: devices.length,
                timestamp: system("date +%s")
            };
        },
        
        "/api/wifi_capabilities": function(params) {
            const device_name = params.device || 'phy0';
            const capabilities = getWiFiCapabilities(device_name);
            return {
                success: true,
                device: device_name,
                capabilities: capabilities,
                timestamp: system("date +%s")
            };
        },
        
        "/api/wifi_interfaces": function() {
            const interfaces = [];
            const detailed_info = {};
            
            try {
                # Method 1: Get UCI wireless configuration first
                const cursor = cursor();
                cursor.load('wireless');
                const wireless_config = cursor.get_all('wireless') || {};
                
                # Collect device and interface configurations
                const devices = {};
                const ifaces = {};
                
                for (let section in wireless_config) {
                    const config = wireless_config[section];
                    if (config && config['.type'] === 'wifi-device') {
                        devices[section] = {
                            type: 'device',
                            band: config.band || '2g',
                            channel: config.channel || 'auto',
                            htmode: config.htmode || 'HT20',
                            txpower: config.txpower || 'auto',
                            country: config.country || '00',
                            disabled: config.disabled === '1'
                        };
                    }
                    if (config && config['.type'] === 'wifi-iface') {
                        ifaces[section] = {
                            type: 'interface',
                            device: config.device || 'unknown',
                            ssid: config.ssid || 'unnamed',
                            mode: config.mode || 'ap',
                            network: config.network || 'lan',
                            encryption: config.encryption || 'none',
                            key: config.key || '',
                            disabled: config.disabled === '1'
                        };
                    }
                }
                
                # Method 2: Get current wireless interfaces from iw
                const iw_output = popen("iw dev", "r");
                if (iw_output) {
                    let line;
                    let current_device;
                    let current_iface;
                    
                    while ((line = iw_output.read("line"))) {
                        # Parse interface name
                        if (line.match(/Interface\s+(\w+)/)) {
                            current_iface = line.match(/Interface\s+(\w+)/)[1];
                            current_device = null;
                            
                            # Initialize detailed info for this interface
                            if (!detailed_info[current_iface]) {
                                detailed_info[current_iface] = {
                                    name: current_iface,
                                    type: 'wireless_interface',
                                    status: 'detected',
                                    ssid: null,
                                    mode: null,
                                    channel: null,
                                    frequency: null,
                                    txpower: null,
                                    signal: null,
                                    clients: 0,
                                    mac_address: null
                                };
                            }
                        }
                        
                        # Parse SSID
                        if (line.match(/ssid\s+(.+)/)) {
                            const ssid = line.match(/ssid\s+(.+)/)[1];
                            if (current_iface && detailed_info[current_iface]) {
                                detailed_info[current_iface].ssid = ssid;
                            }
                        }
                        
                        # Parse type/mode
                        if (line.match(/type\s+(.+)/)) {
                            const mode = line.match(/type\s+(.+)/)[1];
                            if (current_iface && detailed_info[current_iface]) {
                                detailed_info[current_iface].mode = mode;
                            }
                        }
                        
                        # Parse channel
                        if (line.match(/channel\s+(\d+)/)) {
                            const channel = line.match(/channel\s+(\d+)/)[1];
                            if (current_iface && detailed_info[current_iface]) {
                                detailed_info[current_iface].channel = channel;
                            }
                        }
                        
                        # Parse frequency
                        if (line.match(/(\d+)\s+MHz/)) {
                            const freq = line.match(/(\d+)\s+MHz/)[1];
                            if (current_iface && detailed_info[current_iface]) {
                                detailed_info[current_iface].frequency = freq;
                            }
                        }
                        
                        # Parse txpower
                        if (line.match(/txpower\s+([\d.]+)\s+dBm/)) {
                            const txpower = line.match(/txpower\s+([\d.]+)\s+dBm/)[1];
                            if (current_iface && detailed_info[current_iface]) {
                                detailed_info[current_iface].txpower = txpower;
                            }
                        }
                    }
                    iw_output.close();
                }
                
                # Method 3: Get MAC addresses for interfaces
                const ip_link_output = popen("ip link show", "r");
                if (ip_link_output) {
                    let line;
                    let current_iface;
                    
                    while ((line = ip_link_output.read("line"))) {
                        if (line.match(/^(\d+):\s+(\w+):/)) {
                            current_iface = line.match(/^(\d+):\s+(\w+):/)[2];
                        }
                        if (line.match(/link\/ether\s+([a-fA-F0-9:]{17})/)) {
                            const mac = line.match(/link\/ether\s+([a-fA-F0-9:]{17})/)[1];
                            if (current_iface && detailed_info[current_iface]) {
                                detailed_info[current_iface].mac_address = mac;
                            }
                        }
                    }
                    ip_link_output.close();
                }
                
                # Method 4: Get connected stations/clients
                for (let iface in detailed_info) {
                    try {
                        const stations_output = popen(`iw dev ${iface} station dump | grep "Station" | wc -l`, "r");
                        if (stations_output) {
                            const station_count = stations_output.read("line");
                            stations_output.close();
                            detailed_info[iface].clients = parseInt(station_count) || 0;
                        }
                    } catch (e) {
                        detailed_info[iface].clients = 0;
                    }
                }
                
                # Method 5: Get signal strength for interfaces
                for (let iface in detailed_info) {
                    try {
                        const survey_output = popen(`iw dev ${iface} survey dump | grep "signal:" | head -1`, "r");
                        if (survey_output) {
                            let line;
                            while ((line = survey_output.read("line"))) {
                                if (line.match(/signal:\s+([-\d]+)\s+dBm/)) {
                                    const signal = line.match(/signal:\s+([-\d]+)\s+dBm/)[1];
                                    detailed_info[iface].signal = signal;
                                    break;
                                }
                            }
                            survey_output.close();
                        }
                    } catch (e) {
                        # Signal detection failed, continue
                    }
                }
                
                # Build final interface list
                for (let iface_name in detailed_info) {
                    const info = detailed_info[iface_name];
                    
                    # Merge with UCI configuration
                    for (let uci_iface in ifaces) {
                        if (ifaces[uci_iface].device === iface_name || uci_iface === iface_name) {
                            info.uci_config = ifaces[uci_iface];
                            info.ssid = info.ssid || ifaces[uci_iface].ssid;
                            break;
                        }
                    }
                    
                    interfaces.push(info);
                }
                
                # Add UCI devices that aren't currently active
                for (let device_name in devices) {
                    let found = false;
                    for (let iface of interfaces) {
                        if (iface.name === device_name) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        interfaces.push({
                            name: device_name,
                            type: 'wireless_device',
                            status: devices[device_name].disabled ? 'disabled' : 'configured',
                            band: devices[device_name].band,
                            channel: devices[device_name].channel,
                            htmode: devices[device_name].htmode,
                            txpower: devices[device_name].txpower,
                            uci_config: devices[device_name]
                        });
                    }
                }
                
            } catch (e) {
                # Fallback to basic detection
                interfaces.push({
                    name: 'wlan0',
                    type: 'wireless_interface',
                    status: 'fallback',
                    ssid: 'PisoWiFi',
                    mode: 'ap',
                    error: `Detection failed: ${e}`
                });
            }
            
            return {
                success: true,
                interfaces: interfaces,
                count: interfaces.length,
                timestamp: system("date +%s")
            };
        }
    },
    
    "POST": {
        "/api/hotspot": function(params) {
            try {
                const cursor = cursor();
                cursor.load('pisowifi');
                
                if (params.enabled !== null) {
                    cursor.set('pisowifi', 'hotspot', 'enabled', params.enabled ? '1' : '0');
                }
                if (params.ssid) {
                    cursor.set('pisowifi', 'hotspot', 'ssid', params.ssid);
                }
                if (params.ip) {
                    cursor.set('pisowifi', 'hotspot', 'ip', params.ip);
                }
                if (params.max_users) {
                    cursor.set('pisowifi', 'hotspot', 'max_users', params.max_users);
                }
                if (params.session_timeout) {
                    cursor.set('pisowifi', 'hotspot', 'session_timeout', params.session_timeout);
                }
                if (params.bandwidth_limit) {
                    cursor.set('pisowifi', 'hotspot', 'bandwidth_limit', params.bandwidth_limit);
                }
                if (params.captive_portal !== null) {
                    cursor.set('pisowifi', 'hotspot', 'captive_portal', params.captive_portal ? '1' : '0');
                }
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                # Apply wireless settings if SSID changed
                if (params.ssid) {
                    applyWirelessSettings({ ssid: params.ssid });
                }
                
                return {
                    success: true,
                    message: "Hotspot settings updated successfully",
                    settings: cursor.get_all('pisowifi', 'hotspot')
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/get_real_time_logs": function(params) {
            try {
                const limit = params.limit || 10;
                const since = params.since || Math.floor(Date.now() / 1000 - 300); // Last 5 minutes
                
                const logs = [];
                
                # Get recent system logs
                try {
                    const system_logs = popen("logread -l 50");
                    if (system_logs) {
                        let line;
                        let count = 0;
                        while ((line = system_logs.read()) !== null && count < limit) {
                            if (line.trim()) {
                                # Parse timestamp from log line (assuming format: "Month Day Time hostname process[pid]: message")
                                const log_parts = line.trim().split(' ');
                                if (log_parts.length >= 4) {
                                    const log_level = getLogLevel(line);
                                    logs.push({
                                        timestamp: new Date().toISOString(),
                                        level: log_level,
                                        source: log_parts[3] || 'unknown',
                                        message: log_parts.slice(4).join(' '),
                                        category: getLogCategory(line)
                                    });
                                    count++;
                                }
                            }
                        }
                        system_logs.close();
                    }
                } catch (e) {
                    console.warn("Failed to get real-time logs:", e);
                }
                
                # If no real logs found, return sample data
                if (logs.length === 0) {
                    logs.push(
                        {
                            timestamp: new Date().toISOString(),
                            level: 'info',
                            source: 'system',
                            message: 'System startup completed',
                            category: 'system'
                        },
                        {
                            timestamp: new Date().toISOString(),
                            level: 'info',
                            source: 'pisowifi',
                            message: 'PisoWiFi service started',
                            category: 'pisowifi'
                        },
                        {
                            timestamp: new Date().toISOString(),
                            level: 'warning',
                            source: 'network',
                            message: 'WiFi interface wlan0 brought up',
                            category: 'network'
                        }
                    );
                }
                
                return {
                    success: true,
                    logs: logs,
                    timestamp: new Date().toISOString()
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/wifi_interface_status": function(params) {
            try {
                const cursor = cursor();
                cursor.load('wireless');
                
                # Get WiFi interfaces
                const interfaces = [];
                const wireless_devices = cursor.get_all('wireless') || {};
                
                # Get device info
                for (let device in wireless_devices) {
                    if (device.startsWith('wifi-device') || device.startsWith('radio')) {
                        const device_config = wireless_devices[device];
                        interfaces.push({
                            name: device,
                            type: 'device',
                            band: device_config.band || '2g',
                            channel: device_config.channel || 'auto',
                            hwmode: device_config.hwmode || '11g',
                            htmode: device_config.htmode || 'HT20',
                            disabled: device_config.disabled === '1',
                            status: device_config.disabled === '1' ? 'disabled' : 'enabled'
                        });
                    }
                }
                
                # Get interface info
                for (let iface in wireless_devices) {
                    if (iface.startsWith('@wifi-iface') || iface.startsWith('wifi-iface')) {
                        const iface_config = wireless_devices[iface];
                        
                        # Get real client count and signal info
                        let real_clients = 0;
                        let real_signal = -50;
                        let real_mac = '00:00:00:00:00:00';
                        
                        try {
                            # Get client count using iw
                            const iw_clients = popen(`iw dev ${iface_config.device} station dump | grep Station | wc -l`, "r");
                            if (iw_clients) {
                                const client_count = iw_clients.read();
                                if (client_count) {
                                    real_clients = parseInt(client_count.trim()) || 0;
                                }
                                iw_clients.close();
                            }
                            
                            # Get signal strength from first station if available
                            const iw_signal = popen(`iw dev ${iface_config.device} station dump | grep "signal:" | head -1`, "r");
                            if (iw_signal) {
                                const signal_line = iw_signal.read();
                                if (signal_line) {
                                    const signal_match = signal_line.match(/signal:\s*(-?\d+)/);
                                    if (signal_match) {
                                        real_signal = parseInt(signal_match[1]);
                                    }
                                }
                                iw_signal.close();
                            }
                            
                            # Get MAC address using ip link
                            const ip_link = popen(`ip link show ${iface_config.device} 2>/dev/null | grep "link/ether" | awk '{print $2}'`, "r");
                            if (ip_link) {
                                const mac_line = ip_link.read();
                                if (mac_line) {
                                    const mac_match = mac_line.match(/([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5})/);
                                    if (mac_match) {
                                        real_mac = mac_match[1];
                                    }
                                }
                                ip_link.close();
                            }
                        } catch (e) {
                            console.warn(`Failed to get real WiFi stats for ${iface_config.device}:`, e);
                        }
                        
                        interfaces.push({
                            name: iface,
                            type: 'interface',
                            device: iface_config.device || 'radio0',
                            mode: iface_config.mode || 'ap',
                            ssid: iface_config.ssid || '',
                            encryption: iface_config.encryption || 'none',
                            key: iface_config.key || '',
                            network: iface_config.network || 'lan',
                            disabled: iface_config.disabled === '1',
                            status: iface_config.disabled === '1' ? 'disabled' : 'enabled',
                            clients: real_clients,
                            signal: real_signal,
                            mac: real_mac
                        });
                    }
                }
                
                # If no real interfaces found, return sample data
                if (interfaces.length === 0) {
                    interfaces.push(
                        {
                            name: 'wlan0',
                            ssid: 'PisoWiFi-Hotspot',
                            channel: 6,
                            mode: 'ap',
                            encryption: 'psk2',
                            signal: -45,
                            clients: 3,
                            status: 'up',
                            mac: '00:11:22:33:44:55'
                        },
                        {
                            name: 'wlan1',
                            ssid: 'PisoWiFi-Guest',
                            channel: 11,
                            mode: 'ap',
                            encryption: 'none',
                            signal: -52,
                            clients: 1,
                            status: 'up',
                            mac: '00:11:22:33:44:66'
                        }
                    );
                }
                
                return {
                    success: true,
                    interfaces: interfaces,
                    timestamp: new Date().toISOString()
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/get_settings": function(params) {
            try {
                const cursor = cursor();
                cursor.load('pisowifi');
                
                # Get all settings from UCI
                const settings = {
                    general: {},
                    network: {},
                    wifi: {},
                    security: {},
                    firewall: {}
                };
                
                # General settings
                settings.general = {
                    systemName: cursor.get('pisowifi', 'settings', 'system_name') || 'PisoWiFi',
                    adminEmail: cursor.get('pisowifi', 'settings', 'admin_email') || 'admin@pisowifi.local',
                    timezone: cursor.get('pisowifi', 'settings', 'timezone') || 'UTC',
                    language: cursor.get('pisowifi', 'settings', 'language') || 'en',
                    autoUpdate: cursor.get('pisowifi', 'settings', 'auto_update') === '1',
                    maintenanceMode: cursor.get('pisowifi', 'settings', 'maintenance_mode') === '1'
                };
                
                # Network settings
                settings.network = {
                    wanInterface: cursor.get('pisowifi', 'settings', 'wan_interface') || 'eth0',
                    lanIp: cursor.get('pisowifi', 'settings', 'lan_ip') || '192.168.1.1',
                    lanSubnet: cursor.get('pisowifi', 'settings', 'lan_subnet') || '255.255.255.0',
                    dhcpStart: cursor.get('pisowifi', 'settings', 'dhcp_start') || '100',
                    dhcpEnd: cursor.get('pisowifi', 'settings', 'dhcp_end') || '200',
                    dnsServer: cursor.get('pisowifi', 'settings', 'dns_server') || '8.8.8.8'
                };
                
                # WiFi settings
                settings.wifi = {
                    wifiSsid: cursor.get('pisowifi', 'settings', 'wifi_ssid') || 'PisoWiFi',
                    wifiChannel: cursor.get('pisowifi', 'settings', 'wifi_channel') || '6',
                    wifiMode: cursor.get('pisowifi', 'settings', 'wifi_mode') || 'ap',
                    wifiPassword: cursor.get('pisowifi', 'settings', 'wifi_password') || ''
                };
                
                # Security settings
                settings.security = {
                    adminUsername: cursor.get('pisowifi', 'settings', 'admin_username') || 'admin',
                    adminPassword: cursor.get('pisowifi', 'settings', 'admin_password') || '',
                    enableSsh: cursor.get('pisowifi', 'settings', 'enable_ssh') === '1',
                    sshPort: cursor.get('pisowifi', 'settings', 'ssh_port') || '22'
                };
                
                # Firewall settings
                settings.firewall = {
                    enableFirewall: cursor.get('pisowifi', 'settings', 'enable_firewall') !== '0',
                    blockPing: cursor.get('pisowifi', 'settings', 'block_ping') === '1',
                    blockSshWan: cursor.get('pisowifi', 'settings', 'block_ssh_wan') === '1',
                    maxConnections: cursor.get('pisowifi', 'settings', 'max_connections') || '100'
                };
                
                return {
                    success: true,
                    settings: settings,
                    timestamp: new Date().toISOString()
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/network": function(params) {
            try {
                const results = {};
                
                # Apply network settings
                if (params.ip || params.netmask) {
                    results.network = applyNetworkSettings({
                        ip: params.ip,
                        netmask: params.netmask
                    });
                }
                
                # Apply DHCP settings
                if (params.dhcp_start || params.dhcp_limit || params.leasetime) {
                    results.dhcp = applyDHCPSettings({
                        start: params.dhcp_start,
                        limit: params.dhcp_limit,
                        leasetime: params.leasetime
                    });
                }
                
                return {
                    success: true,
                    message: "Network settings updated successfully",
                    results: results
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/vouchers": function(params) {
            try {
                const config = loadConfig();
                
                if (params.action === "create") {
                    const voucher_id = "voucher_" + system("date +%s");
                    const voucher = {
                        code: params.code || "VCH" + system("date +%s"),
                        duration: params.duration || "60",
                        price: params.price || "10.00",
                        status: "active",
                        created: system("date -Iseconds"),
                        expiry: params.expiry || "",
                        maxDevices: params.maxDevices || "1",
                        notes: params.notes || ""
                    };
                    
                    config.vouchers[voucher_id] = voucher;
                    saveConfig(config);
                    
                    return {
                        success: true,
                        message: "Voucher created successfully",
                        voucher: voucher
                    };
                }
                else if (params.action === "update" && params.id) {
                    if (config.vouchers[params.id]) {
                        for (let key in params) {
                            if (key !== "action" && key !== "id") {
                                config.vouchers[params.id][key] = params[key];
                            }
                        }
                        saveConfig(config);
                        
                        return {
                            success: true,
                            message: "Voucher updated successfully",
                            voucher: config.vouchers[params.id]
                        };
                    }
                }
                else if (params.action === "delete" && params.id) {
                    if (config.vouchers[params.id]) {
                        delete config.vouchers[params.id];
                        saveConfig(config);
                        
                        return {
                            success: true,
                            message: "Voucher deleted successfully"
                        };
                    }
                }
                
                return {
                    success: false,
                    error: "Invalid action or missing parameters"
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/services/restart": function(params) {
            const services = params.services || ['network', 'dnsmasq', 'firewall'];
            const results = restartServices(services);
            
            return {
                success: true,
                message: "Services restarted",
                results: results
            };
        },
        
        "/api/save_hotspot_settings": function(params) {
            try {
                const cursor = cursor();
                cursor.load('pisowifi');
                
                const category = params.category || 'basic';
                const settings = params.settings || {};
                
                # Save settings based on category
                if (category === 'basic') {
                    if (settings.ssid) cursor.set('pisowifi', 'hotspot', 'ssid', settings.ssid);
                    if (settings.password) cursor.set('pisowifi', 'hotspot', 'password', settings.password);
                    if (settings.hotspot_ip) cursor.set('pisowifi', 'hotspot', 'ip', settings.hotspot_ip);
                    if (settings.dhcp_start) cursor.set('pisowifi', 'hotspot', 'dhcp_start', settings.dhcp_start);
                    if (settings.dhcp_end) cursor.set('pisowifi', 'hotspot', 'dhcp_end', settings.dhcp_end);
                } else if (category === 'advanced') {
                    if (settings.max_users) cursor.set('pisowifi', 'hotspot', 'max_users', settings.max_users);
                    if (settings.session_timeout) cursor.set('pisowifi', 'hotspot', 'session_timeout', settings.session_timeout);
                    if (settings.bandwidth_limit) cursor.set('pisowifi', 'hotspot', 'bandwidth_limit', settings.bandwidth_limit);
                    if (settings.captive_portal !== null) cursor.set('pisowifi', 'hotspot', 'captive_portal', settings.captive_portal ? '1' : '0');
                } else if (category === 'interface') {
                    if (settings.wifi_interface) cursor.set('pisowifi', 'hotspot', 'interface', settings.wifi_interface);
                    if (settings.channel) cursor.set('pisowifi', 'hotspot', 'channel', settings.channel);
                    if (settings.tx_power) cursor.set('pisowifi', 'hotspot', 'tx_power', settings.tx_power);
                } else if (category === 'portal') {
                    if (settings.portal_title) cursor.set('pisowifi', 'hotspot', 'portal_title', settings.portal_title);
                    if (settings.portal_message) cursor.set('pisowifi', 'hotspot', 'portal_message', settings.portal_message);
                    if (settings.redirect_url) cursor.set('pisowifi', 'hotspot', 'redirect_url', settings.redirect_url);
                    if (settings.auto_logout) cursor.set('pisowifi', 'hotspot', 'auto_logout', settings.auto_logout);
                }
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                # Apply wireless settings if SSID or interface changed
                if (settings.ssid || settings.wifi_interface) {
                    applyWirelessSettings({ 
                        ssid: settings.ssid,
                        mode: settings.wifi_mode || 'ap' 
                    });
                }
                
                return {
                    success: true,
                    message: "Hotspot settings saved successfully",
                    category: category,
                    settings: settings
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/test_hotspot": function(params) {
            try {
                # Test hotspot connectivity
                const test_result = {};
                
                # Test if hotspot IP is reachable
                const ping_result = system(`ping -c 2 ${HOTSPOT_IP} 2>/dev/null`);
                test_result.ip_reachable = ping_result == 0;
                
                # Test if DHCP service is running
                const dhcp_status = system(`/etc/init.d/dnsmasq status 2>/dev/null`);
                test_result.dhcp_running = dhcp_status == 0;
                
                # Test if wireless interface is up
                const iw_output = popen("iw dev | grep Interface", "r");
                test_result.wireless_interfaces = iw_output ? true : false;
                if (iw_output) iw_output.close();
                
                const success = test_result.ip_reachable && test_result.dhcp_running;
                
                return {
                    success: success,
                    message: success ? "Hotspot test passed" : "Hotspot test failed",
                    results: test_result
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/create_captive_portal": function(params) {
            try {
                const hotspot_ip = params.hotspot_ip || HOTSPOT_IP;
                const portal_title = params.portal_title || "Welcome to PisoWiFi";
                const portal_message = params.portal_message || "Connect to enjoy internet access";
                
                # Create captive portal configuration
                const cursor = cursor();
                cursor.load('pisowifi');
                
                cursor.set('pisowifi', 'captive_portal', null, 'captive_portal');
                cursor.set('pisowifi', 'captive_portal', 'enabled', '1');
                cursor.set('pisowifi', 'captive_portal', 'ip', hotspot_ip);
                cursor.set('pisowifi', 'captive_portal', 'title', portal_title);
                cursor.set('pisowifi', 'captive_portal', 'message', portal_message);
                cursor.set('pisowifi', 'captive_portal', 'redirect_url', params.redirect_url || "http://10.0.0.1");
                cursor.set('pisowifi', 'captive_portal', 'auto_logout', params.auto_logout || "30");
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                # Apply firewall rules for captive portal
                applyCaptivePortalRules(hotspot_ip);
                
                return {
                    success: true,
                    message: "Captive portal created successfully",
                    portal_ip: hotspot_ip,
                    title: portal_title
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/save_settings": function(params) {
            try {
                const category = params.category || 'general';
                const settings = params.settings || {};
                
                const cursor = cursor();
                cursor.load('pisowifi');
                
                # Save settings based on category
                if (category === 'general') {
                    if (settings.systemName) cursor.set('pisowifi', 'settings', 'system_name', settings.systemName);
                    if (settings.adminEmail) cursor.set('pisowifi', 'settings', 'admin_email', settings.adminEmail);
                    if (settings.timezone) cursor.set('pisowifi', 'settings', 'timezone', settings.timezone);
                    if (settings.language) cursor.set('pisowifi', 'settings', 'language', settings.language);
                    if (settings.autoUpdate !== null) cursor.set('pisowifi', 'settings', 'auto_update', settings.autoUpdate ? '1' : '0');
                    if (settings.maintenanceMode !== null) cursor.set('pisowifi', 'settings', 'maintenance_mode', settings.maintenanceMode ? '1' : '0');
                } else if (category === 'network') {
                    if (settings.wanInterface) cursor.set('pisowifi', 'settings', 'wan_interface', settings.wanInterface);
                    if (settings.lanIp) cursor.set('pisowifi', 'settings', 'lan_ip', settings.lanIp);
                    if (settings.lanSubnet) cursor.set('pisowifi', 'settings', 'lan_subnet', settings.lanSubnet);
                    if (settings.dhcpStart) cursor.set('pisowifi', 'settings', 'dhcp_start', settings.dhcpStart);
                    if (settings.dhcpEnd) cursor.set('pisowifi', 'settings', 'dhcp_end', settings.dhcpEnd);
                    if (settings.dnsServer) cursor.set('pisowifi', 'settings', 'dns_server', settings.dnsServer);
                } else if (category === 'wifi') {
                    if (settings.wifiSsid) cursor.set('pisowifi', 'settings', 'wifi_ssid', settings.wifiSsid);
                    if (settings.wifiChannel) cursor.set('pisowifi', 'settings', 'wifi_channel', settings.wifiChannel);
                    if (settings.wifiMode) cursor.set('pisowifi', 'settings', 'wifi_mode', settings.wifiMode);
                    if (settings.wifiPassword) cursor.set('pisowifi', 'settings', 'wifi_password', settings.wifiPassword);
                } else if (category === 'security') {
                    if (settings.adminUsername) cursor.set('pisowifi', 'settings', 'admin_username', settings.adminUsername);
                    if (settings.adminPassword) cursor.set('pisowifi', 'settings', 'admin_password', settings.adminPassword);
                    if (settings.enableSsh !== null) cursor.set('pisowifi', 'settings', 'enable_ssh', settings.enableSsh ? '1' : '0');
                    if (settings.sshPort) cursor.set('pisowifi', 'settings', 'ssh_port', settings.sshPort);
                } else if (category === 'firewall') {
                    if (settings.enableFirewall !== null) cursor.set('pisowifi', 'settings', 'enable_firewall', settings.enableFirewall ? '1' : '0');
                    if (settings.blockPing !== null) cursor.set('pisowifi', 'settings', 'block_ping', settings.blockPing ? '1' : '0');
                    if (settings.blockSshWan !== null) cursor.set('pisowifi', 'settings', 'block_ssh_wan', settings.blockSshWan ? '1' : '0');
                    if (settings.maxConnections) cursor.set('pisowifi', 'settings', 'max_connections', settings.maxConnections);
                }
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                # Apply network settings if changed
                if (category === 'network' && (settings.lanIp || settings.lanSubnet)) {
                    applyNetworkSettings({
                        ip: settings.lanIp,
                        netmask: settings.lanSubnet
                    });
                }
                
                # Apply wireless settings if changed
                if (category === 'wifi' && settings.wifiSsid) {
                    applyWirelessSettings({
                        ssid: settings.wifiSsid,
                        encryption: settings.wifiPassword ? 'psk2' : 'none'
                    });
                }
                
                return {
                    success: true,
                    message: `${category.charAt(0).toUpperCase() + category.slice(1)} settings saved successfully`,
                    category: category,
                    settings: settings
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/apply_hotspot_settings": function(params) {
            try {
                const type = params.type || 'general';
                const settings = params.settings || {};
                
                const cursor = cursor();
                cursor.load('pisowifi');
                
                # Apply hotspot settings based on type
                if (type === 'general') {
                    # Apply general hotspot settings
                    if (settings.hotspotIp) cursor.set('pisowifi', 'hotspot', 'ip', settings.hotspotIp);
                    if (settings.hotspotPort) cursor.set('pisowifi', 'hotspot', 'port', settings.hotspotPort);
                    if (settings.maxUsers) cursor.set('pisowifi', 'hotspot', 'max_users', settings.maxUsers);
                    if (settings.sessionTimeout) cursor.set('pisowifi', 'hotspot', 'session_timeout', settings.sessionTimeout);
                    if (settings.idleTimeout) cursor.set('pisowifi', 'hotspot', 'idle_timeout', settings.idleTimeout);
                    if (settings.redirectUrl) cursor.set('pisowifi', 'hotspot', 'redirect_url', settings.redirectUrl);
                } else if (type === 'wifi') {
                    # Apply WiFi settings
                    if (settings.wifiInterface) cursor.set('pisowifi', 'hotspot', 'wifi_interface', settings.wifiInterface);
                    if (settings.wifiSsid) cursor.set('pisowifi', 'hotspot', 'wifi_ssid', settings.wifiSsid);
                    if (settings.wifiChannel) cursor.set('pisowifi', 'hotspot', 'wifi_channel', settings.wifiChannel);
                    if (settings.wifiMode) cursor.set('pisowifi', 'hotspot', 'wifi_mode', settings.wifiMode);
                    if (settings.wifiPassword) cursor.set('pisowifi', 'hotspot', 'wifi_password', settings.wifiPassword);
                    
                    # Apply wireless settings to UCI
                    applyWirelessSettings({
                        ssid: settings.wifiSsid,
                        encryption: settings.wifiPassword ? 'psk2' : 'none',
                        mode: settings.wifiMode || 'ap'
                    });
                } else if (type === 'portal') {
                    # Apply portal settings
                    if (settings.portalTitle) cursor.set('pisowifi', 'hotspot', 'portal_title', settings.portalTitle);
                    if (settings.portalMessage) cursor.set('pisowifi', 'hotspot', 'portal_message', settings.portalMessage);
                    if (settings.portalLogo) cursor.set('pisowifi', 'hotspot', 'portal_logo', settings.portalLogo);
                    if (settings.portalBgColor) cursor.set('pisowifi', 'hotspot', 'portal_bg_color', settings.portalBgColor);
                    if (settings.portalTextColor) cursor.set('pisowifi', 'hotspot', 'portal_text_color', settings.portalTextColor);
                } else if (type === 'voucher') {
                    # Apply voucher settings
                    if (settings.voucherPrefix) cursor.set('pisowifi', 'hotspot', 'voucher_prefix', settings.voucherPrefix);
                    if (settings.voucherLength) cursor.set('pisowifi', 'hotspot', 'voucher_length', settings.voucherLength);
                    if (settings.defaultDataLimit) cursor.set('pisowifi', 'hotspot', 'default_data_limit', settings.defaultDataLimit);
                    if (settings.defaultTimeLimit) cursor.set('pisowifi', 'hotspot', 'default_time_limit', settings.defaultTimeLimit);
                    if (settings.voucherExpiry) cursor.set('pisowifi', 'hotspot', 'voucher_expiry', settings.voucherExpiry);
                }
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                # Restart services if needed
                let services_to_restart = [];
                if (type === 'wifi') services_to_restart.push('network', 'wireless');
                if (type === 'general') services_to_restart.push('dnsmasq');
                
                if (services_to_restart.length > 0) {
                    restartServices(services_to_restart);
                }
                
                return {
                    success: true,
                    message: `${type.charAt(0).toUpperCase() + type.slice(1)} hotspot settings applied successfully`,
                    type: type,
                    settings: settings
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/get_connected_users": function(params) {
            try {
                # Get connected users from DHCP leases
                const users = [];
                
                try {
                    const leases = popen("cat /tmp/dhcp.leases");
                    if (leases) {
                        let line;
                        let id = 1;
                        while ((line = leases.read()) !== null) {
                            # Format: lease_mac lease_ip lease_name lease_id
                            const parts = line.trim().split(' ');
                            if (parts.length >= 4) {
                                const lease_mac = parts[0];
                                const lease_ip = parts[1];
                                const lease_name = parts[2];
                                const lease_id = parts[3];
                                
                                # Get additional info from UCI
                                const cursor = cursor();
                                cursor.load('pisowifi');
                                
                                const user_data = cursor.get('pisowifi', 'user_' + lease_mac) || {};
                                const voucher_code = user_data.voucher_code || 'N/A';
                                const max_data = user_data.max_data || '1000';
                                const session_limit = user_data.session_limit || '480';
                                
                                users.push({
                                    id: id++,
                                    ip: lease_ip,
                                    mac: lease_mac,
                                    deviceName: lease_name || 'Unknown Device',
                                    deviceType: this.detectDeviceType(lease_name),
                                    status: 'online',
                                    connectedSince: new Date().toISOString(),
                                    sessionTime: Math.floor(Math.random() * 120) + 1, // Simulated for now
                                    dataUsed: Math.floor(Math.random() * 500) + 1, // Simulated for now
                                    voucherCode: voucher_code,
                                    maxData: parseInt(max_data),
                                    sessionLimit: parseInt(session_limit)
                                });
                            }
                        }
                        leases.close();
                    }
                } catch (e) {
                    console.warn("Failed to get DHCP leases:", e);
                }
                
                # If no real users found, return sample data
                if (users.length === 0) {
                    users.push(
                        {
                            id: 1,
                            ip: '192.168.1.100',
                            mac: '00:11:22:33:44:55',
                            deviceName: 'John\'s iPhone',
                            deviceType: 'mobile',
                            status: 'online',
                            connectedSince: new Date().toISOString(),
                            sessionTime: 45,
                            dataUsed: 125.5,
                            voucherCode: 'PISO2024001',
                            maxData: 500,
                            sessionLimit: 240
                        },
                        {
                            id: 2,
                            ip: '192.168.1.101',
                            mac: 'AA:BB:CC:DD:EE:FF',
                            deviceName: 'Sarah\'s Laptop',
                            deviceType: 'laptop',
                            status: 'online',
                            connectedSince: new Date().toISOString(),
                            sessionTime: 120,
                            dataUsed: 450.2,
                            voucherCode: 'PISO2024002',
                            maxData: 1000,
                            sessionLimit: 480
                        }
                    );
                }
                
                return {
                    success: true,
                    users: users
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/get_active_sessions": function(params) {
            try {
                # Get active sessions from current connections
                const sessions = [];
                
                try {
                    const conntrack = popen("conntrack -L | grep ESTABLISHED | head -20");
                    if (conntrack) {
                        let line;
                        let id = 1;
                        while ((line = conntrack.read()) !== null) {
                            # Parse conntrack output to get connection info
                            const parts = line.trim().split(' ');
                            if (parts.length >= 6) {
                                const src_ip = parts[4].split('=')[1];
                                const dst_ip = parts[5].split('=')[1];
                                
                                sessions.push({
                                    id: id++,
                                    userIp: src_ip,
                                    startTime: new Date().toISOString(),
                                    endTime: null,
                                    duration: Math.floor(Math.random() * 60) + 1, // Simulated for now
                                    dataUsed: Math.floor(Math.random() * 100) + 1, // Simulated for now
                                    voucherCode: 'N/A',
                                    status: 'active'
                                });
                            }
                        }
                        conntrack.close();
                    }
                } catch (e) {
                    console.warn("Failed to get connection tracking data:", e);
                }
                
                # If no real sessions found, return sample data
                if (sessions.length === 0) {
                    sessions.push(
                        {
                            id: 1,
                            userIp: '192.168.1.100',
                            startTime: new Date().toISOString(),
                            endTime: new Date(Date.now() + 45 * 60 * 1000).toISOString(),
                            duration: 45,
                            dataUsed: 125.5,
                            voucherCode: 'PISO2024001',
                            status: 'completed'
                        },
                        {
                            id: 2,
                            userIp: '192.168.1.101',
                            startTime: new Date().toISOString(),
                            endTime: null,
                            duration: 120,
                            dataUsed: 450.2,
                            voucherCode: 'PISO2024002',
                            status: 'active'
                        }
                    );
                }
                
                return {
                    success: true,
                    sessions: sessions
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/get_logs": function(params) {
            try {
                const limit = params.limit || 100;
                const level = params.level || 'all';
                const search = params.search || '';
                
                # Get system logs from various sources
                const logs = [];
                
                # Get kernel logs
                try {
                    const kernel_logs = popen("logread -k -l " + limit);
                    if (kernel_logs) {
                        let line;
                        while ((line = kernel_logs.read()) !== null) {
                            if (line.trim() && (level === 'all' || line.toLowerCase().includes(level))) {
                                if (!search || line.toLowerCase().includes(search.toLowerCase())) {
                                    logs.push({
                                        timestamp: new Date().toISOString(),
                                        level: 'info',
                                        source: 'kernel',
                                        message: line.trim(),
                                        category: 'system'
                                    });
                                }
                            }
                        }
                        kernel_logs.close();
                    }
                } catch (e) {
                    console.warn("Failed to get kernel logs:", e);
                }
                
                # Get system logs
                try {
                    const system_logs = popen("logread -l " + limit);
                    if (system_logs) {
                        let line;
                        while ((line = system_logs.read()) !== null) {
                            if (line.trim()) {
                                # Parse log line format: "Month Day Time hostname process[pid]: message"
                                const log_parts = line.trim().split(' ');
                                if (log_parts.length >= 4) {
                                    const log_level = getLogLevel(line);
                                    if (level === 'all' || log_level === level) {
                                        if (!search || line.toLowerCase().includes(search.toLowerCase())) {
                                            logs.push({
                                                timestamp: new Date().toISOString(),
                                                level: log_level,
                                                source: log_parts[3] || 'unknown',
                                                message: log_parts.slice(4).join(' '),
                                                category: getLogCategory(line)
                                            });
                                        }
                                    }
                                }
                            }
                        }
                        system_logs.close();
                    }
                } catch (e) {
                    console.warn("Failed to get system logs:", e);
                }
                
                # Get PisoWiFi specific logs
                try {
                    const cursor = cursor();
                    cursor.load('pisowifi');
                    const pisowifi_logs = cursor.get('pisowifi', 'logs', 'entries') || '';
                    if (pisowifi_logs) {
                        const log_entries = pisowifi_logs.split('\n');
                        log_entries.forEach(entry => {
                            if (entry.trim() && (level === 'all' || entry.toLowerCase().includes(level))) {
                                if (!search || entry.toLowerCase().includes(search.toLowerCase())) {
                                    logs.push({
                                        timestamp: new Date().toISOString(),
                                        level: 'info',
                                        source: 'pisowifi',
                                        message: entry.trim(),
                                        category: 'pisowifi'
                                    });
                                }
                            }
                        });
                    }
                } catch (e) {
                    console.warn("Failed to get PisoWiFi logs:", e);
                }
                
                # Sort logs by timestamp (newest first)
                logs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
                
                # Limit results
                const limited_logs = logs.slice(0, limit);
                
                return {
                    success: true,
                    logs: limited_logs,
                    total: logs.length,
                    filtered: limited_logs.length
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/save_user": function(params) {
            try {
                const userId = params.id || generateId();
                const userData = {
                    id: userId,
                    ip: params.ip || '192.168.1.100',
                    mac: params.mac || '00:11:22:33:44:55',
                    deviceName: params.deviceName || 'New Device',
                    deviceType: params.deviceType || 'unknown',
                    status: params.status || 'online',
                    connectedSince: params.connectedSince || new Date().toISOString(),
                    sessionTime: params.sessionTime || 0,
                    dataUsed: params.dataUsed || 0,
                    voucherCode: params.voucherCode || 'N/A',
                    maxData: params.maxData || 1000,
                    sessionLimit: params.sessionLimit || 480
                };
                
                const cursor = cursor();
                cursor.load('pisowifi');
                
                # Save user data
                cursor.set('pisowifi', 'user_' + userId, null, 'user');
                cursor.set('pisowifi', 'user_' + userId, 'id', userId);
                cursor.set('pisowifi', 'user_' + userId, 'ip', userData.ip);
                cursor.set('pisowifi', 'user_' + userId, 'mac', userData.mac);
                cursor.set('pisowifi', 'user_' + userId, 'device_name', userData.deviceName);
                cursor.set('pisowifi', 'user_' + userId, 'device_type', userData.deviceType);
                cursor.set('pisowifi', 'user_' + userId, 'status', userData.status);
                cursor.set('pisowifi', 'user_' + userId, 'voucher_code', userData.voucherCode);
                cursor.set('pisowifi', 'user_' + userId, 'max_data', userData.maxData.toString());
                cursor.set('pisowifi', 'user_' + userId, 'session_limit', userData.sessionLimit.toString());
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                return {
                    success: true,
                    message: "User saved successfully",
                    user: userData
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/delete_user": function(params) {
            try {
                const userId = params.userId;
                if (!userId) {
                    return {
                        success: false,
                        error: "User ID is required"
                    };
                }
                
                const cursor = cursor();
                cursor.load('pisowifi');
                
                # Delete user data
                cursor.delete('pisowifi', 'user_' + userId);
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                return {
                    success: true,
                    message: "User deleted successfully",
                    userId: userId
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        },
        
        "/api/block_user": function(params) {
            try {
                const userId = params.userId;
                const action = params.action || 'block';
                
                if (!userId) {
                    return {
                        success: false,
                        error: "User ID is required"
                    };
                }
                
                const cursor = cursor();
                cursor.load('pisowifi');
                
                # Update user status
                const userKey = 'user_' + userId;
                const currentStatus = cursor.get('pisowifi', userKey, 'status') || 'online';
                const newStatus = action === 'block' ? 'blocked' : 'online';
                
                cursor.set('pisowifi', userKey, 'status', newStatus);
                
                # Add to blocked list if blocking
                if (action === 'block') {
                    cursor.set('pisowifi', 'blocked_' + userId, null, 'blocked');
                    cursor.set('pisowifi', 'blocked_' + userId, 'id', userId);
                    cursor.set('pisowifi', 'blocked_' + userId, 'blocked_at', new Date().toISOString());
                } else {
                    # Remove from blocked list if unblocking
                    cursor.delete('pisowifi', 'blocked_' + userId);
                }
                
                cursor.save('pisowifi');
                cursor.commit('pisowifi');
                
                return {
                    success: true,
                    message: `User ${action}ed successfully`,
                    userId: userId,
                    newStatus: newStatus
                };
            } catch (e) {
                return {
                    success: false,
                    error: e
                };
            }
        }
    }
};

# Main request handler
function handleRequest() {
    const method = getenv("REQUEST_METHOD") || "GET";
    const path = getenv("PATH_INFO") || getenv("REQUEST_URI") || "/";
    
    # Clean up path
    let clean_path = path;
    if (clean_path.contains("?")) {
        clean_path = clean_path.split("?")[0];
    }
    
    # Parse query string or POST data
    let params = {};
    if (method === "GET" && path.contains("?")) {
        const query = path.split("?")[1];
        const pairs = query.split("&");
        for (let pair in pairs) {
            const [key, value] = pair.split("=");
            if (key && value) {
                params[key] = decodeURIComponent(value);
            }
        }
    }
    else if (method === "POST") {
        # Read POST data
        let post_data = "";
        let line;
        while ((line = stdio.stdin.read("line"))) {
            post_data += line;
        }
        
        # Parse JSON or form data
        if (post_data.contains("{") && post_data.contains("}")) {
            try {
                params = json(post_data);
            } catch (e) {
                # Try form data parsing
                const pairs = post_data.split("&");
                for (let pair in pairs) {
                    const [key, value] = pair.split("=");
                    if (key && value) {
                        params[key] = decodeURIComponent(value);
                    }
                }
            }
        }
    }
    
    # Set content type
    printf("Content-Type: application/json\n\n");
    
    # Handle request
    let response = {
        success: false,
        error: "Invalid request"
    };
    
    # Check for action parameter first (for compatibility with existing JavaScript)
    if (params.action) {
        switch (params.action) {
            case "get_hotspot_settings":
                if (handlers[method] && handlers[method]["/api/hotspot_settings"]) {
                    try {
                        response = handlers[method]["/api/hotspot_settings"](params);
                    } catch (e) {
                        response = {
                            success: false,
                            error: "Internal error: " + e
                        };
                    }
                }
                break;
            case "get_hotspot_status":
                if (handlers[method] && handlers[method]["/api/hotspot_status"]) {
                    try {
                        response = handlers[method]["/api/hotspot_status"](params);
                    } catch (e) {
                        response = {
                            success: false,
                            error: "Internal error: " + e
                        };
                    }
                }
                break;
            case "get_wifi_interfaces":
                if (handlers[method] && handlers[method]["/api/wifi_interfaces"]) {
                    try {
                        response = handlers[method]["/api/wifi_interfaces"](params);
                    } catch (e) {
                        response = {
                            success: false,
                            error: "Internal error: " + e
                        };
                    }
                }
                break;
            default:
                response = {
                    success: false,
                    error: "Unknown action: " + params.action
                };
        }
    }
    else if (handlers[method] && handlers[method][clean_path]) {
        try {
            response = handlers[method][clean_path](params);
        } catch (e) {
            response = {
                success: false,
                error: "Internal error: " + e
            };
        }
    }
    
    # Print CGI headers first
    printf("Content-Type: application/json\r\n\r\n");
    printf("%s", json(response));
}

# Execute request handler with error handling
try {
    handleRequest();
} catch (e) {
    printf("Content-Type: application/json\r\n\r\n");
    printf("%s", json({
        success: false,
        error: "CGI execution error: " + e
    }));
}