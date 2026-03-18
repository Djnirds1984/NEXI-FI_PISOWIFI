@echo off
REM PisoWiFi Device Loader Deployment Script for Windows
REM Deploys the lightweight loader to Vercel for global access

setlocal enabledelayedexpansion

REM Colors (using ANSI escape codes where supported)
set "GREEN=[92m"
set "YELLOW=[93m"
set "RED=[91m"
set "NC=[0m"

REM Configuration
set "LOADER_NAME=pisowifi-device-loader"
set "SUPABASE_URL=https://fuiabtdflbodglfexvln.supabase.co"
set "SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo"

echo [INFO] Starting PisoWiFi Device Loader deployment...

REM Check if Node.js is installed
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js is not installed. Please install Node.js first.
    echo Download from: https://nodejs.org/
    pause
    exit /b 1
)

REM Check if Vercel CLI is installed
vercel --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Vercel CLI not found. Installing...
    call npm install -g vercel
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to install Vercel CLI
        pause
        exit /b 1
    )
)

REM Check if user is logged in to Vercel
vercel whoami >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Please login to Vercel first:
    call vercel login
    if %errorlevel% neq 0 (
        echo [ERROR] Vercel login failed
        pause
        exit /b 1
    )
)

REM Create Vercel configuration
echo [INFO] Creating Vercel configuration...
(
echo {
echo   "version": 2,
echo   "name": "%LOADER_NAME%",
echo   "description": "Ultra-lightweight device loader for PisoWiFi OpenWrt devices",
echo   "functions": {},
echo   "routes": [
echo     {
echo       "src": "/(.*)",
echo       "dest": "/$1",
echo       "headers": {
echo         "Access-Control-Allow-Origin": "*",
echo         "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
echo         "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
echo         "Cache-Control": "public, max-age=300",
echo         "Content-Type": "application/javascript; charset=utf-8"
echo       }
echo     }
echo   ],
echo   "headers": [
echo     {
echo       "source": "/pisowifi-loader.js",
echo       "headers": [
echo         {
echo           "key": "Content-Type",
echo           "value": "application/javascript; charset=utf-8"
echo         },
echo         {
echo           "key": "Cache-Control",
echo           "value": "public, max-age=300"
echo         },
echo         {
echo           "key": "Access-Control-Allow-Origin",
echo           "value": "*"
echo         }
echo       ]
echo     }
echo   ],
echo   "builds": [
echo     {
echo       "src": "pisowifi-loader.js",
echo       "use": "@vercel/static"
echo     }
echo   ]
echo }
) > vercel.json

REM Create package.json for Vercel
echo [INFO] Creating package.json for Vercel...
(
echo {
echo   "name": "%LOADER_NAME%",
echo   "version": "1.0.0",
echo   "description": "Ultra-lightweight device loader for PisoWiFi OpenWrt devices",
echo   "main": "pisowifi-loader.js",
echo   "scripts": {
echo     "deploy": "vercel --prod",
echo     "dev": "vercel dev"
echo   },
echo   "keywords": ["pisowifi", "openwrt", "device-loader", "supabase"],
echo   "author": "PisoWiFi System",
echo   "license": "MIT"
echo }
) > package.json

REM Create deployment info
echo [INFO] Creating deployment information...
(
echo # PisoWiFi Device Loader Deployment
echo.
echo ## Deployment URL
echo After deployment, your device loader will be available at:
echo \`https://%LOADER_NAME%.vercel.app/pisowifi-loader.js\`
echo.
echo ## Usage in OpenWrt Devices
echo Replace the loader URL in your installation script with the deployed URL:
echo.
echo \`\`\`bash
echo LOADER_URL="https://%LOADER_NAME%.vercel.app/pisowifi-loader.js"
echo \`\`\`
echo.
echo ## Features
echo - Ultra-lightweight (2KB)
echo - Direct Supabase integration
echo - Automatic device authentication
echo - Real-time heartbeat monitoring
echo - Session management
echo - Coin tracking
echo - Dynamic configuration updates
echo.
echo ## Configuration
echo - **Supabase URL**: %SUPABASE_URL%
echo - **Global CDN**: Enabled via Vercel
echo - **Caching**: 5-minute cache for optimal performance
echo - **CORS**: Enabled for cross-origin requests
echo.
echo ## Security Notes
echo - Uses Supabase anon key (safe for frontend)
echo - Implements retry logic for reliability
echo - Minimal resource usage for OpenWrt
echo - Runs entirely in RAM (/tmp)
) > DEPLOYMENT_INFO.md

REM Deploy to Vercel
echo [INFO] Deploying to Vercel...
call vercel --prod --yes

if %errorlevel% equ 0 (
    echo [SUCCESS] Deployment successful!
    
    REM Get deployment URL (simplified for Windows)
    echo [INFO] Device loader will be available at:
    echo [INFO] https://%LOADER_NAME%.vercel.app/pisowifi-loader.js
    
    REM Update installation script with new URL
    powershell -Command "(Get-Content ..\install-loader.sh) -replace 'LOADER_URL=\".*\"', 'LOADER_URL=\"https://%LOADER_NAME%.vercel.app/pisowifi-loader.js\"' | Set-Content ..\install-loader.sh"
    echo [INFO] Installation script updated with new URL
    
) else (
    echo [ERROR] Deployment failed
    pause
    exit /b 1
)

REM Create deployment summary
echo [INFO] Creating deployment summary...
(
echo # Deployment Summary
echo.
echo ## Files Deployed
echo - \`pisowifi-loader.js\` - Main device loader (2KB)
echo - \`vercel.json\` - Vercel configuration
echo - \`package.json\` - Package configuration
echo.
echo ## Configuration
echo - **Supabase URL**: %SUPABASE_URL%
echo - **Global CDN**: Enabled via Vercel
echo - **Caching**: 5-minute cache for optimal performance
echo - **CORS**: Enabled for cross-origin requests
echo.
echo ## Next Steps
echo 1. Test the deployment URL in your OpenWrt devices
echo 2. Update your installation scripts with the new URL
echo 3. Monitor device connections in your Supabase dashboard
echo 4. Scale to multiple devices using the same loader
echo.
echo ## Monitoring
echo Check device logs at: \`/tmp/pisowifi-cloud.log\` on each device
) > DEPLOYMENT_SUMMARY.md

echo [SUCCESS] Deployment complete!
echo [INFO] Check DEPLOYMENT_INFO.md and DEPLOYMENT_SUMMARY.md for details
echo.
echo [INFO] Your device loader is now live at:
echo [INFO] https://%LOADER_NAME%.vercel.app/pisowifi-loader.js
echo.
echo [INFO] Use this URL in your OpenWrt installation script
echo.
pause