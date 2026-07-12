from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.api import views

app_name = "api"

router = DefaultRouter()
router.register("menu-items", views.MenuItemViewSet, basename="menu-item")
router.register("menu-categories", views.MenuCategoryViewSet, basename="menu-category")
router.register("tables", views.TableViewSet, basename="table")
router.register("orders", views.OrderViewSet, basename="order")
router.register("order-items", views.OrderItemViewSet, basename="order-item")
router.register("attention-signals", views.AttentionSignalViewSet, basename="attention-signal")
router.register("employees", views.EmployeeViewSet, basename="employee")

urlpatterns = [
    path("", include(router.urls)),
    path("auth/token/", views.ThrottledObtainAuthToken.as_view(), name="auth-token"),
    path("staff/bootstrap/", views.StaffBootstrapView.as_view(), name="staff-bootstrap"),
    path("staff/stats/", views.StaffStatsView.as_view(), name="staff-stats"),
    path("staff/order-history/", views.StaffOrderHistoryView.as_view(), name="staff-order-history"),
    path("staff/table-history/", views.StaffTableHistoryView.as_view(), name="staff-table-history"),
    path("staff/accounts/", views.StaffAccountCreateView.as_view(), name="staff-account-create"),
    path("staff/preferences/", views.StaffPreferenceView.as_view(), name="staff-preferences"),
    path("health/", views.HealthCheckView.as_view(), name="health"),
]
