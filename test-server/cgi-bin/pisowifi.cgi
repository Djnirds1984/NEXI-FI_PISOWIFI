#!/usr/bin/env ucode

'use strict';

import { fs } from 'fs';
import { uci } from 'uci';

// PisoWiFi Web Interface Handler
const PISOWIFI_ROOT = '/www/pisowifi';
const CAPTIVE_PORTAL_IP = '10.0.0.1';

function getClientIP() {
    return getenv('REMOTE_ADDR') || '127.0.0.1';
}

function isCaptivePortalRequest() {
    const clientIP = getClientIP();
    return clientIP.startsWith('10.0.0.');
}

function serveFile(path) {
    const fullPath = PISOWIFI_ROOT + path;
    
    if (!fs.access(fullPath, 'r')) {
        return serve404();
    }
    
    const content = fs.readfile(fullPath);
    const ext = path.match(/\.([^.]+)$/)[1];
    
    const contentTypes = {
        'html': 'text/html',
        'css': 'text/css',
        'js': 'application/javascript',
        'json': 'application/json',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'svg': 'image/svg+xml',
        'ico': 'image/x-icon'
    };
    
    print(`Content-Type: ${contentTypes[ext] || 'application/octet-stream'}\n`);
    return content;
}

function serve404() {
    print('Content-Type: text/html\n');
    return `<!DOCTYPE html>
<html>
<head>
    <title>404 - Not Found</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .error { color: #e74c3c; }
    </style>
</head>
<body>
    <h1 class="error">404 - Page Not Found</h1>
    <p>The requested page could not be found.</p>
    <a href="/pisowifi/">← Back to PisoWiFi</a>
</body>
</html>`;
}

