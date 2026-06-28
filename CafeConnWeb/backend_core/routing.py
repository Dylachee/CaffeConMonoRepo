from channels.routing import URLRouter
from django.urls import path

from apps.api.routing import websocket_urlpatterns as api_ws_patterns

websocket_urlpatterns = [
    path("ws/", URLRouter(api_ws_patterns)),
]
