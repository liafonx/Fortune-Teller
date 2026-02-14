return function(FT)
    FT.utils = FT.utils or {}
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Utils')) or function() end
    local EDITION_KEYS = {'foil', 'holo', 'polychrome', 'negative'}

    local function forced_center_allowed(forced_key)
        if not forced_key then
            return false
        end
        local banned = G and G.GAME and G.GAME.banned_keys
        return not (banned and banned[forced_key])
    end

    local function safe_call(fn, error_prefix)
        if type(fn) ~= 'function' then
            log("error", "safe_call expected function, got: " .. tostring(type(fn)))
            return nil
        end
        local ok, result = pcall(fn)
        if ok then
            return result
        end
        log("warning", error_prefix .. ": " .. tostring(result))
        return nil
    end

    function U.copy_edition_flags(edition)
        if not edition then
            return nil
        end

        local out = {}
        for _, key in ipairs(EDITION_KEYS) do
            out[key] = edition[key] or nil
        end

        return (out.foil or out.holo or out.polychrome or out.negative) and out or nil
    end

    function U.with_prediction_snapshot(fn)
        if type(fn) ~= 'function' then
            log("error", "with_prediction_snapshot expected function, got: " .. tostring(type(fn)))
            return nil
        end

        if not (G and G.GAME and G.GAME.pseudorandom and copy_table) then
            log("debug", "Running prediction without snapshot (missing PRNG/copy_table context)")
            return safe_call(fn, "Prediction fallback execution failed")
        end

        local prng_snapshot = copy_table(G.GAME.pseudorandom)
        local overlay_snapshot = G.OVERLAY_MENU

        if not G.OVERLAY_MENU then
            G.OVERLAY_MENU = true
        end

        local ok, result = pcall(fn)

        G.GAME.pseudorandom = prng_snapshot
        G.OVERLAY_MENU = overlay_snapshot

        if ok then
            return result
        end

        log("warning", "Prediction snapshot execution failed: " .. tostring(result))
        return nil
    end

    function U.pick_center(card_type, rarity, legendary, forced_key, key_append)
        if forced_center_allowed(forced_key) then
            return G.P_CENTERS[forced_key]
        end

        local pool, pool_key = get_current_pool(card_type, rarity, legendary, key_append)
        if not (pool and next(pool) and pool_key) then
            log("error", "Center pool unavailable for type=" .. tostring(card_type) .. " key_append=" .. tostring(key_append))
            return nil
        end

        local center_key = pseudorandom_element(pool, pseudoseed(pool_key))
        local it = 1

        while center_key == 'UNAVAILABLE' do
            it = it + 1
            center_key = pseudorandom_element(pool, pseudoseed(pool_key .. '_resample' .. it))
        end

        local center = G.P_CENTERS[center_key]
        if not center then
            log("error", "Center lookup failed for key: " .. tostring(center_key))
        end
        return center
    end

    function U.descriptor_from_card(card)
        if not (card and card.config) then
            log("debug", "descriptor_from_card skipped: missing card/config")
            return nil
        end

        local center = card.config.center
        local front = card.config.card
        if not center and G and G.P_CENTERS then
            center = G.P_CENTERS.c_base
        end

        return {
            center = center or nil,
            front = front or nil,
            edition = U.copy_edition_flags(card.edition),
            seal = card.seal,
            sticker = card.sticker,
            sticker_run = card.sticker_run,
        }
    end

    function U.consumeable_free_slots(card)
        if not (G and G.consumeables and G.consumeables.config) then
            return 0
        end

        local delta = 0
        if card and card.area == G.consumeables and card.ability and card.ability.consumeable then
            delta = 1
        end

        return math.max(0, G.consumeables.config.card_limit - #G.consumeables.cards + delta)
    end

    function U.can_spawn_joker(card)
        if not (G and G.jokers and G.jokers.config) then
            return false
        end

        return (#G.jokers.cards < G.jokers.config.card_limit) or (card and card.area == G.jokers)
    end

    log("info", "Utility module initialized")
end
