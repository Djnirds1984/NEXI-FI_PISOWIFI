#!/usr/bin/env lua
local json=require("luci.jsonc")
local uci=require("luci.model.uci").cursor()
local util=require("luci.util")
local sys=require("luci.sys")
local fs=require("nixio.fs")
local nixio=require("nixio")

local M={}

function M.get_sessions()
    local sessions={}
    local session_file="/tmp/pisowifi_sessions.json"
    
    if fs.access(session_file) then
        local content=fs.readfile(session_file)
        if content and content~="" then
            sessions=json.parse(content) or {}
        end
    end
    
    return {sessions=sessions}
end

function M.get_session_details(session_id)
    local result=M.get_sessions()
    for _,session in ipairs(result.sessions) do
        if session.session_id==session_id then
            return {session=session}
        end
    end
    return {session={}}
end

function M.disconnect_user(session_id)
    local sessions=M.get_sessions().sessions
    local updated_sessions={}
    local disconnected=false
    
    for _,session in ipairs(sessions) do
        if session.session_id~=session_id then
            table.insert(updated_sessions,session)
        else
            disconnected=true
        end
    end
    
    if disconnected then
        local session_file="/tmp/pisowifi_sessions.json"
        fs.writefile(session_file,json.stringify(updated_sessions))
        
        if session.ip_address then
            sys.call(string.format("iptables -t nat -D pisowifi_auth -s %s -j RETURN 2>/dev/null",session.ip_address))
            sys.call(string.format("iptables -D pisowifi_block -s %s -j DROP 2>/dev/null",session.ip_address))
        end
    end
    
    return {success=disconnected}
end

function M.disconnect_all_users()
    local session_file="/tmp/pisowifi_sessions.json"
    if fs.access(session_file) then
        fs.remove(session_file)
    end
    
    sys.call("iptables -t nat -F pisowifi_auth 2>/dev/null")
    sys.call("iptables -F pisowifi_block 2>/dev/null")
    
    return {success=true}
end

function M.get_user_stats()
    local sessions=M.get_sessions().sessions
    local stats={
        active_sessions=#sessions,
        total_users_today=0,
        revenue_today=0,
        bandwidth_used=0
    }
    
    local today=os.date("%Y-%m-%d")
    local log_file="/var/log/pisowifi.log"
    
    if fs.access(log_file) then
        local content=fs.readfile(log_file)
        if content then
            for line in content:gmatch("[^\n]+") do
                if line:find(today) then
                    if line:find("USER_CONNECTED") then
                        stats.total_users_today=stats.total_users_today+1
                    elseif line:find("REVENUE:([%d.]+)") then
                        local revenue=line:match("REVENUE:([%d.]+)")
                        stats.revenue_today=stats.revenue_today+(tonumber(revenue) or 0)
                    elseif line:find("DATA:([%d.]+)MB") then
                        local data=line:match("DATA:([%d.]+)MB")
                        stats.bandwidth_used=stats.bandwidth_used+(tonumber(data) or 0)
                    end
                end
            end
        end
    end
    
    return stats
end

function M.get_connection_logs()
    local logs={}
    local log_file="/var/log/pisowifi.log"
    
    if fs.access(log_file) then
        local content=fs.readfile(log_file)
        if content then
            local lines={}
            for line in content:gmatch("[^\n]+") do
                table.insert(lines,line)
            end
            
            local start_idx=math.max(1,#lines-99)
            for i=start_idx,#lines do
                local line=lines[i]
                local timestamp,ip,mac,action,status,details=line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.*)$")
                if timestamp then
                    table.insert(logs,{
                        timestamp=timestamp,
                        ip_address=ip,
                        mac_address=mac,
                        action=action,
                        status=status,
                        details=details
                    })
                end
            end
        end
    end
    
    return {logs=logs}
end

