# PisoWiFi Test Server

This directory contains a local test server for the PisoWiFi system.

## Quick Start

1. Run tests to validate all files:
   `powershell
   .\run-tests.ps1
   `

2. Start the test server:
   `powershell
   .\start-server.ps1
   `

3. Open your browser and navigate to:
   - Dashboard: http://localhost:8080/
   - Hotspot Settings: http://localhost:8080/hotspot.html
   - Vouchers: http://localhost:8080/vouchers.html
   - System Settings: http://localhost:8080/settings.html
   - Logs: http://localhost:8080/logs.html
   - Users: http://localhost:8080/users.html

## Features

- Simulates OpenWrt uhttpd environment
- Provides mock API responses for testing
- Serves static files (HTML, CSS, JS)
- Includes comprehensive test suite
- Real-time log monitoring simulation
- User management simulation

## API Simulation

The test server simulates these API endpoints:
- /cgi-bin/api-real.cgi?action=get_vouchers
- /cgi-bin/api-real.cgi?action=save_voucher
- /cgi-bin/api-real.cgi?action=delete_voucher
- /cgi-bin/api-real.cgi?action=get_settings
- /cgi-bin/api-real.cgi?action=save_settings
- /cgi-bin/api-real.cgi?action=apply_hotspot_settings
- /cgi-bin/api-real.cgi?action=get_connected_users
- /cgi-bin/api-real.cgi?action=get_active_sessions
- /cgi-bin/api-real.cgi?action=get_logs
- /cgi-bin/api-real.cgi?action=get_real_time_logs

## Testing Checklist

- [ ] Dashboard loads correctly
- [ ] Hotspot settings page loads and shows WiFi interfaces
- [ ] Voucher CRUD operations work
- [ ] Settings can be saved and loaded
- [ ] Logs display and update in real-time
- [ ] Users page shows connected clients
- [ ] All buttons respond to clicks
- [ ] Forms validate input correctly
- [ ] Notifications appear for actions
- [ ] Mobile responsiveness works

## Troubleshooting

If the server doesn't start:
1. Check if port 8080 is available
2. Run PowerShell as Administrator
3. Check Windows Firewall settings

If pages don't load:
1. Check browser console for JavaScript errors
2. Verify all files are present using un-tests.ps1
3. Check network tab for API request failures
