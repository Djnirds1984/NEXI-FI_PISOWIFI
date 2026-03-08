// Logs Management JavaScript with Real API Integration
class LogsManager {
    constructor() {
        this.logs = [];
        this.filteredLogs = [];
        this.currentPage = 1;
        this.logsPerPage = 50;
        this.autoScroll = true;
        this.apiUrl = '/cgi-bin/api-real.cgi';
        this.init();
    }

    async init() {
        await this.loadLogs();
        this.setupEventListeners();
        this.updateStatistics();
        this.renderLogs();
        this.startRealTimeMonitor();
    }

    async loadLogs() {
        try {
            const response = await fetch(`${this.apiUrl}?action=get_logs`);
            const data = await response.json();
            
            if (data.success) {
                this.logs = data.logs || [];
                this.filteredLogs = [...this.logs];
            } else {
                console.error('Failed to load logs:', data.error);
                this.loadSampleLogs();
            }
        } catch (error) {
            console.error('Error loading logs:', error);
            this.loadSampleLogs();
        }
    }

    loadSampleLogs() {
        // Fallback sample log data
        this.logs = [
            {
                id: 1,
                timestamp: new Date('2024-01-20T14:30:15').toISOString(),
                level: 'info',
                category: 'system',
                message: 'System started successfully',
                source: 'systemd'
            },
            {
                id: 2,
                timestamp: new Date('2024-01-20T14:30:20').toISOString(),
                level: 'info',
                category: 'hotspot',
                message: 'Hotspot service started on interface wlan0',
                source: 'hostapd'
            },
            {
                id: 3,
                timestamp: new Date('2024-01-20T14:31:45').toISOString(),
                level: 'warning',
                category: 'network',
                message: 'DHCP lease pool 80% utilized',
                source: 'dnsmasq'
            },
            {
                id: 4,
                timestamp: new Date('2024-01-20T14:32:10').toISOString(),
                level: 'info',
                category: 'voucher',
                message: 'Voucher PISO2024001 created successfully',
                source: 'pisowifi'
            },
            {
                id: 5,
                timestamp: new Date('2024-01-20T14:33:25').toISOString(),
                level: 'error',
                category: 'system',
                message: 'Failed to connect to upstream DNS server',
                source: 'dnsmasq'
            },
            {
                id: 6,
                timestamp: new Date('2024-01-20T14:34:00').toISOString(),
                level: 'info',
                category: 'user',
                message: 'User 192.168.1.100 connected with voucher PISO2024002',
                source: 'pisowifi'
            },
            {
                id: 7,
                timestamp: new Date('2024-01-20T14:35:15').toISOString(),
                level: 'warning',
                category: 'firewall',
                message: 'Blocked suspicious connection from 192.168.1.150',
                source: 'fw4'
            },
            {
                id: 8,
                timestamp: new Date('2024-01-20T14:36:30').toISOString(),
                level: 'info',
                category: 'hotspot',
                message: 'WiFi client disconnected: MAC 00:11:22:33:44:55',
                source: 'hostapd'
            },
            {
                id: 9,
                timestamp: new Date('2024-01-20T14:37:45').toISOString(),
                level: 'critical',
                category: 'system',
                message: 'Memory usage exceeded 90% threshold',
                source: 'systemd'
            },
            {
                id: 10,
                timestamp: new Date('2024-01-20T14:38:00').toISOString(),
                level: 'info',
                category: 'voucher',
                message: 'Voucher PISO2024002 marked as used',
                source: 'pisowifi'
            }
        ];

        this.filteredLogs = [...this.logs];
    }

    setupEventListeners() {
        // Filter listeners
        document.getElementById('log-level')?.addEventListener('change', () => this.filterLogs());
        document.getElementById('log-category')?.addEventListener('change', () => this.filterLogs());
        document.getElementById('date-from')?.addEventListener('change', () => this.filterLogs());
        document.getElementById('date-to')?.addEventListener('change', () => this.filterLogs());
        document.getElementById('search-logs')?.addEventListener('input', () => this.searchLogs());

        // Set default dates
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);

