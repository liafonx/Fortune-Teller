local M = {}

M._prefix = "[FT]"
M._debug_mode = false

M._LEVELS = {
    error = true,
    warning = true,
    info = true,
    debug = true,
}

local function should_log(level)
    if not level or not M._LEVELS[level] then
        return true
    end

    if level == "error" or level == "warning" then
        return true
    end

    if M._debug_mode then
        return true
    end

    if rawget(_G, "FT_FORESEE")
        and _G.FT_FORESEE.config
        and _G.FT_FORESEE.config.debug_mode then
        return true
    end

    return false
end

function M.set_debug_mode(enabled)
    M._debug_mode = not not enabled
end

function M.create(module_name)
    return function(level, msg)
        if not should_log(level) then
            return
        end

        local full_msg
        if module_name and module_name ~= "" then
            if level and level ~= "" then
                full_msg = M._prefix .. "[" .. module_name .. "][" .. tostring(level) .. "] " .. tostring(msg)
            else
                full_msg = M._prefix .. "[" .. module_name .. "] " .. tostring(msg)
            end
        else
            full_msg = M._prefix .. " " .. tostring(msg)
        end

        pcall(print, full_msg)
    end
end

function M.log(level, msg)
    if not should_log(level) then
        return
    end

    local full_msg
    if level and level ~= "" then
        full_msg = M._prefix .. "[" .. tostring(level) .. "] " .. tostring(msg)
    else
        full_msg = M._prefix .. " " .. tostring(msg)
    end

    pcall(print, full_msg)
end

return M
