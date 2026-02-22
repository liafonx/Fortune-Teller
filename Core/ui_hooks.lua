return function(FT)
    local P = FT.predictors
    local Preview = FT.preview
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Hooks')) or function() end

    local popup = FT.load_module('UI/card_popup.lua')(FT)

    local function is_collection_card(card)
        return card and card.area and card.area.config and card.area.config.collection
    end

    local function clear_popup_state(card)
        if card then
            card._ft_has_custom_popup = nil
        end
    end

    local function card_log_name(card)
        return tostring(card and card.ability and card.ability.name)
    end

    local function should_refresh_popup_after_highlight(card)
        if not (card and card.states and card.states.hover and card.states.hover.is) then
            return false
        end
        if U.is_pack_context_active() then
            return false
        end
        if card.area ~= G.hand then
            return false
        end
        if card.facing ~= 'front' or card.no_ui or G.debug_tooltip_toggle then
            return false
        end
        if card.states.drag and card.states.drag.is then
            return G and G.CONTROLLER and G.CONTROLLER.HID and G.CONTROLLER.HID.touch
        end
        return true
    end

    local function sort_forecast_items_like_hand_rank(items, sort_meta)
        if not (items and sort_meta and #items > 1) then
            return items
        end

        local sortable = {}
        for item_index = 1, #items do
            local item = items[item_index]
            local meta = sort_meta[item_index]

            if not (item and item.kind == 'card' and item.card and meta and meta.hand_sortable) then
                return items
            end

            if type(item.card.get_nominal) ~= 'function' then
                return items
            end

            local nominal = item.card:get_nominal()
            if type(nominal) ~= 'number' then
                return items
            end

            sortable[#sortable + 1] = {
                item = item,
                nominal = nominal,
                destroyed = meta.destroyed and 1 or 0,
                idx = meta.idx or item_index,
            }
        end

        table.sort(sortable, function(a, b)
            if a.destroyed ~= b.destroyed then
                return a.destroyed > b.destroyed
            end
            if a.nominal ~= b.nominal then
                return a.nominal > b.nominal
            end
            return a.idx < b.idx
        end)

        local out = {}
        for i = 1, #sortable do
            out[i] = sortable[i].item
        end
        return out
    end

    local function collect_dynatext_objects(node, out, depth)
        if depth > 8 or type(node) ~= 'table' then
            return
        end

        if node.n == G.UIT.O
                and node.config
                and type(node.config.object) == 'table'
                and node.config.object.config
                and type(node.config.object.config.string) == 'table' then
            out[#out + 1] = node.config.object
        end

        if type(node.nodes) == 'table' then
            for i = 1, #node.nodes do
                collect_dynatext_objects(node.nodes[i], out, depth + 1)
            end
        end
        for i = 1, #node do
            collect_dynatext_objects(node[i], out, depth + 1)
        end
    end

    local function center_key(card)
        return card and card.config and card.config.center and card.config.center.key or nil
    end

    local function resolve_effective_joker_card(card)
        if not (card and G and G.jokers and G.jokers.cards and U.resolve_effective_joker) then
            return card
        end
        for i = 1, #G.jokers.cards do
            if G.jokers.cards[i] == card then
                return U.resolve_effective_joker(i, {}) or card
            end
        end
        return card
    end

    local function patch_jokerdisplay_misprint_definition()
        if FT.runtime.jokerdisplay_misprint_patched then
            return
        end
        if not (G and G.C) then
            return
        end
        if not (_G.JokerDisplay and JokerDisplay.Definitions and JokerDisplay.Definitions.j_misprint) then
            return
        end

        local def = JokerDisplay.Definitions.j_misprint
        def.text = {
            {text = '+', colour = G.C.MULT},
            {ref_table = 'card.joker_display_values', ref_value = 'ft_misprint_mult'},
        }
        def.text_config = {colour = G.C.MULT}
        def.calc_function = function(card)
            local mult = U.predict_misprint_mult and U.predict_misprint_mult(card, card) or nil
            local fallback = card and card.ability and card.ability.extra and card.ability.extra.min or 0
            card.joker_display_values.ft_misprint_mult = tonumber(mult) or fallback
        end

        -- For Blueprint/Brainstorm copied Misprint displays, bind copied row values to the
        -- copy card's joker_display_values (not the source Misprint card), so each copy can
        -- show its own deterministic roll.
        if not FT.runtime.jokerdisplay_add_text_patched
                and type(JokerDisplayBox) == 'table'
                and type(JokerDisplayBox.add_text) == 'function' then
            local original_add_text = JokerDisplayBox.add_text
            JokerDisplayBox.add_text = function(self, nodes, config, custom_parent)
                if custom_parent
                        and U.center_key_of(custom_parent) == 'j_misprint'
                        and self
                        and self.parent
                        and self.parent.joker_display_values
                        and self.parent.joker_display_values.blueprint_ability_key == 'j_misprint' then
                    for i = 1, #nodes do
                        local display_object = JokerDisplay.create_display_object(self.parent, nodes[i], config)
                        if display_object then
                            self:add_child(display_object, self.text)
                        end
                    end
                    self.has_text = #self.text.children > 0
                    return
                end
                return original_add_text(self, nodes, config, custom_parent)
            end
            FT.runtime.jokerdisplay_add_text_patched = true
        end

        local function patch_copy_calc(def_key)
            local copy_def = JokerDisplay.Definitions and JokerDisplay.Definitions[def_key]
            if not (copy_def and type(copy_def.calc_function) == 'function') then
                return
            end
            if copy_def.ft_misprint_calc_wrapped then
                return
            end
            local original_calc = copy_def.calc_function
            copy_def.calc_function = function(card)
                original_calc(card)
                local copied = card and card.joker_display_values and card.joker_display_values.blueprint_ability_joker
                if U.center_key_of(copied) == 'j_misprint' then
                    local mult = U.predict_misprint_mult and U.predict_misprint_mult(card, copied) or nil
                    local fallback = copied and copied.ability and copied.ability.extra and copied.ability.extra.min or 0
                    card.joker_display_values.ft_misprint_mult = tonumber(mult) or fallback
                end
            end
            copy_def.ft_misprint_calc_wrapped = true
        end

        patch_copy_calc('j_blueprint')
        patch_copy_calc('j_brainstorm')

        FT.runtime.jokerdisplay_misprint_patched = true
        log('debug', 'Patched JokerDisplay Misprint display to deterministic mult')
    end

    local function apply_misprint_vanilla_override(card, effective_card, ui_table, descriptors, original_generate)
        local hovered_key = center_key(card)
        local effective_key = center_key(effective_card)
        if hovered_key ~= 'j_misprint' and effective_key ~= 'j_misprint' then
            return false
        end
        if not (ui_table and type(ui_table.main) == 'table') then
            return false
        end

        -- If hover is a copy joker (Blueprint/Brainstorm) resolving to Misprint, swap in the
        -- copied Misprint vanilla UI table first so styling/layout stays fully vanilla.
        if hovered_key ~= 'j_misprint' and effective_key == 'j_misprint' and original_generate then
            local original_main = ui_table.main
            local original_name = U.extract_popup_title(ui_table.name)
                or U.normalize_text(card and card.ability and card.ability.name)
            local copied_ui = original_generate(effective_card)
            if copied_ui and type(copied_ui.main) == 'table' then
                ui_table.main = copied_ui.main
                -- Preserve hovered copy-joker self panel as mini info box.
                if original_main and #original_main > 0 then
                    ui_table.info = ui_table.info or {}
                    original_main.name = original_name or ''
                    table.insert(ui_table.info, 1, original_main)
                end
            end
        end

        local predicted_mult = nil
        for i = 1, #descriptors do
            local d = descriptors[i]
            if d and d.kind == 'misprint_mult' then
                predicted_mult = tonumber(d.mult)
                break
            end
        end
        if not predicted_mult then
            return false
        end

        local dynas = {}
        for i = 1, #ui_table.main do
            collect_dynatext_objects(ui_table.main[i], dynas, 0)
        end
        if #dynas < 2 then
            log('warning', 'Misprint vanilla override skipped: expected 2 DynaText objects, got ' .. tostring(#dynas))
            return false
        end

        local mult_obj = dynas[1]
        local line_obj = dynas[2]

        mult_obj.config.string = {tostring(predicted_mult)}
        mult_obj.config.colours = {G.C.RED}
        mult_obj.config.random_element = false
        mult_obj.focused_string = 1
        if mult_obj.update_text then
            mult_obj:update_text(true)
        end

        local show_draw = FT.config_api and FT.config_api.show_misprint_draw_preview and FT.config_api.show_misprint_draw_preview()
        local draw_token = show_draw and U.misprint_draw_preview_token and U.misprint_draw_preview_token() or nil
        if draw_token then
            -- Keep symmetric padding so centered alignment remains stable.
            line_obj.config.string = {' ' .. draw_token .. ' '}
            line_obj.config.colours = {G.C.RED}
        else
            local mult_label = localize and localize('k_mult') or 'Mult'
            if type(mult_label) ~= 'string' or mult_label == '' or mult_label == 'ERROR' or mult_label == 'k_mult' then
                mult_label = 'Mult'
            end
            line_obj.config.string = {' ' .. tostring(mult_label) .. ' '}
            line_obj.config.colours = {G.C.UI.TEXT_DARK}
        end
        line_obj.config.random_element = false
        line_obj.focused_string = 1
        if line_obj.update_text then
            line_obj:update_text(true)
        end

        -- Keep Misprint popup name visibility aligned with FT display config
        -- even though this path uses vanilla AUT.main rendering.
        local show_name = FT.config_api and FT.config_api.show_main_popup_name and FT.config_api.show_main_popup_name()
        if not show_name then
            ui_table.name = nil
        end

        return true
    end

    local original_generate_ability_table = Card.generate_UIBox_ability_table
    Card.generate_UIBox_ability_table = function(self, ...)
        patch_jokerdisplay_misprint_definition()
        local vars_only = ...

        if self and self.states and self._ft_preview_cards then
            Preview.cleanup_preview_cards(self)
        end

        local ui_table = original_generate_ability_table(self, ...)
        if vars_only then
            return ui_table
        end
        if not (self and self.states and ui_table and ui_table.main) then
            return ui_table
        end
        if is_collection_card(self) then
            return ui_table
        end

        local descriptors = P.predict_descriptors(self)
        if not (descriptors and #descriptors > 0) then
            return ui_table
        end

        -- Misprint uses vanilla info area override; do not render custom forecast card panel.
        if apply_misprint_vanilla_override(
                self,
                resolve_effective_joker_card(self),
                ui_table,
                descriptors,
                original_generate_ability_table
            ) then
            return ui_table
        end

        local previews = {}
        local forecast_items = {}
        local sort_meta = {}

        for i = 1, #descriptors do
            local desc = descriptors[i]
            if desc and (desc.kind == 'text' or desc.kind == 'misprint_mult') then
                forecast_items[#forecast_items + 1] = desc
            elseif desc then
                local preview = Preview.make_preview_card(desc)
                if preview then
                    local item_index = #forecast_items + 1
                    previews[#previews + 1] = preview
                    forecast_items[item_index] = {
                        kind = 'card',
                        card = preview,
                    }
                    sort_meta[item_index] = {
                        destroyed = desc.destroyed and true or false,
                        hand_sortable = desc.front and desc.front.value and desc.front.suit,
                        idx = i,
                    }
                end
            end
        end

        if #forecast_items < 1 then
            log('error', 'Descriptor->preview conversion produced no forecast items for: ' .. card_log_name(self))
            return ui_table
        end

        forecast_items = sort_forecast_items_like_hand_rank(forecast_items, sort_meta)

        ui_table.ft_effect_set = self.config.center and self.config.center.set or nil
        ui_table.ft_effect_key = self.config.center and self.config.center.key or nil
        ui_table.ft_effect_name = U.extract_popup_title(ui_table.name)
        ui_table.ft_forecast_items = forecast_items

        self._ft_preview_cards = previews
        return ui_table
    end

    local original_stop_hover = Card.stop_hover
    Card.stop_hover = function(self, ...)
        if self and self._ft_preview_cards then
            Preview.cleanup_preview_cards(self)
        end
        return original_stop_hover(self, ...)
    end

    local original_card_remove = Card.remove
    Card.remove = function(self, ...)
        if self and self._ft_preview_cards then
            Preview.cleanup_preview_cards(self)
        end
        return original_card_remove(self, ...)
    end

    local original_card_highlight = Card.highlight
    Card.highlight = function(self, ...)
        local was_highlighted = not not (self and self.highlighted)
        local result = original_card_highlight(self, ...)
        local is_highlighted = not not (self and self.highlighted)

        if was_highlighted == is_highlighted then
            return result
        end

        if not should_refresh_popup_after_highlight(self) then
            return result
        end

        if self._ft_preview_cards then
            Preview.cleanup_preview_cards(self)
        end

        self.ability_UIBox_table = self:generate_UIBox_ability_table()
        self.config = self.config or {}
        self.config.h_popup = G.UIDEF.card_h_popup(self)
        self.config.h_popup_config = self:align_h_popup()

        return result
    end

    local original_card_h_popup = G.UIDEF.card_h_popup
    G.UIDEF.card_h_popup = function(card)
        if not (card and card.ability_UIBox_table) then
            clear_popup_state(card)
            return original_card_h_popup(card)
        end
        if is_collection_card(card) then
            clear_popup_state(card)
            return original_card_h_popup(card)
        end

        local aut = card.ability_UIBox_table
        if not (aut and aut.ft_forecast_items and aut.main) then
            clear_popup_state(card)
            return original_card_h_popup(card)
        end

        card._ft_has_custom_popup = true
        return popup.build_custom_popup(card, aut)
    end

    local original_align_h_popup = Card.align_h_popup
    Card.align_h_popup = function(self, ...)
        local cfg = original_align_h_popup(self, ...)
        if cfg and self and self._ft_has_custom_popup then
            cfg.lr_clamp = true
        end
        return cfg
    end

    patch_jokerdisplay_misprint_definition()
    log('info', 'Hook overrides initialized')
end
