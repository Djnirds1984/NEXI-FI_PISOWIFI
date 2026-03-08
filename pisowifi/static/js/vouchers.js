// Voucher Management JavaScript
class VoucherManager {
    constructor() {
        this.vouchers = [];
        this.filteredVouchers = [];
        this.init();
    }

    init() {
        this.loadSampleData();
        this.setupEventListeners();
        this.updateStatistics();
        this.renderVouchers();
    }

    loadSampleData() {
        // Sample voucher data
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
            },
            {
                id: 3,
                code: 'PISO2024003',
                duration: 30,
                price: 5.00,
                status: 'expired',
                created: new Date('2023-12-01T09:00:00'),
                expiry: new Date('2024-01-01T23:59:59'),
                usedBy: null,
                usedTime: null,
                maxDevices: 1,
                notes: 'Test voucher'
            },
            {
                id: 4,
                code: 'PISO2024004',
                duration: 360,
                price: 45.00,
                status: 'active',
                created: new Date('2024-01-16T14:00:00'),
                expiry: new Date('2024-02-16T23:59:59'),
                usedBy: null,
                usedTime: null,
                maxDevices: 3,
                notes: 'Premium voucher'
            },
            {
                id: 5,
                code: 'PISO2024005',
                duration: 1440,
                price: 150.00,
                status: 'active',
                created: new Date('2024-01-17T11:30:00'),
                expiry: new Date('2024-02-17T23:59:59'),
                usedBy: null,
                usedTime: null,
                maxDevices: 5,
                notes: '24-hour unlimited'
            }
        ];

        this.filteredVouchers = [...this.vouchers];
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

    saveVoucher() {
        const id = document.getElementById('voucher-id').value;
        const code = document.getElementById('voucher-code').value.trim();
        const duration = parseInt(document.getElementById('duration').value);
        const price = parseFloat(document.getElementById('price').value);
        const expiry = new Date(document.getElementById('expiry-date').value);
        const maxDevices = parseInt(document.getElementById('max-devices').value);
        const notes = document.getElementById('notes').value.trim();

        if (!code || !duration || !price || !expiry) {
            alert('Please fill in all required fields');
            return;
        }

        if (id) {
            // Edit existing voucher
            const voucher = this.vouchers.find(v => v.id === parseInt(id));
            if (voucher) {
                voucher.code = code;
                voucher.duration = duration;
                voucher.price = price;
                voucher.expiry = expiry;
                voucher.maxDevices = maxDevices;
                voucher.notes = notes;
            }
        } else {
            // Create new voucher
            const newVoucher = {
                id: this.vouchers.length + 1,
                code: code,
                duration: duration,
                price: price,
                status: 'active',
                created: new Date(),
                expiry: expiry,
                usedBy: null,
                usedTime: null,
                maxDevices: maxDevices,
                notes: notes
            };
            this.vouchers.push(newVoucher);
        }

        this.filteredVouchers = [...this.vouchers];
        this.updateStatistics();
        this.renderVouchers();
        this.closeModal();
        this.showNotification('Voucher saved successfully!', 'success');
    }

    deleteVoucher(id) {
        if (confirm('Are you sure you want to delete this voucher?')) {
            this.vouchers = this.vouchers.filter(v => v.id !== id);
            this.filteredVouchers = [...this.vouchers];
            this.updateStatistics();
            this.renderVouchers();
            this.showNotification('Voucher deleted successfully!', 'success');
        }
    }

    viewVoucher(id) {
        const voucher = this.vouchers.find(v => v.id === id);
        if (voucher) {
            alert(`Voucher Details:\n\n` +
                  `Code: ${voucher.code}\n` +
                  `Duration: ${this.formatDuration(voucher.duration)}\n` +
                  `Price: ₱${voucher.price.toFixed(2)}\n` +
                  `Status: ${voucher.status.toUpperCase()}\n` +
                  `Created: ${this.formatDate(voucher.created)}\n` +
                  `Expiry: ${this.formatDate(voucher.expiry)}\n` +
                  `Max Devices: ${voucher.maxDevices}\n` +
                  `Used By: ${voucher.usedBy || 'Not used'}\n` +
                  `Used Time: ${voucher.usedTime ? this.formatDate(voucher.usedTime) : 'Not used'}\n` +
                  `Notes: ${voucher.notes || 'None'}`);
        }
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

    generateBatchVouchers() {
        const count = parseInt(document.getElementById('batch-count').value);
        const duration = parseInt(document.getElementById('batch-duration').value);
        const price = parseFloat(document.getElementById('batch-price').value);
        const expiry = new Date(document.getElementById('batch-expiry').value);
        const prefix = document.getElementById('batch-prefix').value.trim();

        if (!count || !duration || !price || !expiry) {
            alert('Please fill in all required fields');
            return;
        }

        const newVouchers = [];
        const startId = this.vouchers.length + 1;

        for (let i = 0; i < count; i++) {
            const code = prefix ? 
                `${prefix}${(startId + i).toString().padStart(4, '0')}` :
                `PISO${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`;

            newVouchers.push({
                id: startId + i,
                code: code,
                duration: duration,
                price: price,
                status: 'active',
                created: new Date(),
                expiry: expiry,
                usedBy: null,
                usedTime: null,
                maxDevices: 1,
                notes: 'Batch generated voucher'
            });
        }

        this.vouchers.push(...newVouchers);
        this.filteredVouchers = [...this.vouchers];
        this.updateStatistics();
        this.renderVouchers();
        this.closeBatchModal();
        this.showNotification(`${count} vouchers generated successfully!`, 'success');
    }

    exportVouchers() {
        const csvContent = this.generateCSV();
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

    generateCSV() {
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

        return [headers, ...rows].map(row => row.join(',')).join('\n');
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
    voucherManager.viewVoucher(id);
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