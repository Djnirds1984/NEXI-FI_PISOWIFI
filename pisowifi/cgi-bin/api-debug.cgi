#!/usr/bin/ucode

# Debug PisoWiFi API Backend - Simplified version for testing
# This script helps debug CGI execution issues

import { cursor, load, save, unload } from "uci";
import { system, popen, execute } from "posix";
import { printf, print } from "stdio";
import { getenv, setenv } from "stdlib";

# Simple JSON output function
function json_response(data) {
    printf("Content-Type: application/json\n\n");
    printf("%s", json(data));
}

# Debug function to log errors
function debug_log(message) {
    system(`echo "$(date): ${message}" >> /tmp/pisowifi-debug.log`);
}

# Main execution
try {
    debug_log("CGI script started");
    
    # Get environment variables
    const method = getenv("REQUEST_METHOD") || "GET";
    const path = getenv("PATH_INFO") || getenv("REQUEST_URI") || "/";
    const query_string = getenv("QUERY_STRING") || "";
    
    debug_log(`Method: ${method}, Path: ${path}, Query: ${query_string}`);
    
    # Parse action from query string
    let action = "";
    let params = {};
    
    if (query_string) {
        const pairs = query_string.split("&");
        for (let pair in pairs) {
            const [key, value] = pair.split("=");
            if (key && value) {
                params[key] = decodeURIComponent(value);
                if (key === "action") {
                    action = value;
                }
            }
        }
    }
    
    debug_log(`Parsed action: ${action}`);
    
    # Handle different actions
    let response = {
        success: false,
        error: "Unknown action"
    };
    
    if (action === "get_hotspot_settings") {
        response = {
            success: true,
            settings: {
                enabled: true,
                ssid: "PisoWiFi_Debug",
                ip: "10.0.0.1",
                dhcp_start: "10.0.0.10",
                dhcp_end: "10.0.0.250",
                voucher_required: true,
                redirect_url: "http://10.0.0.1"
            },
            message: "Debug hotspot settings"
        };
    }
    else if (action === "get_hotspot_status") {
        response = {
            success: true,
            status: {
                enabled: true,
                connected_clients: 2,
                active_vouchers: 1,
                total_vouchers: 5,
                uptime: "2h 30m",
                interfaces: [{
                    name: "wlan0",
                    ssid: "PisoWiFi_Debug",
                    status: "up",
                    clients: 2
                }]
            },
            message: "Debug hotspot status"
        };
    }
    else if (action === "get_wifi_interfaces") {
        response = {
            success: true,
            interfaces: [{
                name: "wlan0",
                ssid: "PisoWiFi_Debug",
                device: "radio0",
                mode: "ap",
                status: "enabled",
                clients: 2,
                signal: -45
            }],
            message: "Debug WiFi interfaces"
        };
    }
    else if (action === "debug") {
        response = {
            success: true,
            debug: {
                method: method,
                path: path,
                query_string: query_string,
                action: action,
                params: params,
                timestamp: system("date +%s"),
                ucode_version: "1.0"
            },
            message: "Debug information"
        };
    }
    else {
        response = {
            success: false,
            error: `Unknown action: ${action}`,
            available_actions: ["get_hotspot_settings", "get_hotspot_status", "get_wifi_interfaces", "debug"]
        };
    }
    
    debug_log(`Response: ${json(response)}`);
    json_response(response);
    
} catch (e) {
    debug_log(`Error: ${e}`);
    json_response({
        success: false,
        error: `Script error: ${e}`,
        timestamp: system("date +%s")
    });
}