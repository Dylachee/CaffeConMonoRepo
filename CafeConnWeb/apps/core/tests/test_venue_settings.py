from django.core.cache import cache
from django.test import TestCase

from apps.core.models import VenueSettings
from apps.core.theme_presets import SISSI_PALETTE, THEME_PRESETS


class VenueSettingsSoloTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_get_solo_creates_singleton_with_sissi_defaults(self):
        settings = VenueSettings.get_solo()
        self.assertEqual(settings.slug, "sissy-bar")
        self.assertEqual(settings.name, "Caffè & Bistrò Sissi")
        self.assertEqual(settings.palette(), SISSI_PALETTE)
        # Repeated calls return the same row, not new ones.
        again = VenueSettings.get_solo()
        self.assertEqual(settings.pk, again.pk)
        self.assertEqual(VenueSettings.objects.count(), 1)

    def test_get_solo_is_cached_and_invalidated_on_save(self):
        first = VenueSettings.get_solo()
        with self.assertNumQueries(0):
            VenueSettings.get_solo()  # served from cache
        first.name = "Another venue"
        first.save()  # must drop the cache
        self.assertEqual(VenueSettings.get_solo().name, "Another venue")

    def test_future_per_venue_slug_isolation(self):
        VenueSettings.get_solo()
        other = VenueSettings.get_solo("second-venue")
        other.name = "Second venue"
        other.save()
        self.assertEqual(VenueSettings.get_solo().name, "Caffè & Bistrò Sissi")
        self.assertEqual(VenueSettings.get_solo("second-venue").name, "Second venue")

    def test_css_variables_match_original_root_block(self):
        expected = [
            ("--bg", "#f2efe8"),
            ("--card", "#ffffff"),
            ("--ink", "#1e1b16"),
            ("--mut", "#8b8377"),
            ("--line", "#e7e2d8"),
            ("--accent", "#c8821e"),
            ("--accent-deep", "#9a6310"),
            ("--accent-soft", "#f1e2c8"),
        ]
        self.assertEqual(VenueSettings.get_solo().css_variables(), expected)

    def test_blocks_sanitizes_junk_and_backfills_missing(self):
        settings = VenueSettings.get_solo()
        settings.storefront_blocks = [
            {"key": "about", "visible": False},
            {"key": "nonsense", "visible": True},
            "garbage",
            {"key": "about", "visible": True},  # duplicate ignored
        ]
        settings.save()
        blocks = VenueSettings.get_solo().blocks()
        self.assertEqual(blocks[0], {"key": "about", "visible": False})
        keys = [block["key"] for block in blocks]
        self.assertEqual(
            sorted(keys), sorted(VenueSettings.STOREFRONT_BLOCK_KEYS)
        )

    def test_sissi_is_the_first_builtin_preset(self):
        self.assertEqual(THEME_PRESETS[0]["key"], "sissi")
        self.assertEqual(THEME_PRESETS[0]["palette"], SISSI_PALETTE)
