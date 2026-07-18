from decimal import Decimal

from django.db import migrations

from apps.core.menu_catalog import RAW_MENU, normalized_category, station_for_category


OLD_CATEGORY_NAMES = {
    "APERITIVI": "Aperitivi",
    "BEVANDE": "Bevande",
    "CAFFETTERIA": "Caffetteria",
    "DOLCI": "Dolci",
    "FOOD": "Food",
    "GELATI": "Gelati",
    "LIQUORI": "Liquori",
    "VINO": "Vino",
}


def old_category(raw_category):
    key = raw_category.strip().upper()
    return OLD_CATEGORY_NAMES.get(key, raw_category.title())


def update_categories(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")

    for name, price, raw_category, *_rest in RAW_MENU:
        target_category = normalized_category(raw_category, name)
        target_station = station_for_category(raw_category)
        categories = {old_category(raw_category), target_category}
        for item in MenuItem.objects.filter(
            name=name,
            price=Decimal(price),
            category__in=categories,
        ):
            tags = item.tags or []
            if "archived" in tags:
                continue
            item.category = target_category
            item.station = target_station
            item.save(update_fields=["category", "station", "updated_at"])


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0021_raw_staff_menu_client_tags"),
    ]

    operations = [
        migrations.RunPython(update_categories, noop),
    ]
