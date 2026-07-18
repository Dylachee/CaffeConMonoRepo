from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.db import migrations

# Clean slate for the staff roster. Existing users are removed (orders/tables
# keep their rows via SET_NULL) and these seven accounts are created.
# (username, display name, role, is_staff, is_superuser, can_wait, can_bar,
#  can_kitchen, can_manage_menu, password)
STAFF = [
    ("owner",     "Владелец",   "admin",   True,  True,  True,  True,  True,  True,  "Owner2026!"),
    ("manager",   "Менеджер",   "manager", True,  False, True,  True,  True,  True,  "Manager2026!"),
    ("waiter1",   "Официант 1", "waiter",  False, False, True,  True,  True,  False, "Waiter2026!"),
    ("waiter2",   "Официант 2", "waiter",  False, False, True,  True,  True,  False, "Waiter2026!"),
    ("waiter3",   "Официант 3", "waiter",  False, False, True,  True,  True,  False, "Waiter2026!"),
    ("bartender", "Бартендер",  "bar",     False, False, True,  True,  True,  False, "Bartender2026!"),
    ("cook",      "Повар",      "kitchen", False, False, False, False, True,  False, "Cook2026!"),
]


def reset_staff(apps, schema_editor):
    User = apps.get_model(settings.AUTH_USER_MODEL)
    Employee = apps.get_model("core", "Employee")

    # Wipe the whole user base (cascades employees, tokens, preferences).
    User.objects.all().delete()

    for (username, name, role, is_staff, is_superuser,
         can_wait, can_bar, can_kitchen, can_manage_menu, password) in STAFF:
        user = User.objects.create(
            username=username,
            first_name=name,
            is_staff=is_staff,
            is_superuser=is_superuser,
            is_active=True,
            password=make_password(password),
        )
        Employee.objects.create(
            user=user,
            name=name,
            role=role,
            is_on_shift=True,
            can_wait=can_wait,
            can_bar=can_bar,
            can_kitchen=can_kitchen,
            can_manage_menu=can_manage_menu,
        )


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0013_reset_sissi_menu"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.RunPython(reset_staff, noop),
    ]
