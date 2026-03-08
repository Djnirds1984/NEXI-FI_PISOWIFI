Write-Host "Testing PisoWiFi files..." -ForegroundColor Green

# Test HTML files
$testPath = "index.html"
if (Test-Path $testPath) { Write-Host "✓ index.html exists" -ForegroundColor Green } else { Write-Host "✗ index.html missing" -ForegroundColor Red }

$testPath = "hotspot.html"  
if (Test-Path $testPath) { Write-Host "✓ hotspot.html exists" -ForegroundColor Green } else { Write-Host "✗ hotspot.html missing" -ForegroundColor Red }

$testPath = "vouchers.html"
if (Test-Path $testPath) { Write-Host "✓ vouchers.html exists" -ForegroundColor Green } else { Write-Host "✗ vouchers.html missing" -ForegroundColor Red }

$testPath = "settings.html"
if (Test-Path $testPath) { Write-Host "✓ settings.html exists" -ForegroundColor Green } else { Write-Host "✗ settings.html missing" -ForegroundColor Red }

$testPath = "logs.html"
if (Test-Path $testPath) { Write-Host "✓ logs.html exists" -ForegroundColor Green } else { Write-Host "✗ logs.html missing" -ForegroundColor Red }

$testPath = "users.html"
if (Test-Path $testPath) { Write-Host "✓ users.html exists" -ForegroundColor Green } else { Write-Host "✗ users.html missing" -ForegroundColor Red }

# Test JavaScript files
Write-Host "`nTesting JavaScript files..." -ForegroundColor Yellow
$jsFiles = @("dashboard.js", "hotspot.js", "vouchers.js", "settings.js", "logs.js", "users.js")
foreach ($jsFile in $jsFiles) {
    $testPath = "static\js\$jsFile"
    if (Test-Path $testPath) { 
        Write-Host "✓ $jsFile exists" -ForegroundColor Green 
    } else { 
        Write-Host "✗ $jsFile missing" -ForegroundColor Red 
    }
}

# Test CSS files  
Write-Host "`nTesting CSS files..." -ForegroundColor Yellow
if (Test-Path "static\css\style.css") { Write-Host "✓ style.css exists" -ForegroundColor Green } else { Write-Host "✗ style.css missing" -ForegroundColor Red }
if (Test-Path "static\css\dashboard.css") { Write-Host "✓ dashboard.css exists" -ForegroundColor Green } else { Write-Host "✗ dashboard.css missing" -ForegroundColor Red }

# Test API file
Write-Host "`nTesting API file..." -ForegroundColor Yellow
if (Test-Path "cgi-bin\api-real.cgi") { Write-Host "✓ api-real.cgi exists" -ForegroundColor Green } else { Write-Host "✗ api-real.cgi missing" -ForegroundColor Red }

Write-Host "`nTest complete!" -ForegroundColor Green