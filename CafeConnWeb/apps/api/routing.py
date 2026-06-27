from django.urls import path

from apps.api.consumers import StaffConsumer

urlpatterns = [
    path("staff/", StaffConsumer.as_asgi()),
]
