"""Restaurant context resolution shared by REST permissions and querysets."""

from django.http import Http404
from rest_framework.exceptions import PermissionDenied

from apps.core.models import Employee, Restaurant


def _route_slug(request) -> str:
    if getattr(request, "route_restaurant_slug", None):
        return request.route_restaurant_slug
    parser_context = getattr(request, "parser_context", None) or {}
    kwargs = parser_context.get("kwargs") or {}
    if kwargs.get("restaurant_slug"):
        return kwargs["restaurant_slug"]
    match = getattr(request, "resolver_match", None)
    if match and match.kwargs.get("restaurant_slug"):
        return match.kwargs["restaurant_slug"]
    # Compatibility for the existing deployed app while it learns the
    # restaurant-qualified routes. All new clients use an explicit slug.
    return "sissy-bar"


def restaurant_for_request(request, *, require_membership: bool = True) -> Restaurant:
    cached = getattr(request, "restaurant", None)
    if cached is not None:
        return cached

    requested_slug = _route_slug(request)
    try:
        restaurant = Restaurant.objects.get(slug=requested_slug, is_active=True)
    except Restaurant.DoesNotExist:
        restaurant = next(
            (
                item
                for item in Restaurant.objects.filter(is_active=True)
                if requested_slug in (item.legacy_slugs or [])
            ),
            None,
        )
        if restaurant is None:
            raise Http404("Restaurant not found.")

    user = getattr(request, "user", None)
    if (
        require_membership
        and user
        and user.is_authenticated
        and not user.is_superuser
        and not Employee.objects.filter(user=user, restaurant=restaurant).exists()
    ):
        raise PermissionDenied("You do not have access to this restaurant.")

    request.restaurant = restaurant
    return restaurant


def employee_for_request(request) -> Employee | None:
    user = getattr(request, "user", None)
    if not user or user.is_anonymous:
        return None
    restaurant = restaurant_for_request(request)
    return (
        Employee.objects.select_related("user", "restaurant")
        .filter(user=user, restaurant=restaurant)
        .first()
    )


def capabilities_for_request(request) -> dict[str, bool]:
    user = getattr(request, "user", None)
    if user and user.is_authenticated and user.is_superuser:
        return {
            "wait": True,
            "bar": True,
            "kitchen": True,
            "menu": True,
            "manage": True,
            "content": True,
            "discount": True,
            "reports": True,
        }
    employee = employee_for_request(request)
    if employee:
        return employee.capabilities
    return {
        "wait": False,
        "bar": False,
        "kitchen": False,
        "menu": False,
        "manage": False,
        "content": False,
        "discount": False,
        "reports": False,
    }


def chat_channels_for_request(request) -> list[str]:
    """Channels the signed-in membership may read or write."""
    caps = capabilities_for_request(request)
    if caps["manage"]:
        return ["general", "floor", "kitchen", "bar"]
    channels = ["general"]
    if caps["wait"]:
        channels.append("floor")
    if caps["kitchen"]:
        channels.append("kitchen")
    if caps["bar"]:
        channels.append("bar")
    return channels


class RestaurantQuerysetMixin:
    """Scope DRF viewset reads/writes to the authenticated restaurant."""

    restaurant_field = "restaurant"
    create_restaurant_field = "restaurant"

    def get_restaurant(self):
        return restaurant_for_request(self.request)

    def get_queryset(self):
        queryset = super().get_queryset()
        return queryset.filter(**{self.restaurant_field: self.get_restaurant()})

    def perform_create(self, serializer):
        if self.create_restaurant_field:
            serializer.save(**{self.create_restaurant_field: self.get_restaurant()})
        else:
            serializer.save()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["restaurant"] = self.get_restaurant()
        return context
