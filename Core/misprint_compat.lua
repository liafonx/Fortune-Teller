return function(FT)
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('MisprintCompat')) or function() end

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
        local hovered_key = U.center_key_of(card)
        local effective_key = U.center_key_of(effective_card)
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

        local draw_token = U.misprint_draw_preview_token and U.misprint_draw_preview_token() or nil
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

    return {
        patch_jokerdisplay_misprint_definition = patch_jokerdisplay_misprint_definition,
        apply_misprint_vanilla_override = apply_misprint_vanilla_override,
    }
end
