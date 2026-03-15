local license_model = require "luci.model.pisowifi_license"

m = Map("pisowifi", "PisoWifi Settings", "Configure your PisoWifi hotspot settings here.")

-- General Settings Section
s = m:section(TypedSection, "general", "General Settings")
s.anonymous = true

o = s:option(Flag, "enabled", "Enable PisoWifi", "Enable or disable the captive portal service.")
o.default = o.enabled

o = s:option(Value, "rate", "Rate per Minute (PHP)", "Set the rate for internet access.")
o.datatype = "ufloat"
o.default = "1.0"

o = s:option(Value, "welcome_msg", "Welcome Message", "Message displayed on the landing page.")
o.default = "Welcome to NEXI-FI PISOWIFI"

-- Centralized Key Card Section (Always Visible)
s3 = m:section(TypedSection, "centralized_key", "🔑 Centralized License Key Card")
s3.anonymous = true

-- Centralized Key Card Display (Always Visible)
o = s3:option(DummyValue, "centralized_key_display", "")
o.rawhtml = true
o.value = [[
<style>
.centralized-key-card {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 12px;
    padding: 20px;
    color: white;
    margin-bottom: 20px;
    box-shadow: 0 4px 15px rgba(0,0,0,0.2);
    display: block !important;
    visibility: visible !important;
    min-height: 150px;
    border: 2px solid rgba(255,255,255,0.3);
}
.centralized-key-card h3 {
    margin: 0 0 10px 0;
    color: white;
    font-size: 18px;
    font-weight: bold;
}
.centralized-key-card .card-row {
    display: flex;
    justify-content: space-between;
    margin-top: 8px;
    font-size: 14px;
}
.centralized-key-card .card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
}
.centralized-key-card .status-right {
    text-align: right;
}
.centralized-key-card .divider {
    margin-top: 15px;
    padding-top: 15px;
    border-top: 1px solid rgba(255,255,255,0.2);
}
.centralized-key-card .loading {
    opacity: 0.7;
    font-style: italic;
}
.centralized-key-card .card-title {
    font-size: 20px;
    margin-bottom: 15px;
    text-align: center;
    font-weight: bold;
}
</style>

<div class="centralized-key-card" id="centralized-key-card-main">
    <div class="card-title">🌐 CENTRALIZED LICENSE MANAGEMENT</div>
    <div class="card-header">
        <div>
            <h3>🔑 Centralized License</h3>
            <p style="margin: 0; opacity: 0.9;" id="centralized-status" class="loading">Loading centralized key status...</p>
        </div>
        <div class="status-right">
            <div style="font-size: 24px; font-weight: bold;" id="centralized-key-display">---</div>
            <div style="font-size: 12px; opacity: 0.8;">Centralized Key</div>
        </div>
    </div>
    <div class="divider">
        <div class="card-row">
            <span>Vendor ID:</span>
            <span id="centralized-vendor-id" class="loading">Loading...</span>
        </div>
        <div class="card-row">
            <span>Machine ID:</span>
            <span id="centralized-machine-id">]] .. (luci.sys.hostname() or 'Unknown') .. [[</span>
        </div>
        <div class="card-row">
            <span>Activation Status:</span>
            <span id="centralized-activation-status" class="loading">Loading...</span>
        </div>
        <div class="card-row">
            <span>Devices Synced:</span>
            <span id="centralized-devices-count">0</span>
        </div>
    </div>
</div>

<script>
// Force the card to be visible immediately
document.addEventListener('DOMContentLoaded', function() {
    console.log('Centralized Key Card: Forcing immediate visibility');
    setTimeout(function() {
        var card = document.getElementById('centralized-key-card-main');
        if (card) {
            card.style.display = 'block';
            card.style.visibility = 'visible';
            card.style.opacity = '1';
        }
    }, 50);
});
</script>
]]

-- Centralized Key Input and Buttons (Raw HTML to bypass CBI form submission)
o = s3:option(DummyValue, "centralized_key_controls", "")
o.rawhtml = true
o.value = [[
<div class="cbi-value">
    <label class="cbi-value-title">Centralized Key</label>
    <div class="cbi-value-field">
        <input type="text" class="cbi-input-text" id="centralized_key_input_field" placeholder="CENTRAL-XXXXXXXX-XXXXXXXXX" style="width: 300px;">
        <div class="cbi-value-description">
            <span class="cbi-value-helpicon"><img src="/luci-static/resources/cbi/help.gif" alt="help"></span>
            Enter your Centralized License Key here (format: CENTRAL-XXXXXXXX-XXXXXXXX)
        </div>
    </div>
</div>
<div class="cbi-value">
    <div class="cbi-value-field">
        <input type="button" class="cbi-button cbi-button-apply" value="Activate Centralized Key" onclick="activateCentralizedKey(this); return false;">
        <input type="button" class="cbi-button cbi-button-remove" value="Clear Centralized Key" onclick="clearCentralizedKey(this); return false;">
    </div>
</div>
]]

