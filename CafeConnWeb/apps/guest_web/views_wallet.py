"""Guest wallet endpoints: claim coupons, list the wallet, recover it.

Identity model (deliberately NOT the Django session — sessions expire and
rotate): a GuestWallet row whose UUID rides in a signed, httpOnly, 1-year
cookie. The cookie is set lazily — only when a guest actually claims a
coupon or opens a recovery link — so ordinary menu visitors stay cookie-free
and menu_page never writes cookies at all.
"""

from django.conf import settings
from django.core.cache import cache
from django.http import HttpResponse, JsonResponse
from django.shortcuts import redirect
from django.views.decorators.http import require_GET, require_POST

from apps.core import coupons
from apps.core.coupons import CouponError
from apps.core.models import CouponCampaign, Employee, GuestWallet, IssuedCoupon
from apps.guest_web.views import restaurant_for_guest_request

WALLET_COOKIE_NAME = "cc_wallet"
WALLET_COOKIE_MAX_AGE = 365 * 24 * 60 * 60  # 1 year; recovery link outlives it


def _wallet_from_request(request) -> GuestWallet | None:
    raw = request.COOKIES.get(WALLET_COOKIE_NAME)
    if not raw:
        return None
    token = coupons.parse_wallet_cookie(raw)
    if token is None:
        return None
    return GuestWallet.objects.filter(
        restaurant=restaurant_for_guest_request(request), pk=token
    ).first()


def _attach_wallet_cookie(response: HttpResponse, wallet: GuestWallet) -> HttpResponse:
    response.set_cookie(
        WALLET_COOKIE_NAME,
        coupons.make_wallet_cookie(wallet),
        max_age=WALLET_COOKIE_MAX_AGE,
        httponly=True,
        samesite="Lax",
        secure=not settings.DEBUG,
    )
    return response


def _coupon_payload(coupon: IssuedCoupon) -> dict:
    campaign = coupon.campaign
    display = coupons.display_status(coupon)
    payload = {
        "id": coupon.pk,
        "code": coupon.code,
        "status": display,
        "title": campaign.title,
        "titleIt": campaign.title_it or campaign.title,
        "description": campaign.description,
        "descriptionIt": campaign.description_it or campaign.description,
        "discountType": campaign.discount_type,
        "discountValue": float(campaign.discount_value),
        "validFrom": campaign.valid_from.isoformat() if campaign.valid_from else None,
        "validUntil": campaign.valid_until.isoformat() if campaign.valid_until else None,
        "issuedVia": coupon.issued_via,
        "redeemedAt": coupon.redeemed_at.isoformat() if coupon.redeemed_at else None,
        "createdAt": coupon.created_at.isoformat(),
    }
    if display == IssuedCoupon.Status.ACTIVE:
        # The QR the staff app scans: a signed redeem token, never a bare id.
        payload["qrSvg"] = coupons.qr_svg(coupons.make_redeem_token(coupon))
    return payload


@require_GET
def wallet_state(request, restaurant_slug=None):
    """The guest's wallet. Never creates a wallet or sets a cookie — reads
    stay side-effect-free so the menu page stays cookie-free by default."""
    wallet = _wallet_from_request(request)
    if wallet is None:
        return JsonResponse({"ok": True, "hasWallet": False, "coupons": []})
    wallet.touch()
    items = list(
        wallet.coupons.select_related("campaign").order_by("-created_at")
    )
    recovery_url = request.build_absolute_uri(
        f"/r/{wallet.restaurant.slug}/wallet/recover/{coupons.make_recovery_token(wallet)}/"
    )
    return JsonResponse(
        {
            "ok": True,
            "hasWallet": True,
            "coupons": [_coupon_payload(coupon) for coupon in items],
            "recovery": {
                "url": recovery_url,
                "qrSvg": coupons.qr_svg(recovery_url, scale=3),
            },
        }
    )


@require_POST
def claim_coupon_view(request, restaurant_slug=None):
    """Land a coupon in the wallet from either claim flow:

      * `claim`    — signed token from a waiter's on-screen QR;
      * `campaign` — campaign slug from a marketing link (+ utm_source).

    Idempotent per wallet (apps.core.coupons.claim_coupon); the wallet cookie
    is created here, lazily, on the guest's first ever claim.
    """
    # Every claim creates DB rows; keep bots and stuck buttons on a leash.
    rate_key = f"wallet-claim:{request.META.get('REMOTE_ADDR', '?')}"
    cache.add(rate_key, 0, 60)
    if cache.incr(rate_key) > 10:
        return JsonResponse(
            {"ok": False, "error": "Too many attempts — wait a minute and try again."},
            status=429,
        )

    restaurant = restaurant_for_guest_request(request)
    token = (request.POST.get("claim") or "").strip()
    slug = (request.POST.get("campaign") or "").strip()
    utm_source = (request.POST.get("utm_source") or "").strip()

    try:
        if token:
            payload = coupons.parse_claim_token(token)
            try:
                campaign = CouponCampaign.objects.get(
                    restaurant=restaurant, pk=payload["campaign"]
                )
            except CouponCampaign.DoesNotExist:
                raise CouponError("This campaign no longer exists.")
            issued_by = (
                Employee.objects.filter(
                    restaurant=restaurant, pk=payload["employee"]
                ).first()
                if payload.get("employee")
                else None
            )
            issued_via = IssuedCoupon.IssuedVia.STAFF_QR
        elif slug:
            try:
                campaign = CouponCampaign.objects.get(
                    restaurant=restaurant, slug=slug
                )
            except CouponCampaign.DoesNotExist:
                raise CouponError("This campaign does not exist.")
            issued_by = None
            issued_via = IssuedCoupon.IssuedVia.CAMPAIGN_LINK
        else:
            raise CouponError("This coupon link is not valid.")

        wallet = _wallet_from_request(request)
        created_wallet = wallet is None
        if created_wallet:
            wallet = GuestWallet.objects.create(restaurant=restaurant)

        coupon, created = coupons.claim_coupon(
            campaign,
            wallet,
            issued_via=issued_via,
            issued_by=issued_by,
            utm_source=utm_source or campaign.source_utm,
        )
    except CouponError as error:
        return JsonResponse({"ok": False, "error": str(error)}, status=400)

    response = JsonResponse(
        {"ok": True, "created": created, "coupon": _coupon_payload(coupon)}
    )
    return _attach_wallet_cookie(response, wallet)


@require_GET
def recover_wallet(request, token, restaurant_slug=None):
    """Signed "save forever" link: re-attach the wallet cookie on this device
    and land on the menu with the Wallet tab open."""
    try:
        wallet_pk = coupons.parse_recovery_token(token)
    except CouponError:
        return redirect(f"/r/{restaurant_for_guest_request(request).slug}/?wallet=invalid")
    restaurant = restaurant_for_guest_request(request)
    wallet = GuestWallet.objects.filter(
        restaurant=restaurant, pk=wallet_pk
    ).first()
    if wallet is None:
        return redirect(f"/r/{restaurant.slug}/?wallet=invalid")
    wallet.touch()
    response = redirect(f"/r/{restaurant.slug}/?wallet=1")
    return _attach_wallet_cookie(response, wallet)
