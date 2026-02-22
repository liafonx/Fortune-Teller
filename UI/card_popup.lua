return function(FT)
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('CardPopup')) or function() end
    local render = FT.load_module('UI/card_popup_render.lua')(FT)

    local CARD_SCALE = 0.56
    local DEFAULT_MINI_POPUP_MINW = 1.5
    local MAX_MINI_POPUP_MINW = 2

    local cached_layout = nil

    local function make_layout(cs)
        local k = cs / 0.56
        return {
            preview_w = (G and G.CARD_W and (G.CARD_W * cs)) or 0.56,
            preview_h = (G and G.CARD_H and (G.CARD_H * cs)) or 0.78,
            box_padding = 0.05 * k,
            panel_padding = 0.07 * k,
            badge_padding = 0.03 * k,
            frame_padding = 0.18 * k,
            two_side_gap = 0.085 * k,
            two_middle_gap = 0.02 * k,
            multi_gap = 0.05 * k,
            multi_side_gap = 0.1 * k,
            forecast_inner_pad = 0.04 * k,
            forecast_cards_pad = 0.03 * k,
            text_scale = 0.55 * k,
            badge_font_scale = 1.2 * k,
            text_h_ratio = 0.82,
            gap_height = 0.1 * k,
            tag_floor = 2.05 * k,
            emboss_outer = 0.07 * k,
            emboss_inner = 0.05 * k,
            corner_outer = 0.12 * k,
            corner_inner = 0.1,
        }
    end

    local function normalized_or(text, fallback)
        return U.normalize_text(text) or fallback
    end

    local function visible_title_text_length(text)
        local s = tostring(text or '')
        -- Strip Balatro formatting markers so width reflects rendered glyphs.
        s = s:gsub('{[^}]-}', '')
        s = s:gsub('#%d+#', '')
        s = U.normalize_text(s) or ''
        return #s
    end

    local function compute_mini_popup_minw(title_text)
        local len = visible_title_text_length(title_text)
        local grow = math.max(0, len - 12) * 0.065
        return U.clamp(DEFAULT_MINI_POPUP_MINW + grow, DEFAULT_MINI_POPUP_MINW, MAX_MINI_POPUP_MINW)
    end

    local function localize_effect_name(card, ui_table)
        local explicit_name = ui_table and U.normalize_text(ui_table.ft_effect_name)
        if explicit_name then
            return explicit_name
        end

        if ui_table and ui_table.ft_effect_set and ui_table.ft_effect_key then
            local ok, value = pcall(localize, {
                type = 'name_text',
                set = ui_table.ft_effect_set,
                key = ui_table.ft_effect_key,
            })
            if not ok then
                log(
                    'warning',
                    'name_text lookup failed: set=' .. tostring(ui_table.ft_effect_set)
                        .. ' key=' .. tostring(ui_table.ft_effect_key)
                        .. ' card=' .. tostring(card and card.ability and card.ability.name)
                        .. ' err=' .. tostring(value)
                )
            elseif value == 'ERROR' then
                log(
                    'warning',
                    'name_text lookup returned ERROR: set=' .. tostring(ui_table.ft_effect_set)
                        .. ' key=' .. tostring(ui_table.ft_effect_key)
                        .. ' card=' .. tostring(card and card.ability and card.ability.name)
                )
            end
            local normalized = ok and U.normalize_text(value) or nil
            if normalized then
                return normalized
            end
        end

        return U.normalize_text(card and card.ability and card.ability.name) or ''
    end

    local function add_gap(nodes, width, layout)
        if width and width > 0 then
            nodes[#nodes + 1] = {n = G.UIT.B, config = {w = width, h = layout.gap_height}}
        end
    end

    local function empty_layout()
        return {
            nodes = {},
            width = 0,
            height = 0,
            inner_padding = 0,
            cards_padding = 0,
        }
    end

    local function build_forecast_elements(items, layout)
        local elements = {}

        for i = 1, #items do
            local item = items[i]
            local element = render.make_forecast_element(item, layout)
            if element then
                elements[#elements + 1] = element
            else
                log('warning', 'Unknown forecast item kind at index ' .. tostring(i) .. ': ' .. tostring(item and item.kind))
            end
        end

        return elements
    end

    local function compute_forecast_layout(items, layout)
        if not (items and #items > 0) then
            return empty_layout()
        end

        local elements = build_forecast_elements(items, layout)
        local item_count = #elements
        if item_count < 1 then
            return empty_layout()
        end

        local total_items_width = 0
        for i = 1, item_count do
            total_items_width = total_items_width + elements[i].width
        end

        local forecast_nodes = {}
        local forecast_inner_padding = layout.forecast_inner_pad
        local forecast_cards_padding = layout.forecast_cards_pad
        local forecast_height = layout.preview_h + layout.frame_padding
        local single_card_slot_width = math.max(layout.preview_w + layout.frame_padding, layout.tag_floor)
        local forecast_width = single_card_slot_width

        if item_count == 2 then
            forecast_width = total_items_width + (2 * layout.two_side_gap) + layout.two_middle_gap
            add_gap(forecast_nodes, layout.two_side_gap, layout)
            forecast_nodes[#forecast_nodes + 1] = elements[1].node
            add_gap(forecast_nodes, layout.two_middle_gap, layout)
            forecast_nodes[#forecast_nodes + 1] = elements[2].node
            add_gap(forecast_nodes, layout.two_side_gap, layout)
            forecast_inner_padding = 0
            forecast_cards_padding = 0
        elseif item_count > 2 then
            forecast_width = total_items_width + (2 * layout.multi_side_gap) + ((item_count - 1) * layout.multi_gap)
            add_gap(forecast_nodes, layout.multi_side_gap, layout)
            for i = 1, item_count do
                forecast_nodes[#forecast_nodes + 1] = elements[i].node
                if i < item_count then
                    add_gap(forecast_nodes, layout.multi_gap, layout)
                end
            end
            add_gap(forecast_nodes, layout.multi_side_gap, layout)
            forecast_inner_padding = 0
            forecast_cards_padding = 0
        else
            forecast_nodes[#forecast_nodes + 1] = elements[1].node
            forecast_width = math.max(single_card_slot_width, total_items_width + layout.frame_padding)
        end

        return {
            nodes = forecast_nodes,
            width = forecast_width,
            height = forecast_height,
            inner_padding = forecast_inner_padding,
            cards_padding = forecast_cards_padding,
        }
    end

    local function normalize_badge_key(raw_key)
        if type(raw_key) ~= 'string' then
            return raw_key
        end

        local key = raw_key:gsub('_SMODS_INTERNAL$', '')

        -- Collapse any remaining "prefix_suffix" down to the prefix for SMODS internal keys
        if key ~= raw_key then
            local first_underscore = key:find('_')
            if first_underscore then
                key = key:sub(1, first_underscore - 1)
            end
        end

        if key == 'negative_consumable' then
            key = 'negative'
        end

        return key
    end

    local function build_badges(card, aut, card_type, card_type_colour, hide_all_labels, layout)
        local badges = {}
        if hide_all_labels then
            return badges
        end

        if aut.badges and (aut.badges.card_type or aut.badges.force_rarity) then
            badges[#badges + 1] = create_badge(
                normalized_or(card_type, card_type),
                card_type_colour,
                nil,
                layout.badge_font_scale
            )
        end

        if aut.badges then
            for _, badge in ipairs(aut.badges) do
                local raw_key = badge
                local key = normalize_badge_key(raw_key)
                local badge_text = localize(key, 'labels')
                if key == 'negative' then
                    log(
                        'debug',
                        'negative badge probe: raw=' .. tostring(raw_key)
                            .. ' mapped=' .. tostring(key)
                            .. ' text=' .. tostring(badge_text)
                            .. ' card=' .. tostring(card and card.ability and card.ability.name)
                            .. ' center=' .. tostring(card and card.config and card.config.center and card.config.center.key)
                    )
                end
                if badge_text == 'ERROR' then
                    log(
                        'warning',
                        'badge label lookup returned ERROR: raw=' .. tostring(raw_key)
                            .. ' mapped=' .. tostring(key)
                            .. ' card=' .. tostring(card and card.ability and card.ability.name)
                            .. ' center_set=' .. tostring(card and card.config and card.config.center and card.config.center.set)
                            .. ' center_key=' .. tostring(card and card.config and card.config.center and card.config.center.key)
                            .. ' edition=' .. tostring(card and card.edition and card.edition.type)
                    )
                    if key == 'negative' then
                        local is_negative_consumable = type(raw_key) == 'string' and raw_key:sub(1, 19) == 'negative_consumable'
                        local edition_probe_key = is_negative_consumable and 'e_negative_consumable' or 'e_negative'
                        local edition_name = localize({type = 'name_text', set = 'Edition', key = edition_probe_key})
                        log(
                            'warning',
                            'edition name probe: key=' .. tostring(edition_probe_key)
                                .. ' text=' .. tostring(edition_name)
                        )
                    end
                end
                badges[#badges + 1] = create_badge(normalized_or(badge_text, badge_text), get_badge_colour(key))
            end
        end

        return badges
    end

    local function build_infotips(card, aut, layout)
        local info_boxes = {}
        render.add_info_box(info_boxes, aut.main or {}, localize_effect_name(card, aut), layout, compute_mini_popup_minw)

        if aut.info then
            for _, info in ipairs(aut.info) do
                render.add_info_box(info_boxes, info, info and info.name, layout, compute_mini_popup_minw)
            end
        end

        return info_boxes
    end

    local function build_popup_tree(layout, card_type_background, info_tip_ref, show_main_popup_name, aut, is_playing_card, forecast_row, badges)
        return {
            n = G.UIT.ROOT,
            config = {align = 'cm', colour = G.C.CLEAR},
            nodes = {
                {
                    n = G.UIT.C,
                    config = {
                        align = 'cm',
                        func = info_tip_ref and 'show_infotip' or nil,
                        object = info_tip_ref and Moveable() or nil,
                        ref_table = info_tip_ref,
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {
                                padding = layout.box_padding,
                                r = layout.corner_outer,
                                colour = lighten(G.C.JOKER_GREY, 0.5),
                                emboss = layout.emboss_outer,
                            },
                            nodes = {
                                {
                                    n = G.UIT.R,
                                    config = {
                                        align = 'cm',
                                        padding = layout.panel_padding,
                                        r = layout.corner_inner,
                                        colour = adjust_alpha(card_type_background, 0.8),
                                    },
                                    nodes = {
                                        show_main_popup_name and name_from_rows(aut.name, is_playing_card and G.C.WHITE or nil) or nil,
                                        forecast_row,
                                        badges[1] and {n = G.UIT.R, config = {align = 'cm', padding = layout.badge_padding}, nodes = badges}
                                            or nil,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }
    end

    local M = {}

    function M.build_custom_popup(card, aut)
        if not cached_layout then
            cached_layout = make_layout(CARD_SCALE)
        end
        local layout = cached_layout
        local debuffed = card.debuff
        local card_type_colour = get_type_colour(card.config.center or card.config, card)
        local card_type_background =
            (aut.card_type == 'Locked' and G.C.BLACK)
            or ((aut.card_type == 'Undiscovered') and darken(G.C.JOKER_GREY, 0.3))
            or ((aut.card_type == 'Enhanced' or aut.card_type == 'Default') and darken(G.C.BLACK, 0.1))
            or (debuffed and darken(G.C.BLACK, 0.1))
            or (card_type_colour and darken(G.C.BLACK, 0.1))
            or G.C.SET[aut.card_type]
            or {0, 1, 1, 1}

        local card_type = localize('k_' .. string.lower(aut.card_type))
        local is_playing_card = aut.card_type == 'Enhanced' or aut.card_type == 'Default'

        if aut.card_type == 'Joker' or (aut.badges and aut.badges.force_rarity) then
            card_type = ({localize('k_common'), localize('k_uncommon'), localize('k_rare'), localize('k_legendary')})[card.config.center.rarity]
        end
        if aut.card_type == 'Enhanced' then
            card_type = localize({type = 'name_text', key = card.config.center.key, set = 'Enhanced'})
        end
        card_type = (debuffed and aut.card_type ~= 'Enhanced') and localize('k_debuffed') or card_type

        local hide_all_labels = FT.config_api and FT.config_api.hide_all_labels and FT.config_api.hide_all_labels()
        local badges = build_badges(card, aut, card_type, card_type_colour, hide_all_labels, layout)

        local show_effect_popup = FT.config_api and FT.config_api.show_effect_popup and FT.config_api.show_effect_popup()
        local info_boxes = show_effect_popup and build_infotips(card, aut, layout) or {}
        local info_tip_ref = show_effect_popup and next(info_boxes) and info_boxes or nil

        local forecast = compute_forecast_layout(aut.ft_forecast_items, layout)
        local forecast_row = render.build_forecast_slot(forecast, layout)

        local show_main_popup_name = FT.config_api and FT.config_api.show_main_popup_name and FT.config_api.show_main_popup_name()

        return build_popup_tree(
            layout,
            card_type_background,
            info_tip_ref,
            show_main_popup_name,
            aut,
            is_playing_card,
            forecast_row,
            badges
        )
    end

    return M
end
