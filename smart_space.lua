local mp = require 'mp'

-- === 用户自定义参数 ===
local hold_threshold = 0.20       -- 长按判定阈值
local target_speed = 2.0          -- 目标倍速
local update_interval = 0.05      -- 更新频率 0.05秒 (20Hz)
local speed_factor = 1.05         -- 【核心】每次增加 5% (即乘以 1.05)

-- === 内部变量 ===
local delay_timer = nil
local ramp_timer = nil
local is_held = false
local saved_speed = 1.0
local active_target = 1.0
local current_transition_speed = 1.0 

-- 变速处理函数 (乘法递增/递减)
function process_ramp_tick()
    -- 1. 获取当前状态与目标的偏差
    local diff = active_target - current_transition_speed
    
    -- 2. 判断是否足够接近目标 (吸附逻辑)
    -- 如果差距小于 0.01，直接到位并停止
    if math.abs(diff) < 0.01 then
        mp.set_property("speed", active_target)
        current_transition_speed = active_target
        ramp_timer = nil
        return 
    end
    
    -- 3. 计算下一帧速度 (核心修改)
    if active_target > current_transition_speed then
        -- 加速阶段：当前速度 * 1.05
        current_transition_speed = current_transition_speed * speed_factor
        -- 防止超调
        if current_transition_speed > active_target then 
            current_transition_speed = active_target 
        end
    else
        -- 减速阶段：当前速度 / 1.05 (平滑回落)
        current_transition_speed = current_transition_speed / speed_factor
        -- 防止超调
        if current_transition_speed < active_target then 
            current_transition_speed = active_target 
        end
    end
    
    -- 4. 执行变速
    mp.set_property("speed", current_transition_speed)
    
    -- 5. 继续循环
    ramp_timer = mp.add_timeout(update_interval, process_ramp_tick)
end

function start_ramp(final_value)
    active_target = final_value
    
    -- 获取当前实际速度作为起点
    current_transition_speed = mp.get_property_number("speed")
    
    -- 如果计时器没在跑，就启动它；如果在跑，上面的 logic 会自动处理 active_target 的变化
    if not ramp_timer then
        process_ramp_tick()
    end
end

function on_key_event(table)
    if table.event == "down" then
        delay_timer = mp.add_timeout(hold_threshold, function()
            is_held = true
            saved_speed = mp.get_property_number("speed")
            
            -- 只有当当前速度不等于目标速度时才启动
            if math.abs(saved_speed - target_speed) > 0.01 then
                mp.osd_message("▶▶", 2)
                start_ramp(target_speed)
            end
        end)
    elseif table.event == "up" then
        if delay_timer then delay_timer:kill() end
        
        if is_held then
            -- 长按结束：平滑恢复到记忆速度
            start_ramp(saved_speed)
            is_held = false
            mp.osd_message("", 0)
        else
            -- 短按：暂停/播放
            if ramp_timer then ramp_timer:kill() ramp_timer = nil end
            mp.command("cycle pause")
            mp.command('show-text "${?pause==yes:暂停}${?pause==no:播放}"')
        end
    end
end

mp.add_key_binding(nil, "smart_space", on_key_event, {complex=true})