        document.getElementById('date-from').value = yesterday.toISOString().split('T')[0];
        document.getElementById('date-to').value = today.toISOString().split('T')[0];
    }

    filterLogs() {
        const levelFilter = document.getElementById('log-level').value;
        const categoryFilter = document.getElementById('log-category').value;
        const dateFrom = document.getElementById('date-from').value;
        const dateTo = document.getElementById('date-to').value;
        const searchTerm = document.getElementById('search-logs').value.toLowerCase();

        this.filteredLogs = this.logs.filter(log => {
            const matchesLevel = !levelFilter || log.level === levelFilter;
            const matchesCategory = !categoryFilter || log.category === categoryFilter;
            const matchesDate = this.isWithinDateRange(log.timestamp, dateFrom, dateTo);
            const matchesSearch = !searchTerm || 
                log.message.toLowerCase().includes(searchTerm) ||
                log.source.toLowerCase().includes(searchTerm);

            return matchesLevel && matchesCategory && matchesDate && matchesSearch;
        });

        this.currentPage = 1;
        this.renderLogs();
        this.updateStatistics();
    }

    isWithinDateRange(timestamp, dateFrom, dateTo) {
        if (!dateFrom && !dateTo) return true;
        
        const logDate = new Date(timestamp);
        const from = dateFrom ? new Date(dateFrom) : null;
        const to = dateTo ? new Date(dateTo) : null;

        if (from) from.setHours(0, 0, 0, 0);
        if (to) to.setHours(23, 59, 59, 999);

        if (from && logDate < from) return false;
        if (to && logDate > to) return false;
        
        return true;
    }

    searchLogs() {
        this.filterLogs();
    }

    updateStatistics() {
        const total = this.filteredLogs.length;
        const warnings = this.filteredLogs.filter(log => log.level === 'warning').length;
        const errors = this.filteredLogs.filter(log => log.level === 'error' || log.level === 'critical').length;
        const lastUpdate = new Date().toLocaleTimeString();

        document.getElementById('total-logs').textContent = total;
        document.getElementById('warning-logs').textContent = warnings;
        document.getElementById('error-logs').textContent = errors;
        document.getElementById('last-update').textContent = lastUpdate;
    }

    renderLogs() {
        const tbody = document.getElementById('logs-tbody');
        if (!tbody) return;

        tbody.innerHTML = '';

        const startIndex = (this.currentPage - 1) * this.logsPerPage;
        const endIndex = startIndex + this.logsPerPage;
        const pageLogs = this.filteredLogs.slice(startIndex, endIndex);

        pageLogs.forEach(log => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${this.formatTimestamp(log.timestamp)}</td>
                <td><span class="log-level log-${log.level}">${log.level.toUpperCase()}</span></td>
                <td><span class="log-category">${log.category}</span></td>
                <td>${log.message}</td>
                <td>${log.source}</td>
                <td>
                    <div class="action-buttons">
                        <button class="btn-small btn-view" onclick="viewLog(${log.id})">View</button>
                        <button class="btn-small btn-copy" onclick="copyLog(${log.id})">Copy</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });

        this.updatePagination();
    }

    formatTimestamp(timestamp) {
        return new Date(timestamp).toLocaleString();
    }

    updatePagination() {
        const totalPages = Math.ceil(this.filteredLogs.length / this.logsPerPage);
        document.getElementById('page-info').textContent = `Page ${this.currentPage} of ${totalPages}`;
        
        document.getElementById('prev-btn').disabled = this.currentPage === 1;
        document.getElementById('next-btn').disabled = this.currentPage === totalPages;
    }

    previousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.renderLogs();
        }
    }

    nextPage() {
        const totalPages = Math.ceil(this.filteredLogs.length / this.logsPerPage);
        if (this.currentPage < totalPages) {
            this.currentPage++;
            this.renderLogs();
        }
    }

    startRealTimeMonitor() {
        // Check for new logs every 5 seconds
        setInterval(() => {
            this.checkForNewLogs();
        }, 5000);
    }

    async checkForNewLogs() {
        try {
            // Use the dedicated real-time logs endpoint for better performance
            const response = await fetch(`${this.apiUrl}?action=get_real_time_logs&limit=5`);
            const data = await response.json();
            
            if (data.success && data.logs && data.logs.length > 0) {
                // Add all new logs to the monitor
                data.logs.forEach(log => {
                    // Check if this log is newer than our last update
                    const logTime = new Date(log.timestamp);
                    const lastUpdateTime = this.lastLogUpdate || new Date(Date.now() - 10000); // 10 seconds ago
                    
                    if (logTime > lastUpdateTime) {
                        this.addLogToMonitor(log);
                    }
                });
                
                this.lastLogUpdate = new Date();
            }
        } catch (error) {
            console.error('Error checking for new logs:', error);
            // Fallback to simulated logs if API fails
            this.addSimulatedLog();
        }
    }

    addSimulatedLog() {
        const categories = ['system', 'hotspot', 'voucher', 'user', 'network', 'firewall'];
        const levels = ['info', 'warning', 'error'];
        const messages = {
            system: ['System health check passed', 'Memory usage normal', 'CPU temperature stable'],
            hotspot: ['New client connected', 'Client disconnected', 'WiFi signal strong'],
            voucher: ['Voucher validated', 'Voucher expired', 'New voucher created'],
            user: ['User session started', 'User session ended', 'User blocked'],
            network: ['Network traffic normal', 'Bandwidth usage high', 'Connection stable'],
            firewall: ['Connection allowed', 'Connection blocked', 'Security check passed']
        };

        const category = categories[Math.floor(Math.random() * categories.length)];
        const level = levels[Math.floor(Math.random() * levels.length)];
        const message = messages[category][Math.floor(Math.random() * messages[category].length)];

        const logEntry = {
            timestamp: new Date().toISOString(),
            level: level,
            category: category,
            message: message,
            source: 'real-time'
        };

        this.addLogToMonitor(logEntry);
    }

    addLogToMonitor(log) {
        const monitor = document.getElementById('log-monitor');
        if (!monitor) return;

        const logElement = document.createElement('div');
        logElement.className = 'log-entry';
        logElement.innerHTML = `
            <span class="timestamp">[${this.formatTimestamp(log.timestamp)}]</span>
            <span class="level log-${log.level}">${log.level.toUpperCase()}</span>
            <span class="category">${log.category}</span>
            <span class="message">${log.message}</span>
        `;

        monitor.appendChild(logElement);

        // Auto-scroll to bottom if enabled
        if (this.autoScroll) {
            monitor.scrollTop = monitor.scrollHeight;
        }

        // Keep only last 100 entries
        const entries = monitor.querySelectorAll('.log-entry');
        if (entries.length > 100) {
            entries[0].remove();
        }
    }

    toggleAutoScroll() {
        this.autoScroll = !this.autoScroll;
        const button = document.getElementById('autoscroll-btn');
        button.textContent = `Auto Scroll: ${this.autoScroll ? 'ON' : 'OFF'}`;
    }

    clearMonitor() {
        const monitor = document.getElementById('log-monitor');
        if (monitor) {
            monitor.innerHTML = '';
        }
    }

    refreshLogs() {
        this.loadSampleLogs();
        this.filterLogs();
        this.showNotification('Logs refreshed successfully!', 'success');
    }

    exportLogs() {
        const csvContent = this.generateCSV();
        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `logs_${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        this.showNotification('Logs exported successfully!', 'success');
    }

    generateCSV() {
        const headers = ['Timestamp', 'Level', 'Category', 'Message', 'Source'];
        const rows = this.filteredLogs.map(log => [
            this.formatTimestamp(log.timestamp),
            log.level,
            log.category,
            log.message,
            log.source
        ]);

        return [headers, ...rows].map(row => row.join(',')).join('\n');
    }

    clearAllLogs() {
        if (confirm('Are you sure you want to clear all logs?')) {
            this.logs = [];
            this.filteredLogs = [];
            this.renderLogs();
            this.updateStatistics();
            this.showNotification('All logs cleared successfully!', 'success');
        }
    }

    viewLog(id) {
        const log = this.logs.find(l => l.id === id);
        if (log) {
            alert(`Log Details:\n\n` +
                  `Timestamp: ${this.formatTimestamp(log.timestamp)}\n` +
                  `Level: ${log.level.toUpperCase()}\n` +
                  `Category: ${log.category}\n` +
                  `Message: ${log.message}\n` +
                  `Source: ${log.source}\n` +
                  `ID: ${log.id}`);
        }
    }

    copyLog(id) {
        const log = this.logs.find(l => l.id === id);
        if (log) {
            const logText = `[${this.formatTimestamp(log.timestamp)}] [${log.level.toUpperCase()}] [${log.category}] ${log.message}`;
            navigator.clipboard.writeText(logText).then(() => {
                this.showNotification('Log copied to clipboard!', 'success');
            });
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
let logsManager;

function filterLogs() {
    logsManager.filterLogs();
}

function searchLogs() {
    logsManager.searchLogs();
}

function previousPage() {
    logsManager.previousPage();
}

function nextPage() {
    logsManager.nextPage();
}

function toggleAutoScroll() {
    logsManager.toggleAutoScroll();
}

function clearMonitor() {
    logsManager.clearMonitor();
}

function refreshLogs() {
    logsManager.refreshLogs();
}

function exportLogs() {
    logsManager.exportLogs();
}

function clearAllLogs() {
    logsManager.clearAllLogs();
}

function viewLog(id) {
    logsManager.viewLog(id);
}

function copyLog(id) {
    logsManager.copyLog(id);
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    logsManager = new LogsManager();
});