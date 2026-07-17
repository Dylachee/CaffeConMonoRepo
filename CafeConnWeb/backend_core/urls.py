from django.conf import settings
from django.contrib import admin
from django.shortcuts import redirect
from django.urls import include, path, re_path
from django.views.generic import TemplateView
from django.views.static import serve as media_serve

from apps.guest_web.views import staff_app


def home_redirect(request):
    return redirect("guest_web:menu")


urlpatterns = [
    path("", home_redirect, name="home"),
    path("menu/", include("apps.guest_web.urls")),
    path("staff/", staff_app),
    path("staff/<path:path>", staff_app),
    path("dashboard/", include("apps.admin_web.urls")),
    path("system-admin/", admin.site.urls),
    path("api/", include("apps.api.urls")),
    path("health/", TemplateView.as_view(template_name="health.html"), name="health"),
    # Venue media (logo/cover) from MEDIA_ROOT. WhiteNoise only covers static
    # files, so uploads need this route. Fine for a handful of small images on
    # the single-process deploy; goes away once media_storage points at
    # S3/Cloudinary (whose URLs bypass this route entirely).
    re_path(r"^media/(?P<path>.*)$", media_serve, {"document_root": settings.MEDIA_ROOT}),
]
