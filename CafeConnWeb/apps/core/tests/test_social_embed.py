from unittest import mock

from django.test import SimpleTestCase

from apps.core.social_embed import (
    SocialEmbedError,
    build_embed,
    detect_platform,
    domain_for_display,
)


class DetectPlatformTests(SimpleTestCase):
    def test_detects_each_platform(self):
        cases = {
            "https://www.instagram.com/p/Cxyz123/": "instagram",
            "https://instagram.com/reel/Cxyz123/": "instagram",
            "https://www.threads.net/@sissi/post/Cxyz": "threads",
            "https://www.threads.com/@sissi/post/Cxyz": "threads",
            "https://x.com/sissi/status/1234567890": "twitter_x",
            "https://twitter.com/sissi/status/1234567890": "twitter_x",
            "https://www.facebook.com/sissi/posts/pfbid0xyz": "facebook",
            "https://fb.watch/abc123/": "facebook",
        }
        for url, expected in cases.items():
            with self.subTest(url=url):
                platform, normalized = detect_platform(url)
                self.assertEqual(platform, expected)
                self.assertTrue(normalized.startswith("https://"))

    def test_foreign_domain_rejected(self):
        for url in (
            "https://example.com/p/123",
            "https://tiktok.com/@x/video/1",
            # Lookalikes must not pass the whitelist.
            "https://instagram.com.evil.io/p/123",
            "https://notinstagram.com/p/123",
        ):
            with self.subTest(url=url):
                with self.assertRaises(SocialEmbedError):
                    detect_platform(url)

    def test_junk_rejected_with_message(self):
        for url in ("", "not a url", "ftp://instagram.com/p/1", "javascript:alert(1)"):
            with self.subTest(url=url):
                with self.assertRaises(SocialEmbedError) as ctx:
                    detect_platform(url)
                self.assertTrue(str(ctx.exception))  # human-readable, never empty

    def test_profile_link_without_post_path_rejected(self):
        with self.assertRaises(SocialEmbedError):
            detect_platform("https://www.instagram.com/")

    def test_fragment_dropped_query_kept(self):
        _, normalized = detect_platform(
            "https://www.facebook.com/permalink.php?story_fbid=1&id=2#comment"
        )
        self.assertEqual(
            normalized, "https://www.facebook.com/permalink.php?story_fbid=1&id=2"
        )


class BuildEmbedTests(SimpleTestCase):
    def test_instagram_blockquote_without_token(self):
        html = build_embed("instagram", "https://www.instagram.com/p/Cxyz123/")
        self.assertIn('class="instagram-media"', html)
        self.assertIn('data-instgrm-permalink="https://www.instagram.com/p/Cxyz123/"', html)
        self.assertNotIn("<script", html)

    def test_threads_blockquote(self):
        html = build_embed("threads", "https://www.threads.net/@sissi/post/Cxyz")
        self.assertIn('class="text-post-media"', html)
        self.assertNotIn("<script", html)

    def test_facebook_post_and_video_markup(self):
        post = build_embed("facebook", "https://www.facebook.com/sissi/posts/123")
        video = build_embed("facebook", "https://www.facebook.com/sissi/videos/123/")
        self.assertIn('class="fb-post"', post)
        self.assertIn('class="fb-video"', video)

    def test_twitter_falls_back_to_blockquote_when_oembed_unreachable(self):
        with mock.patch("apps.core.social_embed._fetch_oembed", return_value=None):
            html = build_embed("twitter_x", "https://x.com/sissi/status/1")
        self.assertIn('class="twitter-tweet"', html)
        self.assertIn('href="https://x.com/sissi/status/1"', html)
        self.assertNotIn("<script", html)

    def test_twitter_uses_oembed_html_when_available(self):
        with mock.patch(
            "apps.core.social_embed._fetch_oembed",
            return_value='<blockquote class="twitter-tweet"><p>hi</p></blockquote>',
        ):
            html = build_embed("twitter_x", "https://x.com/sissi/status/1")
        self.assertIn("twitter-tweet", html)
        self.assertIn("<p>hi</p>", html)
        self.assertNotIn("<script", html)

    def test_strip_scripts_removes_provider_script_tags(self):
        from apps.core.social_embed import _strip_scripts

        html = (
            '<blockquote class="twitter-tweet"><p>hi</p></blockquote>\n'
            '<script async src="https://platform.twitter.com/widgets.js"></script>'
        )
        stripped = _strip_scripts(html)
        self.assertIn("twitter-tweet", stripped)
        self.assertNotIn("<script", stripped)

    def test_embed_escapes_url(self):
        # A URL that survives validation must still land escaped in markup.
        platform, url = detect_platform(
            'https://www.facebook.com/permalink.php?story_fbid=1&id="><img>'
        )
        html = build_embed(platform, url)
        self.assertNotIn('"><img>', html)

    def test_domain_for_display(self):
        self.assertEqual(domain_for_display("https://www.instagram.com/p/1/"), "instagram.com")
        self.assertEqual(domain_for_display("https://x.com/a/status/1"), "x.com")
