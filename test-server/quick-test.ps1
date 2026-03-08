Write-Host "PisoWiFi Test Suite" -ForegroundColor Green

# Check HTML files
Write-Host "`nChecking HTML files..." -ForegroundColor Yellow
$files = @("index.html", "hotspot.html", "vouchers.html", "settings.html", "logs.html", "users.html")
foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "✓ $file exists" -ForegroundColor Green
    } else {
        Write-Host "✗ $file missing" -ForegroundColor Red
    }
}

# Check JS files  
Write-Host "`nChecking JavaScript files..." -ForegroundColor Yellow
$jsFiles = @("static\js\dashboard.js", "static\js\hotspot.js", "static\js\vouchers.js", "static\js\settings.js", "static\js\logs.js", "static\js\users.js")
foreach ($file in $jsFiles) {
    if (Test-Path $file) {
        Write-Host "✓ $file exists" -ForegroundColor Green
    } else {
        Write-Host "✗ $file missing" -ForegroundColor Red
    }
}

# Check CSS files
Write-Host "`nChecking CSS files..." -ForegroundColor Yellow
$cssFiles = @("static\css\style.css", "static\css\dashboard.css")
foreach ($file in $cssFiles) {
    if (Test-Path $file) {
        Write-Host "✓ $file exists" -ForegroundColor Green
    } else {
        Write-Host "✗ $file missing" -ForegroundColor Red
    }
}

# Check API file
Write-Host "`nChecking API file..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") {
    Write-Host "✓ api-real.cgi exists" -ForegroundColor Green
} else {
    Write-Host "✗ api-real.cgi missing" -ForegroundColor Red
}

Write-Host "`nTest complete!" -ForegroundColor Green
Write-Host "Run .\start-server.ps1 to start the test server" -ForegroundColor Cyan