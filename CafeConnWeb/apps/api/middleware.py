from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from rest_framework.authtoken.models import Token

from apps.core.models import Employee, Restaurant


class RestaurantRouteMiddleware:
    """Keep the tenant slug as request context without leaking the include
    parameter into every DRF handler method."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        return self.get_response(request)

    def process_view(self, request, view_func, view_args, view_kwargs):
        if request.path.startswith("/api/restaurants/"):
            request.route_restaurant_slug = view_kwargs.pop(
                "restaurant_slug", "sissy-bar"
            )
        return None


@database_sync_to_async
def get_user_for_token(token_key):
    try:
        return Token.objects.select_related("user").get(key=token_key).user
    except Token.DoesNotExist:
        return None


@database_sync_to_async
def get_restaurant_access(user, slug):
    try:
        restaurant = Restaurant.objects.get(slug=slug, is_active=True)
    except Restaurant.DoesNotExist:
        return None
    if user.is_superuser or Employee.objects.filter(
        user=user, restaurant=restaurant
    ).exists():
        return {"id": restaurant.pk, "slug": restaurant.slug}
    return None


class TokenAuthMiddleware:
    """Authenticate WebSocket clients with ?token=<drf-token>."""

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        query_params = parse_qs(scope.get("query_string", b"").decode())
        token = query_params.get("token", [None])[0]

        if token:
            scope = dict(scope)
            user = await get_user_for_token(token)
            if user is not None:
                scope["user"] = user
                slug = (
                    scope.get("url_route", {}).get("kwargs", {}).get("restaurant_slug")
                    or "sissy-bar"
                )
                scope["restaurant"] = await get_restaurant_access(user, slug)

        return await self.inner(scope, receive, send)
