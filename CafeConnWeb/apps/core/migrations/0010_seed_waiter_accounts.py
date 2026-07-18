from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.db import migrations

# Three extra floor waiters so more than one person can work the room.
# Same default password as the seeded `waiter` account — change it before
# go-live with `manage.py changepassword <username>`. Tokens are created
# lazily on first login (POST /api/auth/token/), so none is seeded here.
NEW_WAITERS = [
    ("waiter2", "Waiter 2"),
    ("waiter3", "Waiter 3"),
    ("waiter4", "Waiter 4"),
]
DEFAULT_PASSWORD = "Waiter2026!"


def create_waiters(apps, schema_editor):
    User = apps.get_model(settings.AUTH_USER_MODEL)
    Employee = apps.get_model("core", "Employee")
    for username, name in NEW_WAITERS:
        user, _ = User.objects.get_or_create(
            username=username,
            defaults={
                "first_name": name,
                "is_staff": False,
                "is_superuser": False,
                "password": make_password(DEFAULT_PASSWORD),
            },
        )
        Employee.objects.update_or_create(
            user=user,
            defaults={"name": name, "role": "waiter", "is_on_shift": True},
        )


def remove_waiters(apps, schema_editor):
    User = apps.get_model(settings.AUTH_USER_MODEL)
    User.objects.filter(username__in=[u for u, _ in NEW_WAITERS]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0009_sync_printed_sissi_menu"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.RunPython(create_waiters, remove_waiters),
    ]
