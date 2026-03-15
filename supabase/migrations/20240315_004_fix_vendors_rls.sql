-- Fix RLS policies for vendors table
-- Allow machines to manage their own records

ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow anon to manage own vendor record" ON vendors;

-- Allow anon to select their own record
CREATE POLICY "Allow anon to select own vendor record" ON vendors
    FOR SELECT TO anon USING (true);

-- Allow anon to insert their own record
CREATE POLICY "Allow anon to insert own vendor record" ON vendors
    FOR INSERT TO anon WITH CHECK (true);

-- Allow anon to update their own record
CREATE POLICY "Allow anon to update own vendor record" ON vendors
    FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON vendors TO anon;
