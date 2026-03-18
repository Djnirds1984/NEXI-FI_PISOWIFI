#!/bin/bash
# PisoWiFi Device Loader Deployment Script
# Deploys the lightweight loader to Vercel for global access

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Vercel CLI is installed
check_vercel() {
    if ! command -v vercel &> /dev/null; then
        log_error "Vercel CLI is not installed. Installing..."
        npm install -g vercel
    fi
    
    # Check if user is logged in
    if ! vercel whoami &> /dev/null; then
        log_info "Please login to Vercel first:"
        vercel login
    fi
}

# Create Vercel configuration
create_vercel_config() {
    log_info "Creating Vercel configuration..."
    
    cat > vercel.json << 'EOF'
{
  "version": 2,
  "name": "pisowifi-device-loader",
  "description": "Ultra-lightweight device loader for PisoWiFi OpenWrt devices",
  "functions": {},
  "routes": [
    {
      "src": "/(.*)",
      "dest": "/$1",
      "headers": {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
        "Cache-Control": "public, max-age=300",
        "Content-Type": "application/javascript; charset=utf-8"
      }
    }
  ],
  "headers": [
    {
      "source": "/pisowifi-loader.js",
      "headers": [
        {
          "key": "Content-Type",
          "value": "application/javascript; charset=utf-8"
        },
        {
          "key": "Cache-Control",
          "value": "public, max-age=300"
        },
        {
          "key": "Access-Control-Allow-Origin",
          "value": "*"
        }
      ]
    }
  ],
  "builds": [
    {
      "src": "pisowifi-loader.js",
      "use": "@vercel/static"
    }
  ]
}
EOF
}

# Create package.json for Vercel
create_package_json() {
    log_info "Creating package.json for Vercel..."
    
    cat > package.json << 'EOF'
{
  "name": "pisowifi-device-loader",
  "version": "1.0.0",
  "description": "Ultra-lightweight device loader for PisoWiFi OpenWrt devices",
  "main": "pisowifi-loader.js",
  "scripts": {
    "deploy": "vercel --prod",
    "dev": "vercel dev"
  },
  "keywords": ["pisowifi", "openwrt", "device-loader", "supabase"],
  "author": "PisoWiFi System",
  "license": "MIT"
}
EOF
}

# Create deployment info
create_deployment_info() {
    log_info "Creating deployment information..."
    
    cat > DEPLOYMENT_INFO.md << 'EOF'
# PisoWiFi Device Loader Deployment

## Deployment URL
After deployment, your device loader will be available at:
`https://pisowifi-device-loader.vercel.app/pisowifi-loader.js`

## Usage in OpenWrt Devices
Replace the loader URL in your installation script with the deployed URL:

```bash
LOADER_URL="https://pisowifi-device-loader.vercel.app/pisowifi-loader.js"
```

## Features
- Ultra-lightweight (2KB)
- Direct Supabase integration
- Automatic device authentication
- Real-time heartbeat monitoring
- Session management
- Coin tracking
- Dynamic configuration updates

## Security Notes
- Uses Supabase anon key (safe for frontend)
- Implements retry logic for reliability
- Minimal resource usage for OpenWrt
- Runs entirely in RAM (/tmp)
EOF
}

# Deploy to Vercel
deploy_to_vercel() {
    log_info "Deploying to Vercel..."
    
    # Deploy with production flag
    if vercel --prod --yes; then
        log_info "Deployment successful!"
        
        # Get deployment URL
        local deployment_url=$(vercel ls pisowifi-device-loader --json | jq -r '.[0].url' 2>/dev/null || echo "pisowifi-device-loader.vercel.app")
        
        log_info "Device loader will be available at:"
        log_info "https://${deployment_url}/pisowifi-loader.js"
        
        # Update installation script with new URL
        sed -i "s|LOADER_URL=\".*\"|LOADER_URL=\"https://${deployment_url}/pisowifi-loader.js\"|g" ../install-loader.sh
        log_info "Installation script updated with new URL"
        
    else
        log_error "Deployment failed"
        exit 1
    fi
}

# Create deployment summary
create_deployment_summary() {
    log_info "Creating deployment summary..."
    
    cat > DEPLOYMENT_SUMMARY.md << EOF
# Deployment Summary

## Files Deployed
- \`pisowifi-loader.js\` - Main device loader (2KB)
- \`vercel.json\` - Vercel configuration
- \`package.json\` - Package configuration

## Configuration
- **Supabase URL**: https://fuiabtdflbodglfexvln.supabase.co
- **Global CDN**: Enabled via Vercel
- **Caching**: 5-minute cache for optimal performance
- **CORS**: Enabled for cross-origin requests

## Next Steps
1. Test the deployment URL in your OpenWrt devices
2. Update your installation scripts with the new URL
3. Monitor device connections in your Supabase dashboard
4. Scale to multiple devices using the same loader

## Monitoring
Check device logs at: \`/tmp/pisowifi-cloud.log\` on each device
EOF
}

# Main deployment function
main() {
    log_info "Starting PisoWiFi Device Loader deployment..."
    
    check_vercel
    create_vercel_config
    create_package_json
    create_deployment_info
    deploy_to_vercel
    create_deployment_summary
    
    log_info "Deployment complete!"
    log_info "Check DEPLOYMENT_INFO.md and DEPLOYMENT_SUMMARY.md for details"
    
    # Show deployment URL
    echo
    log_info "Your device loader is now live at:"
    log_info "https://pisowifi-device-loader.vercel.app/pisowifi-loader.js"
    echo
    log_info "Use this URL in your OpenWrt installation script"
}

# Run main function
main "$@"