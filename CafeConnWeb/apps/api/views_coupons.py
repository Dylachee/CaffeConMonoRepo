"""Staff coupon endpoints: /api/staff/coupons/…

Responsibility split (mirrors the capability model):
  * campaign CRUD + UTM analytics — `content` (SMM's marketing job) or manage;
  * issuing claim QRs and redeeming coupons — `discount` (a manager-granted
    flag, boss included);
  * voiding a cancelled order's redemption — `manage` only.

All state transitions live in apps.core.coupons; every CouponError surfaces
verbatim as a 400/409 with a human-readable message.
"""

from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.permissions import (
    HasContentCapability,
    HasDiscountCapability,
    HasManageCapability,
)
from apps.api.serializers import (
    CouponCampaignSerializer,
    IssuedCouponStaffSerializer,
    OrderSerializer,
)
from apps.api.tenant import employee_for_request, restaurant_for_request
from apps.core import coupons
from apps.core.coupons import CouponError
from apps.core.models import CouponCampaign, IssuedCoupon, Order


def _campaigns_with_counters(restaurant):
    return CouponCampaign.objects.filter(restaurant=restaurant).annotate(
        issued_count_annotated=Count(
            "coupons", filter=~Q(coupons__status=IssuedCoupon.Status.VOID)
        ),
        redeemed_count_annotated=Count(
            "coupons", filter=Q(coupons__status=IssuedCoupon.Status.REDEEMED)
        ),
    )


class StaffCampaignsView(APIView):
    permission_classes = [permissions.IsAuthenticated, HasContentCapability]

    def get(self, request):
        restaurant = restaurant_for_request(request)
        campaigns = _campaigns_with_counters(restaurant).select_related("created_by")
        return Response({"campaigns": CouponCampaignSerializer(campaigns, many=True).data})

    def post(self, request):
        restaurant = restaurant_for_request(request)
        serializer = CouponCampaignSerializer(
            data=request.data, context={"restaurant": restaurant}
        )
        serializer.is_valid(raise_exception=True)
        campaign = serializer.save(
            restaurant=restaurant, created_by=employee_for_request(request)
        )
        return Response(
            CouponCampaignSerializer(campaign).data, status=status.HTTP_201_CREATED
        )


class StaffCampaignDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated, HasContentCapability]

    def patch(self, request, pk):
        restaurant = restaurant_for_request(request)
        campaign = get_object_or_404(CouponCampaign, restaurant=restaurant, pk=pk)
        serializer = CouponCampaignSerializer(
            campaign,
            data=request.data,
            partial=True,
            context={"restaurant": restaurant},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, pk):
        campaign = get_object_or_404(
            CouponCampaign, restaurant=restaurant_for_request(request), pk=pk
        )
        if campaign.coupons.exists():
            # Issued coupons are guest property and analytics history —
            # deactivate instead of destroying them.
            campaign.is_active = False
            campaign.save(update_fields=["is_active", "updated_at"])
            return Response(
                {
                    "detail": (
                        "The campaign has issued coupons, so it was deactivated "
                        "instead of deleted."
                    ),
                    "campaign": CouponCampaignSerializer(campaign).data,
                }
            )
        campaign.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class StaffCouponIssueView(APIView):
    """Waiter picks a campaign; the response carries a signed claim URL the
    staff app renders as a fullscreen QR for the guest's phone camera."""

    permission_classes = [permissions.IsAuthenticated, HasDiscountCapability]

    def post(self, request):
        restaurant = restaurant_for_request(request)
        campaign = get_object_or_404(
            CouponCampaign,
            restaurant=restaurant,
            pk=request.data.get("campaign"),
        )
        if not campaign.is_active or campaign.window_state() != "open":
            return Response(
                {"detail": "This campaign is not currently claimable."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        token = coupons.make_claim_token(campaign, employee_for_request(request))
        return Response(
            {
                "token": token,
                "claimUrl": request.build_absolute_uri(
                    f"/r/{restaurant.slug}/?claim={token}"
                ),
                "expiresIn": coupons.CLAIM_TOKEN_TTL,
                "campaign": CouponCampaignSerializer(campaign).data,
            }
        )


def _resolve_coupon(request) -> IssuedCoupon:
    """Find the coupon a staff member scanned (signed token) or typed (code)."""
    token = (request.data.get("token") or "").strip()
    code = (request.data.get("code") or "").strip().upper()
    if token:
        payload = coupons.parse_redeem_token(token)  # raises CouponError
        try:
            return IssuedCoupon.objects.select_related("campaign", "order").get(
                restaurant=restaurant_for_request(request),
                pk=payload["coupon"], code=payload["code"]
            )
        except IssuedCoupon.DoesNotExist:
            raise CouponError("This coupon does not exist.")
    if code:
        try:
            return IssuedCoupon.objects.select_related("campaign", "order").get(
                restaurant=restaurant_for_request(request), code=code
            )
        except IssuedCoupon.DoesNotExist:
            raise CouponError("No coupon with this code.")
    raise CouponError("Scan the coupon QR or enter its code.")


class StaffCouponPreviewView(APIView):
    """Read-only look-up before the confirmation sheet: campaign, discount,
    display status, and the computed discount for an optional order."""

    permission_classes = [permissions.IsAuthenticated, HasDiscountCapability]

    def post(self, request):
        try:
            coupon = _resolve_coupon(request)
        except CouponError as error:
            return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)

        payload = {
            "coupon": IssuedCouponStaffSerializer(coupon).data,
            "displayStatus": coupons.display_status(coupon),
        }
        order_id = request.data.get("order_id")
        if order_id:
            order = get_object_or_404(
                Order, restaurant=restaurant_for_request(request), pk=order_id
            )
            payload["discountPreview"] = str(
                coupons.compute_discount(coupon.campaign, order.total)
            )
            payload["orderTotal"] = str(order.total)
        return Response(payload)


class StaffCouponRedeemView(APIView):
    permission_classes = [permissions.IsAuthenticated, HasDiscountCapability]

    def post(self, request):
        from apps.api.events import broadcast_order_event

        try:
            coupon = _resolve_coupon(request)
        except CouponError as error:
            return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)

        order = None
        order_id = request.data.get("order_id")
        if order_id:
            order = get_object_or_404(
                Order, restaurant=restaurant_for_request(request), pk=order_id
            )

        try:
            coupon = coupons.redeem_coupon(
                coupon.pk, redeemed_by=employee_for_request(request), order=order
            )
        except CouponError as error:
            return Response({"detail": str(error)}, status=status.HTTP_409_CONFLICT)

        payload = {"coupon": IssuedCouponStaffSerializer(coupon).data}
        if order is not None:
            order.refresh_from_db()
            payload["order"] = OrderSerializer(order).data
            # Every staff device sees the discount line appear live.
            broadcast_order_event("updated", order)
        return Response(payload)


class StaffCouponVoidView(APIView):
    """Return a redeemed coupon of a CANCELLED order to active — manager only."""

    permission_classes = [permissions.IsAuthenticated, HasManageCapability]

    def post(self, request, pk):
        coupon = get_object_or_404(
            IssuedCoupon, restaurant=restaurant_for_request(request), pk=pk
        )
        try:
            coupon = coupons.void_redemption(coupon)
        except CouponError as error:
            return Response({"detail": str(error)}, status=status.HTTP_409_CONFLICT)
        return Response({"coupon": IssuedCouponStaffSerializer(coupon).data})
