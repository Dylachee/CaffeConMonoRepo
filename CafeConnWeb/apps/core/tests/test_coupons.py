import threading
import time
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.db import DatabaseError, connections
from django.test import TestCase, TransactionTestCase
from django.utils import timezone

from apps.core import coupons
from apps.core.coupons import CouponError
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


def make_employee(username: str, role: str = Employee.Role.WAITER, **flags) -> Employee:
    flags.setdefault("is_on_shift", True)
    user = User.objects.create_user(username=f"tstc-{username}", password="x-test-pass-1")
    return Employee.objects.create(user=user, name=username, role=role, **flags)


def make_campaign(**overrides) -> CouponCampaign:
    defaults = dict(
        slug=overrides.pop("slug", f"camp-{CouponCampaign.objects.count() + 1}"),
        title="Aperitivo −15%",
        title_it="Aperitivo −15%",
        discount_type=CouponCampaign.DiscountType.PERCENT,
        discount_value=Decimal("15.00"),
    )
    defaults.update(overrides)
    return CouponCampaign.objects.create(**defaults)


def make_order(total: str = "20.00") -> Order:
    table, _ = Table.objects.get_or_create(number=990, defaults={"capacity": 2})
    category, _ = MenuCategory.objects.get_or_create(key="tstc-cat", defaults={"name": "Test"})
    item, _ = MenuItem.objects.get_or_create(
        name="Coupon test dish",
        defaults={"price": Decimal(total), "category": category},
    )
    order = Order.objects.create(table=table, status=Order.Status.NEW)
    OrderItem.objects.create(order=order, menu_item=item, quantity=1, unit_price=Decimal(total))
    return order


def claim(campaign, wallet, **kw):
    kw.setdefault("issued_via", IssuedCoupon.IssuedVia.CAMPAIGN_LINK)
    return coupons.claim_coupon(campaign, wallet, **kw)


class SignedTokenTests(TestCase):
    def setUp(self):
        self.campaign = make_campaign()
        self.wallet = GuestWallet.objects.create()

    def test_claim_token_roundtrip(self):
        staff = make_employee("waiter1")
        token = coupons.make_claim_token(self.campaign, staff)
        payload = coupons.parse_claim_token(token)
        self.assertEqual(payload["campaign"], self.campaign.pk)
        self.assertEqual(payload["employee"], staff.pk)

    def test_redeem_token_roundtrip(self):
        coupon, _ = claim(self.campaign, self.wallet)
        payload = coupons.parse_redeem_token(coupons.make_redeem_token(coupon))
        self.assertEqual(payload["coupon"], coupon.pk)
        self.assertEqual(payload["code"], coupon.code)

    def test_recovery_token_roundtrip(self):
        token = coupons.make_recovery_token(self.wallet)
        self.assertEqual(coupons.parse_recovery_token(token), str(self.wallet.pk))

    def test_wallet_cookie_roundtrip(self):
        value = coupons.make_wallet_cookie(self.wallet)
        self.assertEqual(coupons.parse_wallet_cookie(value), str(self.wallet.pk))
        self.assertIsNone(coupons.parse_wallet_cookie(value + "x"))
        self.assertIsNone(coupons.parse_wallet_cookie("garbage"))

    def test_tampered_tokens_rejected(self):
        claim_token = coupons.make_claim_token(self.campaign, None)
        coupon, _ = claim(self.campaign, self.wallet)
        redeem_token = coupons.make_redeem_token(coupon)
        recovery_token = coupons.make_recovery_token(self.wallet)
        for parse, token in (
            (coupons.parse_claim_token, claim_token[:-2] + "zz"),
            (coupons.parse_redeem_token, redeem_token[:-2] + "zz"),
            (coupons.parse_recovery_token, recovery_token[:-2] + "zz"),
            (coupons.parse_claim_token, ""),
        ):
            with self.subTest(token=token[:24]):
                with self.assertRaises(CouponError):
                    parse(token)

    def test_salts_are_not_interchangeable(self):
        # A claim token must never pass as a redeem token and vice versa.
        claim_token = coupons.make_claim_token(self.campaign, None)
        with self.assertRaises(CouponError):
            coupons.parse_redeem_token(claim_token)
        coupon, _ = claim(self.campaign, self.wallet)
        with self.assertRaises(CouponError):
            coupons.parse_claim_token(coupons.make_redeem_token(coupon))

    def test_claim_token_expires(self):
        token = coupons.make_claim_token(self.campaign, None)
        real_time = coupons.signing.time.time()
        with mock.patch(
            "django.core.signing.time.time",
            return_value=real_time + coupons.CLAIM_TOKEN_TTL + 5,
        ):
            with self.assertRaises(CouponError) as ctx:
                coupons.parse_claim_token(token)
        self.assertIn("expired", str(ctx.exception))

    def test_qr_svg_renders(self):
        svg = coupons.qr_svg("https://example.com/menu/?claim=abc")
        self.assertTrue(svg.startswith("<svg"))
        self.assertIn("path", svg)


