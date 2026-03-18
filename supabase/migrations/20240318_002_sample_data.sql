-- Phase 1: Sample Data for Testing Cloud Dashboard
-- Insert sample data to test the new tables and functionality

-- Sample Device Configurations
INSERT INTO device_configs (hardware_id, device_name, location, vendor_uuid, settings, network_config, rate_plans, is_active) VALUES
('openwrt-device-001', 'PisoWiFi Router 1', 'Makati City', '550e8400-e29b-41d4-a716-446655440001', 
'{"minutes_per_peso": 12, "max_sessions": 50, "auto_pause": true, "theme": "default"}', 
'{"wan_interface": "eth0", "lan_ip": "10.0.0.1", "dhcp_range": "10.0.0.100-10.0.0.200"}', 
'[{"amount": 1, "minutes": 12, "pausable": true}, {"amount": 5, "minutes": 65, "pausable": true}, {"amount": 10, "minutes": 135, "pausable": true}]', 
true),

('openwrt-device-002', 'PisoWiFi Router 2', 'Quezon City', '550e8400-e29b-41d4-a716-446655440002', 
'{"minutes_per_peso": 10, "max_sessions": 30, "auto_pause": false, "theme": "minimal"}', 
'{"wan_interface": "eth1", "lan_ip": "192.168.1.1", "dhcp_range": "192.168.1.100-192.168.1.150"}', 
'[{"amount": 1, "minutes": 10, "pausable": false}, {"amount": 5, "minutes": 55, "pausable": false}]', 
true),

('openwrt-device-003', 'PisoWiFi Router 3', 'Manila City', '550e8400-e29b-41d4-a716-446655440003', 
'{"minutes_per_peso": 15, "max_sessions": 25, "auto_pause": true, "theme": "dark"}', 
'{"wan_interface": "wlan0", "lan_ip": "172.16.0.1", "dhcp_range": "172.16.0.50-172.16.0.100"}', 
'[{"amount": 1, "minutes": 15, "pausable": true}, {"amount": 5, "minutes": 80, "pausable": true}]', 
true);

-- Sample Device Status
INSERT INTO device_status (hardware_id, cpu_usage, memory_usage, disk_usage, temperature, uptime_seconds, active_sessions, total_sessions_today, revenue_today, network_status) VALUES
('openwrt-device-001', 45.2, 68.5, 23.1, 65.3, 86400, 5, 25, 150.00, 
'{"wan_connected": true, "signal_strength": -45, "clients_connected": 5}'),

('openwrt-device-002', 32.8, 55.2, 18.7, 58.9, 172800, 3, 18, 95.00, 
'{"wan_connected": true, "signal_strength": -52, "clients_connected": 3}'),

('openwrt-device-003', 28.5, 42.1, 15.3, 62.1, 259200, 2, 12, 75.00, 
'{"wan_connected": true, "signal_strength": -38, "clients_connected": 2}');

-- Sample Centralized Sessions
INSERT INTO centralized_sessions (hardware_id, mac_address, ip_address, session_uuid, remaining_seconds, total_seconds, coins_inserted, is_paused, is_active, connected_at, expires_at) VALUES
('openwrt-device-001', 'AA:BB:CC:DD:EE:01', '10.0.0.101', 'session-uuid-001', 7200, 3600, 5, false, true, NOW() - INTERVAL '30 minutes', NOW() + INTERVAL '2 hours'),
('openwrt-device-001', 'AA:BB:CC:DD:EE:02', '10.0.0.102', 'session-uuid-002', 5400, 7200, 10, false, true, NOW() - INTERVAL '1 hour', NOW() + INTERVAL '1.5 hours'),
('openwrt-device-001', 'AA:BB:CC:DD:EE:03', '10.0.0.103', 'session-uuid-003', 1800, 1800, 2, true, true, NOW() - INTERVAL '45 minutes', NOW() + INTERVAL '30 minutes'),

('openwrt-device-002', 'BB:CC:DD:EE:FF:01', '192.168.1.101', 'session-uuid-004', 3600, 3600, 3, false, true, NOW() - INTERVAL '20 minutes', NOW() + INTERVAL '1 hour'),
('openwrt-device-002', 'BB:CC:DD:EE:FF:02', '192.168.1.102', 'session-uuid-005', 9000, 5400, 15, false, true, NOW() - INTERVAL '90 minutes', NOW() + INTERVAL '2.5 hours'),

('openwrt-device-003', 'CC:DD:EE:FF:GG:01', '172.16.0.51', 'session-uuid-006', 4500, 2700, 3, false, true, NOW() - INTERVAL '40 minutes', NOW() + INTERVAL '1.25 hours'),
('openwrt-device-003', 'CC:DD:EE:FF:GG:02', '172.16.0.52', 'session-uuid-007', 2700, 1800, 2, false, true, NOW() - INTERVAL '25 minutes', NOW() + INTERVAL '45 minutes');

