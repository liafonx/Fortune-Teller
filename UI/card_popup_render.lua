return function(FT)
    local log = (FT.Logger and FT.Logger.create and FT.Logger.create('CardPopupRender')) or function() end

    local DEFAULT_FORECAST_BG_MIX = 0.8
    local MINI_HEADING_SIDE_PADDING = 0.05

    local NopeStampIcon = nil

    local function clamp(value, min_value, max_value)
        if value < min_value then
            return min_value
        end
        if value > max_value then
            return max_value
        end
        return value
    end

    local function create_nope_stamp_icon(text, w, h, stamp_colour, text_colour, text_scale)
        if not (Moveable and Moveable.extend and love and love.graphics) then
            return nil
        end

        if not NopeStampIcon then
            NopeStampIcon = Moveable:extend()

            function NopeStampIcon:init(icon_w, icon_h, icon_text, icon_stamp_colour, icon_text_colour, icon_text_scale)
                Moveable.init(self, 0, 0, icon_w, icon_h)
                self.text = tostring(icon_text or '')
                self.stamp_colour = {
                    (icon_stamp_colour and icon_stamp_colour[1]) or 0.7,
                    (icon_stamp_colour and icon_stamp_colour[2]) or 0.4,
                    (icon_stamp_colour and icon_stamp_colour[3]) or 0.85,
                    (icon_stamp_colour and icon_stamp_colour[4]) or 1,
                }
                self.text_colour = {
                    (icon_text_colour and icon_text_colour[1]) or 1,
                    (icon_text_colour and icon_text_colour[2]) or 1,
                    (icon_text_colour and icon_text_colour[3]) or 1,
                    (icon_text_colour and icon_text_colour[4]) or 1,
                }
                self.text_scale = icon_text_scale or 0.58
                self.font = (G and G.LANG and G.LANG.font and G.LANG.font.FONT) or love.graphics.getFont()
                self.text_obj = love.graphics.newText(self.font, self.text)
                self.states = {
                    drag = {can = false},
                    hover = {can = false},
                    collide = {can = false},
                }
            end

            function NopeStampIcon:draw()
                if not self.VT then
                    return
                end

                prep_draw(self, 1)
                love.graphics.scale(1 / G.TILESIZE)

                local w_px = math.max(1, self.VT.w * G.TILESIZE)
                local h_px = math.max(1, self.VT.h * G.TILESIZE)
                local lang_font = (G and G.LANG and G.LANG.font) or {}
                local base_scale = self.text_scale * 1.12
                local font_scale = (lang_font.FONTSCALE or 1)
                local squish = (lang_font.squish or 1)
                local base_sx = base_scale * squish * font_scale
                local base_sy = base_scale * font_scale
                local raw_w = (self.text_obj and self.text_obj:getWidth() or 0)
                local raw_h = (self.text_obj and self.text_obj:getHeight() or 0)
                local side = math.max(10, math.min(w_px, h_px) * 0.8)
                local fit_h = (side * 0.66) / math.max(1, raw_h * base_sy)
                local fit_w = (w_px * 0.9) / math.max(1, raw_w * base_sx)
                local fit = clamp(math.min(fit_h, fit_w), 0.72, 1.0)
                local sx = base_sx * fit
                local sy = base_sy * fit
                local tw = raw_w * sx
                local th = raw_h * sy
                local tx = math.floor((w_px - tw) * 0.5 + 0.5)
                local ty = math.floor((h_px - th) * 0.5 + 0.5)
                local cx = tx + (tw * 0.56)
                local cy = ty + (th * 0.52)
                local half = side * 0.5

                if G.SETTINGS and G.SETTINGS.GRAPHICS and G.SETTINGS.GRAPHICS.shadows == 'On' then
                    love.graphics.push()
                    love.graphics.translate(cx + 1.4, cy + 1.4)
                    love.graphics.rotate(math.rad(22))
                    love.graphics.setColor(0, 0, 0, 0.26)
                    love.graphics.rectangle('fill', -half, -half, side, side)
                    love.graphics.pop()
                end

                love.graphics.push()
                love.graphics.translate(cx, cy)
                love.graphics.rotate(math.rad(22))
                love.graphics.setColor(self.stamp_colour[1], self.stamp_colour[2], self.stamp_colour[3], self.stamp_colour[4] or 1)
                love.graphics.rectangle('fill', -half, -half, side, side)
                love.graphics.pop()

                love.graphics.setColor(0, 0, 0, 0.35)
                love.graphics.draw(self.text_obj, tx + 1, ty + 1, 0, sx, sy)
                love.graphics.setColor(self.text_colour[1], self.text_colour[2], self.text_colour[3], self.text_colour[4] or 1)
                love.graphics.draw(self.text_obj, tx, ty, 0, sx, sy)

                love.graphics.pop()
            end
        end

        return NopeStampIcon(w or 1, h or 0.5, text, stamp_colour, text_colour, text_scale)
    end

    local function build_nope_static_node(item, text_width, layout, resolve_text_item)
        local text = resolve_text_item(item)
        local text_colour = (G and G.C and G.C.WHITE) or {1, 1, 1, 1}
        local base = (G and G.C and G.C.SECONDARY_SET and G.C.SECONDARY_SET.Tarot) or G.C.PURPLE or G.C.RED
        local stamp_colour = adjust_alpha(base, 0.95)
        local icon_h = layout.preview_h * layout.text_h_ratio
        local icon = create_nope_stamp_icon(text, text_width, icon_h, stamp_colour, text_colour, layout.text_scale)

        if icon then
            return {
                n = G.UIT.O,
                config = {object = icon},
            }
        end

        return {
            n = G.UIT.C,
            config = {
                align = 'cm',
                minw = text_width,
                minh = layout.preview_h * layout.text_h_ratio,
                colour = G.C.CLEAR,
                padding = 0,
            },
            nodes = {
                {
                    n = G.UIT.R,
                    config = {align = 'cm', minw = text_width * 0.84, minh = 0.34, colour = stamp_colour, r = 0},
                    nodes = {
                        {
                            n = G.UIT.T,
                            config = {
                                text = text,
                                scale = layout.text_scale * 1.08,
                                colour = text_colour,
                                shadow = true,
                            },
                        },
                    },
                },
            },
        }
    end

    local function build_plain_text_node(item, text_width, layout, resolve_text_item)
        local text_colour = (G and G.C and G.C['UI'] and G.C['UI'].TEXT_LIGHT) or G.C.WHITE

        return {
            n = G.UIT.C,
            config = {
                align = 'cm',
                minw = text_width,
                minh = layout.preview_h * layout.text_h_ratio,
                colour = G.C.CLEAR,
                padding = 0,
            },
            nodes = {
                {
                    n = G.UIT.T,
                    config = {
                        text = resolve_text_item(item),
                        scale = layout.text_scale,
                        colour = text_colour,
                        shadow = true,
                    },
                },
            },
        }
    end

    local function is_nope_text_item(item, normalize_title_text)
        if not item then
            return false
        end

        if item.text_key == 'k_nope_ex' then
            return true
        end

        local text = normalize_title_text(item.text)
        local nope = normalize_title_text(localize('k_nope_ex'))
        return text and nope and text == nope
    end

    local function build_info_tip_from_rows(desc_nodes, title, compute_mini_popup_minw)
        local title_text = tostring(title or '')
        local minw = compute_mini_popup_minw(title_text)
        local rows = {}

        for i = 1, #(desc_nodes or {}) do
            rows[#rows + 1] = {
                n = G.UIT.R,
                config = {align = 'cm'},
                nodes = desc_nodes[i],
            }
        end

        return {
            n = G.UIT.R,
            config = {align = 'cm', colour = lighten(G.C.GREY, 0.15), r = 0.1},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {align = 'cm', minh = 0.36, padding = 0.03 + MINI_HEADING_SIDE_PADDING},
                    nodes = {
                        {
                            n = G.UIT.T,
                            config = {
                                text = title_text,
                                scale = 0.32,
                                colour = G.C.UI.TEXT_LIGHT,
                            },
                        },
                    },
                },
                {
                    n = G.UIT.R,
                    config = {
                        align = 'cm',
                        minw = minw,
                        minh = 0.4,
                        r = 0.1,
                        padding = 0.05,
                        colour = G.C.WHITE,
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {align = 'cm', padding = 0.03},
                            nodes = rows,
                        },
                    },
                },
            },
        }
    end

    local R = {}

    function R.make_forecast_element(item, layout, resolve_text_item, normalize_title_text)
        if item.kind == 'card' and item.card then
            return {
                width = layout.preview_w,
                node = {
                    n = G.UIT.O,
                    config = {object = item.card},
                },
            }
        end

        if item.kind ~= 'text' then
            return nil
        end

        local text_width = layout.preview_w + layout.frame_padding
        local is_nope = is_nope_text_item(item, normalize_title_text)
        if is_nope then
            text_width = math.max(text_width, 1.08)
        end

        local node = is_nope
            and build_nope_static_node(item, text_width, layout, resolve_text_item)
            or build_plain_text_node(item, text_width, layout, resolve_text_item)

        return {
            width = text_width,
            node = node,
        }
    end

    function R.add_info_box(info_boxes, rows, title, layout, compute_mini_popup_minw)
        local info_box = {
            n = G.UIT.R,
            config = {align = 'cm'},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {
                        align = 'cm',
                        colour = lighten(G.C.JOKER_GREY, 0.5),
                        r = layout.corner_inner,
                        padding = layout.box_padding,
                        emboss = layout.emboss_inner,
                    },
                    nodes = {
                        build_info_tip_from_rows(rows, title, compute_mini_popup_minw),
                    },
                },
            },
        }

        info_boxes[#info_boxes + 1] = info_box
    end

    function R.build_forecast_slot(forecast, layout)
        return {
            n = G.UIT.R,
            config = {align = 'cm', padding = 0},
            nodes = {
                {
                    n = G.UIT.R,
                    config = {
                        align = 'cm',
                        minw = forecast.width,
                        minh = forecast.height,
                        padding = forecast.inner_padding,
                        r = layout.corner_inner,
                        colour = mix_colours(G.C.BLACK, G.C.L_BLACK, DEFAULT_FORECAST_BG_MIX),
                        emboss = layout.emboss_inner,
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {align = 'cm', padding = forecast.cards_padding},
                            nodes = forecast.nodes,
                        },
                    },
                },
            },
        }
    end

    return R
end
