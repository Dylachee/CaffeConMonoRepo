from django.db import transaction
from django.utils import timezone
from rest_framework import decorators, permissions, status, viewsets
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.events import broadcast_attention_event, broadcast_order_event
from apps.api.serializers import (
    AttentionSignalSerializer,
    EmployeeSerializer,
    MenuItemSerializer,
    OrderItemSerializer,
    OrderSerializer,
    StaffPreferenceSerializer,
    TableSerializer,
)
from apps.core.models import AttentionSignal, Employee, MenuItem, Order, OrderItem, StaffPreference, Table


class HealthCheckView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response({"status": "ok", "service": "CafeConnect API"})


def employee_for_user(user):
    if not user or user.is_anonymous:
        return None
    try:
        return user.employee_profile
    except Employee.DoesNotExist:
        return None


def table_attention_from_signal(signal_type: str) -> str:
    return {
        AttentionSignal.Type.ARRIVED: Table.Attention.ARRIVED,
        AttentionSignal.Type.CALL_WAITER: Table.Attention.CALL,
        AttentionSignal.Type.BILL_REQUEST: Table.Attention.BILL,
    }.get(signal_type, Table.Attention.NONE)


def flutter_table_status(status_value: str) -> str:
    return {
        Table.Status.FREE: "free",
        Table.Status.OCCUPIED: "occupied",
        Table.Status.AWAITING_PAYMENT: "awaitingPayment",
        Table.Status.READY: "ready",
        Table.Status.LATE: "late",
        Table.Status.NEW_ORDER: "newOrder",
        Table.Status.NEEDS_SERVICE: "newOrder",
    }.get(status_value, "free")


def flutter_order_status(status_value: str) -> str:
    return {
        Order.Status.NEW: "accepted",
        Order.Status.PENDING: "accepted",
        Order.Status.COOKING: "cooking",
        Order.Status.PREPARING: "cooking",
        Order.Status.READY: "ready",
        Order.Status.DELIVERED: "completed",
        Order.Status.COMPLETED: "completed",
        Order.Status.PAID: "completed",
    }.get(status_value, "accepted")


def serialize_for_flutter_menu(item: MenuItem) -> dict:
    return {
        "id": str(item.id),
        "name": item.name,
        "description": item.description,
        "price": float(item.price),
        "category": item.category,
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
    current_order = table.orders.exclude(status__in=[Order.Status.PAID, Order.Status.CANCELLED]).first()
    return {
        "id": str(table.id),
        "number": table.number,
        "name": table.label or f"Стол {table.number:02d}",
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
                "name": item.menu_item.name,
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
        return Response(
            {
                "currentUser": {
                    "id": str(request.user.id),
                    "username": request.user.username,
                    "name": employee_for_user(request.user).name if employee_for_user(request.user) else request.user.get_full_name(),
                },
                "tables": [serialize_for_flutter_table(table) for table in Table.objects.select_related("waiter").all()],
                "menu": [serialize_for_flutter_menu(item) for item in MenuItem.objects.all()],
                "orders": [serialize_for_flutter_order(order) for order in orders],
                "preferences": StaffPreferenceSerializer(preferences).data,
                "websocketPath": "/ws/staff/?token=<token>",
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
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filterset_fields = ["status"]
    search_fields = ["number", "label"]
    ordering_fields = ["number", "updated_at"]


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
        order.table.status = Table.Status.NEW_ORDER
        order.table.opened_at = order.table.opened_at or timezone.now()
        order.table.save(update_fields=["status", "opened_at", "updated_at"])
        broadcast_order_event("created", order)

    def perform_update(self, serializer):
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
        broadcast_order_event("updated", item.order)
        return Response(OrderItemSerializer(item).data)

    @decorators.action(detail=True, methods=["post"], url_path="toggle-done")
    def toggle_done(self, request, pk=None):
        item = self.get_object()
        item.done = not item.done
        item.save(update_fields=["done", "updated_at"])
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

    @transaction.atomic
    def perform_create(self, serializer):
        signal = serializer.save()
        table = signal.table
        table.attention = table_attention_from_signal(signal.signal_type)
        table.attention_reason = signal.reason
        table.attention_acknowledged = False
        if signal.signal_type == AttentionSignal.Type.ARRIVED and table.status == Table.Status.FREE:
            table.status = Table.Status.OCCUPIED
            table.opened_at = timezone.now()
        table.save(update_fields=["attention", "attention_reason", "attention_acknowledged", "status", "opened_at", "updated_at"])
        broadcast_attention_event("created", signal)

    @decorators.action(detail=True, methods=["post"], url_path="ack")
    def ack(self, request, pk=None):
        signal = self.get_object()
        employee = employee_for_user(request.user)
        signal.acknowledge(employee)
        table = signal.table
        table.attention_acknowledged = True
        table.save(update_fields=["attention_acknowledged", "updated_at"])
        broadcast_attention_event("acked", signal)
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
