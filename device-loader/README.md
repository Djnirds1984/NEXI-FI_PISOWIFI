# PisoWiFi Cloud Device Loader

Ultra-lightweight (2KB) device loader for OpenWrt PisoWiFi systems with direct Supabase integration. Runs entirely in RAM with zero server-side JavaScript on devices.

## 🚀 Features

- **Ultra-lightweight**: Only 2KB in size, perfect for resource-constrained OpenWrt devices
- **Zero server-side JS**: Runs entirely in browser, no Node.js required on devices
- **Direct Supabase integration**: Real-time database connectivity without middleware
- **Automatic device authentication**: Uses existing session tokens from your PisoWiFi system
- **Real-time heartbeat monitoring**: 30-second intervals to track device health
- **Session management**: Centralized session control across all devices
- **Coin tracking**: Automatic recording of coin insertions and revenue
- **Dynamic configuration**: Remote configuration updates without device restart
- **RAM-based execution**: Downloads to `/tmp` folder, no persistent storage usage
- **Auto-restart on boot**: Integrated with `/etc/rc.local` for automatic startup

## 📦 Installation

### Quick Install (OpenWrt)

```bash
# Download and run the installation script
curl -sSf https://raw.githubusercontent.com/your-repo/pisowifi-cloud/main/device-loader/install-loader.sh | sh

# Or manually:
wget https://your-domain.com/install-loader.sh
chmod +x install-loader.sh
./install-loader.sh
```

### Manual Installation

1. **Download the loader**:
```bash
curl -sSf https://your-domain.com/pisowifi-loader.js -o /tmp/pisowifi-loader.js
```

2. **Configure your portal**:
```bash
# Add to your existing index.html before </body>
echo '<script src="file:///tmp/pisowifi-loader.js"></script>' >> /www/index.html
```

3. **Add to startup**:
```bash
echo "/tmp/start-pisowifi-cloud.sh &" >> /etc/rc.local
```

## 🔧 Configuration

The loader automatically uses your Supabase credentials:

- **Supabase URL**: `https://fuiabtdflbodglfexvln.supabase.co`
- **Supabase Anon Key**: Already embedded in the loader
- **Machine ID**: Auto-detected from `/etc/machine-id` or generated

## 📊 Usage

### Basic Integration

Add these functions to your existing portal code:

```javascript
// When coin is inserted
window.handleCoinInsert(5); // 5 coins inserted

// When session starts
window.startCloudSession();

// When session ends
window.endCloudSession();
```

### Custom Events

```javascript
// Update device status
await updateDeviceStatus('online', { signal: -45, coins: 25 });

// Get remote configuration
const config = await getDeviceConfig();
if (config.coin_rate) {
    // Apply new coin rate
    localStorage.setItem('coin_rate', config.coin_rate);
}
```

## 📈 Monitoring

### Device Dashboard
Access your cloud dashboard at: `https://your-dashboard.vercel.app`

### Device Logs
Check device logs on each OpenWrt device:
```bash
tail -f /tmp/pisowifi-cloud.log
```

### Database Views
Use these Supabase views for analytics:
- `device_analytics_summary` - Overall device performance
- `revenue_by_device` - Daily revenue tracking
- `network_performance_metrics` - Signal strength analysis

## 🛠️ API Functions

### Device Authentication
```javascript
// Authenticate device with machine ID
const result = await authenticateDevice(machineId);
```

### Heartbeat
```javascript
// Send heartbeat every 30 seconds automatically
await sendHeartbeat();
```

### Session Management
```javascript
// Start/stop sessions
await updateSession(true);   // Start
await updateSession(false);  // Stop
```

### Configuration
```javascript
// Get device configuration from cloud
const config = await getDeviceConfig();
```

## 🔒 Security

- **Anon Key Only**: Uses Supabase anon key (safe for frontend)
- **No Service Role**: Never exposes service role key
- **HTTPS Only**: All communications encrypted
- **Session Token Validation**: Validates existing session tokens
- **Rate Limiting**: Built-in retry logic prevents abuse

## 🚨 Troubleshooting

### Device Not Connecting
1. Check internet connectivity: `ping fuiabtdflbodglfexvln.supabase.co`
2. Verify machine ID in database
3. Check session token validity
4. Review logs: `cat /tmp/pisowifi-cloud.log`

### High Memory Usage
- Loader runs in RAM but only uses ~50KB memory
- Automatically cleans up on device restart
- No persistent storage usage

### Sync Errors
- Automatic retry with exponential backoff
- Maximum 3 retry attempts
- Errors logged to `/tmp/pisowifi-cloud.log`

## 📁 File Structure

```
device-loader/
├── pisowifi-loader.js          # Main device loader (2KB)
├── install-loader.sh          # OpenWrt installation script
├── deploy-loader.sh           # Vercel deployment (Linux/Mac)
├── deploy-windows.bat         # Vercel deployment (Windows)
├── vercel.json                # Vercel configuration
├── package.json               # Package configuration
├── DEPLOYMENT_INFO.md         # Deployment information
├── DEPLOYMENT_SUMMARY.md      # Deployment summary
└── README.md                  # This file
```

## 🚀 Deployment

### Deploy to Vercel (Linux/Mac)
```bash
cd device-loader
chmod +x deploy-loader.sh
./deploy-loader.sh
```

### Deploy to Vercel (Windows)
```cmd
cd device-loader
deploy-windows.bat
```

### Manual Deployment
1. Upload `pisowifi-loader.js` to your web server
2. Update installation script with your URL
3. Ensure CORS headers are configured

## 📊 Performance

- **File Size**: 2KB (compressed)
- **Memory Usage**: ~50KB RAM
- **Network**: 1-2KB per heartbeat
- **CPU**: <1% usage
- **Battery**: Minimal impact

## 🔧 Customization

### Change Heartbeat Interval
Edit `heartbeatInterval` in the loader:
```javascript
const CONFIG = {
    heartbeatInterval: 60000, // 60 seconds
    // ...
};
```

### Add Custom Events
Extend the loader with your events:
```javascript
window.customEvent = async function(data) {
    await apiFetch('custom_events', {
        method: 'POST',
        body: JSON.stringify(data)
    });
};
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on actual OpenWrt device
5. Submit a pull request

## 📄 License

MIT License - Feel free to use in your projects.

## 🆘 Support

- **Issues**: Report on GitHub
- **Documentation**: Check this README
- **Logs**: Review `/tmp/pisowifi-cloud.log`
- **Database**: Check Supabase dashboard

---

**Built for OpenWrt PisoWiFi systems with ❤️**