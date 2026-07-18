"""Coupon domain service: signed tokens, claiming, redemption, discount math.

One module owns every state transition of a coupon so the API views and the
guest web stay thin:

  * signed tokens (django.core.signing, purpose-specific salts + TTLs) for
    the three QR/link payloads — staff claim QR, guest redeem QR, wallet
    recovery link. A QR never encodes a bare id;
  * `claim_coupon`  — idempotent per wallet, enforces the campaign window,
    per-wallet limit and the global issue cap under a row lock;
  * `redeem_coupon` — single-use under `select_for_update`, computes and
    snapshots the discount when an order is attached;
  * `compute_discount` — the one pure function for the money math;
  * `void_redemption` — manager-only return of a cancelled order's coupon.

Every guard raises CouponError with a human-readable, guest-safe message.
"""

import secrets
from decimal import Decimal

from django.core import signing
from django.db import transaction
from django.utils import timezone

from apps.core.models import CouponCampaign, Employee, GuestWallet, IssuedCoupon, Order

# Purpose-specific salts: a token minted for one flow can never be replayed
# in another.
CLAIM_SALT = "cafeconnect.coupon.claim"
REDEEM_SALT = "cafeconnect.coupon.redeem"
RECOVERY_SALT = "cafeconnect.wallet.recovery"
WALLET_COOKIE_SALT = "cafeconnect.wallet.cookie"

# A waiter's on-screen claim QR is scanned within minutes; 6 h covers a shift.
CLAIM_TOKEN_TTL = 6 * 60 * 60
# The guest's redeem QR is regenerated on every wallet fetch; 48 h of slack
# covers a wallet screen left open overnight.
REDEEM_TOKEN_TTL = 48 * 60 * 60
# Recovery links are the guest's "save forever" handle — no expiry; the
# wallet cookie is re-validated against a generous ceiling instead.
WALLET_COOKIE_MAX_AGE = 2 * 365 * 24 * 60 * 60

# No 0/O, 1/I/L — codes get read out loud over a counter.
CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
CODE_LENGTH = 8


class CouponError(Exception):
    """A coupon rule was violated. str(error) is safe to show to a human."""


# --- signed tokens -----------------------------------------------------------


def make_claim_token(campaign: CouponCampaign, issued_by: Employee | None) -> str:
    """Token behind a staff-issued claim QR (encodes campaign + waiter)."""
    return signing.dumps(
        {"campaign": campaign.pk, "employee": issued_by.pk if issued_by else None},
        salt=CLAIM_SALT,
    )


def parse_claim_token(token: str) -> dict:
    try:
        return signing.loads(token, salt=CLAIM_SALT, max_age=CLAIM_TOKEN_TTL)
    except signing.SignatureExpired:
        raise CouponError("This coupon QR has expired — ask the staff for a fresh one.")
    except signing.BadSignature:
        raise CouponError("This coupon link is not valid.")


def make_redeem_token(coupon: IssuedCoupon) -> str:
    """Token inside the guest's wallet-card QR (what the staff app scans)."""
    return signing.dumps({"coupon": coupon.pk, "code": coupon.code}, salt=REDEEM_SALT)


def parse_redeem_token(token: str) -> dict:
    try:
        return signing.loads(token, salt=REDEEM_SALT, max_age=REDEEM_TOKEN_TTL)
    except signing.SignatureExpired:
        raise CouponError("This coupon QR is stale — ask the guest to reopen their wallet.")
    except signing.BadSignature:
        raise CouponError("This is not a valid coupon QR.")


def make_recovery_token(wallet: GuestWallet) -> str:
    return signing.dumps(str(wallet.pk), salt=RECOVERY_SALT)


def parse_recovery_token(token: str) -> str:
    try:
        return signing.loads(token, salt=RECOVERY_SALT)  # deliberate: no expiry
    except signing.BadSignature:
        raise CouponError("This wallet link is not valid.")


def make_wallet_cookie(wallet: GuestWallet) -> str:
    return signing.dumps(str(wallet.pk), salt=WALLET_COOKIE_SALT)


def parse_wallet_cookie(value: str) -> str | None:
    """Wallet token from the signed cookie, or None for anything invalid —
    a bad cookie must read as 'no wallet', never as an error page."""
    try:
        return signing.loads(value, salt=WALLET_COOKIE_SALT, max_age=WALLET_COOKIE_MAX_AGE)
    except signing.BadSignature:
        return None


# --- codes and QR ------------------------------------------------------------


def generate_coupon_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def qr_svg(payload: str, *, scale: int = 4) -> str:
    """Inline-SVG QR (segno). Always dark-on-transparent: QRs sit on a white
    card area for scan contrast regardless of the venue theme."""
    import segno

    return segno.make(payload, error="m").svg_inline(scale=scale, dark="#1e1b16", border=1)


# --- claiming ----------------------------------------------------------------


def _check_window(campaign: CouponCampaign) -> None:
    if not campaign.is_active:
        raise CouponError("This campaign is no longer active.")
    state = campaign.window_state()
    if state == "pending":
        raise CouponError("This campaign has not started yet.")
    if state == "expired":
        raise CouponError("This campaign has ended.")


