from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase

from apps.core import coupons
from apps.core.models import CouponCampaign, GuestWallet, IssuedCoupon, MenuCategory, MenuItem, Order, OrderItem, Table

WALLET_COOKIE = "cc_wallet"


def make_campaign(**overrides) -> CouponCampaign:
    defaults = dict(
        slug=f"guest-camp-{CouponCampaign.objects.count() + 1}",
        title="Welcome −10%",
        title_it="Benvenuto −10%",
        discount_type=CouponCampaign.DiscountType.PERCENT,
        discount_value=Decimal("10.00"),
    )
    defaults.update(overrides)
    return CouponCampaign.objects.create(**defaults)


class GuestClaimFlowTests(TestCase):
    def setUp(self):
        cache.clear()
        self.campaign = make_campaign(slug="welcome")

    def test_menu_page_sets_no_cookies_for_ordinary_guests(self):
        response = self.client.get("/r/sissy-bar/")
        self.assertNotIn(WALLET_COOKIE, response.cookies)
        self.assertNotIn("sessionid", response.cookies)

    def test_menu_page_has_wallet_tab_and_screen(self):
        html = self.client.get("/r/sissy-bar/").content.decode()
        self.assertIn('data-testid="nav-wallet"', html)
        self.assertIn('data-screen="wallet"', html)
        self.assertIn('data-testid="wallet-list"', html)
        self.assertIn('data-testid="wallet-empty"', html)
        # Four focused tabs: home, menu, coupons, and service.
        self.assertEqual(html.count('class="tab'), 4)

    def test_wallet_read_never_creates_a_wallet(self):
        response = self.client.get("/r/sissy-bar/wallet/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"ok": True, "hasWallet": False, "coupons": []})
        self.assertNotIn(WALLET_COOKIE, response.cookies)
        self.assertEqual(GuestWallet.objects.count(), 0)

    def test_campaign_link_claim_sets_cookie_and_records_utm(self):
        response = self.client.post(
            "/r/sissy-bar/wallet/claim/", {"campaign": "welcome", "utm_source": "instagram_bio"}
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["ok"])
        self.assertTrue(body["created"])
        self.assertEqual(body["coupon"]["title"], "Welcome −10%")
        self.assertIn("qrSvg", body["coupon"])
        self.assertIn(WALLET_COOKIE, response.cookies)
        cookie = response.cookies[WALLET_COOKIE]
        self.assertTrue(cookie["httponly"])
        self.assertEqual(cookie["samesite"], "Lax")

        coupon = IssuedCoupon.objects.get()
        self.assertEqual(coupon.utm_source, "instagram_bio")
        self.assertEqual(coupon.issued_via, IssuedCoupon.IssuedVia.CAMPAIGN_LINK)

    def test_claim_is_idempotent_for_the_same_browser(self):
        first = self.client.post("/r/sissy-bar/wallet/claim/", {"campaign": "welcome"})
        self.assertTrue(first.json()["created"])
        # The test client carries cookies over — same wallet, same coupon.
        second = self.client.post("/r/sissy-bar/wallet/claim/", {"campaign": "welcome"})
        self.assertFalse(second.json()["created"])
        self.assertEqual(IssuedCoupon.objects.count(), 1)
        self.assertEqual(GuestWallet.objects.count(), 1)

    def test_staff_token_claim(self):
        token = coupons.make_claim_token(self.campaign, None)
        response = self.client.post("/r/sissy-bar/wallet/claim/", {"claim": token})
        self.assertEqual(response.status_code, 200)
        coupon = IssuedCoupon.objects.get()
        self.assertEqual(coupon.issued_via, IssuedCoupon.IssuedVia.STAFF_QR)

    def test_bad_claims_get_clear_errors(self):
        cases = {
            "tampered token": {"claim": "obviously-not-a-token"},
            "unknown campaign": {"campaign": "no-such-campaign"},
            "nothing at all": {},
        }
        for label, payload in cases.items():
            with self.subTest(label=label):
                response = self.client.post("/r/sissy-bar/wallet/claim/", payload)
                self.assertEqual(response.status_code, 400)
                self.assertTrue(response.json()["error"])

    def test_exhausted_campaign_claim_is_clear_error(self):
        campaign = make_campaign(slug="tiny", max_total_issues=1)
        self.client.post("/r/sissy-bar/wallet/claim/", {"campaign": "tiny"})
        # A different browser (fresh client, no cookie).
        other = self.client_class()
        response = other.post("/r/sissy-bar/wallet/claim/", {"campaign": "tiny"})
        self.assertEqual(response.status_code, 400)
        self.assertIn("fully claimed", response.json()["error"])

    def test_wallet_lists_coupons_and_recovery(self):
        self.client.post("/r/sissy-bar/wallet/claim/", {"campaign": "welcome"})
        response = self.client.get("/r/sissy-bar/wallet/")
        body = response.json()
        self.assertTrue(body["hasWallet"])
        self.assertEqual(len(body["coupons"]), 1)
        coupon = body["coupons"][0]
        self.assertEqual(coupon["status"], "active")
        self.assertTrue(coupon["qrSvg"].startswith("<svg"))
        self.assertIn("/r/sissy-bar/wallet/recover/", body["recovery"]["url"])
        self.assertTrue(body["recovery"]["qrSvg"].startswith("<svg"))

    def test_recovery_link_reattaches_wallet_on_new_device(self):
        self.client.post("/r/sissy-bar/wallet/claim/", {"campaign": "welcome"})
        wallet = GuestWallet.objects.get()
        token = coupons.make_recovery_token(wallet)

        new_device = self.client_class()
        response = new_device.get(f"/r/sissy-bar/wallet/recover/{token}/")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, "/r/sissy-bar/?wallet=1")
        self.assertIn(WALLET_COOKIE, response.cookies)
        listing = new_device.get("/r/sissy-bar/wallet/").json()
        self.assertEqual(len(listing["coupons"]), 1)

    def test_invalid_recovery_token_redirects_with_error(self):
        response = self.client.get("/r/sissy-bar/wallet/recover/garbage/")
        self.assertEqual(response.url, "/r/sissy-bar/?wallet=invalid")
        self.assertNotIn(WALLET_COOKIE, response.cookies)

    def test_redeemed_coupon_shows_as_used_without_qr(self):
        self.client.post("/r/sissy-bar/wallet/claim/", {"campaign": "welcome"})
        coupon = IssuedCoupon.objects.get()
        table = Table.objects.create(number=899, capacity=2)
        category = MenuCategory.objects.create(key="wallet-test", name="Wallet test")
        item = MenuItem.objects.create(name="Wallet dish", price=Decimal("10.00"), category=category)
        order = Order.objects.create(table=table, status=Order.Status.NEW)
        OrderItem.objects.create(order=order, menu_item=item, quantity=1, unit_price=Decimal("10.00"))
        coupons.redeem_coupon(coupon.pk, redeemed_by=None, order=order)
        listing = self.client.get("/r/sissy-bar/wallet/").json()
        entry = listing["coupons"][0]
        self.assertEqual(entry["status"], "redeemed")
        self.assertNotIn("qrSvg", entry)
