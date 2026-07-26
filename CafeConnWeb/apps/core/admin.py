from django import forms
from django.contrib import admin
from django.utils.html import format_html

from apps.core.models import (
    AttentionSignal,
    CouponCampaign,
    Employee,
    GuestWallet,
    IssuedCoupon,
    MenuCategory,
    MenuItem,
    Order,
    OrderItem,
    PushSubscription,
    SocialPost,
    StaffPreference,
    Table,
    VenueSettings,
)


class MenuItemAdminForm(forms.ModelForm):
    show_in_guest_menu = forms.BooleanField(
        required=False, label="Mostra nel menu ospiti"
    )

    class Meta:
        model = MenuItem
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["show_in_guest_menu"].initial = (
            self.instance.pk is None or "client" in (self.instance.tags or [])
        )

    def save(self, commit=True):
        item = super().save(commit=False)
        tags = list(item.tags or [])
        visible = self.cleaned_data.get("show_in_guest_menu", True)
        if visible and "client" not in tags:
            tags.append("client")
        if not visible:
            tags = [tag for tag in tags if tag != "client"]
        item.tags = tags
        if commit:
            item.save()
            self.save_m2m()
        return item


@admin.register(MenuCategory)
class MenuCategoryAdmin(admin.ModelAdmin):
    """The owner's category console: rename/recolor categories used by menu
    items, waiter filters, and guest menu accents."""

    list_display = ("swatch", "key", "name", "color", "sort_order", "updated_at")
    list_display_links = ("key",)
    list_editable = ("name", "color", "sort_order")
    ordering = ("sort_order",)

    @admin.display(description="")
    def swatch(self, obj):
        return format_html(
            '<span style="display:inline-block;width:18px;height:18px;'
            'border-radius:5px;background:{};border:1px solid #0002"></span>',
            obj.color,
        )


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0
    autocomplete_fields = ["menu_item"]


@admin.register(MenuItem)
class MenuItemAdmin(admin.ModelAdmin):
    """The owner's menu console: every field editable, category/price/flags
    right in the list, bulk actions for the common tag flips so nobody has to
    hand-edit the tags JSON."""

    form = MenuItemAdminForm
    list_display = (
        "name",
        "category",
        "station",
        "price",
        "is_guest_visible",
        "is_waiter_popular",
        "is_promoted",
        "is_available",
        "updated_at",
    )
    list_display_links = ("name",)
    list_editable = (
        "category",
        "station",
        "price",
        "is_promoted",
        "is_available",
    )
    list_filter = ("category", "station", "is_available", "is_promoted")
    list_select_related = ("category",)
    search_fields = ("name", "description", "category__name")
    ordering = ("category__sort_order", "category__name", "name")
    list_per_page = 200
    actions = [
        "make_available",
        "make_unavailable",
        "pin_waiter_popular",
        "unpin_waiter_popular",
    ]
    fieldsets = (
        (None, {"fields": ("name", "description", "price", "category", "station")}),
        ("Visibilità", {"fields": ("is_available", "show_in_guest_menu", "is_promoted", "tags")}),
        (
            "Dettagli piatto",
            {
                "classes": ("collapse",),
                "fields": (
                    "composition",
                    "allergens",
                    "image_url",
                    "preparation_minutes",
                    "portion_weight",
                    "calories",
                ),
            },
        ),
    )

    @admin.display(boolean=True, description="★ Camerieri")
    def is_waiter_popular(self, obj):
        return "popular" in (obj.tags or [])

    @admin.display(boolean=True, description="Menu ospiti")
    def is_guest_visible(self, obj):
        return "client" in (obj.tags or [])

    def _set_tag(self, queryset, tag, on):
        for item in queryset:
            tags = list(item.tags or [])
            if on and tag not in tags:
                tags.append(tag)
            elif not on and tag in tags:
                tags.remove(tag)
            else:
                continue
            item.tags = tags
            item.save(update_fields=["tags", "updated_at"])

    @admin.action(description="Rendi disponibili")
    def make_available(self, request, queryset):
        for item in queryset:
            tags = list(item.tags or [])
            if "client" not in tags:
                tags.append("client")
            item.tags = tags
            item.is_available = True
            item.save(update_fields=["tags", "is_available", "updated_at"])

    @admin.action(description="Rendi NON disponibili")
    def make_unavailable(self, request, queryset):
        queryset.update(is_available=False)

    @admin.action(description="Aggiungi ai Popolari camerieri (★)")
    def pin_waiter_popular(self, request, queryset):
        self._set_tag(queryset, "popular", True)

    @admin.action(description="Rimuovi dai Popolari camerieri")
    def unpin_waiter_popular(self, request, queryset):
        self._set_tag(queryset, "popular", False)