def claim_coupon(
    campaign: CouponCampaign,
    wallet: GuestWallet,
    *,
    issued_via: str,
    issued_by: Employee | None = None,
    utm_source: str = "",
) -> tuple[IssuedCoupon, bool]:
    """Put one coupon of `campaign` into `wallet`. Returns (coupon, created).

    Idempotent per wallet: once the wallet holds `per_wallet_limit` coupons of
    the campaign, re-claiming returns the newest one instead of failing — so
    re-opening a claim link never scares a guest with an error.
    """
    if wallet.restaurant_id != campaign.restaurant_id:
        raise CouponError("This wallet belongs to another restaurant.")
    if issued_by is not None and issued_by.restaurant_id != campaign.restaurant_id:
        raise CouponError("This employee belongs to another restaurant.")
    with transaction.atomic():
        # Lock the campaign row: the max_total_issues check and the insert
        # must be atomic against concurrent claims.
        campaign = CouponCampaign.objects.select_for_update().get(pk=campaign.pk)
        _check_window(campaign)

        existing = list(
            IssuedCoupon.objects.filter(campaign=campaign, wallet=wallet)
            .exclude(status=IssuedCoupon.Status.VOID)
            .order_by("-created_at")
        )
        if len(existing) >= campaign.per_wallet_limit:
            return existing[0], False

        if campaign.max_total_issues is not None:
            issued = (
                IssuedCoupon.objects.filter(campaign=campaign)
                .exclude(status=IssuedCoupon.Status.VOID)
                .count()
            )
            if issued >= campaign.max_total_issues:
                raise CouponError("This campaign is fully claimed — all coupons are gone.")

        for _ in range(20):
            code = generate_coupon_code()
            if not IssuedCoupon.objects.filter(code=code).exists():
                break
        else:  # pragma: no cover — 31^8 keyspace
            raise CouponError("Could not allocate a coupon code, please retry.")

        coupon = IssuedCoupon.objects.create(
            restaurant=campaign.restaurant,
            campaign=campaign,
            wallet=wallet,
            code=code,
            issued_via=issued_via,
            issued_by=issued_by,
            utm_source=utm_source[:64],
        )
        return coupon, True


# --- discount math -----------------------------------------------------------

_CENT = Decimal("0.01")


def compute_discount(campaign: CouponCampaign, order_total: Decimal) -> Decimal:
    """The one place discount money is computed. Percent of the items total,
    or the fixed amount capped at the total; never negative."""
    if order_total is None or order_total <= 0:
        return Decimal("0.00")
    if campaign.discount_type == CouponCampaign.DiscountType.PERCENT:
        amount = order_total * campaign.discount_value / Decimal("100")
    else:
        amount = campaign.discount_value
    amount = min(amount, order_total)
    if amount < 0:
        return Decimal("0.00")
    return amount.quantize(_CENT)


# --- redemption --------------------------------------------------------------


def redeem_coupon(
    coupon_id: int,
    *,
    redeemed_by: Employee | None,
    order: Order | None = None,
) -> IssuedCoupon:
    """Redeem exactly once.

    Two layers keep simultaneous scans from double-spending one coupon:
    `select_for_update` serializes the whole redemption on backends with row
    locks (Postgres in production), and the actual state transition is a
    compare-and-swap `UPDATE … WHERE status = ACTIVE` — so even on backends
    where FOR UPDATE is a no-op (SQLite in tests) exactly one caller wins and
    the other gets a clear "already used" error.
    """
    # Expiry pre-check OUTSIDE the transaction: the lazy EXPIRED mark must
    # survive the CouponError below (inside atomic it would be rolled back
    # together with everything else).
    try:
        pre = IssuedCoupon.objects.select_related("campaign").get(pk=coupon_id)
    except IssuedCoupon.DoesNotExist:
        raise CouponError("This coupon does not exist.")
    if pre.status == IssuedCoupon.Status.ACTIVE and pre.campaign.window_state() == "expired":
        IssuedCoupon.objects.filter(
            pk=coupon_id, status=IssuedCoupon.Status.ACTIVE
        ).update(status=IssuedCoupon.Status.EXPIRED, updated_at=timezone.now())
        raise CouponError("This coupon has expired.")

    with transaction.atomic():
        coupon = (
            IssuedCoupon.objects.select_for_update()
            .select_related("campaign")
            .get(pk=coupon_id)
        )

        if coupon.status == IssuedCoupon.Status.REDEEMED:
            raise CouponError("This coupon has already been used.")
        if coupon.status == IssuedCoupon.Status.VOID:
            raise CouponError("This coupon was invalidated.")
        if coupon.status == IssuedCoupon.Status.EXPIRED:
            raise CouponError("This coupon has expired.")

        if order is not None:
            order = Order.objects.select_for_update().get(pk=order.pk)
            if order.restaurant_id != coupon.restaurant_id:
                raise CouponError("This coupon belongs to another restaurant.")
            if order.status in (Order.Status.PAID, Order.Status.CANCELLED):
                raise CouponError("This order is closed — the coupon cannot be applied to it.")
            if order.coupon_id is not None and order.coupon_id != coupon.pk:
                raise CouponError("This order already has a coupon applied.")

        now = timezone.now()
        won = IssuedCoupon.objects.filter(
            pk=coupon.pk, status=IssuedCoupon.Status.ACTIVE
        ).update(
            status=IssuedCoupon.Status.REDEEMED,
            redeemed_by=redeemed_by,
            redeemed_at=now,
            order=order,
            updated_at=now,
        )
        if not won:
            raise CouponError("This coupon has already been used.")
        coupon.refresh_from_db()

        if order is not None:
            order.coupon = coupon
            order.discount_amount = compute_discount(coupon.campaign, order.total)
            order.save(update_fields=["coupon", "discount_amount", "updated_at"])
        return coupon


