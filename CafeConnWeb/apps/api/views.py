from datetime import timedelta

from django.contrib.auth import get_user_model
from django.http import Http404
from django.shortcuts import get_object_or_404
from django.db import transaction
from django.db.models import (
    Avg,
    Count,
    DecimalField,
    DurationField,
    ExpressionWrapper,
    F,
    Prefetch,
    Q,
    Sum,
)
from django.db.models.functions import ExtractHour
from django.utils import timezone
from rest_framework import decorators, permissions, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.authtoken.models import Token
from rest_framework.authtoken.views import ObtainAuthToken
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.api.events import (
    broadcast_attention_event,
    broadcast_order_event,
    broadcast_table_event,
    notify_order_alert_handled,
)
from apps.api.tenant import (
    RestaurantQuerysetMixin,
    capabilities_for_request,
    employee_for_request,
    restaurant_for_request,
)
from apps.core import push as web_push
from apps.core.services import (
    acknowledge_signal_on_table,
    apply_signal_to_table,
    reset_free_table,
    sync_order_status_from_items,
)
from apps.api.serializers import (
    AttentionSignalSerializer,
    EmployeeSerializer,
    MenuCategorySerializer,
    MenuItemSerializer,
    OrderItemSerializer,
    OrderSerializer,
    RestaurantSerializer,
    StaffPreferenceSerializer,
    TableSerializer,
)
from apps.core.menu_i18n import menu_item_labels
from apps.core.menu_visibility import (
    menu_has_client_items,
    menu_item_archived,
    menu_item_guest_visible,
)
from apps.core.models import (
    AttentionSignal,
    Employee,
    MenuCategory,
    MenuItem,
    Order,
    OrderEvent,
    OrderItem,
    PushSubscription,
    Restaurant,
    StaffPreference,
    StaffTask,
    Table,
    VenueSettings,
)

User = get_user_model()


class HealthCheckView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response({"status": "ok", "service": "CafeConnect API"})


class PlatformRestaurantsView(APIView):
    """Developer-owner control plane for restaurant provisioning."""

    permission_classes = [permissions.IsAdminUser]

    def get(self, request):
        if not request.user.is_superuser:
            raise PermissionDenied("Only the platform Owner can list restaurants.")
        restaurants = Restaurant.objects.annotate(
            staff_count=Count("memberships"), table_count=Count("tables", distinct=True)
        )
        return Response(
            {
                "restaurants": [
                    {
                        **RestaurantSerializer(item).data,
                        "staffCount": item.staff_count,
                        "tableCount": item.table_count,
                    }
                    for item in restaurants
                ]
            }
        )

    def post(self, request):
        if not request.user.is_superuser:
            raise PermissionDenied("Only the platform Owner can create restaurants.")
        serializer = RestaurantSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            restaurant = serializer.save()
            VenueSettings.objects.create(
                restaurant=restaurant,
                slug=restaurant.slug,
                name=restaurant.name,
            )
        return Response(
            RestaurantSerializer(restaurant).data, status=status.HTTP_201_CREATED
        )


