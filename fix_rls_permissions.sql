-- Fix RLS permissions for centralized_keys table
-- Run these commands in your Supabase SQL editor

-- Step 1: Check current RLS status
SELECT relname, relrowsecurity 
FROM pg_class 
WHERE relname = 'centralized_keys';

-- Step 2: If RLS is enabled, add policies for anonymous access
-- Policy to allow anyone to read centralized keys for validation
CREATE POLICY "Allow anonymous read access to centralized keys" 
ON public.centralized_keys 
FOR SELECT 
USING (true);

-- Alternative: More restrictive policy - only allow reading active keys
CREATE POLICY "Allow read access to active centralized keys" 
ON public.centralized_keys 
FOR SELECT 
USING (is_active = true);

-- Step 3: Grant explicit permissions (backup solution if policies don't work)
GRANT SELECT ON public.centralized_keys TO anon;
GRANT SELECT ON public.centralized_keys TO authenticated;

-- Step 4: Verify the key exists and is active
SELECT id, key_value, vendor_id, is_active, created_at 
FROM public.centralized_keys 
WHERE key_value = 'CENTRAL-377ed7bc-94f058b9';

-- Step 5: Check permissions after changes
SELECT grantee, table_name, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_schema = 'public' 
AND table_name = 'centralized_keys' 
AND grantee IN ('anon', 'authenticated');