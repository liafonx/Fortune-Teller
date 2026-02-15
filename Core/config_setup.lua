return function(FT)
    local defaults = {
        cards = {
            enabled_by_key = {
                c_wheel_of_fortune = true,
                c_judgement = true,
                c_soul = true,
                c_wraith = true,
                c_emperor = true,
                c_high_priestess = true,

                c_aura = true,
                c_sigil = true,
                c_ouija = true,
                c_hex = true,
                c_ectoplasm = true,
                c_ankh = true,
                c_familiar = true,
                c_grim = true,
                c_incantation = true,
                c_immolate = true,

                j_invisible = true,
            },
            show_invisible_pretrigger = false,
            show_purple_seal_preview = true,
        },
        display = {
            show_main_popup_name = false,
            show_effect_popup = true,
            show_type_label = true,
            hide_all_labels = false,
        },
        logging = {
            verbose = false,
        },
        debug_mode = false,
    }

    local card_entries = {
        {key = 'c_wheel_of_fortune', group = 'Tarot', fallback = 'Wheel of Fortune'},
        {key = 'c_judgement', group = 'Tarot', fallback = 'Judgement'},
        {key = 'c_soul', group = 'Tarot', fallback = 'The Soul'},
        {key = 'c_wraith', group = 'Tarot', fallback = 'Wraith'},
        {key = 'c_emperor', group = 'Tarot', fallback = 'The Emperor'},
        {key = 'c_high_priestess', group = 'Tarot', fallback = 'The High Priestess'},

        {key = 'c_aura', group = 'Spectral', fallback = 'Aura'},
        {key = 'c_sigil', group = 'Spectral', fallback = 'Sigil'},
        {key = 'c_ouija', group = 'Spectral', fallback = 'Ouija'},
        {key = 'c_hex', group = 'Spectral', fallback = 'Hex'},
        {key = 'c_ectoplasm', group = 'Spectral', fallback = 'Ectoplasm'},
        {key = 'c_ankh', group = 'Spectral', fallback = 'Ankh'},
        {key = 'c_familiar', group = 'Spectral', fallback = 'Familiar'},
        {key = 'c_grim', group = 'Spectral', fallback = 'Grim'},
        {key = 'c_incantation', group = 'Spectral', fallback = 'Incantation'},
        {key = 'c_immolate', group = 'Spectral', fallback = 'Immolate'},

        {key = 'j_invisible', group = 'Joker', fallback = 'Invisible Joker'},
    }

    local function deep_copy(v)
        if type(v) ~= 'table' then
            return v
        end

        local out = {}
        for k, x in pairs(v) do
            out[k] = deep_copy(x)
        end
        return out
    end

    local function deep_fill(target, template)
        if type(target) ~= 'table' or type(template) ~= 'table' then
            return
        end

        for k, v in pairs(template) do
            if target[k] == nil then
                target[k] = deep_copy(v)
            elseif type(target[k]) == 'table' and type(v) == 'table' then
                deep_fill(target[k], v)
            end
        end
    end

    local function normalize_config(cfg)
        cfg.cards = cfg.cards or {}
        cfg.cards.enabled_by_key = cfg.cards.enabled_by_key or {}
        cfg.display = cfg.display or {}
        cfg.logging = cfg.logging or {}

        local had_verbose_flag = cfg.logging.verbose ~= nil
        local had_hide_all_labels = cfg.display.hide_all_labels ~= nil
        deep_fill(cfg, defaults)

        if not had_verbose_flag and cfg.debug_mode ~= nil then
            cfg.logging.verbose = not not cfg.debug_mode
        end

        if not had_hide_all_labels then
            cfg.display.hide_all_labels = false
        end

        cfg.display.hide_all_labels = not not cfg.display.hide_all_labels
        cfg.display.show_type_label = not cfg.display.hide_all_labels

        cfg.logging.verbose = not not cfg.logging.verbose
        cfg.debug_mode = cfg.logging.verbose
    end

    local base_config = nil
    if SMODS and SMODS.current_mod then
        SMODS.current_mod.config = SMODS.current_mod.config or {}
        base_config = SMODS.current_mod.config
    elseif type(FT.config) == 'table' then
        base_config = FT.config
    else
        base_config = {}
    end

    normalize_config(base_config)

    FT.config = base_config
    if SMODS and SMODS.current_mod then
        SMODS.current_mod.config = base_config
    end

    FT.config_meta = FT.config_meta or {}
    FT.config_meta.card_entries = card_entries

    FT.config_api = FT.config_api or {}
    local api = FT.config_api

    function api.is_card_enabled(center_key)
        if not center_key then
            return false
        end

        local per_card = FT.config and FT.config.cards and FT.config.cards.enabled_by_key
        if per_card and per_card[center_key] ~= nil then
            return not not per_card[center_key]
        end
        return true
    end

    function api.show_invisible_pretrigger()
        return not not (FT.config and FT.config.cards and FT.config.cards.show_invisible_pretrigger)
    end

    function api.show_purple_seal_preview()
        return not not (FT.config and FT.config.cards and FT.config.cards.show_purple_seal_preview)
    end

    function api.show_main_popup_name()
        return not not (FT.config and FT.config.display and FT.config.display.show_main_popup_name)
    end

    function api.show_effect_popup()
        return not not (FT.config and FT.config.display and FT.config.display.show_effect_popup)
    end

    function api.show_type_label()
        return not api.hide_all_labels()
    end

    function api.hide_all_labels()
        return not not (FT.config and FT.config.display and FT.config.display.hide_all_labels)
    end

    function api.verbose_logging()
        return not not (FT.config and FT.config.logging and FT.config.logging.verbose)
    end

    function api.apply_logging()
        local verbose = api.verbose_logging()

        if FT.config then
            FT.config.debug_mode = verbose
            FT.config.logging = FT.config.logging or {}
            FT.config.logging.verbose = verbose
        end

        if FT.Logger and FT.Logger.set_debug_mode then
            FT.Logger.set_debug_mode(verbose)
        end
    end

    local setup_config_ui = FT.load_module('UI/config_tabs.lua')
    if type(setup_config_ui) == 'function' then
        setup_config_ui(FT)
    end
end
