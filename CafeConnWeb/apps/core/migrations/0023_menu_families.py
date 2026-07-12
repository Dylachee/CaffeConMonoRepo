import django.db.models.deletion
from django.db import migrations, models


# Seed = the owner's 8 POS families with the colors the app shipped hardcoded.
# From here on, names and colors are DATA (editable in the manager panel and
# /system-admin/), not code.
SEED = [
    ("caffetteria", "Caffetteria", "#E0823A", 0),
    ("bevande", "Bevande", "#5BAEDC", 1),
    ("liquori", "Liquori", "#3E9C63", 2),
    ("vino", "Vino", "#C0463B", 3),
    ("gelati", "Gelati", "#3C7BCF", 4),
    ("food", "Food", "#DFAF2B", 5),
    ("dolci", "Dolci", "#8A6FC0", 6),
    ("aperitivi", "Aperitivi", "#7CC488", 7),
]


def _family_key(category):
    c = (category or "").lower()

    def has(*keys):
        return any(k in c for k in keys)

    if has("caffett", "coffee"):
        return "caffetteria"
    if has("gelat"):
        return "gelati"
    if has("dolc", "dessert"):
        return "dolci"
    if has("liquor", "grapp", "amari"):
        return "liquori"
    if has("vino", "wine"):
        return "vino"
    if has("aperitiv", "cocktail", "birra", "spritz"):
        return "aperitivi"
    if has("bibit", "bevand", "analcolic", "succ"):
        return "bevande"
    return "food"


def seed_and_backfill(apps, schema_editor):
    MenuFamily = apps.get_model("core", "MenuFamily")
    MenuItem = apps.get_model("core", "MenuItem")

    by_key = {}
    for key, name, color, sort_order in SEED:
        family, _ = MenuFamily.objects.get_or_create(
            key=key,
            defaults={"name": name, "color": color, "sort_order": sort_order},
        )
        by_key[key] = family

    # One-time backfill of the NEW column only — no menu content is touched.
    for item in MenuItem.objects.filter(family__isnull=True):
        item.family = by_key[_family_key(item.category)]
        item.save(update_fields=["family"])


def unseed(apps, schema_editor):
    pass  # dropping the table (schema reverse) is enough


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0022_seed_popular_tags"),
    ]

    operations = [
        migrations.CreateModel(
            name="MenuFamily",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("key", models.SlugField(max_length=40, unique=True)),
                ("name", models.CharField(max_length=80)),
                ("color", models.CharField(default="#DFAF2B", max_length=9)),
                ("sort_order", models.PositiveSmallIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "db_table": "cafe_menu_families",
                "ordering": ["sort_order", "name"],
                "verbose_name_plural": "menu families",
            },
        ),
        migrations.AddField(
            model_name="menuitem",
            name="family",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="items",
                to="core.menufamily",
            ),
        ),
        migrations.RunPython(seed_and_backfill, unseed),
    ]