class ClaimCouponTests(TestCase):
    def setUp(self):
        self.campaign = make_campaign()
        self.wallet = GuestWallet.objects.create()

    def test_claim_creates_coupon_with_code_and_utm(self):
        coupon, created = claim(self.campaign, self.wallet, utm_source="instagram_bio")
        self.assertTrue(created)
        self.assertEqual(coupon.status, IssuedCoupon.Status.ACTIVE)
        self.assertEqual(coupon.utm_source, "instagram_bio")
        self.assertEqual(len(coupon.code), coupons.CODE_LENGTH)
        self.assertTrue(set(coupon.code) <= set(coupons.CODE_ALPHABET))

    def test_claim_is_idempotent_per_wallet(self):
        first, created_first = claim(self.campaign, self.wallet)
        second, created_second = claim(self.campaign, self.wallet)
        self.assertTrue(created_first)
        self.assertFalse(created_second)
        self.assertEqual(first.pk, second.pk)
        self.assertEqual(IssuedCoupon.objects.count(), 1)

    def test_one_coupon_per_campaign_even_if_legacy_limit_is_higher(self):
        campaign = make_campaign(per_wallet_limit=2)
        _, c1 = claim(campaign, self.wallet)
        _, c2 = claim(campaign, self.wallet)
        _, c3 = claim(campaign, self.wallet)
        self.assertEqual([c1, c2, c3], [True, False, False])
        self.assertEqual(IssuedCoupon.objects.filter(campaign=campaign).count(), 1)

    def test_max_total_issues_enforced(self):
        campaign = make_campaign(max_total_issues=1)
        claim(campaign, self.wallet)
        with self.assertRaises(CouponError) as ctx:
            claim(campaign, GuestWallet.objects.create())
        self.assertIn("fully claimed", str(ctx.exception))

    def test_window_and_active_guards(self):
        now = timezone.now()
        cases = {
            "inactive": make_campaign(is_active=False),
            "pending": make_campaign(valid_from=now + timedelta(days=1)),
            "expired": make_campaign(valid_until=now - timedelta(days=1)),
        }
        for label, campaign in cases.items():
            with self.subTest(label=label):
                with self.assertRaises(CouponError):
                    claim(campaign, self.wallet)

    def test_staff_issue_records_employee_and_channel(self):
        staff = make_employee("waiter2", can_grant_discount=True)
        coupon, _ = claim(
            self.campaign,
            self.wallet,
            issued_via=IssuedCoupon.IssuedVia.STAFF_QR,
            issued_by=staff,
        )
        self.assertEqual(coupon.issued_via, IssuedCoupon.IssuedVia.STAFF_QR)
        self.assertEqual(coupon.issued_by, staff)