-- Sample Traffic Data (last 24 hours)
INSERT INTO traffic_data (hardware_id, device_mac, rx_bytes, tx_bytes, rx_packets, tx_packets, interface_name, timestamp) VALUES
-- Device 001 - Recent traffic
('openwrt-device-001', 'AA:BB:CC:DD:EE:01', 157286400, 52428800, 45000, 15000, 'eth0', NOW() - INTERVAL '1 hour'),
('openwrt-device-001', 'AA:BB:CC:DD:EE:02', 209715200, 104857600, 60000, 30000, 'eth0', NOW() - INTERVAL '2 hours'),
('openwrt-device-001', 'AA:BB:CC:DD:EE:03', 78643200, 26214400, 22500, 7500, 'eth0', NOW() - INTERVAL '3 hours'),

-- Device 002 - Recent traffic
('openwrt-device-002', 'BB:CC:DD:EE:FF:01', 104857600, 52428800, 30000, 15000, 'eth1', NOW() - INTERVAL '1 hour'),
('openwrt-device-002', 'BB:CC:DD:EE:FF:02', 262144000, 131072000, 75000, 37500, 'eth1', NOW() - INTERVAL '2 hours'),

-- Device 003 - Recent traffic
('openwrt-device-003', 'CC:DD:EE:FF:GG:01', 131072000, 65536000, 37500, 18750, 'wlan0', NOW() - INTERVAL '1 hour'),
('openwrt-device-003', 'CC:DD:EE:FF:GG:02', 65536000, 32768000, 18750, 9375, 'wlan0', NOW() - INTERVAL '2 hours');

-- Sample Revenue Analytics (today's data)
INSERT INTO revenue_analytics (hardware_id, date, total_revenue, total_sessions, total_minutes, coins_inserted, average_session_duration, peak_hours) VALUES
('openwrt-device-001', CURRENT_DATE, 150.00, 25, 1800, 150, 72, '[{"hour": 9, "sessions": 5}, {"hour": 12, "sessions": 8}, {"hour": 18, "sessions": 7}]'),
('openwrt-device-002', CURRENT_DATE, 95.00, 18, 1080, 95, 60, '[{"hour": 10, "sessions": 3}, {"hour": 14, "sessions": 6}, {"hour": 19, "sessions": 5}]'),
('openwrt-device-003', CURRENT_DATE, 75.00, 12, 900, 75, 75, '[{"hour": 8, "sessions": 2}, {"hour": 13, "sessions": 4}, {"hour": 20, "sessions": 3}]');

-- Sample System Logs
INSERT INTO system_logs (hardware_id, log_level, log_type, message, metadata, timestamp) VALUES
('openwrt-device-001', 'info', 'session', 'New session started', '{"mac": "AA:BB:CC:DD:EE:04", "session_uuid": "session-uuid-008", "coins": 3}', NOW() - INTERVAL '10 minutes'),
('openwrt-device-001', 'info', 'device', 'Device heartbeat received', '{"cpu": 45.2, "memory": 68.5, "uptime": 86400}', NOW() - INTERVAL '5 minutes'),
('openwrt-device-001', 'warning', 'network', 'High CPU usage detected', '{"cpu": 85.3, "threshold": 80}', NOW() - INTERVAL '15 minutes'),

('openwrt-device-002', 'info', 'session', 'Session paused by user', '{"mac": "BB:CC:DD:EE:FF:02", "session_uuid": "session-uuid-005", "remaining_time": 9000}', NOW() - INTERVAL '8 minutes'),
('openwrt-device-002', 'error', 'network', 'WAN connection lost', '{"interface": "eth1", "duration": 30}', NOW() - INTERVAL '20 minutes'),

('openwrt-device-003', 'info', 'device', 'Configuration updated', '{"setting": "minutes_per_peso", "old_value": 12, "new_value": 15}', NOW() - INTERVAL '12 minutes'),
('openwrt-device-003', 'info', 'session', 'Session expired', '{"mac": "CC:DD:EE:FF:GG:03", "session_uuid": "session-uuid-expired", "duration": 3600}', NOW() - INTERVAL '25 minutes');

-- Test queries to verify data integrity
-- SELECT * FROM dashboard_summary;
-- SELECT * FROM traffic_summary;
-- SELECT * FROM centralized_sessions WHERE is_active = true;
-- SELECT * FROM device_status ORDER BY last_heartbeat DESC;
-- SELECT * FROM revenue_analytics WHERE date = CURRENT_DATE;