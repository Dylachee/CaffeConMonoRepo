# CafeConnect Django Hub

Django is the central hub for CafeConnect. It renders the guest menu and management dashboard, and exposes REST + WebSocket interfaces for the Flutter staff app.

## Local Start

1. Copy .env.example to .env and change DJANGO_SECRET_KEY before any real deployment.
2. Start services: docker compose up --build
3. Load demo data: docker compose exec web python manage.py seed_demo
4. Create a staff/admin user: docker compose exec web python manage.py createsuperuser

## Main URLs

- Guest menu: http://localhost:8000/menu/
- Management dashboard: http://localhost:8000/dashboard/
- Django admin: http://localhost:8000/system-admin/
- REST API root: http://localhost:8000/api/
- Health check: http://localhost:8000/api/health/

## Flutter Integration

Get a DRF token with POST /api/auth/token/ and JSON body: {"username":"staff","password":"password"}.
Use Authorization: Token <token> for REST calls.
Connect to ws://localhost:8000/ws/staff/?token=<token> for realtime order updates.

Order events look like: {"event":"order.created","order":{"id":1,"status":"pending"}}

## Production Notes

- Set DJANGO_DEBUG=false.
- Set a strong DJANGO_SECRET_KEY.
- Set real DJANGO_ALLOWED_HOSTS and DJANGO_CSRF_TRUSTED_ORIGINS.
- Keep PostgreSQL and Redis managed or backed up.
- Put a reverse proxy such as Nginx or Caddy in front of Daphne for TLS.
