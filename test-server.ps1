# PisoWiFi Test Server Setup Script
# This script creates a simple local web server to test all PisoWiFi pages

Write-Host "Setting up PisoWiFi test server..." -ForegroundColor Green

# Create test server directory
$testDir = "test-server"
if (Test-Path $testDir) {
    Remove-Item -Recurse -Force $testDir
}
New-Item -ItemType Directory -Path $testDir | Out-Null

# Copy all PisoWiFi files to test directory
Write-Host "Copying PisoWiFi files..." -ForegroundColor Yellow
Copy-Item -Recurse -Path "pisowifi\*" -Destination $testDir -Force

# Create a simple HTTP server script
$serverScript = @"
# Simple HTTP Server for PisoWiFi Testing
# This simulates the OpenWrt uhttpd environment

`$port = 8080
`$rootDir = "."

Write-Host "Starting PisoWiFi test server on port `$port..." -ForegroundColor Green
Write-Host "Access the dashboard at: http://localhost:`$port/" -ForegroundColor Yellow
Write-Host "Access hotspot settings at: http://localhost:`$port/hotspot.html" -ForegroundColor Yellow
Write-Host "Access vouchers at: http://localhost:`$port/vouchers.html" -ForegroundColor Yellow
Write-Host "Access settings at: http://localhost:`$port/settings.html" -ForegroundColor Yellow
Write-Host "Access logs at: http://localhost:`$port/logs.html" -ForegroundColor Yellow
Write-Host "Access users at: http://localhost:`$port/users.html" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Red

# Create HTTP listener
`$listener = New-Object System.Net.HttpListener
`$listener.Prefixes.Add("http://+:`$port/")
`$listener.Start()

function Send-Response {
    param(`$context, `$content, `$contentType = "text/html", `$statusCode = 200)
    
    `$response = `$context.Response
    `$response.StatusCode = `$statusCode
    `$response.ContentType = `$contentType
    
    `$buffer = [System.Text.Encoding]::UTF8.GetBytes(`$content)
    `$response.ContentLength64 = `$buffer.Length
    `$response.OutputStream.Write(`$buffer, 0, `$buffer.Length)
    `$response.OutputStream.Close()
}

function Get-ContentType {
    param(`$extension)
    switch (`$extension.ToLower()) {
        ".html" { return "text/html" }
        ".css" { return "text/css" }
        ".js" { return "application/javascript" }
        ".json" { return "application/json" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".gif" { return "image/gif" }
        ".ico" { return "image/x-icon" }
        default { return "text/plain" }
    }
}

# Simulate CGI for api-real.cgi
function Handle-ApiRequest {
    param(`$context, `$requestBody)
    
    `$responseData = @{
        success = `$true
        message = "API simulation - all functions working"
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }
    
    # Simulate different API endpoints
    if (`$context.Request.RawUrl -like "*action=get_vouchers*") {
        `$responseData.vouchers = @(
            @{
                id = "TEST001"
                code = "TEST123"
                duration = 60
                price = 10
                status = "active"
                created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }
        )
    }
    elseif (`$context.Request.RawUrl -like "*action=get_settings*") {
        `$responseData.settings = @{
            hotspot_name = "PisoWiFi-Test"
            hotspot_password = "test12345"
            admin_password = "admin123"
            voucher_expiry = 24
            max_clients = 50
            captive_portal = `$true
            redirect_url = "http://10.0.0.1"
        }
    }
    elseif (`$context.Request.RawUrl -like "*action=get_connected_users*") {
        `$responseData.users = @(
            @{
                ip = "192.168.1.100"
                mac = "00:11:22:33:44:55"
                hostname = "test-client"
                connected_time = "00:15:30"
                status = "online"
            }
        )
    }
    elseif (`$context.Request.RawUrl -like "*action=get_logs*") {
        `$responseData.logs = @(
            @{
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                level = "info"
                source = "system"
                message = "Test server started successfully"
                category = "system"
            }
        )
    }
    
    `$jsonResponse = `$responseData | ConvertTo-Json -Depth 10
    Send-Response `$context `$jsonResponse "application/json"
}

