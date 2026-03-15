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

-- License Management Section
s2 = m:section(TypedSection, "license", "License Management")
s2.anonymous = true

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

-- Add JavaScript for license management
o = s2:option(DummyValue, "license_script", "")
o.rawhtml = true
o.value = [[
<script type="text/javascript">
(function() {
    var apiUrl = "/cgi-bin/luci/pisowifi/api";
    
    function formatDate(dateString) {
        if (!dateString) return "N/A";
        var date = new Date(dateString);
        return date.toLocaleString();
    }
    
    function formatDaysRemaining(expiresAt) {
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
    }
    
    function checkLicenseStatus() {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', apiUrl + '/license_status', true);
        xhr.onload = function() {
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText);
                displayLicenseStatus(data);
            } else {
                document.getElementById('license-status-display').innerHTML = '<span style="color: red;">Error checking license</span>';
            }
        };
        xhr.send();
    }
    
    function displayLicenseStatus(data) {
        document.getElementById('hardware-id-display').innerText = data.hardware_id || 'Unknown';
        
        if (data.status === 'valid') {
            document.getElementById('license-status-display').innerHTML = '<span style="color: green;">✓ Valid</span>';
            
            if (data.license_data) {
                if (data.license_data.status === 'trial') {
                    document.getElementById('trial-info-display').innerHTML = 'You are using a 7-day trial. ' + formatDaysRemaining(data.license_data.expires_at);
                    // Show license key input for activation
                    document.querySelector('[data-name="license_key"]').parentElement.style.display = 'block';
                    document.querySelector('[data-name="activate_license"]').parentElement.style.display = 'block';
                } else if (data.license_data.status === 'active') {
                    document.getElementById('license-status-display').innerHTML = '<span style="color: green;">✓ Active License</span>';
                    document.getElementById('vendor-uuid-display').innerText = data.license_data.vendor_uuid || 'N/A';
                    if (data.license_data.license_key) {
                        document.querySelector('[data-name="license_key"]').value = data.license_data.license_key;
                    }
                    // Hide activation controls
                    document.querySelector('[data-name="license_key"]').parentElement.style.display = 'none';
                    document.querySelector('[data-name="activate_license"]').parentElement.style.display = 'none';
                }
            }
        } else if (data.status === 'no_license') {
            document.getElementById('license-status-display').innerHTML = '<span style="color: orange;">No license found</span>';
            document.getElementById('trial-info-display').innerHTML = 'No license found. A trial license will be created automatically.';
            // Show license key input for activation
            document.querySelector('[data-name="license_key"]').parentElement.style.display = 'block';
            document.querySelector('[data-name="activate_license"]').parentElement.style.display = 'block';
        } else {
            document.getElementById('license-status-display').innerHTML = '<span style="color: red;">✗ Invalid</span>';
            document.getElementById('trial-info-display').innerHTML = 'License is invalid or expired.';
            // Show license key input for activation
            document.querySelector('[data-name="license_key"]').parentElement.style.display = 'block';
            document.querySelector('[data-name="activate_license"]').parentElement.style.display = 'block';
        }
    }
    
    function activateLicense() {
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
    }
    
    // Initialize license check when page loads
    document.addEventListener('DOMContentLoaded', function() {
        checkLicenseStatus();
        
        // Set up activation button
        var activateBtn = document.querySelector('[data-name="activate_license"]');
        if (activateBtn) {
            activateBtn.addEventListener('click', function(e) {
                e.preventDefault();
                activateLicense();
            });
        }
    });
})();
</script>
]]

return m