-- Note: Removed CBI Value/Button objects to prevent accidental form submission loops

-- License Management Section (Original)
s2 = m:section(TypedSection, "license", "License Management")
s2.anonymous = true

-- Centralized Key Card Display
o = s2:option(DummyValue, "centralized_key_card", "Centralized Key Card")
o.rawhtml = true
o.value = [[
<style>
.centralized-key-card {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 12px;
    padding: 20px;
    color: white;
    margin-bottom: 20px;
    box-shadow: 0 4px 15px rgba(0,0,0,0.2);
    display: block !important;
    visibility: visible !important;
    min-height: 150px;
}
.centralized-key-card h3 {
    margin: 0 0 10px 0;
    color: white;
    font-size: 18px;
}
.centralized-key-card .card-row {
    display: flex;
    justify-content: space-between;
    margin-top: 8px;
    font-size: 14px;
}
.centralized-key-card .card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
}
.centralized-key-card .status-right {
    text-align: right;
}
.centralized-key-card .divider {
    margin-top: 15px;
    padding-top: 15px;
    border-top: 1px solid rgba(255,255,255,0.2);
}
.centralized-key-card .loading {
    opacity: 0.7;
    font-style: italic;
}
</style>

<div class="centralized-key-card" id="centralized-key-card-main">
    <div class="card-header">
        <div>
            <h3>🔑 Centralized License</h3>
            <p style="margin: 0; opacity: 0.9;" id="centralized-status" class="loading">Loading centralized key status...</p>
        </div>
        <div class="status-right">
            <div style="font-size: 24px; font-weight: bold;" id="centralized-key-display">---</div>
            <div style="font-size: 12px; opacity: 0.8;">Centralized Key</div>
        </div>
    </div>
    <div class="divider">
        <div class="card-row">
            <span>Vendor ID:</span>
            <span id="centralized-vendor-id" class="loading">Loading...</span>
        </div>
        <div class="card-row">
            <span>Machine ID:</span>
            <span id="centralized-machine-id">]] .. (luci.sys.hostname() or 'Unknown') .. [[</span>
        </div>
        <div class="card-row">
            <span>Activation Status:</span>
            <span id="centralized-activation-status" class="loading">Loading...</span>
        </div>
        <div class="card-row">
            <span>Devices Synced:</span>
            <span id="centralized-devices-count">0</span>
        </div>
    </div>
</div>

<script>
// Force the card to be visible immediately
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(function() {
        var card = document.getElementById('centralized-key-card-main');
        if (card) {
            card.style.display = 'block';
            card.style.visibility = 'visible';
        }
    }, 100);
});
</script>
]]

-- Hardware ID Display
o = s2:option(DummyValue, "hardware_id", "Hardware ID")
o.rawhtml = true
o.value = "<span id='hardware-id-display'>Loading...</span>"

-- License Status Display
o = s2:option(DummyValue, "license_status", "License Status")
o.rawhtml = true
o.value = "<span id='license-status-display'>Loading...</span>"

-- License Key Input (only shown when needed)
o = s2:option(Value, "license_key", "License Key")
o.placeholder = "Enter license key to activate"
o.rmempty = true
o:depends("license_needed", "1")

-- Activation Button
o = s2:option(Button, "activate_license", "Activate License")
o.inputstyle = "apply"
o.inputtitle = "Activate"
o:depends("license_needed", "1")

-- Trial Information
o = s2:option(DummyValue, "trial_info", "Trial Information")
o.rawhtml = true
o.value = "<span id='trial-info-display'></span>"

-- Vendor UUID (shown when activated)
o = s2:option(DummyValue, "vendor_uuid", "Vendor UUID")
o.rawhtml = true
o.value = "<span id='vendor-uuid-display'></span>"

-- Centralized Vendor Sync Button
o = s2:option(Button, "sync_centralized", "Sync with Centralized System")
o.inputstyle = "apply"
o.inputtitle = "Sync Now"
o.onclick = "return confirm('This will sync your machine with the centralized vendor system. Continue?')"

