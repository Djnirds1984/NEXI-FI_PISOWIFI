# Simple HTTP Server for PisoWiFi Testing
# This simulates the OpenWrt uhttpd environment

$port = 8080
$rootDir = "."

Write-Host "Starting PisoWiFi test server on port $port..." -ForegroundColor Green
Write-Host "Access the dashboard at: http://localhost:$port/" -ForegroundColor Yellow
Write-Host "Access hotspot settings at: http://localhost:$port/hotspot.html" -ForegroundColor Yellow
Write-Host "Access vouchers at: http://localhost:$port/vouchers.html" -ForegroundColor Yellow
Write-Host "Access settings at: http://localhost:$port/settings.html" -ForegroundColor Yellow
Write-Host "Access logs at: http://localhost:$port/logs.html" -ForegroundColor Yellow
Write-Host "Access users at: http://localhost:$port/users.html" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Red

# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")
$listener.Start()

function Send-Response {
    param($context, $content, $contentType = "text/html", $statusCode = 200)
    
    $response = $context.Response
    $response.StatusCode = $statusCode
    $response.ContentType = $contentType
    
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}

function Get-ContentType {
    param($extension)
    switch ($extension.ToLower()) {
        ".html" { return "text/html" }
        ".css" { return "text/css" }
        ".js" { return "application/javascript" }
        ".json" { return "application/json" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".gif" { return "image/gif" }
        ".ico" { return "image/x-icon" }
        default { return "text/plain" }
    }
}

# Simulate CGI for api-real.cgi
function Handle-ApiRequest {
    param($context, $requestBody)
    
    $responseData = @{
        success = $true
        message = "API simulation - all functions working"
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    }
    
    # Simulate different API endpoints
    if ($context.Request.RawUrl -like "*action=get_vouchers*") {
        $responseData.vouchers = @(
            @{
                id = "TEST001"
                code = "TEST123"
                duration = 60
                price = 10
                status = "active"
                created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }
        )
    }
    elseif ($context.Request.RawUrl -like "*action=get_settings*") {
        $responseData.settings = @{
            hotspot_name = "PisoWiFi-Test"
            hotspot_password = "test12345"
            admin_password = "admin123"
            voucher_expiry = 24
            max_clients = 50
            captive_portal = $true
            redirect_url = "http://10.0.0.1"
        }
    }
    elseif ($context.Request.RawUrl -like "*action=get_connected_users*") {
        $responseData.users = @(
            @{
                ip = "192.168.1.100"
                mac = "00:11:22:33:44:55"
                hostname = "test-client"
                connected_time = "00:15:30"
                status = "online"
            }
        )
    }
    elseif ($context.Request.RawUrl -like "*action=get_logs*") {
        $responseData.logs = @(
            @{
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                level = "info"
                source = "system"
                message = "Test server started successfully"
                category = "system"
            }
        )
    }
    
    $jsonResponse = $responseData | ConvertTo-Json -Depth 10
    Send-Response $context $jsonResponse "application/json"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $url = $request.RawUrl
        
        Write-Host "$(Get-Date): Requested $url" -ForegroundColor Cyan
        
        # Handle CGI requests
        if ($url -like "*/cgi-bin/api-real.cgi*") {
            Handle-ApiRequest $context
            continue
        }
        
        # Handle static files
        $localPath = $url.Substring(1) -replace '\?.*', ''  # Remove query string
        if ([string]::IsNullOrEmpty($localPath)) {
            $localPath = "index.html"
        }
        
        $fullPath = Join-Path $rootDir $localPath
        
        if (Test-Path $fullPath -PathType Leaf) {
            try {
                $content = [System.IO.File]::ReadAllBytes($fullPath)
                $extension = [System.IO.Path]::GetExtension($fullPath)
                $contentType = Get-ContentType $extension
                
                $response = $context.Response
                $response.StatusCode = 200
                $response.ContentType = $contentType
                $response.ContentLength64 = $content.Length
                $response.OutputStream.Write($content, 0, $content.Length)
                $response.OutputStream.Close()
                
                Write-Host "Served: $fullPath" -ForegroundColor Green
            }
            catch {
                Send-Response $context "Error reading file: $($_.Exception.Message)" "text/plain" 500
            }
        }
        else {
            # Try to find index.html in requested directory
            $indexPath = Join-Path $fullPath "index.html"
            if (Test-Path $indexPath -PathType Leaf) {
                try {
                    $content = [System.IO.File]::ReadAllBytes($indexPath)
                    $response = $context.Response
                    $response.StatusCode = 200
                    $response.ContentType = "text/html"
                    $response.ContentLength64 = $content.Length
                    $response.OutputStream.Write($content, 0, $content.Length)
                    $response.OutputStream.Close()
                    
                    Write-Host "Served: $indexPath" -ForegroundColor Green
                }
                catch {
                    Send-Response $context "Error reading file: $($_.Exception.Message)" "text/plain" 500
                }
            }
            else {
                Send-Response $context "404 - File not found: $localPath" "text/plain" 404
                Write-Host "Not found: $fullPath" -ForegroundColor Red
            }
        }
    }
}
catch {
    Write-Host "Server error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    $listener.Stop()
    Write-Host "Server stopped" -ForegroundColor Yellow
}
