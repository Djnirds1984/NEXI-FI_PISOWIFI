local pisowifi=require("luci.model.pisowifi.pisowifi")

local M={}

function M.get_sessions()
    return pisowifi.get_sessions()
end

function M.get_session_details(session_id)
    return pisowifi.get_session_details(session_id)
end

function M.disconnect_user(session_id)
    return pisowifi.disconnect_user(session_id)
end

function M.disconnect_all_users()
    return pisowifi.disconnect_all_users()
end

function M.get_user_stats()
    return pisowifi.get_user_stats()
end

function M.get_connection_logs()
    return pisowifi.get_connection_logs()
end

function M.get_revenue_data(days)
    return pisowifi.get_revenue_data(days)
end

function M.get_usage_data(days)
    return pisowifi.get_usage_data(days)
end

function M.get_user_activity(days)
    return pisowifi.get_user_activity(days)
end

function M.generate_vouchers(count,prefix,duration,segment,price)
    return pisowifi.generate_vouchers(count,prefix,duration,segment,price)
end

function M.get_vouchers()
    return pisowifi.get_vouchers()
end

function M.get_voucher_stats()
    return pisowifi.get_voucher_stats()
end

function M.delete_voucher(code)
    return pisowifi.delete_voucher(code)
end

function M.validate_voucher(code)
    return pisowifi.validate_voucher(code)
end

return M