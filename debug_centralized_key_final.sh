#!/bin/bash

# Final debug script for centralized key activation
# This script will identify the exact issue and provide the solution

SUPA_URL="$1"
SUPA_KEY="$2"
TEST_KEY="$3"

if [ -z "$SUPA_URL" ] || [ -z "$SUPA_KEY" ] || [ -z "$TEST_KEY" ]; then
    echo "Usage: bash debug_centralized_key_final.sh <SUPA_URL> <SUPA_KEY> <KEY_TO_TEST>"
    echo "Example: bash debug_centralized_key_final.sh https://xyz.supabase.co your-key-here CENTRAL-377ed7bc-94f058b9"
    exit 1
fi

echo "=== CENTRALIZED KEY DEBUG & SOLUTION ==="
echo "URL: $SUPA_URL"
echo "Testing key: $TEST_KEY"
echo ""

# Function to test Supabase query
test_query() {
    local query="$1"
    local description="$2"
    
    echo "Testing: $description"
    echo "Query: $query"
    
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -H "apikey: $SUPA_KEY" \
        -H "Authorization: Bearer $SUPA_KEY" \
        -H "Content-Type: application/json" \
        "${SUPA_URL}/rest/v1/${query}")
    
    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    body=$(echo "$response" | grep -v "HTTP_CODE:")
    
    echo "HTTP Code: $http_code"
    echo "Response: $body"
    
    if [ "$body" != "[]" ] && [ -n "$body" ] && [ "$body" != "null" ]; then
        echo "✅ FOUND DATA!"
        return 0
    else
        echo "❌ No data found"
        return 1
    fi
    echo "---"
}

echo "1. Testing basic table access:"
echo ""

# Test 1: Check if we can access the table at all
test_query "centralized_keys?select=id&limit=1" "Basic table access"

echo ""
echo "2. Testing exact key match:"
echo ""

# Test 2: Exact key match
test_query "centralized_keys?select=id,key_value,vendor_id,is_active&key_value=eq.$TEST_KEY&limit=1" "Exact key match"

echo ""
echo "3. Testing case-insensitive key match:"
echo ""

# Test 3: Case-insensitive match
test_query "centralized_keys?select=id,key_value,vendor_id,is_active&key_value=ilike.$TEST_KEY&limit=1" "Case-insensitive key match"

echo ""
echo "4. Testing with different column names:"
echo ""

# Test different column names
for col in "key_value" "key" "license_key" "centralized_key" "license"; do
    test_query "centralized_keys?select=id,${col},vendor_id,is_active&${col}=eq.$TEST_KEY&limit=1" "Testing column '$col'"
done

echo ""
echo "5. Testing if key exists with different case variations:"
echo ""

# Test different case variations
case_variations=(
    "CENTRAL-377ed7bc-94f058b9"
    "central-377ed7bc-94f058b9" 
    "Central-377ed7bc-94f058b9"
    "CENTRAL-377ED7BC-94F058B9"
)

for variant in "${case_variations[@]}"; do
    test_query "centralized_keys?select=id,key_value,vendor_id,is_active&key_value=eq.$variant&limit=1" "Case variant: $variant"
done

echo ""
echo "6. Getting all records to see what's actually in the database:"
echo ""

# Get sample records
test_query "centralized_keys?select=id,key_value,vendor_id,is_active&limit=10" "Sample records from database"

echo ""
echo "7. Testing permissions issue - check if RLS is blocking access:"
echo ""

# Test with service role key (if available)
if [ -n "$SUPA_SERVICE_KEY" ]; then
    echo "Testing with service role key:"
    response=$(curl -s \
        -H "apikey: $SUPA_SERVICE_KEY" \
        -H "Authorization: Bearer $SUPA_SERVICE_KEY" \
        -H "Content-Type: application/json" \
        "${SUPA_URL}/rest/v1/centralized_keys?select=id,key_value,vendor_id,is_active&key_value=eq.$TEST_KEY&limit=1")
    
    echo "Service role response: $response"
    
    if [ "$response" != "[]" ] && [ -n "$response" ]; then
        echo "✅ KEY FOUND WITH SERVICE ROLE! This confirms RLS/permissions issue"
        echo ""
        echo "🎯 SOLUTION: You need to add RLS policy or grant permissions"
        echo "Run this SQL in your Supabase dashboard:"
        echo ""
        echo "-- Option 1: Add RLS policy for anonymous users"
        echo "CREATE POLICY \"Allow anonymous read access\" ON public.centralized_keys"
        echo "FOR SELECT USING (true);"
        echo ""
        echo "-- Option 2: Grant direct permissions"
        echo "GRANT SELECT ON public.centralized_keys TO anon;"
        echo "GRANT SELECT ON public.centralized_keys TO authenticated;"
    else
        echo "❌ Key not found even with service role - key doesn't exist in database"
    fi
else
    echo "No service role key provided. To test permissions, set SUPA_SERVICE_KEY environment variable"
fi

echo ""
echo "=== SUMMARY ==="
echo ""
echo "Based on the tests above:"
echo "1. If you found data in step 1 but not in steps 2-5: KEY DOESN'T EXIST IN DATABASE"
echo "2. If you found data with service role but not anon: PERMISSIONS/RLS ISSUE"
echo "3. If you found data with case variations: CASE SENSITIVITY ISSUE"
echo "4. If you found no data anywhere: KEY IS NOT IN THE DATABASE"