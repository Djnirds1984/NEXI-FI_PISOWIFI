#!/bin/bash

# Test script to verify centralized key format
TEST_KEY="CENTRAL-377ed7bc-94f058b9"

echo "Testing key format validation..."
echo "Test key: $TEST_KEY"
echo ""

# Test the regex pattern
echo "1. Testing regex pattern:"
if echo "$TEST_KEY" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
    echo "   ✓ REGEX MATCHED"
else
    echo "   ✗ REGEX FAILED"
fi

# Test key components
echo ""
echo "2. Testing key components:"
echo "   Prefix: $(echo "$TEST_KEY" | cut -d'-' -f1)"
echo "   Part 1: $(echo "$TEST_KEY" | cut -d'-' -f2)"
echo "   Part 2: $(echo "$TEST_KEY" | cut -d'-' -f3)"

# Test each part is hex
echo ""
echo "3. Testing hex validity:"
PART1=$(echo "$TEST_KEY" | cut -d'-' -f2)
PART2=$(echo "$TEST_KEY" | cut -d'-' -f3)

if echo "$PART1" | grep -Eq "^[a-fA-F0-9]+$"; then
    echo "   ✓ Part 1 is valid hex: $PART1"
else
    echo "   ✗ Part 1 is NOT valid hex: $PART1"
fi

if echo "$PART2" | grep -Eq "^[a-fA-F0-9]+$"; then
    echo "   ✓ Part 2 is valid hex: $PART2"
else
    echo "   ✗ Part 2 is NOT valid hex: $PART2"
fi

echo ""
echo "4. Testing case variations:"
for variant in "CENTRAL-377ed7bc-94f058b9" "central-377ED7BC-94F058B9" "Central-377Ed7Bc-94F058B9"; do
    if echo "$variant" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
        echo "   ✓ $variant: MATCHED"
    else
        echo "   ✗ $variant: FAILED"
    fi
done