-- WiFi Devices Sync Button
o = s2:option(Button, "sync_devices", "Sync WiFi Devices")
o.inputstyle = "apply"
o.inputtitle = "Sync Devices"
o.onclick = "return confirm('This will sync all active WiFi devices to the centralized system. Continue?')"

-- Add JavaScript for license management
o = s3:option(DummyValue, "license_script", "")
o.rawhtml = true
o.value = [[
<script type="text/javascript">
// Define functions globally so they can be called from onclick handlers
window.formatDate = function(dateString) {
    if (!dateString) return "N/A";
    var date = new Date(dateString);
    return date.toLocaleString();
};

window.formatDaysRemaining = function(expiresAt) {
    if (!expiresAt) return "";
    var expires = new Date(expiresAt);
    var now = new Date();
    var diffTime = expires - now;
    var diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    if (diffDays > 0) {
        return "Days remaining: " + diffDays;
    } else {
        return "Trial has expired";
    }
};

window.checkLicenseStatus = function() {
    console.log('Centralized Key Card: Checking license status...');
    var apiUrl = "/cgi-bin/luci/pisowifi/api";
    var xhr = new XMLHttpRequest();
    xhr.open('GET', apiUrl + '/license_status', true);
    xhr.onload = function() {
        if (xhr.status === 200) {
            var data = JSON.parse(xhr.responseText);
            console.log('Centralized Key Card: License data received', data);
            displayLicenseStatus(data);
        } else {
            console.log('Centralized Key Card: Error checking license');
            document.getElementById('license-status-display').innerHTML = '<span style="color: red;">Error checking license</span>';
        }
    };
    xhr.onerror = function() {
        console.log('Centralized Key Card: Network error checking license');
        document.getElementById('license-status-display').innerHTML = '<span style="color: red;">Network error</span>';
    };
    xhr.send();
};

window.displayLicenseStatus = function(data) {
    // ... (keep implementation same as before)
    console.log('Centralized Key Card: Displaying license status', data);
    document.getElementById('hardware-id-display').innerText = data.hardware_id || 'Unknown';
    
    // Update centralized key card
    if (data.license_data) {
        console.log('Centralized Key Card: License data found', data.license_data);
        if (data.license_data.vendor_uuid) {
            document.getElementById('centralized-vendor-id').innerText = data.license_data.vendor_uuid;
            // Display the actual centralized key format
            if (data.license_data.license_key && data.license_data.license_key.startsWith('CENTRAL-')) {
                document.getElementById('centralized-key-display').innerText = data.license_data.license_key;
                
                // Populate the input field if empty
                var input = document.getElementById('centralized_key_input_field');
                if (input && !input.value) {
                    input.value = data.license_data.license_key;
                }
            } else {
                document.getElementById('centralized-key-display').innerText = 'ACTIVE';
            }
            document.getElementById('centralized-activation-status').innerHTML = '<span style="color: #4ade80;">✓ Activated</span>';
        } else {
            document.getElementById('centralized-vendor-id').innerText = 'Not Assigned';
            document.getElementById('centralized-key-display').innerText = 'PENDING';
            document.getElementById('centralized-activation-status').innerHTML = '<span style="color: #fbbf24;">⏳ Pending</span>';
        }
    
        if (data.license_data.status === 'trial') {
            document.getElementById('centralized-status').innerText = 'You are using a 7-day trial license';
            document.getElementById('centralized-key-display').innerText = 'TRIAL';
            document.getElementById('centralized-activation-status').innerHTML = '<span style="color: #60a5fa;">🕒 Trial</span>';
        } else if (data.license_data.status === 'active') {
            document.getElementById('centralized-status').innerText = 'Centralized license is active and verified';
            // Show the actual centralized key format if available
            if (data.license_data.license_key && data.license_data.license_key.startsWith('CENTRAL-')) {
                document.getElementById('centralized-key-display').innerText = data.license_data.license_key;
            }
        } else if (data.license_data.status === 'expired') {
            document.getElementById('centralized-status').innerText = 'License has expired - please renew';
            document.getElementById('centralized-key-display').innerText = 'EXPIRED';
            document.getElementById('centralized-activation-status').innerHTML = '<span style="color: #ef4444;">✗ Expired</span>';
        }
        
        // Show device sync status if available
        if (data.devices_synced) {
            document.getElementById('centralized-devices-count').innerText = data.devices_synced;
        } else {
            document.getElementById('centralized-devices-count').innerText = '0';
        }
    } else {
        console.log('Centralized Key Card: No license data found');
        document.getElementById('centralized-status').innerText = 'No centralized license data available';
        document.getElementById('centralized-vendor-id').innerText = 'Not Available';
        document.getElementById('centralized-key-display').innerText = 'NONE';
        document.getElementById('centralized-activation-status').innerHTML = '<span style="color: #6b7280;">⚪ None</span>';
        document.getElementById('centralized-devices-count').innerText = '0';
    }
    
    if (data.status === 'valid') {
        document.getElementById('license-status-display').innerHTML = '<span style="color: green;">✓ Valid</span>';
        
        if (data.license_data) {
            if (data.license_data.status === 'trial') {
                document.getElementById('trial-info-display').innerHTML = 'You are using a 7-day trial. ' + formatDaysRemaining(data.license_data.expires_at);
                // Show license key input for activation
                var keyInput = document.querySelector('[data-name="license_key"]');
                if (keyInput && keyInput.parentElement) keyInput.parentElement.style.display = 'block';
                var activateBtn = document.querySelector('[data-name="activate_license"]');
                if (activateBtn && activateBtn.parentElement) activateBtn.parentElement.style.display = 'block';
            } else if (data.license_data.status === 'active') {
                document.getElementById('license-status-display').innerHTML = '<span style="color: green;">✓ Active License</span>';
                document.getElementById('vendor-uuid-display').innerText = data.license_data.vendor_uuid || 'N/A';
                if (data.license_data.license_key) {
                    var keyInput = document.querySelector('[data-name="license_key"]');
                    if (keyInput) keyInput.value = data.license_data.license_key;
                }
                // Hide activation controls
                var keyInput = document.querySelector('[data-name="license_key"]');
                if (keyInput && keyInput.parentElement) keyInput.parentElement.style.display = 'none';
                var activateBtn = document.querySelector('[data-name="activate_license"]');
                if (activateBtn && activateBtn.parentElement) activateBtn.parentElement.style.display = 'none';
            }
        }
    } else if (data.status === 'no_license') {
        document.getElementById('license-status-display').innerHTML = '<span style="color: orange;">No license found</span>';
        document.getElementById('trial-info-display').innerHTML = 'No license found. A trial license will be created automatically.';
        // Show license key input for activation
        var keyInput = document.querySelector('[data-name="license_key"]');
        if (keyInput && keyInput.parentElement) keyInput.parentElement.style.display = 'block';
        var activateBtn = document.querySelector('[data-name="activate_license"]');
        if (activateBtn && activateBtn.parentElement) activateBtn.parentElement.style.display = 'block';
    } else {
        document.getElementById('license-status-display').innerHTML = '<span style="color: red;">✗ Invalid</span>';
        document.getElementById('trial-info-display').innerHTML = 'License is invalid or expired.';
        // Show license key input for activation
        var keyInput = document.querySelector('[data-name="license_key"]');
        if (keyInput && keyInput.parentElement) keyInput.parentElement.style.display = 'block';
        var activateBtn = document.querySelector('[data-name="activate_license"]');
        if (activateBtn && activateBtn.parentElement) activateBtn.parentElement.style.display = 'block';
    }
};

window.activateLicense = function() {
    var apiUrl = "/cgi-bin/luci/pisowifi/api";
    var licenseKey = document.querySelector('[data-name="license_key"]').value.trim();
    if (!licenseKey) {
        alert('Please enter a license key');
        return;
    }
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', apiUrl + '/license_activate', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.onload = function() {
        if (xhr.status === 200) {
            var data = JSON.parse(xhr.responseText);
            alert('License activated successfully! Vendor UUID: ' + (data.vendor_uuid || 'N/A'));
            // Reload to update display
            location.reload();
        } else {
            var error = JSON.parse(xhr.responseText);
            alert('Activation failed: ' + (error.error || 'Unknown error'));
        }
    };
    xhr.send('license_key=' + encodeURIComponent(licenseKey));
};

window.syncCentralizedVendor = function() {
    if (!confirm('This will sync your machine with the centralized vendor system. Continue?')) {
        return;
    }
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/pisowifi/sync_centralized', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.onload = function() {
        if (xhr.status === 200) {
            var data = JSON.parse(xhr.responseText);
            if (data.success) {
                alert('Successfully synced with centralized vendor system!');
                checkLicenseStatus(); // Refresh the display
            } else {
                alert('Sync failed: ' + (data.error || 'Unknown error'));
            }
        } else {
            alert('Sync request failed');
        }
    };
    xhr.send();
};

