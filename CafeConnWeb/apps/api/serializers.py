from django.contrib.auth import get_user_model
from django.db.models import Max
from django.utils.text import slugify
from rest_framework import serializers

from apps.core.menu_i18n import menu_item_labels
from apps.core.models import (
    AttentionSignal,
    Employee,
    MenuCategory,
    MenuItem,
    Order,
    OrderItem,
    StaffPreference,
    Table,
)

User = get_user_model()


class MenuCategorySerializer(serializers.ModelSerializer):
    item_count = serializers.SerializerMethodField()

    class Meta:
        model = MenuCategory
        fields = [
            "id",
            "key",
            "name",
            "color",
            "sort_order",
            "item_count",
            "updated_at",
        ]
        read_only_fields = ["key", "updated_at"]

    def create(self, validated_data):
        name = validated_data.get("name", "").strip()
        validated_data["name"] = name
        if "sort_order" not in validated_data:
            validated_data["sort_order"] = (
                MenuCategory.objects.aggregate(max_order=Max("sort_order"))["max_order"]
                or 0
            ) + 1
        base = slugify(name)[:40] or "category"
        key = base
        suffix = 2
        while MenuCategory.objects.filter(key=key).exists():
            tail = f"-{suffix}"
            key = f"{base[:40 - len(tail)]}{tail}"
            suffix += 1
        return MenuCategory.objects.create(key=key, **validated_data)

    def get_item_count(self, obj):
        item_count = getattr(obj, "item_count", None)
        return item_count if item_count is not None else obj.items.count()


class MenuItemSerializer(serializers.ModelSerializer):
    category = serializers.PrimaryKeyRelatedField(queryset=MenuCategory.objects.all())

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
            "portion_weight",
            "calories",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        labels = menu_item_labels(instance)
        data["categoryId"] = str(instance.category_id)
        data["name"] = labels["name_en"]
        data["description"] = labels["description_en"]
        data["category"] = labels["category_en"]
        data["categoryIt"] = labels["category_it"]
        return data


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
    first_name = serializers.CharField(source="user.first_name", read_only=True)
    last_name = serializers.CharField(source="user.last_name", read_only=True)
    # Effective (role + grants) capabilities, so the client can gate its UI.
    capabilities = serializers.DictField(read_only=True)

    class Meta:
        model = Employee
        fields = [
            "id", "username", "email", "first_name", "last_name", "name",
            "role", "phone", "is_on_shift",
            "can_wait", "can_bar", "can_kitchen", "can_manage_menu",
            "capabilities", "created_at", "updated_at",
        ]
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
    status = serializers.ChoiceField(
        choices=list(Order.Status.choices) + [(value, value.title()) for value in Order.LEGACY_STATUS_ALIASES],
        required=False,
    )
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
            "accepted_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "accepted_at", "updated_at"]

    def validate_status(self, value):
        return Order.LEGACY_STATUS_ALIASES.get(value, value)

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
