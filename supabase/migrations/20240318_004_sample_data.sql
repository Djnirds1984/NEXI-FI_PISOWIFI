-- Sample Data for Cloud Dashboard Testing
-- Phase 1: Test Data Population

-- Insert sample vendors (machines) if not exists
INSERT INTO vendors (hardware_id, machine_name, location, is_licensed, status, total_revenue, coin_slot_pulses, last_seen, created_at, updated_at)
VALUES 
('machine_001', 'PisoWiFi Machine 1', 'Quezon City Branch', true, 'online', 1250.00, 250, NOW(), NOW(), NOW()),
('machine_002', 'PisoWiFi Machine 2', 'Manila Branch', true, 'online', 980.00, 196, NOW(), NOW(), NOW()),
('machine_003', 'PisoWiFi Machine 3', 'Makati Branch', false, 'offline', 0.00, 0, NOW() - INTERVAL '2 days', NOW(), NOW())
ON CONFLICT (hardware_id) DO NOTHING;

-- Insert sample wifi_devices for testing
INSERT INTO wifi_devices (
    machine_id, vendor_id, mac_address, device_name, device_type, 
    session_token, is_connected, centralized_session_id,
    roaming_enabled, session_start_time, session_duration_seconds,
    coins_used, signal_strength, last_heartbeat, total_lifetime_data,
    data_used_bytes, sync_errors, is_centralized
) 
SELECT 
    v.id as machine_id,
    COALESCE(v.vendor_id, (SELECT id FROM auth.users LIMIT 1)) as vendor_id,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 'AA:BB:CC:DD:EE:01'
        WHEN v.hardware_id = 'machine_002' THEN 'AA:BB:CC:DD:EE:02'
        WHEN v.hardware_id = 'machine_003' THEN 'AA:BB:CC:DD:EE:03'
    END as mac_address,
    v.machine_name as device_name,
    'other' as device_type,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 'active_token_001'
        WHEN v.hardware_id = 'machine_002' THEN 'active_token_002'
        WHEN v.hardware_id = 'machine_003' THEN 'inactive_token_003'
    END as session_token,
    CASE WHEN v.status = 'online' THEN true ELSE false END as is_connected,
    gen_random_uuid() as centralized_session_id,
    CASE WHEN v.hardware_id = 'machine_002' THEN true ELSE false END as roaming_enabled,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN NOW() - INTERVAL '2 hours'
        WHEN v.hardware_id = 'machine_002' THEN NOW() - INTERVAL '1 hour'
        WHEN v.hardware_id = 'machine_003' THEN NOW() - INTERVAL '1 day'
    END as session_start_time,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 7200  -- 2 hours in seconds
        WHEN v.hardware_id = 'machine_002' THEN 3600  -- 1 hour in seconds
        WHEN v.hardware_id = 'machine_003' THEN 1800  -- 30 minutes in seconds
    END as session_duration_seconds,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 25
        WHEN v.hardware_id = 'machine_002' THEN 18
        WHEN v.hardware_id = 'machine_003' THEN 8
    END as coins_used,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN -45  -- Excellent signal
        WHEN v.hardware_id = 'machine_002' THEN -55  -- Good signal
        WHEN v.hardware_id = 'machine_003' THEN -75  -- Poor signal
    END as signal_strength,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN NOW() - INTERVAL '5 minutes'
        WHEN v.hardware_id = 'machine_002' THEN NOW() - INTERVAL '2 minutes'
        WHEN v.hardware_id = 'machine_003' THEN NOW() - INTERVAL '45 minutes'
    END as last_heartbeat,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 524288000  -- 500MB
        WHEN v.hardware_id = 'machine_002' THEN 262144000  -- 250MB
        WHEN v.hardware_id = 'machine_003' THEN 104857600  -- 100MB
    END as total_lifetime_data,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 104857600  -- 100MB current session
        WHEN v.hardware_id = 'machine_002' THEN 52428800   -- 50MB current session
        WHEN v.hardware_id = 'machine_003' THEN 20971520   -- 20MB current session
    END as data_used_bytes,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 0
        WHEN v.hardware_id = 'machine_002' THEN 1
        WHEN v.hardware_id = 'machine_003' THEN 3
    END as sync_errors,
    CASE 
        WHEN v.hardware_id IN ('machine_001', 'machine_002') THEN true
        ELSE false
    END as is_centralized
