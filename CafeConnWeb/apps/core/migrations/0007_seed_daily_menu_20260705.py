from decimal import Decimal

from django.db import migrations


DAILY_ITEMS = [
    {
        "name": "Spiedino di pollo con patatine fritte",
        "description": "Spiedino di pollo servito con patatine fritte.",
        "price": Decimal("14.00"),
        "allergens": [],
    },
    {
        "name": "Caprese",
        "description": "Pomodoro, mozzarella e basilico.",
        "price": Decimal("12.00"),
        "allergens": ["Milk"],
    },
    {
        "name": "Cestino di insalata verde rucola e pomodoro",
        "description": "Insalata verde con rucola e pomodoro.",
        "price": Decimal("12.00"),
        "allergens": [],
    },
    {
        "name": "Nuggets di pollo",
        "description": "Nuggets di pollo.",
        "price": Decimal("6.00"),
        "allergens": ["Gluten"],
    },
    {
        "name": "Piadina tacchino pomodoro insalata",
        "description": "Piadina con tacchino, pomodoro e insalata.",
        "price": Decimal("8.50"),
        "allergens": ["Gluten"],
    },
]


def seed_daily_menu(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    shared = {
        "category": "Menu del giorno",
        "station": "kitchen",
        "tags": ["daily", "valid_until:2026-07-05"],
        "is_available": True,
        "is_promoted": True,
        "preparation_minutes": 12,
        "portion_weight": "1 plate",
        "calories": 650,
        "image_url": "",
    }
    for item in DAILY_ITEMS:
        defaults = {
            **shared,
            "description": item["description"],
            "price": item["price"],
            "composition": item["description"],
            "allergens": item["allergens"],
        }
        existing = MenuItem.objects.filter(name=item["name"]).order_by("id").first()
        if existing:
            for field, value in defaults.items():
                setattr(existing, field, value)
            existing.save()
        else:
            MenuItem.objects.create(name=item["name"], **defaults)


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0006_collapse_order_status_constraints_indexes"),
    ]

    operations = [
        migrations.RunPython(seed_daily_menu, migrations.RunPython.noop),
    ]
