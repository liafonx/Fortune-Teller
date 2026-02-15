return function(FT)
    local P = FT.predictors
    local Preview = FT.preview
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

    local function normalize_popup_title_text(text)
        if type(text) ~= 'string' then
            return nil
        end
        local normalized = text:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
        if normalized == '' then
            return nil
        end
        return normalized
    end

    local function append_normalized_title(out, text)
        local normalized = normalize_popup_title_text(text)
        if normalized then
            out[#out + 1] = normalized
        end
    end

    local function collect_title_fragments_from_dynastring(str, out, depth)
        if depth > 8 or str == nil then
            return
        end
        local t = type(str)
        if t == 'string' then
            append_normalized_title(out, str)
            return
        end
        if t ~= 'table' then
            return
        end

        local embedded = rawget(str, 'string')
        if type(embedded) == 'string' then
            append_normalized_title(out, embedded)
        end

        for i = 1, #str do
            collect_title_fragments_from_dynastring(str[i], out, depth + 1)
        end
    end

    local function collect_title_text_from_node(node, out, depth)
        if depth > 12 or node == nil then
            return
        end

        local node_type = type(node)
        if node_type == 'string' then
            append_normalized_title(out, node)
            return
        end
        if node_type ~= 'table' then
            return
        end

        local cfg = rawget(node, 'config')
        if type(cfg) == 'table' then
            append_normalized_title(out, cfg.text)

            local obj = rawget(cfg, 'object')
            if type(obj) == 'table' then
                collect_title_fragments_from_dynastring(rawget(obj, 'string'), out, 0)
            end
        end

        local children = rawget(node, 'nodes')
        if type(children) == 'table' then
            for i = 1, #children do
                collect_title_text_from_node(children[i], out, depth + 1)
            end
        end

        for i = 1, #node do
            collect_title_text_from_node(node[i], out, depth + 1)
        end
    end

    local function extract_popup_title_from_name_nodes(name_nodes)
        if type(name_nodes) ~= 'table' then
            return nil
        end

        local fragments = {}
        for i = 1, #name_nodes do
            collect_title_text_from_node(name_nodes[i], fragments, 0)
        end

        if #fragments < 1 then
            return nil
        end
        return normalize_popup_title_text(table.concat(fragments, ' '))
    end

    local PACK_STATE_KEYS = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK'}

    local function is_active_pack_state()
        if not (G and G.STATES and G.STATE) then
            return false
        end

        for i = 1, #PACK_STATE_KEYS do
            local state = G.STATES[PACK_STATE_KEYS[i]]
            if state and G.STATE == state then
                return true
            end
        end
        return false
    end

    local function has_visible_pack_cards()
        return G
            and G.pack_cards
            and not G.pack_cards.REMOVED
            and G.pack_cards.cards
            and G.pack_cards.cards[1]
    end

    local function is_pack_context_active()
        if not G then
            return false
        end

        if is_active_pack_state() then
            return true
        end

        -- Booster UI can remain active while state transitions (hand shown above pack cards).
        if G.booster_pack and not G.booster_pack.REMOVED then
            return true
        end
        if has_visible_pack_cards() then
            return true
        end

        return false
    end

    local function should_refresh_popup_after_highlight(card)
        if not (card and card.states and card.states.hover and card.states.hover.is) then
            return false
        end
        if is_pack_context_active() then
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

    local original_generate_ability_table = Card.generate_UIBox_ability_table
    Card.generate_UIBox_ability_table = function(self, ...)
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

        local previews = {}
        local forecast_items = {}
        local sort_meta = {}

        for i = 1, #descriptors do
            local desc = descriptors[i]
            if desc and desc.kind == 'text' then
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
        ui_table.ft_effect_name = extract_popup_title_from_name_nodes(ui_table.name)
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

    log('info', 'Hook overrides initialized')
end
