from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from rest_framework.authtoken.models import Token


@database_sync_to_async
def get_user_for_token(token_key):
    try:
        return Token.objects.select_related("user").get(key=token_key).user
    except Token.DoesNotExist:
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

        return await self.inner(scope, receive, send)
