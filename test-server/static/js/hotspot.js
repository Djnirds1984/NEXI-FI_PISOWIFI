// Hotspot Configuration JavaScript with Real API Integration
class HotspotManager {
    constructor() {
        this.apiUrl = '/cgi-bin/api-real.cgi';
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

    async loadCurrentSettings() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_hotspot_settings`);
            const data = await response.json();
            
            if (data.success) {
                this.populateForms(data.settings || this.getDefaultSettings());
                await this.loadWiFiInterfaces();
            } else {
                this.showNotification('Failed to load hotspot settings: ' + data.error, 'error');
                this.populateForms(this.getDefaultSettings());
            }
        } catch (error) {
            console.error('Error loading hotspot settings:', error);
            this.showNotification('Error loading hotspot settings from server', 'error');
            this.populateForms(this.getDefaultSettings());
        }
    }

    async loadWiFiInterfaces() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_wifi_interfaces`);
            const data = await response.json();
            
            if (data.success && data.interfaces) {
                this.populateWiFiInterfaces(data.interfaces);
            } else {
                console.warn('Failed to load WiFi interfaces:', data.error);
            }
        } catch (error) {
            console.error('Error loading WiFi interfaces:', error);
        }
    }

    populateWiFiInterfaces(interfaces) {
        const wifiInterfaceSelect = document.getElementById('wifi-interface');
        if (!wifiInterfaceSelect) return;

        // Clear existing options except the first one
        while (wifiInterfaceSelect.options.length > 1) {
            wifiInterfaceSelect.remove(1);
        }

        // Add available interfaces
        interfaces.forEach(iface => {
            const option = document.createElement('option');
            option.value = iface.name;
            option.textContent = `${iface.name} (${iface.description || 'Wireless Interface'})`;
            wifiInterfaceSelect.appendChild(option);
        });
    }

    getDefaultSettings() {
        return {
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

    async saveBasicSettings() {
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

        await this.saveSettingsToAPI('basic', settings);
    }

    async saveAdvancedSettings() {
        const formData = new FormData(document.getElementById('hotspot-advanced-form'));
        const settings = Object.fromEntries(formData);
        
        // Convert checkbox value
        settings.captive_portal = document.getElementById('captive-portal').checked;
        
        await this.saveSettingsToAPI('advanced', settings);
    }

    async saveInterfaceSettings() {
        const formData = new FormData(document.getElementById('wifi-interface-form'));
        const settings = Object.fromEntries(formData);
        
        await this.saveSettingsToAPI('interface', settings);
    }

    async savePortalSettings() {
        const formData = new FormData(document.getElementById('portal-settings-form'));
        const settings = Object.fromEntries(formData);
        
        await this.saveSettingsToAPI('portal', settings);
    }

    async saveSettingsToAPI(category, settings) {
        try {
            const response = await fetch(this.apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    action: 'save_hotspot_settings',
                    category: category,
                    settings: settings
                })
            });

            const data = await response.json();
            
            if (data.success) {
                this.showNotification(`${category.charAt(0).toUpperCase() + category.slice(1)} settings saved successfully!`, 'success');
                // Apply settings and update status
                this.applySettings(settings, category);
            } else {
                this.showNotification('Failed to save settings: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error saving settings:', error);
            this.showNotification('Error saving settings to server', 'error');
        }
    }

    async applySettings(settings, type) {
        try {
            // Apply settings to the system
            const response = await fetch(this.apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    action: 'apply_hotspot_settings',
                    type: type,
                    settings: settings
                })
            });

            const data = await response.json();
            
            if (data.success) {
                this.showNotification(`${type.charAt(0).toUpperCase() + type.slice(1)} settings applied successfully!`, 'success');
                
                // Update WiFi interfaces status
                await this.loadWiFiInterfaces();
                
                // Update general status
                await this.updateStatus();
            } else {
                this.showNotification('Failed to apply settings: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error applying settings:', error);
            this.showNotification('Error applying settings to server', 'error');
        }
    }

    validateIP(ip) {
        const ipRegex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
        return ipRegex.test(ip);
    }

    async getWiFiInterfaceStatus() {
        try {
            const response = await fetch(`${this.apiUrl}?action=wifi_interface_status`);
            const data = await response.json();
            
            if (data.success && data.interfaces) {
                return data.interfaces;
            } else {
                // Return sample data if API fails
                return [
                    {
                        name: 'wlan0',
                        ssid: 'PisoWiFi-Hotspot',
                        channel: 6,
                        mode: 'ap',
                        encryption: 'psk2',
                        signal: -45,
                        clients: 3,
                        status: 'up',
                        mac: '00:11:22:33:44:55'
                    },
                    {
                        name: 'wlan1',
                        ssid: 'PisoWiFi-Guest',
                        channel: 11,
                        mode: 'ap',
                        encryption: 'none',
                        signal: -52,
                        clients: 1,
                        status: 'up',
                        mac: '00:11:22:33:44:66'
                    }
                ];
            }
        } catch (error) {
            console.error('Error getting WiFi interface status:', error);
            return this.getSampleWiFiInterfaces();
        }
    }

    getSampleWiFiInterfaces() {
        return [
            {
                name: 'wlan0',
                ssid: 'PisoWiFi-Hotspot',
                channel: 6,
                mode: 'ap',
                encryption: 'psk2',
                signal: -45,
                clients: 3,
                status: 'up',
                mac: '00:11:22:33:44:55'
            },
            {
                name: 'wlan1',
                ssid: 'PisoWiFi-Guest',
                channel: 11,
                mode: 'ap',
                encryption: 'none',
                signal: -52,
                clients: 1,
                status: 'up',
                mac: '00:11:22:33:44:66'
            }
        ];
    }

    async updateWiFiInterfaceStatus() {
        try {
            const interfaces = await this.getWiFiInterfaceStatus();
            
            // Update the interface status in the UI
            interfaces.forEach(iface => {
                const interfaceElement = document.querySelector(`[data-interface="${iface.name}"]`);
                if (interfaceElement) {
                    const statusElement = interfaceElement.querySelector('.interface-status');
                    const clientsElement = interfaceElement.querySelector('.interface-clients');
                    const signalElement = interfaceElement.querySelector('.interface-signal');
                    
                    if (statusElement) {
                        statusElement.textContent = iface.status === 'up' ? 'Active' : 'Inactive';
                        statusElement.className = `interface-status badge ${iface.status === 'up' ? 'badge-success' : 'badge-danger'}`;
                    }
                    
                    if (clientsElement) {
                        clientsElement.textContent = `${iface.clients} clients`;
                    }
                    
                    if (signalElement) {
                        const signalClass = iface.signal > -50 ? 'text-success' : iface.signal > -70 ? 'text-warning' : 'text-danger';
                        signalElement.textContent = `${iface.signal} dBm`;
                        signalElement.className = `interface-signal ${signalClass}`;
                    }
                }
            });
            
            return interfaces;
        } catch (error) {
            console.error('Error updating WiFi interface status:', error);
            return this.getSampleWiFiInterfaces();
        }
    }

    async testHotspot() {
        const button = event.target;
        const originalText = button.textContent;
        
        button.textContent = 'Testing...';
        button.disabled = true;
        
        try {
            const response = await fetch(`${this.apiUrl}?action=test_hotspot`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                }
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.showNotification('Hotspot test successful!', 'success');
            } else {
                this.showNotification('Hotspot test failed: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error testing hotspot:', error);
            this.showNotification('Error testing hotspot', 'error');
        } finally {
            button.textContent = originalText;
            button.disabled = false;
        }
    }

    async createCaptivePortal() {
        try {
            const response = await fetch(`${this.apiUrl}?action=create_captive_portal`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    hotspot_ip: document.getElementById('hotspot-ip').value,
                    portal_title: document.getElementById('portal-title').value,
                    portal_message: document.getElementById('portal-message').value
                })
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.showNotification('Captive portal created successfully!', 'success');
            } else {
                this.showNotification('Failed to create captive portal: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error creating captive portal:', error);
            this.showNotification('Error creating captive portal', 'error');
        }
    }

    startStatusUpdates() {
        this.updateStatus();
        setInterval(() => {
            this.updateStatus();
        }, 5000); // Update every 5 seconds
    }

    async updateStatus() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_hotspot_status`);
            const data = await response.json();
            
            if (data.success) {
                this.updateStatusDisplay(data.status || this.getDefaultStatus());
            } else {
                console.error('Failed to get hotspot status:', data.error);
                this.updateStatusDisplay(this.getDefaultStatus());
            }
        } catch (error) {
            console.error('Error updating hotspot status:', error);
            this.updateStatusDisplay(this.getDefaultStatus());
        }
    }

    getDefaultStatus() {
        return {
            service: 'Unknown',
            interface: 'Unknown',
            users: 0,
            signal: 'N/A'
        };
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
async function saveHotspotSettings() {
    const manager = new HotspotManager();
    try {
        // Save basic settings
        let response = await fetch(`${manager.apiUrl}?action=save_hotspot_settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: 'basic',
                settings: Object.fromEntries(new FormData(document.getElementById('hotspot-basic-form')))
            })
        });
        let data = await response.json();
        if (!data.success) { manager.showNotification('Failed to save basic settings: ' + data.error, 'error'); return; }

        // Save advanced settings
        const advancedForm = document.getElementById('hotspot-advanced-form');
        const advancedSettings = Object.fromEntries(new FormData(advancedForm));
        advancedSettings.captive_portal = document.getElementById('captive-portal').checked;
        response = await fetch(`${manager.apiUrl}?action=save_hotspot_settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ category: 'advanced', settings: advancedSettings })
        });
        data = await response.json();
        if (!data.success) { manager.showNotification('Failed to save advanced settings: ' + data.error, 'error'); return; }

        // Save interface settings
        response = await fetch(`${manager.apiUrl}?action=save_hotspot_settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: 'interface',
                settings: Object.fromEntries(new FormData(document.getElementById('wifi-interface-form')))
            })
        });
        data = await response.json();
        if (!data.success) { manager.showNotification('Failed to save interface settings: ' + data.error, 'error'); return; }

        // Save portal settings
        response = await fetch(`${manager.apiUrl}?action=save_hotspot_settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                category: 'portal',
                settings: Object.fromEntries(new FormData(document.getElementById('portal-settings-form')))
            })
        });
        data = await response.json();
        if (data.success) {
            manager.showNotification('Hotspot settings saved successfully!', 'success');
        } else {
            manager.showNotification('Failed to save portal settings: ' + data.error, 'error');
        }
    } catch (error) {
        console.error('Error saving hotspot settings:', error);
        manager.showNotification('Error saving hotspot settings', 'error');
    }
}

async function testHotspot() {
    const manager = new HotspotManager();
    await manager.testHotspot();
}

async function createCaptivePortal() {
    const manager = new HotspotManager();
    await manager.createCaptivePortal();
}

// Initialize hotspot manager
document.addEventListener('DOMContentLoaded', () => {
    new HotspotManager();
});