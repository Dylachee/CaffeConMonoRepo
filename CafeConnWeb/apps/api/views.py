from datetime import timedelta

from django.db import transaction
from django.db.models import (
    Avg,
    DecimalField,
    DurationField,
    ExpressionWrapper,
    F,
    Prefetch,
    Sum,
)
from django.db.models.functions import ExtractHour
from django.utils import timezone
from rest_framework import decorators, permissions, status, viewsets
from rest_framework.exceptions import PermissionDenied
from rest_framework.authtoken.views import ObtainAuthToken
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.api.events import broadcast_attention_event, broadcast_order_event, broadcast_table_event
from apps.core.services import (
    acknowledge_signal_on_table,
    apply_signal_to_table,
    reset_free_table,
    sync_order_status_from_items,
)
from apps.api.serializers import (
    AttentionSignalSerializer,
    EmployeeSerializer,
    MenuItemSerializer,
    OrderItemSerializer,
    OrderSerializer,
    StaffPreferenceSerializer,
    TableSerializer,
)
from apps.core.menu_i18n import menu_item_labels
from apps.core.models import AttentionSignal, Employee, MenuItem, Order, OrderItem, StaffPreference, Table


class HealthCheckView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response({"status": "ok", "service": "CafeConnect API"})


class ThrottledObtainAuthToken(ObtainAuthToken):
    """Login endpoint with a brute-force brake: DRF ships obtain_auth_token
    without any throttle, so passwords could be guessed at wire speed."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"


def employee_for_user(user):
    if not user or user.is_anonymous:
        return None
    try:
        return user.employee_profile
    except Employee.DoesNotExist:
        return None


# Kitchen and bar staff run their station screen only: they may move an order
# through the cooking pipeline but never complete/cancel it (delivery is the
# waiter's call) and never touch tables.
STATION_ROLES = {Employee.Role.KITCHEN, Employee.Role.BAR}
STATION_ALLOWED_ORDER_STATUSES = {Order.Status.NEW, Order.Status.COOKING, Order.Status.READY}


def role_for_user(user):
    """Effective staff role: employee profile first, Django staff flag as admin
    fallback, waiter as the most-restricted-but-usable default."""
    employee = employee_for_user(user)
    if employee:
        return employee.role
    if user.is_superuser or user.is_staff:
        return Employee.Role.ADMIN
    return Employee.Role.WAITER


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
        "waiter": table.waiter.name if table.waiter else "",
        "openedAt": table.opened_at.isoformat() if table.opened_at else None,
        "notes": [],
        "currentOrderId": str(current_order.id) if current_order else None,
        "attention": table.attention or None,
        "attentionReason": table.attention_reason,
        "attentionSignalId": str(unacked[0].id) if unacked else None,
        "ack": table.attention_acknowledged,
    }


def serialize_for_flutter_order(order: Order) -> dict:
    return {
        "id": str(order.id),
        "tableId": str(order.table_id),
        "status": flutter_order_status(order.status),
        "station": order.station_scope,
        "createdAt": order.created_at.isoformat(),
        "updatedAt": order.updated_at.isoformat(),
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
        preferences, _ = StaffPreference.objects.get_or_create(user=request.user)
        orders = (
            Order.objects.select_related("table")
            .prefetch_related("items", "items__menu_item")
            .exclude(status__in=[Order.Status.PAID, Order.Status.CANCELLED])
            .order_by("-created_at")[:100]
        )
        tables_qs = Table.objects.select_related("waiter").prefetch_related(
            Prefetch(
                "attention_signals",
                queryset=AttentionSignal.objects.filter(ack=False).order_by("-created_at"),
                to_attr="unacked_signals",
            ),
            Prefetch(
                "orders",
                queryset=Order.objects.exclude(
                    status__in=[Order.Status.PAID, Order.Status.CANCELLED]
                ).order_by("-created_at"),
                to_attr="active_orders",
            ),
        )
        return Response(
            {
                "currentUser": {
                    "id": str(request.user.id),
                    "username": request.user.username,
                    "name": employee_for_user(request.user).name if employee_for_user(request.user) else request.user.get_full_name(),
                    "role": role_for_user(request.user),
                },
                "tables": [serialize_for_flutter_table(table) for table in tables_qs],
                "menu": [serialize_for_flutter_menu(item) for item in MenuItem.objects.all()],
                "orders": [serialize_for_flutter_order(order) for order in orders],
                "preferences": StaffPreferenceSerializer(preferences).data,
                "websocketPath": "/ws/staff/?token=<token>",
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
        if role_for_user(request.user) not in {Employee.Role.MANAGER, Employee.Role.ADMIN}:
            raise PermissionDenied("Only a manager or admin can view analytics.")

        now = timezone.localtime()
        today = now.date()
        yesterday = today - timedelta(days=1)
        line_total = ExpressionWrapper(F("unit_price") * F("quantity"), output_field=self._MONEY)

        def revenue_on(day):
            value = (
                OrderItem.objects.filter(order__created_at__date=day)
                .exclude(order__status=Order.Status.CANCELLED)
                .aggregate(total=Sum(line_total))["total"]
            )
            return float(value or 0)

        def served_tables_on(day):
            return (
                Order.objects.filter(created_at__date=day)
                .exclude(status=Order.Status.CANCELLED)
                .values("table")
                .distinct()
                .count()
            )

        revenue_today = revenue_on(today)
        revenue_yesterday = revenue_on(yesterday)
        orders_today = (
            Order.objects.filter(created_at__date=today)
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
            OrderItem.objects.filter(order__created_at__date=today)
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
            order__created_at__date=today, ready=True
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
            Order.objects.exclude(
                status__in=[Order.Status.PAID, Order.Status.CANCELLED]
            )
            .filter(created_at__lt=late_threshold)
            .count()
        )

        total_tables = Table.objects.count()
        active_tables = Table.objects.exclude(status=Table.Status.FREE).count()

        def pct(today_value, prev_value):
            if not prev_value:
                return None
            return round((today_value - prev_value) / prev_value * 100)

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
                "generatedAt": now.isoformat(),
            }
        )


class StaffOrderHistoryView(APIView):
    """Manager/admin order history, including closed/paid orders."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if role_for_user(request.user) not in {Employee.Role.MANAGER, Employee.Role.ADMIN}:
            raise PermissionDenied("Only a manager or admin can view order history.")

        orders = (
            Order.objects.select_related("table", "employee")
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


class MenuItemViewSet(viewsets.ModelViewSet):
    queryset = MenuItem.objects.all()
    serializer_class = MenuItemSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_fields = ["category", "is_available"]
    search_fields = ["name", "description", "category"]
    ordering_fields = ["name", "category", "price", "updated_at"]


class TableViewSet(viewsets.ModelViewSet):
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
        # Tables are the waiter's (and manager's) domain: the station screens
        # only see their order feed, so a kitchen/bar token must not be able
        # to clear or re-status a table.
        if role_for_user(self.request.user) in STATION_ROLES:
            raise PermissionDenied("Kitchen/bar staff cannot change tables.")
        table = serializer.save()
        if table.status == Table.Status.FREE:
            table = reset_free_table(table)
        elif table.opened_at is None:
            table.opened_at = timezone.now()
            table.save(update_fields=["opened_at", "updated_at"])
        broadcast_table_event(table)


class OrderViewSet(viewsets.ModelViewSet):
    queryset = (
        Order.objects.select_related("table", "employee", "employee__user")
        .prefetch_related("items", "items__menu_item")
        .all()
    )
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["status", "table"]
    search_fields = ["guest_name", "notes", "table__number"]
    ordering_fields = ["created_at", "updated_at", "status"]

    def perform_create(self, serializer):
        order = serializer.save(employee=employee_for_user(self.request.user), source=Order.Source.STAFF_APP)
        # A waiter placed the order himself — the table is simply occupied
        # (WAITING is reserved for "guests are waiting for a waiter").
        order.table.status = Table.Status.OCCUPIED
        order.table.opened_at = order.table.opened_at or timezone.now()
        order.table.save(update_fields=["status", "opened_at", "updated_at"])
        broadcast_order_event("created", order)
        broadcast_table_event(order.table)

    def perform_update(self, serializer):
        new_status = serializer.validated_data.get("status")
        if new_status is not None:
            role = role_for_user(self.request.user)
            if role in STATION_ROLES and new_status not in STATION_ALLOWED_ORDER_STATUSES:
                raise PermissionDenied(
                    "Kitchen/bar staff can only move an order to cooking or ready. "
                    "Completing (delivery) is the waiter's action."
                )
            if role in STATION_ROLES and new_status == Order.Status.READY:
                order = serializer.instance
                station = "bar" if role == Employee.Role.BAR else "kitchen"
                order.items.filter(station=station).update(ready=True, updated_at=timezone.now())
                order = sync_order_status_from_items(order)
                broadcast_order_event("updated", order)
                return
            if new_status == Order.Status.COMPLETED and serializer.instance.items.filter(done=False).exists():
                raise PermissionDenied("Mark each item delivered before completing the order.")
            if new_status == Order.Status.CANCELLED and role not in {
                Employee.Role.MANAGER,
                Employee.Role.ADMIN,
            }:
                raise PermissionDenied("Only a manager or admin can cancel an order.")
        order = serializer.save()
        broadcast_order_event("updated", order)

    @decorators.action(detail=False, methods=["get"], url_path="station-feed")
    def station_feed(self, request):
        station = request.query_params.get("station")
        if station not in {"kitchen", "bar"}:
            return Response({"detail": "station must be kitchen or bar"}, status=status.HTTP_400_BAD_REQUEST)

        orders = (
            self.get_queryset()
            .filter(items__station=station)
            .exclude(status__in=[Order.Status.PAID, Order.Status.CANCELLED])
            .distinct()
        )
        data = []
        for order in orders:
            payload = OrderSerializer(order).data
            payload["items"] = [item for item in payload["items"] if item["station"] == station]
            data.append(payload)
        return Response(data)


class OrderItemViewSet(viewsets.ModelViewSet):
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
        item.ready = True
        item.save(update_fields=["ready", "updated_at"])
        sync_order_status_from_items(item.order)
        broadcast_order_event("updated", item.order)
        return Response(OrderItemSerializer(item).data)

    @decorators.action(detail=True, methods=["post"], url_path="toggle-done")
    def toggle_done(self, request, pk=None):
        # "done" = delivered to the guest — that's the waiter's confirmation,
        # not something a station can flip (and un-flip) from the pass.
        if role_for_user(request.user) in STATION_ROLES:
            raise PermissionDenied("Only a waiter or manager can mark an item as delivered.")
        item = self.get_object()
        item.done = not item.done
        if item.done:
            item.ready = True
        item.save(update_fields=["ready", "done", "updated_at"])
        sync_order_status_from_items(item.order)
        broadcast_order_event("updated", item.order)
        return Response(OrderItemSerializer(item).data)


class AttentionSignalViewSet(viewsets.ModelViewSet):
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
        signal = serializer.save()
        table = apply_signal_to_table(signal, signal.table)
        broadcast_attention_event("created", signal)
        broadcast_table_event(table)

    @decorators.action(detail=True, methods=["post"], url_path="ack")
    def ack(self, request, pk=None):
        signal = self.get_object()
        employee = employee_for_user(request.user)
        signal.acknowledge(employee)
        table = acknowledge_signal_on_table(signal.table)
        broadcast_attention_event("acked", signal)
        broadcast_table_event(table)
        return Response(AttentionSignalSerializer(signal).data)


class EmployeeViewSet(viewsets.ModelViewSet):
    queryset = Employee.objects.select_related("user").all()
    serializer_class = EmployeeSerializer
    permission_classes = [permissions.IsAdminUser]
    filterset_fields = ["role", "is_on_shift"]
    search_fields = ["name", "user__username", "user__email"]
    ordering_fields = ["name", "role", "updated_at"]


class StaffPreferenceView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        preferences, _ = StaffPreference.objects.get_or_create(user=request.user)
        return Response(StaffPreferenceSerializer(preferences).data)

    def patch(self, request):
        preferences, _ = StaffPreference.objects.get_or_create(user=request.user)
        serializer = StaffPreferenceSerializer(preferences, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
