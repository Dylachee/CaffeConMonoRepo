import os

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from django.conf import settings
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "backend_core.settings")

django_asgi_app = get_asgi_application()

from apps.api.middleware import TokenAuthMiddleware  # noqa: E402
from backend_core.routing import websocket_urlpatterns  # noqa: E402

# Token auth (?token=<drf-token>) wraps the standard auth stack and router.
websocket_router = TokenAuthMiddleware(
    AuthMiddlewareStack(
        URLRouter(websocket_urlpatterns),
    )
)

# Origin handling differs by environment:
#   * Production -> validate the WS Origin header against ALLOWED_HOSTS so only
#     trusted browser origins (guest/management web) can connect.
#   * DEBUG -> native mobile clients (Flutter on a physical Android device over
#     Wi-Fi) send NO Origin header, which AllowedHostsOriginValidator rejects.
#     We therefore skip origin validation locally; the token check still applies.
if settings.DEBUG:
    websocket_application = websocket_router
else:
    websocket_application = AllowedHostsOriginValidator(websocket_router)

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": websocket_application,
    }
)
