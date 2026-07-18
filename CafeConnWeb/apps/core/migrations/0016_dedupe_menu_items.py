from django.db import migrations


def dedupe_menu(apps, schema_editor):
    """Collapse duplicate menu items (same name) down to a single copy.

    The printed-menu reload left old English-seeded rows sitting next to the
    fresh ones. For each name we keep the best copy — available first, then the
    most recently updated, then the highest id — repoint any order-history rows
    to it, and delete the leftovers."""
    MenuItem = apps.get_model("core", "MenuItem")
    OrderItem = apps.get_model("core", "OrderItem")

    groups = {}
    for mi in MenuItem.objects.all().order_by("id"):
        groups.setdefault(mi.name, []).append(mi)

    for name, items in groups.items():
        if len(items) < 2:
            continue
        items.sort(key=lambda m: (m.is_available, m.updated_at, m.id))
        keep = items[-1]
        for dup in items[:-1]:
            # OrderItem.menu_item is PROTECT — move any references first.
            OrderItem.objects.filter(menu_item=dup).update(menu_item=keep)
            dup.delete()


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0015_order_event"),
    ]

    operations = [
        migrations.RunPython(dedupe_menu, migrations.RunPython.noop),
    ]
