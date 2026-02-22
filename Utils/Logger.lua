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

local function format_and_print(module_name, level, msg)
    if type(msg) == 'function' then
        msg = msg()
    end

    local parts = {M._prefix}
    if module_name and module_name ~= "" then
        parts[#parts + 1] = "[" .. module_name .. "]"
    end
    if level and level ~= "" then
        parts[#parts + 1] = "[" .. tostring(level) .. "]"
    end
    parts[#parts + 1] = " " .. tostring(msg)

    pcall(print, table.concat(parts))
end

function M.create(module_name)
    return function(level, msg)
        if not should_log(level) then
            return
        end
        format_and_print(module_name, level, msg)
    end
end

function M.log(level, msg)
    if not should_log(level) then
        return
    end
    format_and_print(nil, level, msg)
end

return M
