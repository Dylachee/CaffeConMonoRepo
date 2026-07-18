from django.urls import path

from apps.api.consumers import StaffConsumer

websocket_urlpatterns = [
    path("restaurants/<slug:restaurant_slug>/staff/", StaffConsumer.as_asgi()),
    path("staff/", StaffConsumer.as_asgi()),
]
