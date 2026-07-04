# CafeConnect — Database Analysis & Improvement Plan

*Generated 2026-07-04. Covers every data store in the monorepo: PostgreSQL (Django hub), Redis (realtime), and Hive (Flutter local cache).*

---

## 1. What databases the project actually has

| Store | Where | Purpose | State |
|---|---|---|---|
| **PostgreSQL 16** | `CafeConnWeb` Docker service `db` | Source of truth: menu, tables, employees, orders, guest signals, staff preferences, DRF auth tokens | Healthy schema, 5 migrations, seeded by `seed_bar` |
| **Redis 7** | Docker service `redis` | Django Channels layer only (WebSocket fan-out to staff devices). No persistent data. | Fine as-is |
| **Hive (local)** | Flutter app, box `cafeconnect` | Offline cache: menu, tables, per-table checks, chat history, settings, API token | Works, but is a *second* source of truth (see §5) |

The Django schema (`apps/core/models.py`) has 6 domain tables: `cafe_menu_items`, `cafe_tables`, `cafe_employees`, `cafe_orders`, `cafe_order_items`, `cafe_attention_signals`, plus `cafe_staff_preferences`.

---

## 2. What is already good (keep it)

- **Price locking.** `OrderItem.unit_price` copies the menu price at order time, and `OrderItem.station` copies the routing. A later price/station change never rewrites an open check. The Flutter side mirrors this with `CartLine.lockedPrice`. This is the correct pattern.
- **`DecimalField` for money** with `max_digits=10, decimal_places=2`. Correct choice.
- **`on_delete=PROTECT`** for `Order.table` and `OrderItem.menu_item` — order history can't be silently destroyed by deleting a table or a dish.
- **Single place for state transitions** (`apps/core/services.py`) so the API, guest web and dashboard can't drift on the 3-status table model.
- **`Table.number` is `unique=True`** and QR codes address tables by number (`/menu/n/<number>/`), which survives DB reseeds. Good call.
- **Sane indexes already present:** `MenuItem.category`, `MenuItem.station`, `Employee.role`, `Order.status/source/station_scope/created_at`, `OrderItem.station`, `AttentionSignal.signal_type/created_at`.
- Timestamps (`created_at`/`updated_at`) on every table, `USE_TZ = True`.

---

## 3. Schema issues, ordered by importance

### 3.1 `Order.Status` has 9 states, but only ~5 are real *(highest value fix)*
```
NEW, PENDING, COOKING, PREPARING, READY, DELIVERED, COMPLETED, PAID, CANCELLED
```
`NEW`/`PENDING` are synonyms, `COOKING`/`PREPARING` are synonyms, and `DELIVERED`/`COMPLETED`/`PAID` all map to the Flutter status "completed" (`flutter_order_status()` in `apps/api/views.py`). Nine states means every filter has to remember every synonym — the admin dashboard already counts only `PENDING` and misses `NEW` orders, and every `exclude(status__in=[PAID, CANCELLED])` must never forget a synonym.

**Recommendation:** collapse to `NEW → COOKING → READY → COMPLETED → PAID`, plus `CANCELLED` (a data migration mapping the synonyms is ~15 lines). If you don't want a migration before the deploy, at minimum add a comment block declaring the canonical subset and make the dashboard count `NEW + PENDING`.

### 3.2 No database-level integrity constraints
Nothing stops bad rows today:
- `OrderItem.quantity = 0` (PositiveSmallIntegerField allows 0),
- `unit_price` negative? No — Decimal allows negative; nothing forbids it,
- `Table.guest_count > capacity`,
- `StaffPreference.volume = 999`.

**Recommendation** (one small migration):
```python
class Meta:
    constraints = [
        models.CheckConstraint(check=Q(quantity__gte=1), name="orderitem_qty_gte_1"),
        models.CheckConstraint(check=Q(unit_price__gte=0), name="orderitem_price_gte_0"),
    ]
```
and the same idea for `volume` (0–100). The guest order form is the one место where users control quantity, so this is a real, not theoretical, risk (see SECURITY_REVIEW).

### 3.3 Table attention state is stored twice
`Table.attention / attention_reason / attention_acknowledged` duplicate what the newest `AttentionSignal` row already says. `services.py` keeps them in sync today, but any future write path that forgets the service function silently desynchronizes them (the bootstrap endpoint already has to stitch `unacked_signals` back onto tables to find the signal id).