@admin.register(Table)
class TableAdmin(admin.ModelAdmin):
    list_display = ("number", "status", "guest_count", "capacity", "attention", "attention_acknowledged", "updated_at")
    list_filter = ("status", "attention", "attention_acknowledged")
    search_fields = ("number", "label", "waiter__name")


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ("id", "table", "status", "station_scope", "source", "employee", "created_at")
    list_filter = ("status", "station_scope", "source", "created_at")
    search_fields = ("id", "table__number", "employee__name")
    inlines = [OrderItemInline]


@admin.register(Employee)
class EmployeeAdmin(admin.ModelAdmin):
    list_display = ("name", "role", "user", "is_on_shift")
    list_filter = ("role", "is_on_shift")
    search_fields = ("name", "user__username", "user__email")


@admin.register(AttentionSignal)
class AttentionSignalAdmin(admin.ModelAdmin):
    list_display = ("id", "table", "signal_type", "ack", "acknowledged_by", "created_at")
    list_filter = ("signal_type", "ack", "created_at")
    search_fields = ("table__number", "reason", "acknowledged_by__name")


@admin.register(StaffPreference)
class StaffPreferenceAdmin(admin.ModelAdmin):
    list_display = ("user", "theme", "text_size", "high_contrast", "updated_at")
    list_filter = ("theme", "text_size", "high_contrast")
    search_fields = ("user__username", "user__email")


@admin.register(SocialPost)
class SocialPostAdmin(admin.ModelAdmin):
    list_display = ("id", "platform", "source_url", "is_pinned", "is_hidden", "created_by", "created_at")
    list_filter = ("platform", "is_pinned", "is_hidden")
    search_fields = ("source_url",)
    readonly_fields = ("embed_html", "created_at", "pinned_at")


@admin.register(VenueSettings)
class VenueSettingsAdmin(admin.ModelAdmin):
    """Back-office escape hatch; day-to-day edits go through the staff app's
    Storefront editor."""

    list_display = ("slug", "name", "pinned_posts_limit", "updated_at")
    readonly_fields = ("updated_at",)


@admin.register(CouponCampaign)
class CouponCampaignAdmin(admin.ModelAdmin):
    list_display = (
        "title",
        "slug",
        "discount_type",
        "discount_value",
        "is_active",
        "valid_from",
        "valid_until",
        "per_wallet_limit",
        "max_total_issues",
    )
    list_filter = ("is_active", "discount_type")
    search_fields = ("title", "slug", "source_utm")
    prepopulated_fields = {"slug": ("title",)}


@admin.register(IssuedCoupon)
class IssuedCouponAdmin(admin.ModelAdmin):
    list_display = ("code", "campaign", "status", "issued_via", "utm_source", "redeemed_by", "redeemed_at", "created_at")
    list_filter = ("status", "issued_via", "campaign")
    search_fields = ("code", "utm_source")
    readonly_fields = ("code", "wallet", "campaign", "redeemed_at", "created_at")


@admin.register(GuestWallet)
class GuestWalletAdmin(admin.ModelAdmin):
    list_display = ("token", "user", "created_at", "last_seen_at")
    readonly_fields = ("token", "created_at", "last_seen_at")


@admin.register(PushSubscription)
class PushSubscriptionAdmin(admin.ModelAdmin):
    list_display = ("employee", "endpoint", "user_agent", "created_at")
    search_fields = ("employee__name", "endpoint")
    readonly_fields = ("endpoint", "p256dh", "auth", "created_at")
