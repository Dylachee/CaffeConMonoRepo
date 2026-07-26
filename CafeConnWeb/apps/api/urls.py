from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.api import views, views_chat, views_coupons, views_feed, views_tasks, views_venue

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
    path("platform/restaurants/", views.PlatformRestaurantsView.as_view(), name="platform-restaurants"),
    path("platform/restaurants/<int:pk>/", views.PlatformRestaurantDetailView.as_view(), name="platform-restaurant-detail"),
    path("auth/token/", views.ThrottledObtainAuthToken.as_view(), name="auth-token"),
    path("staff/bootstrap/", views.StaffBootstrapView.as_view(), name="staff-bootstrap"),
    path("staff/stats/", views.StaffStatsView.as_view(), name="staff-stats"),
    path("staff/order-history/", views.StaffOrderHistoryView.as_view(), name="staff-order-history"),
    path("staff/station-history/", views.StaffStationHistoryView.as_view(), name="staff-station-history"),
    path("staff/table-bill/", views.StaffTableBillView.as_view(), name="staff-table-bill"),
    path("staff/menu-snapshot/", views.StaffMenuSnapshotView.as_view(), name="staff-menu-snapshot"),
    path("staff/table-history/", views.StaffTableHistoryView.as_view(), name="staff-table-history"),
    path("staff/accounts/", views.StaffAccountCreateView.as_view(), name="staff-account-create"),
    path("staff/preferences/", views.StaffPreferenceView.as_view(), name="staff-preferences"),
    # Alerts: self-service shift toggle + Web-Push subscription lifecycle.
    path("staff/shift/", views.StaffShiftView.as_view(), name="staff-shift"),
    path("staff/push-subscriptions/", views.StaffPushSubscriptionView.as_view(), name="staff-push-subscriptions"),
    # Staff chat (persistent, threaded) + tasks (chat bubbles = planner rows).
    path("staff/chat/messages/", views_chat.StaffChatMessagesView.as_view(), name="staff-chat-messages"),
    path("staff/chat/thread/<int:pk>/", views_chat.StaffChatThreadView.as_view(), name="staff-chat-thread"),
    path("staff/chat/read/", views_chat.StaffChatReadView.as_view(), name="staff-chat-read"),
    path("staff/tasks/", views_tasks.StaffTasksView.as_view(), name="staff-tasks"),
    path("staff/tasks/<int:pk>/", views_tasks.StaffTaskDetailView.as_view(), name="staff-task-detail"),
    path("staff/tasks/<int:pk>/done/", views_tasks.StaffTaskDoneView.as_view(), name="staff-task-done"),
    path("staff/tasks/<int:pk>/take/", views_tasks.StaffTaskTakeView.as_view(), name="staff-task-take"),
    path("staff/tasks/<int:pk>/leave/", views_tasks.StaffTaskLeaveView.as_view(), name="staff-task-leave"),
    path("staff/tasks/<int:pk>/thread/", views_tasks.StaffTaskThreadView.as_view(), name="staff-task-thread"),
    # Content: the venue's social feed (SMM / content capability).
    path("staff/feed/", views_feed.StaffFeedView.as_view(), name="staff-feed"),
    path("staff/feed/<int:pk>/", views_feed.StaffFeedDetailView.as_view(), name="staff-feed-detail"),
    path("staff/feed/<int:pk>/pin/", views_feed.StaffFeedPinView.as_view(), name="staff-feed-pin"),
    path("staff/feed/<int:pk>/unpin/", views_feed.StaffFeedUnpinView.as_view(), name="staff-feed-unpin"),
    path("staff/feed/<int:pk>/hide/", views_feed.StaffFeedHideView.as_view(), name="staff-feed-hide"),
    # Coupons: campaign CRUD (content capability) + issue/redeem (discount).
    path("staff/coupons/campaigns/", views_coupons.StaffCampaignsView.as_view(), name="staff-coupon-campaigns"),
    path("staff/coupons/campaigns/<int:pk>/", views_coupons.StaffCampaignDetailView.as_view(), name="staff-coupon-campaign-detail"),
    path("staff/coupons/issue/", views_coupons.StaffCouponIssueView.as_view(), name="staff-coupon-issue"),
    path("staff/coupons/redeem-preview/", views_coupons.StaffCouponPreviewView.as_view(), name="staff-coupon-redeem-preview"),
    path("staff/coupons/redeem/", views_coupons.StaffCouponRedeemView.as_view(), name="staff-coupon-redeem"),
    path("staff/coupons/<int:pk>/void-redemption/", views_coupons.StaffCouponVoidView.as_view(), name="staff-coupon-void"),
    # Content: storefront/theme settings.
    path("staff/venue/", views_venue.StaffVenueView.as_view(), name="staff-venue"),
    path("staff/venue/logo/", views_venue.StaffVenueImageView.as_view(kind="logo"), name="staff-venue-logo"),
    path("staff/venue/cover/", views_venue.StaffVenueImageView.as_view(kind="cover"), name="staff-venue-cover"),
    path("staff/venue/preview/", views_venue.StaffVenuePreviewView.as_view(), name="staff-venue-preview"),
    path("health/", views.HealthCheckView.as_view(), name="health"),
]