**Recommendation:** keep the denormalization (it makes table queries cheap) but add a `current_signal = FK(AttentionSignal, null=True)` instead of the three copied fields — one pointer can't half-drift. Not urgent; document the invariant if you skip it.

### 3.4 Missing composite index for the hot query
Every bootstrap and station feed runs some form of `Order WHERE status NOT IN (paid, cancelled) ORDER BY created_at`. With single-column indexes Postgres will manage at bar scale (hundreds of rows/day), but the right index is:
```python
indexes = [models.Index(fields=["status", "-created_at"], name="order_status_created_idx")]
```
Also `AttentionSignal(table, ack)` for the unacked-signals prefetch. Cheap, do it with the constraints migration.

### 3.5 N+1 in `serialize_for_flutter_table`
`table.orders.exclude(...).first()` runs one query per table — 30 tables → 30 extra queries on every staff bootstrap. Fix by prefetching active orders with a `Prefetch(..., to_attr="active_orders")` the same way `unacked_signals` already does. This is the single biggest DB-load reduction available before people start using the app.

### 3.6 `Employee.Role` vs Flutter roles vocabulary mismatch
Django: `waiter, kitchen, bar, manager, accountant, admin`. Flutter `UserRole`: `waiter, cook, bartender, manager, admin`. The API never sends the role to the app today, so nothing breaks — but the moment role-based UI gating is added, `kitchen ≠ cook` and `bar ≠ bartender` will bite. Pick one vocabulary now (suggest Django's, since it's persisted) and map in one place.

### 3.7 Seeded credentials in the database
`seed_bar` creates four superuser-equivalent accounts (`tony`, `ibi`, `alina`, `uluk`) all with password **`cafeconnect`** and prints their API tokens to stdout. Fine for the demo; before real users, every account needs a real password (`manage.py changepassword`) and DRF tokens should be rotated (delete rows in `authtoken_token`, they regenerate at next login). Also note: **DRF tokens never expire** — a leaked token works forever until manually deleted.

### 3.8 Small things
- `Table.status` has no index while `TableViewSet.filterset_fields = ["status"]` — irrelevant at 30 rows, add it if the venue count ever grows.
- `MenuItem.tags`/`allergens` as JSONField is fine on Postgres; don't move to M2M unless you need to query by allergen.
- `Order.total` is a Python property that iterates `items.all()` — fine where items are prefetched (bootstrap does), but calling it in a loop without prefetch would N+1. The admin dashboard correctly aggregates in SQL instead.
- `CONN_MAX_AGE=60` + daphne is fine at this scale.

---

## 4. Redis
Used only as the Channels layer — no persistence configured, and none needed (losing Redis loses in-flight WS fan-out, clients recover via bootstrap on reconnect). No action. If Redis is down the code paths degrade gracefully (`get_channel_layer() is None` guards), but note **staff devices then silently stop receiving live updates** — worth a health indicator later.

## 5. Hive (Flutter local store)
- Persists: `menu`, `tables`, `check_<tableId>`, `chatMessages` (capped at 500), `pendingQueue`, settings, and `apiToken`.
- Legacy-format migration for old 6-value table status exists (`CafeTable._statusFromRaw`) — good.
- **Main risk:** when backend-connected, Hive still *rehydrates old tables/checks on boot before bootstrap answers*, so a device that was offline can briefly show stale checks. Acceptable, but the chat is Hive-only (messages are never sent to the server) — staff on different devices see **different chat histories**. That's a product decision to make explicit, not a bug fix.
- `apiToken` in Hive means the token sits in browser IndexedDB for the PWA — standard practice, but combined with never-expiring DRF tokens (§3.7), a stolen device stays logged in forever. Rotation policy recommended.

---

## 6. Recommended action list (in order)

1. **Before deploy:** change seeded passwords + rotate tokens (§3.7); fix the bootstrap N+1 (§3.5). Add role accounts for manager/cook/bartender/waiter (done — see `seed_bar`).
2. **This week:** one migration with CheckConstraints (§3.2) + composite indexes (§3.4); collapse `Order.Status` synonyms (§3.1).
3. **Later:** `current_signal` FK cleanup (§3.3), role vocabulary unification (§3.6), token expiry (e.g. `rest_framework-simplejwt` or knox).