class PlatformRestaurantDetailView(APIView):
    permission_classes = [permissions.IsAdminUser]

    def patch(self, request, pk):
        if not request.user.is_superuser:
            raise PermissionDenied("Only the platform Owner can edit restaurants.")
        restaurant = get_object_or_404(Restaurant, pk=pk)
        old_slug = restaurant.slug
        serializer = RestaurantSerializer(
            restaurant, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        restaurant = serializer.save()
        if restaurant.slug != old_slug:
            legacy = list(dict.fromkeys([*(restaurant.legacy_slugs or []), old_slug]))
            restaurant.legacy_slugs = legacy
            restaurant.save(update_fields=["legacy_slugs", "updated_at"])
            settings = VenueSettings.objects.get(restaurant=restaurant)
            settings.slug = restaurant.slug
            settings.save(update_fields=["slug", "updated_at"])
        return Response(RestaurantSerializer(restaurant).data)


class ThrottledObtainAuthToken(ObtainAuthToken):
    """Login endpoint with a brute-force brake: DRF ships obtain_auth_token
    without any throttle, so passwords could be guessed at wire speed."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"


def employee_for_user(user, restaurant=None):
    """Legacy helper for domain code; request handlers must pass a restaurant."""
    if not user or user.is_anonymous:
        return None
    queryset = Employee.objects.filter(user=user)
    if restaurant is not None:
        queryset = queryset.filter(restaurant=restaurant)
    else:
        queryset = queryset.filter(restaurant__slug="sissy-bar")
    return queryset.first()


# Kitchen and bar staff run their station screen only: they may move an order
# through the cooking pipeline but never complete/cancel it (delivery is the
# waiter's call) and never touch tables.
STATION_ROLES = {Employee.Role.KITCHEN, Employee.Role.BAR}
STATION_ALLOWED_ORDER_STATUSES = {Order.Status.NEW, Order.Status.COOKING, Order.Status.READY}


def role_for_user(user, restaurant=None):
    """Effective staff role: employee profile first, Django staff flag as admin
    fallback, waiter as the most-restricted-but-usable default."""
    employee = employee_for_user(user, restaurant)
    if employee:
        return employee.role
    if user.is_superuser or user.is_staff:
        return Employee.Role.ADMIN
    return Employee.Role.WAITER


def role_for_request(request):
    employee = employee_for_request(request)
    if employee:
        return employee.role
    if request.user.is_superuser:
        return Employee.Role.ADMIN
    return Employee.Role.WAITER


def log_order_event(order, request, action, detail=""):
    """Append one line to an order's audit trail (who did what)."""
    OrderEvent.objects.create(
        order=order,
        actor=employee_for_request(request),
        action=action,
        detail=detail[:255],
    )


def caps_for_user(user, restaurant=None):
    """Effective capabilities for a user: the role's base plus any extras a
    manager granted. Drives every permission gate below so a waiter who was
    given `bar` can work the bar and a bartender given `wait` can work tables.

    No employee profile: a Django superuser/staff account gets everything; a
    bare token falls back to a plain waiter."""
    employee = employee_for_user(user, restaurant)
    if employee:
        return employee.capabilities
    if user and (user.is_superuser or user.is_staff):
        return {"wait": True, "bar": True, "kitchen": True, "menu": True, "manage": True, "content": True, "discount": True, "reports": True}
    return {"wait": False, "bar": False, "kitchen": False, "menu": False, "manage": False, "content": False, "discount": False, "reports": False}


def flutter_table_status(status_value: str) -> str:
    # Django values and Flutter TableStatus names now match 1:1 (3 statuses).
    return {
        Table.Status.FREE: "free",
        Table.Status.OCCUPIED: "occupied",
        Table.Status.WAITING: "waiting",
    }.get(status_value, "free")


def flutter_order_status(status_value: str) -> str:
    status_value = Order.LEGACY_STATUS_ALIASES.get(status_value, status_value)
    return {
        Order.Status.AWAITING: "awaiting",
        Order.Status.NEW: "accepted",
        Order.Status.COOKING: "cooking",
        Order.Status.READY: "ready",
        Order.Status.COMPLETED: "completed",
        Order.Status.PAID: "completed",
    }.get(status_value, "accepted")


def serialize_for_flutter_menu(item: MenuItem) -> dict:
    labels = menu_item_labels(item)
    return {
        "id": str(item.id),
        "name": labels["name_en"],
        "nameIt": labels["name_it"],
        "description": labels["description_en"],
        "descriptionIt": labels["description_it"],
        "price": float(item.price),
        "category": labels["category_en"],
        "categoryIt": labels["category_it"],
        "categoryId": str(item.category_id),
        "imageUrl": item.image_url,
        "tags": item.tags,
        "prepTime": item.preparation_minutes,
        "available": item.is_available,
        "promo": item.is_promoted,
        "composition": item.composition,
        "allergens": item.allergens,
        "station": item.station,
    }


def serialize_for_flutter_table(table: Table) -> dict:
    # Bootstrap prefetches active orders (to_attr) — one query for all tables
    # instead of one per table. Fall back to a direct query for callers that
    # didn't prefetch.
    active = getattr(table, "active_orders", None)
    if active is not None:
        current_order = active[0] if active else None
    else:
        current_order = table.orders.exclude(status__in=[Order.Status.PAID, Order.Status.CANCELLED]).first()
    # Set by the bootstrap prefetch (to_attr); lets the app ack a signal that
    # was created before this device (re)connected.
    unacked = getattr(table, "unacked_signals", None) or []
    return {
        "id": str(table.id),
        "number": table.number,
        "name": table.label or f"Table {table.number:02d}",
        "seats": table.capacity,
        "guestCount": table.guest_count,
        "status": flutter_table_status(table.status),
        "colorTag": table.color_tag,
        "waiterId": str(table.waiter_id) if table.waiter_id else None,
        "waiter": table.waiter.name if table.waiter else "",
        "openedAt": table.opened_at.isoformat() if table.opened_at else None,
        "notes": [],
        "currentOrderId": str(current_order.id) if current_order else None,
        "attention": table.attention or None,
        "attentionReason": table.attention_reason,
        "attentionSignalId": str(unacked[0].id) if unacked else None,
        "attentionEscalated": unacked[0].alert_escalated if unacked else False,
        "ack": table.attention_acknowledged,
    }


def serialize_for_flutter_order(order: Order) -> dict:
    return {
        "id": str(order.id),
        "tableId": str(order.table_id),
        "status": flutter_order_status(order.status),
        "station": order.station_scope,
        "waiterId": str(order.employee_id) if order.employee_id else None,
        "waiterName": order.employee.name if order.employee else "",
        "createdAt": order.created_at.isoformat(),
        "acceptedAt": order.accepted_at.isoformat() if order.accepted_at else None,
        "updatedAt": order.updated_at.isoformat(),
        "note": order.notes,
        # Coupon snapshot (0 / '' when no coupon) — the app shows a
        # "− discount (coupon CODE)" line in the check.
        "discountAmount": float(order.discount_amount or 0),
        "couponCode": order.coupon.code if order.coupon_id else "",
        # Alert ladder L3: some device saw this AWAITING order unhandled for
        # 60s — every on-shift device highlights it.
        "alertEscalated": order.alert_escalated,
        "items": [
            {
                "id": str(item.id),
                "dishId": str(item.menu_item_id),
                "name": menu_item_labels(item.menu_item)["name_en"],
                "qty": item.quantity,
                "price": float(item.unit_price),
                "notes": item.notes,
                "station": item.station,
                "ready": item.ready,
                "done": item.done,
            }
            for item in order.items.all()
        ],
    }


class StaffBootstrapView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        restaurant = restaurant_for_request(request)
        preferences, _ = StaffPreference.objects.get_or_create(
            user=request.user, restaurant=restaurant
        )
        orders = (
            Order.objects.filter(restaurant=restaurant)
            .select_related("table", "coupon", "employee")
            .prefetch_related("items", "items__menu_item")
            .exclude(status__in=[Order.Status.PAID, Order.Status.CANCELLED])
            .order_by("-created_at")[:100]
        )
        # Recently-archived orders (a freed table's paid visits) so the app's
        # per-table history survives a reload/resync. The app caps it per table.
        history = (
            Order.objects.filter(restaurant=restaurant)
            .select_related("table", "coupon", "employee")
            .prefetch_related("items", "items__menu_item")
            .filter(status=Order.Status.PAID)
            .order_by("-created_at")[:80]
        )
        tables_qs = Table.objects.filter(restaurant=restaurant).select_related("waiter").prefetch_related(
            Prefetch(
                "attention_signals",
                queryset=AttentionSignal.objects.filter(
                    restaurant=restaurant, ack=False
                ).order_by("-created_at"),
                to_attr="unacked_signals",
            ),
            Prefetch(
                "orders",
                queryset=Order.objects.filter(restaurant=restaurant).exclude(
                    status__in=[Order.Status.PAID, Order.Status.CANCELLED]
                ).order_by("-created_at"),
                to_attr="active_orders",
            ),
        )
        employee = employee_for_request(request)
        restaurants = Restaurant.objects.filter(is_active=True)
        if not request.user.is_superuser:
            restaurants = restaurants.filter(memberships__user=request.user).distinct()
        return Response(
            {
                "restaurant": {
                    "id": str(restaurant.pk),
                    "name": restaurant.name,
                    "slug": restaurant.slug,
                    "timezone": restaurant.timezone,
                    "currency": restaurant.currency,
                },
                "availableRestaurants": [
                    {"id": str(item.pk), "name": item.name, "slug": item.slug}
                    for item in restaurants
                ],
                "isPlatformOwner": request.user.is_superuser,
                "currentUser": {
                    "id": str(request.user.id),
                    "employeeId": str(employee.pk) if employee else None,
                    "username": request.user.username,
                    "name": employee.name if employee else request.user.get_full_name(),
                    "role": role_for_request(request),
                    "capabilities": capabilities_for_request(request),
                    "isOnShift": employee.is_on_shift if employee else False,
                    # Kept as empty compatibility fields for older staff builds.
                    "shiftAreas": [],
                    "lastShiftAreas": [],
                },
                # Web Push feature flag + the applicationServerKey the browser
                # needs for pushManager.subscribe(). Disabled = keys not in env.
                "push": {
                    "enabled": web_push.push_configured(),
                    "publicKey": web_push.vapid_public_key(),
                },
                "tables": [serialize_for_flutter_table(table) for table in tables_qs],
                "menu": [
                    serialize_for_flutter_menu(item)
                    for item in MenuItem.objects.filter(restaurant=restaurant)
                    if "archived" not in (item.tags or [])
                ],
                "categories": MenuCategorySerializer(
                    MenuCategory.objects.filter(restaurant=restaurant), many=True
                ).data,
                "orders": [serialize_for_flutter_order(order) for order in orders],
                "history": [serialize_for_flutter_order(order) for order in history],
                "preferences": StaffPreferenceSerializer(preferences).data,
                "websocketPath": f"/ws/restaurants/{restaurant.slug}/staff/?token=<token>",
            }
        )


class StaffStatsView(APIView):
    """Manager/admin dashboard analytics, aggregated from the whole order
    history in the DB (not just the live orders a device happens to hold).

    The staff app computed these client-side from its in-memory order list,
    which only ever contains *active* orders — so once tables were cleared the
    numbers collapsed to ~0. The source of truth for a day's revenue is the
    database, hence this endpoint.
    """

    permission_classes = [permissions.IsAuthenticated]

    # Line revenue = unit_price * quantity, summed across items.
    _MONEY = DecimalField(max_digits=12, decimal_places=2)

    def get(self, request):
        if not capabilities_for_request(request)["reports"]:
            raise PermissionDenied("Only a manager or admin can view analytics.")
        restaurant = restaurant_for_request(request)

        now = timezone.localtime()
        today = now.date()
        yesterday = today - timedelta(days=1)
        line_total = ExpressionWrapper(F("unit_price") * F("quantity"), output_field=self._MONEY)

        def revenue_on(day):
            value = (
                OrderItem.objects.filter(
                    order__restaurant=restaurant, order__created_at__date=day
                )
                .exclude(order__status=Order.Status.CANCELLED)
                .aggregate(total=Sum(line_total))["total"]
            )
            return float(value or 0)

        def served_tables_on(day):
            return (
                Order.objects.filter(restaurant=restaurant, created_at__date=day)
                .exclude(status=Order.Status.CANCELLED)
                .values("table")
                .distinct()
                .count()
            )

        revenue_today = revenue_on(today)
        revenue_yesterday = revenue_on(yesterday)
        orders_today = (
            Order.objects.filter(restaurant=restaurant, created_at__date=today)
            .exclude(status=Order.Status.CANCELLED)
            .count()
        )
        served_today = served_tables_on(today)
        served_yesterday = served_tables_on(yesterday)
        avg_check_today = revenue_today / served_today if served_today else 0.0
        avg_check_yesterday = (
            revenue_yesterday / served_yesterday if served_yesterday else 0.0
        )

        # Revenue by hour (0..23), today.
        by_hour = [0.0] * 24
        rows = (
            OrderItem.objects.filter(
                order__restaurant=restaurant, order__created_at__date=today
            )
            .exclude(order__status=Order.Status.CANCELLED)
            .annotate(hour=ExtractHour("order__created_at"))
            .values("hour")
            .annotate(value=Sum(line_total))
        )
        for row in rows:
            if row["hour"] is not None:
                by_hour[int(row["hour"])] = float(row["value"] or 0)

        # Average prep time: how long ready items took (updated_at - created_at).
        prep = OrderItem.objects.filter(
            order__restaurant=restaurant, order__created_at__date=today, ready=True
        ).aggregate(
            avg=Avg(
                ExpressionWrapper(
                    F("updated_at") - F("created_at"), output_field=DurationField()
                )
            )
        )["avg"]
        avg_prep_min = int(prep.total_seconds() // 60) if prep else 0

        # Orders still open longer than 20 minutes = running late.
        late_threshold = now - timedelta(minutes=20)
        delayed = (
            Order.objects.filter(restaurant=restaurant).exclude(
                status__in=[Order.Status.PAID, Order.Status.CANCELLED]
            )
            .filter(created_at__lt=late_threshold)
            .count()
        )

        total_tables = Table.objects.filter(restaurant=restaurant).count()
        active_tables = Table.objects.filter(restaurant=restaurant).exclude(
            status=Table.Status.FREE
        ).count()

        # Per-waiter breakdown for today: orders + tables from the Order rows,
        # revenue from their items. Keyed by the order's employee (the waiter
        # who placed or approved it); unattributed orders are skipped.
        waiter_stats = {}
        for row in (
            Order.objects.filter(restaurant=restaurant, created_at__date=today)
            .exclude(status=Order.Status.CANCELLED)
            .values("employee", "employee__name")
            .annotate(orders=Count("id"), tables=Count("table", distinct=True))
        ):
            emp = row["employee"]
            if emp is None:
                continue
            waiter_stats[emp] = {
                "id": str(emp),
                "name": row["employee__name"] or "—",
                "orders": row["orders"],
                "tables": row["tables"],
                "revenue": 0.0,
            }
        for row in (
            OrderItem.objects.filter(
                order__restaurant=restaurant, order__created_at__date=today
            )
            .exclude(order__status=Order.Status.CANCELLED)
            .values("order__employee")
            .annotate(revenue=Sum(line_total))
        ):
            emp = row["order__employee"]
            if emp in waiter_stats:
                waiter_stats[emp]["revenue"] = round(float(row["revenue"] or 0), 2)
        by_waiter = sorted(
            waiter_stats.values(), key=lambda w: w["revenue"], reverse=True
        )

        def pct(today_value, prev_value):
            if not prev_value:
                return None
            return round((today_value - prev_value) / prev_value * 100)

        # What's actually selling today — top positions by quantity, so the
        # manager sees at a glance what to push and what to prep.
        top_items = list(
            OrderItem.objects.filter(
                order__restaurant=restaurant, order__created_at__date=today
            )
            .exclude(order__status=Order.Status.CANCELLED)
            .values("menu_item__name", "menu_item__category__name")
            .annotate(
                qty=Sum("quantity"),
                item_revenue=Sum(
                    ExpressionWrapper(
                        F("unit_price") * F("quantity"), output_field=self._MONEY
                    )
                ),
            )
            .order_by("-qty")[:5]
        )

        return Response(
            {
                "revenueToday": round(revenue_today, 2),
                "revenueYesterday": round(revenue_yesterday, 2),
                "revenueDeltaPct": pct(revenue_today, revenue_yesterday),
                "ordersToday": orders_today,
                "avgCheck": round(avg_check_today, 2),
                "avgCheckDeltaPct": pct(avg_check_today, avg_check_yesterday),
                "servedTables": served_today,
                "activeTables": active_tables,
                "totalTables": total_tables,
                "freeTables": max(total_tables - active_tables, 0),
                "avgPrepMinutes": avg_prep_min,
                "delayedOrders": delayed,
                "revenueByHour": by_hour,
                "byWaiter": by_waiter,
                "topItems": [
                    {
                        "name": r["menu_item__name"],
                        "category": r["menu_item__category__name"] or "",
                        "qty": int(r["qty"] or 0),
                        "revenue": float(r["item_revenue"] or 0),
                    }
                    for r in top_items
                ],
                "generatedAt": now.isoformat(),
            }
        )


class StaffOrderHistoryView(APIView):
    """Manager/admin order history, including closed/paid orders."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if not capabilities_for_request(request)["reports"]:
            raise PermissionDenied("Only a manager or admin can view order history.")
        restaurant = restaurant_for_request(request)

        orders = (
            Order.objects.filter(restaurant=restaurant)
            .select_related("table", "employee")
            .prefetch_related("items", "items__menu_item")
            .order_by("-created_at")
        )
        return Response(
            {
                "orders": [
                    {
                        "id": str(order.id),
                        "tableNumber": order.table.number,
                        "status": order.status,
                        "source": order.source,
                        "station": order.station_scope,
                        "guestName": order.guest_name,
                        "employee": order.employee.name if order.employee else "",
                        "createdAt": order.created_at.isoformat(),
                        "updatedAt": order.updated_at.isoformat(),
                        "total": float(order.total),
                        "items": [
                            {
                                "name": menu_item_labels(item.menu_item)["name_en"],
                                "qty": item.quantity,
                                "station": item.station,
                                "ready": item.ready,
                                "done": item.done,
                            }
                            for item in order.items.all()
                        ],
                    }
                    for order in orders
                ]
            }
        )


class StaffTableHistoryView(APIView):
    """One table's order history, a single calendar day at a time, for any
    staff member (the floor shares one view — not scoped to a waiter).

    Read-only, no schema change. Returns the distinct days that have orders
    (newest first) so the client can page day-by-day without ever landing on
    an empty day, plus the orders for the requested day (default: newest).
    Bounded to the most recent 300 orders per table for cost safety.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        restaurant = restaurant_for_request(request)
        table_id = request.query_params.get("table")
        if not table_id:
            return Response({"detail": "table is required"}, status=status.HTTP_400_BAD_REQUEST)

        recent = (
            Order.objects.filter(restaurant=restaurant, table_id=table_id)
            .exclude(status=Order.Status.CANCELLED)
            .select_related("table")
            .prefetch_related("items", "items__menu_item")
            .order_by("-created_at")[:300]
        )
        # Group by *local* calendar day (avoids the UTC __date mismatch), keeping
        # the newest-first order the queryset already gives us.
        groups: dict[str, list] = {}
        for order in recent:
            day = timezone.localtime(order.created_at).date().isoformat()
            groups.setdefault(day, []).append(order)

        dates = list(groups.keys())
        want = request.query_params.get("date")
        if want not in groups:
            want = dates[0] if dates else None
        day_orders = groups.get(want, []) if want else []

        return Response(
            {
                "tableId": str(table_id),
                "date": want,
                "dates": dates,
                "orders": [serialize_for_flutter_order(o) for o in day_orders],
            }
        )


class MenuCategoryViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    """The owner's menu categories (name + color + order). Any staff can read
    them; renaming/recoloring is a manager/admin action."""

    queryset = MenuCategory.objects.annotate(
        item_count=Count("items", filter=Q(items__is_available=True))
    )
    serializer_class = MenuCategorySerializer
    permission_classes = [permissions.IsAuthenticated]

    def _require_manage(self):
        if not capabilities_for_request(self.request)["manage"]:
            raise PermissionDenied("Only a manager or admin can edit menu categories.")

    def perform_create(self, serializer):
        self._require_manage()
        serializer.save(restaurant=self.get_restaurant())

    def perform_update(self, serializer):
        self._require_manage()
        serializer.save()

    def perform_destroy(self, instance):
        self._require_manage()
        if instance.items.exists():
            raise ValidationError(
                "Reassign or delete menu items before deleting this category."
            )
        instance.delete()


class MenuItemViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    queryset = MenuItem.objects.select_related("category").order_by("-is_available", "name")
    serializer_class = MenuItemSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_fields = ["category", "is_available"]
    search_fields = ["name", "description", "category__name"]
    ordering_fields = ["name", "category__name", "price", "updated_at"]

    def _public_menu_has_client_items(self):
        if not hasattr(self, "_has_public_client_menu"):
            self._has_public_client_menu = menu_has_client_items(
                self.get_queryset().only("tags", "is_available")
            )
        return self._has_public_client_menu

    def _visible_to_request(self, item):
        if menu_item_archived(item):
            return False
        if self.request.user and self.request.user.is_authenticated:
            return True
        return menu_item_guest_visible(
            item,
            has_client_menu=self._public_menu_has_client_items(),
        )

    def list(self, request, *args, **kwargs):
        queryset = [
            item
            for item in self.filter_queryset(self.get_queryset())
            if self._visible_to_request(item)
        ]
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)

    def get_object(self):
        obj = super().get_object()
        if not self._visible_to_request(obj):
            raise Http404
        return obj

    @decorators.action(detail=True, methods=["post"], url_path="toggle-popular")
    def toggle_popular(self, request, pk=None):
        """Pin/unpin an item on the waiter 'Popular' shelf (hold on a tile in
        the app). Deliberately open to ANY authenticated staff — pinning a
        bestseller is floor work, not menu management."""
        if not request.user or not request.user.is_authenticated:
            raise PermissionDenied("Sign in to pin items.")
        item = self.get_object()
        tags = list(item.tags or [])
        if "popular" in tags:
            tags.remove("popular")
        else:
            tags.append("popular")
        item.tags = tags
        item.save(update_fields=["tags", "updated_at"])
        return Response(MenuItemSerializer(item).data)

    def _require_menu_cap(self):
        # Changing the menu (e.g. the in/out-of-stock toggle) is a granted
        # capability now, not a free-for-all for anyone with a token.
        if not capabilities_for_request(self.request)["menu"]:
            raise PermissionDenied("You need the menu capability to change menu items.")

    def perform_create(self, serializer):
        self._require_menu_cap()
        serializer.save(restaurant=self.get_restaurant())

    def perform_update(self, serializer):
        self._require_menu_cap()
        serializer.save()

    def perform_destroy(self, instance):
        self._require_menu_cap()
        if instance.order_items.exists():
            tags = list(instance.tags or [])
            if "archived" not in tags:
                tags.append("archived")
            instance.tags = tags
            instance.is_available = False
            instance.save(update_fields=["tags", "is_available", "updated_at"])
            return
        instance.delete()


class TableViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    queryset = Table.objects.all()
    serializer_class = TableSerializer
    # Staff-only, reads included: the guest page is fully server-rendered and
    # never calls this API, so there is no reason to expose the live floor
    # state (statuses, waiter names) to anyone unauthenticated.
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["status"]
    search_fields = ["number", "label"]
    ordering_fields = ["number", "updated_at"]

    def perform_update(self, serializer):
        # Tables are the floor's domain: someone without the waiter capability
        # (a pure station worker) must not be able to clear or re-status one.
        if not capabilities_for_request(self.request)["wait"]:
            raise PermissionDenied("You need the waiter capability to change tables.")
        table = serializer.save()
        if table.status == Table.Status.FREE:
            table = reset_free_table(table)
        elif table.opened_at is None:
            table.opened_at = timezone.now()
            table.save(update_fields=["opened_at", "updated_at"])
        broadcast_table_event(table)

    @decorators.action(detail=True, methods=["post"], url_path="claim")
    def claim(self, request, pk=None):
        if not capabilities_for_request(request)["wait"]:
            raise PermissionDenied("You need the Floor capability to claim a table.")
        table = self.get_object()
        employee = employee_for_request(request)
        if table.waiter_id not in (None, employee.pk if employee else None):
            return Response(
                {"detail": f"{table} is already assigned to {table.waiter.name}."},
                status=status.HTTP_409_CONFLICT,
            )
        table.waiter = employee
        table.save(update_fields=["waiter", "updated_at"])
        broadcast_table_event(table)
        return Response(TableSerializer(table).data)

    @decorators.action(detail=True, methods=["post"], url_path="assign")
    def assign(self, request, pk=None):
        if not capabilities_for_request(request)["manage"]:
            raise PermissionDenied("Only a manager can assign tables.")
        table = self.get_object()
        employee_id = request.data.get("employee")
        employee = None
        if employee_id is not None:
            employee = get_object_or_404(
                Employee,
                restaurant=self.get_restaurant(),
                pk=employee_id,
            )
            if not employee.capabilities["wait"]:
                raise ValidationError("The employee needs the Floor capability.")
        table.waiter = employee
        table.save(update_fields=["waiter", "updated_at"])
        broadcast_table_event(table)
        return Response(TableSerializer(table).data)


class OrderViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    queryset = (
        Order.objects.select_related("table", "employee", "employee__user", "coupon")
        .prefetch_related("items", "items__menu_item")
        .all()
    )
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["status", "table"]
    search_fields = ["guest_name", "notes", "table__number"]
    ordering_fields = ["created_at", "updated_at", "status"]

    def perform_create(self, serializer):
        if not capabilities_for_request(self.request)["wait"]:
            raise PermissionDenied("You need the Floor capability to create an order.")
        employee = employee_for_request(self.request)
        order = serializer.save(
            restaurant=self.get_restaurant(),
            employee=employee,
            source=Order.Source.STAFF_APP,
        )
        # A waiter placed the order himself — the table is simply occupied
        # (WAITING is reserved for "guests are waiting for a waiter"), and it
        # becomes *his* table so analytics attribute it to him.
        order.table.status = Table.Status.OCCUPIED
        order.table.opened_at = order.table.opened_at or timezone.now()
        if employee is not None and order.table.waiter_id is None:
            order.table.waiter = employee
        order.table.save(update_fields=["status", "opened_at", "waiter", "updated_at"])
        log_order_event(order, self.request, OrderEvent.Action.CREATED)
        broadcast_order_event("created", order)
        broadcast_table_event(order.table)

    def perform_update(self, serializer):
        new_status = serializer.validated_data.get("status")
        if new_status is not None:
            caps = capabilities_for_request(self.request)
            # A pure station worker (no waiter capability) may only move an
            # order through the cooking pipeline — completing (= delivery) is
            # the waiter's call.
            if not caps["wait"] and new_status not in STATION_ALLOWED_ORDER_STATUSES:
                raise PermissionDenied(
                    "Station staff can only move an order to cooking or ready. "
                    "Completing (delivery) is a waiter action."
                )
            if not caps["wait"] and new_status == Order.Status.READY:
                # Mark ready only the items for the station(s) this person
                # actually covers — a bar+kitchen worker readies both.
                order = serializer.instance
                stations = [s for s in ("kitchen", "bar") if caps[s]]
                order.items.filter(station__in=stations).update(ready=True, updated_at=timezone.now())
                order = sync_order_status_from_items(order)
                log_order_event(
                    order, self.request, OrderEvent.Action.ITEM_READY,
                    "/".join(stations),
                )
                broadcast_order_event("updated", order)
                return
            if new_status == Order.Status.COMPLETED and serializer.instance.items.filter(done=False).exists():
                raise PermissionDenied("Mark each item delivered before completing the order.")
            if new_status == Order.Status.CANCELLED and not caps["manage"]:
                raise PermissionDenied("Only a manager or admin can cancel an order.")
        order = serializer.save()
        if new_status is not None:
            log_order_event(
                order, self.request, OrderEvent.Action.STATUS,
                flutter_order_status(order.status),
            )
        broadcast_order_event("updated", order)

    @decorators.action(detail=False, methods=["get"], url_path="station-feed")
    def station_feed(self, request):
        station = request.query_params.get("station")
        if station not in {"kitchen", "bar"}:
            return Response({"detail": "station must be kitchen or bar"}, status=status.HTTP_400_BAD_REQUEST)
        if not capabilities_for_request(request)[station]:
            raise PermissionDenied(f"You need the {station.title()} capability.")

        orders = (
            self.get_queryset()
            .filter(items__station=station)
            # AWAITING orders are still pending a waiter's approval — the
            # station must not see them until they are confirmed.
            .exclude(status__in=[Order.Status.AWAITING, Order.Status.PAID, Order.Status.CANCELLED])
            .distinct()
        )
        data = []
        for order in orders:
            payload = OrderSerializer(order).data
            payload["items"] = [item for item in payload["items"] if item["station"] == station]
            data.append(payload)
        return Response(data)

    @decorators.action(detail=True, methods=["post"], url_path="confirm")
    def confirm(self, request, pk=None):
        """Waiter/manager approves a pending guest order: it enters the
        kitchen/bar pipeline (awaiting → new) and the stations see it for the
        first time. Stations themselves can't confirm."""
        if not capabilities_for_request(request)["wait"]:
            raise PermissionDenied("You need the waiter capability to confirm an order.")
        order = self.get_object()
        if order.status != Order.Status.AWAITING:
            raise PermissionDenied("Only a pending order can be confirmed.")
        employee = employee_for_request(request)
        order.status = Order.Status.NEW
        # Prep timer starts now — when the waiter accepts — not when the guest
        # placed the order.
        order.accepted_at = timezone.now()
        order.employee = employee or order.employee
        order.save(update_fields=["status", "accepted_at", "employee", "updated_at"])

        # The waiter who approved the guest order owns the table now, so its
        # sales attribute to him in the analytics.
        table = order.table
        table_fields = ["updated_at"]
        if table.status == Table.Status.WAITING:
            table.status = Table.Status.OCCUPIED
            table_fields.append("status")
        if employee is not None and table.waiter_id is None:
            table.waiter = employee
            table_fields.append("waiter")
        table.save(update_fields=table_fields)

        log_order_event(order, request, OrderEvent.Action.CONFIRMED)
        broadcast_order_event("updated", order)
        broadcast_table_event(table)
        # The alert is handled — background devices close their OS banner.
        notify_order_alert_handled(order)
        return Response(OrderSerializer(order).data)

    @decorators.action(detail=True, methods=["post"], url_path="reject")
    def reject(self, request, pk=None):
        """Waiter/manager declines a pending guest order (wrong/duplicate): it
        is cancelled and never reaches the kitchen/bar."""
        if not capabilities_for_request(request)["wait"]:
            raise PermissionDenied("You need the waiter capability to reject an order.")
        order = self.get_object()
        if order.status != Order.Status.AWAITING:
            raise PermissionDenied("Only a pending order can be rejected.")
        order.status = Order.Status.CANCELLED
        order.save(update_fields=["status", "updated_at"])

        # The guest submission put the table into WAITING; with the order gone
        # nothing is pending anymore, so mirror confirm and settle the table
        # back to OCCUPIED. Skip when an attention badge (call/bill) is active:
        # that signal owns the WAITING state until a waiter acknowledges it.
        table = order.table
        if (
            table.status == Table.Status.WAITING
            and table.attention == Table.Attention.NONE
        ):
            table.status = Table.Status.OCCUPIED
            table.save(update_fields=["status", "updated_at"])

        log_order_event(order, request, OrderEvent.Action.REJECTED)
        broadcast_order_event("updated", order)
        broadcast_table_event(order.table)
        notify_order_alert_handled(order)
        return Response(OrderSerializer(order).data)

    @decorators.action(detail=True, methods=["post"], url_path="escalate")
    def escalate(self, request, pk=None):
        """Alert ladder L3 for a guest order stuck in AWAITING. Idempotent;
        an order that already left AWAITING can't be escalated."""
        order = self.get_object()
        if order.status != Order.Status.AWAITING:
            return Response(
                {"detail": "This order was already handled."},
                status=status.HTTP_409_CONFLICT,
            )
        if not order.alert_escalated:
            order.alert_escalated = True
            order.save(update_fields=["alert_escalated", "updated_at"])
            broadcast_order_event("escalated", order)
        return Response(OrderSerializer(order).data)

    @decorators.action(detail=True, methods=["get"], url_path="events")
    def events(self, request, pk=None):
        """The order's audit trail: who did what, oldest first."""
        order = self.get_object()
        return Response(
            [
                {
                    "id": e.id,
                    "actor": e.actor.name if e.actor else "",
                    "action": e.action,
                    "detail": e.detail,
                    "createdAt": e.created_at.isoformat(),
                }
                for e in order.events.select_related("actor").all()
            ]
        )


class OrderItemViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    restaurant_field = "order__restaurant"
    create_restaurant_field = None
    queryset = OrderItem.objects.select_related("order", "menu_item").all()
    serializer_class = OrderItemSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["station", "ready", "done", "order"]
    ordering_fields = ["created_at", "updated_at"]

    def perform_update(self, serializer):
        item = serializer.save()
        broadcast_order_event("updated", item.order)

    @decorators.action(detail=True, methods=["post"], url_path="mark-ready")
    def mark_ready(self, request, pk=None):
        item = self.get_object()
        if not capabilities_for_request(request).get(item.station, False):
            raise PermissionDenied(
                f"You need the {item.station.title()} capability to mark this item ready."
            )
        item.ready = True
        item.save(update_fields=["ready", "updated_at"])
        sync_order_status_from_items(item.order)
        log_order_event(item.order, request, OrderEvent.Action.ITEM_READY, item.menu_item.name)
        broadcast_order_event("updated", item.order)
        return Response(OrderItemSerializer(item).data)

    @decorators.action(detail=True, methods=["post"], url_path="toggle-done")
    def toggle_done(self, request, pk=None):
        # "done" = delivered to the guest — that's the waiter's confirmation,
        # not something a pure station worker flips (and un-flips) from the pass.
        if not capabilities_for_request(request)["wait"]:
            raise PermissionDenied("You need the waiter capability to mark an item as delivered.")
        item = self.get_object()
        item.done = not item.done
        if item.done:
            item.ready = True
        item.save(update_fields=["ready", "done", "updated_at"])
        sync_order_status_from_items(item.order)
        log_order_event(
            item.order,
            request,
            OrderEvent.Action.ITEM_DELIVERED if item.done else OrderEvent.Action.ITEM_UNDELIVERED,
            item.menu_item.name,
        )
        broadcast_order_event("updated", item.order)
        return Response(OrderItemSerializer(item).data)


class AttentionSignalViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    queryset = AttentionSignal.objects.select_related("table", "acknowledged_by", "acknowledged_by__user").all()
    serializer_class = AttentionSignalSerializer
    filterset_fields = ["signal_type", "ack", "table"]
    ordering_fields = ["created_at", "acked_at"]

    def get_permissions(self):
        if self.action == "create":
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated()]

    def get_throttles(self):
        # Anonymous guests may create signals, but each one pings every staff
        # device — keep the anonymous path on a short leash.
        if self.action == "create":
            self.throttle_scope = "attention-create"
            return [ScopedRateThrottle()]
        return super().get_throttles()

    @transaction.atomic
    def perform_create(self, serializer):
        signal = serializer.save(restaurant=self.get_restaurant())
        table = apply_signal_to_table(signal, signal.table)
        broadcast_attention_event("created", signal)
        broadcast_table_event(table)

    @decorators.action(detail=True, methods=["post"], url_path="ack")
    def ack(self, request, pk=None):
        signal = self.get_object()
        employee = employee_for_request(request)
        signal.acknowledge(employee)
        table = acknowledge_signal_on_table(signal.table)
        broadcast_attention_event("acked", signal)
        broadcast_table_event(table)
        return Response(AttentionSignalSerializer(signal).data)

    @decorators.action(detail=True, methods=["post"], url_path="escalate")
    def escalate(self, request, pk=None):
        """Alert ladder L3: a device saw this signal go unhandled for 60s.
        Idempotent — only the first caller flags and broadcasts; a signal
        already acked can't be escalated (the alert lifecycle is over)."""
        signal = self.get_object()
        if signal.ack:
            return Response(
                {"detail": "This signal was already handled."},
                status=status.HTTP_409_CONFLICT,
            )
        if not signal.alert_escalated:
            signal.alert_escalated = True
            signal.save(update_fields=["alert_escalated"])
            broadcast_attention_event("escalated", signal)
        return Response(AttentionSignalSerializer(signal).data)


