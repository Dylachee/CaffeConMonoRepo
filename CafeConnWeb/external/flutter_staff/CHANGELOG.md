# Changelog

All notable changes to CafeConnect are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0-alpha] — 2026-06-27

First public alpha. Single-device, local-only, no realtime backend.

### Added

- Live table map with status colors (free / occupied / awaiting payment / ready / late / new order),
  seat count, and waiter name on each tile.
- Tap a table → table detail screen (current order, notes, status picker, change calculator).
- Long-press a table (380 ms) → quick-check overlay ("Reels"-style bill peek) with espresso/white
  action buttons.
- Order intake via iOS-Photos-style multi-select on the menu grid: long-press to enter select mode,
  tap to toggle, inline qty stepper per selected card.
- Precheck bottom sheet before sending: editable qty per item, per-item notes with preset chips
  (Без лука, Без льда, Остро, etc.) plus free text, table picker chips when opened from the Menu
  tab, kitchen/bar auto-split preview, total, single "ОТПРАВИТЬ ЗАКАЗ" confirm button.
- Auto-split: food categories → kitchen feed, drinks/coffee → bar feed.
- Orders screen with tap-only КУХНЯ/БАР segmented control (IndexedStack), live timer with color
  grades (<15м green, 15–20м orange, >20м red), and per-order "Готово" / "Завершить" action.
- Staff chat list and thread with receipt-style cards for kitchen/bar order messages.
- Forwarded table cards in chat (forward a table to a group with a comment).
- Panel: overview metrics, team management (add/edit staff, role picker), menu management
  (toggle availability, add/edit items), role-access matrix.
- Pull-to-refresh on the tables grid.
- Hive persistence — tables, cart contents, notes, orders, and settings survive restart.
- Inter (Regular/Medium/SemiBold/Bold/ExtraBold) and JetBrains Mono bundled as font assets —
  offline-safe, no google_fonts at runtime.
- Settings screen: theme (light/dark/system), text scale, tables-per-row, haptics, sounds,
  offline simulation toggle, demo-data reset.
- Clear-table confirmation dialog before `closeTable` fires.

### Changed

- Centralized typography system: `T.screenTitle` (30 px / 700 weight), `T.sectionTitle`
  (18 px / 700), `T.subtitle` (ink at 50 % opacity — warm, not grey). All screen titles are
  now solid espresso, matching the design prototype.
- Introduced `PrimaryButton` (espresso bg, always-white label, readable muted disabled state),
  `GhostButton` (cream bg, ink label), `DangerButton` (red bg, white label). Eliminates
  dark-text-on-dark-button bugs throughout.
- Orders screen rebuilt around `IndexedStack` instead of `TabBarView` — the nested-swipe
  conflict with the main PageView is gone. КУХНЯ/БАР is tap-only.
- Cupertino page transitions enabled for both Android and iOS (`CupertinoPageTransitionsBuilder`).
- Chat input bar padding uses `MediaQuery.viewInsetsOf` so it rises correctly above the keyboard.
- GoRouter hoisted to `initState` as `late final` — never rebuilt inside Consumer, chat no longer
  resets to `/tables` on `notifyListeners`.

### Fixed

- Sending an order from the Menu tab now works: precheck sheet has a working table picker, and
  "ОТПРАВИТЬ ЗАКАЗ" enables only when `items.isNotEmpty && table != null`.
- Quick-check overlay action button is now espresso bg / white text (was invisible dark-on-dark).
- Screen titles throughout the app are solid ink, not washed-out near-white.
- Typing in a chat thread no longer navigates away to the tables screen.
- `markReady` no longer calls `context.go('/tables')` — stays on the Orders screen after marking.

### Known limitations

- No realtime sync between devices — single-device alpha only.
- No backend, no cash-register integration, no guest web channel (QR).
- iOS-edge-swipe-back for pushed routes (`/table-details`, `/chat`) requires a parent-navigator
  refactor not included in this alpha.
- Edit/delete table lost its entry point when the long-press options menu was removed to match
  the design; a new entry point (e.g., via the table detail header) needs to be added.
