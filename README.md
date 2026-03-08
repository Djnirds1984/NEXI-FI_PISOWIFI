# PisoWiFi Management System

A comprehensive PisoWiFi management system built exclusively using LuCI framework components for OpenWrt routers. This system provides captive portal functionality, user management, and complete system configuration capabilities.

## Features

### Core Components
- **Captive Portal**: 2.4G/5G WiFi captive portal with payment integration
- **Admin Panel**: Secure login-enabled administration interface with 2FA support
- **System Dashboard**: LuCI-based dashboard displaying CPU, memory, and network statistics
- **WiFi Management**: Full CRUD operations for WiFi network configuration
- **Hotspot Segments**: Create and manage WiFi hotspot segments with custom settings
- **System Settings**: Complete LuCI settings fetch and edit capability for all system configurations

### Additional Features
- **User Management**: Manage WiFi users, sessions, and access control
- **Voucher System**: Create and manage time-based access vouchers
- **Revenue Tracking**: Monitor income and usage statistics
- **System Reports**: Generate detailed usage and revenue reports
- **Firewall Integration**: Automatic firewall rule management for PisoWiFi

## Installation

### Prerequisites
- OpenWrt router with LuCI web interface
- SSH access to the router
- Root privileges

### Quick Installation

1. **Upload the files to your router:**
   ```bash
   # Copy all files to your router via SCP or similar method
   scp -r * root@your-router-ip:/tmp/pisowifi/
   ```

2. **Run the installation script:**
   ```bash
   ssh root@your-router-ip
   cd /tmp/pisowifi
   chmod +x install.sh
   ./install.sh
   ```

3. **Access the web interface:**
   - Open your web browser
   - Navigate to: `http://your-router-ip/cgi-bin/luci/admin/pisowifi`
   - Default login: `admin` / `admin`

### Manual Installation

If you prefer manual installation, follow these steps:

1. **Create necessary directories:**
   ```bash
   mkdir -p /etc/pisowifi
   mkdir -p /usr/lib/lua/luci/model/pisowifi
   mkdir -p /usr/lib/lua/luci/controller/pisowifi
   mkdir -p /www/luci-static/resources/view/pisowifi
   ```

2. **Copy files to appropriate locations:**
   ```bash
   # Copy LuCI view files
   cp luci-static/resources/view/pisowifi/* /www/luci-static/resources/view/pisowifi/
   
   # Copy Lua controller and model files
   cp usr/lib/lua/luci/controller/pisowifi/* /usr/lib/lua/luci/controller/pisowifi/
   cp usr/lib/lua/luci/model/pisowifi/* /usr/lib/lua/luci/model/pisowifi/
   
   # Copy configuration files
   cp etc/config/* /etc/config/
   
   # Set permissions
   chmod 755 /usr/lib/lua/luci/controller/pisowifi/*
   chmod 644 /usr/lib/lua/luci/model/pisowifi/*
   chmod 644 /www/luci-static/resources/view/pisowifi/*
   ```

3. **Create data files:**
   ```bash
   echo '{}' > /etc/pisowifi/vouchers.json
   echo '[]' > /tmp/pisowifi_sessions.json
   chmod 644 /etc/pisowifi/vouchers.json
   chmod 666 /tmp/pisowifi_sessions.json
   ```

4. **Restart services:**
   ```bash
   /etc/init.d/uhttpd restart
   ```

## Configuration

### Initial Setup

1. **Change default password:**
   - Log into the admin panel
   - Navigate to "Admin Panel" → "Change Password"
   - Set a strong password immediately

2. **Configure WiFi settings:**
   - Go to "WiFi Setup" in the sidebar
   - Configure your 2.4G and 5G networks
   - Set appropriate security settings

3. **Set up captive portal:**
   - Navigate to "Captive Portal"
   - Enable the portal for desired WiFi bands
   - Configure pricing and session timeout
   - Customize portal appearance

4. **Configure system settings:**
   - Access "System Settings" for full LuCI configuration
   - Set hostname, timezone, and network parameters
   - Configure firewall rules and DHCP settings

### WiFi Configuration

The system supports both 2.4G and 5G WiFi bands with full configuration options:

- **SSID Configuration**: Set custom network names
- **Security**: WPA2-PSK, WPA3-SAE, or mixed modes
- **Channel Selection**: Auto or manual channel selection
- **Transmit Power**: Adjust power levels for optimal coverage
- **MAC Filtering**: Allow/deny specific devices

### Captive Portal Settings

- **Portal URL**: Customizable authentication page
- **Session Timeout**: Configurable session duration (default: 60 minutes)
- **Pricing**: Set hourly rates in PHP
- **Payment Integration**: Support for various payment methods
- **Custom Branding**: Portal page customization

### Hotspot Segments

Create isolated WiFi segments with different settings:

- **Segment Name**: Custom segment identifiers
- **IP Range**: Dedicated IP address pools
- **Bandwidth Limits**: Per-segment speed restrictions
- **Access Rules**: Custom firewall rules per segment
- **Isolation**: Complete network isolation between segments

## Usage

### Admin Panel

The admin panel provides comprehensive management capabilities:

1. **Dashboard**: Real-time system statistics and user activity
2. **User Management**: View and manage connected users
3. **Voucher System**: Create time-based access codes
4. **Reports**: Generate usage and revenue reports
5. **System Settings**: Full LuCI configuration access

