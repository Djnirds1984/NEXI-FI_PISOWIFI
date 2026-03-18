#!/bin/sh
# Ruijie Sync Installer
# Sets up the lightweight sync script and cron job on OpenWrt

set -e

# Configuration
SYNC_SCRIPT_URL="https://yourdomain.com/sync_devices.sh" # Palitan ito sa actual Cloudflare URL mo
SCRIPT_PATH="/tmp/sync_devices.sh"

echo "[INFO] Installing Ruijie Cloud Sync..."

# Ensure curl is installed (usually default in recent OpenWrt, but just in case)
if ! command -v curl >/dev/null 2>&1; then
    echo "[INFO] Installing curl..."
    opkg update && opkg install curl
fi

# Download the sync script to /tmp (RAM)
echo "[INFO] Downloading sync script to RAM..."
curl -sSf "$SYNC_SCRIPT_URL" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# Function to setup Cron Job
setup_cron() {
    echo "[INFO] Setting up cron job (every 2 minutes)..."
    
    # Check if cron job already exists
    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        # Append new cron job
        (crontab -l 2>/dev/null; echo "*/2 * * * * /bin/sh $SCRIPT_PATH") | crontab -
        echo "[SUCCESS] Cron job added!"
    else
        echo "[INFO] Cron job already exists."
    fi
    
    # Ensure cron service is enabled and running
    /etc/init.d/cron enable
    /etc/init.d/cron restart
}

# Ensure script downloads on boot since /tmp is cleared
setup_autostart() {
    echo "[INFO] Configuring auto-download on boot..."
    
    local rc_local="/etc/rc.local"
    local download_cmd="curl -sSf $SYNC_SCRIPT_URL -o $SCRIPT_PATH && chmod +x $SCRIPT_PATH"
    
    if ! grep -q "$SYNC_SCRIPT_URL" "$rc_local" 2>/dev/null; then
        # Insert before 'exit 0' if it exists, otherwise append
        sed -i "/^exit 0/i $download_cmd" "$rc_local" 2>/dev/null || {
            echo "$download_cmd" >> "$rc_local"
            echo "exit 0" >> "$rc_local"
        }
        echo "[SUCCESS] Added to rc.local for auto-download on boot."
    else
        echo "[INFO] Auto-download already configured in rc.local."
    fi
}

setup_cron
setup_autostart

echo "[SUCCESS] Ruijie Cloud Sync setup complete!"
echo "It will now sync devices to your Supabase every 2 minutes."
