from importlib import import_module

from django.db import migrations


ARCHIVE_TAG = "archived"


def archive_obsolete_menu_items(apps, schema_editor):
    """Hide old POS/menu rows that were intentionally seeded unavailable.

    They are kept in the DB so historic orders can still point to them, but
    guest/staff menu screens should not list them as stop-list items.
    """
    MenuItem = apps.get_model("core", "MenuItem")
    reset_menu = import_module("apps.core.migrations.0013_reset_sissi_menu")
    obsolete = {
        (name, category, price)
        for name, category, _station, price, _description, _composition, available in reset_menu.ITEMS
        if available is False
    }

    for item in MenuItem.objects.filter(is_available=False):
        key = (item.name, item.category, f"{item.price:.2f}")
        if key not in obsolete:
            continue
        tags = list(item.tags or [])
        if ARCHIVE_TAG not in tags:
            tags.append(ARCHIVE_TAG)
            item.tags = tags
            item.save(update_fields=["tags", "updated_at"])


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0017_dedupe_menu_by_label"),
    ]

    operations = [
        migrations.RunPython(archive_obsolete_menu_items, migrations.RunPython.noop),
    ]
