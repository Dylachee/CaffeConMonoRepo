from django.contrib.auth import get_user_model
from django.db.models import Count, Max, Q
from django.utils.text import slugify
from rest_framework import serializers

from apps.core.menu_catalog import CLIENT_MENU_TAG
from apps.core.menu_i18n import menu_item_labels
from apps.core.models import (
    AttentionSignal,
    ChatMessage,
    CouponCampaign,
    Employee,
    IssuedCoupon,
    MenuCategory,
    MenuItem,
    Order,
    OrderItem,
    Restaurant,
    SocialPost,
    StaffPreference,
    StaffTask,
    Table,
    VenueSettings,
)
from apps.core.social_embed import domain_for_display

User = get_user_model()


class RestaurantSerializer(serializers.ModelSerializer):
    class Meta:
        model = Restaurant
        fields = [
            "id",
            "name",
            "slug",
            "timezone",
            "currency",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]


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
        restaurant = validated_data["restaurant"]
        name = validated_data.get("name", "").strip()
        validated_data["name"] = name
        if "sort_order" not in validated_data:
            validated_data["sort_order"] = (
                MenuCategory.objects.filter(restaurant=restaurant).aggregate(max_order=Max("sort_order"))["max_order"]
                or 0
            ) + 1
        base = slugify(name)[:40] or "category"
        key = base
        suffix = 2
        while MenuCategory.objects.filter(restaurant=restaurant, key=key).exists():
            tail = f"-{suffix}"
            key = f"{base[:40 - len(tail)]}{tail}"
            suffix += 1
        return MenuCategory.objects.create(key=key, **validated_data)

    def get_item_count(self, obj):
        item_count = getattr(obj, "item_count", None)
        return item_count if item_count is not None else obj.items.filter(is_available=True).count()


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

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        restaurant = self.context.get("restaurant")
        if restaurant is not None:
            self.fields["category"].queryset = MenuCategory.objects.filter(
                restaurant=restaurant
            )

    def _tags_for_clients(self, tags):
        tags = list(tags or [])
        if CLIENT_MENU_TAG not in tags:
            tags.append(CLIENT_MENU_TAG)
        return tags

    def create(self, validated_data):
        validated_data["tags"] = self._tags_for_clients(validated_data.get("tags"))
        return super().create(validated_data)

    def update(self, instance, validated_data):
        if "tags" in validated_data:
            validated_data["tags"] = self._tags_for_clients(validated_data["tags"])
        else:
            validated_data["tags"] = self._tags_for_clients(instance.tags)
        return super().update(instance, validated_data)

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
            "can_wait", "can_bar", "can_kitchen", "can_manage_menu", "can_content",
            "can_grant_discount", "can_manage", "can_reports",
            "shift_areas", "last_shift_areas",
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

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        restaurant = self.context.get("restaurant")
        if restaurant is not None:
            self.fields["menu_item_id"].queryset = MenuItem.objects.filter(
                restaurant=restaurant, is_available=True
            )


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
    total_due = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    # Coupon snapshot — written only by apps.core.coupons.redeem_coupon.
    coupon_code = serializers.CharField(source="coupon.code", read_only=True, default="")

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
            "discount_amount",
            "coupon_code",
            "total_due",
            "alert_escalated",
            "created_at",
            "accepted_at",
            "updated_at",
        ]
        read_only_fields = ["discount_amount", "alert_escalated", "created_at", "accepted_at", "updated_at"]

    def validate_status(self, value):
        return Order.LEGACY_STATUS_ALIASES.get(value, value)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        restaurant = self.context.get("restaurant")
        if restaurant is not None:
            self.fields["table_id"].queryset = Table.objects.filter(
                restaurant=restaurant
            )
            items = self.fields.get("items")
            if items is not None and hasattr(items, "child"):
                items.child.context.update(self.context)

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
            "alert_escalated",
            "acknowledged_by",
            "acked_at",
            "created_at",
        ]
        read_only_fields = ["ack", "alert_escalated", "acknowledged_by", "acked_at", "created_at"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        restaurant = self.context.get("restaurant")
        if restaurant is not None:
            self.fields["table_id"].queryset = Table.objects.filter(
                restaurant=restaurant
            )


class SocialPostSerializer(serializers.ModelSerializer):
    """A feed post as the staff app sees it. `embed_html` is backend-generated
    markup (apps.core.social_embed); `domain` feeds the fallback/preview card."""

    created_by = serializers.CharField(source="created_by.name", read_only=True, default="")
    domain = serializers.SerializerMethodField()

    class Meta:
        model = SocialPost
        fields = [
            "id",
            "source_url",
            "platform",
            "domain",
            "embed_html",
            "is_hidden",
            "is_pinned",
            "pinned_at",
            "created_by",
            "created_at",
        ]
        read_only_fields = fields

    def get_domain(self, obj):
        try:
            return domain_for_display(obj.source_url)
        except ValueError:
            return ""


class VenueSettingsSerializer(serializers.ModelSerializer):
    """Storefront settings for the staff editor. Colors are validated by the
    model's #RRGGBB validators; images are uploaded via dedicated endpoints
    and only exposed here as URLs."""

    logo_url = serializers.SerializerMethodField()
    cover_url = serializers.SerializerMethodField()

    class Meta:
        model = VenueSettings
        fields = [
            "name",
            "tagline",
            "tagline_it",
            "about",
            "about_it",
            "address",
            "address_it",
            "hours",
            "hours_it",
            "badges",
            "maps_url",
            "logo_url",
            "cover_url",
            "color_bg",
            "color_card",
            "color_ink",
            "color_mut",
            "color_line",
            "color_accent",
            "color_accent_deep",
            "color_accent_soft",
            "storefront_blocks",
            "pinned_posts_limit",
            "updated_at",
        ]
        read_only_fields = ["logo_url", "cover_url", "updated_at"]

    def get_logo_url(self, obj):
        return obj.logo.url if obj.logo else ""

    def get_cover_url(self, obj):
        return obj.cover.url if obj.cover else ""

    def validate_badges(self, value):
        if not isinstance(value, list) or len(value) > 8:
            raise serializers.ValidationError("Badges must be a list of up to 8 entries.")
        cleaned = []
        for badge in value:
            if not isinstance(badge, dict) or not str(badge.get("en", "")).strip():
                raise serializers.ValidationError(
                    'Each badge needs at least an English label: {"en": "...", "it": "..."}.'
                )
            en = str(badge.get("en", "")).strip()[:60]
            it = str(badge.get("it", "")).strip()[:60] or en
            cleaned.append({"en": en, "it": it})
        return cleaned

    def validate_storefront_blocks(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("Storefront blocks must be a list.")
        known = set(VenueSettings.STOREFRONT_BLOCK_KEYS)
        cleaned, seen = [], set()
        for entry in value:
            key = entry.get("key") if isinstance(entry, dict) else None
            if key not in known:
                raise serializers.ValidationError(
                    f"Unknown storefront block; use: {', '.join(VenueSettings.STOREFRONT_BLOCK_KEYS)}."
                )
            if key in seen:
                raise serializers.ValidationError(f"Duplicate storefront block: {key}.")
            seen.add(key)
            cleaned.append({"key": key, "visible": bool(entry.get("visible", True))})
        return cleaned

    def validate_pinned_posts_limit(self, value):
        if not 0 <= value <= 12:
            raise serializers.ValidationError("Pinned posts limit must be between 0 and 12.")
        return value


class CouponCampaignSerializer(serializers.ModelSerializer):
    """A coupon campaign for the staff app, with live counters. Slug is
    auto-generated from the title when omitted (mirrors MenuCategory keys)."""

    slug = serializers.SlugField(required=False, allow_blank=True)
    issued_count = serializers.SerializerMethodField()
    redeemed_count = serializers.SerializerMethodField()
    by_utm = serializers.SerializerMethodField()
    created_by = serializers.CharField(source="created_by.name", read_only=True, default="")

    class Meta:
        model = CouponCampaign
        fields = [
            "id",
            "slug",
            "title",
            "title_it",
            "description",
            "description_it",
            "discount_type",
            "discount_value",
            "source_utm",
            "valid_from",
            "valid_until",
            "max_total_issues",
            "per_wallet_limit",
            "is_active",
            "issued_count",
            "redeemed_count",
            "by_utm",
            "created_by",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_at", "updated_at"]

    def validate(self, attrs):
        discount_type = attrs.get(
            "discount_type", getattr(self.instance, "discount_type", None)
        )
        discount_value = attrs.get(
            "discount_value", getattr(self.instance, "discount_value", None)
        )
        if discount_value is None or discount_value <= 0:
            raise serializers.ValidationError(
                {"discount_value": "The discount must be greater than zero."}
            )
        if (
            discount_type == CouponCampaign.DiscountType.PERCENT
            and discount_value > 100
        ):
            raise serializers.ValidationError(
                {"discount_value": "A percent discount cannot exceed 100%."}
            )
        valid_from = attrs.get("valid_from", getattr(self.instance, "valid_from", None))
        valid_until = attrs.get("valid_until", getattr(self.instance, "valid_until", None))
        if valid_from and valid_until and valid_from >= valid_until:
            raise serializers.ValidationError(
                {"valid_until": "The campaign must end after it starts."}
            )
        return attrs

    def create(self, validated_data):
        restaurant = validated_data["restaurant"]
        slug = (validated_data.get("slug") or "").strip()
        if not slug:
            base = slugify(validated_data.get("title", ""))[:50] or "campaign"
            slug = base
            suffix = 2
            while CouponCampaign.objects.filter(restaurant=restaurant, slug=slug).exists():
                tail = f"-{suffix}"
                slug = f"{base[:50 - len(tail)]}{tail}"
                suffix += 1
        validated_data["slug"] = slug
        return super().create(validated_data)

    def _counters(self, obj):
        # Set by the view via annotate(); fall back to queries for detail use.
        issued = getattr(obj, "issued_count_annotated", None)
        redeemed = getattr(obj, "redeemed_count_annotated", None)
        if issued is None:
            issued = obj.coupons.exclude(status=IssuedCoupon.Status.VOID).count()
        if redeemed is None:
            redeemed = obj.coupons.filter(status=IssuedCoupon.Status.REDEEMED).count()
        return issued, redeemed

    def get_issued_count(self, obj):
        return self._counters(obj)[0]

    def get_redeemed_count(self, obj):
        return self._counters(obj)[1]

    def get_by_utm(self, obj):
        rows = (
            obj.coupons.exclude(status=IssuedCoupon.Status.VOID)
            .values("utm_source")
            .annotate(
                issued=Count("id"),
                redeemed=Count("id", filter=Q(status=IssuedCoupon.Status.REDEEMED)),
            )
            .order_by("-issued")
        )
        return [
            {
                "utm_source": row["utm_source"] or "",
                "issued": row["issued"],
                "redeemed": row["redeemed"],
            }
            for row in rows
        ]


class IssuedCouponStaffSerializer(serializers.ModelSerializer):
    """A coupon as staff sees it in the redeem flow — campaign context and
    discount, nothing about the guest beyond the coupon itself."""

    campaign_title = serializers.CharField(source="campaign.title", read_only=True)
    campaign_title_it = serializers.CharField(source="campaign.title_it", read_only=True)
    discount_type = serializers.CharField(source="campaign.discount_type", read_only=True)
    discount_value = serializers.DecimalField(
        source="campaign.discount_value", max_digits=8, decimal_places=2, read_only=True
    )
    order_id = serializers.IntegerField(source="order.id", read_only=True, default=None)
    redeemed_by = serializers.CharField(source="redeemed_by.name", read_only=True, default="")

    class Meta:
        model = IssuedCoupon
        fields = [
            "id",
            "code",
            "status",
            "campaign",
            "campaign_title",
            "campaign_title_it",
            "discount_type",
            "discount_value",
            "issued_via",
            "utm_source",
            "order_id",
            "redeemed_by",
            "redeemed_at",
            "created_at",
        ]
        read_only_fields = fields


class StaffTaskSerializer(serializers.ModelSerializer):
    """A task as chat bubbles and the planner see it. Status transitions and
    the permission matrix live in the views; this is the wire shape."""

    assignee_name = serializers.CharField(source="assignee.name", read_only=True, default="")
    created_by_name = serializers.CharField(source="created_by.name", read_only=True, default="")
    done_by_name = serializers.CharField(source="done_by.name", read_only=True, default="")
    checklist_key = serializers.CharField(
        source="template_item.template.key", read_only=True, default=""
    )

    class Meta:
        model = StaffTask
        fields = [
            "id",
            "title",
            "note",
            "category",
            "assignee",
            "assignee_name",
            "created_by",
            "created_by_name",
            "due_at",
            "recurrence",
            "recurrence_weekdays",
            "recurring_parent",
            "status",
            "done_by_name",
            "done_at",
            "source",
            "template_item",
            "checklist_key",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "created_by",
            "done_by_name",
            "done_at",
            "source",
            "template_item",
            "recurring_parent",
            "created_at",
            "updated_at",
        ]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        restaurant = self.context.get("restaurant")
        if restaurant is not None:
            self.fields["assignee"].queryset = Employee.objects.filter(
                restaurant=restaurant
            )


class ChatMessageSerializer(serializers.ModelSerializer):
    """One chat message. `author_name` is 'CafeBot' for bot/system posts;
    task bubbles nest the LIVE task so every client renders current state."""

    author_name = serializers.SerializerMethodField()
    task = StaffTaskSerializer(read_only=True)
    reply_preview = serializers.SerializerMethodField()
    reply_count = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = [
            "id",
            "channel",
            "kind",
            "body",
            "author",
            "author_name",
            "task",
            "reply_to",
            "reply_preview",
            "reply_count",
            "created_at",
        ]
        read_only_fields = fields

    def get_author_name(self, obj):
        return obj.author.name if obj.author else "CafeBot"

    def get_reply_preview(self, obj):
        parent = obj.reply_to
        if parent is None:
            return None
        return {
            "id": parent.pk,
            "author_name": parent.author.name if parent.author else "CafeBot",
            "kind": parent.kind,
            "body": (parent.task.title if parent.kind == ChatMessage.Kind.TASK and parent.task
                     else parent.body)[:120],
        }

    def get_reply_count(self, obj):
        annotated = getattr(obj, "reply_count_annotated", None)
        if annotated is not None:
            return annotated
        return obj.replies.count()


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
