-- License System for PisoWifi OpenWRT
-- Add license fields to existing pisowifi_openwrt table

-- Check if pisowifi_openwrt table exists first
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables 
                  WHERE table_schema = 'public' 
                  AND table_name = 'pisowifi_openwrt') THEN
        -- Create the table if it doesn't exist
        CREATE TABLE pisowifi_openwrt (
            id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
            hardware_id TEXT UNIQUE,
            vendor_uuid UUID,
            license_key TEXT UNIQUE,
            status TEXT DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'expired', 'trial')),
            expires_at TIMESTAMP WITH TIME ZONE,
            trial_days INTEGER DEFAULT 7,
            activated_at TIMESTAMP WITH TIME ZONE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    ELSE
        -- Add license columns if they don't exist
        ALTER TABLE pisowifi_openwrt 
        ADD COLUMN IF NOT EXISTS hardware_id TEXT UNIQUE,
        ADD COLUMN IF NOT EXISTS vendor_uuid UUID,
        ADD COLUMN IF NOT EXISTS license_key TEXT UNIQUE,
        ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'expired', 'trial')),
        ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS trial_days INTEGER DEFAULT 7,
        ADD COLUMN IF NOT EXISTS activated_at TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
    END IF;
END $$;

-- License activation logs
CREATE TABLE IF NOT EXISTS pisowifi_license_activations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    license_id UUID REFERENCES pisowifi_openwrt(id) ON DELETE CASCADE,
    hardware_id TEXT NOT NULL,
    activated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT
);

-- Enable RLS
ALTER TABLE pisowifi_openwrt ENABLE ROW LEVEL SECURITY;
ALTER TABLE pisowifi_license_activations ENABLE ROW LEVEL SECURITY;

-- Policies for pisowifi_openwrt table
CREATE POLICY "Allow anon to check license by hardware_id" ON pisowifi_openwrt
    FOR SELECT USING (
        hardware_id = current_setting('app.hardware_id', true)::TEXT
        OR EXISTS (
            SELECT 1 FROM pisowifi_openwrt 
            WHERE hardware_id = current_setting('app.hardware_id', true)::TEXT
        )
    );

CREATE POLICY "Allow anon to create trial licenses" ON pisowifi_openwrt
    FOR INSERT WITH CHECK (
        status = 'trial' 
        AND trial_days = 7
        AND activated_at IS NULL
        AND vendor_uuid IS NULL
    );

CREATE POLICY "Allow anon to update license activation" ON pisowifi_openwrt
    FOR UPDATE USING (
        hardware_id = current_setting('app.hardware_id', true)::TEXT
    ) WITH CHECK (
        hardware_id = current_setting('app.hardware_id', true)::TEXT
    );

-- Policies for pisowifi_license_activations table
CREATE POLICY "Allow anon to view own activations" ON pisowifi_license_activations
    FOR SELECT USING (
        hardware_id = current_setting('app.hardware_id', true)::TEXT
    );

CREATE POLICY "Allow anon to create activations" ON pisowifi_license_activations
    FOR INSERT WITH CHECK (
        license_id IN (
            SELECT id FROM pisowifi_openwrt 
            WHERE hardware_id = current_setting('app.hardware_id', true)::TEXT
        )
    );

-- Grant permissions
GRANT SELECT ON pisowifi_openwrt TO anon;
GRANT INSERT ON pisowifi_openwrt TO anon;
GRANT UPDATE ON pisowifi_openwrt TO anon;
GRANT SELECT ON pisowifi_license_activations TO anon;
GRANT INSERT ON pisowifi_license_activations TO anon;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_pisowifi_hardware_id ON pisowifi_openwrt(hardware_id);
CREATE INDEX IF NOT EXISTS idx_pisowifi_status ON pisowifi_openwrt(status);
CREATE INDEX IF NOT EXISTS idx_pisowifi_expires_at ON pisowifi_openwrt(expires_at);
CREATE INDEX IF NOT EXISTS idx_license_activations_license_id ON pisowifi_license_activations(license_id);
CREATE INDEX IF NOT EXISTS idx_license_activations_hardware_id ON pisowifi_license_activations(hardware_id);