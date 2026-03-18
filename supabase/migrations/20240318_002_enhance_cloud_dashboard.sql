-- Enhanced Cloud Dashboard Migration - Working with Existing Schema
-- Phase 1: Enhance existing tables for cloud dashboard functionality

-- 1. Add missing columns to existing wifi_devices table for enhanced session management
ALTER TABLE wifi_devices 
ADD COLUMN IF NOT EXISTS roaming_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS roaming_devices TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS session_start_time TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS session_duration_minutes INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS data_used_bytes BIGINT DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_centralized BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS centralized_session_id UUID,
ADD COLUMN IF NOT EXISTS last_sync_attempt TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS sync_errors INTEGER DEFAULT 0;

-- 2. Create enhanced indexes for performance
CREATE INDEX IF NOT EXISTS idx_wifi_devices_session_token ON wifi_devices(session_token);
CREATE INDEX IF NOT EXISTS idx_wifi_devices_hardware_id ON wifi_devices(hardware_id);
CREATE INDEX IF NOT EXISTS idx_wifi_devices_centralized ON wifi_devices(is_centralized, is_connected);
CREATE INDEX IF NOT EXISTS idx_wifi_devices_last_heartbeat ON wifi_devices(last_heartbeat DESC);

-- 3. Create device authentication function for cloud access
CREATE OR REPLACE FUNCTION authenticate_device(hardware_id_param TEXT, auth_key_param TEXT)
RETURNS TABLE (
    device_id UUID,
    vendor_id UUID,
    is_authorized BOOLEAN,
    auth_token TEXT,
    expires_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    -- Check if device exists and is active
    IF EXISTS (
        SELECT 1 FROM wifi_devices 
        WHERE hardware_id = hardware_id_param 
        AND is_connected = true
        AND last_heartbeat > NOW() - INTERVAL '1 hour'
    ) THEN
        -- Generate authentication token
        RETURN QUERY
        SELECT 
            wd.id as device_id,
            wd.vendor_id,
            true as is_authorized,
            encode(gen_random_bytes(32), 'hex') as auth_token,
            NOW() + INTERVAL '24 hours' as expires_at
        FROM wifi_devices wd
        WHERE wd.hardware_id = hardware_id_param
        LIMIT 1;
    ELSE
        -- Return unauthorized
        RETURN QUERY
        SELECT 
            NULL::UUID as device_id,
            NULL::UUID as vendor_id,
            false as is_authorized,
            NULL::TEXT as auth_token,
            NULL::TIMESTAMP WITH TIME ZONE as expires_at;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create centralized session management function
CREATE OR REPLACE FUNCTION create_centralized_session(
    hardware_id_param TEXT,
    mac_address_param TEXT,
    ip_address_param TEXT,
    roaming_enabled_param BOOLEAN DEFAULT false
)
RETURNS TABLE (
    session_uuid UUID,
    session_token TEXT,
    is_success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    new_session_uuid UUID;
    new_session_token TEXT;
    device_record RECORD;
BEGIN
    -- Get device information
    SELECT * INTO device_record 
    FROM wifi_devices 
    WHERE hardware_id = hardware_id_param 
    AND mac_address = mac_address_param
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::UUID, NULL::TEXT, false, 'Device not found'::TEXT;
        RETURN;
    END IF;
    
    -- Generate session UUID and token
    new_session_uuid := gen_random_uuid();
    new_session_token := encode(gen_random_uuid()::TEXT || mac_address_param || NOW()::TEXT, 'hex');
    
    -- Update device with centralized session info
    UPDATE wifi_devices 
    SET 
        session_uuid = new_session_uuid::TEXT,
        centralized_session_id = new_session_uuid,
        is_centralized = true,
        roaming_enabled = roaming_enabled_param,
        session_start_time = NOW(),
        last_sync_attempt = NOW(),
        sync_errors = 0
    WHERE id = device_record.id;
    
    RETURN QUERY SELECT 
        new_session_uuid,
        new_session_token,
        true,
        'Session created successfully'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Create traffic data aggregation function
CREATE OR REPLACE FUNCTION aggregate_traffic_data(
    hardware_id_param TEXT,
    interval_minutes INTEGER DEFAULT 5
)
RETURNS TABLE (
    total_download BIGINT,
    total_upload BIGINT,
    total_data BIGINT,
    session_count INTEGER,
    avg_duration_minutes NUMERIC,
    revenue_estimate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(wd.data_used_bytes), 0) as total_download,
        COALESCE(SUM(wd.session_duration_minutes * 1024 * 1024), 0) as total_upload, -- Estimated upload
        COALESCE(SUM(wd.data_used_bytes), 0) + COALESCE(SUM(wd.session_duration_minutes * 1024 * 1024), 0) as total_data,
        COUNT(*) as session_count,
        COALESCE(AVG(wd.session_duration_minutes), 0) as avg_duration_minutes,
        COALESCE(SUM(wd.coins_used * 5.00), 0.00) as revenue_estimate -- Assuming 5 pesos per coin
    FROM wifi_devices wd
    WHERE wd.hardware_id = hardware_id_param
    AND wd.last_heartbeat > NOW() - (interval_minutes || ' minutes')::INTERVAL
    AND wd.is_connected = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Create device health check function
CREATE OR REPLACE FUNCTION check_device_health(hardware_id_param TEXT)
RETURNS TABLE (
    health_status TEXT,
    last_heartbeat TIMESTAMP WITH TIME ZONE,
    uptime_minutes INTEGER,
    sync_status TEXT,
    recommendations TEXT[]
) AS $$
DECLARE
    device_record RECORD;
    recommendations TEXT[] := '{}';
    health_status TEXT := 'healthy';
BEGIN
    SELECT * INTO device_record 
    FROM wifi_devices 
    WHERE hardware_id = hardware_id_param 
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'unknown'::TEXT, NULL::TIMESTAMP WITH TIME ZONE, 0, 'device_not_found'::TEXT, recommendations;
        RETURN;
    END IF;
    
    -- Check heartbeat
    IF device_record.last_heartbeat < NOW() - INTERVAL '5 minutes' THEN
        health_status := 'warning';
        recommendations := array_append(recommendations, 'Device heartbeat stale - check connectivity');
    END IF;
    
    IF device_record.last_heartbeat < NOW() - INTERVAL '15 minutes' THEN
        health_status := 'critical';
        recommendations := array_append(recommendations, 'Device offline - immediate attention required');
    END IF;
    
    -- Check sync errors
    IF device_record.sync_errors > 5 THEN
        health_status := 'warning';
        recommendations := array_append(recommendations, 'High sync error count - check device configuration');
    END IF;
    
    RETURN QUERY SELECT 
        health_status,
        device_record.last_heartbeat,
        COALESCE(EXTRACT(EPOCH FROM (NOW() - device_record.connected_at))/60, 0)::INTEGER as uptime_minutes,
        CASE 
            WHEN device_record.sync_errors = 0 THEN 'synced'
            WHEN device_record.sync_errors < 3 THEN 'syncing'
            ELSE 'sync_failed'
        END as sync_status,
        recommendations;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Create analytics views for dashboard
CREATE OR REPLACE VIEW device_analytics_summary AS
SELECT 
    wd.hardware_id,
    wd.vendor_id,
    COUNT(*) as total_sessions,
    COUNT(CASE WHEN wd.is_connected THEN 1 END) as active_sessions,
    COALESCE(SUM(wd.coins_used), 0) as total_coins,
    COALESCE(SUM(wd.session_duration_minutes), 0) as total_minutes,
    COALESCE(AVG(wd.signal_strength), 0) as avg_signal,
    MAX(wd.last_heartbeat) as last_activity,
    COUNT(CASE WHEN wd.last_heartbeat > NOW() - INTERVAL '1 hour' THEN 1 END) as recent_devices
FROM wifi_devices wd
GROUP BY wd.hardware_id, wd.vendor_id;

CREATE OR REPLACE VIEW revenue_by_device AS
SELECT 
    wd.hardware_id,
    DATE(wd.connected_at) as date,
    COUNT(*) as sessions_count,
    COALESCE(SUM(wd.coins_used), 0) as total_coins,
    COALESCE(SUM(wd.coins_used * 5.00), 0.00) as total_revenue, -- 5 pesos per coin
    COALESCE(AVG(wd.session_duration_minutes), 0) as avg_duration,
    COUNT(CASE WHEN wd.is_connected THEN 1 END) as active_now
FROM wifi_devices wd
GROUP BY wd.hardware_id, DATE(wd.connected_at);

CREATE OR REPLACE VIEW network_performance_metrics AS
SELECT 
    wd.hardware_id,
    AVG(wd.signal_strength) as avg_signal,
    MIN(wd.signal_strength) as min_signal,
    MAX(wd.signal_strength) as max_signal,
    COUNT(CASE WHEN wd.signal_strength > -50 THEN 1 END) as excellent_connections,
    COUNT(CASE WHEN wd.signal_strength BETWEEN -50 AND -70 THEN 1 END) as good_connections,
    COUNT(CASE WHEN wd.signal_strength < -70 THEN 1 END) as poor_connections,
    COUNT(*) as total_connections
FROM wifi_devices wd
WHERE wd.last_heartbeat > NOW() - INTERVAL '24 hours'
GROUP BY wd.hardware_id;

-- 8. Create RLS policies for cloud dashboard access
-- Enable RLS on wifi_devices if not already enabled
ALTER TABLE wifi_devices ENABLE ROW LEVEL SECURITY;

-- Device can read own data
CREATE POLICY "Device can read own data" ON wifi_devices
    FOR SELECT USING (auth.jwt() ->> 'hardware_id' = hardware_id);

-- Device can update own status
CREATE POLICY "Device can update own status" ON wifi_devices
    FOR UPDATE USING (auth.jwt() ->> 'hardware_id' = hardware_id)
    WITH CHECK (auth.jwt() ->> 'hardware_id' = hardware_id);

-- Vendor can manage all their devices
CREATE POLICY "Vendor can manage own devices" ON wifi_devices
    FOR ALL USING (auth.jwt() ->> 'vendor_id' = vendor_id::TEXT);

-- Admin can read all data
CREATE POLICY "Admin can read all data" ON wifi_devices
    FOR SELECT USING (auth.role() = 'authenticated');

-- 9. Grant permissions for analytics views
GRANT SELECT ON device_analytics_summary TO anon, authenticated;
GRANT SELECT ON revenue_by_device TO anon, authenticated;
GRANT SELECT ON network_performance_metrics TO anon, authenticated;

-- 10. Create sample data for testing
INSERT INTO wifi_devices (
    hardware_id, vendor_id, mac_address, device_name, device_type, 
    session_token, session_uuid, is_connected, centralized_session_id,
    roaming_enabled, session_start_time, session_duration_minutes,
    coins_used, signal_strength, last_heartbeat, connected_at
) VALUES 
('device_001', (SELECT id FROM auth.users LIMIT 1), 'AA:BB:CC:DD:EE:01', 'PisoWiFi Router 1', 'router', 'token_001', 'session_001', true, gen_random_uuid(), false, NOW(), 120, 10, -45, NOW(), NOW()),
('device_002', (SELECT id FROM auth.users LIMIT 1), 'AA:BB:CC:DD:EE:02', 'PisoWiFi Router 2', 'router', 'token_002', 'session_002', true, gen_random_uuid(), true, NOW(), 180, 15, -55, NOW(), NOW()),
('device_003', (SELECT id FROM auth.users LIMIT 1), 'AA:BB:CC:DD:EE:03', 'PisoWiFi Router 3', 'router', 'token_003', 'session_003', false, gen_random_uuid(), false, NOW() - INTERVAL '2 hours', 60, 5, -65, NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '2 hours');

-- 11. Create device authentication tokens table
CREATE TABLE IF NOT EXISTS device_auth_tokens (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    hardware_id TEXT NOT NULL,
    auth_token TEXT NOT NULL UNIQUE,
    vendor_id UUID,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true
);

-- Indexes for device auth tokens
CREATE INDEX IF NOT EXISTS idx_device_auth_tokens_hardware ON device_auth_tokens(hardware_id);
CREATE INDEX IF NOT EXISTS idx_device_auth_tokens_token ON device_auth_tokens(auth_token);
CREATE INDEX IF NOT EXISTS idx_device_auth_tokens_expires ON device_auth_tokens(expires_at);

-- RLS for device auth tokens
ALTER TABLE device_auth_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can manage own tokens" ON device_auth_tokens
    FOR ALL USING (auth.jwt() ->> 'hardware_id' = hardware_id);
CREATE POLICY "Vendor can manage own tokens" ON device_auth_tokens
    FOR ALL USING (auth.jwt() ->> 'vendor_id' = vendor_id::TEXT);