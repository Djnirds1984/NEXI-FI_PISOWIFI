@echo off
echo Testing CGI configuration...
echo.
echo Creating test CGI script...
echo #!/usr/bin/ucode > test.cgi
echo print("Content-Type: application/json\n") >> test.cgi
echo print('{"success": true, "message": "CGI is working!"}') >> test.cgi

echo.
echo Test CGI script created: test.cgi
echo Content:
type test.cgi
echo.
echo To test this on OpenWrt:
echo 1. Copy test.cgi to /www/pisowifi/cgi-bin/
echo 2. chmod 755 /www/pisowifi/cgi-bin/test.cgi
echo 3. Access: http://10.0.0.1/cgi-bin/test.cgi
echo.
echo To test api-real.cgi:
echo curl -s "http://10.0.0.1/cgi-bin/api-real.cgi?action=get_hotspot_settings"