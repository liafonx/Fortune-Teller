return function(FT)
    FT.utils = FT.utils or {}
    FT.runtime = FT.runtime or {}
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
        local used_jokers_snapshot = copy_table(G.GAME.used_jokers)
        local overlay_snapshot = G.OVERLAY_MENU

        if not G.OVERLAY_MENU then
            G.OVERLAY_MENU = true
        end

        local ok, result = pcall(fn)

        G.GAME.pseudorandom = prng_snapshot
        G.GAME.used_jokers = used_jokers_snapshot
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

    function U.can_spawn_joker(card)
        if not (G and G.jokers and G.jokers.config) then
            return false
        end

        return (#G.jokers.cards < G.jokers.config.card_limit) or (card and card.area == G.jokers)
    end

    function U.clamp(value, min_value, max_value)
        if value < min_value then
            return min_value
        end
        if value > max_value then
            return max_value
        end
        return value
    end

    function U.normalize_text(text)
        if type(text) ~= 'string' then
            return nil
        end
        local normalized = text:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
        if normalized == '' then
            return nil
        end
        return normalized
    end

    local PACK_STATE_KEYS = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK'}

    function U.is_pack_context_active()
        if not G then
            return false
        end

        if G.STATES and G.STATE then
            for i = 1, #PACK_STATE_KEYS do
                local state = G.STATES[PACK_STATE_KEYS[i]]
                if state and G.STATE == state then
                    return true
                end
            end
        end

        if G.booster_pack and not G.booster_pack.REMOVED then
            return true
        end
        if G.pack_cards and not G.pack_cards.REMOVED and G.pack_cards.cards and G.pack_cards.cards[1] then
            return true
        end

        return false
    end

    local function append_normalized(out, text)
        local normalized = U.normalize_text(text)
        if normalized then
            out[#out + 1] = normalized
        end
    end

    local function collect_dynastring_fragments(str, out, depth)
        if depth > 8 or str == nil then
            return
        end
        local t = type(str)
        if t == 'string' then
            append_normalized(out, str)
            return
        end
        if t ~= 'table' then
            return
        end

        local embedded = rawget(str, 'string')
        if type(embedded) == 'string' then
            append_normalized(out, embedded)
        end

        for i = 1, #str do
            collect_dynastring_fragments(str[i], out, depth + 1)
        end
    end

    local function collect_node_text(node, out, depth)
        if depth > 12 or node == nil then
            return
        end

        local node_type = type(node)
        if node_type == 'string' then
            append_normalized(out, node)
            return
        end
        if node_type ~= 'table' then
            return
        end

        local cfg = rawget(node, 'config')
        if type(cfg) == 'table' then
            append_normalized(out, cfg.text)

            local obj = rawget(cfg, 'object')
            if type(obj) == 'table' then
                collect_dynastring_fragments(rawget(obj, 'string'), out, 0)
            end
        end

        local children = rawget(node, 'nodes')
        if type(children) == 'table' then
            for i = 1, #children do
                collect_node_text(children[i], out, depth + 1)
            end
        end

        for i = 1, #node do
            collect_node_text(node[i], out, depth + 1)
        end
    end

    function U.extract_popup_title(name_nodes)
        if type(name_nodes) ~= 'table' then
            return nil
        end

        local fragments = {}
        for i = 1, #name_nodes do
            collect_node_text(name_nodes[i], fragments, 0)
        end

        if #fragments < 1 then
            return nil
        end
        return U.normalize_text(table.concat(fragments, ' '))
    end

    -- Check if j_showman is active in the joker area
    function U.has_showman()
        if not (G and G.jokers and G.jokers.cards) then return false end
        for _, j in ipairs(G.jokers.cards) do
            if j and j.config and j.config.center
                    and j.config.center.key == 'j_showman' and not j.debuff then
                return true
            end
        end
        return false
    end

    -- Note: "consumeable" (extra 'e') matches Balatro's own spelling of G.consumeables.
    -- This spelling is used consistently for all internal slot-cap helpers below.
    local function normalize_consumable_slot_cap(value)
        return (tonumber(value) or 0) >= 3 and 3 or 2
    end

    function U.set_consumable_slot_cap(cap)
        FT.runtime.consumeable_slot_cap = normalize_consumable_slot_cap(cap)
        return FT.runtime.consumeable_slot_cap
    end

    function U.refresh_consumable_slot_cap_from_run()
        if not (G and G.GAME) then
            return U.set_consumable_slot_cap(2)
        end

        local used = G.GAME.used_vouchers or {}
        return U.set_consumable_slot_cap(used.v_crystal_ball and 3 or 2)
    end

    function U.mark_crystal_ball_used()
        return U.set_consumable_slot_cap(3)
    end

    -- Cached base consumable slot cap for prediction display.
    -- Slot count is treated as 2 -> 3 (Crystal Ball) and never drops in-run.
    function U.consumeable_max_slots()
        local cached = FT.runtime.consumeable_slot_cap
        if type(cached) == 'number' then
            return cached
        end
        return U.refresh_consumable_slot_cap_from_run()
    end

    function U.set_joker_slot_cap(cap)
        FT.runtime.joker_slot_cap = math.max(0, tonumber(cap) or 0)
        return FT.runtime.joker_slot_cap
    end

    function U.refresh_joker_slot_cap_from_run()
        if not (G and G.GAME) then
            return U.set_joker_slot_cap(5)
        end

        local base = tonumber(G.GAME.starting_params and G.GAME.starting_params.joker_slots) or 5
        local used = G.GAME.used_vouchers or {}
        if used.v_antimatter then
            base = base + 1
        end
        return U.set_joker_slot_cap(base)
    end

    function U.mark_antimatter_used()
        local current = FT.runtime.joker_slot_cap
        if type(current) ~= 'number' then
            current = U.refresh_joker_slot_cap_from_run()
        end
        local base = tonumber(G and G.GAME and G.GAME.starting_params and G.GAME.starting_params.joker_slots) or 5
        local target = base + 1
        return U.set_joker_slot_cap(math.max(current, target))
    end

    -- Base joker slot cap (ignores negative-edition +slot inflation).
    -- Vanilla source model:
    -- - base starts from G.GAME.starting_params.joker_slots
    -- - Antimatter adds +1 to G.jokers.config.card_limit
    -- - set_joker_slots_ante challenge modifier can set Joker slots to 0
    -- - Negative jokers only inflate card_limit transiently
    function U.joker_max_slots()
        if not (G and G.GAME and G.jokers and G.jokers.config) then return 0 end

        local cached = FT.runtime.joker_slot_cap
        if type(cached) ~= 'number' then
            cached = U.refresh_joker_slot_cap_from_run()
        end

        local set_ante = G.GAME.modifiers and G.GAME.modifiers.set_joker_slots_ante
        local ante = G.GAME.round_resets and G.GAME.round_resets.ante
        if (tonumber(G.jokers.config.card_limit) or 0) <= 0 then
            return 0
        end
        if set_ante and ante and ante > set_ante then
            return 0
        end

        return math.max(0, cached)
    end

    function U.set_normal_probability(value)
        FT.runtime.normal_probability = tonumber(value) or 1
        return FT.runtime.normal_probability
    end

    function U.refresh_normal_probability_from_run()
        local normal = G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal
        return U.set_normal_probability(normal)
    end

    function U.normal_probability()
        local cached = FT.runtime.normal_probability
        if type(cached) == 'number' then
            return cached
        end
        return U.refresh_normal_probability_from_run()
    end

    -- Top card of current draw deck
    function U.deck_top_card()
        if not (G and G.deck and G.deck.cards and #G.deck.cards > 0) then return nil end
        return G.deck.cards[#G.deck.cards]
    end

    -- Misprint vanilla preview token format used in Card:generate_UIBox_ability_table:
    -- "#@<id><suit initial>", e.g. "#@14H"
    function U.misprint_draw_preview_token()
        local top = U.deck_top_card()
        if not (top and top.base) then return nil end
        local id = tonumber(top.base.id)
        local suit = type(top.base.suit) == 'string' and top.base.suit:sub(1, 1) or nil
        if not (id and suit and suit ~= '') then return nil end
        return '#@' .. tostring(id) .. tostring(suit)
    end

    -- Deterministic Misprint roll for a specific joker slot.
    -- `hovered_card` controls slot-order consumption (Blueprint/Brainstorm included).
    -- `effective_card` provides the min/max roll range (actual copied Misprint card).
    function U.predict_misprint_mult(hovered_card, effective_card)
        local target = effective_card or hovered_card
        if not (target and target.ability) then
            return nil
        end

        return U.with_prediction_snapshot(function()
            local hovered_idx = nil
            if hovered_card and G and G.jokers and G.jokers.cards then
                for i = 1, #G.jokers.cards do
                    if G.jokers.cards[i] == hovered_card then
                        hovered_idx = i
                        break
                    end
                end
            end

            if hovered_idx then
                for i = 1, hovered_idx - 1 do
                    local effective = U.resolve_effective_joker and U.resolve_effective_joker(i, {}) or nil
                    if effective and U.center_key_of(effective) == 'j_misprint' then
                        local prior_lo = effective.ability and effective.ability.extra and effective.ability.extra.min or 0
                        local prior_hi = effective.ability and effective.ability.extra and effective.ability.extra.max or 23
                        pseudorandom('misprint', prior_lo, prior_hi)
                    end
                end
            end

            local lo = target.ability.extra and target.ability.extra.min or 0
            local hi = target.ability.extra and target.ability.extra.max or 23
            return pseudorandom('misprint', lo, hi)
        end)
    end

    -- Game phase checks
    function U.is_playing_blind()
        if not (G and G.STATE and G.STATES) then return false end
        return G.STATE == G.STATES.HAND_PLAYED
            or G.STATE == G.STATES.DRAW_TO_HAND
            or G.STATE == G.STATES.SELECTING_HAND
    end

    function U.is_in_blind_select()
        if not (G and G.STATE and G.STATES) then return false end
        return G.STATE == G.STATES.BLIND_SELECT
    end

    function U.is_in_shop()
        if not (G and G.STATE and G.STATES) then return false end
        return G.STATE == G.STATES.SHOP
    end

    -- Mirrors blind-on-deck resolution from create_UIBox_blind_select.
    -- Returns 'Small' | 'Big' | 'Boss' (defaults to 'Boss' when uncertain).
    function U.next_blind_on_deck()
        local rr = G and G.GAME and G.GAME.round_resets
        local states = rr and rr.blind_states
        if type(states) ~= 'table' then
            return 'Boss'
        end

        local function blocked(v)
            return v == 'Defeated' or v == 'Skipped' or v == 'Hide'
        end

        if not blocked(states.Small) then return 'Small' end
        if not blocked(states.Big) then return 'Big' end
        return 'Boss'
    end

    function U.is_next_blind_boss()
        return U.next_blind_on_deck() == 'Boss'
    end

    -- Shared chain resolver: resolves the effective joker card at position idx through
    -- Blueprint/Brainstorm chains (arbitrary depth). Returns the effective card object,
    -- or nil on cycle / dead-end / debuffed target.
    -- `visited` should be a fresh {} per top-level call; passed recursively to break cycles.
    function U.resolve_effective_joker(idx, visited)
        if not (G and G.jokers and G.jokers.cards) then return nil end
        local cards = G.jokers.cards
        visited = visited or {}
        if idx < 1 or idx > #cards then return nil end
        if visited[idx] then return nil end  -- circuit breaker
        local j = cards[idx]
        if not j or j.debuff then return nil end
        local k = j.config and j.config.center and j.config.center.key
        if not k then return nil end
        visited[idx] = true
        if k == 'j_blueprint' then
            return U.resolve_effective_joker(idx + 1, visited)
        elseif k == 'j_brainstorm' then
            return U.resolve_effective_joker(1, visited)
        end
        return j
    end

    -- Count effective copies of a joker effect through Blueprint/Brainstorm chains.
    -- Use for jokers that ARE Blueprint/Brainstorm-compatible (most scoring jokers).
    function U.count_joker_copies(center_key)
        if not (G and G.jokers and G.jokers.cards) then return 0 end
        local count = 0
        local visited = {}
        for i = 1, #G.jokers.cards do
            -- Clear visited table between iterations without allocating a new one
            for k in pairs(visited) do visited[k] = nil end
            local effective = U.resolve_effective_joker(i, visited)
            if effective and effective.config and effective.config.center
                    and effective.config.center.key == center_key then
                count = count + 1
            end
        end
        return math.max(0, count)
    end

    -- Count ONLY direct copies of a joker effect (no Blueprint/Brainstorm).
    -- Use for jokers gated by `not context.blueprint` in vanilla source:
    -- j_madness (card.lua:2503) and j_sixth_sense (card.lua:2603).
    function U.count_direct_joker_copies(center_key)
        if not (G and G.jokers and G.jokers.cards) then return 0 end
        local count = 0
        for _, j in ipairs(G.jokers.cards) do
            if j and not j.debuff
                    and j.config and j.config.center
                    and j.config.center.key == center_key then
                count = count + 1
            end
        end
        return math.max(0, count)
    end

    -- Evaluate current highlighted hand using the game's poker evaluator.
    -- Returns: text (canonical hand name string), scoring_hand (array of card objects).
    -- Returns nil, nil if evaluation is unavailable or no cards highlighted.
    function U.highlighted_hand_type()
        local highlighted = G and G.hand and G.hand.highlighted
        if not (highlighted and #highlighted > 0) then return nil, nil end
        if not (G.FUNCS and G.FUNCS.get_poker_hand_info) then return nil, nil end
        local ok, text, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, highlighted)
        if not ok then return nil, nil end
        return text, scoring_hand
    end

    -- Buyable booster packs remaining in current shop
    function U.shop_packs_remaining()
        if not (G and G.shop_booster and G.shop_booster.cards) then return 0 end
        return #G.shop_booster.cards
    end

    function U.clone_descriptor(desc)
        if not desc then return nil end
        return {
            center = desc.center,
            front = desc.front,
            edition = U.copy_edition_flags(desc.edition),
            seal = desc.seal,
            sticker = desc.sticker,
            sticker_run = desc.sticker_run,
        }
    end

    function U.center_key_of(entry)
        return entry and entry.config and entry.config.center and entry.config.center.key or 'nil'
    end

    log("info", "Utility module initialized")
end
