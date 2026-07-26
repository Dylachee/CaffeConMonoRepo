import json
from pathlib import Path

from django.db import migrations


def seed_snapshot_if_empty(apps, schema_editor):
    Restaurant = apps.get_model("core", "Restaurant")
    MenuCategory = apps.get_model("core", "MenuCategory")
    MenuItem = apps.get_model("core", "MenuItem")
    snapshot_dir = Path(__file__).resolve().parent.parent / "menu_snapshots"
    for path in snapshot_dir.glob("*.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        restaurant = Restaurant.objects.filter(slug=payload["restaurant"]).first()
        if restaurant is None or MenuItem.objects.filter(restaurant=restaurant).exists():
            continue
        categories = {}
        for row in payload.get("categories", []):
            category, _ = MenuCategory.objects.update_or_create(
                restaurant=restaurant,
                key=row["key"],
                defaults={
                    "name": row["name"],
                    "color": row["color"],
                    "sort_order": row["sort_order"],
                },
            )
            categories[row["key"]] = category
        for row in payload.get("items", []):
            data = dict(row)
            data["category"] = categories[data.pop("category")]
            MenuItem.objects.create(restaurant=restaurant, **data)


class Migration(migrations.Migration):

    dependencies = [("core", "0041_order_idempotency_task_recurrence_enabled")]

    operations = [
        migrations.RunPython(seed_snapshot_if_empty, migrations.RunPython.noop),
    ]
