from django.contrib.auth import get_user_model
from rest_framework import serializers

from apps.core.models import AttentionSignal, Employee, MenuItem, Order, OrderItem, StaffPreference, Table

User = get_user_model()


class MenuItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = MenuItem
        fields = [
            "id",
            "name",
            "description",
            "price",
            "category",
            "image_url",
            "station",
            "tags",
            "composition",
            "allergens",
            "is_available",
            "is_promoted",
            "preparation_minutes",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]


class TableSerializer(serializers.ModelSerializer):
    waiter = serializers.StringRelatedField(read_only=True)

    class Meta:
        model = Table
        fields = [
            "id",
            "number",
            "label",
            "status",
            "capacity",
            "guest_count",
            "color_tag",
            "waiter",
            "opened_at",
            "attention",
            "attention_reason",
            "attention_acknowledged",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]


class EmployeeSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)
    email = serializers.EmailField(source="user.email", read_only=True)

    class Meta:
        model = Employee
        fields = ["id", "username", "email", "name", "role", "phone", "is_on_shift", "created_at", "updated_at"]
        read_only_fields = ["created_at", "updated_at"]


class OrderItemSerializer(serializers.ModelSerializer):
    menu_item = MenuItemSerializer(read_only=True)
    menu_item_id = serializers.PrimaryKeyRelatedField(
        source="menu_item",
        queryset=MenuItem.objects.filter(is_available=True),
        write_only=True,
    )
    line_total = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)

    class Meta:
        model = OrderItem
        fields = [
            "id",
            "menu_item",
            "menu_item_id",
            "quantity",
            "unit_price",
            "station",
            "notes",
            "ready",
            "done",
            "line_total",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["unit_price", "line_total"]


class OrderSerializer(serializers.ModelSerializer):
    table = TableSerializer(read_only=True)
    table_id = serializers.PrimaryKeyRelatedField(source="table", queryset=Table.objects.all(), write_only=True)
    employee = EmployeeSerializer(read_only=True)
    items = OrderItemSerializer(many=True)
    total = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)

    class Meta:
        model = Order
        fields = [
            "id",
            "table",
            "table_id",
            "employee",
            "status",
            "source",
            "station_scope",
            "guest_name",
            "notes",
            "items",
            "total",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def create(self, validated_data):
        items_data = validated_data.pop("items", [])
        order = Order.objects.create(**validated_data)

        order_items = [
            OrderItem(
                order=order,
                menu_item=item_data["menu_item"],
                quantity=item_data.get("quantity", 1),
                unit_price=item_data["menu_item"].price,
                station=item_data["menu_item"].station,
                notes=item_data.get("notes", []),
            )
            for item_data in items_data
        ]
        OrderItem.objects.bulk_create(order_items)
        stations = {item.station for item in order_items}
        if len(stations) == 1:
            order.station_scope = stations.pop()
        elif len(stations) > 1:
            order.station_scope = Order.StationScope.MIXED
        order.save(update_fields=["station_scope", "updated_at"])
        return order

    def update(self, instance, validated_data):
        validated_data.pop("items", None)
        return super().update(instance, validated_data)


class AttentionSignalSerializer(serializers.ModelSerializer):
    table = TableSerializer(read_only=True)
    table_id = serializers.PrimaryKeyRelatedField(source="table", queryset=Table.objects.all(), write_only=True)
    acknowledged_by = EmployeeSerializer(read_only=True)

    class Meta:
        model = AttentionSignal
        fields = [
            "id",
            "table",
            "table_id",
            "signal_type",
            "reason",
            "ack",
            "acknowledged_by",
            "acked_at",
            "created_at",
        ]
        read_only_fields = ["ack", "acknowledged_by", "acked_at", "created_at"]


class StaffPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = StaffPreference
        fields = [
            "sound_arrival",
            "sound_call",
            "sound_bill",
            "haptics",
            "volume",
            "sort_undelivered",
            "show_ready",
            "confirm_clear",
            "theme",
            "text_size",
            "high_contrast",
            "updated_at",
        ]
        read_only_fields = ["updated_at"]
