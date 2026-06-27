from django.urls import include, path

websocket_urlpatterns = [
    path("ws/", include("apps.api.routing")),
]