class ComputeDiscountTests(TestCase):
    def test_percent(self):
        campaign = make_campaign(discount_value=Decimal("15.00"))
        self.assertEqual(coupons.compute_discount(campaign, Decimal("20.00")), Decimal("3.00"))

    def test_percent_rounds_to_cents(self):
        campaign = make_campaign(discount_value=Decimal("10.00"))
        self.assertEqual(coupons.compute_discount(campaign, Decimal("9.99")), Decimal("1.00"))

    def test_fixed(self):
        campaign = make_campaign(
            discount_type=CouponCampaign.DiscountType.FIXED,
            discount_value=Decimal("5.00"),
        )
        self.assertEqual(coupons.compute_discount(campaign, Decimal("20.00")), Decimal("5.00"))

    def test_fixed_caps_at_total(self):
        campaign = make_campaign(
            discount_type=CouponCampaign.DiscountType.FIXED,
            discount_value=Decimal("50.00"),
        )
        self.assertEqual(coupons.compute_discount(campaign, Decimal("12.40")), Decimal("12.40"))

    def test_zero_or_negative_total_never_negative(self):
        campaign = make_campaign(
            discount_type=CouponCampaign.DiscountType.FIXED,
            discount_value=Decimal("5.00"),
        )
        self.assertEqual(coupons.compute_discount(campaign, Decimal("0.00")), Decimal("0.00"))
        self.assertEqual(coupons.compute_discount(campaign, Decimal("-3.00")), Decimal("0.00"))


class RedeemCouponTests(TestCase):
    def setUp(self):
        self.campaign = make_campaign()  # 15 %
        self.wallet = GuestWallet.objects.create()
        self.staff = make_employee("redeemer", can_grant_discount=True)
        self.coupon, _ = claim(self.campaign, self.wallet)

    def test_redeem_with_order_snapshots_discount(self):
        order = make_order("20.00")
        coupon = coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)
        order.refresh_from_db()
        self.assertEqual(coupon.status, IssuedCoupon.Status.REDEEMED)
        self.assertEqual(coupon.redeemed_by, self.staff)
        self.assertEqual(coupon.order, order)
        self.assertEqual(order.coupon, coupon)
        self.assertEqual(order.discount_amount, Decimal("3.00"))
        self.assertEqual(order.total_due, Decimal("17.00"))

    def test_snapshot_immutable_after_cart_grows(self):
        order = make_order("20.00")
        coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)
        OrderItem.objects.create(
            order=order,
            menu_item=MenuItem.objects.get(name="Coupon test dish"),
            quantity=1,
            unit_price=Decimal("80.00"),
        )
        order.refresh_from_db()
        self.assertEqual(order.total, Decimal("100.00"))
        # The snapshot deliberately stays what it was at redemption.
        self.assertEqual(order.discount_amount, Decimal("3.00"))

    def test_double_redeem_rejected(self):
        order = make_order()
        coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)
        with self.assertRaises(CouponError) as ctx:
            coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)
        self.assertIn("already been used", str(ctx.exception))

    def test_void_and_expired_rejected(self):
        self.coupon.status = IssuedCoupon.Status.VOID
        self.coupon.save(update_fields=["status"])
        with self.assertRaises(CouponError):
            coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=make_order())

        expired_campaign = make_campaign(valid_until=timezone.now() + timedelta(days=1))
        coupon, _ = claim(expired_campaign, self.wallet)
        coupon.valid_until_snapshot = timezone.now() - timedelta(minutes=1)
        coupon.save(update_fields=["valid_until_snapshot"])
        with self.assertRaises(CouponError) as ctx:
            coupons.redeem_coupon(coupon.pk, redeemed_by=self.staff, order=make_order())
        self.assertIn("expired", str(ctx.exception))
        coupon.refresh_from_db()
        self.assertEqual(coupon.status, IssuedCoupon.Status.EXPIRED)

    def test_closed_order_rejected(self):
        order = make_order()
        order.status = Order.Status.CANCELLED
        order.save(update_fields=["status"])
        with self.assertRaises(CouponError):
            coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)

    def test_order_cannot_take_two_coupons(self):
        order = make_order()
        coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)
        other, _ = claim(make_campaign(), self.wallet)
        with self.assertRaises(CouponError) as ctx:
            coupons.redeem_coupon(other.pk, redeemed_by=self.staff, order=order)
        self.assertIn("already has a coupon", str(ctx.exception))

    def test_void_redemption_manager_flow(self):
        order = make_order()
        coupons.redeem_coupon(self.coupon.pk, redeemed_by=self.staff, order=order)

        # Not cancelled yet -> refused.
        with self.assertRaises(CouponError):
            coupons.void_redemption(self.coupon)

        order.status = Order.Status.CANCELLED
        order.save(update_fields=["status"])
        coupon = coupons.void_redemption(self.coupon)
        order.refresh_from_db()
        self.assertEqual(coupon.status, IssuedCoupon.Status.ACTIVE)
        self.assertIsNone(coupon.order)
        self.assertIsNone(coupon.redeemed_at)
        self.assertIsNone(order.coupon)
        self.assertIsNone(order.discount_amount)

    def test_display_status_shows_expired_campaign(self):
        self.assertEqual(coupons.display_status(self.coupon), "active")
        self.coupon.valid_until_snapshot = timezone.now() - timedelta(minutes=1)
        self.coupon.save(update_fields=["valid_until_snapshot"])
        self.coupon.refresh_from_db()
        self.assertEqual(coupons.display_status(self.coupon), "expired")


