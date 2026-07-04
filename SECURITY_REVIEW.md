# CafeConnect — Security & Pre-Deploy Review

*2026-07-04. Scope: Django hub (`CafeConnWeb`), guest web, staff API/WebSocket, Docker setup, Flutter client. Issues marked ✅ were fixed in this pass and verified against the running stack; ⚠️ items need your action before/at deploy.*

---

## Fixed in this pass (verified live)

| # | Issue | Fix | Verified |
|---|---|---|---|
| 1 | **Path traversal in `/staff/<path>`** — `<path:path>` accepts `..` and absolute paths; `/staff/..%2fbackend_core%2fsettings.py` could read files outside the PWA build dir | `staff_app` now resolves the path and requires it to stay inside `static/staff/`; a missing build returns 404 instead of a 500 `FileNotFoundError` | traversal → 404; `/staff/` without build → 404 |
| 2 | **Login brute force** — `/api/auth/token/` had no throttle; passwords could be guessed at wire speed | `ThrottledObtainAuthToken`, 10/min per IP | config in place (same mechanism as #3, which was observed live) |
| 3 | **Guest signal flood** — anonymous `attention-signals` API create + the guest "call waiter" form could ping every staff device without limit | API: scoped throttle 6/min per IP; guest form: cache-based 6/min per IP returning 429/message | 7th anon API create → 429 |
| 4 | **Guest order 500s** — non-numeric `table` id, non-numeric item ids, or a non-numeric quantity crashed with `ValueError`; quantity had no upper bound (a "999999999 espressos" order would flood the kitchen feed) | ids sanitized, friendly error for unknown table, quantity clamped to 1–50, guest_name/notes length-capped | garbage table id → 302 + message; qty 99999999999999 → stored as 50 |
| 5 | **Floor state world-readable** — `/api/tables/` allowed anonymous reads (statuses, waiter names) though the guest page never uses it | `TableViewSet` now `IsAuthenticated` | anon → 401 |
| 6 | **Bootstrap N+1** — every staff app load ran 1 query per table (30 tables = 30 extra queries) for `currentOrderId` | active orders prefetched once via `to_attr` | bootstrap 200 for all four role accounts |

Also verified working as intended (no change needed):
- CSRF: guest forms POST with `csrfmiddlewaretoken`; cookies are `HttpOnly`; `X_FRAME_OPTIONS=DENY`.
- `/api/orders/`, `/api/order-items/` require auth; `/api/employees/` requires admin (`waiter/cook/bartender` → 403, `manager` → 200).
- `/dashboard/` requires a staff login (anon → redirect to login).
- WebSocket `StaffConsumer` rejects unauthenticated connections (code 4401).
- Prod settings block exists: HSTS, secure cookies, SSL redirect when `DEBUG=false`; startup refuses a dev SECRET_KEY in prod.
- Menu API stays read-open intentionally (public menu data only).

---

## ⚠️ Must do at deploy (config, not code)

1. **Set real env values in `../.env`** (compose defaults are dev-grade):
   ```
   DJANGO_DEBUG=false
   DJANGO_SECRET_KEY=<python -c "import secrets; print(secrets.token_urlsafe(50))">
   DJANGO_ALLOWED_HOSTS=<your-domain-or-LAN-IP>,localhost
   DJANGO_CSRF_TRUSTED_ORIGINS=http(s)://<your-domain-or-LAN-IP>:8000
   POSTGRES_PASSWORD=<strong password>
   ```
   With `DEBUG=false` and no SSL in front, also set `DJANGO_SECURE_SSL_REDIRECT=false` or the LAN HTTP setup will redirect to https and break.
2. **Change every seeded password** (all admin accounts currently share `cafeconnect`; role accounts have the defaults printed in `seed_bar.py`):
   `docker compose exec web python manage.py changepassword tony` (etc.)
3. **Rotate DRF tokens after changing passwords** — tokens never expire and the seeder prints them to stdout (they are in your shell history/logs):
   `docker compose exec web python manage.py shell -c "from rest_framework.authtoken.models import Token; Token.objects.all().delete()"` — the app re-issues tokens at next login.
4. **Don't publish Postgres/Redis to the network** unless you need them: compose maps `5432` and `6379` to the host. On an untrusted network, delete those `ports:` entries (containers reach them internally).
5. **Deploy the staff PWA build** to `CafeConnWeb/static/staff/` (RUNBOOK.md §rebuild) — it is gitignored and currently absent, so `/staff/` is 404.

## Known accepted risks (documented, not fixed)

- **WS token in query string** (`/ws/staff/?token=…`) — ends up in server logs. Acceptable on a trusted LAN; move to a subprotocol header if the hub ever goes on the public internet.
- **DRF tokens never expire** — a stolen device stays authenticated until its token row is deleted. Consider knox/JWT later.
- **Anyone can cancel a guest signal** by guessing its sequential id via the guest cancel endpoint (rate-limited, low impact: worst case a call-waiter badge disappears).
- **Whole-staff broadcast group** — every staff device receives every event; there is no per-role channel. Fine at one-venue scale.
- **LocMem cache for throttles** resets on restart and is per-process — correct for the current single-daphne deployment; switch throttle cache to Redis if you ever scale out.

## Load-survival notes ("не умереть под людьми")

- Bootstrap now does a constant number of queries (~6) regardless of table count.
- Station feed and bootstrap cap payloads (orders limited to 100 / active only).
- daphne is a single asyncio process; DB work runs in a thread pool. For one venue with ~10 staff devices + guest traffic this is comfortably enough. If it ever isn't: run 2+ daphne replicas behind nginx — Channels is already Redis-backed, only the throttle cache needs moving to Redis.
