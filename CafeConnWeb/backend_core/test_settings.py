"""Settings for running the Django test suite (and a local dev server) on
SQLite — for environments without a PostgreSQL service (CI, sandboxes).

Production settings are untouched: this module is opt-in via
    python manage.py test --settings=backend_core.test_settings
    python manage.py migrate --settings=backend_core.test_settings

The app uses no Postgres-specific features (plain JSONField works on SQLite),
so the suite exercises the same code paths.
"""

from backend_core.settings import *  # noqa: F401,F403
from backend_core.settings import BASE_DIR

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "test_db.sqlite3",
    }
}

# Tests must not depend on cross-test cache state.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "cafeconnect-tests",
    }
}

# Keep uploaded test media out of the real MEDIA_ROOT.
MEDIA_ROOT = BASE_DIR / "test_media"
