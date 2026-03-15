-- Check current permissions for centralized_keys table
SELECT grantee, table_name, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_schema = 'public' 
AND table_name = 'centralized_keys' 
AND grantee IN ('anon', 'authenticated') 
ORDER BY privilege_type;

-- Check if RLS is enabled
SELECT relname, relrowsecurity 
FROM pg_class 
WHERE relname = 'centralized_keys';

-- Check RLS policies
SELECT * 
FROM pg_policies 
WHERE tablename = 'centralized_keys';

-- Grant necessary permissions for anonymous access (if needed)
GRANT SELECT ON public.centralized_keys TO anon;
GRANT SELECT ON public.centralized_keys TO authenticated;

-- Check if key exists (for debugging)
SELECT id, key_value, vendor_id, is_active 
FROM public.centralized_keys 
WHERE key_value = 'CENTRAL-377ed7bc-94f058b9';