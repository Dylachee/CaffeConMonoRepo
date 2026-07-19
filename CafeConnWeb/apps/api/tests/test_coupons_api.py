from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core import coupons
from apps.core.models import (
    CouponCampaign,
    Employee,
    GuestWallet,
    IssuedCoupon,
    MenuCategory,
    MenuItem,
    Order,
    OrderItem,
    Table,
)

User = get_user_model()


def make_client(username: str, role: str, **flags) -> tuple[APIClient, Employee]:
    username = f"tsta-{username}"
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    flags.setdefault("is_on_shift", True)
    employee = Employee.objects.create(user=user, name=username, role=role, **flags)
    token, _ = Token.objects.get_or_create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client, employee


def make_campaign(**overrides) -> CouponCampaign:
    defaults = dict(
        slug=f"api-camp-{CouponCampaign.objects.count() + 1}",
        title="Spritz hour",
        discount_type=CouponCampaign.DiscountType.PERCENT,
        discount_value=Decimal("10.00"),
    )
    defaults.update(overrides)
    return CouponCampaign.objects.create(**defaults)


def make_wallet_coupon(campaign, **kw):
    wallet = GuestWallet.objects.create()
    coupon, _ = coupons.claim_coupon(
        campaign, wallet, issued_via=IssuedCoupon.IssuedVia.CAMPAIGN_LINK, **kw
    )
    return wallet, coupon


def make_order(total: str = "30.00") -> Order:
    table, _ = Table.objects.get_or_create(number=991, defaults={"capacity": 2})
    category, _ = MenuCategory.objects.get_or_create(key="tsta-cat", defaults={"name": "T"})
    item, _ = MenuItem.objects.get_or_create(
        name="API coupon dish", defaults={"price": Decimal(total), "category": category}
    )
    order = Order.objects.create(table=table, status=Order.Status.NEW)
    OrderItem.objects.create(order=order, menu_item=item, quantity=1, unit_price=Decimal(total))
    return order