### User Experience

1. **WiFi Connection**: Users connect to configured WiFi networks
2. **Portal Redirect**: Automatic redirect to captive portal
3. **Authentication**: Payment or voucher-based authentication
4. **Internet Access**: Granted access for configured duration
5. **Session Management**: Automatic session tracking and renewal

### Voucher System

Create and manage access vouchers:

- **Time-based**: 1 hour, 3 hours, 1 day, custom duration
- **Bulk Generation**: Generate multiple vouchers at once
- **Usage Tracking**: Monitor voucher usage and status
- **Expiration**: Set voucher expiration dates
- **Export**: Download voucher lists for distribution

## File Structure

```
pisowifi/
├── luci-static/resources/view/pisowifi/
│   ├── admin-panel.js          # Admin panel with login
│   ├── captive-portal.js       # 2.4G/5G captive portal
│   ├── dashboard.js            # System statistics dashboard
│   ├── hotspot-segments.js     # WiFi segment creator
│   ├── menu.js                 # LuCI menu configuration
│   ├── reports.js              # System reports
│   ├── system-settings.js      # Full LuCI settings
│   ├── users.js                # User management
│   ├── vouchers.js             # Voucher management
│   └── wifi-setup.js           # WiFi configuration
├── usr/lib/lua/luci/controller/pisowifi/
│   └── pisowifi.lua            # LuCI controller
├── usr/lib/lua/luci/model/pisowifi/
│   └── pisowifi.lua            # RPC backend
├── etc/config/
│   └── pisowifi                # Main configuration
└── install.sh                  # Installation script
```

## Security Features

### Admin Security
- **Strong Authentication**: Secure login with password hashing
- **Brute Force Protection**: Automatic IP blocking after failed attempts
- **Two-Factor Authentication**: Optional 2FA support
- **Session Management**: Secure admin session handling
- **Access Logging**: Complete admin activity logging

### Network Security
- **Firewall Integration**: Automatic firewall rule management
- **Network Isolation**: Complete isolation between user segments
- **MAC Address Filtering**: Device-level access control
- **Bandwidth Limiting**: Prevent network abuse
- **Session Timeout**: Automatic session expiration

## Troubleshooting

### Common Issues

1. **Portal not redirecting:**
   - Check firewall rules: `iptables -L -n -t nat`
   - Verify DNS configuration
   - Ensure uhttpd is running: `/etc/init.d/uhttpd status`

2. **Users cannot connect:**
   - Verify WiFi configuration in LuCI
   - Check DHCP server status
   - Ensure sufficient IP addresses available

3. **Admin panel not accessible:**
   - Verify file permissions
   - Check LuCI controller registration
   - Restart uhttpd service

4. **Vouchers not working:**
   - Check voucher file permissions
   - Verify voucher format in `/etc/pisowifi/vouchers.json`
   - Review session tracking file `/tmp/pisowifi_sessions.json`

### Log Files

- **System Logs**: `/var/log/messages`
- **PisoWiFi Logs**: `/var/log/pisowifi.log`
- **Revenue Logs**: `/var/log/pisowifi_revenue.log`
- **Web Server Logs**: `/var/log/uhttpd.log`

### Debug Commands

```bash
# Check service status
/etc/init.d/uhttpd status
/etc/init.d/firewall status

# View system logs
logread | grep pisowifi

# Check network configuration
uci show network
uci show wireless

# Verify firewall rules
iptables -L -n -v
iptables -t nat -L -n -v

# Test RPC connectivity
ubus list | grep pisowifi
```

## Performance Optimization

### System Resources
- **Memory Usage**: Monitor RAM usage, especially with many concurrent users
- **CPU Load**: Check CPU usage during peak hours
- **Network Throughput**: Monitor bandwidth utilization
- **Storage Space**: Ensure sufficient space for logs and data

### Optimization Tips
1. **Regular Maintenance**: Clean up old logs and session data
2. **Bandwidth Management**: Implement fair queuing for users
3. **Firewall Optimization**: Use connection tracking efficiently
4. **Database Cleanup**: Regular voucher and user data cleanup

## API Reference

### RPC Methods

The system provides several RPC methods for external integration:

- `pisowifi.get_status`: Get system status
- `pisowifi.get_users`: List active users
- `pisowifi.create_voucher`: Generate new vouchers
- `pisowifi.validate_voucher`: Check voucher validity
- `pisowifi.get_revenue`: Retrieve revenue data

### Example Usage

```javascript
// Get system status
ubus call pisowifi get_status

// Create voucher
ubus call pisowifi create_voucher '{"duration": 3600, "count": 10}'

// Validate voucher
ubus call pisowifi validate_voucher '{"code": "ABC123"}'
```

## Support

For issues and questions:

1. **Check Logs**: Review system and application logs
2. **Documentation**: Refer to OpenWrt and LuCI documentation
3. **Community**: OpenWrt forums and community support
4. **Updates**: Keep system and packages updated

## License

This PisoWiFi system is built using LuCI framework components and follows OpenWrt development standards. Ensure compliance with local regulations regarding internet service provision and billing.

## Disclaimer

This system is provided as-is for educational and legitimate business purposes. Users are responsible for:
- Compliance with local laws and regulations
- Proper configuration and security
- User privacy and data protection
- Financial transaction handling
- Network security and abuse prevention

---

**Note**: Always test thoroughly in a development environment before deploying to production systems.