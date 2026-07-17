import uuid
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.core.validators import RegexValidator
from django.db import models
from django.utils import timezone

from apps.core.media_storage import venue_image_path, venue_media_storage
from apps.core.theme_presets import SISSI_PALETTE


class Station(models.TextChoices):
    KITCHEN = "kitchen", "Kitchen"
    BAR = "bar", "Bar"


class MenuCategory(models.Model):
    """One owner-defined menu category with its display color and order."""

    key = models.SlugField(max_length=40, unique=True)
    name = models.CharField(max_length=80)
    # Hex like #DFAF2B — rendered as-is by the app and the guest web.
    color = models.CharField(max_length=9, default="#DFAF2B")
    sort_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_menu_categories"
        ordering = ["sort_order", "name"]
        verbose_name_plural = "menu categories"

    def __str__(self) -> str:
        return self.name


class MenuItem(models.Model):
    name = models.CharField(max_length=160)
    description = models.TextField(blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    category = models.ForeignKey(
        MenuCategory,
        on_delete=models.PROTECT,
        related_name="items",
    )
    image_url = models.URLField(blank=True)
    station = models.CharField(max_length=24, choices=Station.choices, default=Station.KITCHEN, db_index=True)
    tags = models.JSONField(default=list, blank=True)
    composition = models.TextField(blank=True)
    allergens = models.JSONField(default=list, blank=True)
    is_available = models.BooleanField(default=True)
    is_promoted = models.BooleanField(default=False)
    preparation_minutes = models.PositiveSmallIntegerField(default=5)
    # Dish-detail card on the guest page: portion size / calories.
    # Free-form weight so "380 g" and "250 ml" both fit.
    portion_weight = models.CharField(max_length=32, blank=True)
    calories = models.PositiveSmallIntegerField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_menu_items"
        ordering = ["category__sort_order", "category__name", "name"]

    def __str__(self) -> str:
        return self.name


class Table(models.Model):
    class Status(models.TextChoices):
        # Deliberately just three states (product decision, 2026-07-02):
        # a table is either free, taken, or the guests want a waiter.
        # Everything finer-grained (new order / bill / late / reserved)
        # proved to be noise for a small bar floor.
        FREE = "free", "Free"
        OCCUPIED = "occupied", "Occupied"
        WAITING = "waiting", "Waiting for waiter"

    class Attention(models.TextChoices):
        NONE = "", "None"
        ARRIVED = "arrived", "Arrived"
        CALL = "call", "Call waiter"
        BILL = "bill", "Bill requested"

    number = models.PositiveIntegerField(unique=True)
    label = models.CharField(max_length=80, blank=True)
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.FREE, db_index=True)
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
        SMM = "smm", "SMM"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="employee_profile",
    )
    name = models.CharField(max_length=160)
    role = models.CharField(max_length=32, choices=Role.choices, db_index=True)
    phone = models.CharField(max_length=32, blank=True)
    is_on_shift = models.BooleanField(default=False)
    # Extra capabilities a manager can grant on top of the primary role, so
    # one person can cover two stations (a waiter who also tends bar, a
    # bartender who also works the floor, …). The role still implies its own
    # base capability; these are purely additive. See `capabilities`.
    can_wait = models.BooleanField(default=False)
    can_bar = models.BooleanField(default=False)
    can_kitchen = models.BooleanField(default=False)
    can_manage_menu = models.BooleanField(default=False)
    # Content = the venue's public face: social feed + storefront/theme. The
    # SMM role has it by definition; a manager can also grant it to anyone.
    can_content = models.BooleanField(default=False)
    # Coupons: issuing and redeeming guest discounts. No role implies it —
    # a manager toggles it per waiter, exactly like the other grants.
    can_grant_discount = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_employees"
        ordering = ["name"]

    def __str__(self) -> str:
        return f"{self.name} ({self.get_role_display()})"

    @property
    def capabilities(self) -> dict:
        """Effective capabilities: what this employee may actually do, the
        role's own base plus any manager-granted extras. `manage` (panel /
        analytics / cancel / grant) stays tied to manager/admin."""
        boss = self.role in (Employee.Role.MANAGER, Employee.Role.ADMIN)
        return {
            "wait": boss or self.role == Employee.Role.WAITER or self.can_wait,
            "bar": boss or self.role == Employee.Role.BAR or self.can_bar,
            "kitchen": boss or self.role == Employee.Role.KITCHEN or self.can_kitchen,
            "menu": boss or self.can_manage_menu,
            "manage": boss,
            # SMM gets ONLY this: orders/payments/shifts/menu stay closed
            # unless a manager grants those capabilities explicitly.
            "content": boss or self.role == Employee.Role.SMM or self.can_content,
            # Guest-coupon issue/redeem. Campaign CRUD is `content` (SMM's
            # marketing job); touching money at the table needs this grant.
            "discount": boss or self.can_grant_discount,
        }


