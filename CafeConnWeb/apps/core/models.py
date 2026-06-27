from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone


class Station(models.TextChoices):
    KITCHEN = "kitchen", "Kitchen"
    BAR = "bar", "Bar"


class MenuItem(models.Model):
    name = models.CharField(max_length=160)
    description = models.TextField(blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    category = models.CharField(max_length=80, db_index=True)
    image_url = models.URLField(blank=True)
    station = models.CharField(max_length=24, choices=Station.choices, default=Station.KITCHEN, db_index=True)
    tags = models.JSONField(default=list, blank=True)
    composition = models.TextField(blank=True)
    allergens = models.JSONField(default=list, blank=True)
    is_available = models.BooleanField(default=True)
    is_promoted = models.BooleanField(default=False)
    preparation_minutes = models.PositiveSmallIntegerField(default=5)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_menu_items"
        ordering = ["category", "name"]

    def __str__(self) -> str:
        return self.name


class Table(models.Model):
    class Status(models.TextChoices):
        FREE = "free", "Free"
        OCCUPIED = "occupied", "Occupied"
        RESERVED = "reserved", "Reserved"
        NEW_ORDER = "new_order", "New order"
        READY = "ready", "Ready"
        AWAITING_PAYMENT = "awaiting_payment", "Awaiting payment"
        NEEDS_SERVICE = "needs_service", "Needs service"
        LATE = "late", "Late"
        CLOSED = "closed", "Closed"

    class Attention(models.TextChoices):
        NONE = "", "None"
        ARRIVED = "arrived", "Arrived"
        CALL = "call", "Call waiter"
        BILL = "bill", "Bill requested"

    number = models.PositiveIntegerField(unique=True)
    label = models.CharField(max_length=80, blank=True)
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.FREE)
    capacity = models.PositiveSmallIntegerField(default=2)
    guest_count = models.PositiveSmallIntegerField(default=0)
    color_tag = models.CharField(max_length=24, blank=True)
    waiter = models.ForeignKey(
        "Employee",
        on_delete=models.SET_NULL,
        related_name="tables",
        null=True,
        blank=True,
    )
    opened_at = models.DateTimeField(null=True, blank=True)
    attention = models.CharField(max_length=24, choices=Attention.choices, blank=True, default=Attention.NONE)
    attention_reason = models.CharField(max_length=255, blank=True)
    attention_acknowledged = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_tables"
        ordering = ["number"]

    def __str__(self) -> str:
        return self.label or f"Table {self.number}"


class Employee(models.Model):
    class Role(models.TextChoices):
        WAITER = "waiter", "Waiter"
        KITCHEN = "kitchen", "Kitchen"
        BAR = "bar", "Bar"
        MANAGER = "manager", "Manager"
        ACCOUNTANT = "accountant", "Accountant"
        ADMIN = "admin", "Admin"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="employee_profile",
    )
    name = models.CharField(max_length=160)
    role = models.CharField(max_length=32, choices=Role.choices, db_index=True)
    phone = models.CharField(max_length=32, blank=True)
    is_on_shift = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_employees"
        ordering = ["name"]

    def __str__(self) -> str:
        return f"{self.name} ({self.get_role_display()})"


class Order(models.Model):
    class Status(models.TextChoices):
        NEW = "new", "New"
        PENDING = "pending", "Pending"
        COOKING = "cooking", "Cooking"
        PREPARING = "preparing", "Preparing"
        READY = "ready", "Ready"
        DELIVERED = "delivered", "Delivered"
        COMPLETED = "completed", "Completed"
        PAID = "paid", "Paid"
        CANCELLED = "cancelled", "Cancelled"

    class Source(models.TextChoices):
        GUEST_WEB = "guest_web", "Guest web"
        STAFF_APP = "staff_app", "Staff app"
        ADMIN_WEB = "admin_web", "Admin web"

    class StationScope(models.TextChoices):
        MIXED = "mixed", "Mixed"
        KITCHEN = Station.KITCHEN, "Kitchen"
        BAR = Station.BAR, "Bar"

    table = models.ForeignKey(Table, on_delete=models.PROTECT, related_name="orders")
    employee = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="orders",
        null=True,
        blank=True,
    )
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.NEW, db_index=True)
    source = models.CharField(max_length=32, choices=Source.choices, default=Source.GUEST_WEB, db_index=True)
    station_scope = models.CharField(max_length=24, choices=StationScope.choices, default=StationScope.MIXED, db_index=True)
    guest_name = models.CharField(max_length=120, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_orders"
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"Order #{self.pk} - {self.table}"

    @property
    def total(self) -> Decimal:
        return sum((item.line_total for item in self.items.all()), Decimal("0.00"))


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    menu_item = models.ForeignKey(MenuItem, on_delete=models.PROTECT, related_name="order_items")
    quantity = models.PositiveSmallIntegerField(default=1)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    station = models.CharField(max_length=24, choices=Station.choices, default=Station.KITCHEN, db_index=True)
    notes = models.JSONField(default=list, blank=True)
    ready = models.BooleanField(default=False)
    done = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_order_items"

    def __str__(self) -> str:
        return f"{self.quantity} x {self.menu_item.name}"

    @property
    def line_total(self) -> Decimal:
        return self.unit_price * self.quantity


class AttentionSignal(models.Model):
    class Type(models.TextChoices):
        ARRIVED = "arrived", "Arrived"
        CALL_WAITER = "call_waiter", "Call waiter"
        BILL_REQUEST = "bill_request", "Bill request"

    table = models.ForeignKey(Table, on_delete=models.CASCADE, related_name="attention_signals")
    signal_type = models.CharField(max_length=24, choices=Type.choices, db_index=True)
    reason = models.CharField(max_length=255, blank=True)
    ack = models.BooleanField(default=False)
    acknowledged_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="acknowledged_signals",
        null=True,
        blank=True,
    )
    acked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "cafe_attention_signals"
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.get_signal_type_display()} - {self.table}"

    def acknowledge(self, employee: Employee | None = None) -> None:
        self.ack = True
        self.acknowledged_by = employee
        self.acked_at = timezone.now()
        self.save(update_fields=["ack", "acknowledged_by", "acked_at"])


class StaffPreference(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="staff_preferences",
    )
    sound_arrival = models.BooleanField(default=True)
    sound_call = models.BooleanField(default=True)
    sound_bill = models.BooleanField(default=True)
    haptics = models.BooleanField(default=True)
    volume = models.PositiveSmallIntegerField(default=70)
    sort_undelivered = models.BooleanField(default=True)
    show_ready = models.BooleanField(default=True)
    confirm_clear = models.BooleanField(default=True)
    theme = models.CharField(max_length=16, default="light")
    text_size = models.CharField(max_length=8, default="m")
    high_contrast = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_staff_preferences"

    def __str__(self) -> str:
        return f"Preferences for {self.user}"
