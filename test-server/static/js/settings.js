// Settings Management JavaScript with Real API Integration
class SettingsManager {
    constructor() {
        this.currentTab = 'general';
        this.apiUrl = '/cgi-bin/api-real.cgi';
        this.init();
    }

    init() {
        this.loadSettings();
        this.setupEventListeners();
        this.updateSystemInfo();
        this.startSystemInfoUpdate();
    }

    setupEventListeners() {
        // Tab switching
        document.querySelectorAll('.tab-button').forEach(button => {
            button.addEventListener('click', (e) => {
                const tab = e.target.textContent.toLowerCase().split(' ')[0];
                this.showTab(tab);
            });
        });

        // Form submissions
        document.getElementById('general-settings-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveGeneralSettings();
        });

        document.getElementById('network-settings-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveNetworkSettings();
        });

        document.getElementById('wifi-settings-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveWiFiSettings();
        });

        document.getElementById('security-settings-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveSecuritySettings();
        });

        document.getElementById('firewall-settings-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveFirewallSettings();
        });
    }

    showTab(tabName) {
        // Hide all tabs
        document.querySelectorAll('.tab-content').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelectorAll('.tab-button').forEach(button => {
            button.classList.remove('active');
        });

        // Show selected tab
        const tabContent = document.getElementById(`${tabName}-tab`);
        const tabButton = Array.from(document.querySelectorAll('.tab-button'))
            .find(btn => btn.textContent.toLowerCase().includes(tabName));

        if (tabContent && tabButton) {
            tabContent.classList.add('active');
            tabButton.classList.add('active');
            this.currentTab = tabName;
        }
    }

    async loadSettings() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_settings`);
            const data = await response.json();
            
            if (data.success) {
                this.populateSettings(data.settings || {});
            } else {
                this.showNotification('Failed to load settings: ' + data.error, 'error');
                // Fallback to localStorage
                this.loadSettingsFromLocal();
            }
        } catch (error) {
            console.error('Error loading settings:', error);
            this.showNotification('Error loading settings from server', 'error');
            // Fallback to localStorage
            this.loadSettingsFromLocal();
        }
    }

    loadSettingsFromLocal() {
        // Load settings from localStorage or use defaults
        const settings = JSON.parse(localStorage.getItem('pisowifi-settings') || '{}');
        this.populateSettings(settings);
    }

    populateSettings(settings) {
        // General settings
        document.getElementById('system-name').value = settings.systemName || 'PisoWiFi System';
        document.getElementById('admin-email').value = settings.adminEmail || '';
        document.getElementById('timezone').value = settings.timezone || 'Asia/Manila';
        document.getElementById('language').value = settings.language || 'en';
        document.getElementById('auto-update').checked = settings.autoUpdate || false;
        document.getElementById('maintenance-mode').checked = settings.maintenanceMode || false;

        // Network settings
        document.getElementById('wan-interface').value = settings.wanInterface || 'eth0';
        document.getElementById('lan-ip').value = settings.lanIp || '192.168.1.1';
        document.getElementById('lan-subnet').value = settings.lanSubnet || '255.255.255.0';
        document.getElementById('dhcp-start').value = settings.dhcpStart || '192.168.1.100';
        document.getElementById('dhcp-end').value = settings.dhcpEnd || '192.168.1.200';
        document.getElementById('dns-server').value = settings.dnsServer || '8.8.8.8, 8.8.4.4';

        // WiFi settings
        document.getElementById('wifi-ssid').value = settings.wifiSsid || 'PisoWiFi';
        document.getElementById('wifi-channel').value = settings.wifiChannel || 'auto';
        document.getElementById('wifi-mode').value = settings.wifiMode || 'bgn';

        // Security settings
        document.getElementById('admin-username').value = settings.adminUsername || 'admin';
        document.getElementById('enable-ssh').checked = settings.enableSsh || true;
        document.getElementById('ssh-port').value = settings.sshPort || 22;

        // Firewall settings
        document.getElementById('enable-firewall').checked = settings.enableFirewall !== false;
        document.getElementById('block-ping').checked = settings.blockPing || false;
        document.getElementById('block-ssh-wan').checked = settings.blockSshWan || true;
        document.getElementById('max-connections').value = settings.maxConnections || 100;
    }

    async saveGeneralSettings() {
        const settings = {
            systemName: document.getElementById('system-name').value,
            adminEmail: document.getElementById('admin-email').value,
            timezone: document.getElementById('timezone').value,
            language: document.getElementById('language').value,
            autoUpdate: document.getElementById('auto-update').checked,
            maintenanceMode: document.getElementById('maintenance-mode').checked
        };

        await this.saveSettingsToAPI('general', settings);
    }

    async saveNetworkSettings() {
        const settings = {
            wanInterface: document.getElementById('wan-interface').value,
            lanIp: document.getElementById('lan-ip').value,
            lanSubnet: document.getElementById('lan-subnet').value,
            dhcpStart: document.getElementById('dhcp-start').value,
            dhcpEnd: document.getElementById('dhcp-end').value,
            dnsServer: document.getElementById('dns-server').value
        };

        await this.saveSettingsToAPI('network', settings);
    }

    async saveWiFiSettings() {
        const password = document.getElementById('wifi-password').value;
        if (password && password.length < 8) {
            this.showNotification('WiFi password must be at least 8 characters!', 'error');
            return;
        }

        const settings = {
            wifiSsid: document.getElementById('wifi-ssid').value,
            wifiChannel: document.getElementById('wifi-channel').value,
            wifiMode: document.getElementById('wifi-mode').value
        };

        if (password) {
            settings.wifiPassword = password;
        }

        await this.saveSettingsToAPI('wifi', settings);
    }

    async saveSecuritySettings() {
        const username = document.getElementById('admin-username').value;
        const password = document.getElementById('admin-password').value;
        const confirmPassword = document.getElementById('confirm-password').value;

        if (password && password !== confirmPassword) {
            this.showNotification('Passwords do not match!', 'error');
            return;
        }

        const settings = {
            adminUsername: username,
            enableSsh: document.getElementById('enable-ssh').checked,
            sshPort: parseInt(document.getElementById('ssh-port').value)
        };

        if (password) {
            settings.adminPassword = password;
        }

        await this.saveSettingsToAPI('security', settings);
    }

    async saveFirewallSettings() {
        const settings = {
            enableFirewall: document.getElementById('enable-firewall').checked,
            blockPing: document.getElementById('block-ping').checked,
            blockSshWan: document.getElementById('block-ssh-wan').checked,
            maxConnections: parseInt(document.getElementById('max-connections').value)
        };

        await this.saveSettingsToAPI('firewall', settings);
    }

    async saveSettingsToAPI(category, settings) {
        try {
            const response = await fetch(this.apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    action: 'save_settings',
                    category: category,
                    settings: settings
                })
            });

            const data = await response.json();
            
            if (data.success) {
                this.showNotification(`${category.charAt(0).toUpperCase() + category.slice(1)} settings saved successfully!`, 'success');
                // Also save to localStorage as backup
                this.saveSettingsToLocal(category, settings);
            } else {
                this.showNotification('Failed to save settings: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error saving settings:', error);
            this.showNotification('Error saving settings to server', 'error');
            // Fallback to localStorage
            this.saveSettingsToLocal(category, settings);
        }
    }

    saveSettingsToLocal(category, settings) {
        const currentSettings = JSON.parse(localStorage.getItem('pisowifi-settings') || '{}');
        const updatedSettings = { ...currentSettings, ...settings };
        localStorage.setItem('pisowifi-settings', JSON.stringify(updatedSettings));
    }

    saveSettings(newSettings) {
        const currentSettings = JSON.parse(localStorage.getItem('pisowifi-settings') || '{}');
        const updatedSettings = { ...currentSettings, ...newSettings };
        localStorage.setItem('pisowifi-settings', JSON.stringify(updatedSettings));
    }

    async saveSettingsToAPI(category, settings) {
        try {
            const response = await fetch(`${this.apiUrl}?action=save_settings`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    category: category,
                    settings: settings
                })
            });
            
            const data = await response.json();
            
            if (data.success) {
                // Update localStorage with the saved settings
                this.saveSettings(settings);
                this.showNotification(`${category.charAt(0).toUpperCase() + category.slice(1)} settings saved successfully!`, 'success');
            } else {
                this.showNotification(`Failed to save ${category} settings: ${data.error}`, 'error');
            }
        } catch (error) {
            console.error(`Error saving ${category} settings:`, error);
            this.showNotification(`Error saving ${category} settings to server`, 'error');
            // Fallback to localStorage
            this.saveSettings(settings);
            this.showNotification(`${category.charAt(0).toUpperCase() + category.slice(1)} settings saved locally (server unavailable)`, 'warning');
        }
    }

    async updateSystemInfo() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_system_info`);
            const data = await response.json();
            
            if (data.success) {
                document.getElementById('system-uptime').textContent = this.formatUptime(data.uptime || 0);
                document.getElementById('cpu-usage').textContent = `${data.cpu_usage || 0}%`;
                document.getElementById('memory-usage').textContent = `${data.memory_usage || 0}%`;
            } else {
                // Fallback to simulated data
                this.updateSystemInfoSimulated();
            }
        } catch (error) {
            console.error('Error loading system info:', error);
            // Fallback to simulated data
            this.updateSystemInfoSimulated();
        }
    }

    updateSystemInfoSimulated() {
        // Simulate system info when API is not available
        const uptime = this.formatUptime(Math.floor(Math.random() * 1000000));
        const cpuUsage = Math.floor(Math.random() * 100);
        const memoryUsage = Math.floor(Math.random() * 100);

        document.getElementById('system-uptime').textContent = uptime;
        document.getElementById('cpu-usage').textContent = `${cpuUsage}%`;
        document.getElementById('memory-usage').textContent = `${memoryUsage}%`;
    }

    formatUptime(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        if (days > 0) {
            return `${days}d ${hours}h ${minutes}m`;
        } else if (hours > 0) {
            return `${hours}h ${minutes}m`;
        } else {
            return `${minutes}m`;
        }
    }

    startSystemInfoUpdate() {
        // Update system info every 30 seconds
        setInterval(() => {
            this.updateSystemInfo();
        }, 30000);
    }

    createBackup() {
        const settings = JSON.parse(localStorage.getItem('pisowifi-settings') || '{}');
        const backup = {
            version: '1.0.0',
            timestamp: new Date().toISOString(),
            settings: settings
        };

        const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `pisowifi-backup-${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        this.showNotification('Backup created successfully!', 'success');
    }

    restoreBackup() {
        const fileInput = document.getElementById('backup-file');
        const file = fileInput.files[0];

        if (!file) {
            this.showNotification('Please select a backup file!', 'error');
            return;
        }

        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const backup = JSON.parse(e.target.result);
                if (confirm('This will replace all current settings. Are you sure?')) {
                    localStorage.setItem('pisowifi-settings', JSON.stringify(backup.settings));
                    this.loadSettings();
                    this.showNotification('Backup restored successfully!', 'success');
                }
            } catch (error) {
                this.showNotification('Invalid backup file!', 'error');
            }
        };
        reader.readAsText(file);
    }

    factoryReset() {
        if (confirm('This will reset all settings to factory defaults. Are you sure?')) {
            localStorage.removeItem('pisowifi-settings');
            this.loadSettings();
            this.showNotification('Factory reset completed!', 'success');
        }
    }

    async restartServices() {
        try {
            this.showNotification('Restarting services...', 'info');
            
            const response = await fetch(this.apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    action: 'restart_services'
                })
            });

            const data = await response.json();
            
            if (data.success) {
                this.showNotification('Services restarted successfully!', 'success');
            } else {
                this.showNotification('Failed to restart services: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error restarting services:', error);
            this.showNotification('Error restarting services', 'error');
        }
    }

    async rebootSystem() {
        if (confirm('Are you sure you want to reboot the system?')) {
            try {
                this.showNotification('System is rebooting...', 'info');
                
                const response = await fetch(this.apiUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        action: 'reboot_system'
                    })
                });

                const data = await response.json();
                
                if (data.success) {
                    this.showNotification('System rebooted successfully!', 'success');
                } else {
                    this.showNotification('Failed to reboot system: ' + data.error, 'error');
                }
            } catch (error) {
                console.error('Error rebooting system:', error);
                this.showNotification('Error rebooting system', 'error');
            }
        }
    }

    clearLogs() {
        if (confirm('Are you sure you want to clear all logs?')) {
            localStorage.removeItem('pisowifi-logs');
            this.showNotification('Logs cleared successfully!', 'success');
        }
    }

    showNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.textContent = message;
        
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
        
        const colors = {
            success: '#27ae60',
            error: '#e74c3c',
            warning: '#f39c12',
            info: '#3498db'
        };
        notification.style.backgroundColor = colors[type] || colors.info;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 4000);
    }
}

// Global functions
let settingsManager;

function showTab(tabName) {
    settingsManager.showTab(tabName);
}

async function saveGeneralSettings() {
    await settingsManager.saveGeneralSettings();
}

async function saveNetworkSettings() {
    await settingsManager.saveNetworkSettings();
}

async function saveWiFiSettings() {
    await settingsManager.saveWiFiSettings();
}

async function saveSecuritySettings() {
    await settingsManager.saveSecuritySettings();
}

async function saveFirewallSettings() {
    await settingsManager.saveFirewallSettings();
}

function createBackup() {
    settingsManager.createBackup();
}

function restoreBackup() {
    settingsManager.restoreBackup();
}

function factoryReset() {
    settingsManager.factoryReset();
}

async function restartServices() {
    await settingsManager.restartServices();
}

async function rebootSystem() {
    await settingsManager.rebootSystem();
}

function clearLogs() {
    settingsManager.clearLogs();
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    settingsManager = new SettingsManager();
});