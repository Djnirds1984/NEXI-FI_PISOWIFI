// Voucher Management JavaScript with Real API Integration
class VoucherManager {
    constructor() {
        this.vouchers = [];
        this.filteredVouchers = [];
        this.apiUrl = '/cgi-bin/api-real.cgi';
        this.init();
    }

    init() {
        this.loadVouchers();
        this.setupEventListeners();
        this.startAutoRefresh();
    }

    async loadVouchers() {
        try {
            const response = await fetch(`${this.apiUrl}?action=list_vouchers`);
            const data = await response.json();
            
            if (data.success) {
                this.vouchers = data.vouchers || [];
                this.filteredVouchers = [...this.vouchers];
                this.updateStatistics();
                this.renderVouchers();
            } else {
                this.showNotification('Failed to load vouchers: ' + data.error, 'error');
                // Fallback to sample data if API fails
                this.loadSampleData();
            }
        } catch (error) {
            console.error('Error loading vouchers:', error);
            this.showNotification('Error loading vouchers from server', 'error');
            // Fallback to sample data
            this.loadSampleData();
        }
    }

    loadSampleData() {
        // Sample voucher data for fallback
        this.vouchers = [
            {
                id: 1,
                code: 'PISO2024001',
                duration: 60,
                price: 10.00,
                status: 'active',
                created: new Date('2024-01-15T10:00:00'),
                expiry: new Date('2024-02-15T23:59:59'),
                usedBy: null,
                usedTime: null,
                maxDevices: 1,
                notes: 'Promotional voucher'
            },
            {
                id: 2,
                code: 'PISO2024002',
                duration: 180,
                price: 25.00,
                status: 'used',
                created: new Date('2024-01-14T15:30:00'),
                expiry: new Date('2024-02-14T23:59:59'),
                usedBy: '192.168.1.100',
                usedTime: new Date('2024-01-15T08:20:00'),
                maxDevices: 2,
                notes: 'Customer voucher'
            }
        ];
        this.filteredVouchers = [...this.vouchers];
        this.updateStatistics();
        this.renderVouchers();
    }

