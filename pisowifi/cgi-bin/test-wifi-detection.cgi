#!/usr/bin/ucode

# Comprehensive WiFi Detection Test Script
# This script tests multiple methods to detect WiFi hardware and interfaces

import { system, popen, execute } from "posix";
import { printf, print } from "stdio";
import { getenv } from "stdlib";

function debug_log(message) {
    system(`echo "$(date): ${message}" >> /tmp/pisowifi-wifi-debug.log`);
}

function run_command(cmd, description) {
    print(`\n=== ${description} ===\n`);
    debug_log(`Running: ${cmd}`);
    
    const proc = popen(cmd, "r");
    if (proc) {
        let line;
        let found = false;
        while ((line = proc.read("line"))) {
            print(line);
            found = true;
        }
        proc.close();
        if (!found) {
            print("No output found\n");
        }
    } else {
        print(`Failed to execute: ${cmd}\n`);
    }
}

function test_wifi_detection() {
    print("Content-Type: text/plain\n\n");
    print("=== COMPREHENSIVE WIFI DETECTION TEST ===\n");
    
    debug_log("Starting comprehensive WiFi detection test");
    
    # Test 1: Check if wireless subsystem exists
    run_command("ls -la /sys/class/ieee80211/ 2>/dev/null", "1. Physical Wireless Devices");
    
    # Test 2: Check UCI wireless configuration
    run_command("uci show wireless 2>/dev/null", "2. UCI Wireless Configuration");
    
    # Test 3: Check available network interfaces
    run_command("ip link show | grep -E '(wlan|wifi|wireless)' 2>/dev/null", "3. Network Interfaces (wlan/wifi)");
    
    # Test 4: Check iw command availability
    run_command("which iw", "4. iw Command Availability");
    
    # Test 5: Test iw dev command
    run_command("iw dev 2>/dev/null", "5. iw dev Output");
    
    # Test 6: Check iwinfo command
    run_command("which iwinfo", "6. iwinfo Command Availability");
    
    # Test 7: Test iwinfo devices
    run_command("iwinfo 2>/dev/null", "7. iwinfo Devices");
    
    # Test 8: Check USB devices
    run_command("lsusb 2>/dev/null", "8. USB Devices");
    
    # Test 9: Check PCI devices
    run_command("lspci | grep -i network 2>/dev/null", "9. PCI Network Devices");
    
    # Test 10: Check kernel modules
    run_command("lsmod | grep -i wifi 2>/dev/null", "10. WiFi Kernel Modules");
    
    # Test 11: Check for wireless drivers
    run_command("find /lib/modules -name '*wifi*' -o -name '*wlan*' 2>/dev/null", "11. WiFi Driver Modules");
    
    # Test 12: Check wireless regulatory database
    run_command("iw reg get 2>/dev/null", "12. Wireless Regulatory Info");
    
    # Test 13: Check network config
    run_command("uci show network 2>/dev/null | grep -i wifi", "13. Network Config WiFi References");
    
    # Test 14: Check for hostapd
    run_command("which hostapd", "14. hostapd Availability");
    
    # Test 15: Check running processes
    run_command("ps | grep -E '(hostapd|wpa_supplicant)' 2>/dev/null", "15. WiFi Related Processes");
    
    # Test 16: Check system log for wireless
    run_command("logread | grep -i wireless | tail -10 2>/dev/null", "16. Recent Wireless System Logs");
    
    # Test 17: Check device tree
    run_command("find /proc/device-tree -name '*wifi*' -o -name '*wireless*' 2>/dev/null", "17. Device Tree WiFi Entries");
    
    # Test 18: Check for wireless interfaces in /proc
    run_command("ls -la /proc/net/ | grep wlan 2>/dev/null", "18. Wireless Interfaces in /proc");
    
    print("\n=== TEST COMPLETED ===\n");
    print("Check /tmp/pisowifi-wifi-debug.log for detailed debug information\n");
    
    debug_log("WiFi detection test completed");
}

try {
    test_wifi_detection();
} catch (e) {
    print(`Error during WiFi detection test: ${e}\n`);
    debug_log(`Error: ${e}`);
}