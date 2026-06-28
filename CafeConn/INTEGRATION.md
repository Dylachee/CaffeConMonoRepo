# CafeConnect Staff App — Backend Integration

This app boots **fully local** (Hive demo data) so it always works offline. The
networking layer in `lib/data/` connects it to the CafeConnect Django hub and
keeps the floor map live. The integration is **additive**: the original local
demo path (`MockCafeApi`, `submitOrder`, the simulated realtime timer) is
untouched, so nothing breaks if the backend is unreachable.

## Files

| File | Responsibility |
|------|----------------|
| `lib/data/api_config.dart` | Base URL (via `--dart-define=API_BASE_URL`), REST + WS URLs |
| `lib/data/dtos.dart` | Pure-Dart DTOs for both server shapes + status mappings |
| `lib/data/cafe_api_client.dart` | Token auth + REST (`bootstrap`, `createOrder`, …) |
| `lib/data/realtime_client.dart` | WebSocket feed with auto-reconnect |
| `test/api_dtos_test.dart` | Parsing/contract tests for the seam |

## How it connects

`CafeState.connectBackend(username, password)`:

1. `POST /api/auth/token/` → caches the DRF token.
2. `GET /api/staff/bootstrap/` → replaces `menu`, `tables`, `orders` with live
   data (mapped DTO → domain via `_menuFromDto` / `_tableFromDto` / `_orderFromDto`).
3. Opens `ws://<host>/ws/staff/?token=…` and upserts orders as `order.created` /
   `order.updated` events arrive.

On any failure it sets `backendConnected = false`, stores `backendError`, falls
back to local demo, and never throws to the UI.

### Triggering it

Auto-connect on launch by supplying credentials at build time:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.42:8000 \
  --dart-define=API_USERNAME=staff \
  --dart-define=API_PASSWORD=yourpassword
```

Or call `context.read<CafeState>().connectBackend(...)` from a login screen.

## Status — now wired end-to-end

- **Order write-path:** when `backendConnected`, `submitOrder` routes through
  `_submitOrderRemote` → `POST /api/orders/`; the WebSocket echo is de-duplicated
  by id (`_upsertLocalOrder`). The local split path stays for offline use.
- **Mark-ready / availability / close-table:** push to the API with optimistic
  update + rollback on failure (`_pushOrderStatus`, `_pushAvailability`,
  `_pushTableStatus`).
- **Guest attention:** `CafeTable.attention` + `attention.*` realtime events
  recolor the tile border and show an `_AttentionPill`; acknowledge clears it.
- **Reconnect:** Settings → "Соединение" shows status + server and calls
  `reconnect()` (reuses stored / `--dart-define` credentials).
- **Demo simulator** is disabled while `backendConnected` so real data isn't
  polluted.

Remaining niceties (small, isolated): per-item mark-ready (needs item ids carried
into `CartLine`), and a dedicated login screen (today: `--dart-define` creds or
the Settings reconnect control).
