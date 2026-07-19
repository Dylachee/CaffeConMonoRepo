from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.core import coupons
from apps.core.coupons import CouponError
from apps.core.models import CouponCampaign, GuestWallet, IssuedCoupon, Order, Table

User = get_user_model()


def make_campaign(**overrides) -> CouponCampaign:
    defaults = dict(
        slug=f"merge-camp-{CouponCampaign.objects.count() + 1}",
        title="Merge test",
        discount_type=CouponCampaign.DiscountType.PERCENT,
        discount_value=Decimal("10.00"),
    )
    defaults.update(overrides)
    return CouponCampaign.objects.create(**defaults)


def claim(campaign, wallet):
    coupon, _ = coupons.claim_coupon(
        campaign, wallet, issued_via=IssuedCoupon.IssuedVia.CAMPAIGN_LINK
    )
    return coupon


class AttachWalletTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="tstm-guest", password="x-test-pass-1")
        self.wallet = GuestWallet.objects.create()

    def test_attach_binds_wallet_to_user(self):
        wallet = coupons.attach_wallet_to_user(self.wallet, self.user)
        self.assertEqual(wallet.user, self.user)

    def test_attach_is_idempotent_for_same_user(self):
        coupons.attach_wallet_to_user(self.wallet, self.user)
        wallet = coupons.attach_wallet_to_user(self.wallet, self.user)
        self.assertEqual(wallet.user, self.user)

    def test_attach_refuses_wallet_of_another_account(self):
        other = User.objects.create_user(username="tstm-other", password="x-test-pass-1")
        coupons.attach_wallet_to_user(self.wallet, self.user)
        with self.assertRaises(CouponError):
            coupons.attach_wallet_to_user(self.wallet, other)
        self.wallet.refresh_from_db()
        self.assertEqual(self.wallet.user, self.user)


class MergeWalletsTests(TestCase):
    def setUp(self):
        self.campaign = make_campaign()
        self.source = GuestWallet.objects.create()
        self.target = GuestWallet.objects.create()

    def test_merge_moves_all_coupons_and_leaves_source_empty(self):
        active = claim(self.campaign, self.source)
        redeemed = claim(make_campaign(), self.source)
        table = Table.objects.create(restaurant=redeemed.restaurant, number=99)
        order = Order.objects.create(restaurant=redeemed.restaurant, table=table)
        coupons.redeem_coupon(redeemed.pk, redeemed_by=None, order=order)
        kept = claim(make_campaign(), self.target)

        coupons.merge_wallets(self.source, self.target)

        target_ids = set(self.target.coupons.values_list("pk", flat=True))
        self.assertEqual(target_ids, {active.pk, redeemed.pk, kept.pk})
        # Redeemed history follows the guest; the source is left empty/inert.
        self.assertEqual(self.source.coupons.count(), 0)
        self.assertTrue(GuestWallet.objects.filter(pk=self.source.pk).exists())

    def test_double_merge_is_a_noop(self):
        claim(self.campaign, self.source)
        coupons.merge_wallets(self.source, self.target)
        before = list(self.target.coupons.values_list("pk", flat=True))
        coupons.merge_wallets(self.source, self.target)  # again — nothing to move
        self.assertEqual(list(self.target.coupons.values_list("pk", flat=True)), before)
        self.assertEqual(self.source.coupons.count(), 0)

    def test_merge_into_itself_is_a_noop(self):
        claim(self.campaign, self.source)
        coupons.merge_wallets(self.source, self.source)
        self.assertEqual(self.source.coupons.count(), 1)

    def test_merge_keeps_per_wallet_limit_duplicates(self):
        # Both wallets legitimately claimed the same limit-1 campaign; after
        # the merge the target holds BOTH — the limit is claim-time only.
        claim(self.campaign, self.source)
        claim(self.campaign, self.target)
        coupons.merge_wallets(self.source, self.target)
        self.assertEqual(self.target.coupons.filter(campaign=self.campaign).count(), 2)

    def test_attach_then_merge_from_second_device(self):
        # Device A: the guest registers — their cookie wallet joins the account.
        user = User.objects.create_user(username="tstm-acct", password="x-test-pass-1")
        phone_wallet = self.target
        coupons.attach_wallet_to_user(phone_wallet, user)
        account_coupon = claim(self.campaign, phone_wallet)

        # Device B (an old tablet) still has its own anonymous wallet.
        tablet_coupon = claim(make_campaign(), self.source)

        # Logging in on device B later merges the tablet wallet into the
        # account's wallet.
        coupons.merge_wallets(self.source, phone_wallet)

        self.assertEqual(
            set(phone_wallet.coupons.values_list("pk", flat=True)),
            {account_coupon.pk, tablet_coupon.pk},
        )
        phone_wallet.refresh_from_db()
        self.assertEqual(phone_wallet.user, user)
        # Re-running the same merge (double tap, retried request) changes nothing.
        coupons.merge_wallets(self.source, phone_wallet)
        self.assertEqual(phone_wallet.coupons.count(), 2)
