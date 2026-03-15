-- License RPC Functions for PisoWifi OpenWRT

-- Function to check license status
CREATE OR REPLACE FUNCTION check_license(hardware_id_param TEXT)
RETURNS JSON AS $$
DECLARE
    license_record RECORD;
    result JSON;
BEGIN
    -- Check if license exists
    SELECT * INTO license_record 
    FROM pisowifi_openwrt 
    WHERE hardware_id = hardware_id_param;
    
    IF NOT FOUND THEN
        result := json_build_object(
            'exists', false,
            'status', 'no_license',
            'message', 'No license found for this hardware'
        );
    ELSE
        -- Check if license is valid
        IF license_record.status = 'active' THEN
            result := json_build_object(
                'exists', true,
                'status', 'active',
                'license_data', row_to_json(license_record),
                'message', 'License is active'
            );
        ELSIF license_record.status = 'trial' THEN
            IF license_record.expires_at IS NULL OR license_record.expires_at > NOW() THEN
                result := json_build_object(
                    'exists', true,
                    'status', 'trial',
                    'license_data', row_to_json(license_record),
                    'message', 'Trial license is valid',
                    'days_remaining', CASE 
                        WHEN license_record.expires_at IS NOT NULL 
                        THEN EXTRACT(DAY FROM (license_record.expires_at - NOW()))::INTEGER
                        ELSE 7
                    END
                );
            ELSE
                result := json_build_object(
                    'exists', true,
                    'status', 'expired',
                    'license_data', row_to_json(license_record),
                    'message', 'Trial license has expired'
                );
            END IF;
        ELSIF license_record.status = 'expired' THEN
            result := json_build_object(
                'exists', true,
                'status', 'expired',
                'license_data', row_to_json(license_record),
                'message', 'License has expired'
            );
        ELSE
            result := json_build_object(
                'exists', true,
                'status', 'inactive',
                'license_data', row_to_json(license_record),
                'message', 'License is inactive'
            );
        END IF;
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to activate license with key
CREATE OR REPLACE FUNCTION activate_license(hardware_id_param TEXT, license_key_param TEXT, ip_address_param TEXT DEFAULT NULL)
RETURNS JSON AS $$
DECLARE
    license_record RECORD;
    vendor_uuid_result UUID;
    result JSON;
BEGIN
    -- Check if license key exists and is valid
    SELECT * INTO license_record 
    FROM pisowifi_openwrt 
    WHERE license_key = license_key_param;
    
    IF NOT FOUND THEN
        result := json_build_object(
            'success', false,
            'error', 'Invalid license key'
        );
    ELSE
        -- Check if license is already active
        IF license_record.status = 'active' THEN
            result := json_build_object(
                'success', false,
                'error', 'License key is already active'
            );
        ELSE
            -- Generate vendor UUID
            vendor_uuid_result := gen_random_uuid();
            
            -- Update license status
            UPDATE pisowifi_openwrt 
            SET 
                status = 'active',
                hardware_id = hardware_id_param,
                vendor_uuid = vendor_uuid_result,
                activated_at = NOW(),
                updated_at = NOW()
            WHERE license_key = license_key_param;
            
            -- Log activation
            INSERT INTO pisowifi_license_activations (license_id, hardware_id, ip_address)
            VALUES (license_record.id, hardware_id_param, ip_address_param::INET);
            
            result := json_build_object(
                'success', true,
                'vendor_uuid', vendor_uuid_result,
                'message', 'License activated successfully'
            );
        END IF;
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions for RPC functions
GRANT EXECUTE ON FUNCTION check_license(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION activate_license(TEXT, TEXT, TEXT) TO anon;

-- Create some sample license keys (for testing)
INSERT INTO pisowifi_openwrt (license_key, status) VALUES 
('PISOWIFI-PRO-001', 'inactive'),
('PISOWIFI-PRO-002', 'inactive'),
('PISOWIFI-PRO-003', 'inactive'),
('PISOWIFI-PRO-004', 'inactive'),
('PISOWIFI-PRO-005', 'inactive')
ON CONFLICT (license_key) DO NOTHING;