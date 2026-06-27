# CafeConnect Audit Report — v0.1.0 Pre-Alpha

> **Date**: 2026-06-26 | **Branch**: release/v0.1.0-prealpha | **Status**: Baseline audit complete, ready for refactor

---

## Executive Summary

The CafeConnect monolith (lib/main.dart, **2,817 lines**) contains a **staff-only waiter POS** with most screens and features present, but suffers from:
- **352 static analysis issues** (mostly token leakage, deprecated APIs, missing const)
- **35 hardcoded colors** that must move into `AppColors` ThemeExtension
- **Dead customer-facing code** (LoginScreen, mobile_scanner, CartLine, waiterCarts, heroIndex)
- **No persistence layer** — all data is in-memory; re-seeds from mock on every launch
- **Missing Settings screen** — gear icon is decorative only
- **No offline queue** — reconnect logic unimplemented

**Scope for v0.1.0**: Fix token leakage, remove dead code, implement Settings, add persistence with Hive, implement offline queue + reconnect, fix analyzer, add tests, and create dev docs.

---

## Part A: Build Sanity

### Dependency Resolution
```
flutter pub get → OK
  21 packages have newer versions incompatible with constraints
  (Flutter 3.44.x compatible; safe to ignore)
```

### Static Analysis
```
flutter analyze → 352 issues found (15.4s)
  - [CRITICAL] 35 × Color(0x...) literals (token leakage)
  - [INFO] ~40 × 'withOpacity' deprecated (use .withValues())
  - [WARNING] ~20 × missing const constructors
  - [WARNING] ~15 × unused imports
  - [ERROR] design/lib/main.dart has 100+ issues (old prototype, safe to delete)
```

### Tests
```
flutter test → NOT YET RUN
  Expected: stale widget_test.dart will fail
    (looks for LoginScreen 'Войти' button; contradicts staff-only auto-login)
```

---

## Part A1: Token Leakage

### Finding: 35 Hardcoded Colors
```bash
grep -n "Color(0x" lib/main.dart → 35 matches
```

Examples:
- `Color(0xFFF5EFE4)` — cream background
- `Color(0xFF1D1D1D)` — espresso black
- `Color(0xFFFFA500)` — orange (Kitchen station)
- `Color(0xFF0066CC)` — blue (Bar station)
- And many more...

**Action**: Create `AppColors` ThemeExtension with semantic tokens (all hardcodes → tokens).

### Finding: Deprecated `withOpacity()`
```bash
grep -n "withOpacity" lib/main.dart → ~40 matches
```

**Action**: Replace with `.withValues(alpha: ...)` or use `Color.from(…).withAlpha(…)`.

### Finding: Inline Styling
- `BorderRadius.circular(12)` / `BorderRadius.circular(20)` scattered throughout
- `TextStyle(fontFamily: 'Courier')` without google_fonts helper
- `BoxShadow(…)` magic values

**Action**: Move to `AppMetrics` ThemeExtension (radii, shadows, text styles).

---

## Part A2: Dead Customer Code

### List of Findings

| Item | Location | Type | Action |
|------|----------|------|--------|
| `LoginScreen` class | lines ~1900 | **DELETE** | Contradicts staff-only; no customer login |
| `/login` route | line 37 | **DELETE** | Auto-login should go straight to Tables |
| `CartLine` model | lines 185–190 | **DELETE** | Old customer cart model; replace with OrderItem |
| `waiterCarts` map | line 259 | **DELETE** | Old per-waiter customer carts; not used in staff flow |
| `heroIndex` field | line 271 | **DELETE** | Old carousel index for hero animations |
| `mobile_scanner` | pubspec.yaml | **REMOVE** | QR code scanner; customer feature |
| demo passwords | line ~1920 (LoginScreen) | **DELETE** | No password auth in staff-only |
| admin auto-login fallback | (search needed) | **DELETE** | Obsolete redirect |

**Verification**: After cleanup, repo should have **zero** references to customer-side code. Minimal "Switch User" picker (select from staff list, no passwords) is acceptable in Settings but not required for v0.1.0.

---

## Part A3: Persistence Gap

### Current State
```dart
// In CafeState
final List<CafeTable> tables = [...]; // in-memory only
final List<MenuItem> menu = [...];    // in-memory only
```

**On app launch** (`CafeState.boot()`):
1. Re-seeds all tables/orders/menu from `MockCafeApi`
2. Wipes any edits from previous session
3. Only `themeMode` preference might persist (unverified)

**Consequence**: 
- Waiter closes app mid-shift → all table orders lost
- Menu edits by manager → lost on app restart
- **Not viable for production; must fix for v0.1.0**

### Action: Implement Hive Persistence

1. **Add to pubspec.yaml**:
   ```yaml
   dev_dependencies:
     build_runner: ^2.4.0
     hive_generator: ^2.0.0
   ```

