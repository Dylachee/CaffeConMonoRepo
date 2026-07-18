from django.db import migrations

from apps.core.menu_i18n import MENU_ITEM_TRANSLATIONS


def _label(name):
    """The English display label the app shows for a raw menu name."""
    return MENU_ITEM_TRANSLATIONS.get(name, {}).get("en", name)


def dedupe_by_label(apps, schema_editor):
    """Second-pass dedup for items that share a *display* name but differ in
    raw name — e.g. old 'Caffè espresso' vs new 'Espresso', both shown as
    "Espresso". Keep the best copy (available/newest), repoint order history."""
    MenuItem = apps.get_model("core", "MenuItem")
    OrderItem = apps.get_model("core", "OrderItem")

    groups = {}
    for mi in MenuItem.objects.all().order_by("id"):
        groups.setdefault(_label(mi.name), []).append(mi)

    for label, items in groups.items():
        if len(items) < 2:
            continue
        items.sort(key=lambda m: (m.is_available, m.updated_at, m.id))
        keep = items[-1]
        for dup in items[:-1]:
            OrderItem.objects.filter(menu_item=dup).update(menu_item=keep)
            dup.delete()


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0016_dedupe_menu_items"),
    ]

    operations = [
        migrations.RunPython(dedupe_by_label, migrations.RunPython.noop),
    ]
