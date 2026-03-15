# 🔧 FIXED: Centralized Key Activation Issue

## 🎯 ROOT CAUSE IDENTIFIED

The issue is **Row Level Security (RLS) policies** in your Supabase database. Your `centralized_keys` table has RLS enabled but no policies allowing anonymous users to read the data, which is why queries return empty results even though the key exists.

## ✅ SOLUTION STEPS

### Step 1: Add Service Role Key to Configuration

**Add this to your `/etc/pisowifi/supabase.env` file:**
```bash
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here
```

**Get your service role key from:**
- Supabase Dashboard → Settings → API → Project API keys → `service_role` key

### Step 2: Fix RLS Permissions (Choose Option A or B)

#### Option A: Add RLS Policy (Recommended)
**Run this SQL in your Supabase dashboard:**
```sql
-- Add policy to allow anonymous users to read centralized keys
CREATE POLICY "Allow anonymous read access to centralized keys" 
ON public.centralized_keys 
FOR SELECT 
USING (true);
```

#### Option B: Grant Direct Permissions
**Run this SQL in your Supabase dashboard:**
```sql
-- Grant read permissions to anonymous users
GRANT SELECT ON public.centralized_keys TO anon;
GRANT SELECT ON public.centralized_keys TO authenticated;
```

### Step 3: Verify the Fix

**Test the query manually:**
```bash
curl -s "https://fuiabtdfLbodglfexvln.supabase.co/rest/v1/centralized_keys?select=id,key_value,vendor_id,is_active&key_value=ilike.CENTRAL-377ed7bc-94f058b9&limit=1" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"
```

**Should return:**
```json
[{"id":"your-uuid","key_value":"CENTRAL-377ed7bc-94f058b9","vendor_id":"your-vendor-uuid","is_active":true}]
```

### Step 4: Apply the Updated Installer

**The installer script now includes:**
- ✅ Service role key fallback mechanism
- ✅ Enhanced debugging to show exact queries
- ✅ Automatic retry with elevated permissions
- ✅ Comprehensive error logging

**Run the updated installer:**
```bash
bash INSTALL_CGI.sh
```

## 🔍 DEBUGGING COMMANDS

**Test your database directly:**
```bash
# Test with the debug script
bash debug_centralized_key_final.sh https://fuiabtdfLbodglfexvln.supabase.co YOUR_ANON_KEY CENTRAL-377ed7bc-94f058b9

# Test with service role (if you have it)
SUPA_SERVICE_KEY=your_service_role_key bash debug_centralized_key_final.sh https://fuiabtdfLbodglfexvln.supabase.co YOUR_ANON_KEY CENTRAL-377ed7bc-94f058b9
```

**Check current permissions:**
```sql
-- Check RLS status
SELECT relname, relrowsecurity 
FROM pg_class 
WHERE relname = 'centralized_keys';

-- Check current policies
SELECT * 
FROM pg_policies 
WHERE tablename = 'centralized_keys';

-- Check permissions
SELECT grantee, table_name, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_schema = 'public' 
AND table_name = 'centralized_keys' 
AND grantee IN ('anon', 'authenticated');
```

## 🚀 WHAT THE FIX DOES

1. **Loads Service Role Key**: The installer now loads your service role key as a fallback
2. **RLS Policy**: Adds a policy allowing anonymous users to read centralized keys
3. **Automatic Fallback**: If anon key fails, automatically tries service role key
4. **Enhanced Debugging**: Shows exact queries being executed for troubleshooting

## 📋 VERIFICATION

After applying the fix, you should see:
- ✅ Key validation passes
- ✅ Database query returns the key data
- ✅ Activation succeeds
- ✅ Centralized key status shows "active"

**The error "Failed to activate Centralized Key. Check format or connection." should be resolved!**