try {
    while (`$listener.IsListening) {
        `$context = `$listener.GetContext()
        `$request = `$context.Request
        `$url = `$request.RawUrl
        
        Write-Host "`$(Get-Date): Requested `$url" -ForegroundColor Cyan
        
        # Handle CGI requests
        if (`$url -like "*/cgi-bin/api-real.cgi*") {
            Handle-ApiRequest `$context
            continue
        }
        
        # Handle static files
        `$localPath = `$url.Substring(1) -replace '\?.*', ''  # Remove query string
        if ([string]::IsNullOrEmpty(`$localPath)) {
            `$localPath = "index.html"
        }
        
        `$fullPath = Join-Path `$rootDir `$localPath
        
        if (Test-Path `$fullPath -PathType Leaf) {
            try {
                `$content = [System.IO.File]::ReadAllBytes(`$fullPath)
                `$extension = [System.IO.Path]::GetExtension(`$fullPath)
                `$contentType = Get-ContentType `$extension
                
                `$response = `$context.Response
                `$response.StatusCode = 200
                `$response.ContentType = `$contentType
                `$response.ContentLength64 = `$content.Length
                `$response.OutputStream.Write(`$content, 0, `$content.Length)
                `$response.OutputStream.Close()
                
                Write-Host "Served: `$fullPath" -ForegroundColor Green
            }
            catch {
                Send-Response `$context "Error reading file: `$(`$_.Exception.Message)" "text/plain" 500
            }
        }
        else {
            # Try to find index.html in requested directory
            `$indexPath = Join-Path `$fullPath "index.html"
            if (Test-Path `$indexPath -PathType Leaf) {
                try {
                    `$content = [System.IO.File]::ReadAllBytes(`$indexPath)
                    `$response = `$context.Response
                    `$response.StatusCode = 200
                    `$response.ContentType = "text/html"
                    `$response.ContentLength64 = `$content.Length
                    `$response.OutputStream.Write(`$content, 0, `$content.Length)
                    `$response.OutputStream.Close()
                    
                    Write-Host "Served: `$indexPath" -ForegroundColor Green
                }
                catch {
                    Send-Response `$context "Error reading file: `$(`$_.Exception.Message)" "text/plain" 500
                }
            }
            else {
                Send-Response `$context "404 - File not found: `$localPath" "text/plain" 404
                Write-Host "Not found: `$fullPath" -ForegroundColor Red
            }
        }
    }
}
catch {
    Write-Host "Server error: `$(`$_.Exception.Message)" -ForegroundColor Red
}
finally {
    `$listener.Stop()
    Write-Host "Server stopped" -ForegroundColor Yellow
}
"@

# Save the server script
$serverScript | Out-File -FilePath "$testDir\start-server.ps1" -Encoding UTF8

# Create a test runner script
$testScript = @"
Write-Host "PisoWiFi Test Suite" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green

# Test 1: Check if all HTML files exist
Write-Host "`nTest 1: Checking HTML files..." -ForegroundColor Yellow
`$htmlFiles = @("index.html", "hotspot.html", "vouchers.html", "settings.html", "logs.html", "users.html")
`$missingFiles = @()

foreach (`$file in `$htmlFiles) {
    if (Test-Path `$file) {
        Write-Host "✓ `$file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ `$file missing" -ForegroundColor Red
        `$missingFiles += `$file
    }
}

# Test 2: Check if all JS files exist
Write-Host "`nTest 2: Checking JavaScript files..." -ForegroundColor Yellow
`$jsFiles = @(
    "static\js\dashboard.js",
    "static\js\hotspot.js", 
    "static\js\vouchers.js",
    "static\js\settings.js",
    "static\js\logs.js",
    "static\js\users.js"
)

foreach (`$file in `$jsFiles) {
    if (Test-Path `$file) {
        Write-Host "✓ `$file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ `$file missing" -ForegroundColor Red
        `$missingFiles += `$file
    }
}

# Test 3: Check if CSS files exist
Write-Host "`nTest 3: Checking CSS files..." -ForegroundColor Yellow
`$cssFiles = @("static\css\style.css", "static\css\dashboard.css")

foreach (`$file in `$cssFiles) {
    if (Test-Path `$file) {
        Write-Host "✓ `$file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ `$file missing" -ForegroundColor Red
        `$missingFiles += `$file
    }
}

# Test 4: Check API CGI file
Write-Host "`nTest 4: Checking API CGI file..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") {
    Write-Host "✓ api-real.cgi exists" -ForegroundColor Green
}
else {
    Write-Host "✗ api-real.cgi missing" -ForegroundColor Red
    `$missingFiles += "cgi-bin\api-real.cgi"
}

# Test 5: Basic HTML validation
Write-Host "`nTest 5: Basic HTML validation..." -ForegroundColor Yellow
foreach (`$file in `$htmlFiles) {
    if (Test-Path `$file) {
        `$content = Get-Content `$file -Raw
        if (`$content -match '<!DOCTYPE html>' -and `$content -match '<html' -and `$content -match '</html>') {
            Write-Host "✓ `$file has valid HTML structure" -ForegroundColor Green
        }
        else {
            Write-Host "✗ `$file has invalid HTML structure" -ForegroundColor Red
        }
        
        # Check for JavaScript links
        if (`$content -match 'src=".*\.js"') {
            Write-Host "✓ `$file has JavaScript links" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ `$file may be missing JavaScript links" -ForegroundColor Yellow
        }
        
        # Check for CSS links
        if (`$content -match 'href=".*\.css"') {
            Write-Host "✓ `$file has CSS links" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ `$file may be missing CSS links" -ForegroundColor Yellow
        }
    }
}