class Order(models.Model):
    class Status(models.TextChoices):
        # Canonical lifecycle: NEW → COOKING → READY → COMPLETED → PAID,
        # plus CANCELLED. The former synonyms (pending≈new, preparing≈cooking,
        # delivered≈completed) were collapsed in migration 0006; the API still
        # accepts them on write for older clients (see LEGACY_STATUS_ALIASES).
        #
        # AWAITING sits *before* NEW: a guest-web order lands here first and is
        # invisible to the kitchen/bar until a waiter confirms it (→ NEW). Staff
        # orders skip it — the waiter placing the order is the confirmation.
        AWAITING = "awaiting", "Awaiting waiter"
        NEW = "new", "New"
        COOKING = "cooking", "Cooking"
        READY = "ready", "Ready"
        COMPLETED = "completed", "Completed"
        PAID = "paid", "Paid"
        CANCELLED = "cancelled", "Cancelled"

    # Old wire values still sent by deployed staff-app builds.
    LEGACY_STATUS_ALIASES = {
        "pending": Status.NEW,
        "preparing": Status.COOKING,
        "delivered": Status.COMPLETED,
    }

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
    # When a waiter approved the order (awaiting → new). The kitchen/bar prep
    # timer counts from here, not from created_at — a guest order shouldn't look
    # "late" for the minutes it sat waiting for approval. Null for orders that
    # predate this field or were never approved.
    accepted_at = models.DateTimeField(null=True, blank=True)
    # --- Guest coupon (additive; never touches the order lifecycle). ---
    # OneToOne: a coupon binds to exactly one order. `discount_amount` is a
    # snapshot computed at redemption (apps.core.coupons.compute_discount);
    # later cart edits deliberately do NOT reprice an already-applied coupon.
    coupon = models.OneToOneField(
        "IssuedCoupon",
        on_delete=models.SET_NULL,
        related_name="applied_order",
        null=True,
        blank=True,
    )
    discount_amount = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )
    # Alert ladder L3 for guest orders stuck in AWAITING — see
    # AttentionSignal.alert_escalated for the semantics.
    alert_escalated = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_orders"
        ordering = ["-created_at"]
        indexes = [
            # The hot query: active orders (status NOT IN paid/cancelled)
            # ordered by recency — bootstrap, station feed, guest tracking.
            models.Index(fields=["status", "-created_at"], name="order_status_created_idx"),
        ]

    def __str__(self) -> str:
        return f"Order #{self.pk} - {self.table}"

    @property
    def total(self) -> Decimal:
        return sum((item.line_total for item in self.items.all()), Decimal("0.00"))

    @property
    def total_due(self) -> Decimal:
        """Items total minus the coupon snapshot, floored at zero."""
        due = self.total - (self.discount_amount or Decimal("0.00"))
        return due if due > 0 else Decimal("0.00")


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
        constraints = [
            # Quantity and price come from the guest's browser on the guest
            # order path — the DB is the last line against zero/negative rows.
            models.CheckConstraint(check=models.Q(quantity__gte=1), name="orderitem_qty_gte_1"),
            models.CheckConstraint(check=models.Q(unit_price__gte=0), name="orderitem_price_gte_0"),
        ]

    def __str__(self) -> str:
        return f"{self.quantity} x {self.menu_item.name}"

    @property
    def line_total(self) -> Decimal:
        return self.unit_price * self.quantity


class OrderEvent(models.Model):
    """Audit trail for an order: who did what and when — who confirmed it, who
    pressed "ready" on a station, who delivered, who removed an item. Keeps the
    accountability the paper ticket never had."""

    class Action(models.TextChoices):
        CREATED = "created", "Created"
        CONFIRMED = "confirmed", "Confirmed"
        REJECTED = "rejected", "Rejected"
        ITEM_READY = "item_ready", "Marked ready"
        ITEM_DELIVERED = "item_delivered", "Delivered"
        ITEM_UNDELIVERED = "item_undelivered", "Undelivered"
        ITEM_DELETED = "item_deleted", "Item removed"
        STATUS = "status", "Status changed"

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="events")
    actor = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="order_events",
        null=True,
        blank=True,
    )
    action = models.CharField(max_length=32, choices=Action.choices, db_index=True)
    detail = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "cafe_order_events"
        ordering = ["created_at"]

    def __str__(self) -> str:
        who = self.actor.name if self.actor else "—"
        return f"{who} {self.action} on order #{self.order_id}"