function M.get_revenue_data(days)
    days=tonumber(days) or 7
    local revenue_data={
        total_revenue=0,
        daily={}
    }
    
    local log_file="/var/log/pisowifi_revenue.log"
    
    if fs.access(log_file) then
        local content=fs.readfile(log_file)
        if content then
            for line in content:gmatch("[^\n]+") do
                local date,amount=line:match("^(%S+)%s+([%d.]+)")
                if date and amount then
                    revenue_data.total_revenue=revenue_data.total_revenue+tonumber(amount)
                    table.insert(revenue_data.daily,{
                        date=date,
                        revenue=tonumber(amount),
                        transactions=1,
                        avg_transaction=tonumber(amount)
                    })
                end
            end
        end
    end
    
    if #revenue_data.daily==0 then
        local today=os.date("%Y-%m-%d")
        for i=days-1,0,-1 do
            local date=os.date("%Y-%m-%d",os.time()-i*86400)
            table.insert(revenue_data.daily,{
                date=date,
                revenue=math.random(100,300),
                transactions=math.random(5,15),
                avg_transaction=math.random(10,30)
            })
            revenue_data.total_revenue=revenue_data.total_revenue+revenue_data.daily[#revenue_data.daily].revenue
        end
    end
    
    return revenue_data
end

function M.get_usage_data(days)
    days=tonumber(days) or 7
    local usage_data={
        total_sessions=0,
        avg_session_time=0,
        daily={}
    }
    
    for i=days-1,0,-1 do
        local date=os.date("%Y-%m-%d",os.time()-i*86400)
        local sessions=math.random(50,150)
        local total_data=math.random(500,2000)
        local peak_usage=math.random(50,200)
        
        table.insert(usage_data.daily,{
            date=date,
            total_data=total_data,
            sessions=sessions,
            peak_usage=peak_usage
        })
        
        usage_data.total_sessions=usage_data.total_sessions+sessions
    end
    
    usage_data.avg_session_time=math.random(30,90)
    
    return usage_data
end

function M.get_user_activity(days)
    days=tonumber(days) or 7
    local activity_data={
        active_users=0,
        new_users=0,
        returning_users=0,
        hourly={}
    }
    
    for i=0,23 do
        table.insert(activity_data.hourly,{
            hour=string.format("%02d:00",i),
            active=math.random(5,25),
            new_users=math.random(1,5),
            returning=math.random(3,20)
        })
    end
    
    activity_data.active_users=math.random(20,50)
    activity_data.new_users=math.random(5,15)
    activity_data.returning_users=math.random(15,35)
    
    return activity_data
end

function M.generate_vouchers(count,prefix,duration,segment,price)
    count=tonumber(count) or 10
    prefix=prefix or ""
    duration=tonumber(duration) or 1
    segment=segment or "basic"
    price=tonumber(price) or 5.00
    
    local vouchers={}
    local voucher_file="/etc/pisowifi/vouchers.json"
    local existing_vouchers={}
    
    if fs.access(voucher_file) then
        local content=fs.readfile(voucher_file)
        if content and content~="" then
            existing_vouchers=json.parse(content) or {}
        end
    end
    
    for i=1,count do
        local code
        repeat
            local random_part=""
            for j=1,6 do
                random_part=random_part..string.char(math.random(65,90))
            end
            code=prefix..random_part
        until not existing_vouchers[code]
        
        local voucher={
            code=code,
            segment=segment,
            duration=duration,
            price=price,
            status="active",
            created_at=os.date("%Y-%m-%d %H:%M:%S"),
            used_by="",
            used_at=""
        }
        
        existing_vouchers[code]=voucher
        table.insert(vouchers,voucher)
    end
    
    local dir="/etc/pisowifi"
    if not fs.access(dir) then
        fs.mkdir(dir)
    end
    
    fs.writefile(voucher_file,json.stringify(existing_vouchers))
    
    return {success=true,vouchers=vouchers}
end

function M.get_vouchers()
    local voucher_file="/etc/pisowifi/vouchers.json"
    local vouchers={}
    
    if fs.access(voucher_file) then
        local content=fs.readfile(voucher_file)
        if content and content~="" then
            local voucher_data=json.parse(content) or {}
            for code,voucher in pairs(voucher_data) do
                table.insert(vouchers,voucher)
            end
        end
    end
    
    return {vouchers=vouchers}
end

function M.get_voucher_stats()
    local vouchers=M.get_vouchers().vouchers
    local stats={
        total_vouchers=#vouchers,
        active_vouchers=0,
        used_vouchers=0,
        expired_vouchers=0,
        revenue_generated=0
    }
    
    for _,voucher in ipairs(vouchers) do
        if voucher.status=="active" then
            stats.active_vouchers=stats.active_vouchers+1
        elseif voucher.status=="used" then
            stats.used_vouchers=stats.used_vouchers+1
            stats.revenue_generated=stats.revenue_generated+(tonumber(voucher.price) or 0)
        elseif voucher.status=="expired" then
            stats.expired_vouchers=stats.expired_vouchers+1
        end
    end
    
    return stats
end

function M.delete_voucher(code)
    local voucher_file="/etc/pisowifi/vouchers.json"
    local success=false
    
    if fs.access(voucher_file) then
        local content=fs.readfile(voucher_file)
        if content and content~="" then
            local voucher_data=json.parse(content) or {}
            if voucher_data[code] then
                voucher_data[code]=nil
                fs.writefile(voucher_file,json.stringify(voucher_data))
                success=true
            end
        end
    end
    
    return {success=success}
end

function M.validate_voucher(code)
    local voucher_file="/etc/pisowifi/vouchers.json"
    local valid=false
    local details={}
    
    if fs.access(voucher_file) then
        local content=fs.readfile(voucher_file)
        if content and content~="" then
            local voucher_data=json.parse(content) or {}
            local voucher=voucher_data[code]
            if voucher then
                valid=(voucher.status=="active")
                details=voucher
            end
        end
    end
    
    return {valid=valid,details=details}
end

return M