return function(S)
    local routes_by_key = {
        c_wheel_of_fortune = S.predict_wheel_of_fortune,
        c_judgement = function(card)
            return S.predict_random_joker(card, nil, nil, 'jud', {bypass_slot_constraint = true})
        end,
        c_soul = function(card)
            return S.predict_random_joker(card, nil, true, 'sou', {bypass_slot_constraint = true})
        end,
        c_wraith = function(card)
            return S.predict_random_joker(card, 0.99, nil, 'wra', {bypass_slot_constraint = true})
        end,
        c_emperor = function(card)
            local amount = card.ability.consumeable and card.ability.consumeable.tarots
            return S.predict_multi_consumables('Tarot', 'emp', amount)
        end,
        c_high_priestess = function(card)
            local amount = card.ability.consumeable and card.ability.consumeable.planets
            return S.predict_multi_consumables('Planet', 'pri', amount)
        end,

        c_aura = S.predict_aura,
        c_sigil = S.predict_sigil,
        c_ouija = S.predict_ouija,
        c_hex = function(card)
            return S.predict_random_joker_effect(card.eligible_editionless_jokers, 'hex', {polychrome = true})
        end,
        c_ectoplasm = function(card)
            return S.predict_random_joker_effect(card.eligible_editionless_jokers, 'ectoplasm', {negative = true})
        end,
        c_ankh = S.predict_ankh,
        c_familiar = S.predict_familiar_grim_incantation,
        c_grim = S.predict_familiar_grim_incantation,
        c_incantation = S.predict_familiar_grim_incantation,
        c_immolate = S.predict_immolate,

        j_invisible = S.predict_invisible_joker,
    }

    return {
        routes_by_key = routes_by_key,
    }
end
