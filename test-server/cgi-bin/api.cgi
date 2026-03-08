#!/usr/bin/env ucode

'use strict';

import { fs } from 'fs';
import { uci } from 'uci';

// PisoWiFi Configuration Manager
const PISOWIFI_CONFIG = '/etc/config/pisowifi';
const HOTSPOT_IP = '10.0.0.1';
const DEFAULT_SSID = 'PisoWiFi_Free';

function loadConfig() {
    const config = {};
    try {
        const cursor = uci.cursor();
        cursor.load('pisowifi');
        
        config.hotspot = cursor.get_all('pisowifi', 'hotspot') || {};
        config.vouchers = cursor.get_all('pisowifi', 'vouchers') || {};
        config.network = cursor.get_all('pisowifi', 'network') || {};
        
        return config;
    } catch (e) {
        print(`Error loading config: ${e}\n`);
        return {
            hotspot: { enabled: '1', ssid: DEFAULT_SSID, ip: HOTSPOT_IP },
            vouchers: {},
            network: {}
        };
    }
}

function saveConfig(config) {
    try {
        const cursor = uci.cursor();
        
        // Save hotspot settings
        if (config.hotspot) {
            cursor.set('pisowifi', 'hotspot', null, 'section');
            cursor.set('pisowifi', 'hotspot', 'enabled', config.hotspot.enabled || '1');
            cursor.set('pisowifi', 'hotspot', 'ssid', config.hotspot.ssid || DEFAULT_SSID);
            cursor.set('pisowifi', 'hotspot', 'ip', config.hotspot.ip || HOTSPOT_IP);
            cursor.set('pisowifi', 'hotspot', 'password', config.hotspot.password || '');
            cursor.set('pisowifi', 'hotspot', 'max_users', config.hotspot.max_users || '50');
            cursor.set('pisowifi', 'hotspot', 'session_timeout', config.hotspot.session_timeout || '60');
            cursor.set('pisowifi', 'hotspot', 'bandwidth_limit', config.hotspot.bandwidth_limit || '2');
            cursor.set('pisowifi', 'hotspot', 'captive_portal', config.hotspot.captive_portal || '1');
        }
        
        // Save network settings
        if (config.network) {
            cursor.set('pisowifi', 'network', null, 'section');
            cursor.set('pisowifi', 'network', 'interface', config.network.interface || 'wlan0');
            cursor.set('pisowifi', 'network', 'channel', config.network.channel || 'auto');
            cursor.set('pisowifi', 'network', 'tx_power', config.network.tx_power || '80');
            cursor.set('pisowifi', 'network', 'dhcp_start', config.network.dhcp_start || '10.0.0.10');
            cursor.set('pisowifi', 'network', 'dhcp_end', config.network.dhcp_end || '10.0.0.250');
        }
        
        cursor.commit('pisowifi');
        return true;
    } catch (e) {
        print(`Error saving config: ${e}\n`);
        return false;
    }
}

function applyHotspotSettings(config) {
    try {
        // Apply wireless settings
        const cursor = uci.cursor();
        
        // Configure wireless interface
        cursor.set('wireless', 'wifi-iface', '@wifi-iface[0]', 'ssid', config.hotspot.ssid);
        cursor.set('wireless', 'wifi-iface', '@wifi-iface[0]', 'key', config.hotspot.password);
        cursor.set('wireless', 'wifi-iface', '@wifi-iface[0]', 'mode', 'ap');
        cursor.set('wireless', 'wifi-iface', '@wifi-iface[0]', 'network', 'lan');
        
        // Configure network interface
        cursor.set('network', 'lan', 'ipaddr', config.hotspot.ip);
        cursor.set('network', 'lan', 'netmask', '255.255.255.0');
        cursor.set('network', 'lan', 'start', config.network.dhcp_start.split('.')[3]);
        cursor.set('network', 'lan', 'limit', parseInt(config.network.dhcp_end.split('.')[3]) - parseInt(config.network.dhcp_start.split('.')[3]));
        
        cursor.commit('wireless');
        cursor.commit('network');
        
        // Restart services
        system('wifi reload');
        system('/etc/init.d/network restart');
        
        if (config.hotspot.captive_portal === '1') {
            system('/etc/init.d/uhttpd restart');
        }
        
        return true;
    } catch (e) {
        print(`Error applying settings: ${e}\n`);
        return false;
    }
}

