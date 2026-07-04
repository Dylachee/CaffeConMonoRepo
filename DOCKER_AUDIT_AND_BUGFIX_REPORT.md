# CafeConnect — Docker Audit & Bottom-Nav Bug Fix

**Date:** 2026-07-01
**Scope:** Full project review, Docker audit, local-run verification, bottom-navigation bug fix.
**Note on git:** per `CafeConnect_Development_Rules.md` §0, no git commands were run. Everything below is a local file change — you review and commit.

---

## 1. Project Overview

Monorepo for **CafeConnect**, a real-time floor-management tool for restaurants/cafés (not a POS/till) — waiters, kitchen and bar coordinate through one shared live view instead of a paper notepad.

| Component | Path | Stack |
|---|---|---|
| Staff mobile app (canonical) | `CafeConn/` | Flutter 3.3+/Dart 3, Provider, go_router, Hive, `main.dart` ≈6.2k lines |
| Backend hub | `CafeConnWeb/` | Django 5 + DRF + Channels, PostgreSQL, Redis, served via Daphne (ASGI) |
| Design reference | `CafeConnectDesighn/` | Static HTML exports, screenshots, prompts (not code) |
| **Stale duplicates — ignore** | `CafeConnWeb/external/flutter_staff/`, `CafeConn/claude/.../cafeconnect-flutter/`, `CafeConn/desidesi/` | Old copies, not wired into anything |

Architecture: Flutter app and a server-rendered guest/management web both talk to one Django hub over REST + WebSocket (Channels/Redis for fan-out, Postgres for state). This is already documented in your own `README.md` and `SYSTEM_DESIGN.md` — both are accurate and current, so local-run steps below mostly restate them.

---

## 2. Docker Audit Results

**Environment note:** the Docker CLI isn't available in my execution sandbox, so I couldn't literally run `docker compose up`. As a substitute I installed `CafeConnWeb/requirements.txt` into a clean venv and ran Django's own checks against your actual settings:

- `python manage.py check` → **0 issues**
- `python manage.py makemigrations --check --dry-run` → **no missing migrations**

This confirms the backend's settings/apps/URLs/models are internally consistent and will boot once Postgres/Redis are reachable — it does not confirm the container build itself, which you'll need to run yourself (Section 3).

### Issues found and fixed