FROM vendors v
WHERE v.hardware_id IN ('machine_001', 'machine_002', 'machine_003');

-- Insert sample device authentication tokens
INSERT INTO device_auth_tokens (machine_id, auth_token, vendor_id, expires_at, last_used, is_active)
SELECT 
    v.id as machine_id,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN 'auth_token_001_active'
        WHEN v.hardware_id = 'machine_002' THEN 'auth_token_002_active'
        WHEN v.hardware_id = 'machine_003' THEN 'auth_token_003_expired'
    END as auth_token,
    COALESCE(v.vendor_id, (SELECT id FROM auth.users LIMIT 1)) as vendor_id,
    CASE 
        WHEN v.hardware_id IN ('machine_001', 'machine_002') THEN NOW() + INTERVAL '24 hours'
        WHEN v.hardware_id = 'machine_003' THEN NOW() - INTERVAL '1 hour'
    END as expires_at,
    CASE 
        WHEN v.hardware_id = 'machine_001' THEN NOW() - INTERVAL '30 minutes'
        WHEN v.hardware_id = 'machine_002' THEN NOW() - INTERVAL '15 minutes'
        WHEN v.hardware_id = 'machine_003' THEN NOW() - INTERVAL '2 hours'
    END as last_used,
    CASE 
        WHEN v.hardware_id IN ('machine_001', 'machine_002') THEN true
        ELSE false
    END as is_active
FROM vendors v
WHERE v.hardware_id IN ('machine_001', 'machine_002', 'machine_003');

-- Insert sample traffic data
INSERT INTO traffic_data (hardware_id, device_mac, rx_bytes, tx_bytes, rx_packets, tx_packets, timestamp)
VALUES 
('machine_001', 'AA:BB:CC:DD:EE:01', 104857600, 52428800, 150000, 75000, NOW() - INTERVAL '10 minutes'),
('machine_001', 'AA:BB:CC:DD:EE:01', 157286400, 78643200, 225000, 112500, NOW() - INTERVAL '5 minutes'),
('machine_002', 'AA:BB:CC:DD:EE:02', 52428800, 26214400, 75000, 37500, NOW() - INTERVAL '8 minutes'),
('machine_002', 'AA:BB:CC:DD:EE:02', 73400320, 36700160, 105000, 52500, NOW() - INTERVAL '3 minutes');

-- Insert sample system logs
INSERT INTO system_logs (hardware_id, log_level, log_type, message, metadata, timestamp)
VALUES 
('machine_001', 'info', 'connection', 'Device connected successfully', '{"ip": "192.168.1.100", "signal": -45}', NOW() - INTERVAL '2 hours'),
('machine_001', 'info', 'payment', 'Coin inserted: 5 pesos', '{"amount": 5, "total": 125}', NOW() - INTERVAL '1 hour'),
('machine_002', 'warning', 'sync', 'Sync attempt failed', '{"error": "timeout", "retry": 3}', NOW() - INTERVAL '30 minutes'),
('machine_003', 'error', 'connection', 'Device heartbeat timeout', '{"last_seen": "45 minutes ago"}', NOW() - INTERVAL '45 minutes');

-- Insert sample revenue analytics
INSERT INTO revenue_analytics (hardware_id, date, total_revenue, total_sessions, total_minutes, coins_inserted, average_session_duration, peak_hours)
VALUES 
('machine_001', CURRENT_DATE, 1250.00, 45, 1800, 250, 40, '[{"hour": 8, "sessions": 12}, {"hour": 12, "sessions": 15}, {"hour": 18, "sessions": 18}]'),
('machine_002', CURRENT_DATE, 980.00, 35, 1400, 196, 40, '[{"hour": 9, "sessions": 10}, {"hour": 13, "sessions": 12}, {"hour": 19, "sessions": 13}]'),
('machine_001', CURRENT_DATE - 1, 1100.00, 40, 1600, 220, 40, '[{"hour": 7, "sessions": 8}, {"hour": 12, "sessions": 14}, {"hour": 17, "sessions": 18}]'),
('machine_002', CURRENT_DATE - 1, 850.00, 30, 1200, 170, 40, '[{"hour": 8, "sessions": 9}, {"hour": 14, "sessions": 11}, {"hour": 20, "sessions": 10}]');