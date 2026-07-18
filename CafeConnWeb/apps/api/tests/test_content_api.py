import io
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core.models import Employee, SocialPost, VenueSettings

User = get_user_model()

INSTAGRAM_URL = "https://www.instagram.com/p/Cxyz{}/"


def make_client(username: str, role: str, **flags) -> tuple[APIClient, Employee]:
    # Seed migrations (0008/0012) create real staff accounts named manager /
    # admin / waiter / … — prefix test users so they can never collide.
    username = f"tst-{username}"
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    employee = Employee.objects.create(user=user, name=username, role=role, **flags)
    token, _ = Token.objects.get_or_create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client, employee


def create_post(client: APIClient, index: int = 1):
    return client.post("/api/staff/feed/", {"url": INSTAGRAM_URL.format(index)}, format="json")


class ContentPermissionTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_bootstrap_exposes_content_capability(self):
        client, _ = make_client("smm", Employee.Role.SMM)
        caps = client.get("/api/staff/bootstrap/").json()["currentUser"]["capabilities"]
        self.assertTrue(caps["content"])
        self.assertFalse(caps["wait"])
        self.assertFalse(caps["manage"])

    def test_smm_and_manager_can_use_feed_waiter_cannot(self):
        for username, role, expected in (
            ("smm", Employee.Role.SMM, 200),
            ("manager", Employee.Role.MANAGER, 200),
            ("admin", Employee.Role.ADMIN, 200),
            ("waiter", Employee.Role.WAITER, 403),
            ("kitchen", Employee.Role.KITCHEN, 403),
            ("bar", Employee.Role.BAR, 403),
        ):
            with self.subTest(role=role):
                client, _ = make_client(username, role)
                self.assertEqual(client.get("/api/staff/feed/").status_code, expected)
                self.assertEqual(client.get("/api/staff/venue/").status_code, expected)

    def test_waiter_with_granted_can_content_gets_access(self):
        client, _ = make_client("waiter2", Employee.Role.WAITER, can_content=True)
        self.assertEqual(client.get("/api/staff/feed/").status_code, 200)

    def test_anonymous_is_rejected(self):
        self.assertEqual(APIClient().get("/api/staff/feed/").status_code, 401)

    def test_smm_cannot_touch_orders_menu_or_staff(self):
        client, _ = make_client("smm", Employee.Role.SMM)
        # Menu writes need the menu capability.
        response = client.post(
            "/api/menu-items/",
            {"name": "X", "price": "1.00", "category": 1},
            format="json",
        )
        self.assertEqual(response.status_code, 403)
        # Staff management needs manage.
        self.assertEqual(client.get("/api/employees/").status_code, 403)
        # Analytics needs manager/admin.
        self.assertEqual(client.get("/api/staff/stats/").status_code, 403)


class FeedApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client_smm, self.employee = make_client("smm", Employee.Role.SMM)

    def test_create_from_valid_url(self):
        response = create_post(self.client_smm)
        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["platform"], "instagram")
        self.assertIn("instagram-media", payload["embed_html"])
        self.assertEqual(payload["created_by"], "tst-smm")
        self.assertEqual(SocialPost.objects.count(), 1)

    def test_foreign_domain_is_400_with_message(self):
        response = self.client_smm.post(
            "/api/staff/feed/", {"url": "https://tiktok.com/@x/video/1"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("not supported", response.json()["detail"])
        self.assertEqual(SocialPost.objects.count(), 0)

    def test_junk_url_is_400_with_message(self):
        response = self.client_smm.post("/api/staff/feed/", {"url": "junk"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertTrue(response.json()["detail"])

    def test_duplicate_url_is_400(self):
        create_post(self.client_smm)
        response = create_post(self.client_smm)
        self.assertEqual(response.status_code, 400)
        self.assertIn("already", response.json()["detail"])

    def test_twitter_create_never_blocks_on_oembed(self):
        with mock.patch("apps.core.social_embed._fetch_oembed", return_value=None):
            response = self.client_smm.post(
                "/api/staff/feed/", {"url": "https://x.com/sissi/status/1"}, format="json"
            )
        self.assertEqual(response.status_code, 201)
        self.assertIn("twitter-tweet", response.json()["embed_html"])

    def test_pin_limit_409_and_configurable(self):
        ids = [create_post(self.client_smm, i).json()["id"] for i in range(1, 5)]
        for post_id in ids[:3]:
            self.assertEqual(
                self.client_smm.post(f"/api/staff/feed/{post_id}/pin/").status_code, 200
            )
        # Default limit is 3 — the 4th pin conflicts with a clear message.
        response = self.client_smm.post(f"/api/staff/feed/{ids[3]}/pin/")
        self.assertEqual(response.status_code, 409)
        self.assertIn("Pinned limit", response.json()["detail"])

        # Raise the limit via the venue settings; the same pin now succeeds.
        patch = self.client_smm.patch(
            "/api/staff/venue/", {"pinned_posts_limit": 4}, format="json"
        )
        self.assertEqual(patch.status_code, 200)
        self.assertEqual(self.client_smm.post(f"/api/staff/feed/{ids[3]}/pin/").status_code, 200)

    def test_pinning_an_already_pinned_post_is_idempotent(self):
        post_id = create_post(self.client_smm).json()["id"]
        self.client_smm.post(f"/api/staff/feed/{post_id}/pin/")
        response = self.client_smm.post(f"/api/staff/feed/{post_id}/pin/")
        self.assertEqual(response.status_code, 200)

    def test_unpin_hide_delete(self):
        post_id = create_post(self.client_smm).json()["id"]
        self.client_smm.post(f"/api/staff/feed/{post_id}/pin/")
        self.assertEqual(
            self.client_smm.post(f"/api/staff/feed/{post_id}/unpin/").json()["is_pinned"], False
        )
        self.assertEqual(
            self.client_smm.post(f"/api/staff/feed/{post_id}/hide/").json()["is_hidden"], True
        )
        self.assertEqual(
            self.client_smm.post(f"/api/staff/feed/{post_id}/hide/").json()["is_hidden"], False
        )
        self.assertEqual(
            self.client_smm.delete(f"/api/staff/feed/{post_id}/").status_code, 204
        )
        self.assertEqual(SocialPost.objects.count(), 0)

    def test_list_orders_pinned_first(self):
        first = create_post(self.client_smm, 1).json()["id"]
        create_post(self.client_smm, 2)
        self.client_smm.post(f"/api/staff/feed/{first}/pin/")
        posts = self.client_smm.get("/api/staff/feed/").json()["posts"]
        self.assertTrue(posts[0]["is_pinned"])
        self.assertEqual(posts[0]["id"], first)


class VenueApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client_smm, _ = make_client("smm", Employee.Role.SMM)

    def test_get_returns_settings_and_presets(self):
        payload = self.client_smm.get("/api/staff/venue/").json()
        self.assertEqual(payload["venue"]["name"], "Caffè & Bistrò Sissi")
        self.assertEqual(payload["presets"][0]["key"], "sissi")
        self.assertEqual(payload["venue"]["color_accent"], "#c8821e")

    def test_patch_updates_and_bad_hex_is_400(self):
        ok = self.client_smm.patch(
            "/api/staff/venue/", {"color_accent": "#123ABC", "name": "New name"}, format="json"
        )
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(VenueSettings.get_solo().color_accent, "#123ABC")

        bad = self.client_smm.patch(
            "/api/staff/venue/", {"color_accent": "tomato"}, format="json"
        )
        self.assertEqual(bad.status_code, 400)
        self.assertIn("color_accent", bad.json())

    def test_patch_rejects_unknown_storefront_block(self):
        response = self.client_smm.patch(
            "/api/staff/venue/",
            {"storefront_blocks": [{"key": "hack", "visible": True}]},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_logo_upload_validates_and_resizes(self):
        from PIL import Image

        buffer = io.BytesIO()
        Image.new("RGB", (1200, 1200), "#c8821e").save(buffer, format="PNG")
        buffer.seek(0)
        buffer.name = "logo.png"
        response = self.client_smm.post(
            "/api/staff/venue/logo/", {"image": buffer}, format="multipart"
        )
        self.assertEqual(response.status_code, 200)
        settings = VenueSettings.get_solo()
        self.assertTrue(settings.logo)
        from PIL import Image as PILImage

        with settings.logo.open("rb") as stored:
            image = PILImage.open(stored)
            image.load()
        self.assertLessEqual(max(image.size), 512)
        # Cleanup the stored test file.
        settings.logo.delete(save=False)

    def test_logo_upload_rejects_non_image(self):
        not_an_image = io.BytesIO(b"definitely not pixels")
        not_an_image.name = "evil.png"
        response = self.client_smm.post(
            "/api/staff/venue/logo/", {"image": not_an_image}, format="multipart"
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(response.json()["detail"])

    def test_preview_token_roundtrip(self):
        response = self.client_smm.post(
            "/api/staff/venue/preview/", {"color_bg": "#101014"}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        token = response.json()["token"]
        self.assertTrue(token)

        page = self.client_smm.get(f"/menu/?preview={token}")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "--bg:#101014")
        # A draft never touches the saved settings.
        self.assertEqual(VenueSettings.get_solo().color_bg, "#f2efe8")

    def test_preview_rejects_invalid_draft(self):
        response = self.client_smm.post(
            "/api/staff/venue/preview/", {"color_bg": "junk"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
