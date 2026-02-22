return function(FT)
    FT.runtime = FT.runtime or {}
    if FT.runtime.slot_cache_hooks_installed then
        return
    end

    local U = FT.utils or {}
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('RunStateHooks')) or function() end

    -- Perkeo verification hook is installed only when verbose logging is active.
    -- Keep output to one summary line per shop close to avoid log spam.

    local function install_toggle_shop_hook()
        if not (G and G.FUNCS and type(G.FUNCS.toggle_shop) == 'function') then
            return
        end
        if FT.runtime.toggle_shop_hook_wrapper and G.FUNCS.toggle_shop == FT.runtime.toggle_shop_hook_wrapper then
            return
        end

        local original_toggle_shop = G.FUNCS.toggle_shop
        local wrapper = function(e, ...)
            if G and G.shop and G.jokers and G.jokers.cards then
                local pool = G.consumeables and G.consumeables.cards or {}
                local perkeo_effective = 0
                for i = 1, #G.jokers.cards do
                    local j = G.jokers.cards[i]
                    local key = U.center_key_of(j)
                    local effective_key = key
                    if U.resolve_effective_joker then
                        local effective = U.resolve_effective_joker(i, {})
                        effective_key = U.center_key_of(effective)
                    end
                    if key == 'j_perkeo' or effective_key == 'j_perkeo' then
                        perkeo_effective = perkeo_effective + 1
                    end
                end
                if perkeo_effective > 0 then
                    log('debug', function()
                        return 'Perkeo actual toggle_shop summary: effective_copies=' .. tostring(perkeo_effective)
                            .. ' pool_size=' .. tostring(#pool)
                    end)
                end
            end
            return original_toggle_shop(e, ...)
        end

        G.FUNCS.toggle_shop = wrapper
        FT.runtime.toggle_shop_hook_wrapper = wrapper
    end

    local function maybe_install_debug_hooks()
        if FT.config and FT.config.debug_mode then
            install_toggle_shop_hook()
        end
    end

    if type(Game) == 'table' and type(Game.start_run) == 'function' then
        local original_start_run = Game.start_run
        Game.start_run = function(self, args, ...)
            local result = original_start_run(self, args, ...)
            if U.refresh_consumable_slot_cap_from_run then
                U.refresh_consumable_slot_cap_from_run()
            end
            if U.refresh_joker_slot_cap_from_run then
                U.refresh_joker_slot_cap_from_run()
            end
            if U.refresh_normal_probability_from_run then
                U.refresh_normal_probability_from_run()
            end
            maybe_install_debug_hooks()
            return result
        end
    end

    if type(Card) == 'table' and type(Card.apply_to_run) == 'function' then
        local original_apply_to_run = Card.apply_to_run
        Card.apply_to_run = function(self, center, ...)
            local result = original_apply_to_run(self, center, ...)

            local center_key = center and center.key
            if not center_key and self and self.config and self.config.center then
                center_key = self.config.center.key
            end
            if center_key == 'v_crystal_ball' and U.mark_crystal_ball_used then
                U.mark_crystal_ball_used()
            elseif center_key == 'v_antimatter' and U.mark_antimatter_used then
                U.mark_antimatter_used()
            end

            return result
        end
    end

    if type(Card) == 'table' and type(Card.add_to_deck) == 'function' then
        local original_add_to_deck = Card.add_to_deck
        Card.add_to_deck = function(self, from_debuff, ...)
            local result = original_add_to_deck(self, from_debuff, ...)
            if U.refresh_normal_probability_from_run then
                U.refresh_normal_probability_from_run()
            end
            return result
        end
    end

    if type(Card) == 'table' and type(Card.remove_from_deck) == 'function' then
        local original_remove_from_deck = Card.remove_from_deck
        Card.remove_from_deck = function(self, from_debuff, ...)
            local result = original_remove_from_deck(self, from_debuff, ...)
            if U.refresh_normal_probability_from_run then
                U.refresh_normal_probability_from_run()
            end
            return result
        end
    end

    maybe_install_debug_hooks()

    FT.runtime.slot_cache_hooks_installed = true
    log('info', 'Run-state slot cache hooks initialized')
end
