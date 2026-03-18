// PisoWiFi Cloud Loader - Ultra Lightweight (2KB)
// Direct Supabase integration for OpenWrt devices

(function() {
    'use strict';
    
    const CONFIG = {
        supabaseUrl: 'https://fuiabtdflbodglfexvln.supabase.co',
        supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo',
        machineId: 'machine_001', // Dynamic per device
        heartbeatInterval: 30000, // 30 seconds
        syncInterval: 300000, // 5 minutes
        maxRetries: 3
    };
    
    let deviceState = {
        isConnected: false,
        sessionToken: null,
        lastSync: 0,
        retryCount: 0
    };
    
    // Minimal fetch wrapper with retry logic
    async function apiFetch(endpoint, options = {}) {
        const url = CONFIG.supabaseUrl + '/rest/v1/' + endpoint;
        const headers = {
            'apikey': CONFIG.supabaseAnonKey,
            'Authorization': `Bearer ${CONFIG.supabaseAnonKey}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
            ...options.headers
        };
        
        for (let i = 0; i < CONFIG.maxRetries; i++) {
            try {
                const response = await fetch(url, { ...options, headers });
                if (response.ok) return await response.json();
            } catch (e) {
                if (i === CONFIG.maxRetries - 1) throw e;
                await new Promise(r => setTimeout(r, 1000 * (i + 1)));
            }
        }
    }
    
    // Device authentication
    async function authenticateDevice() {
        try {
            const [device] = await apiFetch('wifi_devices?machine_id=eq.' + CONFIG.machineId + '&select=session_token,is_connected');
            if (device && device.session_token) {
                deviceState.sessionToken = device.session_token;
                deviceState.isConnected = device.is_connected;
                return true;
            }
        } catch (e) {
            console.log('Auth failed:', e.message);
        }
        return false;
    }
    
    // Send heartbeat to cloud
    async function sendHeartbeat() {
        try {
            await apiFetch('wifi_devices?machine_id=eq.' + CONFIG.machineId, {
                method: 'PATCH',
                body: JSON.stringify({
                    last_heartbeat: new Date().toISOString(),
                    is_connected: true
                })
            });
            deviceState.lastSync = Date.now();
        } catch (e) {
            console.log('Heartbeat failed:', e.message);
        }
    }
    
    // Get device configuration from cloud
    async function getDeviceConfig() {
        try {
            const [config] = await apiFetch('device_configs?machine_id=eq.' + CONFIG.machineId + '&select=config_data');
            return config ? JSON.parse(config.config_data) : null;
        } catch (e) {
            return null;
        }
    }
    
    // Update session status
    async function updateSession(status) {
        if (!deviceState.sessionToken) return;
        
        try {
            await apiFetch('wifi_devices?session_token=eq.' + deviceState.sessionToken, {
                method: 'PATCH',
                body: JSON.stringify({
                    is_session_active: status,
                    last_session_update: new Date().toISOString()
                })
            });
        } catch (e) {
            console.log('Session update failed:', e.message);
        }
    }
    
    // Main initialization
    async function init() {
        console.log('PisoWiFi Cloud Loader starting...');
        
        // Authenticate device
        if (!await authenticateDevice()) {
            console.log('Device authentication failed, retrying in 30s');
            setTimeout(init, 30000);
            return;
        }
        
        console.log('Device authenticated successfully');
        
        // Start heartbeat
        setInterval(sendHeartbeat, CONFIG.heartbeatInterval);
        await sendHeartbeat(); // Initial heartbeat
        
        // Get device configuration
        const config = await getDeviceConfig();
        if (config) {
            console.log('Device config loaded:', config);
            // Apply configuration to local device
            if (config.coin_rate) localStorage.setItem('coin_rate', config.coin_rate);
            if (config.session_timeout) localStorage.setItem('session_timeout', config.session_timeout);
        }
        
        // Setup UI handlers
        setupUI();
        
        console.log('PisoWiFi Cloud Loader ready');
    }
    
    // Setup minimal UI
    function setupUI() {
        // Create minimal UI container
        const container = document.createElement('div');
        container.id = 'pw-cloud-ui';
        container.innerHTML = `
            <div style="position:fixed;top:10px;right:10px;background:#333;color:#fff;padding:5px 10px;border-radius:5px;font-size:12px;z-index:9999">
                <span id="pw-status">🟡 Connecting...</span>
                <span id="pw-coins">Coins: 0</span>
            </div>
        `;
        document.body.appendChild(container);
        
        // Update status display
        setInterval(() => {
            const status = document.getElementById('pw-status');
            const coins = document.getElementById('pw-coins');
            
            if (deviceState.isConnected) {
                status.textContent = '🟢 Connected';
                status.style.color = '#4ade80';
            } else {
                status.textContent = '🔴 Offline';
                status.style.color = '#ef4444';
            }
            
            // Update coins from local storage or API
            const currentCoins = localStorage.getItem('current_coins') || '0';
            coins.textContent = `Coins: ${currentCoins}`;
        }, 1000);
    }
    
    // Handle coin insertion (called from your existing coinslot logic)
    window.handleCoinInsert = async function(coins) {
        if (!deviceState.sessionToken) return;
        
        try {
            await apiFetch('wifi_devices?session_token=eq.' + deviceState.sessionToken, {
                method: 'PATCH',
                body: JSON.stringify({
                    coins_used: { coins_used: '+${coins}' }, // Increment coins
                    total_paid: { total_paid: '+${coins * 5}' } // Assuming 5 pesos per coin
                })
            });
            
            // Update local storage
            const current = parseInt(localStorage.getItem('current_coins') || '0');
            localStorage.setItem('current_coins', (current + coins).toString());
            
            console.log(`Coin insert recorded: ${coins} coins`);
        } catch (e) {
            console.log('Coin recording failed:', e.message);
        }
    };
    
    // Handle session start (called from your existing portal)
    window.startCloudSession = async function() {
        await updateSession(true);
        console.log('Cloud session started');
    };
    
    // Handle session end (called from your existing portal)
    window.endCloudSession = async function() {
        await updateSession(false);
        localStorage.removeItem('current_coins');
        console.log('Cloud session ended');
    };
    
    // Start the loader
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
    
})();