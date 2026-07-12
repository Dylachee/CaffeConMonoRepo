from django.db import migrations

from apps.core.sissi_menu import CLIENT_MENU_TAG, catalog_items, menu_categories


ARCHIVE_TAG = "archived"

ALIASES = {
    "APERITIVI": "cocktail-aperitivi",
    "BIBITE": "bevande",
    "COCKTAILS": "cocktail-aperitivi",
    "COLAZIONE": "pasticceria",
    "CUCINA": "panini",
    "DA STUZZICARE": "fritti-stuzzichini",
    "FOOD": "panini",
    "GRAPPE E LIQUORI": "liquori-grappe-amari",
    "LIQUORI": "liquori-grappe-amari",
    "MENU DEL GIORNO": "panini",
    "PASTICCERIA / COLAZIONE": "pasticceria",
    "SPUNTINO SALATO": "fritti-stuzzichini",
    "VINO AL CALICE E BOTTIGLIE": "vino",
}


def _tags_for_clients(tags):
    tags = list(tags or [])
    if CLIENT_MENU_TAG not in tags:
        tags.append(CLIENT_MENU_TAG)
    return tags


def _is_archived(item):
    return ARCHIVE_TAG in (item.tags or [])


def _archive_or_delete(OrderItem, item, category):
    if OrderItem.objects.filter(menu_item_id=item.pk).exists():
        tags = list(item.tags or [])
        if ARCHIVE_TAG not in tags:
            tags.append(ARCHIVE_TAG)
        item.tags = tags
        item.category = category
        item.is_available = False
        item.save(update_fields=["tags", "category", "is_available", "updated_at"])
        return
    item.delete()


def _category_for_existing_item(item, categories):
    raw = item.category.name if item.category_id else ""
    key = " ".join(raw.upper().split())
    return categories.get(ALIASES.get(key, ""), categories["panini"])


def normalize_sissi_menu(apps, schema_editor):
    MenuCategory = apps.get_model("core", "MenuCategory")
    MenuItem = apps.get_model("core", "MenuItem")
    OrderItem = apps.get_model("core", "OrderItem")

    categories = {}
    for category in menu_categories():
        obj, _ = MenuCategory.objects.update_or_create(
            key=category["key"],
            defaults={
                "name": category["name"],
                "color": category["color"],
                "sort_order": category["sort_order"],
            },
        )
        categories[category["key"]] = obj

    active_keys = set()
    for raw_item in catalog_items():
        data = dict(raw_item)
        category = categories[data.pop("category_key")]
        data["category"] = category
        data["tags"] = _tags_for_clients(data.get("tags"))

        candidates = list(
            MenuItem.objects.filter(
                station=data["station"],
                name=data["name"],
            ).order_by("id")
        )
        active = [item for item in candidates if not _is_archived(item)]
        if active:
            item = active[0]
            for field, value in data.items():
                setattr(item, field, value)
            item.save(update_fields=[*data.keys(), "updated_at"])
            for duplicate in active[1:]:
                _archive_or_delete(OrderItem, duplicate, category)
        else:
            item = MenuItem.objects.create(**data)

        active_keys.add((item.station, item.category_id, item.name))

    canonical_ids = {category.id for category in categories.values()}
    for item in list(MenuItem.objects.select_related("category").all()):
        key = (item.station, item.category_id, item.name)
        if key in active_keys and not _is_archived(item):
            continue
        if _is_archived(item) and item.category_id in canonical_ids:
            continue
        _archive_or_delete(OrderItem, item, _category_for_existing_item(item, categories))

    MenuCategory.objects.exclude(id__in=canonical_ids).delete()


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0024_menu_categories"),
    ]

    operations = [
        migrations.RunPython(normalize_sissi_menu, noop),
    ]