    setupEventListeners() {
        // Modal event listeners
        document.getElementById('voucher-form')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveVoucher();
        });

        // Set default expiry date (30 days from now)
        const expiryInput = document.getElementById('expiry-date');
        if (expiryInput) {
            const defaultExpiry = new Date();
            defaultExpiry.setDate(defaultExpiry.getDate() + 30);
            expiryInput.value = defaultExpiry.toISOString().split('T')[0];
        }

        const batchExpiryInput = document.getElementById('batch-expiry');
        if (batchExpiryInput) {
            batchExpiryInput.value = defaultExpiry.toISOString().split('T')[0];
        }
    }

    async saveVoucher() {
        const id = document.getElementById('voucher-id').value;
        const code = document.getElementById('voucher-code').value.trim();
        const duration = parseInt(document.getElementById('duration').value);
        const price = parseFloat(document.getElementById('price').value);
        const expiry = new Date(document.getElementById('expiry-date').value);
        const maxDevices = parseInt(document.getElementById('max-devices').value);
        const notes = document.getElementById('notes').value.trim();

        if (!code || !duration || !price || !expiry) {
            this.showNotification('Please fill in all required fields', 'error');
            return;
        }

        try {
            const voucherData = {
                code: code,
                duration: duration,
                price: price,
                expiry: expiry.toISOString(),
                maxDevices: maxDevices,
                notes: notes
            };

            if (id) {
                // Edit existing voucher
                voucherData.id = parseInt(id);
                voucherData.action = 'update_voucher';
            } else {
                // Create new voucher
                voucherData.action = 'create_voucher';
            }

            const response = await fetch(this.apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(voucherData)
            });

            const data = await response.json();

            if (data.success) {
                this.showNotification('Voucher saved successfully!', 'success');
                this.closeModal();
                this.loadVouchers(); // Reload from server
            } else {
                this.showNotification('Failed to save voucher: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error saving voucher:', error);
            this.showNotification('Error saving voucher to server', 'error');
        }
    }

    async deleteVoucher(id) {
        if (confirm('Are you sure you want to delete this voucher?')) {
            try {
                const response = await fetch(this.apiUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        action: 'delete_voucher',
                        id: id
                    })
                });

                const data = await response.json();

                if (data.success) {
                    this.showNotification('Voucher deleted successfully!', 'success');
                    this.loadVouchers(); // Reload from server
                } else {
                    this.showNotification('Failed to delete voucher: ' + data.error, 'error');
                }
            } catch (error) {
                console.error('Error deleting voucher:', error);
                this.showNotification('Error deleting voucher from server', 'error');
            }
        }
    }

    async generateBatchVouchers() {
        const count = parseInt(document.getElementById('batch-count').value);
        const duration = parseInt(document.getElementById('batch-duration').value);
        const price = parseFloat(document.getElementById('batch-price').value);
        const expiry = new Date(document.getElementById('batch-expiry').value);
        const prefix = document.getElementById('batch-prefix').value.trim();

        if (!count || !duration || !price || !expiry) {
            this.showNotification('Please fill in all required fields', 'error');
            return;
        }

        try {
            const batchData = {
                action: 'generate_batch_vouchers',
                count: count,
                duration: duration,
                price: price,
                expiry: expiry.toISOString(),
                prefix: prefix
            };

            const response = await fetch(this.apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(batchData)
            });

            const data = await response.json();

            if (data.success) {
                this.showNotification(`${count} vouchers generated successfully!`, 'success');
                this.closeBatchModal();
                this.loadVouchers(); // Reload from server
            } else {
                this.showNotification('Failed to generate vouchers: ' + data.error, 'error');
            }
        } catch (error) {
            console.error('Error generating batch vouchers:', error);
            this.showNotification('Error generating vouchers from server', 'error');
        }
    }

    updateStatistics() {
        const total = this.vouchers.length;
        const active = this.vouchers.filter(v => v.status === 'active').length;
        const used = this.vouchers.filter(v => v.status === 'used').length;
        const expired = this.vouchers.filter(v => v.status === 'expired').length;
        const revenue = this.vouchers.filter(v => v.status === 'used').reduce((sum, v) => sum + v.price, 0);

        document.getElementById('total-vouchers').textContent = total;
        document.getElementById('active-vouchers').textContent = active;
        document.getElementById('expired-vouchers').textContent = expired;
        document.getElementById('total-revenue').textContent = `₱${revenue.toFixed(2)}`;
    }

    renderVouchers() {
        const tbody = document.getElementById('vouchers-tbody');
        if (!tbody) return;

        tbody.innerHTML = '';

        this.filteredVouchers.forEach(voucher => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><strong>${voucher.code}</strong></td>
                <td>${this.formatDuration(voucher.duration)}</td>
                <td>₱${voucher.price.toFixed(2)}</td>
                <td><span class="status-badge status-${voucher.status}">${voucher.status.toUpperCase()}</span></td>
                <td>${this.formatDate(voucher.created)}</td>
                <td>${voucher.usedBy || '-'}</td>
                <td>${voucher.usedTime ? this.formatDate(voucher.usedTime) : '-'}</td>
                <td>
                    <div class="action-buttons">
                        <button class="btn-small btn-view" onclick="viewVoucher(${voucher.id})">View</button>
                        <button class="btn-small btn-edit" onclick="editVoucher(${voucher.id})">Edit</button>
                        <button class="btn-small btn-delete" onclick="deleteVoucher(${voucher.id})">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    }

    formatDuration(minutes) {
        if (minutes < 60) {
            return `${minutes} min`;
        } else {
            const hours = minutes / 60;
            return `${hours} hour${hours !== 1 ? 's' : ''}`;
        }
    }

    formatDate(date) {
        if (!date) return '-';
        return new Date(date).toLocaleString();
    }

    showCreateModal() {
        document.getElementById('modal-title').textContent = 'Create Voucher';
        document.getElementById('voucher-id').value = '';
        document.getElementById('voucher-form').reset();
        
        // Set default expiry date
        const defaultExpiry = new Date();
        defaultExpiry.setDate(defaultExpiry.getDate() + 30);
        document.getElementById('expiry-date').value = defaultExpiry.toISOString().split('T')[0];
        
        document.getElementById('voucher-modal').style.display = 'block';
    }

    showEditModal(voucher) {
        document.getElementById('modal-title').textContent = 'Edit Voucher';
        document.getElementById('voucher-id').value = voucher.id;
        document.getElementById('voucher-code').value = voucher.code;
        document.getElementById('duration').value = voucher.duration;
        document.getElementById('price').value = voucher.price;
        document.getElementById('expiry-date').value = new Date(voucher.expiry).toISOString().split('T')[0];
        document.getElementById('max-devices').value = voucher.maxDevices;
        document.getElementById('notes').value = voucher.notes || '';
        
        document.getElementById('voucher-modal').style.display = 'block';
    }

    closeModal() {
        document.getElementById('voucher-modal').style.display = 'none';
    }

    generateCode() {
        const prefix = 'PISO';
        const timestamp = Date.now().toString().slice(-6);
        const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
        const code = `${prefix}${timestamp}${random}`;
        document.getElementById('voucher-code').value = code;
    }

    filterVouchers() {
        const statusFilter = document.getElementById('status-filter').value;
        const durationFilter = document.getElementById('duration-filter').value;
        const searchInput = document.getElementById('search-input').value.toLowerCase();

        this.filteredVouchers = this.vouchers.filter(voucher => {
            const matchesStatus = !statusFilter || voucher.status === statusFilter;
            const matchesDuration = !durationFilter || voucher.duration === parseInt(durationFilter);
            const matchesSearch = !searchInput || 
                voucher.code.toLowerCase().includes(searchInput) ||
                (voucher.usedBy && voucher.usedBy.toLowerCase().includes(searchInput));

            return matchesStatus && matchesDuration && matchesSearch;
        });

        this.renderVouchers();
    }

    searchVouchers() {
        this.filterVouchers();
    }

    showBatchModal() {
        document.getElementById('batch-modal').style.display = 'block';
    }

    closeBatchModal() {
        document.getElementById('batch-modal').style.display = 'none';
    }

    async exportVouchers() {
        try {
            const response = await fetch(`${this.apiUrl}?action=export_vouchers&format=csv`);
            const data = await response.json();

            if (data.success && data.csv) {
                const blob = new Blob([data.csv], { type: 'text/csv' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `vouchers_${new Date().toISOString().split('T')[0]}.csv`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                this.showNotification('Vouchers exported successfully!', 'success');
            } else {
                // Fallback to local CSV generation
                this.exportVouchersLocal();
            }
        } catch (error) {
            console.error('Error exporting vouchers:', error);
            // Fallback to local CSV generation
            this.exportVouchersLocal();
        }
    }

    exportVouchersLocal() {
        const headers = ['Code', 'Duration (min)', 'Price (PHP)', 'Status', 'Created', 'Expiry', 'Used By', 'Used Time', 'Max Devices', 'Notes'];
        const rows = this.vouchers.map(voucher => [
            voucher.code,
            voucher.duration,
            voucher.price,
            voucher.status,
            this.formatDate(voucher.created),
            this.formatDate(voucher.expiry),
            voucher.usedBy || '',
            voucher.usedTime ? this.formatDate(voucher.usedTime) : '',
            voucher.maxDevices,
            voucher.notes || ''
        ]);

        const csvContent = [headers, ...rows].map(row => row.join(',')).join('\n');
        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `vouchers_${new Date().toISOString().split('T')[0]}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        this.showNotification('Vouchers exported successfully!', 'success');
    }

    startAutoRefresh() {
        // Auto-refresh every 30 seconds
        setInterval(() => {
            this.loadVouchers();
        }, 30000);
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
let voucherManager;

function showCreateModal() {
    voucherManager.showCreateModal();
}

function editVoucher(id) {
    const voucher = voucherManager.vouchers.find(v => v.id === id);
    if (voucher) {
        voucherManager.showEditModal(voucher);
    }
}

function deleteVoucher(id) {
    voucherManager.deleteVoucher(id);
}

function viewVoucher(id) {
    const voucher = voucherManager.vouchers.find(v => v.id === id);
    if (voucher) {
        alert(`Voucher Details:\n\n` +
              `Code: ${voucher.code}\n` +
              `Duration: ${voucherManager.formatDuration(voucher.duration)}\n` +
              `Price: ₱${voucher.price.toFixed(2)}\n` +
              `Status: ${voucher.status.toUpperCase()}\n` +
              `Created: ${voucherManager.formatDate(voucher.created)}\n` +
              `Expiry: ${voucherManager.formatDate(voucher.expiry)}\n` +
              `Max Devices: ${voucher.maxDevices}\n` +
              `Used By: ${voucher.usedBy || 'Not used'}\n` +
              `Used Time: ${voucher.usedTime ? voucherManager.formatDate(voucher.usedTime) : 'Not used'}\n` +
              `Notes: ${voucher.notes || 'None'}`);
    }
}

function generateCode() {
    voucherManager.generateCode();
}

function saveVoucher() {
    voucherManager.saveVoucher();
}

function closeModal() {
    voucherManager.closeModal();
}

function filterVouchers() {
    voucherManager.filterVouchers();
}

function searchVouchers() {
    voucherManager.searchVouchers();
}

function generateBatch() {
    voucherManager.showBatchModal();
}

function generateBatchVouchers() {
    voucherManager.generateBatchVouchers();
}

function closeBatchModal() {
    voucherManager.closeBatchModal();
}

function exportVouchers() {
    voucherManager.exportVouchers();
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    voucherManager = new VoucherManager();
});

// Close modals when clicking outside
window.onclick = function(event) {
    const voucherModal = document.getElementById('voucher-modal');
    const batchModal = document.getElementById('batch-modal');
    
    if (event.target === voucherModal) {
        voucherManager.closeModal();
    }
    if (event.target === batchModal) {
        voucherManager.closeBatchModal();
    }
}