function handleHotspotSettings() {
    const config = loadConfig();
    
    if (env.REQUEST_METHOD === 'POST') {
        const input = io.stdin.read(4096);
        const data = json(input || '{}');
        
        if (data.hotspot) {
            config.hotspot = { ...config.hotspot, ...data.hotspot };
        }
        if (data.network) {
            config.network = { ...config.network, ...data.network };
        }
        
        if (saveConfig(config) && applyHotspotSettings(config)) {
            return json({ success: true, message: 'Settings applied successfully' });
        } else {
            return json({ success: false, message: 'Failed to apply settings' });
        }
    }
    
    return json({ success: true, data: config });
}

function handleVoucherCRUD() {
    const config = loadConfig();
    
    if (env.REQUEST_METHOD === 'GET') {
        return json({ success: true, vouchers: config.vouchers });
    }
    
    if (env.REQUEST_METHOD === 'POST') {
        const input = io.stdin.read(4096);
        const data = json(input || '{}');
        
        if (data.action === 'create') {
            const voucher = data.voucher;
            voucher.id = Date.now();
            voucher.created = new Date().toISOString();
            voucher.status = 'active';
            
            config.vouchers[voucher.id] = voucher;
            
            if (saveConfig(config)) {
                return json({ success: true, voucher: voucher });
            }
        } else if (data.action === 'update') {
            const voucher = data.voucher;
            if (config.vouchers[voucher.id]) {
                config.vouchers[voucher.id] = { ...config.vouchers[voucher.id], ...voucher };
                
                if (saveConfig(config)) {
                    return json({ success: true, voucher: config.vouchers[voucher.id] });
                }
            }
        } else if (data.action === 'delete') {
            const id = data.id;
            if (config.vouchers[id]) {
                delete config.vouchers[id];
                
                if (saveConfig(config)) {
                    return json({ success: true, message: 'Voucher deleted' });
                }
            }
        }
    }
    
    return json({ success: false, message: 'Invalid request' });
}

function handleStatus() {
    const config = loadConfig();
    
    const status = {
        hotspot: {
            enabled: config.hotspot.enabled === '1',
            ssid: config.hotspot.ssid,
            ip: config.hotspot.ip,
            users: Math.floor(Math.random() * 25), // Simulated
            uptime: system('uptime | awk "{print $3,$4}"') || 'Unknown'
        },
        vouchers: {
            total: length(keys(config.vouchers)),
            active: 0,
            used: 0,
            expired: 0
        }
    };
    
    // Count voucher statuses
    for (let id, voucher in config.vouchers) {
        if (voucher.status === 'active') status.vouchers.active++;
        else if (voucher.status === 'used') status.vouchers.used++;
        else if (voucher.status === 'expired') status.vouchers.expired++;
    }
    
    return json({ success: true, status: status });
}

function handleTestConnection() {
    const config = loadConfig();
    
    // Test wireless interface
    const interface = config.network.interface || 'wlan0';
    const testResult = {
        interface: interface,
        status: 'unknown',
        signal: 'unknown',
        clients: 0
    };
    
    try {
        const iwinfo = system(`iwinfo ${interface} info 2>/dev/null`);
        if (iwinfo) {
            testResult.status = 'up';
            testResult.signal = system(`iwinfo ${interface} assoclist 2>/dev/null | grep -c "^\s"`) || '0';
            testResult.clients = system(`iwinfo ${interface} assoclist 2>/dev/null | grep -c "^[0-9]"`) || 0;
        } else {
            testResult.status = 'down';
        }
    } catch (e) {
        testResult.status = 'error';
        testResult.error = e.toString();
    }
    
    return json({ success: true, test: testResult });
}

function main() {
    const path = env.PATH_INFO || env.REQUEST_URI || '';
    
    // Set content type
    print('Content-Type: application/json\n');
    
    try {
        if (path.contains('/api/hotspot')) {
            return handleHotspotSettings();
        } else if (path.contains('/api/vouchers')) {
            return handleVoucherCRUD();
        } else if (path.contains('/api/status')) {
            return handleStatus();
        } else if (path.contains('/api/test')) {
            return handleTestConnection();
        } else {
            return json({ success: false, message: 'Invalid API endpoint' });
        }
    } catch (e) {
        return json({ success: false, message: `Server error: ${e.toString()}` });
    }
}

// Run the main function
main();