window.syncWifiDevices = function() {
    if (!confirm('This will sync all active WiFi devices to the centralized system. Continue?')) {
        return;
    }
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/pisowifi/sync_devices', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.onload = function() {
        if (xhr.status === 200) {
            var data = JSON.parse(xhr.responseText);
            if (data.success) {
                alert('Successfully synced WiFi devices to centralized system! ' + data.message);
            } else {
                alert('Device sync failed: ' + (data.error || 'Unknown error'));
            }
        } else {
            alert('Device sync request failed');
        }
    };
    xhr.send();
};

window.activateCentralizedKey = function(btn) {
    var apiUrl = "/cgi-bin/luci/pisowifi/api";
    // Find the input field by ID since we are using raw HTML now
    var input = document.getElementById('centralized_key_input_field');
    var key = input ? input.value.trim() : '';
    
    if (!key) {
        alert('Please enter a Centralized Key');
        return false;
    }
    
    console.log('Activating Centralized Key:', key);
    
    // Basic format check (relaxed)
    if (!key.toUpperCase().startsWith('CENTRAL-')) {
        alert('Invalid format. Key must start with "CENTRAL-"');
        return false;
    }
    
    if (!confirm('Activate Centralized Key: ' + key + '?')) {
        return false;
    }
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', apiUrl + '/license_activate', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.onload = function() {
        if (xhr.status === 200) {
            var data = JSON.parse(xhr.responseText);
            if (data.vendor_uuid || data.status === 'active') {
                alert('Centralized Key activated successfully!');
                location.reload();
            } else {
                alert('Activation failed: ' + (data.error || 'Unknown error'));
            }
        } else {
            try {
                var error = JSON.parse(xhr.responseText);
                alert('Activation failed: ' + (error.error || 'Server error'));
            } catch(e) {
                alert('Activation failed: Server error ' + xhr.status);
            }
        }
    };
    xhr.send('license_key=' + encodeURIComponent(key));
    
    return false; // Prevent form submission
};