class AttentionSignal(models.Model):
    class Type(models.TextChoices):
        ARRIVED = "arrived", "Arrived"
        CALL_WAITER = "call_waiter", "Call waiter"
        BILL_REQUEST = "bill_request", "Bill request"

    table = models.ForeignKey(Table, on_delete=models.CASCADE, related_name="attention_signals")
    signal_type = models.CharField(max_length=24, choices=Type.choices, db_index=True)
    reason = models.CharField(max_length=255, blank=True)
    ack = models.BooleanField(default=False)
    # Alert ladder L3: a device that saw the signal go unhandled for 60s flags
    # it here so EVERY on-shift device highlights it. Cleared implicitly by
    # the ack (the alert lifecycle ends there); kept for the audit trail.
    alert_escalated = models.BooleanField(default=False)
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
        indexes = [
            # Bootstrap prefetches unacked signals per table.
            models.Index(fields=["table", "ack"], name="signal_table_ack_idx"),
        ]

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
        constraints = [
            models.CheckConstraint(check=models.Q(volume__lte=100), name="staffpref_volume_lte_100"),
        ]

    def __str__(self) -> str:
        return f"Preferences for {self.user}"


class SocialPost(models.Model):
    """One social-media post on the venue's guest feed.

    `embed_html` is generated exclusively by apps.core.social_embed from a
    whitelist-validated URL — raw user-provided HTML is never stored, so the
    guest page may inject it as trusted markup.
    """

    class Platform(models.TextChoices):
        INSTAGRAM = "instagram", "Instagram"
        THREADS = "threads", "Threads"
        TWITTER_X = "twitter_x", "X (Twitter)"
        FACEBOOK = "facebook", "Facebook"

    source_url = models.URLField(max_length=500)
    platform = models.CharField(max_length=24, choices=Platform.choices, db_index=True)
    embed_html = models.TextField(blank=True)
    is_hidden = models.BooleanField(default=False)
    is_pinned = models.BooleanField(default=False)
    pinned_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    created_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="social_posts",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "cafe_social_posts"
        # Pinned first (newest pin leads), then reverse-chronological. The
        # guest feed and the staff list both read in exactly this order.
        ordering = ["-is_pinned", "-pinned_at", "-id"]
        indexes = [
            # The guest feed query: visible posts, pinned first, newest first.
            models.Index(fields=["is_hidden", "-is_pinned", "-id"], name="socialpost_feed_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.get_platform_display()}: {self.source_url}"

    def pin(self) -> None:
        self.is_pinned = True
        self.pinned_at = timezone.now()
        self.save(update_fields=["is_pinned", "pinned_at"])

    def unpin(self) -> None:
        self.is_pinned = False
        self.pinned_at = None
        self.save(update_fields=["is_pinned", "pinned_at"])


HEX_COLOR_VALIDATOR = RegexValidator(
    regex=r"^#[0-9a-fA-F]{6}$",
    message="Enter a color as #RRGGBB (e.g. #C8821E).",
)


def _default_badges() -> list:
    return [
        {"en": "Coffee & hot chocolate", "it": "Caffè e cioccolata"},
        {"en": "Aperitifs & cocktails", "it": "Aperitivi e cocktail"},
        {"en": "Sweet and savory snacks", "it": "Dolce e salato"},
    ]


def _default_storefront_blocks() -> list:
    """Storefront blocks in the guest page's current visual order. Every block
    visible by default — a fresh install must render exactly today's page."""
    return [
        {"key": "cover", "visible": True},
        {"key": "facts", "visible": True},
        {"key": "badges", "visible": True},
        {"key": "cta", "visible": True},
        {"key": "popular", "visible": True},
        {"key": "about", "visible": True},
    ]


class VenueSettings(models.Model):
    """The venue's storefront: everything the guest /menu/ page shows about
    the place, plus its visual theme (palette, logo, cover, block layout).

    One record per installation today, addressed by `slug="default"` via
    get_solo(). Designed as a future per-Venue entity: all reads go through
    get_solo()/the slug, the cache key is slug-scoped, and nothing assumes
    pk=1 — when several venues share one hub, this becomes a FK lookup with
    no architectural rewrite. Field defaults ARE the approved Sissi design:
    a row created with zero configuration renders the guest page
    pixel-for-pixel as before.
    """

    STOREFRONT_BLOCK_KEYS = ("cover", "facts", "badges", "cta", "popular", "about")
    PALETTE_FIELDS = (
        # (model field, CSS variable)
        ("color_bg", "--bg"),
        ("color_card", "--card"),
        ("color_ink", "--ink"),
        ("color_mut", "--mut"),
        ("color_line", "--line"),
        ("color_accent", "--accent"),
        ("color_accent_deep", "--accent-deep"),
        ("color_accent_soft", "--accent-soft"),
    )

    slug = models.SlugField(max_length=40, unique=True, default="default")

    name = models.CharField(max_length=120, default="Caffè & Bistrò Sissi")
    tagline = models.CharField(
        max_length=200, default="Café, bistro and bar in Madonna di Campiglio"
    )
    tagline_it = models.CharField(
        max_length=200, default="Caffè, bistrot e bar a Madonna di Campiglio"
    )
    about = models.TextField(
        default=(
            "A warm mountain bistro for coffee, aperitifs, cocktails, sandwiches, "
            "sweet treats and quick dishes from the Sissi menu."
        )
    )
    about_it = models.TextField(
        default=(
            "Un bistrot di montagna per caffetteria, aperitivi, cocktail, panini, "
            "dolci e piatti veloci dal menu Sissi."
        )
    )
    address = models.CharField(max_length=200, default="Madonna di Campiglio · Trentino")
    address_it = models.CharField(max_length=200, default="Madonna di Campiglio · Trentino")
    hours = models.CharField(max_length=200, default="Ask staff for today's hours")
    hours_it = models.CharField(max_length=200, default="Chiedi allo staff gli orari di oggi")
    badges = models.JSONField(default=_default_badges, blank=True)
    maps_url = models.URLField(
        max_length=500, blank=True, default="https://maps.app.goo.gl/L8UMd16ZXUTk5Jx28"
    )

    logo = models.ImageField(
        upload_to=venue_image_path, storage=venue_media_storage, blank=True, null=True
    )
    cover = models.ImageField(
        upload_to=venue_image_path, storage=venue_media_storage, blank=True, null=True
    )

    # The guest page palette — the 8 :root CSS variables. Defaults are the
    # approved Sissi look (see apps.core.theme_presets.SISSI_PALETTE).
    color_bg = models.CharField(max_length=7, default=SISSI_PALETTE["bg"], validators=[HEX_COLOR_VALIDATOR])
    color_card = models.CharField(max_length=7, default=SISSI_PALETTE["card"], validators=[HEX_COLOR_VALIDATOR])
    color_ink = models.CharField(max_length=7, default=SISSI_PALETTE["ink"], validators=[HEX_COLOR_VALIDATOR])
    color_mut = models.CharField(max_length=7, default=SISSI_PALETTE["mut"], validators=[HEX_COLOR_VALIDATOR])
    color_line = models.CharField(max_length=7, default=SISSI_PALETTE["line"], validators=[HEX_COLOR_VALIDATOR])
    color_accent = models.CharField(max_length=7, default=SISSI_PALETTE["accent"], validators=[HEX_COLOR_VALIDATOR])
    color_accent_deep = models.CharField(max_length=7, default=SISSI_PALETTE["accent_deep"], validators=[HEX_COLOR_VALIDATOR])
    color_accent_soft = models.CharField(max_length=7, default=SISSI_PALETTE["accent_soft"], validators=[HEX_COLOR_VALIDATOR])

    storefront_blocks = models.JSONField(default=_default_storefront_blocks, blank=True)
    pinned_posts_limit = models.PositiveSmallIntegerField(default=3)
    # When the bot posts the recurring checklists into the general chat and
    # when it sends the single "still unfinished" nudge (venue-local time).
    opening_checklist_time = models.TimeField(null=True, blank=True)
    opening_checklist_deadline = models.TimeField(null=True, blank=True)
    closing_checklist_time = models.TimeField(null=True, blank=True)
    closing_checklist_deadline = models.TimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_venue_settings"
        verbose_name_plural = "venue settings"

    def __str__(self) -> str:
        return f"Venue settings ({self.slug})"

    # --- singleton access + cache -------------------------------------------

    _CACHE_TTL = 300  # the save() invalidation is what matters; TTL is a net

    @classmethod
    def _cache_key(cls, slug: str = "default") -> str:
        return f"venue-settings:{slug}"

    @classmethod
    def get_solo(cls, slug: str = "default") -> "VenueSettings":
        """The venue's settings, cached. Creates the row with the Sissi
        defaults on first access so a clean DB still renders the approved
        design with zero configuration."""
        cached = cache.get(cls._cache_key(slug))
        if cached is not None:
            return cached
        instance, _ = cls.objects.get_or_create(slug=slug)
        cache.set(cls._cache_key(slug), instance, cls._CACHE_TTL)
        return instance

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        cache.delete(self._cache_key(self.slug))

    def delete(self, *args, **kwargs):
        cache.delete(self._cache_key(self.slug))
        return super().delete(*args, **kwargs)

    # --- template/API helpers -------------------------------------------------

    @property
    def logo_url(self) -> str:
        return self.logo.url if self.logo else ""

    @property
    def cover_url(self) -> str:
        return self.cover.url if self.cover else ""

    def palette(self) -> dict:
        """Palette keyed like theme presets: bg/card/ink/mut/line/accent/…"""
        return {
            css_var.lstrip("-").replace("-", "_"): getattr(self, field)
            for field, css_var in self.PALETTE_FIELDS
        }

    def css_variables(self) -> list[tuple[str, str]]:
        """[('--bg', '#f2efe8'), …] for the guest page :root block."""
        return [(css_var, getattr(self, field)) for field, css_var in self.PALETTE_FIELDS]

    # Derived surface/text tints. The guest page's original CSS used literal
    # warm tints (rgba(30,27,22,.62), #f8f4ed, …); for the palette to actually
    # re-skin the page they must follow the venue colors. Computed here in
    # Python — not CSS color-mix() — so old phone browsers need nothing new
    # and the default palette reproduces the historical values exactly.

    # (token, palette key, alpha) — rgba(base, alpha); for the Sissi palette
    # each equals the original literal by construction.
    _ALPHA_TINTS = (
        ("--accent-a10", "accent", 0.1),
        ("--accent-a38", "accent", 0.38),
        ("--accent-a45", "accent", 0.45),
        ("--accent-a70", "accent", 0.7),
        ("--accent-deep-a35", "accent_deep", 0.35),
        ("--ink-a46", "ink", 0.46),
        ("--ink-a55", "ink", 0.55),
        ("--ink-a58", "ink", 0.58),
        ("--ink-a60", "ink", 0.6),
        ("--ink-a62", "ink", 0.62),
        ("--ink-a64", "ink", 0.64),
        ("--ink-a66", "ink", 0.66),
        ("--ink-a68", "ink", 0.68),
        ("--ink-a72", "ink", 0.72),
        ("--ink-a82", "ink", 0.82),
        ("--line-a62", "line", 0.62),
        ("--line-a72", "line", 0.72),
        ("--line-a76", "line", 0.76),
        ("--line-a78", "line", 0.78),
        ("--line-a86", "line", 0.86),
        ("--bg-a92", "bg", 0.92),
        ("--bg-a96", "bg", 0.96),
        ("--card-a94", "card", 0.94),
    )

    # Warm neutral surfaces that are NOT a pure alpha of one palette color.
    # For the approved Sissi bg/card they keep their historical literal
    # byte-for-byte; for a custom palette they become card/bg blends so a
    # dark or tinted theme stays coherent.
    # (token, sissi literal, card weight in the card/bg blend, alpha or None)
    _NEUTRAL_TINTS = (
        ("--surface-hi", "#fffdfa", 0.9, None),   # search field, chips, menu cards
        ("--surface-mid", "#faf8f3", 0.7, None),  # fact pills
        ("--surface-low", "#f8f4ed", 0.5, None),  # cart lines, dish tags
        ("--surface-soft", "#fbf6ed", 0.6, None), # category header gradient end
        ("--surface-dim", "#f4f0e8", 0.25, None), # close buttons
        ("--surface-sunken", "#ece6db", 0.0, None),  # progress steps (≈ bg-line blend)
        ("--surface-count", "#f6efe4", 0.35, None),  # category count chip
        ("--surface-note", "#fff5ec", 0.85, None),   # guest note card
        ("--nav-a92", "rgba(252,250,245,.92)", 0.8, 0.92),  # back button, photo chips
        ("--nav-a94", "rgba(252,250,245,.94)", 0.8, 0.94),  # bottom navigation
        ("--nav-a96", "rgba(252,250,245,.96)", 0.8, 0.96),  # detail action bar
    )

    @staticmethod
    def _rgb(hex_color: str) -> tuple[int, int, int]:
        value = hex_color.lstrip("#")
        return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)

    def derived_css(self) -> list[tuple[str, str]]:
        bases = {key: self._rgb(value) for key, value in self.palette().items()}
        tokens = []
        for token, key, alpha in self._ALPHA_TINTS:
            r, g, b = bases[key]
            alpha_text = f"{alpha:.2f}".rstrip("0").rstrip(".")
            tokens.append((token, f"rgba({r},{g},{b},{alpha_text})"))

        default_neutrals = (
            self.color_bg.lower() == SISSI_PALETTE["bg"]
            and self.color_card.lower() == SISSI_PALETTE["card"]
        )
        card, bg = bases["card"], bases["bg"]
        for token, literal, card_weight, alpha in self._NEUTRAL_TINTS:
            if default_neutrals:
                tokens.append((token, literal))
                continue
            r, g, b = (
                round(card[i] * card_weight + bg[i] * (1 - card_weight)) for i in range(3)
            )
            if alpha is None:
                tokens.append((token, f"#{r:02x}{g:02x}{b:02x}"))
            else:
                alpha_text = f"{alpha:.2f}".rstrip("0").rstrip(".")
                tokens.append((token, f"rgba({r},{g},{b},{alpha_text})"))
        return tokens

    def blocks(self) -> list[dict]:
        """Sanitized storefront blocks: known keys only, missing blocks
        appended visible in default order — a partial/corrupt JSON value can
        hide data but never crash the guest page."""
        cleaned, seen = [], set()
        for entry in self.storefront_blocks or []:
            key = entry.get("key") if isinstance(entry, dict) else None
            if key in self.STOREFRONT_BLOCK_KEYS and key not in seen:
                cleaned.append({"key": key, "visible": bool(entry.get("visible", True))})
                seen.add(key)
        for key in self.STOREFRONT_BLOCK_KEYS:
            if key not in seen:
                cleaned.append({"key": key, "visible": True})
        return cleaned


class PushSubscription(models.Model):
    """One browser's Web-Push subscription (VAPID), bound to a staff member.

    Created when the employee flips "On shift" (after the notification
    permission grant), removed on shift-off and garbage-collected when the
    push service answers 404/410. Endpoints are globally unique — a browser
    re-subscribing simply re-binds its endpoint to the current employee.
    """

    employee = models.ForeignKey(
        Employee, on_delete=models.CASCADE, related_name="push_subscriptions"
    )
    endpoint = models.URLField(max_length=500, unique=True)
    p256dh = models.CharField(max_length=255)
    auth = models.CharField(max_length=255)
    user_agent = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "cafe_push_subscriptions"

    def __str__(self) -> str:
        return f"Push for {self.employee.name} ({self.endpoint[:40]}…)"


# ---------------------------------------------------------------------------
# Guest coupons: wallet identity, campaigns, issued coupons
# ---------------------------------------------------------------------------


class GuestWallet(models.Model):
    """A guest's coupon wallet — identity without registration.

    Deliberately NOT keyed to the Django session (sessions expire and rotate):
    the primary key is a UUID carried by a signed, httpOnly, 1-year cookie set
    lazily on the first coupon claim, so guests who never touch a coupon stay
    cookie-free. The signed recovery link (see apps.core.coupons) re-attaches
    the same wallet on any device. `user` is the future hook for real guest
    accounts — intentionally unused today.
    """

    token = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="guest_wallets",
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(default=timezone.now)

    # Throttle last_seen writes: wallet reads happen on every Wallet-tab open.
    _SEEN_WRITE_INTERVAL = timedelta(minutes=15)

    class Meta:
        db_table = "cafe_guest_wallets"

    def __str__(self) -> str:
        return f"Wallet {self.token}"

    def touch(self) -> None:
        now = timezone.now()
        if now - self.last_seen_at >= self._SEEN_WRITE_INTERVAL:
            self.last_seen_at = now
            self.save(update_fields=["last_seen_at"])


class CouponCampaign(models.Model):
    """A discount campaign: the SMM/marketing object coupons are minted from.

    Venue-ready like VenueSettings: nothing assumes a single venue except the
    absence of a venue FK — adding one later is a plain schema change, all
    queries already go through the campaign row.
    """

    class DiscountType(models.TextChoices):
        PERCENT = "percent", "Percent"
        FIXED = "fixed", "Fixed amount"

    # Human slug: marketing links are /menu/?c=<slug>&utm_source=… .
    slug = models.SlugField(max_length=60, unique=True)
    title = models.CharField(max_length=120)
    title_it = models.CharField(max_length=120, blank=True)
    description = models.TextField(blank=True)
    description_it = models.TextField(blank=True)
    discount_type = models.CharField(max_length=16, choices=DiscountType.choices)
    discount_value = models.DecimalField(max_digits=8, decimal_places=2)
    # Default ad tag; the actual incoming utm_source is recorded per coupon.
    source_utm = models.SlugField(max_length=64, blank=True)
    valid_from = models.DateTimeField(null=True, blank=True)
    valid_until = models.DateTimeField(null=True, blank=True)
    max_total_issues = models.PositiveIntegerField(null=True, blank=True)
    per_wallet_limit = models.PositiveSmallIntegerField(default=1)
    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="coupon_campaigns",
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_coupon_campaigns"
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.title

    def clean(self):
        if self.discount_value is None or self.discount_value <= 0:
            raise ValidationError({"discount_value": "The discount must be greater than zero."})
        if self.discount_type == self.DiscountType.PERCENT and self.discount_value > 100:
            raise ValidationError({"discount_value": "A percent discount cannot exceed 100%."})
        if self.valid_from and self.valid_until and self.valid_from >= self.valid_until:
            raise ValidationError({"valid_until": "The campaign must end after it starts."})

    def window_state(self, now=None) -> str:
        """'pending' | 'open' | 'expired' relative to the validity window."""
        now = now or timezone.now()
        if self.valid_from and now < self.valid_from:
            return "pending"
        if self.valid_until and now > self.valid_until:
            return "expired"
        return "open"


class IssuedCoupon(models.Model):
    """One coupon in one guest wallet, minted from a campaign.

    Lifecycle: ACTIVE → REDEEMED (staff scan, atomic single-use) with EXPIRED
    (campaign window passed) and VOID (staff invalidated) as terminal side
    exits; a manager may return a REDEEMED coupon of a cancelled order to
    ACTIVE (apps.core.coupons.void_redemption).
    """

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        REDEEMED = "redeemed", "Redeemed"
        EXPIRED = "expired", "Expired"
        VOID = "void", "Void"

    class IssuedVia(models.TextChoices):
        STAFF_QR = "staff_qr", "Staff QR"
        CAMPAIGN_LINK = "campaign_link", "Campaign link"

    campaign = models.ForeignKey(
        CouponCampaign, on_delete=models.CASCADE, related_name="coupons"
    )
    wallet = models.ForeignKey(
        GuestWallet, on_delete=models.CASCADE, related_name="coupons"
    )
    # Short human-readable code (unambiguous alphabet, see coupons.py) — the
    # fallback when a camera won't scan.
    code = models.CharField(max_length=12, unique=True)
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.ACTIVE, db_index=True
    )
    issued_via = models.CharField(max_length=24, choices=IssuedVia.choices)
    # Incoming ad tag recorded at claim time — drives per-campaign analytics.
    utm_source = models.CharField(max_length=64, blank=True)
    issued_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="issued_coupons",
        null=True,
        blank=True,
    )
    redeemed_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="redeemed_coupons",
        null=True,
        blank=True,
    )
    redeemed_at = models.DateTimeField(null=True, blank=True)
    order = models.ForeignKey(
        Order,
        on_delete=models.SET_NULL,
        related_name="redeemed_coupons",
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_issued_coupons"
        ordering = ["-created_at"]
        indexes = [
            # The wallet screen: a guest's coupons, newest first.
            models.Index(fields=["wallet", "status", "-created_at"], name="coupon_wallet_status_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.code} ({self.get_status_display()})"


# ---------------------------------------------------------------------------
# Staff chat + tasks: the messenger and the owner's day planner share these
# ---------------------------------------------------------------------------


class StaffTask(models.Model):
    """A task as a first-class object, shared between chat and the planner.

    Created from chat (/task), from the planner quick-add, or by the bot
    (checklists, recurrence). A task with `recurrence != NONE` is a RULE: the
    scheduler materializes one instance per matching day (instances carry
    `recurring_parent`), so day lists only ever show plain instances.
    """

    class Category(models.TextChoices):
        OPENING = "opening", "Opening"
        CLOSING = "closing", "Closing"
        CLEANING = "cleaning", "Cleaning"
        INVENTORY = "inventory", "Inventory"
        SERVICE = "service", "Service"
        OTHER = "other", "Other"

    class Recurrence(models.TextChoices):
        NONE = "none", "None"
        DAILY = "daily", "Daily"
        WEEKLY = "weekly", "Weekly"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        DONE = "done", "Done"
        CANCELLED = "cancelled", "Cancelled"

    class Source(models.TextChoices):
        CHAT = "chat", "Chat"
        PLANNER = "planner", "Planner"
        BOT = "bot", "Bot"

    title = models.CharField(max_length=200)
    note = models.TextField(blank=True)
    category = models.CharField(
        max_length=24, choices=Category.choices, default=Category.OTHER, db_index=True
    )
    # Null assignee = anyone on shift may pick it up.
    assignee = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="tasks_assigned",
        null=True,
        blank=True,
    )
    created_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="tasks_created",
        null=True,
        blank=True,
    )
    due_at = models.DateTimeField(null=True, blank=True, db_index=True)
    recurrence = models.CharField(
        max_length=16, choices=Recurrence.choices, default=Recurrence.NONE
    )
    # Weekly rules: ISO weekday numbers 0=Mon .. 6=Sun.
    recurrence_weekdays = models.JSONField(default=list, blank=True)
    recurring_parent = models.ForeignKey(
        "self",
        on_delete=models.CASCADE,
        related_name="occurrences",
        null=True,
        blank=True,
    )
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.OPEN, db_index=True
    )
    done_by = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="tasks_done",
        null=True,
        blank=True,
    )
    done_at = models.DateTimeField(null=True, blank=True)
    source = models.CharField(max_length=16, choices=Source.choices, default=Source.CHAT)
    # Checklist provenance: which template item spawned this task (progress bars).
    template_item = models.ForeignKey(
        "ChecklistItem",
        on_delete=models.SET_NULL,
        related_name="spawned_tasks",
        null=True,
        blank=True,
    )
    # Exactly one gentle overdue nudge, posted into the task's chat thread.
    overdue_nudged_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_staff_tasks"
        ordering = ["-created_at"]
        indexes = [
            # The planner's day query and the overdue sweep.
            models.Index(fields=["status", "due_at"], name="task_status_due_idx"),
        ]

    def __str__(self) -> str:
        return self.title

    @property
    def is_recurring_rule(self) -> bool:
        return self.recurrence != self.Recurrence.NONE


