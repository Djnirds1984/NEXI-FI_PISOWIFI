-- Cloud-Based Dashboard Migration for PisoWiFi System
-- Phase 1: Database Schema Expansion

-- 1. Traffic Data Table (Real-time traffic monitoring)
CREATE TABLE IF NOT EXISTS traffic_data (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    device_id TEXT NOT NULL,
    session_id UUID,
    download_bytes BIGINT DEFAULT 0,
    upload_bytes BIGINT DEFAULT 0,
    total_bytes BIGINT DEFAULT 0,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_traffic_device_timestamp ON traffic_data(device_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_traffic_session ON traffic_data(session_id);
CREATE INDEX IF NOT EXISTS idx_traffic_timestamp ON traffic_data(timestamp DESC);

-- 2. Device Configurations Table (Centralized device settings)
CREATE TABLE IF NOT EXISTS device_configs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    device_id TEXT NOT NULL UNIQUE,
    device_name TEXT,
    location TEXT,
    config JSONB DEFAULT '{}',
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    last_seen TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_device_configs_device_id ON device_configs(device_id);
CREATE INDEX IF NOT EXISTS idx_device_configs_active ON device_configs(is_active);
CREATE INDEX IF NOT EXISTS idx_device_configs_last_seen ON device_configs(last_seen DESC);

-- 3. Centralized Sessions Table (Cross-device session management)
CREATE TABLE IF NOT EXISTS centralized_sessions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    session_token TEXT NOT NULL UNIQUE,
    device_id TEXT NOT NULL,
    user_mac TEXT NOT NULL,
    user_ip TEXT,
    session_start TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    session_end TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER DEFAULT 0,
    data_used BIGINT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    roaming_enabled BOOLEAN DEFAULT false,
    roaming_devices TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_sessions_device_id ON centralized_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_mac ON centralized_sessions(user_mac);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON centralized_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON centralized_sessions(is_active);
CREATE INDEX IF NOT EXISTS idx_sessions_start ON centralized_sessions(session_start DESC);

-- 4. Device Status Table (Real-time device health)
CREATE TABLE IF NOT EXISTS device_status (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    device_id TEXT NOT NULL UNIQUE,
    cpu_usage INTEGER DEFAULT 0,
    memory_usage INTEGER DEFAULT 0,
    disk_usage INTEGER DEFAULT 0,
    network_status TEXT DEFAULT 'online',
    uptime_seconds BIGINT DEFAULT 0,
    temperature_celsius INTEGER,
    last_heartbeat TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    error_count INTEGER DEFAULT 0,
    warning_count INTEGER DEFAULT 0,
    status_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_device_status_device_id ON device_status(device_id);
CREATE INDEX IF NOT EXISTS idx_device_status_network ON device_status(network_status);
CREATE INDEX IF NOT EXISTS idx_device_status_heartbeat ON device_status(last_heartbeat DESC);

-- 5. Revenue Analytics Table (Financial tracking)
CREATE TABLE IF NOT EXISTS revenue_analytics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    device_id TEXT NOT NULL,
    date DATE NOT NULL,
    total_sessions INTEGER DEFAULT 0,
    total_revenue DECIMAL(10,2) DEFAULT 0.00,
    average_session_duration INTEGER DEFAULT 0,
    peak_hour_start INTEGER,
    peak_hour_end INTEGER,
    peak_sessions_count INTEGER DEFAULT 0,
    coins_inserted INTEGER DEFAULT 0,
    bills_inserted INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_revenue_device_date ON revenue_analytics(device_id, date);
CREATE INDEX IF NOT EXISTS idx_revenue_date ON revenue_analytics(date DESC);
CREATE INDEX IF NOT EXISTS idx_revenue_device ON revenue_analytics(device_id);

-- 6. System Logs Table (Audit trail)
CREATE TABLE IF NOT EXISTS system_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    device_id TEXT NOT NULL,
    log_level TEXT NOT NULL DEFAULT 'info',
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_logs_device_timestamp ON system_logs(device_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_logs_level ON system_logs(log_level);
CREATE INDEX IF NOT EXISTS idx_logs_category ON system_logs(category);
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON system_logs(timestamp DESC);

-- Row Level Security (RLS) Policies for Multi-tenant Isolation

-- Traffic Data RLS
ALTER TABLE traffic_data ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can read own traffic data" ON traffic_data
    FOR SELECT USING (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Authenticated users can read traffic data" ON traffic_data
    FOR SELECT USING (auth.role() = 'authenticated');

-- Device Configs RLS
ALTER TABLE device_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can read own config" ON device_configs
    FOR SELECT USING (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Device can update own config" ON device_configs
    FOR UPDATE USING (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Authenticated users can manage all configs" ON device_configs
    FOR ALL USING (auth.role() = 'authenticated');

-- Centralized Sessions RLS
ALTER TABLE centralized_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can manage own sessions" ON centralized_sessions
    FOR ALL USING (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Authenticated users can manage all sessions" ON centralized_sessions
    FOR ALL USING (auth.role() = 'authenticated');

-- Device Status RLS
ALTER TABLE device_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can update own status" ON device_status
    FOR UPDATE USING (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Authenticated users can read all status" ON device_status
    FOR SELECT USING (auth.role() = 'authenticated');

-- Revenue Analytics RLS
ALTER TABLE revenue_analytics ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can read own analytics" ON revenue_analytics
    FOR SELECT USING (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Authenticated users can manage all analytics" ON revenue_analytics
    FOR ALL USING (auth.role() = 'authenticated');

-- System Logs RLS
ALTER TABLE system_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Device can create own logs" ON system_logs
    FOR INSERT WITH CHECK (auth.jwt() ->> 'device_id' = device_id);
CREATE POLICY "Authenticated users can read all logs" ON system_logs
    FOR SELECT USING (auth.role() = 'authenticated');

-- Analytics Views for Dashboard
CREATE OR REPLACE VIEW daily_device_summary AS
SELECT 
    device_id,
    DATE(timestamp) as date,
    COUNT(DISTINCT id) as total_records,
    SUM(download_bytes) as total_download,
    SUM(upload_bytes) as total_upload,
    SUM(total_bytes) as total_data,
    AVG(download_bytes) as avg_download,
    AVG(upload_bytes) as avg_upload
FROM traffic_data 
GROUP BY device_id, DATE(timestamp);

CREATE OR REPLACE VIEW active_sessions_summary AS
SELECT 
    device_id,
    COUNT(*) as active_sessions_count,
    COUNT(DISTINCT user_mac) as unique_users,
    SUM(data_used) as total_data_used,
    AVG(duration_minutes) as avg_session_duration
FROM centralized_sessions 
WHERE is_active = true
GROUP BY device_id;

CREATE OR REPLACE VIEW device_health_summary AS
SELECT 
    ds.device_id,
    ds.network_status,
    ds.cpu_usage,
    ds.memory_usage,
    ds.disk_usage,
    ds.uptime_seconds,
    ds.last_heartbeat,
    CASE 
        WHEN ds.last_heartbeat > NOW() - INTERVAL '5 minutes' THEN 'healthy'
        WHEN ds.last_heartbeat > NOW() - INTERVAL '15 minutes' THEN 'warning'
        ELSE 'critical'
    END as health_status
FROM device_status ds;

-- Grant necessary permissions
GRANT SELECT ON daily_device_summary TO anon, authenticated;
GRANT SELECT ON active_sessions_summary TO anon, authenticated;
GRANT SELECT ON device_health_summary TO anon, authenticated;