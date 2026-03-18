#!/bin/sh
# PisoWiFi Cloud Loader Installation Script
# Downloads and installs the lightweight cloud loader to RAM

set -e

# Configuration
LOADER_URL="https://your-domain.com/pisowifi-loader.js"
MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "machine_$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)")
SUPABASE_URL="https://fuiabtdflbodglfexvln.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Check if running on OpenWrt
check_openwrt() {
    if [ ! -f /etc/openwrt_release ]; then
        log_error "This script is designed for OpenWrt only"
        exit 1
    fi
}

# Check available space in /tmp
check_space() {
    local available=$(df /tmp | tail -1 | awk '{print $4}')
    local required=2048  # 2MB in KB
    
    if [ "$available" -lt "$required" ]; then
        log_error "Insufficient space in /tmp. Available: ${available}KB, Required: ${required}KB"
        exit 1
    fi
    
    log_info "Space check passed: ${available}KB available"
}

# Download the loader
download_loader() {
    log_info "Downloading cloud loader..."
    
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    # Download to RAM (/tmp)
    if ! curl -sSf "$LOADER_URL" -o /tmp/pisowifi-loader.js; then
        log_error "Failed to download loader from $LOADER_URL"
        exit 1
    fi
    
    log_info "Loader downloaded successfully"
}

# Configure the loader
configure_loader() {
    log_info "Configuring loader for machine: $MACHINE_ID"
    
    # Replace placeholders in the loader
    sed -i "s|your-project.supabase.co|$SUPABASE_URL|g" /tmp/pisowifi-loader.js
    sed -i "s|your-anon-key|$SUPABASE_ANON_KEY|g" /tmp/pisowifi-loader.js
    sed -i "s|machine_001|$MACHINE_ID|g" /tmp/pisowifi-loader.js
    
    log_info "Loader configured successfully"
}

# Create startup script
create_startup_script() {
    log_info "Creating startup script..."
    
    cat > /tmp/start-pisowifi-cloud.sh << 'EOF'
#!/bin/sh
# PisoWiFi Cloud Loader Startup Script

LOADER_PATH="/tmp/pisowifi-loader.js"
LOG_FILE="/tmp/pisowifi-cloud.log"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if loader exists
if [ ! -f "$LOADER_PATH" ]; then
    log "Loader not found at $LOADER_PATH"
    exit 1
fi

# Start the loader in background
log "Starting PisoWiFi Cloud Loader..."
cd /www

# Inject loader into existing portal page
if [ -f "index.html" ]; then
    # Backup original
    cp index.html index.html.backup
    
    # Add loader script tag before closing body tag
    sed -i '/<\/body>/i\<script src="file:///tmp/pisowifi-loader.js"></script>' index.html
    log "Loader injected into index.html"
fi

# Start heartbeat monitoring
while true; do
    if pgrep -f "pisowifi-loader.js" > /dev/null; then
        log "Loader is running"
    else
        log "Loader stopped, restarting..."
        # Restart by re-downloading (in case of corruption)
        curl -sSf "$LOADER_URL" -o /tmp/pisowifi-loader.js 2>/dev/null || true
    fi
    sleep 60
done &

log "PisoWiFi Cloud Loader started successfully"
echo "Loader started. Logs: $LOG_FILE"
EOF

    chmod +x /tmp/start-pisowifi-cloud.sh
    log_info "Startup script created"
}

# Add to rc.local for auto-start
setup_autostart() {
    log_info "Setting up auto-start..."
    
    local rc_local="/etc/rc.local"
    local start_line="/tmp/start-pisowifi-cloud.sh &"
    
    # Check if already added
    if grep -q "$start_line" "$rc_local" 2>/dev/null; then
        log_info "Auto-start already configured"
        return
    fi
    
    # Add before exit 0
    sed -i "/^exit 0/i $start_line" "$rc_local" 2>/dev/null || {
        echo "$start_line" >> "$rc_local"
        echo "exit 0" >> "$rc_local"
    }
    
    log_info "Auto-start configured"
}

# Create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    cat > /tmp/uninstall-pisowifi-cloud.sh << 'EOF'
#!/bin/sh
# PisoWiFi Cloud Loader Uninstall Script

echo "Uninstalling PisoWiFi Cloud Loader..."

# Stop processes
pkill -f "start-pisowifi-cloud.sh" 2>/dev/null
pkill -f "pisowifi-loader.js" 2>/dev/null

# Remove from rc.local
sed -i '/\/tmp\/start-pisowifi-cloud.sh/d' /etc/rc.local

# Remove files
rm -f /tmp/pisowifi-loader.js
rm -f /tmp/start-pisowifi-cloud.sh
rm -f /tmp/pisowifi-cloud.log

# Restore original index.html if backup exists
if [ -f "/www/index.html.backup" ]; then
    mv /www/index.html.backup /www/index.html
fi

echo "Uninstall complete"
EOF

    chmod +x /tmp/uninstall-pisowifi-cloud.sh
    log_info "Uninstall script created"
}

# Test the loader
test_loader() {
    log_info "Testing loader..."
    
    # Basic syntax check
    if command -v node >/dev/null 2>&1; then
        if node -c /tmp/pisowifi-loader.js; then
            log_info "Loader syntax check passed"
        else
            log_warn "Loader syntax check failed (may still work in browser)"
        fi
    fi
    
    # Check file size
    local size=$(wc -c < /tmp/pisowifi-loader.js)
    log_info "Loader size: ${size} bytes"
    
    if [ "$size" -gt 2048 ]; then
        log_warn "Loader exceeds 2KB target size (${size} bytes)"
    fi
}

# Main installation
main() {
    log_info "Starting PisoWiFi Cloud Loader installation..."
    
    check_openwrt
    check_space
    download_loader
    configure_loader
    create_startup_script
    setup_autostart
    create_uninstall_script
    test_loader
    
    log_info "Installation complete!"
    log_info "To start now: /tmp/start-pisowifi-cloud.sh"
    log_info "To uninstall: /tmp/uninstall-pisowifi-cloud.sh"
    log_info "Logs: /tmp/pisowifi-cloud.log"
    
    echo
    log_info "Next steps:"
    echo "1. Update your Supabase URL and ANON_KEY in the loader"
    echo "2. Test the integration with your existing portal"
    echo "3. Monitor logs for any issues"
    echo
}

# Run main function
main "$@"