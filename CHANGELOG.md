# Changelog

## 0.2.0

- Added hover predictions for 12 jokers: 8 Ball, Misprint, Madness, Riff-Raff, Hallucination, Vagabond, Superposition, Cartomancer, Sixth Sense, Seance, Certificate, and Perkeo.
- Joker predictions are phase-gated: forecasts show only when the joker's trigger phase is active (e.g. during a blind for scoring jokers, in the shop for shop jokers).
- Added "Timing: Always" config option to show select joker predictions outside their active phase.
- Blueprint and Brainstorm now show the copied joker's prediction when hovered.
- Misprint prediction integrates with JokerDisplay to show the deterministic next mult value.

## 0.1.2

- Fixed predictions not applying vanilla duplicate-prevention rules for multi-card generation (Emperor, High Priestess, Purple Seal).
- Predictions now match vanilla behavior: without Showman, duplicate cards are filtered; with Showman, duplicates are allowed.

## 0.1.1

- Added Purple Seal hand preview — highlight Purple Seal cards to see the next Tarot outcomes.
- Added "Nope!" stamp for Wheel of Fortune when the roll would fail.
- Added option to show Invisible Joker copy before it's ready to trigger.
- Added option to hide all badge labels on popups.
- Improved multi-card preview layout and spacing.
- Improved forecast panel background styling.
- Emperor and High Priestess now always show all generated cards.
- Collection view no longer uses forecast popups.
- Fixed CJK text display in forecast stamps.

## 0.1.0

- Initial release.
- Hover predictions for Wheel of Fortune, Emperor, High Priestess, Judgement, The Soul, Wraith, Invisible Joker, Aura, Sigil, Ouija, Hex, Ectoplasm, Ankh, Familiar, Grim, Incantation, Immolate.
- Per-card config toggles, display settings, and logging options.
