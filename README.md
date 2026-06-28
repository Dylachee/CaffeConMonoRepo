# CafeConnect — Monorepo

> **A live floor map in every waiter's pocket.** Not a cash register, not a POS —
> a coordination tool where waiters, kitchen, bar and management work in one
> shared, real-time space. CafeConnect replaces the paper notepad, not the till.

This repository is the single home for all three "doors" into one backend, exactly
as described in the project Vision (`CafeConnect_Видение_проекта.pdf`):

| Door | Who | Where it lives | Status |
|------|-----|----------------|--------|
| **Mobile app** | Waiters, kitchen, bar | `CafeConn/` (Flutter) | Core product — built first |
| **Management web** | Owner, manager, accountant | `CafeConnWeb/` (Django dashboard) | Server-rendered |
| **Guest web (QR, no login)** | Guests at the table | `CafeConnWeb/` (Django guest pages) | Server-rendered |
| **The hub** | REST + WebSocket for all of the above | `CafeConnWeb/` (Django + Channels) | PostgreSQL + Redis |

```
MonoRepForCafeConn/
├─ docker-compose.yml        ← root orchestration (Postgres + Redis + Django hub)
├─ .env.example              ← copy to .env, set your Wi-Fi LAN IP
├─ CafeConn/                 ← Flutter staff app (the mobile door)
├─ CafeConnWeb/              ← Django hub: API, WebSocket, guest web, dashboard
├─ CafeConnectDesighn/       ← UI/UX reference (HTML design exports, shots, prompts)
└─ CafeConnect_Development_Rules.md   ← engineering rules — read before contributing
```

> ⚠️ **Duplicate trees to ignore.** Two stale copies of the Flutter app exist:
> `CafeConnWeb/external/flutter_staff/` and `CafeConn/claude/.../cafeconnect-flutter/`.
> The **only** canonical Flutter app is `CafeConn/`. The duplicates are not wired
> into anything and should be removed once you confirm nothing references them.

---

## 1. Prerequisites

- **Docker Desktop** (Compose v2) — runs the backend, DB and Redis.
- **Flutter 3.3+ / Dart 3** — only needed to build/run the mobile app.
- The host computer and the Android phone must be on the **same Wi-Fi network**.

---

## 2. Start the backend hub (one command)

```bash
cp .env.example .env
# Edit .env and set DJANGO_LAN_HOST to your computer's Wi-Fi IPv4 address.
docker compose up --build
```

Then, in a second terminal, load demo data and create a login:

```bash
docker compose exec web python manage.py seed_demo
docker compose exec web python manage.py createsuperuser
```

Verify it is up:

- Health: <http://localhost:8000/api/health/>
- Guest menu: <http://localhost:8000/menu/>
- Management dashboard: <http://localhost:8000/dashboard/>
- Django admin: <http://localhost:8000/system-admin/>
- REST API root: <http://localhost:8000/api/>

---

## 3. Make the hub reachable from a physical Android device

The phone cannot reach `localhost` — it must reach the **host computer's LAN IP**.

1. **Find your IP** and put it in `.env` as `DJANGO_LAN_HOST`:
   - Windows: `ipconfig` → *IPv4 Address* of the Wi-Fi adapter (e.g. `192.168.1.42`)
   - macOS: `ipconfig getifaddr en0`
   - Linux: `hostname -I | awk '{print $1}'`
2. Restart the stack so the new `ALLOWED_HOSTS`/CSRF origins apply:
   ```bash
   docker compose up -d --build
   ```
3. On the **phone's browser**, open `http://<LAN-IP>:8000/api/health/`.
   You should see `{"status": "ok", ...}`. If not, allow port 8000 through the
   computer's firewall (on Windows, "Allow an app through firewall" for Docker).

---

## 4. Run the Flutter staff app against the hub

The app reads its backend URL from a compile-time define, so no code edit is
needed to switch between emulator and a real phone.

```bash
cd CafeConn
flutter pub get

# Physical Android device over Wi-Fi (use your LAN IP):
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000

# Android emulator (host loopback alias):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# iOS simulator / desktop:
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

Cleartext HTTP on the dev LAN is enabled for debug builds via
`android/app/src/main/res/xml/network_security_config.xml`. **Release builds keep
cleartext disabled** — production must use HTTPS behind a reverse proxy.

Log in inside the app with the staff credentials you created. The app calls
`POST /api/auth/token/`, hydrates the floor map from `GET /api/staff/bootstrap/`,
and subscribes to live order/attention events over
`ws://<LAN-IP>:8000/ws/staff/?token=<token>`.

---

## 5. How the pieces talk (contract summary)

| Concern | Endpoint | Notes |
|---------|----------|-------|
| Auth | `POST /api/auth/token/` | `{username, password}` → `{token}` |
| Hydrate app | `GET /api/staff/bootstrap/` | Flutter-shaped tables/menu/orders/prefs |
| Create order | `POST /api/orders/` | `{table_id, items:[{menu_item_id, quantity, notes}]}` — auto-splits kitchen/bar by item station |
| Mark item ready | `POST /api/order-items/{id}/mark-ready/` | broadcasts `order.updated` |
| Guest signal | `POST /api/attention-signals/` | public (QR guest) → broadcasts `attention.created` |
| Realtime | `ws://host:8000/ws/staff/?token=` | `order.created`, `order.updated`, `attention.*` |

Full contract: `CafeConnWeb/docs/API_CONTRACT.md`.

---

## 6. Engineering rules

All contributors (human and AI) follow `CafeConnect_Development_Rules.md`. The
non-negotiables: work locally and **never run git** (the human commits), keep data
immutable (`copyWith`/`final`), prefer many small files, handle every error
visibly, and validate input at the boundary.

---

## 7. Troubleshooting

- **Phone shows "connection refused"** → wrong/missing `DJANGO_LAN_HOST`, firewall
  blocking 8000, or phone on a different Wi-Fi/guest network.
- **`DisallowedHost` in logs** → add the LAN IP to `DJANGO_LAN_HOST` and rebuild.
- **WebSocket won't connect** → confirm Redis is healthy (`docker compose ps`) and
  the token is valid; the socket auths via `?token=`.
- **App shows demo data only** → it fell back to the local Hive demo because login
  or bootstrap failed; check the backend URL and that you seeded + created a user.
