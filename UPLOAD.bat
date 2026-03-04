@echo off
setlocal

:: --- CONFIGURATION ---
set ROUTER_IP=192.168.1.1
set ROUTER_USER=root
set REMOTE_WWW=/www/
set REMOTE_CGI=/www/cgi-bin/

echo [1/3] Uploading Frontend (index.html)...
scp index.html %ROUTER_USER%@%ROUTER_IP%:%REMOTE_WWW%

echo [2/3] Uploading API Scripts (cgi-bin folder)...
:: Ito ay mag-u-upload ng lahat ng files sa iyong local 'cgi-bin' folder
scp cgi-bin/* %ROUTER_USER%@%ROUTER_IP%:%REMOTE_CGI%

echo [3/3] Setting Permissions for CGI Scripts...
:: Kailangan ito para maging "executable" ang mga scripts sa router
ssh %ROUTER_USER%@%ROUTER_IP% "chmod +x %REMOTE_CGI%*"

echo.
echo ==========================================
echo DONE! Refresh your browser (192.168.1.1)
echo ==========================================
pause