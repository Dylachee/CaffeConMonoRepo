from django.db import migrations


def add_table_zero(apps, schema_editor):
    Restaurant = apps.get_model("core", "Restaurant")
    Table = apps.get_model("core", "Table")

    try:
        restaurant = Restaurant.objects.get(slug="sissy-bar")
    except Restaurant.DoesNotExist:
        return

    Table.objects.update_or_create(
        restaurant=restaurant,
        number=0,
        defaults={"label": "Table 00", "capacity": 4},
    )


class Migration(migrations.Migration):
    dependencies = [("core", "0042_seed_exported_menu_snapshot")]

    operations = [migrations.RunPython(add_table_zero, migrations.RunPython.noop)]