class ConcurrentRedeemTests(TransactionTestCase):
    """Two simultaneous scans of one coupon must never both succeed.

    On Postgres select_for_update serializes the transactions; on SQLite the
    compare-and-swap UPDATE is the guard. Either way, exactly one caller wins
    and exactly one redemption is recorded.
    """

    def test_concurrent_double_redeem_single_use(self):
        campaign = make_campaign()
        wallet = GuestWallet.objects.create()
        staff = make_employee("racer", can_grant_discount=True)
        coupon, _ = claim(campaign, wallet)
        order = make_order()

        barrier = threading.Barrier(2, timeout=10)
        results: list[str] = []
        lock = threading.Lock()

        def scan():
            outcome = "db-error"
            try:
                barrier.wait()
                # SQLite (shared-cache test DB) may bounce a contender with
                # "database is locked" instead of queueing it like Postgres.
                # Retrying keeps the test meaningful on both engines: the
                # CAS/row-lock still guarantees AT MOST one winner, and the
                # retry guarantees AT LEAST one scan reaches a real verdict —
                # a retry after the winner committed gets "already been used".
                for attempt in range(4):
                    try:
                        coupons.redeem_coupon(coupon.pk, redeemed_by=staff, order=order)
                        outcome = "redeemed"
                        break
                    except CouponError:
                        outcome = "coupon-error"
                        break
                    except DatabaseError:
                        time.sleep(0.05 * (attempt + 1))
            finally:
                for conn in connections.all():
                    conn.close()
            with lock:
                results.append(outcome)

        threads = [threading.Thread(target=scan) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=20)

        self.assertEqual(len(results), 2, f"threads did not finish: {results}")
        self.assertEqual(
            results.count("redeemed"), 1, f"exactly one scan must win, got {results}"
        )
        coupon.refresh_from_db()
        self.assertEqual(coupon.status, IssuedCoupon.Status.REDEEMED)


class DiscountCapabilityTests(TestCase):
    def test_discount_capability_matrix(self):
        cases = [
            (make_employee("w-plain"), False),
            (make_employee("w-granted", can_grant_discount=True), True),
            (make_employee("smm-plain", role=Employee.Role.SMM), False),
            (make_employee("smm-granted", role=Employee.Role.SMM, can_grant_discount=True), True),
            (make_employee("boss", role=Employee.Role.MANAGER), True),
            (make_employee("owner", role=Employee.Role.ADMIN), True),
        ]
        for employee, expected in cases:
            with self.subTest(employee=employee.name):
                self.assertEqual(employee.capabilities["discount"], expected)
