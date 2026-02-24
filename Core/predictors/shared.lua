return function(FT)
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Predictors')) or function() end

    local S = {}
    local PURPLE_SEAL_PREVIEW_MAX = 3
    local PURPLE_SEAL_TAROT_KEY_APPEND = '8ba'

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

    local function count_highlighted_purple_seals()
        local highlighted = G and G.hand and G.hand.highlighted
        if type(highlighted) ~= 'table' then
            return 1
        end

        local count = 0
        for i = 1, #highlighted do
            local c = highlighted[i]
            if c and c.area == G.hand and c.highlighted and c.seal == 'Purple' and not c.debuff then
                count = count + 1
            end
        end

        if count < 1 then
            return 1
        end
        local slot_cap = math.min(PURPLE_SEAL_PREVIEW_MAX, U.consumeable_max_slots())
        return math.min(math.max(1, slot_cap), count)
    end

    function S.predict_multi_consumables(card_type, key_append, amount)
        local count = amount or 0
        if count <= 0 then
            log('debug', 'No multi-consumable prediction count for ' .. tostring(card_type))
            return nil
        end

        return U.with_prediction_snapshot(function()
            local showman = U.has_showman()
            local out = {}
            for _ = 1, count do
                local center = U.pick_center(card_type, nil, nil, nil, key_append)
                if not center then
                    log('error', 'Failed to pick center for ' .. tostring(card_type) .. ' (' .. tostring(key_append) .. ')')
                    return nil
                end
                out[#out + 1] = {center = center}
                if not showman then G.GAME.used_jokers[center.key] = true end
            end
            return out
        end)
    end

    function S.predict_purple_seal_tarot(card)
        if not (card and card.seal == 'Purple') then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local count = count_highlighted_purple_seals()
            local showman = U.has_showman()
            local out = {}

            for _ = 1, count do
                local center = U.pick_center('Tarot', nil, nil, nil, PURPLE_SEAL_TAROT_KEY_APPEND)
                if not center then
                    log('error', 'Failed to pick Tarot center for purple seal preview sequence')
                    return nil
                end
                out[#out + 1] = {center = center}
                if not showman then G.GAME.used_jokers[center.key] = true end
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
            local suit_obj = pseudorandom_element(SMODS.Suits, pseudoseed(seed_key))
            local card_key = suit_obj and suit_obj.card_key
            return card_key and G.P_CARDS[card_key .. '_A'] or nil
        end)
    end

    function S.predict_ouija()
        return predict_base_card_front('ouija', function(seed_key)
            local rank_obj = pseudorandom_element(SMODS.Ranks, pseudoseed(seed_key))
            local card_key = rank_obj and rank_obj.card_key
            return card_key and G.P_CARDS['H_' .. card_key] or nil
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
            local success = pseudorandom('wheel_of_fortune') < U.normal_probability() / card.ability.extra
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
                    local suit_obj = pseudorandom_element(SMODS.Suits, pseudoseed('familiar_create'))
                    suit = suit_obj and suit_obj.card_key
                    rank = pseudorandom_element({'J', 'Q', 'K'}, pseudoseed('familiar_create'))
                elseif card_key == 'c_grim' then
                    local suit_obj = pseudorandom_element(SMODS.Suits, pseudoseed('grim_create'))
                    suit = suit_obj and suit_obj.card_key
                    rank = 'A'
                elseif card_key == 'c_incantation' then
                    local suit_obj = pseudorandom_element(SMODS.Suits, pseudoseed('incantation_create'))
                    suit = suit_obj and suit_obj.card_key
                    rank = pseudorandom_element({'2', '3', '4', '5', '6', '7', '8', '9', 'T'}, pseudoseed('incantation_create'))
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

    function S.predict_random_joker(card, rarity, legendary, key_append, opts)
        local bypass_slot_constraint = opts and opts.bypass_slot_constraint
        if (not bypass_slot_constraint) and (not U.can_spawn_joker(card)) then
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
        local joker_cards = get_joker_state()
        if not joker_cards then
            return nil
        end
        if U.joker_max_slots() <= 1 or #joker_cards < 1 then
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
            return single_descriptor(U.descriptor_from_card(chosen))
        end)
    end

    -- Picks N centers of card_type using key_append; handles Showman gate internally.
    -- count should already be clamped to available slots by caller.
    -- Caches has_showman once per call to avoid O(jokers) scan per item.
    local function pick_n_centers(card_type, key_append, count, rarity)
        local showman = U.has_showman()  -- cache once, not per-iteration
        local results = {}
        for _ = 1, count do
            local center = U.pick_center(card_type, rarity, nil, nil, key_append)
            if center then
                if not showman then G.GAME.used_jokers[center.key] = true end
                results[#results + 1] = {center = center}
            end
        end
        return #results > 0 and results or nil
    end

    -- Dynamic base consumable slot count (0 if unavailable).
    -- This intentionally ignores current fill.
    local function slot_budget(card)
        return math.max(0, U.consumeable_max_slots())
    end

    -- Resolves effective slot count for simple (non-tracking) consumable-generating predictors.
    local function consumeable_slot_count(card, intended)
        return math.min(intended, slot_budget(card))
    end

    -- Shared helper: rolls probability-based Tarot generation with Nope display.
    -- opts: { seed (string), key_append (string), total (int), threshold (number), slot_cap (int) }
    local function predict_probability_tarot(opts)
        local slot_cap = opts.slot_cap
        local slots_remaining = slot_cap
        return U.with_prediction_snapshot(function()
            local showman = U.has_showman()
            local successes, nope_count = {}, 0
            for _ = 1, opts.total do
                if slots_remaining <= 0 then break end
                if pseudorandom(opts.seed) < opts.threshold then
                    local center = U.pick_center('Tarot', nil, nil, nil, opts.key_append)
                    if center then
                        if not showman then G.GAME.used_jokers[center.key] = true end
                        successes[#successes + 1] = {center = center}
                        slots_remaining = slots_remaining - 1
                    end
                else
                    nope_count = nope_count + 1
                end
            end
            local results = {}
            for _, s in ipairs(successes) do results[#results + 1] = s end
            local nope_to_show = math.min(nope_count, math.max(0, slot_cap - #successes))
            for _ = 1, nope_to_show do results[#results + 1] = {kind = 'text', text_key = 'k_nope_ex'} end
            return #results > 0 and results or nil
        end)
    end

    function S.predict_8_ball(card)
        local highlighted = G and G.hand and G.hand.highlighted or {}
        local eights = 0
        for _, c in ipairs(highlighted) do
            if c and c:get_id() == 8 and not c.debuff then eights = eights + 1 end
        end
        if eights == 0 then return nil end
        local copies = U.count_joker_copies('j_8_ball')
        local slot_cap = slot_budget(card)
        if slot_cap == 0 then return nil end
        return predict_probability_tarot({
            seed       = '8ball',
            key_append = '8ba',
            total      = eights * copies,
            threshold  = U.normal_probability() / (card.ability.extra or 4),
            slot_cap   = slot_cap,
        })
    end

    function S.predict_misprint(card, hovered_card)
        -- 'card' is the effective j_misprint card (engine resolves Blueprint/Brainstorm).
        -- 'hovered_card' keeps original joker slot identity so copies can show slot-accurate rolls.
        local mult = U.predict_misprint_mult and U.predict_misprint_mult(hovered_card or card, card) or nil
        if mult == nil then return nil end
        return {{
            kind = 'misprint_mult',
            mult = mult,
        }}
    end

    function S.predict_madness(card)
        -- Boss blind gate: j_madness doesn't fire on boss blinds (card.lua:2503).
        -- Also suppress preview when the upcoming blind on deck is Boss.
        -- Trigger conditions — not bypassed by timing_always.
        if G and G.GAME and G.GAME.blind and G.GAME.blind.boss then return nil end
        if U.is_next_blind_boss and U.is_next_blind_boss() then return nil end
        local joker_cards, joker_config = get_joker_state()
        if not joker_cards then return nil end
        -- Collect direct Madness copies in joker-area order (card.lua:2503: not context.blueprint)
        local madness_cards = {}
        for _, j in ipairs(joker_cards) do
            if j and not j.debuff
                    and j.config and j.config.center
                    and j.config.center.key == 'j_madness' then
                madness_cards[#madness_cards + 1] = j
            end
        end
        if #madness_cards == 0 then return nil end
        return U.with_prediction_snapshot(function()
            -- Base eligible pool: non-eternal, not already getting_sliced
            local base_eligible = {}
            for _, j in ipairs(joker_cards) do
                if not (j.ability and j.ability.eternal) and not j.getting_sliced then
                    base_eligible[#base_eligible + 1] = j
                end
            end
            local results = {}
            local claimed = {}  -- jokers chosen by earlier copies in this simulation
            for _, m in ipairs(madness_cards) do
                -- Each Madness copy excludes itself + already-claimed jokers (mirrors vanilla)
                local pool = {}
                for _, j in ipairs(base_eligible) do
                    if j ~= m and not claimed[j] then pool[#pool + 1] = j end
                end
                if #pool == 0 then break end
                local chosen = pseudorandom_element(pool, pseudoseed('madness'))
                if chosen then
                    claimed[chosen] = true
                    local desc = U.descriptor_from_card(chosen)
                    if desc then
                        desc.destroyed = true
                        results[#results + 1] = desc
                    end
                end
            end
            return #results > 0 and results or nil
        end)
    end

    function S.predict_riff_raff(card)
        local joker_cards = get_joker_state()
        if not joker_cards then return nil end
        local copies = U.count_joker_copies('j_riff_raff')
        -- Cap by base max Joker slots after accounting for triggering copies only.
        local max_spawns = math.max(0, U.joker_max_slots() - copies)
        local count = math.min(copies * 2, max_spawns)
        if count == 0 then return nil end
        return U.with_prediction_snapshot(function()
            return pick_n_centers('Joker', 'rif', count, 0)  -- rarity 0 = Common pool
        end)
    end

    function S.predict_hallucination(card)
        local copies = U.count_joker_copies('j_hallucination')
        local packs = U.shop_packs_remaining()
        -- Support choosing-blind saves: if no shop packs are instantiated yet, reserve one
        -- virtual "next pack" preview while on blind-select.
        if packs == 0 and U.is_in_blind_select() then
            packs = 1
        end
        if copies == 0 or packs == 0 then return nil end
        local slot_cap = slot_budget(card)
        if slot_cap == 0 then return nil end
        local ante = G.GAME.round_resets and G.GAME.round_resets.ante or 1
        return predict_probability_tarot({
            seed       = 'halu' .. ante,
            key_append = 'hal',
            total      = copies,
            threshold  = U.normal_probability() / (card.ability.extra or 2),
            slot_cap   = slot_cap,
        })
    end

    function S.predict_vagabond(card)
        local threshold_dollars = card.ability.extra or 4
        if not (G and G.GAME and G.GAME.dollars <= threshold_dollars) then return nil end
        local copies = U.count_joker_copies('j_vagabond')
        local count = consumeable_slot_count(card, copies)
        if count == 0 then return nil end
        return U.with_prediction_snapshot(function()
            return pick_n_centers('Tarot', 'vag', count)
        end)
    end

    function S.predict_superposition(card)
        local hand_text, scoring_hand = U.highlighted_hand_type()
        if hand_text ~= 'Straight' then return nil end
        -- Vanilla loops scoring_hand and checks get_id() == 14 for Ace (card.lua:3762-3770)
        local has_ace = false
        for _, c in ipairs(scoring_hand or {}) do
            if c:get_id() == 14 then has_ace = true; break end
        end
        if not has_ace then return nil end
        local copies = U.count_joker_copies('j_superposition')
        local count = consumeable_slot_count(card, copies)
        if count == 0 then return nil end
        return U.with_prediction_snapshot(function()
            return pick_n_centers('Tarot', 'sup', count)
        end)
    end

    function S.predict_cartomancer(card)
        local copies = U.count_joker_copies('j_cartomancer')
        local count = consumeable_slot_count(card, copies)
        if count == 0 then return nil end
        return U.with_prediction_snapshot(function()
            return pick_n_centers('Tarot', 'car', count)
        end)
    end

    function S.predict_sixth_sense(card)
        -- First hand constraint: G.GAME.current_round.hands_played == 0 (card.lua:2604)
        if not (G and G.GAME and G.GAME.current_round
                and G.GAME.current_round.hands_played == 0) then
            return nil
        end
        local highlighted = G and G.hand and G.hand.highlighted or {}
        -- Vanilla: exactly one card played, that card is a 6 (card.lua:2604: #context.full_hand == 1)
        if #highlighted ~= 1
                or highlighted[1]:get_id() ~= 6
                or highlighted[1].debuff then
            return nil
        end
        -- Direct count only: Blueprint/Brainstorm cannot trigger Sixth Sense (card.lua:2603)
        local copies = U.count_direct_joker_copies('j_sixth_sense')
        local count = consumeable_slot_count(card, copies)
        if count == 0 then return nil end
        return U.with_prediction_snapshot(function()
            return pick_n_centers('Spectral', 'sixth', count)
        end)
    end

    function S.predict_seance(card)
        local required_hand = card.ability and card.ability.extra and card.ability.extra.poker_hand
        if required_hand then
            local hand_text = U.highlighted_hand_type()  -- first return value only
            if hand_text ~= required_hand then return nil end
        end
        local copies = U.count_joker_copies('j_seance')
        local count = consumeable_slot_count(card, copies)
        if count == 0 then return nil end
        return U.with_prediction_snapshot(function()
            return pick_n_centers('Spectral', 'sea', count)
        end)
    end

    function S.predict_certificate(card)
        local copies = U.count_joker_copies('j_certificate')
        if copies == 0 then return nil end
        return U.with_prediction_snapshot(function()
            local results = {}
            for _ = 1, copies do
                local front = pseudorandom_element(G.P_CARDS, pseudoseed('cert_fr'))
                local seal_roll = pseudorandom(pseudoseed('certsl'))
                local seal
                if seal_roll > 0.75 then      seal = 'Red'    -- verified order from card.lua:2470
                elseif seal_roll > 0.5 then   seal = 'Blue'
                elseif seal_roll > 0.25 then  seal = 'Gold'
                else                           seal = 'Purple'
                end
                results[#results + 1] = {center = G.P_CENTERS.c_base, front = front, seal = seal}
            end
            return #results > 0 and results or nil
        end)
    end

    function S.predict_perkeo(card)
        if not (G and G.consumeables and #G.consumeables.cards > 0) then return nil end
        local copies = U.count_joker_copies('j_perkeo')
        if copies == 0 then return nil end
        return U.with_prediction_snapshot(function()
            local results = {}
            local pool = {unpack(G.consumeables.cards)}

            for _ = 1, copies do
                local chosen = pseudorandom_element(pool, pseudoseed('perkeo'))
                if chosen then
                    local desc = U.descriptor_from_card(chosen)
                    if desc then
                        desc.edition = {negative = true}
                        results[#results + 1] = U.clone_descriptor(desc)
                    end
                end
            end
            log('debug', function()
                return 'Perkeo predict summary: copies=' .. tostring(copies)
                    .. ' pool_size=' .. tostring(#pool)
                    .. ' results=' .. tostring(#results)
            end)
            return #results > 0 and results or nil
        end)
    end

    return S
end
