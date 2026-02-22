return function(FT)
    if not (SMODS and SMODS.current_mod) then
        return
    end

    local cfg = FT.config

    local fallback_card_entries = (FT.config_meta and FT.config_meta.card_entries) or {}

    local function loc(key, fallback)
        if not localize then
            return fallback or key
        end

        local ok, value = pcall(localize, key)
        if ok and type(value) == 'string' and value ~= '' and value ~= key then
            return value
        end
        return fallback or key
    end

    local function card_name(entry)
        if not (entry and entry.key) then
            return entry and entry.fallback or ''
        end

        local center = G and G.P_CENTERS and G.P_CENTERS[entry.key]
        local set_name = entry.set or (center and center.set)
        if not set_name then
            return entry.fallback or entry.key
        end

        if not localize then
            return entry.fallback or entry.key
        end

        local ok, value = pcall(localize, {
            type = 'name_text',
            set = set_name,
            key = entry.key,
        })
        if ok and type(value) == 'string' and value ~= '' and value ~= 'ERROR' then
            return value
        end
        return entry.fallback or entry.key
    end

    local function header(text)
        return {
            n = G.UIT.R,
            config = {align = 'cm', padding = 0.05},
            nodes = {
                {
                    n = G.UIT.T,
                    config = {text = text, colour = G.C.UI.TEXT_LIGHT, scale = 0.4},
                },
            },
        }
    end

    local function toggle_row(label, ref_table, ref_value, callback, opts)
        opts = opts or {}
        local col_w = opts.col_w or 2.35
        return {
            n = G.UIT.R,
            config = {align = 'cr', padding = opts.row_padding or 0.01},
            nodes = {
                {
                    n = G.UIT.C,
                    config = {align = 'tr', minw = col_w, padding = 0},
                    nodes = {
                        create_toggle({
                            label = label,
                            ref_table = ref_table,
                            ref_value = ref_value,
                            callback = callback,
                            w = opts.w or col_w,
                            scale = opts.scale or 0.8,
                            label_scale = opts.label_scale or 0.35,
                        }),
                    },
                },
            },
        }
    end

    local function build_runtime_card_entries()
        local routes_by_key = FT.predictors and FT.predictors.routes_by_key or {}
        local entries = {}
        for key, _ in pairs(routes_by_key) do
            local center = G and G.P_CENTERS and G.P_CENTERS[key]
            local set_name = center and center.set
            local group = (set_name == 'Tarot' and 'Tarot')
                or (set_name == 'Spectral' and 'Spectral')
                or (set_name == 'Joker' and 'Joker')
                or (key and key:sub(1, 2) == 'j_' and 'Joker')
                or 'Other'

            entries[#entries + 1] = {
                key = key,
                set = set_name,
                group = group,
                order = (center and center.order) or 9999,
                fallback = (center and center.name) or key,
            }
        end

        if #entries < 1 then
            for _, entry in ipairs(fallback_card_entries) do
                entries[#entries + 1] = {
                    key = entry.key,
                    set = entry.set,
                    group = entry.group or 'Other',
                    order = entry.order or 9999,
                    fallback = entry.fallback or entry.key,
                }
            end
        end

        local group_order = {Tarot = 1, Spectral = 2, Joker = 3, Other = 4}
        table.sort(entries, function(a, b)
            local ga = group_order[a.group] or 99
            local gb = group_order[b.group] or 99
            if ga ~= gb then
                return ga < gb
            end
            if (a.order or 9999) ~= (b.order or 9999) then
                return (a.order or 9999) < (b.order or 9999)
            end
            return tostring(a.key) < tostring(b.key)
        end)

        for _, entry in ipairs(entries) do
            if cfg.cards.enabled_by_key[entry.key] == nil then
                cfg.cards.enabled_by_key[entry.key] = true
            end
        end

        return entries
    end

    local function group_entries(card_entries, group_name)
        local out = {}
        for _, entry in ipairs(card_entries) do
            if entry.group == group_name then
                out[#out + 1] = entry
            end
        end
        return out
    end

    local function card_group_column(card_entries, group_name, title_key, title_fallback, split_cols)
        local rows = {header(loc(title_key, title_fallback))}
        local entries = group_entries(card_entries, group_name)
        split_cols = split_cols or 1
        local base_toggle_opts = {w = 2.1, col_w = 2.1, scale = 0.72, label_scale = 0.32, row_padding = 0.003}

        if split_cols > 1 and #entries > 1 then
            local per_col = math.ceil(#entries / split_cols)
            local split_row = {n = G.UIT.R, config = {align = 'tm', padding = 0.01}, nodes = {}}

            for col = 1, split_cols do
                local col_nodes = {}
                local start_idx = (col - 1) * per_col + 1
                local end_idx = math.min(#entries, start_idx + per_col - 1)
                for i = start_idx, end_idx do
                    col_nodes[#col_nodes + 1] = toggle_row(
                        card_name(entries[i]),
                        cfg.cards.enabled_by_key,
                        entries[i].key,
                        nil,
                        base_toggle_opts
                    )
                end
                split_row.nodes[#split_row.nodes + 1] = {
                    n = G.UIT.C,
                    config = {align = 'tm', padding = 0.01, minw = 2.25},
                    nodes = col_nodes,
                }
            end
            rows[#rows + 1] = split_row
        else
            for _, entry in ipairs(entries) do
                rows[#rows + 1] = toggle_row(
                    card_name(entry),
                    cfg.cards.enabled_by_key,
                    entry.key,
                    nil,
                    base_toggle_opts
                )
            end
        end

        return {
            n = G.UIT.C,
            config = {align = 'tm', padding = 0.03, minw = 2.2},
            nodes = rows,
        }
    end

    local function build_tarot_seal_column(card_entries)
        local rows = {header(loc('ft_cfg_group_tarot', 'Tarot'))}
        local tarot_entries = group_entries(card_entries, 'Tarot')
        local base_toggle_opts = {w = 2.1, col_w = 2.1, scale = 0.72, label_scale = 0.32, row_padding = 0.003}

        for _, entry in ipairs(tarot_entries) do
            rows[#rows + 1] = toggle_row(
                card_name(entry),
                cfg.cards.enabled_by_key,
                entry.key,
                nil,
                base_toggle_opts
            )
        end

        rows[#rows + 1] = header(loc('ft_cfg_group_seal', 'Seal'))
        rows[#rows + 1] = toggle_row(
            loc('ft_cfg_purple_seal_preview', 'Show Purple Seal hand preview sequence'),
            cfg.cards,
            'show_purple_seal_preview',
            nil,
            base_toggle_opts
        )

        return {
            n = G.UIT.C,
            config = {align = 'tm', padding = 0.03, minw = 2.2},
            nodes = rows,
        }
    end

    local function build_joker_special_column()
        local special_toggle_opts = {w = 2.2, col_w = 2.2, scale = 0.72, label_scale = 0.32, row_padding = 0.003}
        return {
            n = G.UIT.C,
            config = {align = 'tm', padding = 0.03, minw = 2.3},
            nodes = {
                header(loc('ft_cfg_joker_special', 'Joker Special')),
                toggle_row(
                    loc('ft_cfg_invisible_pretrigger', 'Show Invisible Joker copy before ready'),
                    cfg.cards,
                    'show_invisible_pretrigger',
                    nil,
                    special_toggle_opts
                ),
                toggle_row(
                    loc('ft_cfg_show_misprint_draw_preview', 'Show next draw after discard'),
                    cfg.cards,
                    'show_misprint_draw_preview',
                    nil,
                    special_toggle_opts
                ),
            },
        }
    end

    local cached_card_entries = nil
    local function get_card_entries()
        if not cached_card_entries then
            cached_card_entries = build_runtime_card_entries()
        end
        return cached_card_entries
    end

    local function build_cards_tab()
        local card_entries = get_card_entries()
        return {
            n = G.UIT.ROOT,
            config = {r = 0.1, minw = 8.4, align = 'tm', padding = 0.12, colour = G.C.BLACK},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {align = 'cm', padding = 0.04},
                    nodes = {
                        {
                            n = G.UIT.T,
                            config = {
                                text = loc('ft_cfg_cards_hint', 'Enable or disable Fortune Teller popup replacement per card'),
                                colour = G.C.UI.TEXT_LIGHT,
                                scale = 0.3,
                            },
                        },
                    },
                },
                {
                    n = G.UIT.R,
                    config = {align = 'tm', padding = 0.02},
                    nodes = {
                        build_tarot_seal_column(card_entries),
                        card_group_column(card_entries, 'Spectral', 'ft_cfg_group_spectral', 'Spectral', 2),
                    },
                },
            },
        }
    end

    local function build_joker_tab()
        local card_entries = get_card_entries()
        return {
            n = G.UIT.ROOT,
            config = {r = 0.1, minw = 8.4, align = 'tm', padding = 0.12, colour = G.C.BLACK},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {align = 'cm', padding = 0.04},
                    nodes = {
                        {
                            n = G.UIT.T,
                            config = {
                                text = loc('ft_cfg_cards_hint', 'Enable or disable Fortune Teller popup replacement per card'),
                                colour = G.C.UI.TEXT_LIGHT,
                                scale = 0.3,
                            },
                        },
                    },
                },
                {
                    n = G.UIT.R,
                    config = {align = 'tm', padding = 0.02},
                    nodes = {
                        card_group_column(card_entries, 'Joker', 'ft_cfg_group_joker', 'Joker', 2),
                        build_joker_special_column(),
                    },
                },
            },
        }
    end

    local function build_display_tab()
        return {
            n = G.UIT.ROOT,
            config = {r = 0.1, minw = 9, align = 'tm', padding = 0.2, colour = G.C.BLACK},
            nodes = {
                header(loc('ft_cfg_tab_display', 'Display')),
                toggle_row(
                    loc('ft_cfg_show_main_popup_name', 'Show card name in main popup'),
                    cfg.display,
                    'show_main_popup_name',
                    nil,
                    {w = 2.35, col_w = 2.35}
                ),
                toggle_row(
                    loc('ft_cfg_show_effect_popup', 'Show small effect popup'),
                    cfg.display,
                    'show_effect_popup',
                    nil,
                    {w = 2.35, col_w = 2.35}
                ),
                toggle_row(
                    loc('ft_cfg_hide_all_labels', 'Hide all card labels'),
                    cfg.display,
                    'hide_all_labels',
                    nil,
                    {w = 2.35, col_w = 2.35}
                ),
                toggle_row(
                    loc('ft_cfg_prediction_timing_always', 'Show predictions outside trigger phase'),
                    cfg.prediction,
                    'timing_always',
                    nil,
                    {w = 2.35, col_w = 2.35}
                ),
            },
        }
    end

    local function build_logging_tab()
        local function on_verbose_toggle(enabled)
            cfg.logging.verbose = not not enabled
            cfg.debug_mode = cfg.logging.verbose
            if FT.config_api and FT.config_api.apply_logging then
                FT.config_api.apply_logging()
            end
        end

        return {
            n = G.UIT.ROOT,
            config = {r = 0.1, minw = 9, align = 'tm', padding = 0.2, colour = G.C.BLACK},
            nodes = {
                header(loc('ft_cfg_tab_logging', 'Logging')),
                toggle_row(
                    loc('ft_cfg_logging_verbose', 'Enable info and debug logs'),
                    cfg.logging,
                    'verbose',
                    on_verbose_toggle,
                    {w = 2.35, col_w = 2.35}
                ),
            },
        }
    end

    SMODS.current_mod.config_tab = build_cards_tab
    SMODS.current_mod.extra_tabs = function()
        return {
            {
                label = loc('ft_cfg_tab_joker', 'Joker'),
                tab_definition_function = build_joker_tab,
            },
            {
                label = loc('ft_cfg_tab_display', 'Display'),
                tab_definition_function = build_display_tab,
            },
            {
                label = loc('ft_cfg_tab_logging', 'Logging'),
                tab_definition_function = build_logging_tab,
            },
        }
    end
end
