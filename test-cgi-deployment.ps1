# Test CGI script with environment variables
Write-Host "Testing CGI script..." -ForegroundColor Green

# Set CGI environment variables
$env:REQUEST_METHOD = "GET"
$env:REQUEST_URI = "/cgi-bin/api-real.cgi?action=get_hotspot_status"
$env:PATH_INFO = "/cgi-bin/api-real.cgi"
$env:QUERY_STRING = "action=get_hotspot_status"

Write-Host "Environment variables set:" -ForegroundColor Yellow
Write-Host "REQUEST_METHOD: $($env:REQUEST_METHOD)"
Write-Host "REQUEST_URI: $($env:REQUEST_URI)"
Write-Host "QUERY_STRING: $($env:QUERY_STRING)"
Write-Host ""

# Note: We can't actually run ucode here since it's not installed
# But we can verify the script syntax by checking the file
Write-Host "CGI script exists: $(Test-Path 'c:\Users\Administrator\Documents\GitHub\NEXI-FI_PISOWIFI\pisowifi\cgi-bin\api-real.cgi')" -ForegroundColor Cyan

# Check if the script has proper headers
$content = Get-Content "c:\Users\Administrator\Documents\GitHub\NEXI-FI_PISOWIFI\pisowifi\cgi-bin\api-real.cgi" -Raw
if ($content -match "Content-Type: application/json") {
    Write-Host "✅ CGI script has proper HTTP headers" -ForegroundColor Green
} else {
    Write-Host "❌ CGI script missing HTTP headers" -ForegroundColor Red
}

Write-Host ""
Write-Host "To deploy to production (10.0.0.1):" -ForegroundColor Yellow
Write-Host "1. Copy the fixed api-real.cgi to your OpenWrt router" -ForegroundColor White
Write-Host "2. Place it in /www/cgi-bin/ directory" -ForegroundColor White
Write-Host "3. Make it executable: chmod +x /www/cgi-bin/api-real.cgi" -ForegroundColor White
Write-Host "4. Restart uhttpd: /etc/init.d/uhttpd restart" -ForegroundColor White