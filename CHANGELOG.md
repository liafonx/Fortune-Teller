# Changelog

## Unreleased

- Refactored core runtime for maintainability:
  - Added root `UI/` modules: `UI/card_popup.lua`, `UI/config_tabs.lua`, `UI/preview_cards.lua`.
  - Merged config bootstrap/defaults into `Core/config_setup.lua`.
  - Merged predictor route files into `Core/predictors/routes.lua`.
  - Moved runtime hooks to `Core/ui_hooks.lua` and removed legacy wrappers/shims.
- Updated forecast panel behavior:
  - Fixed-height baseline from normal joker preview size.
  - Multi-card layout supports equal-gap mode and default-width even-spacing fallback.
  - Forecast area uses shop-style dark joker slot background.
- Updated gameplay/UI behavior:
  - Collection cards now always use vanilla popup.
  - Removed collection-hover skip debug logging from hot path.
  - Emperor/High Priestess show full generated results regardless of current consumable slots.
- Updated repository docs (`README*`, `AGENT.md`, `docs/*`) to reflect current architecture and behavior.

## 0.1.0

- Initial mod setup.
- Added forecast UI architecture split into modules.
- Added deterministic prediction support for current scoped cards.
- Added Balatro mod init scripts/config/docs baseline.
