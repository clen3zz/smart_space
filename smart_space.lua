local mp = require 'mp'

-- === 用户自定义参数 ===
local hold_threshold = 0.20     -- 长按判定阈值
local target_speed = 2.0        -- 目标倍速
local speed_step_per_frame = 0.05 -- 【核心】每一帧增加的速度值
local max_frequency = 180       -- 【核心】脚本工作频率上限 (Hz)

-- === 计算常量 ===
local min_delay = 1 / max_frequency -- 最小间隔 (约 0.0055秒)

-- === 内部变量 ===
local delay_timer = nil   -- 长按判定计时器
local ramp_timer = nil    -- 变速递归计时器
local is_held = false     -- 是否处于长按状态
local saved_speed = 1.0   -- 记忆原始速度
local active_target = 1.0 -- 当前正在前往的目标速度

-- 动态变速核心函数 (Recursive Loop)
function process_frame_ramp()
    -- 1. 获取当前状态
    local current_speed = mp.get_property_number("speed")
    local fps = mp.get_property_number("container-fps") or 24 -- 获取FPS，拿不到默认24
    
    -- 2. 计算与目标的差值
    local diff = active_target - current_speed
    
    -- 3. 判断是否到达目标 (吸附逻辑)
    if math.abs(diff) < 0.001 then
        mp.set_property("speed", active_target)
        ramp_timer = nil
        return -- 结束递归
    end
    
    -- 4. 计算下一级速度
    local next_speed
    if math.abs(diff) <= speed_step_per_frame then
        next_speed = active_target
    else
        local direction = diff > 0 and 1 or -1
        next_speed = current_speed + (speed_step_per_frame * direction)
    end
    
    -- 5. 执行变速
    mp.set_property("speed", next_speed)
    
    -- 6. 【核心算法】计算下一帧到来的物理时间
    -- 公式：时间 = 1 / (帧率 * 速度)
    local theoretical_delay = 1 / (fps * next_speed)
    
    -- 7. 频率限制 (Clamping)
    -- 如果计算出的时间短于 1/180秒，则强制等待 1/180秒
    local actual_delay = math.max(min_delay, theoretical_delay)
    
    -- 8. 递归调用：设置定时器，在 calculated_delay 后再次执行自己
    ramp_timer = mp.add_timeout(actual_delay, process_frame_ramp)
end

function start_ramp(final_value)
    active_target = final_value
    
    -- 如果计时器已经在跑，只需更新 active_target，它下次循环会自动转向
    -- 如果没在跑，则立即启动
    if not ramp_timer then
        process_frame_ramp()
    end
end

function on_key_event(table)
    if table.event == "down" then
        -- 按下：启动长按判定
        delay_timer = mp.add_timeout(hold_threshold, function()
            is_held = true
            saved_speed = mp.get_property_number("speed")
            
            -- 只要不等于目标，就启动变速
            if math.abs(saved_speed - target_speed) > 0.01 then
                mp.osd_message("▶▶", 2)
                start_ramp(target_speed)
            end
        end)
    elseif table.event == "up" then
        -- 松开
        if delay_timer then delay_timer:kill() end
        
        if is_held then
            -- 长按结束：基于同样的物理模型平滑恢复
            start_ramp(saved_speed)
            is_held = false
            mp.osd_message("", 0)
        else
            -- 短按：暂停/播放
            -- 确保停止任何正在进行的变速逻辑，保持清爽
            if ramp_timer then ramp_timer:kill() ramp_timer = nil end
            
            mp.command("cycle pause")
            mp.command('show-text "${?pause==yes:暂停}${?pause==no:播放}"')
        end
    end
end

mp.add_key_binding(nil, "smart_space", on_key_event, {complex=true})