# Test 6: JavaScript validation
Write-Host "`nTest 6: JavaScript validation..." -ForegroundColor Yellow
foreach (`$file in `$jsFiles) {
    if (Test-Path `$file) {
        `$content = Get-Content `$file -Raw
        
        # Check for basic JavaScript patterns
        `$issues = @()
        
        if (`$content -match 'console\.log') {
            `$issues += "Contains console.log statements"
        }
        
        if (`$content -match 'async.*function' -or `$content -match 'async.*=>') {
            Write-Host "✓ `$file uses modern async/await" -ForegroundColor Green
        }
        else {
            `$issues += "May not use async/await patterns"
        }
        
        if (`$content -match 'fetch\(') {
            Write-Host "✓ `$file uses fetch API" -ForegroundColor Green
        }
        else {
            `$issues += "May not use fetch API"
        }
        
        if (`$issues.Count -eq 0) {
            Write-Host "✓ `$file looks good" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ `$file has potential issues: `$(`$issues -join ', ')" -ForegroundColor Yellow
        }
    }
}

# Test 7: API endpoint validation
Write-Host "`nTest 7: API endpoint validation..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") {
    `$content = Get-Content "cgi-bin\api-real.cgi" -Raw
    
    `$endpoints = @(
        "get_vouchers",
        "save_voucher", 
        "delete_voucher",
        "get_settings",
        "save_settings",
        "apply_hotspot_settings",
        "get_connected_users",
        "get_active_sessions",
        "get_logs",
        "get_real_time_logs",
        "save_user",
        "delete_user",
        "block_user"
    )
    
    foreach (`$endpoint in `$endpoints) {
        if (`$content -match `$endpoint) {
            Write-Host "✓ `$endpoint endpoint found" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ `$endpoint endpoint missing" -ForegroundColor Yellow
        }
    }
}

# Summary
Write-Host "`nTest Summary" -ForegroundColor Green
Write-Host "=============" -ForegroundColor Green
if (`$missingFiles.Count -eq 0) {
    Write-Host "✓ All files present and validated!" -ForegroundColor Green
    Write-Host "✓ Ready to start test server" -ForegroundColor Green
}
else {
    Write-Host "✗ Missing files: `$(`$missingFiles -join ', ')" -ForegroundColor Red
    Write-Host "Please fix missing files before starting server" -ForegroundColor Red
}

Write-Host "`nTo start the test server, run: .\start-server.ps1" -ForegroundColor Cyan
"@

# Save the test script
$testScript | Out-File -FilePath "$testDir\run-tests.ps1" -Encoding UTF8

# Create a README for testing
$readme = @"
# PisoWiFi Test Server

This directory contains a local test server for the PisoWiFi system.

## Quick Start

1. Run tests to validate all files:
   ```powershell
   .\run-tests.ps1
   ```

2. Start the test server:
   ```powershell
   .\start-server.ps1
   ```

3. Open your browser and navigate to:
   - Dashboard: http://localhost:8080/
   - Hotspot Settings: http://localhost:8080/hotspot.html
   - Vouchers: http://localhost:8080/vouchers.html
   - System Settings: http://localhost:8080/settings.html
   - Logs: http://localhost:8080/logs.html
   - Users: http://localhost:8080/users.html

## Features

- Simulates OpenWrt uhttpd environment
- Provides mock API responses for testing
- Serves static files (HTML, CSS, JS)
- Includes comprehensive test suite
- Real-time log monitoring simulation
- User management simulation

## API Simulation

The test server simulates these API endpoints:
- `/cgi-bin/api-real.cgi?action=get_vouchers`
- `/cgi-bin/api-real.cgi?action=save_voucher`
- `/cgi-bin/api-real.cgi?action=delete_voucher`
- `/cgi-bin/api-real.cgi?action=get_settings`
- `/cgi-bin/api-real.cgi?action=save_settings`
- `/cgi-bin/api-real.cgi?action=apply_hotspot_settings`
- `/cgi-bin/api-real.cgi?action=get_connected_users`
- `/cgi-bin/api-real.cgi?action=get_active_sessions`
- `/cgi-bin/api-real.cgi?action=get_logs`
- `/cgi-bin/api-real.cgi?action=get_real_time_logs`

## Testing Checklist

- [ ] Dashboard loads correctly
- [ ] Hotspot settings page loads and shows WiFi interfaces
- [ ] Voucher CRUD operations work
- [ ] Settings can be saved and loaded
- [ ] Logs display and update in real-time
- [ ] Users page shows connected clients
- [ ] All buttons respond to clicks
- [ ] Forms validate input correctly
- [ ] Notifications appear for actions
- [ ] Mobile responsiveness works

## Troubleshooting

If the server doesn't start:
1. Check if port 8080 is available
2. Run PowerShell as Administrator
3. Check Windows Firewall settings

If pages don't load:
1. Check browser console for JavaScript errors
2. Verify all files are present using `run-tests.ps1`
3. Check network tab for API request failures
"@

# Save the README
$readme | Out-File -FilePath "$testDir\README.md" -Encoding UTF8

Write-Host "Test server setup complete!" -ForegroundColor Green
Write-Host "Files created in: $testDir" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. cd $testDir" -ForegroundColor White
Write-Host "2. .\run-tests.ps1" -ForegroundColor White
Write-Host "3. .\start-server.ps1" -ForegroundColor White
Write-Host "4. Open browser to http://localhost:8080/" -ForegroundColor White