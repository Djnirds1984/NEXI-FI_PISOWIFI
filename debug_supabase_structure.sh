#!/bin/bash

# Debug script to check Supabase table structure
# Usage: bash debug_supabase_structure.sh <SUPA_URL> <SUPA_KEY>

SUPA_URL="$1"
SUPA_KEY="$2"

if [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ]; then
    echo "Usage: bash debug_supabase_structure.sh <SUPA_URL> <SUPA_KEY>"
    exit 1
fi

echo "=== SUPABASE TABLE STRUCTURE DEBUG ==="
echo "URL: $SUPA_URL"
echo ""

# Function to get table schema
get_table_schema() {
    local table="$1"
    echo "Schema for table: $table"
    
    # Query information_schema to get column info
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "apikey: $SUPA_KEY" \
        -H "Authorization: Bearer $SUPA_KEY" \
        -H "Content-Type: application/json" \
        "${SUPA_URL}/rest/v1/${table}?select=*&limit=0")
    
    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo "✓ Table $table exists"
        
        # Try to get a sample record to see actual column names
        sample_response=$(curl -s \
            -H "apikey: $SUPA_KEY" \
            -H "Authorization: Bearer $SUPA_KEY" \
            -H "Content-Type: application/json" \
            "${SUPA_URL}/rest/v1/${table}?select=*&limit=1")
        
        if [ -n "$sample_response" ] && [ "$sample_response" != "[]" ]; then
            echo "Sample record structure:"
            echo "$sample_response" | jq .[0] 2>/dev/null || echo "$sample_response"
        else
            echo "No records found in $table"
        fi
    else
        echo "✗ Table $table not found or error: HTTP $http_code"
    fi
    echo "---"
}

# Check both tables
echo "1. Checking centralized_keys table:"
get_table_schema "centralized_keys"

echo ""
echo "2. Checking pisowifi_openwrt table:"
get_table_schema "pisowifi_openwrt"

echo ""
echo "3. Checking if there are other tables that might contain the key:"

# Try to list all tables by querying a system table (if accessible)
system_response=$(curl -s \
    -H "apikey: $SUPA_KEY" \
    -H "Authorization: Bearer $SUPA_KEY" \
    -H "Content-Type: application/json" \
    "${SUPA_URL}/rest/v1/information_schema.tables?select=table_name&table_schema=eq.public")

if [ -n "$system_response" ] && [ "$system_response" != "[]" ]; then
    echo "Available tables:"
    echo "$system_response" | jq -r .[].table_name 2>/dev/null | while read table; do
        echo "  - $table"
    done
else
    echo "Could not list tables (may not have access to information_schema)"
fi

echo ""
echo "=== MANUAL QUERY TESTS ==="
echo "Let's test different column names for your key:"

# Test different possible column names for the centralized_keys table
echo ""
echo "Testing centralized_keys with different column names:"

for col in "key_value" "key" "license_key" "centralized_key" "license"; do
    echo "Testing column '$col':"
    response=$(curl -s \
        -H "apikey: $SUPA_KEY" \
        -H "Authorization: Bearer $SUPA_KEY" \
        -H "Content-Type: application/json" \
        "${SUPA_URL}/rest/v1/centralized_keys?select=id,${col},vendor_id,is_active&${col}=eq.CENTRAL-377ed7bc-94f058b9&limit=1")
    
    if [ "$response" != "[]" ] && [ -n "$response" ]; then
        echo "  ✓ FOUND RECORD: $response"
    else
        echo "  ✗ No records found"
    fi
done

echo ""
echo "Testing pisowifi_openwrt with different column names:"

for col in "license_key" "key" "license" "centralized_key"; do
    echo "Testing column '$col':"
    response=$(curl -s \
        -H "apikey: $SUPA_KEY" \
        -H "Authorization: Bearer $SUPA_KEY" \
        -H "Content-Type: application/json" \
        "${SUPA_URL}/rest/v1/pisowifi_openwrt?select=id,${col},status,vendor_uuid&${col}=eq.CENTRAL-377ed7bc-94f058b9&limit=1")
    
    if [ "$response" != "[]" ] && [ -n "$response" ]; then
        echo "  ✓ FOUND RECORD: $response"
    else
        echo "  ✗ No records found"
    fi
done