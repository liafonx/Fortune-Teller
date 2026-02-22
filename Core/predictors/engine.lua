return function(FT)
    FT.predictors = FT.predictors or {}
    local P = FT.predictors
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Engine')) or function() end

    local shared = FT.load_module('Core/predictors/shared.lua')(FT)
    local routes = FT.load_module('Core/predictors/routes.lua')(shared)
    P.routes_by_key = routes.routes_by_key

    -- Maps center_key → required game phase ('blind' | 'blind_select' | 'shop' | 'shop_or_blind_select')
    -- Keys omitted here are always shown (no timing gate).
    local TRIGGER_PHASE = {
        -- In-blind scoring
        j_8_ball = 'blind',
        j_vagabond = 'blind', j_superposition = 'blind',
        j_seance = 'blind', j_sixth_sense = 'blind',
        -- Blind entry / pre-blind planning
        j_riff_raff = 'shop_or_blind_select',
        j_madness = 'shop_or_blind_select',
        j_cartomancer = 'shop_or_blind_select',
        j_certificate = 'shop_or_blind_select',
        -- Shop
        j_hallucination = 'shop_or_blind_select',
        j_perkeo = 'shop',
    }

    -- Only these keys can have their phase gate bypassed by timing_always.
    local TIMING_ALWAYS_KEYS = {
        j_madness = true, j_cartomancer = true, j_certificate = true, j_perkeo = true,
        j_riff_raff = true,
    }

    local function phase_allowed(center_key)
        local phase = TRIGGER_PHASE[center_key]
        if not phase then return true end  -- not phase-gated; always allowed
        if FT.config_api.prediction_timing_always() and TIMING_ALWAYS_KEYS[center_key] then
            return true  -- bypass phase gate for whitelisted keys only
        end
        if phase == 'blind'        then return U.is_playing_blind() end
        if phase == 'blind_select' then return U.is_in_blind_select() end
        if phase == 'shop' then return U.is_in_shop() end
        if phase == 'shop_or_blind_select' then
            return U.is_in_shop() or U.is_in_blind_select()
        end
        return true
    end

    -- Keys with `not context.blueprint` gate in vanilla: Blueprint/Brainstorm copies
    -- cannot trigger these jokers.
    local NON_BLUEPRINT_KEYS = {j_madness = true, j_sixth_sense = true}

    -- Find position of card in G.jokers.cards (needed to call U.resolve_effective_joker).
    local function joker_index(card)
        if not (G and G.jokers and G.jokers.cards) then return nil end
        for i, j in ipairs(G.jokers.cards) do
            if j == card then return i end
        end
        return nil
    end

    -- Resolve hovered card to effective copied card (Blueprint/Brainstorm chain).
    -- Returns nil when chain leads nowhere; returns card itself for non-copy jokers.
    local function resolve_effective_card(start_card)
        local idx = joker_index(start_card)
        if not idx then return start_card end  -- not in joker area; return as-is
        return U.resolve_effective_joker(idx, {})
    end

    local function is_purple_seal_hand_highlight(card)
        return card
            and card.area == G.hand
            and card.highlighted
            and card.seal == 'Purple'
            and not card.debuff
            and not U.is_pack_context_active()
    end

    function P.predict_descriptors(card)
        if not (card and card.ability and G and G.GAME) then
            return nil
        end

        if is_purple_seal_hand_highlight(card)
            and shared.predict_purple_seal_tarot
            and (not FT.config_api or not FT.config_api.show_purple_seal_preview or FT.config_api.show_purple_seal_preview()) then
            return shared.predict_purple_seal_tarot(card)
        end

        local center_key = card.config and card.config.center and card.config.center.key
        if FT.config_api and FT.config_api.is_card_enabled and not FT.config_api.is_card_enabled(center_key) then
            return nil
        end

        -- Resolve Blueprint/Brainstorm hover to the effective copied card.
        -- For direct jokers, effective_card == card (no change in behavior).
        local effective_card = resolve_effective_card(card)
        if not effective_card then return nil end  -- chain leads nowhere → fall back to info box

        local effective_center_key = effective_card.config
            and effective_card.config.center
            and effective_card.config.center.key
        if not effective_center_key then return nil end

        -- Enabled check on effective key: Blueprint/Brainstorm copying a disabled joker must not
        -- show predictions.
        if not FT.config_api.is_card_enabled(effective_center_key) then return nil end

        -- Non-blueprint-compatible jokers must not show predictions when their effect is
        -- reached via a copy joker hover (hovered card ≠ effective card).
        local hovered_key = card.config and card.config.center and card.config.center.key
        if hovered_key ~= effective_center_key and NON_BLUEPRINT_KEYS[effective_center_key] then
            return nil
        end

        -- Phase check and routing operate on effective key, not hovered key.
        if not phase_allowed(effective_center_key) then return nil end
        local resolver = P.routes_by_key and P.routes_by_key[effective_center_key]
        if not resolver then return nil end

        -- Predictor receives:
        -- 1) effective_card: read ability/config from the actual copied joker
        -- 2) hovered card: preserve slot-order semantics for effects that depend on call order
        --    (e.g. j_misprint copies in joker iteration order).
        local result = resolver(effective_card, card)
        if not result then
            log('debug', 'Predictor route returned no preview for card: key=' .. tostring(effective_center_key))
        end
        return result
    end

    log('info', 'Predictor module initialized')
end
