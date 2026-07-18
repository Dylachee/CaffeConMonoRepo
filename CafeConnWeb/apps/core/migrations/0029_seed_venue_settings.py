"""Seed the venue storefront with the approved Sissi design.

Carries the static VENUE dict (apps/guest_web/views.py) and the guest page's
original :root palette (templates/guest_web/menu.html) into the database, so
that immediately after deploy — with zero configuration — /menu/ renders
pixel-for-pixel identical to the previous hardcoded version. The values are
spelled out literally here (not via model defaults) so this migration keeps
seeding the historical Sissi look even if the model defaults change later.
"""

from django.db import migrations

SISSI = {
    "slug": "default",
    "name": "Caffè & Bistrò Sissi",
    "tagline": "Café, bistro and bar in Madonna di Campiglio",
    "tagline_it": "Caffè, bistrot e bar a Madonna di Campiglio",
    "about": (
        "A warm mountain bistro for coffee, aperitifs, cocktails, sandwiches, "
        "sweet treats and quick dishes from the Sissi menu."
    ),
    "about_it": (
        "Un bistrot di montagna per caffetteria, aperitivi, cocktail, panini, "
        "dolci e piatti veloci dal menu Sissi."
    ),
    "address": "Madonna di Campiglio · Trentino",
    "address_it": "Madonna di Campiglio · Trentino",
    "hours": "Ask staff for today's hours",
    "hours_it": "Chiedi allo staff gli orari di oggi",
    "badges": [
        {"en": "Coffee & hot chocolate", "it": "Caffè e cioccolata"},
        {"en": "Aperitifs & cocktails", "it": "Aperitivi e cocktail"},
        {"en": "Sweet and savory snacks", "it": "Dolce e salato"},
    ],
    "maps_url": "https://maps.app.goo.gl/L8UMd16ZXUTk5Jx28",
    # The original menu.html :root palette — the "Sissi" built-in preset.
    "color_bg": "#f2efe8",
    "color_card": "#ffffff",
    "color_ink": "#1e1b16",
    "color_mut": "#8b8377",
    "color_line": "#e7e2d8",
    "color_accent": "#c8821e",
    "color_accent_deep": "#9a6310",
    "color_accent_soft": "#f1e2c8",
    "storefront_blocks": [
        {"key": "cover", "visible": True},
        {"key": "facts", "visible": True},
        {"key": "badges", "visible": True},
        {"key": "cta", "visible": True},
        {"key": "popular", "visible": True},
        {"key": "about", "visible": True},
    ],
    "pinned_posts_limit": 3,
}


def seed_venue_settings(apps, schema_editor):
    VenueSettings = apps.get_model("core", "VenueSettings")
    defaults = {key: value for key, value in SISSI.items() if key != "slug"}
    VenueSettings.objects.get_or_create(slug=SISSI["slug"], defaults=defaults)


def unseed_venue_settings(apps, schema_editor):
    VenueSettings = apps.get_model("core", "VenueSettings")
    VenueSettings.objects.filter(slug=SISSI["slug"]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0028_social_posts_venue_settings_smm"),
    ]

    operations = [
        migrations.RunPython(seed_venue_settings, unseed_venue_settings),
    ]
