#!/bin/bash

# ONE COMMAND INSTALL - Everything automatic
echo "=== INSTALL ALL FEATURES ==="
echo "Running automatic installation..."

# Go to script directory
cd "$(dirname "$0")"

# Make everything executable
chmod +x *.sh

# Run all installers in sequence
echo "Step 1: Device Manager..."
bash QUICK_UPDATE_DEVICE_MANAGER.sh

echo "Step 2: Device Sync..."
bash PATCH_DEVICE_SYNC.sh

echo "Step 3: Centralized Key..."
bash INSTALL_CGI.sh

echo "Step 4: Fix permissions..."
chmod +x /usr/bin/wifi_devices_sync_auto.sh 2>/dev/null
chmod +x /www/cgi-bin/admin 2>/dev/null

echo "✅ ALL DONE! Features installed."
echo "Run: sh INSTALL_ALL.sh"