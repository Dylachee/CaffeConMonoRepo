# Deployment Checklist

## Required Services

- Django/Daphne web process
- PostgreSQL 16+
- Redis 7+
- Persistent media storage if uploads are added later

## Environment

Set DJANGO_SECRET_KEY, DJANGO_DEBUG=false, DJANGO_ALLOWED_HOSTS, DJANGO_CSRF_TRUSTED_ORIGINS, PostgreSQL variables, and REDIS_URL.

## Release Commands

- python manage.py migrate
- python manage.py collectstatic --noinput
- daphne -b 0.0.0.0 -p 8000 backend_core.asgi:application

Terminate TLS at the platform load balancer or a reverse proxy, and forward X-Forwarded-Proto.
