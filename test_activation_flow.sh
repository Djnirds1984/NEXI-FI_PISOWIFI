#!/bin/bash

# Test the entire activation flow
echo "=== CENTRALIZED KEY ACTIVATION DEBUG TEST ==="
echo ""

# Test key
TEST_KEY="CENTRAL-377ed7bc-94f058b9"
echo "Test key: $TEST_KEY"
echo ""

# 1. Test format validation
echo "1. FORMAT VALIDATION TEST:"
if echo "$TEST_KEY" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
    echo "   ✓ Format validation PASSED"
else
    echo "   ✗ Format validation FAILED"
fi
echo ""

# 2. Test key components
echo "2. KEY COMPONENTS:"
PREFIX=$(echo "$TEST_KEY" | cut -d'-' -f1)
PART1=$(echo "$TEST_KEY" | cut -d'-' -f2)
PART2=$(echo "$TEST_KEY" | cut -d'-' -f3)
echo "   Prefix: $PREFIX"
echo "   Part 1: $PART1 (length: ${#PART1})"
echo "   Part 2: $PART2 (length: ${#PART2})"
echo ""

# 3. Test database query format
echo "3. DATABASE QUERY FORMAT:"
echo "   Primary query: centralized_keys?select=id,vendor_id,is_active&key_value=ilike.$TEST_KEY&limit=1"
echo "   Fallback query: pisowifi_openwrt?select=id,status,vendor_uuid&license_key=ilike.$TEST_KEY&limit=1"
echo ""

# 4. Test case variations
echo "4. CASE SENSITIVITY TEST:"
for variant in "CENTRAL-377ed7bc-94f058b9" "central-377ED7BC-94F058B9" "Central-377Ed7Bc-94F058B9"; do
    echo -n "   Testing $variant: "
    if echo "$variant" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
        echo "✓ MATCHED"
    else
        echo "✗ FAILED"
    fi
done
echo ""

# 5. Test invalid formats
echo "5. INVALID FORMAT TEST (should fail):"
for invalid in "CENTRAL-377ed7bc-94F058B9-EXTRA" "INVALID-377ed7bc-94f058b9" "CENTRAL-377ed7bc" "CENTRAL-377ed7bc-94f058b9-EXTRA"; do
    echo -n "   Testing $invalid: "
    if echo "$invalid" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
        echo "✗ UNEXPECTED MATCH (should have failed)"
    else
        echo "✓ Correctly rejected"
    fi
done
echo ""

echo "=== TEST COMPLETE ==="
echo ""
echo "Next steps:"
echo "1. Run 'sh INSTALL_CGI.sh' on your router to apply the updated script"
echo "2. Check browser developer tools for debug output in HTML comments"
echo "3. Look for specific error messages in the debug output"