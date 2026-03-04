# PisoWiFi System for OpenWrt

This is a replacement for the LuCI interface in OpenWrt with a custom PisoWiFi management system.

## Files Created

### 1. `/www/index.html`
- Frontend interface using Tailwind CSS (CDN) and Alpine.js
- Tabbed interface with Status, WiFi, License, and Sales tabs
- Uses fetch('/cgi-bin/api') to communicate with backend

### 2. `/www/cgi-bin/api`
- Shell script backend compatible with BusyBox Ash
- Handles multiple actions via query parameters
- Uses UCI commands to interact with router settings

## Features

### Status Tab
- Router hostname and uptime
- WAN and LAN IP addresses
- Real-time status updates

### WiFi Tab
- SSID configuration
- WiFi key/password management
- Uses UCI wireless settings

### License Tab
- Centralized key management
- Custom UCI configuration section

### Sales Tab
- Daily sales tracking
- Session count monitoring
- Extensible for custom sales data

## API Endpoints

The CGI script supports these actions:

- `?action=get_status` - Get system status
- `?action=get_wifi` - Get WiFi settings
- `?action=set_wifi` - Set WiFi settings (POST)
- `?action=get_license` - Get license settings
- `?action=set_license` - Set license settings (POST)
- `?action=get_sales` - Get sales data

## Deployment Instructions

### On OpenWrt Router:

1. **Copy files to router:**
   ```bash
   scp www/index.html root@192.168.1.1:/www/
   scp www/cgi-bin/api root@192.168.1.1:/www/cgi-bin/
   ```

2. **Make CGI script executable:**
   ```bash
   ssh root@192.168.1.1
   chmod +x /www/cgi-bin/api
   ```

3. **Install required packages (if not already installed):**
   ```bash
   opkg update
   opkg install uci
   ```

4. **Access the interface:**
   Open `http://192.168.1.1/index.html` in your browser

### Configuration

The system uses UCI (Unified Configuration Interface) to manage router settings:

- WiFi settings are stored in `wireless` config
- License settings are stored in custom `pisowifi` config
- Sales data can be logged to `/tmp/pisowifi_sales.log`

### Security Notes

- The CGI script runs with root privileges
- WiFi passwords are handled securely through UCI
- Consider implementing authentication for production use
- Use HTTPS if deploying on public networks

### Customization

You can extend the system by:

1. Adding new actions to the CGI script
2. Adding new tabs to the HTML interface
3. Integrating with your existing PisoWiFi backend
4. Adding database support for sales tracking
5. Implementing user authentication

### Troubleshooting

- Check browser console for JavaScript errors
- Verify CGI script permissions (must be executable)
- Check UCI configuration exists for wireless settings
- Monitor `/tmp/pisowifi_sales.log` for sales data issues

## Requirements

- OpenWrt with BusyBox shell
- UCI (Unified Configuration Interface)
- Web server (uHTTPd) with CGI support
- No Node.js or external dependencies required

## File Structure

```
/www/
├── index.html          # Main interface
└── cgi-bin/
    └── api             # CGI backend script
```