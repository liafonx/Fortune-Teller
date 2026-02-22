if rawget(_G, 'FT_FORESEE_INSTALLED') then
    return
end
FT_FORESEE_INSTALLED = true

local FT = rawget(_G, 'FT_FORESEE') or {}
_G.FT_FORESEE = FT
FT.config = FT.config or {}
FT.modules = FT.modules or {}

local function load_module(path)
    local chunk, err = SMODS.load_file(path)
    assert(chunk, err or ('failed to load module: ' .. tostring(path)))
    return chunk()
end

FT.load_module = FT.load_module or load_module

local config_init = FT.load_module('Core/config_setup.lua')
if type(config_init) == 'function' then
    config_init(FT)
end

local Logger = FT.load_module('Utils/Logger.lua')
FT.Logger = Logger
if FT.config_api and FT.config_api.apply_logging then
    FT.config_api.apply_logging()
elseif FT.Logger and FT.Logger.set_debug_mode then
    FT.Logger.set_debug_mode(FT.config and FT.config.debug_mode)
end

local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Main')) or function() end

local module_paths = {
    'Utils/utils.lua',
    'Core/run_state_hooks.lua',
    'Core/predictors/engine.lua',
    'UI/preview_cards.lua',
    'Core/ui_hooks.lua',
}

local function init_module(path)
    log('debug', 'Loading module: ' .. tostring(path))
    local init = FT.load_module(path)
    if type(init) ~= 'function' then
        log('error', 'Module did not return init function: ' .. tostring(path))
        return
    end

    init(FT)
    FT.modules[path] = true
    log('info', 'Loaded module: ' .. path)
end

log('info', 'Initializing Fortune Teller modules')

for _, path in ipairs(module_paths) do
    init_module(path)
end

log('info', 'Fortune Teller initialization complete')
