from django.core.cache import cache
from django.test import TestCase

from apps.core.models import SocialPost, VenueSettings
from apps.core.social_embed import EMBED_SCRIPTS


def make_post(index: int, *, pinned=False, hidden=False, platform="instagram") -> SocialPost:
    post = SocialPost.objects.create(
        source_url=f"https://www.instagram.com/p/Post{index}/",
        platform=platform,
        embed_html=f'<blockquote class="instagram-media" data-instgrm-permalink="https://www.instagram.com/p/Post{index}/"></blockquote>',
        is_hidden=hidden,
    )
    if pinned:
        post.pin()
    return post


class GuestThemeRenderingTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_default_root_matches_original_sissi_palette(self):
        html = self.client.get("/menu/").content.decode()
        for css in (
            "--bg:#f2efe8",
            "--card:#ffffff",
            "--ink:#1e1b16",
            "--mut:#8b8377",
            "--line:#e7e2d8",
            "--accent:#c8821e",
            "--accent-deep:#9a6310",
            "--accent-soft:#f1e2c8",
        ):
            self.assertIn(css, html)
        self.assertIn('name="theme-color" content="#f2efe8"', html)

    def test_default_derived_tints_equal_original_literals(self):
        """The derived surface/text tokens must reproduce the historical CSS
        values byte-for-byte for the default palette — this is what keeps the
        zero-config page pixel-identical after the theming refactor."""
        html = self.client.get("/menu/").content.decode()
        for css in (
            "--ink-a62:rgba(30,27,22,0.62)",
            "--accent-a45:rgba(200,130,30,0.45)",
            "--line-a78:rgba(231,226,216,0.78)",
            "--bg-a92:rgba(242,239,232,0.92)",
            "--card-a94:rgba(255,255,255,0.94)",
            "--surface-hi:#fffdfa",
            "--surface-low:#f8f4ed",
            "--nav-a94:rgba(252,250,245,.94)",
        ):
            self.assertIn(css, html)
        # No hardcoded tints remain in the CSS rules — only the :root token
        # definitions may spell out the rgba values.
        style = html[html.index("<style>"):html.index("</style>")]
        rules = style[style.index("*{box-sizing"):]
        self.assertNotIn("rgba(30,27,22", rules)
        self.assertNotIn("rgba(200,130,30", rules)

    def test_custom_palette_recolors_derived_tints(self):
        settings = VenueSettings.get_solo()
        settings.color_ink = "#f2eee9"
        settings.color_bg = "#16151a"
        settings.color_card = "#211f27"
        settings.save()
        html = self.client.get("/menu/").content.decode()
        self.assertIn("--ink-a62:rgba(242,238,233,0.62)", html)
        # Neutral surfaces switch from the Sissi literals to card/bg blends.
        self.assertNotIn("--surface-hi:#fffdfa", html)

    def test_saved_palette_renders_into_root(self):
        settings = VenueSettings.get_solo()
        settings.color_accent = "#2f6f96"
        settings.color_bg = "#eef2f4"
        settings.save()
        html = self.client.get("/menu/").content.decode()
        self.assertIn("--accent:#2f6f96", html)
        self.assertIn("--bg:#eef2f4", html)
        self.assertIn('content="#eef2f4"', html)

    def test_storefront_texts_come_from_settings(self):
        settings = VenueSettings.get_solo()
        settings.name = "Trattoria Prova"
        settings.tagline = "A test tagline"
        settings.save()
        html = self.client.get("/menu/").content.decode()
        self.assertIn("Trattoria Prova", html)
        self.assertIn("A test tagline", html)

    def test_hidden_block_disappears(self):
        settings = VenueSettings.get_solo()
        settings.storefront_blocks = [
            {"key": "about", "visible": False},
        ]
        settings.save()
        html = self.client.get("/menu/").content.decode()
        self.assertNotIn('data-i18n="about"', html)
        # Other blocks are backfilled visible.
        self.assertIn('data-i18n="daily_special"', html)

    def test_initial_render_loads_zero_social_scripts(self):
        make_post(1)
        make_post(2, pinned=True)
        html = self.client.get("/menu/").content.decode()
        for script_url in EMBED_SCRIPTS.values():
            self.assertNotIn(script_url, html)
        # No embed markup inlined either — the Feed tab fetches it lazily.
        self.assertNotIn("instagram-media", html)
        self.assertNotIn("platform.twitter.com", html)

    def test_feed_tab_and_screen_present(self):
        html = self.client.get("/menu/").content.decode()
        self.assertIn('data-testid="nav-feed"', html)
        self.assertIn('data-screen="feed"', html)
        self.assertIn('data-testid="feed-list"', html)


class GuestFeedEndpointTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_pinned_first_then_chronological(self):
        posts = [make_post(i) for i in range(1, 5)]
        pinned = make_post(99, pinned=True)
        payload = self.client.get("/menu/feed/").json()
        self.assertTrue(payload["ok"])
        self.assertEqual([p["id"] for p in payload["pinned"]], [pinned.pk])
        self.assertEqual(
            [p["id"] for p in payload["posts"]],
            [post.pk for post in sorted(posts, key=lambda p: -p.pk)],
        )
        self.assertEqual(payload["scripts"], EMBED_SCRIPTS)

    def test_hidden_posts_never_reach_guests(self):
        make_post(1, hidden=True)
        visible = make_post(2)
        payload = self.client.get("/menu/feed/").json()
        self.assertEqual([p["id"] for p in payload["posts"]], [visible.pk])
        self.assertEqual(payload["pinned"], [])

    def test_cursor_pagination(self):
        posts = [make_post(i) for i in range(1, 9)]
        first = self.client.get("/menu/feed/?limit=3").json()
        self.assertEqual(len(first["posts"]), 3)
        self.assertTrue(first["hasMore"])
        self.assertEqual(first["nextCursor"], first["posts"][-1]["id"])

        second = self.client.get(f"/menu/feed/?limit=3&cursor={first['nextCursor']}").json()
        self.assertEqual(len(second["posts"]), 3)
        # No overlap, strictly descending ids across pages.
        first_ids = {p["id"] for p in first["posts"]}
        second_ids = {p["id"] for p in second["posts"]}
        self.assertFalse(first_ids & second_ids)
        # Pinned posts ride along only on the first page.
        self.assertEqual(second["pinned"], [])

        third = self.client.get(f"/menu/feed/?limit=3&cursor={second['nextCursor']}").json()
        self.assertEqual(len(third["posts"]), 2)
        self.assertFalse(third["hasMore"])
        self.assertIsNone(third["nextCursor"])
        total = first_ids | second_ids | {p["id"] for p in third["posts"]}
        self.assertEqual(total, {post.pk for post in posts})

    def test_junk_cursor_and_limit_are_harmless(self):
        make_post(1)
        response = self.client.get("/menu/feed/?cursor=abc&limit=junk")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()["posts"]), 1)