class EmployeeViewSet(RestaurantQuerysetMixin, viewsets.ModelViewSet):
    queryset = Employee.objects.select_related("user").all()
    serializer_class = EmployeeSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["role", "is_on_shift"]
    search_fields = ["name", "user__username", "user__email"]
    ordering_fields = ["name", "role", "updated_at"]

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if not capabilities_for_request(request)["manage"]:
            raise PermissionDenied("Only a manager or admin can manage staff.")

    def _guard_owner_target(self, employee):
        """Owner (admin/superuser) accounts are managed from /system-admin/
        only — a manager must not be able to edit, demote or lock out the
        owner from the app."""
        if employee.role == Employee.Role.ADMIN or employee.user.is_superuser:
            raise PermissionDenied(
                "Owner accounts are managed from the system admin."
            )

    def perform_update(self, serializer):
        target = self.get_object()
        self._guard_owner_target(target)
        # A manager may re-role staff between floor/station/manager, but
        # cannot mint admins from the app.
        if serializer.validated_data.get("role") == Employee.Role.ADMIN:
            raise PermissionDenied("The admin role is granted from the system admin.")
        actor = employee_for_request(self.request)
        next_role = serializer.validated_data.get("role", target.role)
        next_can_manage = serializer.validated_data.get(
            "can_manage", target.can_manage
        )
        if (
            actor is not None
            and actor.pk == target.pk
            and next_role not in {Employee.Role.MANAGER, Employee.Role.ADMIN}
            and not next_can_manage
        ):
            raise PermissionDenied(
                "Another manager or the Owner must remove your management access."
            )
        serializer.save()

    def perform_destroy(self, instance):
        self._guard_owner_target(instance)
        instance.delete()

    @decorators.action(detail=True, methods=["post"], url_path="credentials")
    def credentials(self, request, pk=None):
        """Manager/admin: change a staff member's login — username and/or a
        new password. Blank fields are left unchanged. Changing the password
        also revokes the member's auth token so stale sessions drop."""
        employee = self.get_object()
        self._guard_owner_target(employee)
        user = employee.user
        username = (request.data.get("username") or "").strip()
        password = request.data.get("password") or ""

        if username and username.lower() != user.username.lower():
            if (
                User.objects.filter(username__iexact=username)
                .exclude(pk=user.pk)
                .exists()
            ):
                return Response(
                    {"detail": "That username is already taken."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            user.username = username
        if password:
            if len(password) < 6:
                return Response(
                    {"detail": "Password must be at least 6 characters."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            user.set_password(password)
            Token.objects.filter(user=user).delete()
        user.save()
        return Response(EmployeeSerializer(employee).data)


class StaffAccountCreateView(APIView):
    """Manager/admin: create a login account (Django user + Employee profile)
    for a staff member. The password is set here; the auth token is issued
    lazily on the member's first login (POST /api/auth/token/)."""

    permission_classes = [permissions.IsAuthenticated]

    # A manager may staff the floor and stations, and add other managers, but
    # not mint admins/superusers — that stays a deliberate back-office action.
    CREATABLE_ROLES = {
        Employee.Role.WAITER,
        Employee.Role.KITCHEN,
        Employee.Role.BAR,
        Employee.Role.MANAGER,
        Employee.Role.SMM,
    }

    def post(self, request):
        if not capabilities_for_request(request)["manage"]:
            raise PermissionDenied("Only a manager or admin can create accounts.")
        restaurant = restaurant_for_request(request)

        username = (request.data.get("username") or "").strip()
        password = request.data.get("password") or ""
        first_name = (request.data.get("first_name") or "").strip()
        last_name = (request.data.get("last_name") or "").strip()
        name = (request.data.get("name") or "").strip()
        if not name:
            name = " ".join(part for part in [first_name, last_name] if part).strip()
        role = request.data.get("role") or Employee.Role.WAITER

        errors = {}
        if not username:
            errors["username"] = "Username is required."
        if len(password) < 6:
            errors["password"] = "Password must be at least 6 characters."
        if not name:
            errors["name"] = "Name is required."
        if role not in self.CREATABLE_ROLES:
            errors["role"] = "Unsupported role."
        if not errors and User.objects.filter(username__iexact=username).exists():
            errors["username"] = "That username is already taken."
        if errors:
            return Response(errors, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            user = User.objects.create_user(
                username=username,
                password=password,
                first_name=first_name or name,
                last_name=last_name,
                is_staff=(role == Employee.Role.MANAGER),
            )
            employee = Employee.objects.create(
                restaurant=restaurant,
                user=user,
                name=name,
                role=role,
                is_on_shift=False,
            )
        return Response(EmployeeSerializer(employee).data, status=status.HTTP_201_CREATED)


class StaffShiftView(APIView):
    """Self-service shift toggle. The app's "On shift" switch binds here —
    the same tap that unlocks audio/notification permissions client-side.
    Alerts and web pushes only ever target on-shift employees."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        employee = employee_for_request(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        wants_on = bool(request.data.get("on"))
        capabilities = capabilities_for_request(request)
        allowed_areas = {
            area
            for area, capability in (
                ("floor", "wait"),
                ("bar", "bar"),
                ("kitchen", "kitchen"),
            )
            if capabilities[capability]
        }
        if wants_on and not allowed_areas:
            raise PermissionDenied(
                "A shift requires the Floor, Bar, or Kitchen capability."
            )

        if wants_on:
            employee.is_on_shift = True
        else:
            active_tables = Table.objects.filter(
                restaurant=employee.restaurant, waiter=employee
            ).exclude(status=Table.Status.FREE).count()
            active_tasks = employee.tasks_assigned.filter(
                status__in=[StaffTask.Status.OPEN, StaffTask.Status.IN_PROGRESS]
            ).count()
            unhandled_calls = AttentionSignal.objects.filter(
                restaurant=employee.restaurant,
                table__waiter=employee,
                ack=False,
            ).count()
            handoff = {
                "tables": active_tables,
                "tasks": active_tasks,
                "calls": unhandled_calls,
            }
            if any(handoff.values()) and not bool(request.data.get("force")):
                return Response(
                    {"detail": "Hand off active work before ending the shift.", "handoff": handoff},
                    status=status.HTTP_409_CONFLICT,
                )
            if any(handoff.values()) and not capabilities["manage"]:
                raise PermissionDenied("Only a manager can force an active shift to end.")
            employee.is_on_shift = False
        employee.save(update_fields=["is_on_shift", "updated_at"])
        return Response(
            {
                "on": employee.is_on_shift,
                "areas": [],
                "preset": [],
            }
        )


class StaffPushSubscriptionView(APIView):
    """Web-Push subscription lifecycle, bound to the signed-in employee.
    POST upserts (a browser re-subscribing re-binds its unique endpoint);
    DELETE removes this device's subscription on shift-off."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        employee = employee_for_request(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        endpoint = (request.data.get("endpoint") or "").strip()
        keys = request.data.get("keys") or {}
        p256dh = (keys.get("p256dh") or request.data.get("p256dh") or "").strip()
        auth = (keys.get("auth") or request.data.get("auth") or "").strip()
        if not endpoint or not p256dh or not auth:
            return Response(
                {"detail": "endpoint, p256dh and auth are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        _, created = PushSubscription.objects.update_or_create(
            endpoint=endpoint,
            defaults={
                "restaurant": employee.restaurant,
                "employee": employee,
                "p256dh": p256dh,
                "auth": auth,
                "user_agent": (request.META.get("HTTP_USER_AGENT") or "")[:255],
            },
        )
        return Response(
            {"ok": True, "created": created},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def delete(self, request):
        employee = employee_for_request(request)
        endpoint = (request.data.get("endpoint") or "").strip()
        if not endpoint:
            return Response(
                {"detail": "endpoint is required."}, status=status.HTTP_400_BAD_REQUEST
            )
        queryset = PushSubscription.objects.filter(endpoint=endpoint)
        if employee is not None and not capabilities_for_request(request)["manage"]:
            queryset = queryset.filter(employee=employee)
        queryset.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class StaffPreferenceView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        preferences, _ = StaffPreference.objects.get_or_create(
            user=request.user, restaurant=restaurant_for_request(request)
        )
        return Response(StaffPreferenceSerializer(preferences).data)

    def patch(self, request):
        preferences, _ = StaffPreference.objects.get_or_create(
            user=request.user, restaurant=restaurant_for_request(request)
        )
        serializer = StaffPreferenceSerializer(preferences, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