window.clearCentralizedKey = function(btn) {
    if (!confirm('Are you sure you want to clear the Centralized Key? This will deactivate centralized management.')) {
        return false;
    }
    
    var input = document.getElementById('centralized_key_input_field');
    if (input) input.value = '';
    alert('Key cleared from input. To fully deactivate, please contact support or enter a new key.');
    
    return false; // Prevent form submission
};

(function() {
    // Initialize license check when page loads
    document.addEventListener('DOMContentLoaded', function() {
        console.log('Centralized Key Card: Initializing license check...');
        
        // Force display of centralized key card immediately
        setTimeout(function() {
            console.log('Centralized Key Card: Forcing initial display');
            var cardMain = document.getElementById('centralized-key-card-main');
            if (cardMain) {
                cardMain.style.display = 'block';
                cardMain.style.visibility = 'visible';
            }
            
            // Initialize card with basic info
            if (document.getElementById('centralized-status')) {
                document.getElementById('centralized-status').innerText = 'Initializing centralized license...';
            }
            if (document.getElementById('centralized-key-display')) {
                document.getElementById('centralized-key-display').innerText = 'LOADING';
            }
            if (document.getElementById('centralized-vendor-id')) {
                document.getElementById('centralized-vendor-id').innerText = 'Checking...';
            }
            if (document.getElementById('centralized-activation-status')) {
                document.getElementById('centralized-activation-status').innerHTML = '<span style="color: #60a5fa;">🔄 Loading</span>';
            }
        }, 500);
        
        checkLicenseStatus();
        
        // Setup listeners for other buttons if needed (though onclick handles most now)
        
        // Force display of centralized key card elements
        setTimeout(function() {
            console.log('Centralized Key Card: Forcing display of card elements');
            var cardElements = [
                'centralized-status',
                'centralized-key-display', 
                'centralized-vendor-id',
                'centralized-machine-id',
                'centralized-activation-status',
                'centralized-devices-count'
            ];
            
            cardElements.forEach(function(id) {
                var element = document.getElementById(id);
                if (element) {
                    console.log('Centralized Key Card: Element ' + id + ' found');
                    element.style.display = 'block';
                } else {
                    console.log('Centralized Key Card: Element ' + id + ' NOT found');
                }
            });
        }, 1000);
    });
})();
</script>
]]

return m