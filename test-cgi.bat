@echo off
echo Testing CGI script...
echo.

set REQUEST_METHOD=GET
set REQUEST_URI=/cgi-bin/api-real.cgi?action=get_hotspot_status
set PATH_INFO=/cgi-bin/api-real.cgi
set QUERY_STRING=action=get_hotspot_status

echo Running CGI script with environment variables...
ucode c:\Users\Administrator\Documents\GitHub\NEXI-FI_PISOWIFI\pisowifi\cgi-bin\api-real.cgi

echo.
echo Done testing.
pause