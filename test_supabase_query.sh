#!/bin/bash

# Test script to manually query Supabase database
# Usage: bash test_supabase_query.sh <SUPA_URL> <SUPA_KEY> <KEY_TO_TEST>

SUPA_URL="$1"
SUPA_KEY="$2"
TEST_KEY="$3"

if [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ] || [ -z "$TEST_KEY" ]; then
    echo "Usage: bash test_supabase_query.sh <SUPA_URL> <SUPA_KEY> <KEY_TO_TEST>"
    echo "Example: bash test_supabase_query.sh https://xyz.supabase.co your-key-here CENTRAL-377ed7bc-94f058b9"
    exit 1
fi

echo "=== SUPABASE DATABASE QUERY TEST ==="
echo "URL: $SUPA_URL"
echo "Testing key: $TEST_KEY"
echo ""

# Function to make Supabase request (simplified version)
supa_request_test() {
    local url="$1"
    local key="$2"
    local query="$3"
    
    echo "Making request to: ${url}/rest/v1/${query}"
    echo "Headers: apikey: [HIDDEN], Authorization: Bearer [HIDDEN]"
    
    # Use curl to test the query
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "apikey: $key" \
        -H "Authorization: Bearer $key" \
        -H "Content-Type: application/json" \
        "${url}/rest/v1/${query}")
    
    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    body=$(echo "$response" | grep -v "HTTP_CODE:")
    
    echo "HTTP Code: $http_code"
    echo "Response Body: $body"
    echo "---"
    
    return $http_code
}

echo "1. Testing centralized_keys table with exact key:"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id,vendor_id,is_active&key_value=eq.$TEST_KEY"

echo ""
echo "2. Testing centralized_keys table with ilike (case-insensitive):"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id,vendor_id,is_active&key_value=ilike.$TEST_KEY"

echo ""
echo "3. Testing pisowifi_openwrt table with exact key:"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id,status,vendor_uuid&license_key=eq.$TEST_KEY"

echo ""
echo "4. Testing pisowifi_openwrt table with ilike (case-insensitive):"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id,status,vendor_uuid&license_key=ilike.$TEST_KEY"

echo ""
echo "5. Getting all records from centralized_keys (limit 5):"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id,key_value,vendor_id,is_active&limit=5"

echo ""
echo "6. Getting all records from pisowifi_openwrt (limit 5):"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id,license_key,status,vendor_uuid&limit=5"

echo ""
echo "7. Testing with different column names - maybe the key is stored differently:"
echo "   Testing 'key' column instead of 'key_value':"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "centralized_keys?select=id,key,vendor_id,is_active&key=ilike.$TEST_KEY"

echo ""
echo "   Testing 'license' column instead of 'license_key':"
supa_request_test "$SUPA_URL" "$SUPA_KEY" "pisowifi_openwrt?select=id,license,status,vendor_uuid&license=ilike.$TEST_KEY"