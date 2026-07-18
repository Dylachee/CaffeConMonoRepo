"""Shared DRF permission classes for capability-gated staff endpoints."""

from rest_framework import permissions


class HasContentCapability(permissions.BasePermission):
    """Feed and storefront management: the `content` capability (SMM role,
    granted can_content flag) or `manage` (manager/admin)."""

    message = "You need the content capability to manage the venue's feed and storefront."

    def has_permission(self, request, view):
        from apps.api.tenant import capabilities_for_request

        if not request.user or not request.user.is_authenticated:
            return False
        caps = capabilities_for_request(request)
        return bool(caps.get("content") or caps.get("manage"))


class HasDiscountCapability(permissions.BasePermission):
    """Issuing and redeeming guest coupons: the `discount` capability
    (manager/admin, or the can_grant_discount flag a manager toggled)."""

    message = "You need the discount capability to issue or redeem coupons."

    def has_permission(self, request, view):
        from apps.api.tenant import capabilities_for_request

        if not request.user or not request.user.is_authenticated:
            return False
        return bool(capabilities_for_request(request).get("discount"))


class HasManageCapability(permissions.BasePermission):
    """Manager/admin only (e.g. voiding a redeemed coupon)."""

    message = "Only a manager or admin can do this."

    def has_permission(self, request, view):
        from apps.api.tenant import capabilities_for_request

        if not request.user or not request.user.is_authenticated:
            return False
        return bool(capabilities_for_request(request).get("manage"))
