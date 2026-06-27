from django.contrib import admin
from django.shortcuts import redirect
from django.urls import include, path
from django.views.generic import TemplateView


def home_redirect(request):
    return redirect("guest_web:menu")


urlpatterns = [
    path("", home_redirect, name="home"),
    path("menu/", include("apps.guest_web.urls")),
    path("dashboard/", include("apps.admin_web.urls")),
    path("system-admin/", admin.site.urls),
    path("api/", include("apps.api.urls")),
    path("health/", TemplateView.as_view(template_name="health.html"), name="health"),
]
