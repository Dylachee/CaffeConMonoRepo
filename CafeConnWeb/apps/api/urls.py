from django.urls import include, path
from rest_framework.authtoken.views import obtain_auth_token
from rest_framework.routers import DefaultRouter

from apps.api import views

app_name = "api"

router = DefaultRouter()
router.register("menu-items", views.MenuItemViewSet, basename="menu-item")
router.register("tables", views.TableViewSet, basename="table")
router.register("orders", views.OrderViewSet, basename="order")
router.register("order-items", views.OrderItemViewSet, basename="order-item")
router.register("attention-signals", views.AttentionSignalViewSet, basename="attention-signal")
router.register("employees", views.EmployeeViewSet, basename="employee")

urlpatterns = [
    path("", include(router.urls)),
    path("auth/token/", obtain_auth_token, name="auth-token"),
    path("staff/bootstrap/", views.StaffBootstrapView.as_view(), name="staff-bootstrap"),
    path("staff/preferences/", views.StaffPreferenceView.as_view(), name="staff-preferences"),
    path("health/", views.HealthCheckView.as_view(), name="health"),
]