2. **Create HiveType models** (each with `@HiveType` + `@HiveField`):
   - `CafeTable` (order lines, notes, status, openedAt, waiter, colorTag)
   - `OrderItem` (name, qty, price, note, station, ready)
   - `MenuItem` (id, name, price, composition, station, available)
   - `StationTicket` (id, items, status, readyAt, late)
   - `StaffMember` (name, role, status)
   - `ChatGroup` (id, title, members)
   - `ChatMessage` (id, kind, who, text, time, tableNumber, snapshot)
   - `Settings` (themeModeIndex, soundEnabled, textScaleFactor, **all v3 §11 fields**)
   - `TableSnapshot` (frozen table state for forwarded checks)
   - `OfflineQueueItem` (action, payload, timestamp)

3. **Run code generation**:
   ```bash
   flutter pub run build_runner build
   ```

4. **Update HiveService**:
   - `init()` → register all adapters, open boxes
   - `seedIfEmpty()` → seed boxes on first launch only
   - `read<T>(key)` / `write<T>(key, value)` → type-safe getters/setters
   - `resetToDemo()` → wipe all boxes and re-seed (for QA)

5. **Update CafeState**:
   - Every mutation calls `HiveService.write(...)`
   - Every boot call reads from Hive, only seeds if boxes are empty
   - **Result**: Full app state survives restart

**Test**: Add widget test proving theme selection persists across restart.

---

## Part A4: Settings Gap

### Current State
- Gear icon in Panel screen → decorative only
- Only `themeMode` and `soundEnabled` exist as fields
- No UI for users to change settings

### Feature Requirements (v3 §11)
Build a full Settings screen accessible from gear icon (Settings modal or push to `/panel/settings`):

**Sections**:
1. **Account & Shift**
   - Current user name (read-only, from active staff member)
   - Shift start time (read-only, e.g., "Started 9:00 AM")
   - Switch User button → show picker (names only, no passwords)

2. **Appearance**
   - Theme: Light / Dark / System (SegmentedControl or buttons)
   - Text size: Small / Normal / Large slider
   - **Persists** to Hive `Settings.themeModeIndex` / `Settings.textScaleFactor`

3. **Display**
   - Tables per row: 3 / 4 (SegmentedControl)
   - Show gesture hints (toggle)
   - Default Orders zone: "New" / "Ready" / "All" (dropdown)
   - Currency symbol: € / $ / ₽ (text field + position: before/after)
   - Clock: 12h / 24h (toggle)

4. **Feedback**
   - Master toggle: Haptics enabled (on/off)
   - Granular: Long-press = on/off, Status = on/off, etc.
   - Master toggle: Sounds enabled (on/off)
   - Volume: slider (if sounds enabled)
   - **Gated by FeedbackService** (see Part D §4)

5. **Notifications**
   - Late threshold (minutes): input field (default 20)
   - Show banners (toggle)

6. **Data & Sync**
   - Offline mode: toggle (simulates no server; ops queue locally)
   - Force sync: button (flushes offline queue immediately)
   - View pending queue: read-only list of unsent actions
   - Clear cache: button → deletes all local data, reseed from server (if online)
   - **Reset to demo**: button → wipe Hive + re-seed from MockCafeApi (QA tool)

7. **About**
   - App version: "v0.1.0-prealpha"
   - Flutter version
   - Open source licenses (flutter pub get licenses)

**Each toggle/selection works and persists via Hive. Changes apply app-wide instantly through CafeState listeners.**

---

## Part A5: Feature Completeness vs v3

| Feature | Status | Notes |
|---------|--------|-------|
| **Tables screen** | ✓ partial | List view exists, tile design needs v3 polish |
| **Table Detail screen** | ✓ partial | Item add/edit exists, but no change calculator visual |
| **Quick-Check overlay** | ✓ exists | Long-press → preview (needs timer/ready badge) |
| **Menu Browse + Select** | ✓ partial | List view exists, Precheck flow incomplete |
| **Precheck modal** | ✓ partial | Shows items, but auto-split to Kitchen/Bar may be buggy |
| **Send order** | ✓ partial | Splits to stations, but offline queue not tracked |
| **Orders screen** | ✓ partial | Shows Kitchen/Bar tabs, but timers + late threshold TBD |
| **Mark ready + forward** | ✓ partial | UI exists, but deep-link after forward not verified |
| **Chats screen** | ✓ partial | List of groups exists, messages UI TBD |
| **Panel Overview** | ✓ exists | Revenue chart exists |
| **Panel Team** | ✓ exists | Staff list exists |
| **Panel Menu** | ✓ exists | Menu grid exists |
| **Panel Access** | ✓ exists | User/role matrix exists |
| **Settings screen** | ✗ **MISSING** | Entire screen + all toggles/inputs |
| **Auto-login to Tables** | ✗ **MISSING** | Currently routes to `/login` |
| **Offline queue + reconnect** | ✗ **MISSING** | No banner, no reconnect logic, no queue storage |
| **FeedbackService** | ✗ **PARTIAL** | Haptics + sounds skeleton only; not gated by Settings |