function serveCaptivePortal() {
    const clientIP = getClientIP();
    
    print('Content-Type: text/html\n');
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PisoWiFi - Internet Access Portal</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .portal-container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            padding: 40px;
            max-width: 500px;
            width: 100%;
            text-align: center;
        }
        
        .logo {
            font-size: 3rem;
            margin-bottom: 10px;
        }
        
        h1 {
            color: #2c3e50;
            margin-bottom: 10px;
            font-size: 2rem;
        }
        
        .subtitle {
            color: #7f8c8d;
            margin-bottom: 30px;
            font-size: 1.1rem;
        }
        
        .voucher-form {
            margin-bottom: 30px;
        }
        
        .form-group {
            margin-bottom: 20px;
            text-align: left;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            color: #2c3e50;
            font-weight: 500;
        }
        
        .form-group input {
            width: 100%;
            padding: 15px;
            border: 2px solid #e0e6ed;
            border-radius: 10px;
            font-size: 1rem;
            transition: all 0.3s ease;
        }
        
        .form-group input:focus {
            outline: none;
            border-color: #3498db;
            box-shadow: 0 0 0 3px rgba(52, 152, 219, 0.1);
        }
        
        .btn {
            background: linear-gradient(135deg, #3498db, #2980b9);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 10px;
            font-size: 1.1rem;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            width: 100%;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.4);
        }
        
        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: none;
        }
        
        .packages {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 15px;
            margin: 30px 0;
        }
        
        .package {
            background: #f8f9fa;
            border: 2px solid #e9ecef;
            border-radius: 10px;
            padding: 20px 10px;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        
        .package:hover {
            border-color: #3498db;
            transform: translateY(-2px);
        }
        
        .package.selected {
            border-color: #3498db;
            background: #e3f2fd;
        }
        
        .package-duration {
            font-size: 1.2rem;
            font-weight: 600;
            color: #2c3e50;
        }
        
        .package-price {
            font-size: 1.1rem;
            color: #27ae60;
            margin-top: 5px;
        }
        
        .status {
            margin-top: 20px;
            padding: 15px;
            border-radius: 10px;
            font-weight: 500;
        }
        
        .status.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .status.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        .status.info {
            background: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
        }
        
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #e9ecef;
            color: #7f8c8d;
            font-size: 0.9rem;
        }
        
        @media (max-width: 480px) {
            .portal-container {
                padding: 30px 20px;
            }
            
            .logo {
                font-size: 2.5rem;
            }
            
            h1 {
                font-size: 1.5rem;
            }
            
            .packages {
                grid-template-columns: 1fr 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="portal-container">
        <div class="logo">🌐</div>
        <h1>PisoWiFi Portal</h1>
        <p class="subtitle">Connect to enjoy fast and reliable internet access</p>
        
        <div class="packages">
            <div class="package" onclick="selectPackage(30, 5)">
                <div class="package-duration">30 min</div>
                <div class="package-price">₱5</div>
            </div>
            <div class="package" onclick="selectPackage(60, 10)">
                <div class="package-duration">1 hour</div>
                <div class="package-price">₱10</div>
            </div>
            <div class="package" onclick="selectPackage(180, 25)">
                <div class="package-duration">3 hours</div>
                <div class="package-price">₱25</div>
            </div>
            <div class="package" onclick="selectPackage(360, 45)">
                <div class="package-duration">6 hours</div>
                <div class="package-price">₱45</div>
            </div>
        </div>
        
        <form class="voucher-form" onsubmit="connect(event)">
            <div class="form-group">
                <label for="voucher-code">Enter Voucher Code:</label>
                <input type="text" id="voucher-code" placeholder="e.g., PISO2024001" required>
            </div>
            <input type="hidden" id="selected-duration" value="">
            <input type="hidden" id="selected-price" value="">
            <button type="submit" class="btn">Connect to Internet</button>
        </form>
        
        <div id="status"></div>
        
        <div class="footer">
            <p>Need help? Contact support at your location.</p>
            <p>Valid voucher formats: PISO + numbers</p>
        </div>
    </div>

    <script>
        let selectedPackage = null;
        
        function selectPackage(duration, price) {
            // Remove previous selection
            document.querySelectorAll('.package').forEach(p => p.classList.remove('selected'));
            
            // Add selection to clicked package
            event.target.closest('.package').classList.add('selected');
            
            selectedPackage = { duration, price };
            document.getElementById('selected-duration').value = duration;
            document.getElementById('selected-price').value = price;
            
            // Auto-fill voucher code if not already filled
            const voucherCode = document.getElementById('voucher-code');
            if (!voucherCode.value) {
                voucherCode.value = 'PISO' + Date.now().toString().slice(-6);
            }
        }
        
        function connect(event) {
            event.preventDefault();
            
            const voucherCode = document.getElementById('voucher-code').value.trim();
            const statusDiv = document.getElementById('status');
            const submitBtn = event.target.querySelector('button[type="submit"]');
            
            // Validate voucher code format
            if (!voucherCode.match(/^PISO\d{6,}$/)) {
                showStatus('Invalid voucher code format. Use format: PISO + numbers', 'error');
                return;
            }
            
            // Disable submit button
            submitBtn.disabled = true;
            submitBtn.textContent = 'Connecting...';
            
            // Simulate voucher validation
            setTimeout(() => {
                // In real implementation, this would call the API
                const isValid = Math.random() > 0.2; // 80% success rate
                
                if (isValid) {
                    showStatus('✅ Voucher validated! Redirecting to internet...', 'success');
                    
                    // Simulate internet access grant
                    setTimeout(() => {
                        // Redirect to original requested URL or default page
                        const redirectUrl = new URLSearchParams(window.location.search).get('redirect') || 'http://www.google.com';
                        window.location.href = redirectUrl;
                    }, 2000);
                } else {
                    showStatus('❌ Invalid or expired voucher code. Please try again.', 'error');
                    submitBtn.disabled = false;
                    submitBtn.textContent = 'Connect to Internet';
                }
            }, 2000);
        }
        
        function showStatus(message, type) {
            const statusDiv = document.getElementById('status');
            statusDiv.className = `status ${type}`;
            statusDiv.textContent = message;
            statusDiv.style.display = 'block';
            
            // Hide status after 5 seconds
            setTimeout(() => {
                statusDiv.style.display = 'none';
            }, 5000);
        }
        
        // Auto-generate voucher code on page load
        document.addEventListener('DOMContentLoaded', () => {
            const voucherCode = document.getElementById('voucher-code');
            voucherCode.placeholder = 'e.g., PISO' + Date.now().toString().slice(-6);
        });
    </script>
</body>
</html>`;
}

function handleAPI() {
    const path = getenv('PATH_INFO') || '';
    
    if (path.contains('/api/hotspot')) {
        return handleHotspotAPI();
    } else if (path.contains('/api/vouchers')) {
        return handleVoucherAPI();
    } else if (path.contains('/api/status')) {
        return handleStatusAPI();
    }
    
    print('Content-Type: application/json\n');
    return json({ success: false, message: 'Invalid API endpoint' });
}

function handleHotspotAPI() {
    const config = loadConfig();
    
    if (getenv('REQUEST_METHOD') === 'POST') {
        const input = io.stdin.read(4096);
        const data = json(input || '{}');
        
        if (saveConfig(data)) {
            applySettings(data);
            print('Content-Type: application/json\n');
            return json({ success: true, message: 'Settings applied' });
        }
    }
    
    print('Content-Type: application/json\n');
    return json({ success: true, data: config });
}

function handleVoucherAPI() {
    const config = loadConfig();
    
    if (getenv('REQUEST_METHOD') === 'POST') {
        const input = io.stdin.read(4096);
        const data = json(input || '{}');
        
        if (data.action === 'validate') {
            const code = data.code;
            const voucher = findVoucher(code);
            
            if (voucher && voucher.status === 'active') {
                // Mark voucher as used
                voucher.status = 'used';
                voucher.used_by = getenv('REMOTE_ADDR');
                voucher.used_time = new Date().toISOString();
                saveConfig(config);
                
                print('Content-Type: application/json\n');
                return json({ success: true, valid: true, duration: voucher.duration });
            } else {
                print('Content-Type: application/json\n');
                return json({ success: true, valid: false, message: 'Invalid or expired voucher' });
            }
        }
    }
    
    print('Content-Type: application/json\n');
    return json({ success: true, vouchers: config.vouchers });
}

function handleStatusAPI() {
    const config = loadConfig();
    
    const status = {
        hotspot: {
            enabled: config.hotspot?.enabled === '1',
            ssid: config.hotspot?.ssid || 'PisoWiFi_Free',
            ip: config.hotspot?.ip || CAPTIVE_PORTAL_IP,
            clients: getConnectedClients(),
            uptime: system('uptime | awk "{print $3,$4}"') || 'Unknown'
        },
        system: {
            memory: getMemoryUsage(),
            storage: getStorageUsage(),
            load: system('uptime | awk -F"load average:" "{print $2}"') || 'Unknown'
        }
    };
    
    print('Content-Type: application/json\n');
    return json({ success: true, status: status });
}

function loadConfig() {
    try {
        const cursor = uci.cursor();
        cursor.load('pisowifi');
        
        return {
            hotspot: cursor.get_all('pisowifi', 'hotspot') || {},
            vouchers: cursor.get_all('pisowifi', 'vouchers') || {},
            network: cursor.get_all('pisowifi', 'network') || {}
        };
    } catch (e) {
        return {
            hotspot: { enabled: '1', ssid: 'PisoWiFi_Free', ip: CAPTIVE_PORTAL_IP },
            vouchers: {},
            network: {}
        };
    }
}

function saveConfig(config) {
    try {
        const cursor = uci.cursor();
        
        // Save each section
        for (let section, data in config) {
            cursor.set('pisowifi', section, null, 'section');
            for (let key, value in data) {
                cursor.set('pisowifi', section, key, value);
            }
        }
        
        cursor.commit('pisowifi');
        return true;
    } catch (e) {
        return false;
    }
}

function findVoucher(code) {
    const config = loadConfig();
    for (let id, voucher in config.vouchers) {
        if (voucher.code === code) {
            return voucher;
        }
    }
    return null;
}

function getConnectedClients() {
    try {
        const output = system('iwinfo wlan0 assoclist 2>/dev/null | grep -c "^[0-9]"');
        return tonumber(output) || 0;
    } catch (e) {
        return 0;
    }
}

function getMemoryUsage() {
    try {
        const meminfo = fs.readfile('/proc/meminfo');
        const total = tonumber(meminfo.match(/MemTotal:\s+(\d+)/)[1]) || 0;
        const free = tonumber(meminfo.match(/MemFree:\s+(\d+)/)[1]) || 0;
        const available = tonumber(meminfo.match(/MemAvailable:\s+(\d+)/)[1]) || 0;
        
        return {
            total: total,
            free: free,
            available: available,
            used: total - available,
            percentage: math.floor((total - available) / total * 100)
        };
    } catch (e) {
        return { total: 0, free: 0, available: 0, used: 0, percentage: 0 };
    }
}

function getStorageUsage() {
    try {
        const df = system('df / | tail -1');
        const parts = df.split(/\s+/);
        const total = tonumber(parts[1]) || 0;
        const used = tonumber(parts[2]) || 0;
        const free = tonumber(parts[3]) || 0;
        
        return {
            total: total * 1024,
            used: used * 1024,
            free: free * 1024,
            percentage: math.floor(used / total * 100)
        };
    } catch (e) {
        return { total: 0, used: 0, free: 0, percentage: 0 };
    }
}

function applySettings(config) {
    try {
        // Apply wireless settings
        const cursor = uci.cursor();
        
        if (config.hotspot) {
            cursor.set('wireless', '@wifi-iface[0]', 'ssid', config.hotspot.ssid);
            cursor.set('wireless', '@wifi-iface[0]', 'key', config.hotspot.password || '');
            cursor.set('wireless', '@wifi-iface[0]', 'mode', 'ap');
            cursor.set('wireless', '@wifi-iface[0]', 'network', 'lan');
            
            cursor.set('network', 'lan', 'ipaddr', config.hotspot.ip);
            cursor.set('network', 'lan', 'netmask', '255.255.255.0');
        }
        
        cursor.commit('wireless');
        cursor.commit('network');
        
        // Restart services
        system('wifi reload');
        system('/etc/init.d/network restart');
        
        return true;
    } catch (e) {
        return false;
    }
}

function main() {
    const path = getenv('PATH_INFO') || getenv('REQUEST_URI') || '';
    const method = getenv('REQUEST_METHOD') || 'GET';
    
    // Handle API requests
    if (path.contains('/api/')) {
        return handleAPI();
    }
    
    // Handle captive portal requests
    if (isCaptivePortalRequest() && !path.contains('/pisowifi/')) {
        return serveCaptivePortal();
    }
    
    // Serve static files
    let filePath = path;
    if (filePath === '' || filePath === '/') {
        filePath = '/index.html';
    }
    
    return serveFile(filePath);
}

// Run the main function
main();