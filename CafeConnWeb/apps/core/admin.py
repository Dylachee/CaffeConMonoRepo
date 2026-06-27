from django.contrib import admin

from apps.core.models import AttentionSignal, Employee, MenuItem, Order, OrderItem, StaffPreference, Table


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0
    autocomplete_fields = ["menu_item"]


@admin.register(MenuItem)
class MenuItemAdmin(admin.ModelAdmin):
    list_display = ("name", "category", "station", "price", "is_available", "updated_at")
    list_filter = ("category", "station", "is_available")
    search_fields = ("name", "description", "category")


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