class CouponCapabilityMatrixTests(TestCase):
    def setUp(self):
        cache.clear()
        self.campaign = make_campaign()

    def test_issue_and_redeem_gated_on_discount(self):
        _, coupon = make_wallet_coupon(self.campaign)
        for username, role, flags, expected in (
            ("w-plain", Employee.Role.WAITER, {}, 403),
            ("w-disc", Employee.Role.WAITER, {"can_grant_discount": True}, 200),
            ("smm-plain", Employee.Role.SMM, {}, 403),
            ("kitchen", Employee.Role.KITCHEN, {}, 403),
            ("boss", Employee.Role.MANAGER, {}, 200),
        ):
            with self.subTest(user=username):
                client, _ = make_client(username, role, **flags)
                issue = client.post(
                    "/api/staff/coupons/issue/", {"campaign": self.campaign.pk}, format="json"
                )
                self.assertEqual(issue.status_code, expected)
                preview = client.post(
                    "/api/staff/coupons/redeem-preview/", {"code": coupon.code}, format="json"
                )
                self.assertEqual(preview.status_code, expected)

    def test_campaign_crud_gated_on_content(self):
        payload = {
            "title": "New campaign",
            "discount_type": "fixed",
            "discount_value": "5.00",
        }
        for username, role, flags, expected in (
            ("smm", Employee.Role.SMM, {}, 201),
            ("boss2", Employee.Role.MANAGER, {}, 201),
            ("w-disc2", Employee.Role.WAITER, {"can_grant_discount": True}, 403),
            ("w-plain2", Employee.Role.WAITER, {}, 403),
        ):
            with self.subTest(user=username):
                client, _ = make_client(username, role, **flags)
                response = client.post(
                    "/api/staff/coupons/campaigns/",
                    {**payload, "title": f"{payload['title']} {username}"},
                    format="json",
                )
                self.assertEqual(response.status_code, expected)

    def test_smm_cannot_redeem_without_flag_but_can_with_it(self):
        _, coupon = make_wallet_coupon(self.campaign)
        smm_plain, _ = make_client("smm-r", Employee.Role.SMM)
        self.assertEqual(
            smm_plain.post(
                "/api/staff/coupons/redeem/", {"code": coupon.code}, format="json"
            ).status_code,
            403,
        )
        smm_disc, _ = make_client("smm-rd", Employee.Role.SMM, can_grant_discount=True)
        order = make_order()
        self.assertEqual(
            smm_disc.post(
                "/api/staff/coupons/redeem/", {"code": coupon.code, "order_id": order.pk}, format="json"
            ).status_code,
            200,
        )

    def test_void_is_manager_only(self):
        _, coupon = make_wallet_coupon(self.campaign)
        waiter, employee = make_client("w-void", Employee.Role.WAITER, can_grant_discount=True)
        order = make_order()
        waiter.post("/api/staff/coupons/redeem/", {"code": coupon.code, "order_id": order.pk}, format="json")
        self.assertEqual(
            waiter.post(f"/api/staff/coupons/{coupon.pk}/void-redemption/").status_code, 403
        )
        manager, _ = make_client("m-void", Employee.Role.MANAGER)
        order.status = Order.Status.CANCELLED
        order.save(update_fields=["status"])
        response = manager.post(f"/api/staff/coupons/{coupon.pk}/void-redemption/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["coupon"]["status"], "active")

    def test_bootstrap_exposes_discount_capability(self):
        client, _ = make_client("w-boot", Employee.Role.WAITER, can_grant_discount=True)
        caps = client.get("/api/staff/bootstrap/").json()["currentUser"]["capabilities"]
        self.assertTrue(caps["discount"])
        client2, _ = make_client("w-boot2", Employee.Role.WAITER)
        caps2 = client2.get("/api/staff/bootstrap/").json()["currentUser"]["capabilities"]
        self.assertFalse(caps2["discount"])


class CampaignApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client_smm, _ = make_client("smm-c", Employee.Role.SMM)

    def test_create_autogenerates_slug_and_validates(self):
        response = self.client_smm.post(
            "/api/staff/coupons/campaigns/",
            {"title": "Ferragosto −20%", "discount_type": "percent", "discount_value": "20"},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertTrue(response.json()["slug"])

        bad = self.client_smm.post(
            "/api/staff/coupons/campaigns/",
            {"title": "x", "discount_type": "percent", "discount_value": "150"},
            format="json",
        )
        self.assertEqual(bad.status_code, 400)
        self.assertIn("discount_value", bad.json())

    def test_counters_and_utm_breakdown(self):
        campaign = make_campaign(per_wallet_limit=1)
        w1, c1 = make_wallet_coupon(campaign, utm_source="instagram_bio")
        w2, c2 = make_wallet_coupon(campaign, utm_source="instagram_bio")
        w3, c3 = make_wallet_coupon(campaign, utm_source="flyer")
        staff, employee = make_client("m-stats", Employee.Role.MANAGER)
        coupons.redeem_coupon(c1.pk, redeemed_by=employee, order=make_order())

        payload = self.client_smm.get("/api/staff/coupons/campaigns/").json()["campaigns"]
        row = next(c for c in payload if c["id"] == campaign.pk)
        self.assertEqual(row["issued_count"], 3)
        self.assertEqual(row["redeemed_count"], 1)
        by_utm = {entry["utm_source"]: entry for entry in row["by_utm"]}
        self.assertEqual(by_utm["instagram_bio"]["issued"], 2)
        self.assertEqual(by_utm["instagram_bio"]["redeemed"], 1)
        self.assertEqual(by_utm["flyer"]["issued"], 1)

    def test_delete_with_coupons_deactivates(self):
        campaign = make_campaign()
        make_wallet_coupon(campaign)
        response = self.client_smm.delete(f"/api/staff/coupons/campaigns/{campaign.pk}/")
        self.assertEqual(response.status_code, 200)
        campaign.refresh_from_db()
        self.assertFalse(campaign.is_active)
        self.assertIn("deactivated", response.json()["detail"])

        empty = make_campaign()
        self.assertEqual(
            self.client_smm.delete(f"/api/staff/coupons/campaigns/{empty.pk}/").status_code,
            204,
        )


class IssueRedeemApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.campaign = make_campaign(discount_value=Decimal("10.00"))
        self.client_w, self.employee = make_client(
            "w-ir", Employee.Role.WAITER, can_grant_discount=True
        )

    def test_issue_returns_claim_url_with_valid_token(self):
        response = self.client_w.post(
            "/api/staff/coupons/issue/", {"campaign": self.campaign.pk}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertIn("/r/sissy-bar/?claim=", body["claimUrl"])
        payload = coupons.parse_claim_token(body["token"])
        self.assertEqual(payload["campaign"], self.campaign.pk)
        self.assertEqual(payload["employee"], self.employee.pk)

    def test_issue_refuses_inactive_campaign(self):
        self.campaign.is_active = False
        self.campaign.save(update_fields=["is_active"])
        response = self.client_w.post(
            "/api/staff/coupons/issue/", {"campaign": self.campaign.pk}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(response.json()["detail"])

    def test_preview_by_token_and_by_code(self):
        _, coupon = make_wallet_coupon(self.campaign)
        token = coupons.make_redeem_token(coupon)
        by_token = self.client_w.post(
            "/api/staff/coupons/redeem-preview/", {"token": token}, format="json"
        )
        self.assertEqual(by_token.status_code, 200)
        self.assertEqual(by_token.json()["coupon"]["code"], coupon.code)
        self.assertEqual(by_token.json()["displayStatus"], "active")

        order = make_order("30.00")
        by_code = self.client_w.post(
            "/api/staff/coupons/redeem-preview/",
            {"code": coupon.code.lower(), "order_id": order.pk},
            format="json",
        )
        self.assertEqual(by_code.status_code, 200)
        self.assertEqual(by_code.json()["discountPreview"], "3.00")

    def test_tampered_redeem_token_rejected(self):
        _, coupon = make_wallet_coupon(self.campaign)
        token = coupons.make_redeem_token(coupon)
        response = self.client_w.post(
            "/api/staff/coupons/redeem-preview/", {"token": token[:-2] + "zz"}, format="json"
        )
        self.assertEqual(response.status_code, 400)

    def test_redeem_with_order_applies_discount_line(self):
        _, coupon = make_wallet_coupon(self.campaign)
        order = make_order("30.00")
        response = self.client_w.post(
            "/api/staff/coupons/redeem/",
            {"token": coupons.make_redeem_token(coupon), "order_id": order.pk},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["coupon"]["status"], "redeemed")
        self.assertEqual(body["order"]["discount_amount"], "3.00")
        self.assertEqual(body["order"]["coupon_code"], coupon.code)
        self.assertEqual(body["order"]["total_due"], "27.00")

    def test_second_redeem_is_conflict_with_message(self):
        _, coupon = make_wallet_coupon(self.campaign)
        order = make_order()
        self.client_w.post("/api/staff/coupons/redeem/", {"code": coupon.code, "order_id": order.pk}, format="json")
        response = self.client_w.post(
            "/api/staff/coupons/redeem/", {"code": coupon.code, "order_id": order.pk}, format="json"
        )
        self.assertEqual(response.status_code, 409)
        self.assertIn("already been used", response.json()["detail"])

    def test_unknown_code_is_400(self):
        response = self.client_w.post(
            "/api/staff/coupons/redeem/", {"code": "ZZZZZZZZ"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(response.json()["detail"])
