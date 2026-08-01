# CafeConnect — Sissi Bistro Bar Runbook

Use this document every time: first launch, morning startup, after a code change, after a reboot.

---

## One-time setup (laptop, first time only)

```powershell
# 1. Copy the env template and fill in your Wi-Fi IP
Copy-Item ..\\.env.example ..\\.env

# 2. Open ../.env in Notepad and set:
#    DJANGO_LAN_HOST=192.168.179.75     ← run ipconfig to confirm your current IP
#    DJANGO_SECRET_KEY=<any long random string>
#    Leave everything else as-is for local use.
notepad ..\\.env
```

macOS (zsh/bash):

```bash
cp ../.env.example ../.env
# Wi-Fi IP: ipconfig getifaddr en0
open -e ../.env
```

> **Wi-Fi IP warning:** if the laptop reconnects to Wi-Fi and gets a new IP, you must
> re-check with `ipconfig`, update `.env`, rebuild the Flutter web bundle (step 5 below),
> and reprint QR codes. A stale IP baked into a Flutter build or a printed QR is a
> silent failure — the app opens but gets no data.

---

## Every launch — full procedure from cold start

Run all commands from `MonoRepForCafeConn\CafeConnWeb\`:

```powershell
# 1. Start the stack (safe to run whether already up or not)
docker compose up -d

# 2. Confirm all three services are healthy (wait ~20s after first boot)
docker compose ps
# Expected output: db Up (healthy) | web Up (healthy)

# 3. Apply any pending migrations (no-op if none)
docker compose exec web python manage.py migrate

# 4. Seed / re-seed real bar data
#    Safe: uses update_or_create — does NOT wipe existing orders or duplicate rows.
#    Run this every launch to ensure 31 tables and 56 items are current.
docker compose exec web python manage.py seed_bar
```

The seed command prints a token for each staff account — copy them if you need to
reconfigure a phone. Credentials:

| Username | Password     | Role  |
|----------|-------------|-------|
| tony     | cafeconnect | Admin |
| ibi      | cafeconnect | Admin |
| alina    | cafeconnect | Admin |
| uluk     | cafeconnect | Admin |

**Change the password after the first login** via `/system-admin/` → Users.

---

## After a Python / Django file change

Any `.py` file under `CafeConnWeb/` — Daphne does not hot-reload:

```powershell
docker compose restart web
```

---

## After a static file change (CSS / JS / templates)

WhiteNoise re-runs `collectstatic` on container startup, so a restart is enough:

```powershell
docker compose restart web
```

---

## After rebuilding the Flutter staff web bundle

```powershell
# From MonoRepForCafeConn\CafeConn\
flutter build web --release --base-href /staff/

# Copy build output into Django's static directory
Copy-Item -Recurse -Force .\build\web\* ..\CafeConnWeb\static\staff\

# REQUIRED: restore the source-map placeholder. Flutter release builds do NOT
# emit flutter.js.map, but flutter.js references it — without this file
# collectstatic fails with MissingFileError and the web container will not start.
$map = "..\CafeConnWeb\static\staff\flutter.js.map"
if (-not (Test-Path $map)) { Set-Content $map '{"version":3,"sources":[],"names":[],"mappings":""}' }

# Back in CafeConnWeb/ — collectstatic picks up the new files, then restart
cd ..\CafeConnWeb
docker compose restart web
```

macOS (zsh/bash) — same steps:

```bash
# From MonoRepForCafeConn/CafeConn/
flutter build web --release --base-href /staff/
cp -R build/web/. ../CafeConnWeb/static/staff/

# REQUIRED: same source-map placeholder (see note above)
MAP=../CafeConnWeb/static/staff/flutter.js.map
[ -f "$MAP" ] || echo '{"version":3,"sources":[],"names":[],"mappings":""}' > "$MAP"

cd ../CafeConnWeb && docker compose restart web
```

> Since v0.2.0 the web build needs **no** `--dart-define=API_BASE_URL`: the PWA
> is served by Django itself at `/staff/`, so it talks to its own origin. A new
> LAN IP no longer requires a rebuild (QR-код links still встраивают IP — держите
> DHCP-резервацию на роутере, чтобы адрес не менялся).

---

## After a Dockerfile or requirements.txt change

A restart is not enough — must rebuild the image:

```powershell
docker compose up -d --build
```

---

## What WhiteNoise actually does (important for static files)

From `backend_core/settings.py`:

```
STATIC_ROOT  = BASE_DIR / "staticfiles"   ← where collectstatic copies files to
STATICFILES_DIRS = [BASE_DIR / "static"]  ← your source files (including static/staff/)
STORAGES → CompressedManifestStaticFilesStorage  ← WhiteNoise compresses + fingerprints
```

WhiteNoise serves from `STATIC_ROOT` (the collected output), **not** from `STATICFILES_DIRS`
directly. On container startup the `command:` block runs `collectstatic --noinput` which
copies everything from `static/` into `staticfiles/`. A `docker compose restart web`
reruns that command. So:

- Edit a CSS file → restart → WhiteNoise picks it up ✓  
- Drop a new Flutter build into `static/staff/` → restart → served ✓  
- Add a file **without** restarting → WhiteNoise keeps serving the old version ✗

---

## Print QR codes for tables

Each QR should encode the table-scoped URL **by table number** (`/menu/n/…`, not
the legacy `/menu/t/…` which uses an internal DB id and breaks after reseeding):

```
http://<LAN-IP>:8000/menu/n/<NUMBER>/
```

Replace `<LAN-IP>` with the current LAN IP (`ipconfig`). Example for table 7:

```
http://192.168.1.94:8000/menu/n/7/
```

Generate QRs with any free QR generator (one per table, numbered 1–30).
**Reprint if the LAN IP changes.**

---

## Staff PWA — install on iPhone

1. Open `http://192.168.179.75:8000/staff/` in Safari.
2. Tap the Share icon → **Add to Home Screen**.
3. Tap Add. The icon appears on the home screen and launches full-screen.

---

## Verify end-to-end before opening to guests

```
□ docker compose ps → all three: Up (healthy)
□ Each account (tony/ibi/alina/uluk) logs in → sees kitchen, bar, floor, panel tabs
□ None of the four can reach http://192.168.179.75:8000/system-admin/ (is_superuser=False)
□ Scan a printed QR for table 7 → menu opens with «стол 7» badge, no dropdown
□ Tap «Позвать официанта» → staff PWA shows the call within ~1 s, 5/5 times; «Счёт» works too
□ Staff PWA shows real bar data (56 items, 31 tables), not seed_demo placeholders
□ All 30 QR codes open the correct scoped table
```

---

## Shut down

```powershell
docker compose down        # stops containers, preserves postgres_data volume (orders safe)
docker compose down -v     # DANGER: also deletes the volume — wipes all orders and data
```
