// Dashboard JavaScript for PisoWiFi
class PisoWiFiDashboard {
    constructor() {
        this.init();
        this.startDataUpdates();
    }

    init() {
        this.updateSystemTime();
        this.setupEventListeners();
        this.loadDashboardData();
        this.setupMobileSidebar();
    }

    setupEventListeners() {
        // Sidebar navigation
        document.querySelectorAll('.sidebar-menu a').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                this.handleNavigation(link.getAttribute('href'));
                this.setActiveMenuItem(link);
            });
        });

        // Logout button
        document.querySelector('.btn-logout')?.addEventListener('click', () => {
            this.logout();
        });
    }

    setupMobileSidebar() {
        // Create mobile sidebar toggle button
        const toggleBtn = document.createElement('button');
        toggleBtn.className = 'sidebar-toggle';
        toggleBtn.innerHTML = '☰';
        document.body.appendChild(toggleBtn);

        // Create overlay
        const overlay = document.createElement('div');
        overlay.className = 'sidebar-overlay';
        document.body.appendChild(overlay);

        // Toggle sidebar
        toggleBtn.addEventListener('click', () => {
            document.querySelector('.sidebar').classList.toggle('active');
            overlay.classList.toggle('active');
        });

        // Close sidebar when clicking overlay
        overlay.addEventListener('click', () => {
            document.querySelector('.sidebar').classList.remove('active');
            overlay.classList.remove('active');
        });
    }

    handleNavigation(hash) {
        switch(hash) {
            case '#dashboard':
                this.showDashboard();
                break;
            case '#hotspot':
                this.showHotspot();
                break;
            case '#vouchers':
                this.showVouchers();
                break;
            case '#users':
                this.showUsers();
                break;
            case '#settings':
                this.showSettings();
                break;
            case '#logs':
                this.showLogs();
                break;
            default:
                this.showDashboard();
        }
    }

    setActiveMenuItem(activeLink) {
        document.querySelectorAll('.sidebar-menu a').forEach(link => {
            link.classList.remove('active');
        });
        activeLink.classList.add('active');
    }

    showDashboard() {
        // Dashboard is already visible
        this.loadDashboardData();
    }

    showHotspot() {
        window.location.href = 'hotspot.html';
    }

    showVouchers() {
        window.location.href = 'vouchers.html';
    }

    showUsers() {
        this.loadUsersTable();
    }

    showSettings() {
        window.location.href = 'settings.html';
    }

    showLogs() {
        window.location.href = 'logs.html';
    }

    updateSystemTime() {
        const updateTime = () => {
            const now = new Date();
            const timeString = now.toLocaleString('en-US', {
                weekday: 'short',
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
            document.getElementById('system-time').textContent = timeString;
        };
        
        updateTime();
        setInterval(updateTime, 1000);
    }

    loadDashboardData() {
        // Simulate loading dashboard data
        this.updateSystemStatus();
        this.updateNetworkInfo();
        this.updateVoucherStats();
        this.loadUsersTable();
    }

    updateSystemStatus() {
        // Simulate system status data
        const status = {
            hotspot: 'Active',
            activeUsers: Math.floor(Math.random() * 50) + 1,
            uptime: this.formatUptime(Math.floor(Math.random() * 86400) + 3600)
        };

        document.getElementById('hotspot-status').textContent = status.hotspot;
        document.getElementById('hotspot-status').className = status.hotspot === 'Active' ? 'status-active' : 'status-inactive';
        document.getElementById('active-users').textContent = status.activeUsers;
        document.getElementById('system-uptime').textContent = status.uptime;
    }

    updateNetworkInfo() {
        // Simulate network information
        const network = {
            hotspotIp: '10.0.0.1',
            gatewayIp: '192.168.1.1',
            dnsServer: '8.8.8.8',
            wifiInterface: 'wlan0'
        };

        document.getElementById('hotspot-ip').textContent = network.hotspotIp;
        document.getElementById('gateway-ip').textContent = network.gatewayIp;
        document.getElementById('dns-server').textContent = network.dnsServer;
        document.getElementById('wifi-interface').textContent = network.wifiInterface;
    }

    updateVoucherStats() {
        // Simulate voucher statistics
        const stats = {
            total: Math.floor(Math.random() * 1000) + 100,
            active: Math.floor(Math.random() * 100) + 10,
            used: Math.floor(Math.random() * 500) + 50
        };

        document.getElementById('total-vouchers').textContent = stats.total;
        document.getElementById('active-vouchers').textContent = stats.active;
        document.getElementById('used-vouchers').textContent = stats.used;
    }

    loadUsersTable() {
        // Simulate loading connected users
        const users = this.generateMockUsers();
        const tbody = document.getElementById('users-tbody');
        
        if (tbody) {
            tbody.innerHTML = '';
            users.forEach(user => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${user.ip}</td>
                    <td>${user.mac}</td>
                    <td>${user.timeConnected}</td>
                    <td><span class="status-active">Connected</span></td>
                    <td>
                        <button class="btn btn-small btn-danger" onclick="disconnectUser('${user.mac}')">Disconnect</button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }
    }

    generateMockUsers() {
        const users = [];
        const userCount = Math.floor(Math.random() * 10) + 1;
        
        for (let i = 0; i < userCount; i++) {
            users.push({
                ip: `10.0.0.${i + 10}`,
                mac: this.generateMAC(),
                timeConnected: this.formatTimeConnected(Math.floor(Math.random() * 3600))
            });
        }
        
        return users;
    }

    generateMAC() {
        const hex = '0123456789ABCDEF';
        let mac = '';
        for (let i = 0; i < 6; i++) {
            if (i > 0) mac += ':';
            mac += hex[Math.floor(Math.random() * 16)] + hex[Math.floor(Math.random() * 16)];
        }
        return mac;
    }

    formatUptime(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        return `${hours}h ${minutes}m`;
    }

    formatTimeConnected(seconds) {
        const minutes = Math.floor(seconds / 60);
        const remainingSeconds = seconds % 60;
        return `${minutes}m ${remainingSeconds}s`;
    }

    startDataUpdates() {
        // Update data every 30 seconds
        setInterval(() => {
            this.updateSystemStatus();
            this.updateVoucherStats();
            this.loadUsersTable();
        }, 30000);
    }

    logout() {
        if (confirm('Are you sure you want to logout?')) {
            // Simulate logout
            window.location.href = '../index.html';
        }
    }
}

// Global functions for button actions
function restartHotspot() {
    if (confirm('Are you sure you want to restart the hotspot? This will disconnect all users.')) {
        alert('Hotspot restart initiated...');
        // Add actual restart logic here
    }
}

function viewActiveUsers() {
    document.querySelector('a[href="#users"]').click();
}

function disconnectUser(mac) {
    if (confirm(`Are you sure you want to disconnect user with MAC: ${mac}?`)) {
        alert(`User ${mac} disconnected.`);
        // Add actual disconnect logic here
        dashboard.loadUsersTable();
    }
}

// Initialize dashboard when page loads
let dashboard;
document.addEventListener('DOMContentLoaded', () => {
    dashboard = new PisoWiFiDashboard();
});