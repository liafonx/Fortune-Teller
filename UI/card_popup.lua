return function(FT)
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('CardPopup')) or function() end

    local UI = {
        outer_padding = 0.05,
        panel_inner_padding = 0.07,
        info_box_padding = 0.05,
        badge_row_padding = 0.03,
        preview_scale = 0.56,
        single_card_tag_floor_desktop = 2.05,
        single_card_tag_floor_touch = 1.95,
        frame_padding_desktop = 0.18,
        frame_padding_touch = 0.15,
        inter_card_gap_desktop = 0.05,
        inter_card_gap_touch = 0.04,
        forecast_inner_padding_single = 0.04,
        forecast_cards_padding_single = 0.03,
        text_box_height_ratio = 0.82,
    }

    local M = {}

    local function is_touch_ui()
        return (G and G.F_MOBILE_UI) or (G and G.CONTROLLER and G.CONTROLLER.HID and G.CONTROLLER.HID.touch)
    end

    local function localize_effect_name(card, ui_table)
        if ui_table and ui_table.ft_effect_set and ui_table.ft_effect_key then
            return localize({
                type = 'name_text',
                set = ui_table.ft_effect_set,
                key = ui_table.ft_effect_key,
            })
        end
        return card and card.ability and card.ability.name or ''
    end

    local function resolve_text_item(item)
        if item.text then
            return tostring(item.text)
        end
        if item.text_key then
            return localize(item.text_key)
        end
        return ''
    end

    local function add_gap(nodes, width)
        if width and width > 0 then
            nodes[#nodes + 1] = {n = G.UIT.B, config = {w = width, h = 0.1}}
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

    local function build_forecast_elements(items, base_preview_w, base_preview_h, touch)
        local elements = {}

        for i = 1, #items do
            local item = items[i]
            if item.kind == 'card' and item.card then
                elements[#elements + 1] = {
                    width = base_preview_w,
                    node = {
                        n = G.UIT.O,
                        config = {object = item.card, can_collide = false},
                    },
                }
            elseif item.kind == 'text' then
                local text_width = base_preview_w + 0.18
                local text_colour = (G and G.C and G.C.UI and G.C.UI.TEXT_LIGHT) or G.C.WHITE
                elements[#elements + 1] = {
                    width = text_width,
                    node = {
                        n = G.UIT.C,
                        config = {
                            align = 'cm',
                            minw = text_width,
                            minh = base_preview_h * UI.text_box_height_ratio,
                            colour = G.C.CLEAR,
                            padding = 0,
                        },
                        nodes = {
                            {
                                n = G.UIT.T,
                                config = {
                                    text = resolve_text_item(item),
                                    scale = touch and 0.5 or 0.55,
                                    colour = text_colour,
                                    shadow = true,
                                },
                            },
                        },
                    },
                }
            else
                log('warning', 'Unknown forecast item kind at index ' .. tostring(i) .. ': ' .. tostring(item and item.kind))
            end
        end

        return elements
    end

    local function compute_forecast_layout(items)
        if not (items and #items > 0) then
            return empty_layout()
        end

        local touch = is_touch_ui()
        local base_preview_w = (G and G.CARD_W and (G.CARD_W * UI.preview_scale)) or 0.56
        local base_preview_h = (G and G.CARD_H and (G.CARD_H * UI.preview_scale)) or 0.78
        local frame_padding = touch and UI.frame_padding_touch or UI.frame_padding_desktop
        local inter_card_gap = touch and UI.inter_card_gap_touch or UI.inter_card_gap_desktop
        local single_card_tag_floor = touch and UI.single_card_tag_floor_touch or UI.single_card_tag_floor_desktop

        local elements = build_forecast_elements(items, base_preview_w, base_preview_h, touch)
        local item_count = #elements
        if item_count < 1 then
            return empty_layout()
        end

        local total_items_width = 0
        for i = 1, item_count do
            total_items_width = total_items_width + elements[i].width
        end

        local forecast_nodes = {}
        local forecast_inner_padding = UI.forecast_inner_padding_single
        local forecast_cards_padding = UI.forecast_cards_padding_single
        local forecast_height = base_preview_h + frame_padding
        local single_card_slot_width = math.max(base_preview_w + frame_padding, single_card_tag_floor)
        local forecast_width = single_card_slot_width

        if item_count > 1 then
            local equal_gap_width = total_items_width + (item_count - 1) * inter_card_gap + (2 * inter_card_gap)

            if equal_gap_width < single_card_slot_width then
                forecast_width = single_card_slot_width
                local even_gap = math.max(0, (forecast_width - total_items_width) / (item_count + 1))
                add_gap(forecast_nodes, even_gap)
                for i = 1, item_count do
                    forecast_nodes[#forecast_nodes + 1] = elements[i].node
                    add_gap(forecast_nodes, even_gap)
                end
            else
                forecast_width = equal_gap_width
                add_gap(forecast_nodes, inter_card_gap)
                for i = 1, item_count do
                    forecast_nodes[#forecast_nodes + 1] = elements[i].node
                    add_gap(forecast_nodes, inter_card_gap)
                end
            end

            forecast_inner_padding = 0
            forecast_cards_padding = 0
        else
            forecast_nodes[#forecast_nodes + 1] = elements[1].node
            forecast_width = math.max(single_card_slot_width, total_items_width + frame_padding)
        end

        return {
            nodes = forecast_nodes,
            width = forecast_width,
            height = forecast_height,
            inner_padding = forecast_inner_padding,
            cards_padding = forecast_cards_padding,
        }
    end

    local function build_badges(card, aut, card_type, card_type_colour, show_type_label)
        local badges = {}
        if show_type_label and aut.badges and (aut.badges.card_type or aut.badges.force_rarity) then
            badges[#badges + 1] = create_badge(
                ((card.ability.name == 'Pluto' or card.ability.name == 'Ceres' or card.ability.name == 'Eris') and localize('k_dwarf_planet'))
                    or (card.ability.name == 'Planet X' and localize('k_planet_q') or card_type),
                card_type_colour,
                nil,
                1.2
            )
        end

        if aut.badges then
            for _, badge in ipairs(aut.badges) do
                local key = badge
                if key == 'negative_consumable' then
                    key = 'negative'
                end
                badges[#badges + 1] = create_badge(localize(key, 'labels'), get_badge_colour(key))
            end
        end

        return badges
    end

    local function add_info_box(info_boxes, rows, title)
        info_boxes[#info_boxes + 1] = {
            n = G.UIT.R,
            config = {align = 'cm'},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {
                        align = 'cm',
                        colour = lighten(G.C.JOKER_GREY, 0.5),
                        r = 0.1,
                        padding = UI.info_box_padding,
                        emboss = 0.05,
                    },
                    nodes = {
                        info_tip_from_rows(rows or {}, title or ''),
                    },
                },
            },
        }
    end

    local function build_infotips(card, aut)
        local info_boxes = {}
        add_info_box(info_boxes, aut.main or {}, localize_effect_name(card, aut))

        if aut.info then
            for _, info in ipairs(aut.info) do
                add_info_box(info_boxes, info, info and info.name)
            end
        end

        return info_boxes
    end

    local function build_forecast_slot(forecast)
        return {
            n = G.UIT.R,
            config = {align = 'cm', padding = 0},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {
                        align = 'cm',
                        minw = forecast.width,
                        minh = forecast.height,
                        padding = forecast.inner_padding,
                        r = 0.1,
                        colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.8),
                        emboss = 0.05,
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {align = 'cm', padding = forecast.cards_padding},
                            nodes = forecast.nodes,
                        },
                    },
                },
            },
        }
    end

    function M.build_custom_popup(card, aut)
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

        local outer_padding = UI.outer_padding
        local card_type = localize('k_' .. string.lower(aut.card_type))
        local is_playing_card = aut.card_type == 'Enhanced' or aut.card_type == 'Default'

        if aut.card_type == 'Joker' or (aut.badges and aut.badges.force_rarity) then
            card_type = ({localize('k_common'), localize('k_uncommon'), localize('k_rare'), localize('k_legendary')})[card.config.center.rarity]
        end
        if aut.card_type == 'Enhanced' then
            card_type = localize({type = 'name_text', key = card.config.center.key, set = 'Enhanced'})
        end
        card_type = (debuffed and aut.card_type ~= 'Enhanced') and localize('k_debuffed') or card_type

        local show_type_label = FT.config_api and FT.config_api.show_type_label and FT.config_api.show_type_label()
        local badges = build_badges(card, aut, card_type, card_type_colour, show_type_label)

        local show_effect_popup = FT.config_api and FT.config_api.show_effect_popup and FT.config_api.show_effect_popup()
        local info_boxes = show_effect_popup and build_infotips(card, aut) or {}
        local infotip_ref = show_effect_popup and next(info_boxes) and info_boxes or nil

        local forecast = compute_forecast_layout(aut.ft_forecast_items)
        local forecast_row = build_forecast_slot(forecast)

        local show_main_popup_name = FT.config_api and FT.config_api.show_main_popup_name and FT.config_api.show_main_popup_name()

        return {
            n = G.UIT.ROOT,
            config = {align = 'cm', colour = G.C.CLEAR},
            nodes = {
                {
                    n = G.UIT.C,
                    config = {
                        align = 'cm',
                        func = infotip_ref and 'show_infotip' or nil,
                        object = infotip_ref and Moveable() or nil,
                        ref_table = infotip_ref,
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {padding = outer_padding, r = 0.12, colour = lighten(G.C.JOKER_GREY, 0.5), emboss = 0.07},
                            nodes = {
                                {
                                    n = G.UIT.R,
                                    config = {align = 'cm', padding = UI.panel_inner_padding, r = 0.1, colour = adjust_alpha(card_type_background, 0.8)},
                                    nodes = {
                                        show_main_popup_name and name_from_rows(aut.name, is_playing_card and G.C.WHITE or nil) or nil,
                                        forecast_row,
                                        badges[1] and {n = G.UIT.R, config = {align = 'cm', padding = UI.badge_row_padding}, nodes = badges} or nil,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }
    end

    return M
end
