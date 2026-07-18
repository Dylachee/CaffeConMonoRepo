from django.db import migrations


def archive_unavailable_menu_items(apps, schema_editor):
    """Hide stale unavailable menu rows from guest/staff menus.

    The manager can still stop-list live rows later, but the current database
    contains many old unavailable imports that should no longer be selectable.
    """
    MenuItem = apps.get_model("core", "MenuItem")
    for item in MenuItem.objects.filter(is_available=False):
        tags = list(item.tags or [])
        if "archived" in tags:
            continue
        tags.append("archived")
        item.tags = tags
        item.save(update_fields=["tags", "updated_at"])


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0018_archive_obsolete_menu_items"),
    ]

    operations = [
        migrations.RunPython(archive_unavailable_menu_items, migrations.RunPython.noop),
    ]