class ChatMessage(models.Model):
    """One append-only message in the staff chat. `author` null = CafeBot.
    `reply_to` makes Telegram-style threads; `task` links a task bubble to
    its live StaffTask (the bubble re-renders from the task's state)."""

    class Channel(models.TextChoices):
        GENERAL = "general", "General"
        KITCHEN = "kitchen", "Kitchen"
        BAR = "bar", "Bar"

    class Kind(models.TextChoices):
        TEXT = "text", "Text"
        TASK = "task", "Task"
        CHECKLIST = "checklist", "Checklist"
        SYSTEM = "system", "System"

    channel = models.CharField(max_length=16, choices=Channel.choices, db_index=True)
    author = models.ForeignKey(
        Employee,
        on_delete=models.SET_NULL,
        related_name="chat_messages",
        null=True,
        blank=True,
    )
    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.TEXT)
    body = models.TextField(blank=True)
    task = models.ForeignKey(
        StaffTask,
        on_delete=models.SET_NULL,
        related_name="messages",
        null=True,
        blank=True,
    )
    reply_to = models.ForeignKey(
        "self",
        on_delete=models.SET_NULL,
        related_name="replies",
        null=True,
        blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "cafe_chat_messages"
        # Cursor pagination walks ids downward (imitates the guest feed).
        ordering = ["-id"]
        indexes = [
            models.Index(fields=["channel", "-id"], name="chat_channel_id_idx"),
        ]

    def __str__(self) -> str:
        who = self.author.name if self.author else "CafeBot"
        return f"{who} in {self.channel}: {self.body[:40]}"


class ChatReadMark(models.Model):
    """Per-employee, per-channel high-water mark for unread badges."""

    employee = models.ForeignKey(
        Employee, on_delete=models.CASCADE, related_name="chat_read_marks"
    )
    channel = models.CharField(max_length=16, choices=ChatMessage.Channel.choices)
    last_read_message_id = models.BigIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_chat_read_marks"
        constraints = [
            models.UniqueConstraint(
                fields=["employee", "channel"], name="chat_read_unique"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.employee.name} read {self.channel} up to #{self.last_read_message_id}"


class ChecklistTemplate(models.Model):
    """A recurring checklist (Opening / Closing seeded; manager-editable).
    Post + nudge times live in VenueSettings."""

    key = models.SlugField(max_length=40, unique=True)
    title = models.CharField(max_length=120)
    title_it = models.CharField(max_length=120, blank=True)
    task_category = models.CharField(
        max_length=24,
        choices=StaffTask.Category.choices,
        default=StaffTask.Category.OTHER,
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "cafe_checklist_templates"

    def __str__(self) -> str:
        return self.title


class ChecklistItem(models.Model):
    template = models.ForeignKey(
        ChecklistTemplate, on_delete=models.CASCADE, related_name="items"
    )
    text = models.CharField(max_length=200)
    text_it = models.CharField(max_length=200, blank=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        db_table = "cafe_checklist_items"
        ordering = ["sort_order", "id"]

    def __str__(self) -> str:
        return self.text


class BotReminder(models.Model):
    """A /remind job: the bot posts [text] into [channel] at [remind_at].
    Reminders ride alert Level 1 only — they never escalate."""

    channel = models.CharField(max_length=16, choices=ChatMessage.Channel.choices)
    text = models.CharField(max_length=300)
    remind_at = models.DateTimeField(db_index=True)
    created_by = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name="bot_reminders",
    )
    posted_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "cafe_bot_reminders"
        ordering = ["remind_at"]

    def __str__(self) -> str:
        return f"remind {self.remind_at:%H:%M}: {self.text[:40]}"


class BotJobRun(models.Model):
    """Idempotency marker for scheduler jobs: one row per job key, so a
    doubled run (cron + in-process ticker, or two web processes) posts once.
    The unique constraint IS the lock — the loser of the race hits it."""

    job_key = models.CharField(max_length=120, unique=True)
    ran_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "cafe_bot_job_runs"

    def __str__(self) -> str:
        return self.job_key
