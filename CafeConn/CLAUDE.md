# CafeConnect Staff — Claude Code Project Config

## What this project is
Staff-only café/restaurant operations app. NOT a POS/cash register. A digital replacement for the paper waiter notepad — live dining room map, order coordination, kitchen/bar feed. Guests interact via a separate web app (out of scope here).

## Stack
- Flutter 3.x / Dart 3.x
- State: Provider (CafeState — ChangeNotifier)
- Local DB: Hive + hive_flutter
- Navigation: go_router ^14
- Animation: flutter_animate
- Fonts: Inter (UI) + JetBrains Mono (numbers/timers) — **must be bundled assets, NOT google_fonts**

## File structure (modularized 2026-07-04)
```
lib/
  main.dart                        ← main() + CafeConnectApp + GoRouter only
  core/theme/app_theme.dart        ← AppTheme + T (typography scale)
  core/theme/app_colors.dart       ← AppColors design tokens
  core/theme/app_typography.dart   ← AppTypography helpers
  core/utils.dart                  ← DurationNum / Money extensions
  models/models.dart               ← enums, AppUser, CafeTable, MenuItem, CartLine, CafeOrder, chat models + status/role label helpers
  state/cafe_state.dart            ← CafeState (ChangeNotifier) + MockCafeApi (offline seed)
  data/                            ← ApiConfig, CafeApiClient, DTOs, realtime client
  widgets/app_widgets.dart         ← shared widgets (buttons, cards, AppScaffold, EmptyState, LiveTimer, AttentionBanner, showForwardSheet...)
  screens/shell/main_shell.dart    ← bottom-nav PageView shell
  screens/tables/table_grid.dart   ← WaiterTableGridScreen + TableCard + QuickCheckOverlay
  screens/tables/table_details.dart
  screens/orders/order_composer.dart ← WaiterOrderScreen + precheck sheet
  screens/orders/order_feed.dart   ← kitchen/bar feed + OrderCard
  screens/menu/staff_menu.dart     ← menu showcase + table picker
  screens/menu/dish_details.dart   ← showStaffDishDetails sheet
  screens/chat/chat.dart           ← chat list + chat screen + receipt cards
  screens/panel/staff_panel.dart   ← panel tabs (overview/team/menu/access)
  screens/settings/settings.dart
```

Every class lives in exactly one file; there are no duplicate copies. Put new screens under `lib/screens/<area>/`, shared widgets in `lib/widgets/app_widgets.dart`, domain types in `lib/models/models.dart`.

## Commands
```bash
flutter pub get
flutter analyze
flutter test
flutter run --debug
flutter build apk --release --split-per-abi
```

## Known critical bugs (fix these first)
1. **ROUTER BUG (chat kicks to tables):** `GoRouter` is created inside `Consumer<CafeState>.builder`, so every `notifyListeners()` recreates the router and resets to `initialLocation: '/tables'`. Fix: hoist GoRouter creation outside Consumer, store as a `late final` or use `context.read` only.
2. **FONT BUG (text broken in APK):** `google_fonts` fetches fonts over the network at runtime. No `assets/` folder exists. Inter and JetBrains Mono must be downloaded and bundled as `assets/fonts/` with proper `pubspec.yaml` declarations.
3. **CLEAR TABLE: no confirmation.** `state.closeTable(table)` fires immediately. Must show a `showDialog` with table name and require explicit confirm.
4. **PANEL MENU TAB: renders but content is placeholder.** `MenuManagementScreen` is a stub — needs real content.
5. **SELECT/PRECHECK:** After selecting menu items, shows a raw table-number grid. Missing the full precheck step (edit quantities, notes, see auto-split preview before sending).

## Hard rules — ALWAYS follow
- **NEVER `git commit`, `git push`, create PR, tag, or touch the remote.** Work locally only. When done: output the list of changed files + what to verify. User commits and pushes.
- All working code lives in `lib/main.dart`. Do not scatter fixes into dead duplicate files.
- No raw `Color(0x...)` literals outside AppColors. Use AppColors tokens.
- No `print()` — use `debugPrint()` only.
- No `GoogleFonts.xxx()` calls anywhere — use bundled font families by name.
- Every mutation in CafeState must call `notifyListeners()` after the change.
- `flutter analyze` must be clean (0 errors) after your changes.

## Design tokens (non-negotiable)
```dart
// AppColors — use these names everywhere
bg: #F2EFE8       surface: #FFFFFF    sunken: #EBE6DB
ink: #1E1B16      ink55: 55% ink      ink40: 40% ink
hairline: #E7E2D8 espresso: #221F1A   // primary action — buttons, send
kitchen: #E0823A  bar: #3C7BCF        // blue is NEVER a button fill
ok: #3E9C63       late: #D9564A       gold: #B98A3C
```
Font families: `'Inter'` (UI), `'JetBrainsMono'` (prices, timers, quantities).
Radii: cards 18–20, buttons 14, sheets 24 (top), chips 9–11.

## Skills available
- `/flutter-tests` — write unit/widget tests
- `/prod-checklist` — production readiness checklist
- `/perf-review` — performance/rebuild audit
- `/fix-bugs` — targeted bug fix workflow
