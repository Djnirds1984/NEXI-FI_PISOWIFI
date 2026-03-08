# PisoWiFi Simple Test Suite
Write-Host "PisoWiFi Test Suite" -ForegroundColor Green
Write-Host "==================" -ForegroundColor Green

# Test 1: Check if all HTML files exist
Write-Host "`nTest 1: Checking HTML files..." -ForegroundColor Yellow
$htmlFiles = @("index.html", "hotspot.html", "vouchers.html", "settings.html", "logs.html", "users.html")
$missingFiles = @()

foreach ($file in $htmlFiles) {
    if (Test-Path $file) {
        Write-Host "✓ $file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ $file missing" -ForegroundColor Red
        $missingFiles += $file
    }
}

# Test 2: Check if all JS files exist
Write-Host "`nTest 2: Checking JavaScript files..." -ForegroundColor Yellow
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
        Write-Host "✓ $file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ $file missing" -ForegroundColor Red
        $missingFiles += $file
    }
}

# Test 3: Check if CSS files exist
Write-Host "`nTest 3: Checking CSS files..." -ForegroundColor Yellow
$cssFiles = @("static\css\style.css", "static\css\dashboard.css")

foreach ($file in $cssFiles) {
    if (Test-Path $file) {
        Write-Host "✓ $file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ $file missing" -ForegroundColor Red
        $missingFiles += $file
    }
}

# Test 4: Check API CGI file
Write-Host "`nTest 4: Checking API CGI file..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") {
    Write-Host "✓ api-real.cgi exists" -ForegroundColor Green
}
else {
    Write-Host "✗ api-real.cgi missing" -ForegroundColor Red
    $missingFiles += "cgi-bin\api-real.cgi"
}

# Summary
Write-Host "`nTest Summary" -ForegroundColor Green
Write-Host "=============" -ForegroundColor Green
if ($missingFiles.Count -eq 0) {
    Write-Host "✓ All files present!" -ForegroundColor Green
    Write-Host "✓ Ready to start test server" -ForegroundColor Green
}
else {
    Write-Host "✗ Missing files: $($missingFiles -join ', ')" -ForegroundColor Red
}

Write-Host "`nTo start the test server, run: .\start-server.ps1" -ForegroundColor Cyan