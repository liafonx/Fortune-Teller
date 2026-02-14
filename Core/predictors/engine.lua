return function(FT)
    FT.predictors = FT.predictors or {}
    local P = FT.predictors
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Predictors')) or function() end

    local shared = FT.load_module('Core/predictors/shared.lua')(FT)
    local routes = FT.load_module('Core/predictors/routes.lua')(shared)
    P.routes_by_key = routes.routes_by_key

    function P.predict_descriptors(card)
        if not (card and card.ability and G and G.GAME) then
            return nil
        end

        local center_key = card.config and card.config.center and card.config.center.key
        if FT.config_api and FT.config_api.is_card_enabled and not FT.config_api.is_card_enabled(center_key) then
            return nil
        end

        local resolver = P.routes_by_key and P.routes_by_key[center_key]
        if not resolver then
            return nil
        end

        local result = resolver(card)
        if not result then
            log('debug', 'Predictor route returned no preview for card: key=' .. tostring(center_key))
        end
        return result
    end

    log('info', 'Predictor module initialized')
end
