-- Enhance existing wifi_devices table for cloud dashboard
-- Add session token functionality and cloud integration features

-- Add session token column if not exists
ALTER TABLE wifi_devices 
ADD COLUMN IF NOT EXISTS session_token TEXT UNIQUE;

-- Add cloud integration columns
ALTER TABLE wifi_devices 
ADD COLUMN IF NOT EXISTS cloud_sync_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS last_cloud_sync TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS cloud_config JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS roaming_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS roaming_devices TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS data_used_today BIGINT DEFAULT 0,
ADD COLUMN IF NOT EXISTS revenue_today NUMERIC DEFAULT 0.00;

-- Create indexes for cloud dashboard performance
CREATE INDEX IF NOT EXISTS idx_wifi_devices_session_token ON wifi_devices(session_token);
CREATE INDEX IF NOT EXISTS idx_wifi_devices_last_sync ON wifi_devices(last_cloud_sync DESC);
CREATE INDEX IF NOT EXISTS idx_wifi_devices_roaming ON wifi_devices(roaming_enabled);

-- Add RLS policies for cloud dashboard access
ALTER TABLE wifi_devices ENABLE ROW LEVEL SECURITY;

-- Device can read own data using session token
CREATE POLICY "Device can read own data via session token" ON wifi_devices
    FOR SELECT USING (
        auth.jwt() ->> 'session_token' = session_token OR
        auth.jwt() ->> 'device_id' = mac_address
    );

-- Device can update own data
CREATE POLICY "Device can update own data" ON wifi_devices