| # | Issue | Fix applied |
|---|---|---|
| 1 | **No root `.gitignore`.** The README has you `cp .env.example .env` at the repo root, but nothing excluded `.env` from git — the real `DJANGO_SECRET_KEY`/DB password/your LAN IP had no protection from an accidental `git add .`. (Confirmed no `.env` is currently tracked — you're not exposed today, but you were unprotected going forward.) | Added `.gitignore` at repo root (`.env`, OS cruft, `.idea/`). |
| 2 | **`CafeConnWeb/.dockerignore` too narrow.** `COPY . /app` in the Dockerfile was pulling ~35MB of irrelevant content into the image/build context: the stale `external/flutter_staff` duplicate (27MB), `refs/` (3MB), `uploads/` (4.2MB — runtime data, shouldn't be baked into an image anyway), `shots/`, `.thumbnail`, and the root-level `*.dc.html`/`support.js` design exports. None of these are read by the Django app (nothing under `static/`/`templates/` references them). | Extended `.dockerignore` to exclude them. |
| 3 | **`web` service had no healthcheck.** `db` and `redis` do; `web` didn't, despite a working `/api/health/` endpoint, so `docker compose ps` couldn't report backend readiness. | Added a healthcheck using the image's own Python interpreter (`urllib.request`) — deliberately not `curl`/`wget`, which aren't installed in `python:3.12-slim` and installing them would undo the point of the slim base. |
| 4 | **Two docker-compose files that can drift.** `CafeConnWeb/docker-compose.yml` + `CafeConnWeb/.env.example` predate the root orchestration (added in your latest commit) and differ from it in real ways: different `DJANGO_ALLOWED_HOSTS` default (`*` vs. assembled localhost+LAN-IP), and it bind-mounts source (`.:/app`, live-reload) where the root file bakes the image. Running the wrong one, or both at once, means port collisions and confusing behavior differences. | **Not removed.** Your README already calls the root file canonical, but I can't confirm the `CafeConnWeb/` one is dead rather than kept intentionally for standalone backend dev, and deleting files outside "don't remove functionality without a clear reason" isn't my call to make silently. **Recommendation: delete both, or add a header comment marking them dev-only/deprecated.** |

### Already solid (no change needed)

Worth naming since an audit that only lists problems is misleading: Dockerfile already runs as a non-root user, uses `psycopg[binary]` (no `libpq-dev`/`gcc` needed, keeping the image genuinely minimal), and layers deps before app code for good cache reuse. `settings.py` already refuses to boot in production with the placeholder `SECRET_KEY`. `db`/`redis` healthchecks and `depends_on: condition: service_healthy` were already correct.

---

## 3. Local Run Instructions

Prerequisites: Docker Desktop (Compose v2), Flutter 3.3+/Dart 3 if you'll also run the mobile app.

```bash
cp .env.example .env
# edit .env — set DJANGO_LAN_HOST to your Wi-Fi IPv4 if you'll test on a phone
docker compose up --build
```

In a second terminal:

```bash
docker compose exec web python manage.py seed_demo
docker compose exec web python manage.py createsuperuser
```

Verify it's up:

| Check | URL |
|---|---|
| Health | http://localhost:8000/api/health/ |
| Guest menu | http://localhost:8000/menu/ |
| Management dashboard | http://localhost:8000/dashboard/ |
| Django admin | http://localhost:8000/system-admin/ |

Run the Flutter app against it (separate process, not containerized):

```bash
cd CafeConn
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000   # desktop / iOS simulator
# physical Android device on the same Wi-Fi: use your LAN IP instead of localhost
# Android emulator: use http://10.0.2.2:8000
```

I could not execute `docker compose up` myself to confirm the ports/URLs above respond — please run it and confirm; if `web` fails to become healthy, `docker compose logs web` is the first thing to check.

---

## 4. Bug Fix Details — bottom nav disappearing

**Root cause.** `_MainShellScreenState` (`CafeConn/lib/main.dart`, the 5-tab shell: Столы/Заказы/Меню/Чаты/Панель) renders its tabs in a `PageView` and its real bottom nav bar (`_ShellBottomNav`) via `Scaffold.bottomNavigationBar`, gated on `CafeState.shellHideNav`. `StaffMenuScreen` flips that flag off when you long-press a dish to enter multi-select mode, swapping the nav for an in-tab selection action bar.

The bug: the `PageView`'s swipe gesture was **never disabled** while `shellHideNav` was true. Swipe to a different tab mid-selection (an easy, plausible gesture — nothing blocks it) and you land on a tab with **no bottom nav at all** — the selection bar only exists inside `StaffMenuScreen`, so it doesn't follow you. The only way back was swiping to the exact tab that hid it and tapping the header's X. From the outside this looks exactly like "the bottom menu sometimes disappears / behaves unexpectedly while scrolling."

**Fix.** One `physics` parameter on the shell's `PageView` (`CafeConn/lib/main.dart`, ~line 2342): swipe is locked (`NeverScrollableScrollPhysics`) while `shellHideNav` is true, normal (`PageScrollPhysics`) otherwise. The active tab and the nav's visibility can no longer desync. Nothing else about selection mode, the selection bar, or normal tab-switching changed.

```dart
body: PageView(
  controller: _pageController,
  physics: state.shellHideNav
      ? const NeverScrollableScrollPhysics()
      : const PageScrollPhysics(),
  onPageChanged: (i) => setState(() => _currentIndex = i),
  children: const [ ... ],
),
```

**Testing.** `CafeConn/test/` currently covers DTO parsing only (`api_dtos_test.dart`); `widget_test.dart` is still the unmodified default smoke test. There's no widget-test harness set up yet for `main.dart` (it'd need Provider/Hive mocking to pump a real widget tree), so per your rule §8 ("test that reproduces the bug, then fix") I'm flagging this gap rather than quietly skipping it — building that harness is a separate task, not something to bolt on inside this fix.

**Verify by hand:** open the app → Меню tab → long-press a dish (enters selection, nav disappears as designed) → swipe left/right. Before the fix: you land on another tab with no nav. After: the swipe is blocked until you cancel (X) or confirm the selection — the nav is always where it should be.

---

## Files changed (nothing committed — that's on you per project rules)

| File | Change |
|---|---|
| `CafeConn/lib/main.dart` | Bug fix: lock `PageView` swipe while `shellHideNav` is true (~line 2342). |
| `docker-compose.yml` | Added `healthcheck` to the `web` service. |
| `CafeConnWeb/.dockerignore` | Excluded stale/duplicate/design-reference directories from the build context. |
| `.gitignore` (new) | Root-level; protects the future `.env` from accidental commit. |

**Not changed, flagged for your decision:** `CafeConnWeb/docker-compose.yml` and `CafeConnWeb/.env.example` (duplicate of root config, see audit item 4).

**To check by hand:** run `docker compose up --build` and confirm all four health-check URLs; run `flutter analyze` and the selection-mode swipe steps above (no Flutter/Docker toolchain in my sandbox to run either).
