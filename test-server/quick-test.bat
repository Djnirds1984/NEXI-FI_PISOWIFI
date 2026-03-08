@echo off
echo PisoWiFi Test Suite
echo ==================
echo.
echo Checking HTML files...
if exist "index.html" echo ✓ index.html exists
if exist "hotspot.html" echo ✓ hotspot.html exists  
if exist "vouchers.html" echo ✓ vouchers.html exists
if exist "settings.html" echo ✓ settings.html exists
if exist "logs.html" echo ✓ logs.html exists
if exist "users.html" echo ✓ users.html exists

echo.
echo Checking JavaScript files...
if exist "static\js\dashboard.js" echo ✓ dashboard.js exists
if exist "static\js\hotspot.js" echo ✓ hotspot.js exists
if exist "static\js\vouchers.js" echo ✓ vouchers.js exists
if exist "static\js\settings.js" echo ✓ settings.js exists
if exist "static\js\logs.js" echo ✓ logs.js exists
if exist "static\js\users.js" echo ✓ users.js exists

echo.
echo Checking CSS files...
if exist "static\css\style.css" echo ✓ style.css exists
if exist "static\css\dashboard.css" echo ✓ dashboard.css exists

echo.
echo Checking API file...
if exist "cgi-bin\api-real.cgi" echo ✓ api-real.cgi exists

echo.
echo Test complete!
echo Run start-server.bat to start the test server
pause