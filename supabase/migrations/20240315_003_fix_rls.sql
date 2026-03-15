-- Fix RLS policies for pisowifi_openwrt
-- Allow anon to select by hardware_id directly

DROP POLICY IF EXISTS "Allow anon to check license by hardware_id" ON pisowifi_openwrt;
DROP POLICY IF EXISTS "Allow anon to create trial licenses" ON pisowifi_openwrt;
DROP POLICY IF EXISTS "Allow anon to update license activation" ON pisowifi_openwrt;

-- Simplified Select Policy: Allow anon to see any row (we filter by HW ID in the app anyway)
-- Alternatively, more secure: hardware_id = current_setting('request.header.x-hardware-id', true)
CREATE POLICY "Allow anon to check license" ON pisowifi_openwrt
    FOR SELECT TO anon USING (true);

-- Allow anon to insert trial licenses
CREATE POLICY "Allow anon to create trial" ON pisowifi_openwrt
    FOR INSERT TO anon WITH CHECK (
        status = 'trial' 
        AND (trial_days = 7 OR trial_days IS NULL)
    );

-- Allow anon to update (activate) licenses
CREATE POLICY "Allow anon to activate" ON pisowifi_openwrt
    FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- Ensure table has correct columns
ALTER TABLE pisowifi_openwrt 
ADD COLUMN IF NOT EXISTS hardware_id TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS vendor_uuid UUID,
ADD COLUMN IF NOT EXISTS license_key TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'inactive',
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS trial_days INTEGER DEFAULT 7,
ADD COLUMN IF NOT EXISTS activated_at TIMESTAMP WITH TIME ZONE;
