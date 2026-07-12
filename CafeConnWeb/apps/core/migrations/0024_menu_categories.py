import django.db.models.deletion
from django.db import migrations, models
from django.utils.text import slugify


CATEGORIES = [
    ("caffetteria", "Caffetteria", "#E0823A", 0),
    ("bevande", "Bevande", "#5BAEDC", 1),
    ("analcolici", "Analcolici", "#3E9C63", 2),
    ("birra", "Birra", "#DFAF2B", 3),
    ("vino", "Vino", "#C0463B", 4),
    ("cocktail-aperitivi", "Cocktail & Aperitivi", "#7CC488", 5),
    ("liquori-grappe-amari", "Liquori/Grappe/Amari", "#8A6FC0", 6),
    ("pasticceria", "Pasticceria", "#B88746", 7),
    ("dolci", "Dolci", "#C95F8A", 8),
    ("gelati", "Gelati", "#3C7BCF", 9),
    ("panini", "Panini", "#DFAF2B", 10),
    ("piadine", "Piadine", "#C9A227", 11),
    ("tortel", "Tortel", "#B97832", 12),
    ("secondi", "Secondi", "#A94D3E", 13),
    ("uova-colazione-salata", "Uova/colazione salata", "#6F8F42", 14),
    ("toast", "Toast", "#9A7A45", 15),
    ("fritti-stuzzichini", "Fritti/stuzzichini", "#B66A2D", 16),
]

ALIASES = {
    "CAFFETTERIA": "Caffetteria",
    "BEVANDE": "Bevande",
    "ANALCOLICI": "Analcolici",
    "BIRRA": "Birra",
    "VINO": "Vino",
    "LIQUORI": "Liquori/Grappe/Amari",
    "LIQUORI / GRAPPE / AMARI": "Liquori/Grappe/Amari",
    "LIQUORI/GRAPPE/AMARI": "Liquori/Grappe/Amari",
    "APERITIVI": "Cocktail & Aperitivi",
    "COCKTAILS": "Cocktail & Aperitivi",
    "COCKTAIL & APERITIVI": "Cocktail & Aperitivi",
    "COLAZIONE": "Pasticceria",
    "PASTICCERIA / COLAZIONE": "Pasticceria",
    "PASTICCERIA": "Pasticceria",
    "DOLCI": "Dolci",
    "GELATI": "Gelati",
    "PANINI": "Panini",
    "PIADINE": "Piadine",
    "TORTEL": "Tortel",
    "TORTEL DI PATATE": "Tortel",
    "SECONDI": "Secondi",
    "UOVA / COLAZIONE SALATA": "Uova/colazione salata",
    "UOVA/COLAZIONE SALATA": "Uova/colazione salata",
    "TOAST": "Toast",
    "FRITTI / STUZZICHINI": "Fritti/stuzzichini",
    "FRITTI/STUZZICHINI": "Fritti/stuzzichini",
    "FOOD": "Panini",
    "CUCINA": "Panini",
    "SPUNTINO SALATO": "Fritti/stuzzichini",
    "DA STUZZICARE": "Fritti/stuzzichini",
}


def canonical_name(raw):
    name = (raw or "").strip()
    if not name:
        return "Panini"
    key = " ".join(name.upper().split())
    return ALIASES.get(key, name)


def category_key(name):
    return slugify(name)[:40] or "category"


def backfill_categories(apps, schema_editor):
    MenuCategory = apps.get_model("core", "MenuCategory")
    MenuItem = apps.get_model("core", "MenuItem")

    by_name = {}
    for key, name, color, sort_order in CATEGORIES:
        category, _ = MenuCategory.objects.update_or_create(
            key=key,
            defaults={"name": name, "color": color, "sort_order": sort_order},
        )
        by_name[name] = category

    for item in MenuItem.objects.select_related("category").all():
        legacy = getattr(item, "legacy_category", "") or ""
        name = canonical_name(legacy)
        if name not in by_name:
            key = category_key(name)
            category, _ = MenuCategory.objects.get_or_create(
                key=key,
                defaults={
                    "name": name,
                    "color": "#DFAF2B",
                    "sort_order": MenuCategory.objects.count(),
                },
            )
            by_name[name] = category
        item.category = by_name[name]
        item.save(update_fields=["category"])

    # Remove the old coarse POS buckets only when they are empty after the
    # backfill. Custom unused categories are left alone.
    MenuCategory.objects.filter(
        key__in=["food", "liquori", "aperitivi"],
        items__isnull=True,
    ).delete()


def reverse_backfill(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    for item in MenuItem.objects.select_related("category").all():
        if item.category_id:
            item.legacy_category = item.category.name
            item.save(update_fields=["legacy_category"])


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0023_menu_families"),
    ]

    operations = [
        migrations.RenameModel(
            old_name="MenuFamily",
            new_name="MenuCategory",
        ),
        migrations.AlterModelTable(
            name="menucategory",
            table="cafe_menu_categories",
        ),
        migrations.AlterModelOptions(
            name="menucategory",
            options={
                "ordering": ["sort_order", "name"],
                "verbose_name_plural": "menu categories",
            },
        ),
        migrations.RenameField(
            model_name="menuitem",
            old_name="category",
            new_name="legacy_category",
        ),
        migrations.RenameField(
            model_name="menuitem",
            old_name="family",
            new_name="category",
        ),
        migrations.AlterField(
            model_name="menuitem",
            name="category",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="items",
                to="core.menucategory",
            ),
        ),
        migrations.RunPython(backfill_categories, reverse_backfill),
        migrations.AlterField(
            model_name="menuitem",
            name="category",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name="items",
                to="core.menucategory",
            ),
        ),
        migrations.RemoveField(
            model_name="menuitem",
            name="legacy_category",
        ),
        migrations.AlterModelOptions(
            name="menuitem",
            options={"ordering": ["category__sort_order", "category__name", "name"]},
        ),
    ]
