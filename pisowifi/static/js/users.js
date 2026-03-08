// User Management JavaScript
class UserManager {
    constructor() {
        this.users = [];
        this.sessions = [];
        this.filteredUsers = [];
        this.bandwidthData = [];
        this.apiUrl = '/pisowifi/cgi-bin/api-real.cgi';
        this.init();
    }

    async init() {
        await this.loadUsers();
        await this.loadSessions();
        this.setupEventListeners();
        this.updateStatistics();
        this.renderUsers();
        this.renderSessions();
        this.startBandwidthMonitoring();
    }

    async loadUsers() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_connected_users`);
            const data = await response.json();
            
            if (data.success) {
                this.users = data.users || [];
                this.filteredUsers = [...this.users];
            } else {
                console.error('Failed to load users:', data.error);
                this.loadSampleUsers();
            }
        } catch (error) {
            console.error('Error loading users:', error);
            this.loadSampleUsers();
        }
    }

    async loadSessions() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_active_sessions`);
            const data = await response.json();
            
            if (data.success) {
                this.sessions = data.sessions || [];
            } else {
                console.error('Failed to load sessions:', data.error);
                this.loadSampleSessions();
            }
        } catch (error) {
            console.error('Error loading sessions:', error);
            this.loadSampleSessions();
        }
    }

    loadSampleUsers() {
        // Sample user data
        this.users = [
            {
                id: 1,
                ip: '192.168.1.100',
                mac: '00:11:22:33:44:55',
                deviceName: 'John\'s iPhone',
                deviceType: 'mobile',
                status: 'online',
                connectedSince: new Date('2024-01-20T14:30:00').toISOString(),
                sessionTime: 45,
                dataUsed: 125.5,
                voucherCode: 'PISO2024001',
                maxData: 500,
                sessionLimit: 240
            },
            {
                id: 2,
                ip: '192.168.1.101',
                mac: 'AA:BB:CC:DD:EE:FF',
                deviceName: 'Sarah\'s Laptop',
                deviceType: 'laptop',
                status: 'online',
                connectedSince: new Date('2024-01-20T13:15:00').toISOString(),
                sessionTime: 120,
                dataUsed: 450.2,
                voucherCode: 'PISO2024002',
                maxData: 1000,
                sessionLimit: 480
            },
            {
                id: 3,
                ip: '192.168.1.102',
                mac: '11:22:33:44:55:66',
                deviceName: 'Tablet-ABC123',
                deviceType: 'tablet',
                status: 'offline',
                connectedSince: new Date('2024-01-20T12:00:00').toISOString(),
                sessionTime: 180,
                dataUsed: 275.8,
                voucherCode: 'PISO2024003',
                maxData: 750,
                sessionLimit: 360
            },
            {
                id: 4,
                ip: '192.168.1.103',
                mac: '77:88:99:AA:BB:CC',
                deviceName: 'Mike\'s Phone',
                deviceType: 'mobile',
                status: 'blocked',
                connectedSince: new Date('2024-01-20T11:30:00').toISOString(),
                sessionTime: 0,
                dataUsed: 0,
                voucherCode: null,
                maxData: 0,
                sessionLimit: 0
            },
            {
                id: 5,
                ip: '192.168.1.104',
                mac: 'DD:EE:FF:00:11:22',
                deviceName: 'Desktop-PC',
                deviceType: 'laptop',
                status: 'online',
                connectedSince: new Date('2024-01-20T15:45:00').toISOString(),
                sessionTime: 15,
                dataUsed: 85.3,
                voucherCode: 'PISO2024004',
                maxData: 2000,
                sessionLimit: 720
            }
        ];

        this.loadSampleSessions();
        this.filteredUsers = [...this.users];
    }

    loadSampleSessions() {
        // Sample session data
        this.sessions = [
            {
                id: 1,
                userIp: '192.168.1.100',
                startTime: new Date('2024-01-20T14:30:00').toISOString(),
                endTime: new Date('2024-01-20T15:15:00').toISOString(),
                duration: 45,
                dataUsed: 125.5,
                voucherCode: 'PISO2024001',
                status: 'completed'
            },
            {
                id: 2,
                userIp: '192.168.1.101',
                startTime: new Date('2024-01-20T13:15:00').toISOString(),
                endTime: null,
                duration: 120,
                dataUsed: 450.2,
                voucherCode: 'PISO2024002',
                status: 'active'
            },
            {
                id: 3,
                userIp: '192.168.1.102',
                startTime: new Date('2024-01-20T12:00:00').toISOString(),
                endTime: new Date('2024-01-20T15:00:00').toISOString(),
                duration: 180,
                dataUsed: 275.8,
                voucherCode: 'PISO2024003',
                status: 'completed'
            }
        ];
    }

    setupEventListeners() {
        // Filter listeners
        document.getElementById('status-filter')?.addEventListener('change', () => this.filterUsers());
        document.getElementById('device-filter')?.addEventListener('change', () => this.filterUsers());
        document.getElementById('search-users')?.addEventListener('input', () => this.searchUsers());

        // Modal listeners
        document.getElementById('user-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveUser();
        });
    }

    updateStatistics() {
        const total = this.users.length;
        const online = this.users.filter(u => u.status === 'online').length;
        const activeDevices = this.users.filter(u => u.status === 'online').length;
        const avgSession = this.calculateAverageSession();

        document.getElementById('total-users').textContent = total;
        document.getElementById('online-users').textContent = online;
        document.getElementById('active-devices').textContent = activeDevices;
        document.getElementById('avg-session').textContent = `${avgSession}m`;
    }

    calculateAverageSession() {
        const sessions = this.sessions.filter(s => s.status === 'completed');
        if (sessions.length === 0) return 0;
        
        const totalDuration = sessions.reduce((sum, session) => sum + session.duration, 0);
        return Math.round(totalDuration / sessions.length);
    }

    renderUsers() {
        const tbody = document.getElementById('users-tbody');
        if (!tbody) return;

        tbody.innerHTML = '';

        this.filteredUsers.forEach(user => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${user.ip}</td>
                <td>${user.mac}</td>
                <td>${user.deviceName}</td>
                <td><span class="device-type device-${user.deviceType}">${user.deviceType}</span></td>
                <td><span class="status-badge status-${user.status}">${user.status.toUpperCase()}</span></td>
                <td>${this.formatTime(user.connectedSince)}</td>
                <td>${user.sessionTime} min</td>
                <td>${user.dataUsed.toFixed(1)} MB</td>
                <td>${user.voucherCode || '-'}</td>
                <td>
                    <div class="action-buttons">
                        <button class="btn-small btn-view" onclick="viewUser(${user.id})">View</button>
                        <button class="btn-small btn-${user.status === 'blocked' ? 'unblock' : 'block'}" 
                                onclick="toggleBlockUser(${user.id})">${user.status === 'blocked' ? 'Unblock' : 'Block'}</button>
                        <button class="btn-small btn-disconnect" 
                                onclick="disconnectUser(${user.id})" 
                                ${user.status !== 'online' ? 'disabled' : ''}>Disconnect</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    }

    renderSessions() {
        const tbody = document.getElementById('sessions-tbody');
        if (!tbody) return;

        tbody.innerHTML = '';

        this.sessions.forEach(session => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${session.userIp}</td>
                <td>${this.formatTime(session.startTime)}</td>
                <td>${session.endTime ? this.formatTime(session.endTime) : '-'}</td>
                <td>${session.duration} min</td>
                <td>${session.dataUsed.toFixed(1)} MB</td>
                <td>${session.voucherCode || '-'}</td>
                <td><span class="session-status status-${session.status}">${session.status.toUpperCase()}</span></td>
            `;
            tbody.appendChild(row);
        });
    }

    filterUsers() {
        const statusFilter = document.getElementById('status-filter').value;
        const deviceFilter = document.getElementById('device-filter').value;
        const searchTerm = document.getElementById('search-users').value.toLowerCase();

        this.filteredUsers = this.users.filter(user => {
            const matchesStatus = !statusFilter || user.status === statusFilter;
            const matchesDevice = !deviceFilter || user.deviceType === deviceFilter;
            const matchesSearch = !searchTerm || 
                user.ip.includes(searchTerm) ||
                user.mac.toLowerCase().includes(searchTerm) ||
                user.deviceName.toLowerCase().includes(searchTerm) ||
                (user.voucherCode && user.voucherCode.toLowerCase().includes(searchTerm));

            return matchesStatus && matchesDevice && matchesSearch;
        });

        this.renderUsers();
    }

    searchUsers() {
        this.filterUsers();
    }

    formatTime(date) {
        return new Date(date).toLocaleString();
    }

    showAddUserModal() {
        document.getElementById('user-modal-title').textContent = 'Add User';
        document.getElementById('user-id').value = '';
        document.getElementById('user-form').reset();
        document.getElementById('user-modal').style.display = 'block';
    }

    closeUserModal() {
        document.getElementById('user-modal').style.display = 'none';
    }

    saveUser() {
        const id = document.getElementById('user-id').value;
        const ip = document.getElementById('user-ip').value;
        const mac = document.getElementById('user-mac').value;
        const deviceName = document.getElementById('device-name').value;
        const deviceType = document.getElementById('device-type').value;
        const voucherCode = document.getElementById('user-voucher').value;
        const status = document.getElementById('user-status').value;
        const maxData = parseFloat(document.getElementById('max-data').value) || 0;
        const sessionLimit = parseInt(document.getElementById('session-limit').value) || 0;

        if (!ip || !mac || !deviceName) {
            this.showNotification('Please fill in all required fields!', 'error');
            return;
        }

        if (id) {
            // Edit existing user
            const user = this.users.find(u => u.id === parseInt(id));
            if (user) {
                user.ip = ip;
                user.mac = mac;
                user.deviceName = deviceName;
                user.deviceType = deviceType;
                user.voucherCode = voucherCode || null;
                user.status = status;
                user.maxData = maxData;
                user.sessionLimit = sessionLimit;
            }
        } else {
            // Add new user
            const newUser = {
                id: this.users.length + 1,
                ip: ip,
                mac: mac,
                deviceName: deviceName,
                deviceType: deviceType,
                status: status,
                connectedSince: new Date(),
                sessionTime: 0,
                dataUsed: 0,
                voucherCode: voucherCode || null,
                maxData: maxData,
                sessionLimit: sessionLimit
            };
            this.users.push(newUser);
        }

        this.filteredUsers = [...this.users];
        this.updateStatistics();
        this.renderUsers();
        this.closeUserModal();
        this.showNotification('User saved successfully!', 'success');
    }

    viewUser(id) {
        const user = this.users.find(u => u.id === id);
        if (user) {
            alert(`User Details:\n\n` +
                  `IP Address: ${user.ip}\n` +
                  `MAC Address: ${user.mac}\n` +
                  `Device Name: ${user.deviceName}\n` +
                  `Device Type: ${user.deviceType}\n` +
                  `Status: ${user.status.toUpperCase()}\n` +
                  `Connected Since: ${this.formatTime(user.connectedSince)}\n` +
                  `Session Time: ${user.sessionTime} minutes\n` +
                  `Data Used: ${user.dataUsed.toFixed(1)} MB\n` +
                  `Voucher Code: ${user.voucherCode || 'None'}\n` +
                  `Max Data: ${user.maxData > 0 ? user.maxData + ' MB' : 'Unlimited'}\n` +
                  `Session Limit: ${user.sessionLimit > 0 ? user.sessionLimit + ' min' : 'Unlimited'}`);
        }
    }

    toggleBlockUser(id) {
        const user = this.users.find(u => u.id === id);
        if (user) {
            if (user.status === 'blocked') {
                this.unblockUser(id);
            } else {
                this.blockUser(id);
            }
        }
    }

    async saveUser(userData) {
        try {
            const response = await fetch(`${this.apiUrl}?action=save_user`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(userData)
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.showNotification('User saved successfully!', 'success');
                await this.loadUsers(); // Reload users
            } else {
                this.showNotification('Failed to save user: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error saving user:', error);
            this.showNotification('Error saving user', 'error');
        }
    }

    async deleteUser(userId) {
        try {
            const response = await fetch(`${this.apiUrl}?action=delete_user`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ userId: userId })
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.showNotification('User deleted successfully!', 'success');
                await this.loadUsers(); // Reload users
            } else {
                this.showNotification('Failed to delete user: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error deleting user:', error);
            this.showNotification('Error deleting user', 'error');
        }
    }

    async blockUser(userId) {
        try {
            const response = await fetch(`${this.apiUrl}?action=block_user`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ userId: userId, action: 'block' })
            });
            
            const data = await response.json();
            
            if (data.success) {
                const user = this.users.find(u => u.id === userId);
                if (user) {
                    user.status = 'blocked';
                    this.renderUsers();
                    this.showNotification(`User ${user.deviceName} blocked successfully`, 'success');
                }
            } else {
                this.showNotification('Failed to block user: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error blocking user:', error);
            this.showNotification('Error blocking user', 'error');
        }
    }

    async unblockUser(userId) {
        try {
            const response = await fetch(`${this.apiUrl}?action=block_user`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ userId: userId, action: 'unblock' })
            });
            
            const data = await response.json();
            
            if (data.success) {
                const user = this.users.find(u => u.id === userId);
                if (user) {
                    user.status = 'online';
                    this.renderUsers();
                    this.showNotification(`User ${user.deviceName} unblocked successfully`, 'success');
                }
            } else {
                this.showNotification('Failed to unblock user: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error unblocking user:', error);
            this.showNotification('Error unblocking user', 'error');
        }
    }

    disconnectUser(id) {
        const user = this.users.find(u => u.id === id);
        if (user && user.status === 'online') {
            if (confirm(`Are you sure you want to disconnect ${user.deviceName}?`)) {
                user.status = 'offline';
                user.sessionTime = Math.floor((new Date() - user.connectedSince) / 60000);
                
                // Add to sessions
                this.sessions.push({
                    id: this.sessions.length + 1,
                    userIp: user.ip,
                    startTime: user.connectedSince,
                    endTime: new Date(),
                    duration: user.sessionTime,
                    dataUsed: user.dataUsed,
                    voucherCode: user.voucherCode,
                    status: 'completed'
                });

                this.renderUsers();
                this.renderSessions();
                this.updateStatistics();
                this.showNotification('User disconnected successfully!', 'success');
            }
        }
    }

    exportUsers() {
        const csvContent = this.generateCSV();
        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `users_${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        this.showNotification('Users exported successfully!', 'success');
    }

    generateCSV() {
        const headers = ['IP Address', 'MAC Address', 'Device Name', 'Device Type', 'Status', 'Connected Since', 'Session Time (min)', 'Data Used (MB)', 'Voucher Code'];
        const rows = this.users.map(user => [
            user.ip,
            user.mac,
            user.deviceName,
            user.deviceType,
            user.status,
            this.formatTime(user.connectedSince),
            user.sessionTime,
            user.dataUsed.toFixed(1),
            user.voucherCode || ''
        ]);

        return [headers, ...rows].map(row => row.join(',')).join('\n');
    }

    clearInactiveUsers() {
        if (confirm('Are you sure you want to clear all inactive users?')) {
            this.users = this.users.filter(user => user.status === 'online');
            this.filteredUsers = [...this.users];
            this.updateStatistics();
            this.renderUsers();
            this.showNotification('Inactive users cleared successfully!', 'success');
        }
    }

    startBandwidthMonitoring() {
        // Simulate bandwidth data
        setInterval(() => {
            this.updateBandwidthData();
        }, 2000);
    }

    updateBandwidthData() {
        const now = new Date();
        const download = Math.random() * 10; // Mbps
        const upload = Math.random() * 5; // Mbps

        this.bandwidthData.push({
            time: now,
            download: download,
            upload: upload
        });

        // Keep only last 60 data points
        if (this.bandwidthData.length > 60) {
            this.bandwidthData.shift();
        }

        this.updateBandwidthStats();
    }

    updateBandwidthStats() {
        const totalDownload = this.users.reduce((sum, user) => sum + user.dataUsed, 0);
        const totalUpload = totalDownload * 0.3; // Simulate upload as 30% of download
        
        const peakDownload = Math.max(...this.bandwidthData.map(d => d.download));
        const peakUpload = Math.max(...this.bandwidthData.map(d => d.upload));

        document.getElementById('total-download').textContent = `${totalDownload.toFixed(1)} MB`;
        document.getElementById('total-upload').textContent = `${totalUpload.toFixed(1)} MB`;
        document.getElementById('peak-download').textContent = `${peakDownload.toFixed(1)} Mbps`;
        document.getElementById('peak-upload').textContent = `${peakUpload.toFixed(1)} Mbps`;
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
let userManager;

function showAddUserModal() {
    userManager.showAddUserModal();
}

function closeUserModal() {
    userManager.closeUserModal();
}

function saveUser() {
    userManager.saveUser();
}

function viewUser(id) {
    userManager.viewUser(id);
}

function toggleBlockUser(id) {
    userManager.toggleBlockUser(id);
}

function disconnectUser(id) {
    userManager.disconnectUser(id);
}

function filterUsers() {
    userManager.filterUsers();
}

function searchUsers() {
    userManager.searchUsers();
}

function exportUsers() {
    userManager.exportUsers();
}

function clearInactiveUsers() {
    userManager.clearInactiveUsers();
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    userManager = new UserManager();
});

// Close modal when clicking outside
window.onclick = function(event) {
    const userModal = document.getElementById('user-modal');
    if (event.target === userModal) {
        userManager.closeUserModal();
    }
};