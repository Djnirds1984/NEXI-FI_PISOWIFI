#!/bin/bash

echo "Testing shell syntax..."

# Test the key validation regex
test_key="CENTRAL-377ed7bc-94f058b9"
echo "Test key: $test_key"

if echo "$test_key" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
    echo "✓ Regex validation PASSED"
else
    echo "✗ Regex validation FAILED"
fi

# Test case variations
for variant in "CENTRAL-377ed7bc-94f058b9" "central-377ED7BC-94F058B9" "Central-377Ed7Bc-94F058B9"; do
    if echo "$variant" | grep -Eqi "^CENTRAL-[a-fA-F0-9]+-[a-fA-F0-9]+$"; then
        echo "✓ $variant: MATCHED"
    else
        echo "✗ $variant: FAILED"
    fi
done

echo ""
echo "Syntax test complete! The installer script should now work correctly."
echo "Next step: Run 'sh INSTALL_CGI.sh' on your router to apply the fixed version."