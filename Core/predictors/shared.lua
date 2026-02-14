return function(FT)
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Predictors')) or function() end

    local S = {}
    local SUIT_KEYS = {'S', 'H', 'D', 'C'}
    local RANK_KEYS = {'2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'}

    local function get_hand_cards()
        return G and G.hand and G.hand.cards or nil
    end

    local function hand_has_at_least(min_count)
        local cards = get_hand_cards()
        return cards and #cards >= (min_count or 1)
    end

    local function get_joker_state()
        if not (G and G.jokers and G.jokers.cards and G.jokers.config) then
            return nil, nil
        end
        return G.jokers.cards, G.jokers.config
    end

    local cached_enhanced_pool = nil
    local cached_enhanced_pool_size = -1

    local function single_descriptor(desc)
        if not desc then
            return nil
        end
        return {desc}
    end

    function S.predict_multi_consumables(card_type, key_append, amount)
        local count = amount or 0
        if count <= 0 then
            log('debug', 'No multi-consumable prediction count for ' .. tostring(card_type))
            return nil
        end

        return U.with_prediction_snapshot(function()
            local out = {}
            for _ = 1, count do
                local center = U.pick_center(card_type, nil, nil, nil, key_append)
                if not center then
                    log('error', 'Failed to pick center for ' .. tostring(card_type) .. ' (' .. tostring(key_append) .. ')')
                    return nil
                end
                out[#out + 1] = {center = center}
            end
            return out
        end)
    end

    local function predict_base_card_front(seed_key, front_resolver, edition)
        return U.with_prediction_snapshot(function()
            local front = front_resolver(seed_key)
            if not front then
                log('debug', 'Base card front resolver returned nil for seed: ' .. tostring(seed_key))
                return nil
            end

            return single_descriptor({
                center = G.P_CENTERS.c_base,
                front = front,
                edition = edition,
            })
        end)
    end

    function S.predict_aura()
        return U.with_prediction_snapshot(function()
            local edition = poll_edition('aura', nil, true, true)
            if not edition then
                return nil
            end

            return single_descriptor({
                center = G.P_CENTERS.c_base,
                front = G.P_CARDS.H_A,
                edition = edition,
            })
        end)
    end

    function S.predict_sigil()
        return predict_base_card_front('sigil', function(seed_key)
            local suit = pseudorandom_element(SUIT_KEYS, pseudoseed(seed_key))
            return suit and G.P_CARDS[suit .. '_A'] or nil
        end)
    end

    function S.predict_ouija()
        return predict_base_card_front('ouija', function(seed_key)
            local rank = pseudorandom_element(RANK_KEYS, pseudoseed(seed_key))
            return rank and G.P_CARDS['H_' .. rank] or nil
        end)
    end

    local function build_non_stone_enhanced_pool()
        local enhanced_pool_source = G.P_CENTER_POOLS['Enhanced'] or {}
        local source_size = #enhanced_pool_source
        if cached_enhanced_pool and cached_enhanced_pool_size == source_size then
            return cached_enhanced_pool
        end

        local pool = {}
        for _, center in pairs(enhanced_pool_source) do
            if center.key ~= 'm_stone' then
                pool[#pool + 1] = center
            end
        end
        cached_enhanced_pool = pool
        cached_enhanced_pool_size = source_size
        return pool
    end

    function S.predict_wheel_of_fortune(card)
        local eligible = card.eligible_strength_jokers
        if not (eligible and next(eligible)) then
            log('debug', 'Wheel prediction skipped: no eligible jokers')
            return nil
        end

        return U.with_prediction_snapshot(function()
            local success = pseudorandom('wheel_of_fortune') < G.GAME.probabilities.normal / card.ability.extra
            if not success then
                log('debug', 'Wheel prediction result: k_nope_ex')
                return {
                    {kind = 'text', text_key = 'k_nope_ex'},
                }
            end

            local chosen = pseudorandom_element(eligible, pseudoseed('wheel_of_fortune'))
            local desc = U.descriptor_from_card(chosen)
            if not (desc and desc.center) then
                log('error', 'Wheel prediction failed to resolve eligible joker descriptor')
                return nil
            end

            desc.edition = poll_edition('wheel_of_fortune', nil, true, true)
            log('debug', 'Wheel prediction success: center=' .. tostring(desc.center and desc.center.key))
            return single_descriptor(desc)
        end)
    end

    local function pick_destroyed_for_familiar_family()
        local hand_cards = get_hand_cards()
        if not (hand_cards and #hand_cards > 0) then
            return nil
        end
        return pseudorandom_element(hand_cards, pseudoseed('random_destroy'))
    end

    local function pick_destroyed_for_immolate(card)
        local hand_cards = get_hand_cards()
        if not (hand_cards and #hand_cards > 0) then
            return {}
        end

        local temp_hand = {}
        for _, v in ipairs(hand_cards) do
            temp_hand[#temp_hand + 1] = v
        end
        table.sort(temp_hand, function(a, b)
            return not a.playing_card or not b.playing_card or a.playing_card < b.playing_card
        end)
        pseudoshuffle(temp_hand, pseudoseed('immolate'))

        local out = {}
        local destroy_count = (card.ability and card.ability.extra and card.ability.extra.destroy) or 0
        for i = 1, destroy_count do
            if temp_hand[i] then
                out[#out + 1] = temp_hand[i]
            end
        end
        return out
    end

    local function build_created_playing_descriptor(suit, rank)
        local enhanced_pool = build_non_stone_enhanced_pool()
        if #enhanced_pool < 1 then
            log('error', 'Enhanced pool unavailable while predicting spectral create')
            return nil
        end

        local center = pseudorandom_element(enhanced_pool, pseudoseed('spe_card'))
        if not center then
            log('error', 'Failed to pick enhanced center for spectral create')
            return nil
        end

        local front = G.P_CARDS[(suit or 'S') .. '_' .. (rank or 'A')]
        if not front then
            log('error', 'Failed to build front for spectral create: ' .. tostring(suit) .. '_' .. tostring(rank))
            return nil
        end

        return {
            center = center,
            front = front,
        }
    end

    function S.predict_familiar_grim_incantation(card)
        if not hand_has_at_least(2) then
            log('debug', 'Spectral destroy/create prediction skipped: hand unavailable or insufficient cards')
            return nil
        end

        local card_key = card.config and card.config.center and card.config.center.key
        if not (card_key == 'c_familiar' or card_key == 'c_grim' or card_key == 'c_incantation') then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local destroyed = pick_destroyed_for_familiar_family()
            local destroyed_desc = U.descriptor_from_card(destroyed)
            if not (destroyed_desc and destroyed_desc.center) then
                log('error', 'Failed to resolve destroyed card for ' .. tostring(card_key))
                return nil
            end
            destroyed_desc.destroyed = true

            local out = {destroyed_desc}
            local create_count = (card.ability and card.ability.extra) or 0
            for _ = 1, create_count do
                local suit, rank
                if card_key == 'c_familiar' then
                    rank = pseudorandom_element({'J', 'Q', 'K'}, pseudoseed('familiar_create'))
                    suit = pseudorandom_element(SUIT_KEYS, pseudoseed('familiar_create'))
                elseif card_key == 'c_grim' then
                    rank = 'A'
                    suit = pseudorandom_element(SUIT_KEYS, pseudoseed('grim_create'))
                elseif card_key == 'c_incantation' then
                    rank = pseudorandom_element({'2', '3', '4', '5', '6', '7', '8', '9', 'T'}, pseudoseed('incantation_create'))
                    suit = pseudorandom_element(SUIT_KEYS, pseudoseed('incantation_create'))
                end

                local created = build_created_playing_descriptor(suit, rank)
                if not created then
                    return nil
                end
                out[#out + 1] = created
            end

            log('debug', tostring(card_key) .. ' prediction: 1 destroyed + ' .. tostring(create_count) .. ' created')
            return out
        end)
    end

    function S.predict_immolate(card)
        if not hand_has_at_least(2) then
            log('debug', 'Immolate prediction skipped: hand unavailable or insufficient cards')
            return nil
        end

        return U.with_prediction_snapshot(function()
            local destroyed = pick_destroyed_for_immolate(card)
            if #destroyed < 1 then
                return nil
            end

            local out = {}
            for i = 1, #destroyed do
                local desc = U.descriptor_from_card(destroyed[i])
                if desc and desc.center then
                    desc.destroyed = true
                    out[#out + 1] = desc
                end
            end
            log('debug', 'Immolate prediction: destroyed count=' .. tostring(#out))
            return (#out > 0) and out or nil
        end)
    end

    function S.predict_random_joker_effect(card_list, seed_key, edition_override)
        if not (card_list and next(card_list)) then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local chosen = pseudorandom_element(card_list, pseudoseed(seed_key))
            local desc = U.descriptor_from_card(chosen)
            if not (desc and desc.center) then
                log('debug', 'Random joker effect descriptor unavailable for seed: ' .. tostring(seed_key))
                return nil
            end

            if edition_override then
                desc.edition = copy_table(edition_override)
            end

            return single_descriptor(desc)
        end)
    end

    function S.predict_random_joker(card, rarity, legendary, key_append)
        if not U.can_spawn_joker(card) then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local center = U.pick_center('Joker', rarity, legendary, nil, key_append)
            if not center then
                log('error', 'Random joker center resolution failed for key_append=' .. tostring(key_append))
                return nil
            end
            local edition = poll_edition('edi' .. (key_append or '') .. G.GAME.round_resets.ante)
            return single_descriptor({
                center = center,
                edition = edition,
            })
        end)
    end

    function S.predict_ankh(card)
        if not (card and card.ability) then
            return nil
        end
        local joker_cards, joker_config = get_joker_state()
        if not (joker_cards and joker_config) then
            return nil
        end
        if joker_config.card_limit <= 1 or #joker_cards < 1 then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local chosen = pseudorandom_element(joker_cards, pseudoseed('ankh_choice'))
            local desc = U.descriptor_from_card(chosen)
            if not desc then
                return nil
            end

            if desc.edition and desc.edition.negative then
                desc.edition = nil
            end

            return single_descriptor(desc)
        end)
    end

    function S.predict_invisible_joker(card)
        if not (card and card.ability) then
            return nil
        end
        local show_pretrigger = FT.config_api and FT.config_api.show_invisible_pretrigger and FT.config_api.show_invisible_pretrigger()
        if not show_pretrigger and card.ability.invis_rounds < card.ability.extra then
            return nil
        end
        local joker_cards, joker_config = get_joker_state()
        if not (joker_cards and joker_config) then
            return nil
        end
        if #joker_cards > joker_config.card_limit then
            return nil
        end

        local eligible_jokers = {}
        for i = 1, #joker_cards do
            if joker_cards[i] ~= card then
                eligible_jokers[#eligible_jokers + 1] = joker_cards[i]
            end
        end
        if #eligible_jokers < 1 then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local chosen = pseudorandom_element(eligible_jokers, pseudoseed('invisible'))
            if not chosen then
                return nil
            end

            return single_descriptor({
                center = chosen.config.center,
                front = chosen.config.card,
                edition = U.copy_edition_flags(chosen.edition),
                seal = chosen.seal,
                sticker = chosen.sticker,
                sticker_run = chosen.sticker_run,
            })
        end)
    end

    return S
end
