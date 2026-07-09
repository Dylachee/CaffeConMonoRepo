from django.db import migrations

from apps.core.menu_catalog import catalog_items


ARCHIVE_TAG = "archived"


def archive_or_delete(OrderItem, item):
    if OrderItem.objects.filter(menu_item_id=item.pk).exists():
        tags = list(item.tags or [])
        if ARCHIVE_TAG not in tags:
            tags.append(ARCHIVE_TAG)
        item.tags = tags
        item.is_available = False
        item.save(update_fields=["tags", "is_available", "updated_at"])
        return
    item.delete()


def reload_raw_menu(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    OrderItem = apps.get_model("core", "OrderItem")

    for item in list(MenuItem.objects.all()):
        archive_or_delete(OrderItem, item)

    MenuItem.objects.bulk_create([MenuItem(**item) for item in catalog_items()])


def noop(apps, schema_editor):
    # One-way menu reset; historic referenced rows may be archived.
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0018_reload_sissi_menu"),
    ]

    operations = [
        migrations.RunPython(reload_raw_menu, noop),
    ]
