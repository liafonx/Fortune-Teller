# Fix: `assume_trigger` always active when `timing_always` is on

## Context

Two bugs after the timing_always refactor:
1. **In trigger phase + timing_always on + guards fail** (e.g., no 8s highlighted): prediction not shown. User wants `timing_always` to mean "always show predictions" regardless of guard state.
2. **Invisible Joker** doesn't show prediction before ready even with timing_always on, because it doesn't receive `assume_trigger` from the engine (not in `TRIGGER_PHASE`).

**Root cause**: `assume_trigger` is only set to `true` when *outside* the natural phase. It should be `true` whenever `timing_always` is on, regardless of phase.

---

## Changes (2 files)

### 1. `Core/predictors/engine.lua` — `assume_trigger = timing_always`

**Lines 108-116** — Replace phase-conditional logic:

```lua
-- BEFORE:
local in_natural_phase = check_natural_phase(effective_center_key)
local assume_trigger = false
if not in_natural_phase then
    if FT.config_api.prediction_timing_always() then
        assume_trigger = true
    else
        return nil
    end
end

-- AFTER:
local in_natural_phase = check_natural_phase(effective_center_key)
local assume_trigger = not not FT.config_api.prediction_timing_always()
if not in_natural_phase and not assume_trigger then
    return nil
end
```

Now `assume_trigger = true` whenever timing_always is on, and the phase gate is only enforced when timing_always is off.

### 2. `Core/predictors/shared.lua` — Two predictor fixes

**`predict_8_ball`** (line 489) — Try real highlighted count first, fall back to assumed default:

```lua
-- BEFORE:
function S.predict_8_ball(card, _, assume_trigger)
    local eights
    if assume_trigger then
        eights = 1
    else
        local highlighted = G and G.hand and G.hand.highlighted or {}
        eights = 0
        for _, c in ipairs(highlighted) do ... end
        if eights == 0 then return nil end
    end

-- AFTER:
function S.predict_8_ball(card, _, assume_trigger)
    local highlighted = G and G.hand and G.hand.highlighted or {}
    local eights = 0
    for _, c in ipairs(highlighted) do ... end
    if eights == 0 then
        if not assume_trigger then return nil end
        eights = 1
    end
```

This preserves accurate predictions when 8s ARE highlighted (uses real count), and falls back to eights=1 only when guards fail + timing_always is on.

**`predict_invisible_joker`** (line 398) — Accept `assume_trigger`, remove internal timing_always check:

```lua
-- BEFORE:
function S.predict_invisible_joker(card)
    ...
    local show_pretrigger = FT.config_api and FT.config_api.prediction_timing_always
        and FT.config_api.prediction_timing_always()
    if not show_pretrigger and card.ability.invis_rounds < card.ability.extra then

-- AFTER:
function S.predict_invisible_joker(card, _, assume_trigger)
    ...
    if not assume_trigger and card.ability.invis_rounds < card.ability.extra then
```

With the engine fix, `assume_trigger = true` when timing_always is on for ALL jokers (including j_invisible, even though it's not in TRIGGER_PHASE).

### Other predictors (no changes needed)

vagabond, superposition, sixth_sense, seance, madness, hallucination — current `if not assume_trigger then <guards> end` pattern works correctly. Their guards are binary (pass/fail) and don't produce values used in the prediction, so always skipping when timing_always is on is fine.

---

## Verification

1. **In blind, no 8s highlighted, timing_always on** → hover j_8_ball → shows Tarot prediction (assuming 1 eight)
2. **In blind, 3 eights highlighted, timing_always on** → hover j_8_ball → shows prediction for 3 eights (real count)
3. **Outside blind, timing_always on** → hover j_8_ball → shows prediction (assuming 1 eight)
4. **Timing_always off** → all guards enforced normally, phase gates enforced normally
5. **Invisible Joker before ready, timing_always on** → shows prediction
6. **Invisible Joker before ready, timing_always off** → no prediction