def void_redemption(coupon: IssuedCoupon) -> IssuedCoupon:
    """Manager-only: return a redeemed coupon of a CANCELLED order to ACTIVE.
    The capability check lives in the API layer; the domain rule here is that
    only a cancelled (or detached) order's coupon may be reactivated."""
    with transaction.atomic():
        coupon = (
            IssuedCoupon.objects.select_for_update()
            .select_related("order")
            .get(pk=coupon.pk)
        )
        if coupon.status != IssuedCoupon.Status.REDEEMED:
            raise CouponError("Only a redeemed coupon can be voided back to active.")
        order = coupon.order
        if order is not None and order.status != Order.Status.CANCELLED:
            raise CouponError("The order is not cancelled — cancel it first, then void the coupon.")

        if order is not None:
            order.coupon = None
            order.discount_amount = None
            order.save(update_fields=["coupon", "discount_amount", "updated_at"])
        coupon.status = IssuedCoupon.Status.ACTIVE
        coupon.redeemed_by = None
        coupon.redeemed_at = None
        coupon.order = None
        coupon.save(update_fields=["status", "redeemed_by", "redeemed_at", "order", "updated_at"])
        return coupon


# --- future-registration seam -------------------------------------------------
# Progressive registration (Google/Apple/OTP) is deliberately NOT built. These
# two functions are the entire data seam it will need: an account adopts the
# browser's cookie wallet via attach_wallet_to_user, and a second device's
# wallet folds into it via merge_wallets. The recovery-link block in the guest
# UI is the future CTA slot.


def attach_wallet_to_user(wallet: GuestWallet, user) -> GuestWallet:
    """Bind a cookie wallet to a real account. Idempotent: re-attaching to the
    same user is a no-op; a wallet already owned by a DIFFERENT user is
    refused (that requires an explicit merge decision, never a silent steal).
    """
    with transaction.atomic():
        wallet = GuestWallet.objects.select_for_update().get(pk=wallet.pk)
        if wallet.user_id is not None:
            if wallet.user_id == user.pk:
                return wallet
            raise CouponError("This wallet already belongs to another account.")
        wallet.user = user
        wallet.last_seen_at = timezone.now()
        wallet.save(update_fields=["user", "last_seen_at"])
        return wallet


def merge_wallets(source: GuestWallet, target: GuestWallet) -> GuestWallet:
    """Fold `source` into `target`: every IssuedCoupon moves to the target,
    whatever its status — redeemed history follows the guest.

    Atomic and idempotent: merging the same pair again (or a wallet into
    itself) is a no-op, so a double-submitted "link this device" action can't
    corrupt anything. The source row is left behind empty and inert (its
    cookie/recovery link then resolves to an empty wallet, which is harmless).

    NOTE on duplicates: `per_wallet_limit` is enforced at CLAIM time only.
    If both wallets claimed the same campaign before merging, the target ends
    up holding more coupons of that campaign than the limit — deliberately.
    They were legitimately issued; silently voiding a guest's coupon during
    account linking would be worse than honoring both.
    """
    if source.pk == target.pk:
        return target
    with transaction.atomic():
        # Deterministic lock order (row by row — a filter() would lock in DB
        # scan order) prevents an AB/BA deadlock between concurrent merges.
        locked = {}
        for pk in sorted([source.pk, target.pk], key=str):
            wallet = GuestWallet.objects.select_for_update().get(pk=pk)
            locked[wallet.pk] = wallet
        source, target = locked[source.pk], locked[target.pk]
        IssuedCoupon.objects.filter(wallet=source).update(
            wallet=target, updated_at=timezone.now()
        )
        target.touch()
        return target


# --- wallet-facing helpers ----------------------------------------------------


def display_status(coupon: IssuedCoupon) -> str:
    """Status as the guest should see it: an ACTIVE coupon of an ended
    campaign reads 'expired' without waiting for a lazy DB update."""
    if (
        coupon.status == IssuedCoupon.Status.ACTIVE
        and coupon.campaign.window_state() == "expired"
    ):
        return IssuedCoupon.Status.EXPIRED
    return coupon.status
