from django.db import migrations


# The owner's most-sold positions (the two R-Keeper quick screens). These get
# the 'popular' tag so the waiter composer opens on a ready-to-tap shelf.
# Staff can pin/unpin any item afterwards (hold a tile in the app), so this
# list only has to be right-ish, not perfect.
POPULAR_NAMES = [
    "Caffè",
    "Cioccolata con panna",
    "Decaffeinato",
    "Lungo caffè",
    "Macchiato",
    "Macchiato freddo",
    "Macchiatone",
    "No lattosio cappuccio",
    "Orzo piccolo",
    "Tè / tisana",
    "Cappuccino",
    "Acqua 0,5 naturale Pejo",
    "Acqua 0,5 asporto",
    "Bicchiere H2O",
    "Bicchiere H2O frizzante",
    "Coca Cola",
    "Sanbitter",
    "Spremuta arancia",
    "Club sandwich",
    "Toast",
    "Krapfen crema",
    "Krapfen marmellata",
    "Krapfen Nutella",
    "Krapfen vuoto",
    "Occhio di bue cioccolato",
    "Occhio di bue marmellata",
    "Sacher",
    "Strudel di mele",
    "Aperol Spritz",
    "Gin tonic 12€ base",
]


def seed_popular(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    for item in MenuItem.objects.filter(name__in=POPULAR_NAMES):
        tags = list(item.tags or [])
        if "archived" in tags or "popular" in tags:
            continue
        tags.append("popular")
        item.tags = tags
        item.save(update_fields=["tags", "updated_at"])


def unseed_popular(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    for item in MenuItem.objects.filter(name__in=POPULAR_NAMES):
        tags = list(item.tags or [])
        if "popular" not in tags:
            continue
        tags.remove("popular")
        item.tags = tags
        item.save(update_fields=["tags", "updated_at"])


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0021_order_accepted_at"),
    ]

    operations = [
        migrations.RunPython(seed_popular, unseed_popular),
    ]
