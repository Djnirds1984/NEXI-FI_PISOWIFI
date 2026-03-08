#!/bin/sh
# Test CGI execution on OpenWrt
echo "Content-type: application/json"
echo ""
echo "{\"success\": true, \"message\": \"CGI execution working\", \"timestamp\": \"$(date)\"}"