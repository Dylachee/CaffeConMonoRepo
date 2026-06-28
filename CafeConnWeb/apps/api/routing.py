from django.urls import path

from apps.api.consumers import StaffConsumer

websocket_urlpatterns = [
    path("staff/", StaffConsumer.as_asgi()),
]
