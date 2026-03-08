// Hotspot Configuration JavaScript
class HotspotManager {
    constructor() {
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadCurrentSettings();
        this.updateTXPowerDisplay();
        this.startStatusUpdates();
    }

    setupEventListeners() {
        // TX Power slider
        const txPowerSlider = document.getElementById('tx-power');
        if (txPowerSlider) {
            txPowerSlider.addEventListener('input', () => {
                this.updateTXPowerDisplay();
            });
        }

        // Form submissions
        document.getElementById('hotspot-basic-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveBasicSettings();
        });

        document.getElementById('hotspot-advanced-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveAdvancedSettings();
        });

        document.getElementById('wifi-interface-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveInterfaceSettings();
        });

        document.getElementById('portal-settings-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.savePortalSettings();
        });
    }

    updateTXPowerDisplay() {
        const txPowerSlider = document.getElementById('tx-power');
        const txPowerValue = document.getElementById('tx-power-value');
        if (txPowerSlider && txPowerValue) {
            txPowerValue.textContent = txPowerSlider.value + '%';
        }
    }

    loadCurrentSettings() {
        // Load current settings from server (simulated)
        const settings = {
            basic: {
                ssid: 'PisoWiFi_Free',
                password: '',
                hotspot_ip: '10.0.0.1',
                dhcp_start: '10.0.0.10',
                dhcp_end: '10.0.0.250'
            },
            advanced: {
                max_users: 50,
                session_timeout: 60,
                bandwidth_limit: 2,
                captive_portal: true
            },
            interface: {
                wifi_interface: 'wlan0',
                channel: 'auto',
                tx_power: 80
            },
            portal: {
                portal_title: 'Welcome to PisoWiFi',
                portal_message: 'Connect to enjoy fast and reliable internet access. Purchase a voucher to get started!',
                redirect_url: 'https://www.google.com',
                auto_logout: 30
            }
        };

        this.populateForms(settings);
    }

    populateForms(settings) {
        // Basic settings
        Object.keys(settings.basic).forEach(key => {
            const element = document.getElementById(key.replace('_', '-'));
            if (element) {
                element.value = settings.basic[key];
            }
        });

        // Advanced settings
        Object.keys(settings.advanced).forEach(key => {
            const element = document.getElementById(key.replace('_', '-'));
            if (element) {
                if (element.type === 'checkbox') {
                    element.checked = settings.advanced[key];
                } else {
                    element.value = settings.advanced[key];
                }
            }
        });

        // Interface settings
        Object.keys(settings.interface).forEach(key => {
            const element = document.getElementById(key.replace('_', '-'));
            if (element) {
                element.value = settings.interface[key];
            }
        });

        // Portal settings
        Object.keys(settings.portal).forEach(key => {
            const element = document.getElementById(key.replace('_', '-'));
            if (element) {
                element.value = settings.portal[key];
            }
        });
    }

    saveBasicSettings() {
        const formData = new FormData(document.getElementById('hotspot-basic-form'));
        const settings = Object.fromEntries(formData);
        
        // Validate IP addresses
        if (!this.validateIP(settings.hotspot_ip)) {
            alert('Invalid Hotspot IP address');
            return;
        }

        if (!this.validateIP(settings.dhcp_start) || !this.validateIP(settings.dhcp_end)) {
            alert('Invalid DHCP range');
            return;
        }

        // Save settings (simulated)
        console.log('Saving basic settings:', settings);
        this.showNotification('Basic settings saved successfully!', 'success');
        
        // Apply settings
        this.applySettings(settings, 'basic');
    }

    saveAdvancedSettings() {
        const formData = new FormData(document.getElementById('hotspot-advanced-form'));
        const settings = Object.fromEntries(formData);
        
        // Convert checkbox value
        settings.captive_portal = document.getElementById('captive-portal').checked;
        
        console.log('Saving advanced settings:', settings);
        this.showNotification('Advanced settings saved successfully!', 'success');
        this.applySettings(settings, 'advanced');
    }

    saveInterfaceSettings() {
        const formData = new FormData(document.getElementById('wifi-interface-form'));
        const settings = Object.fromEntries(formData);
        
        console.log('Saving interface settings:', settings);
        this.showNotification('Interface settings saved successfully!', 'success');
        this.applySettings(settings, 'interface');
    }

    savePortalSettings() {
        const formData = new FormData(document.getElementById('portal-settings-form'));
        const settings = Object.fromEntries(formData);
        
        console.log('Saving portal settings:', settings);
        this.showNotification('Portal settings saved successfully!', 'success');
        this.applySettings(settings, 'portal');
    }

    applySettings(settings, type) {
        // Simulate applying settings
        setTimeout(() => {
            this.updateStatus();
        }, 1000);
    }

    validateIP(ip) {
        const ipRegex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
        return ipRegex.test(ip);
    }

    testHotspot() {
        const button = event.target;
        const originalText = button.textContent;
        
        button.textContent = 'Testing...';
        button.disabled = true;
        
        // Simulate hotspot test
        setTimeout(() => {
            const isSuccess = Math.random() > 0.2; // 80% success rate
            
            if (isSuccess) {
                this.showNotification('Hotspot test successful!', 'success');
            } else {
                this.showNotification('Hotspot test failed. Please check your settings.', 'error');
            }
            
            button.textContent = originalText;
            button.disabled = false;
        }, 3000);
    }

    startStatusUpdates() {
        this.updateStatus();
        setInterval(() => {
            this.updateStatus();
        }, 5000); // Update every 5 seconds
    }

    updateStatus() {
        // Simulate status updates
        const status = {
            service: Math.random() > 0.1 ? 'Running' : 'Stopped',
            interface: Math.random() > 0.05 ? 'Up' : 'Down',
            users: Math.floor(Math.random() * 25),
            signal: -(Math.floor(Math.random() * 30) + 30) + ' dBm'
        };

        this.updateStatusDisplay(status);
    }

    updateStatusDisplay(status) {
        const elements = {
            'service-status': status.service,
            'interface-status': status.interface,
            'connected-users': status.users,
            'signal-strength': status.signal
        };

        Object.keys(elements).forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = elements[id];
                
                // Update status color
                if (id.includes('status')) {
                    element.className = elements[id] === 'Running' || elements[id] === 'Up' 
                        ? 'status-active' : 'status-inactive';
                }
            }
        });
    }

    showNotification(message, type = 'info') {
        // Create notification element
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.textContent = message;
        
        // Style the notification
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px 20px;
            border-radius: 8px;
            color: white;
            font-weight: 500;
            z-index: 10000;
            max-width: 300px;
            word-wrap: break-word;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        `;
        
        // Set background color based on type
        const colors = {
            success: '#27ae60',
            error: '#e74c3c',
            warning: '#f39c12',
            info: '#3498db'
        };
        notification.style.backgroundColor = colors[type] || colors.info;
        
        document.body.appendChild(notification);
        
        // Remove notification after 4 seconds
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 4000);
    }
}

// Global functions
function saveHotspotSettings() {
    const manager = new HotspotManager();
    manager.saveBasicSettings();
    manager.saveAdvancedSettings();
    manager.saveInterfaceSettings();
    manager.savePortalSettings();
}

function testHotspot() {
    const manager = new HotspotManager();
    manager.testHotspot();
}

// Initialize hotspot manager
document.addEventListener('DOMContentLoaded', () => {
    new HotspotManager();
});