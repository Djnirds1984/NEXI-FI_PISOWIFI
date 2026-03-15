#!/usr/bin/lua

-- Test script for centralized key format validation

local function test_centralized_key_format(key)
    -- Test the pattern: CENTRAL-XXXXXXXX-XXXXXXXX
    local pattern = "^CENTRAL%-[a-f0-9]+%-[a-f0-9]+$"
    local is_centralized = key:match(pattern)
    
    print("Testing key: " .. key)
    print("Is centralized key: " .. (is_centralized and "YES" or "NO"))
    print("Pattern used: " .. pattern)
    print("---")
    
    return is_centralized
end

-- Test cases
local test_keys = {
    "CENTRAL-377ed7bc-94f058b9",  -- Valid centralized key (user's sample)
    "CENTRAL-12345678-abcdef12",   -- Valid centralized key
    "CENTRAL-377ed7bc94f058b9",   -- Invalid - missing dash
    "CENTRAL-377ed7bc-94f058b",   -- Invalid - wrong length
    "LICENSE-12345678-abcdef12",  -- Invalid - wrong prefix
    "12345678-abcdef12",          -- Invalid - missing prefix
    "CENTRAL-377ed7bc-94f058b9-extra", -- Invalid - extra characters
    "centraL-377ed7bc-94f058b9",  -- Invalid - wrong case
}

print("Centralized Key Format Validation Test")
print("=====================================")
print("User sample format: CENTRAL-377ed7bc-94f058b9")
print("")

for _, key in ipairs(test_keys) do
    test_centralized_key_format(key)
end

print("Test completed!")