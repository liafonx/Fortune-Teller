return function(FT)
    local U = FT.utils
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('Preview')) or function() end

    FT.preview = FT.preview or {}
    local Preview = FT.preview
    local PREVIEW_SCALE = 0.56

    local function disable_interaction_states(node)
        if not (node and node.states) then
            return
        end

        if node.states.hover then
            node.states.hover.can = false
        end
        if node.states.click then
            node.states.click.can = false
        end
        if node.states.drag then
            node.states.drag.can = false
        end
        if node.states.collide then
            node.states.collide.can = false
        end
    end

    local function freeze_preview_card(card)
        if not card then
            return nil
        end

        card.no_ui = true
        disable_interaction_states(card)

        for _, child in pairs(card.children or {}) do
            disable_interaction_states(child)
        end

        return card
    end

    function Preview.make_preview_card(desc)
        if not desc or not desc.center then
            log("debug", "Preview skipped: missing descriptor center")
            return nil
        end

        local preview = U.with_prediction_snapshot(function()
            local card = Card(
                0,
                0,
                G.CARD_W * PREVIEW_SCALE,
                G.CARD_H * PREVIEW_SCALE,
                desc.front,
                desc.center,
                {
                    bypass_discovery_center = true,
                    bypass_discovery_ui = true,
                    bypass_lock = true,
                }
            )

            if desc.edition then
                card:set_edition(copy_table(desc.edition), true, true)
            end

            if desc.seal then
                card:set_seal(desc.seal, true)
            end

            if desc.sticker then
                card.sticker = desc.sticker
            end

            if desc.sticker_run then
                card.sticker_run = desc.sticker_run
            end

            if desc.destroyed then
                card:set_debuff(true)
            end

            return card
        end)

        if not preview then
            log("error", "Preview card creation failed for center: " .. tostring(desc.center and desc.center.key))
            return nil
        end

        return freeze_preview_card(preview)
    end

    function Preview.cleanup_preview_cards(card)
        if not (card and card._ft_preview_cards) then
            return
        end

        local overlay_snapshot = G and G.OVERLAY_MENU
        if G and not G.OVERLAY_MENU then
            G.OVERLAY_MENU = true
        end

        for _, preview in ipairs(card._ft_preview_cards) do
            if preview and not preview.removed then
                local ok, err = pcall(function()
                    preview:remove()
                end)
                if not ok then
                    log("warning", "Failed to remove preview card: " .. tostring(err))
                end
            end
        end

        if G then
            G.OVERLAY_MENU = overlay_snapshot
        end

        card._ft_preview_cards = nil
    end

    log("info", "Preview module initialized")
end
