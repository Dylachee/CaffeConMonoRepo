from django.contrib import admin
from django.utils.html import format_html

from apps.core.models import AttentionSignal, Employee, MenuCategory, MenuItem, Order, OrderItem, StaffPreference, Table


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

    list_display = (
        "name",
        "category",
        "station",
        "price",
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
        ("Visibilità", {"fields": ("is_available", "is_promoted", "tags")}),
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
