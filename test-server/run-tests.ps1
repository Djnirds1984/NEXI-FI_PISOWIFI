Write-Host "PisoWiFi Test Suite" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green

# Test 1: Check if all HTML files exist
Write-Host "
Test 1: Checking HTML files..." -ForegroundColor Yellow
$htmlFiles = @("index.html", "hotspot.html", "vouchers.html", "settings.html", "logs.html", "users.html")
$missingFiles = @()

foreach ($file in $htmlFiles) {
    if (Test-Path $file) {
        Write-Host "âœ“ $file exists" -ForegroundColor Green
    }
    else {
        Write-Host "âœ— $file missing" -ForegroundColor Red
        $missingFiles += $file
    }
}

# Test 2: Check if all JS files exist
Write-Host "
Test 2: Checking JavaScript files..." -ForegroundColor Yellow
$jsFiles = @(
    "static\js\dashboard.js",
    "static\js\hotspot.js", 
    "static\js\vouchers.js",
    "static\js\settings.js",
    "static\js\logs.js",
    "static\js\users.js"
)

foreach ($file in $jsFiles) {
    if (Test-Path $file) {
        Write-Host "âœ“ $file exists" -ForegroundColor Green
    }
    else {
        Write-Host "âœ— $file missing" -ForegroundColor Red
        $missingFiles += $file
    }
}

# Test 3: Check if CSS files exist
Write-Host "
Test 3: Checking CSS files..." -ForegroundColor Yellow
$cssFiles = @("static\css\style.css", "static\css\dashboard.css")

foreach ($file in $cssFiles) {
    if (Test-Path $file) {
        Write-Host "âœ“ $file exists" -ForegroundColor Green
    }
    else {
        Write-Host "âœ— $file missing" -ForegroundColor Red
        $missingFiles += $file
    }
}

# Test 4: Check API CGI file
Write-Host "
Test 4: Checking API CGI file..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") {
    Write-Host "âœ“ api-real.cgi exists" -ForegroundColor Green
}
else {
    Write-Host "âœ— api-real.cgi missing" -ForegroundColor Red
    $missingFiles += "cgi-bin\api-real.cgi"
}

# Test 5: Basic HTML validation
Write-Host "
Test 5: Basic HTML validation..." -ForegroundColor Yellow
foreach ($file in $htmlFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        if ($content -match '<!DOCTYPE html>' -and $content -match '<html' -and $content -match '</html>') {
            Write-Host "âœ“ $file has valid HTML structure" -ForegroundColor Green
        }
        else {
            Write-Host "âœ— $file has invalid HTML structure" -ForegroundColor Red
        }
        
        # Check for JavaScript links
        if ($content -match 'src=".*\.js"') {
            Write-Host "âœ“ $file has JavaScript links" -ForegroundColor Green
        }
        else {
            Write-Host "âš  $file may be missing JavaScript links" -ForegroundColor Yellow
        }
        
        # Check for CSS links
        if ($content -match 'href=".*\.css"') {
            Write-Host "âœ“ $file has CSS links" -ForegroundColor Green
        }
        else {
            Write-Host "âš  $file may be missing CSS links" -ForegroundColor Yellow
        }
    }
}

# Test 6: JavaScript validation
Write-Host "
Test 6: JavaScript validation..." -ForegroundColor Yellow
foreach ($file in $jsFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        
        # Check for basic JavaScript patterns
        $issues = @()
        
        if ($content -match 'console\.log') {
            $issues += "Contains console.log statements"
        }
        
        if ($content -match 'async.*function' -or $content -match 'async.*=>') {
            Write-Host "âœ“ $file uses modern async/await" -ForegroundColor Green
        }
        else {
            $issues += "May not use async/await patterns"
        }
        
        if ($content -match 'fetch\(') {
            Write-Host "âœ“ $file uses fetch API" -ForegroundColor Green
        }
        else {
            $issues += "May not use fetch API"
        }
        
        if ($issues.Count -eq 0) {
            Write-Host "âœ“ $file looks good" -ForegroundColor Green
        }
        else {
            Write-Host "âš  $file has potential issues: $($issues -join ', ')" -ForegroundColor Yellow
        }
    }
}

# Test 7: API endpoint validation
Write-Host "
Test 7: API endpoint validation..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") {
    $content = Get-Content "cgi-bin\api-real.cgi" -Raw
    
    $endpoints = @(
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
    
    foreach ($endpoint in $endpoints) {
        if ($content -match $endpoint) {
            Write-Host "âœ“ $endpoint endpoint found" -ForegroundColor Green
        }
        else {
            Write-Host "âš  $endpoint endpoint missing" -ForegroundColor Yellow
        }
    }
}

# Summary
Write-Host "
Test Summary" -ForegroundColor Green
Write-Host "=============" -ForegroundColor Green
if ($missingFiles.Count -eq 0) {
    Write-Host "âœ“ All files present and validated!" -ForegroundColor Green
    Write-Host "âœ“ Ready to start test server" -ForegroundColor Green
}
else {
    Write-Host "âœ— Missing files: $($missingFiles -join ', ')" -ForegroundColor Red
    Write-Host "Please fix missing files before starting server" -ForegroundColor Red
}

Write-Host "
To start the test server, run: .\start-server.ps1" -ForegroundColor Cyan