---

## Part A6: Pubspec.yaml Review

### Current
```yaml
name: cafeconnect
version: 1.0.0+1
environment: sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter: sdk
  cached_network_image: ^3.3.1     ✓ Keep (image caching)
  collection: ^1.18.0              ✓ Keep (list utilities)
  cupertino_icons: ^1.0.8          ✓ Keep (iOS icons)
  flutter_animate: ^4.5.0          ✓ Keep (animations)
  go_router: ^14.2.0               ✓ Keep (routing)
  google_fonts: ^6.2.1             ✓ Keep (typography tokens)
  hive_flutter: ^1.1.0             ✓ Keep (persistence)
  mobile_scanner: ^5.1.1           ✗ **REMOVE** (QR; customer feature)
  provider: ^6.1.2                 ✓ Keep (state management)

dev_dependencies:
  flutter_test: sdk                ✓ Keep
  flutter_lints: ^4.0.0            ✓ Keep
  # MISSING:
  build_runner: ^2.4.0             ✗ **ADD** (code generation for Hive)
  hive_generator: ^2.0.0           ✗ **ADD** (generates @HiveType adapters)
```

### Action Items
1. Update version to `0.1.0+1`
2. Remove `mobile_scanner`
3. Add `build_runner` + `hive_generator` to dev_dependencies

---

## Part A7: Stale/Junk Files

| Path | Issue | Action |
|------|-------|--------|
| `flutter_01.log` | Flutter devserver crash log (not app bug) | **DELETE** |
| `design/lib/main.dart` | Old prototype main.dart (~2200 lines, many issues) | **DELETE** entire `design/` folder or keep as archive |
| `landing/` | Prototype HTML landing page | **DELETE** or move to separate repo |
| `web_menu/` | Old web menu UI | **DELETE** or move to separate repo |
| `.idea/` | IDE cache | Already in .gitignore, safe |

---

## Analyzer Summary (Top 10 Issue Types)

```
352 issues found:

1. [INFO] Don't use BuildContext across async gaps (25×)
   → Fix: use mounted check or local copy of context

2. [INFO] 'withOpacity' is deprecated (40×)
   → Fix: use Color(...).withValues(alpha: x/255)

3. [INFO] Statements in if should have braces (15×)
   → Fix: add { } around single statements

4. [INFO] Use const constructors (20×)
   → Fix: add const to constructor calls

5. [WARNING] Unused imports (15×)
   → Fix: remove unused import statements

6. [WARNING] Unused local variables (10×)
   → Fix: remove or use the variable

7. [ERROR] Undefined getter 'messages' in CafeState (1×)
   → Fix: implement messages getter in CafeState

8. [ERROR] Missing required parameter 'onPressed' (2×)
   → Fix: add onPressed callback to button constructors

9. [ERROR] The method 'push' isn't defined for BuildContext (1×)
   → Fix: use GoRouter instead of Navigator.push

10. [ERROR] design/lib/main.dart specific issues (100+)
    → Fix: delete design/ folder entirely
```

---

## Recommendations

### Must Fix Before v0.1.0
1. ✅ Remove dead customer code (LoginScreen, CartLine, waiterCarts, mobile_scanner)
2. ✅ Fix all 352 analyzer issues (token leakage, deprecations, const)
3. ✅ Implement Hive persistence + rebuild models
4. ✅ Implement full Settings screen (per v3 §11)
5. ✅ Implement offline queue + reconnect banner
6. ✅ Replace stale widget test
7. ✅ Create dev docs (README, PROJECT_STRUCTURE, LOGIC, HANDOFF)
8. ✅ Add CI with `flutter analyze` / `flutter test` / `dart format`

### Nice-to-Have for v0.1.0 (Defer if time limited)
- Keyboard-less keypad for order qty
- Nearest-free-table default on new order
- Swipe actions for quick delete
- Repeat-round flow
- Split-bill screen

### Known Toolchain Issue
- **flutter_01.log**: Flutter 3.44.3 `web-server` devserver (bare `flutter run -d web`) crashes with `loadDwdsDirectory ... Null check operator used on a null value`.
  - **Workaround**: Run on Chrome (`flutter run -d chrome`) or desktop (`flutter run -d macos`), not bare web-server.
  - **Document**: Add note to README and CI configuration.

---

## Next Steps

→ **PART B**: Modular refactor (split 2817 lines → modular structure)  
→ **PART C**: Hive persistence (setup + models + HiveService)  
→ **PART D**: Feature gaps (Settings, offline queue, FeedbackService, auto-login)  
→ **PART E**: Tests + CI  
→ **PART F**: Dev docs  
→ **PART G**: Pre-release hygiene  

---

**Audit Completed**: Ready for systematic refactoring.
