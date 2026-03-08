#!/usr/bin/ucode
# PisoWiFi API - Fixed Ucode version for your OpenWrt setup

import { cursor } from "uci";
import { system } from "posix";
import { printf } from "stdio";
import { getenv } from "stdlib";

# JSON output function
function json_response(data) {
    printf("Content-Type: application/json\n\n%s", json(data));
}

# Get system status
function get_system_status() {
    let status = {
        service: "unknown",
        interface: "unknown", 
        users: 0,
        signal: "N/A"
    };
    
    # Check dnsmasq service
    let dnsmasq_check = system("/etc/init.d/dnsmasq status >/dev/null 2>&1");
    status.service = dnsmasq_check == 0 ? "running" : "stopped";
    
    # Check network interfaces
    let interfaces = ["wlan0", "wlan1"];
    for (let i = 0; i < length(interfaces); i++) {
        let iface = interfaces[i];
        let state_path = "/sys/class/net/" + iface + "/operstate";
        
        let state_file = open(state_path, "r");
        if (state_file) {
            let state = trim(state_file.read("*a"));
            state_file.close();
            
            if (state == "up") {
                status.interface = "up";
                break;
            }
        }
    }
    
    if (status.interface == "unknown") {
        status.interface = "down";
    }
    
    return status;
}

# Get hotspot settings
function get_hotspot_settings() {
    let settings = {
        enabled: "1",
        ssid: "PisoWiFi_Free",
        ip: "10.0.0.1"
    };
    
    # Try to get real SSID from UCI
    let uci_cursor = cursor();
    if (uci_cursor) {
        let uci_ssid = uci_cursor.get("wireless", "@wifi-iface[0]", "ssid");
        if (uci_ssid) {
            settings.ssid = uci_ssid;
        }
    }
    
    return settings;
}

# Main execution
try {
    let query_string = getenv("QUERY_STRING") || "";
    
    # Parse action from query string
    let action = "";
    if (query_string) {
        let pairs = split(query_string, "&");
        for (let i = 0; i < length(pairs); i++) {
            let pair = pairs[i];
            let parts = split(pair, "=");
            if (length(parts) == 2 && parts[0] == "action") {
                action = parts[1];
                break;
            }
        }
    }
    
    let response = {
        success: false,
        error: "Unknown action"
    };
    
    if (action == "get_hotspot_status") {
        response = {
            success: true,
            status: get_system_status()
        };
    }
    else if (action == "get_hotspot_settings") {
        response = {
            success: true,
            settings: get_hotspot_settings()
        };
    }
    
    json_response(response);
} catch (e) {
    json_response({
        success: false,
        error: "Script error: " + e
    });
}