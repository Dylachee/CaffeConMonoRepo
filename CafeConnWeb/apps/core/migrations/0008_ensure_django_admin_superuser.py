import os

from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.db import migrations


FALLBACK_USERNAMES = ("manager", "tony", "ibi", "alina", "uluk", "admin")


def ensure_django_admin_superuser(apps, schema_editor):
    app_label, model_name = settings.AUTH_USER_MODEL.split(".")
    User = apps.get_model(app_label, model_name)

    env_username = os.environ.get("DJANGO_SUPERUSER_USERNAME", "").strip()
    env_email = os.environ.get("DJANGO_SUPERUSER_EMAIL", "").strip()
    env_password = os.environ.get("DJANGO_SUPERUSER_PASSWORD", "").strip()

    if env_username:
        username = env_username
        user = User.objects.filter(username=username).first()
    elif env_password:
        username = "admin"
        user = User.objects.filter(username=username).first()
    else:
        user = None
        for username in FALLBACK_USERNAMES:
            user = User.objects.filter(username=username).first()
            if user:
                break
        if user is None:
            return

    if user is None:
        user = User(username=username)
        user.email = env_email

    user.is_staff = True
    user.is_superuser = True
    user.is_active = True
    if env_email:
        user.email = env_email
    if env_password:
        user.password = make_password(env_password)
    user.save()


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0007_seed_daily_menu_20260705"),
    ]

    operations = [
        migrations.RunPython(ensure_django_admin_superuser, migrations.RunPython.noop),
    ]
