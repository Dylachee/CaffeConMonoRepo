import mimetypes
from datetime import date

from django.conf import settings
from django.contrib import messages
from django.core.cache import cache
from django.db import transaction
from django.http import FileResponse, Http404, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_GET, require_POST

from apps.api.events import broadcast_attention_event, broadcast_order_event, broadcast_table_event
from apps.core.menu_i18n import category_labels, menu_item_labels
from apps.core.models import AttentionSignal, MenuItem, Order, OrderItem, Table
from apps.core.services import acknowledge_signal_on_table, apply_signal_to_table


# Venue "storefront" shown on the guest page. Static for now — when venues
# become configurable this moves to a model; keeping it in one place makes
# that swap a one-liner in menu_page.
VENUE = {
    "name": "Sissi Bistro Bar",
    "tagline": "Bistro and bar · European kitchen · cozy room",
    "tagline_it": "Bistrot e bar · cucina europea · sala accogliente",
    "about": (
        "A small bistro in the center. We cook with seasonal products, "
        "serve specialty coffee, and keep a short, honest bar list."
    ),
    "about_it": (
        "Un piccolo bistrot in centro. Cuciniamo con prodotti stagionali, "
        "serviamo specialty coffee e teniamo una carta bar breve e sincera."
    ),
    "address": "Kievskaya St. 77 · ground floor",
    "address_it": "Via Kievskaya 77 · piano terra",
    "hours": "Daily 10:00–23:00",
    "hours_it": "Tutti i giorni 10:00–23:00",
    "badges": [
        {"en": "Vegan options", "it": "Opzioni vegane"},
        {"en": "Specialty coffee", "it": "Specialty coffee"},
        {"en": "All-day breakfast", "it": "Colazione tutto il giorno"},
    ],
    "rating": "4.9",
    "reviews": "320 reviews",
    "reviews_it": "320 recensioni",
}


ORDER_STATUS_LABELS = {
    Order.Status.AWAITING: "Sent — waiting for staff to confirm",
    Order.Status.NEW: "Order accepted",
    Order.Status.COOKING: "Preparing your order",
    Order.Status.READY: "Order is ready",
    Order.Status.COMPLETED: "Order served",
    Order.Status.PAID: "Order paid",
    Order.Status.CANCELLED: "Order cancelled",
}

VALID_UNTIL_TAG = "valid_until:"


MENU_VISUALS = {
    "aperitivi": ("drink", "🍹"),
    "bevande": ("drink", "🥤"),
    "birra": ("drink", "🍺"),
    "caffetteria": ("coffee", "☕"),
    "cocktails": ("drink", "🍸"),
    "colazione": ("breakfast", "🥐"),
    "cucina": ("hot", "🍽"),
    "dolci": ("dessert", "🍰"),
    "gelati": ("dessert", "🍨"),
    "menu del giorno": ("hot", "🍽"),
    "panini": ("hot", "🍔"),
    "vino": ("drink", "🍷"),
}


def menu_page(request, table_id=None, table_number=None):
    """Guest QR page: storefront, menu, cart checkout and service signals."""
    menu_items = MenuItem.objects.order_by("category", "-is_available", "name")
    # Two ways to address a table:
    #   /menu/t/<pk>/     — legacy, internal DB id (kept for old links);
    #   /menu/n/<number>/ — the printed table number. QR codes should use this
    #     one: it survives reseeding/recreating the DB, a pk does not.
    if table_number is not None:
        table = get_object_or_404(Table, number=table_number)
    else:
        table = get_object_or_404(Table, pk=table_id) if table_id is not None else None

    # menu_items is ordered by (category, name), so grouping is a single pass.
    sections = []
    sections_by_name = {}
    menu_payload = []
    visible_items = []
    for item in menu_items:
        if not item.is_available or _menu_item_expired(item) or _menu_item_archived(item):
            continue
        # Printed-menu price style: comma decimal, always two digits («4,50»).
        item.price_str = f"{item.price:.2f}".replace(".", ",")
        display_category = "Menu del giorno" if _menu_item_is_daily(item) else item.category
        item.menu_category = display_category
        item.visual_key, item.visual_icon = _menu_visual(display_category)
        labels = menu_item_labels(item)
        item.name_en = labels["name_en"]
        item.name_it = labels["name_it"]
        item.description_en = labels["description_en"]
        item.description_it = labels["description_it"]
        cat_labels = category_labels(display_category)
        item.category_en = cat_labels["en"]
        item.category_it = cat_labels["it"]
        menu_payload.append(
            {
                "id": item.pk,
                "name": item.name_en,
                "nameEn": item.name_en,
                "nameIt": item.name_it,
                "description": item.description_en,
                "descriptionEn": item.description_en,
                "descriptionIt": item.description_it,
                "price": float(item.price),
                "priceText": item.price_str,
                "category": display_category,
                "categoryEn": item.category_en,
                "categoryIt": item.category_it,
                "imageUrl": item.image_url,
                "tags": item.tags,
                "composition": item.composition,
                "allergens": item.allergens,
                "available": item.is_available,
                "promoted": item.is_promoted,
                "prep": item.preparation_minutes,
                "portionWeight": item.portion_weight,
                "calories": item.calories,
                "visualKey": item.visual_key,
                "visualIcon": item.visual_icon,
            }
        )
        visible_items.append(item)
        section = sections_by_name.get(display_category)
        if section is None:
            section = (
                {
                    "name": display_category,
                    "name_en": cat_labels["en"],
                    "name_it": cat_labels["it"],
                    "items": [],
                }
            )
            sections.append(section)
            sections_by_name[display_category] = section
        section["items"].append(item)
    for section in sections:
        section["items"].sort(
            key=lambda i: (not i.is_available, (i.name_it or i.name_en or i.name).lower())
        )
    visible_items.sort(key=lambda i: (not i.is_available, (i.name_it or i.name_en or i.name).lower()))
    sections.sort(key=lambda s: (s["name"] != "Menu del giorno", s["name_it"]))
    featured_items = [
        item
        for item in visible_items
        if item.is_available and (item.menu_category == "Menu del giorno")
    ]
    if not featured_items:
        featured_items = [
            item
            for item in visible_items
            if item.is_available and "popular" in (item.tags or [])
        ]

    return render(
        request,
        "guest_web/menu.html",
        {
            "featured_items": featured_items,
            "menu_sections": sections,
            "menu_items": visible_items,
            "menu_payload": menu_payload,
            "table": table,
            "venue": VENUE,
        },
    )


def prototype_page(request):
    prototype_path = settings.BASE_DIR / "static" / "prototypes" / "guest.html"
    return FileResponse(open(prototype_path, "rb"), content_type="text/html; charset=utf-8")


# ---------------------------------------------------------------------------
# Staff PWA — serves the compiled Flutter web build from static/staff/
# ---------------------------------------------------------------------------

_STAFF_BUILD = settings.BASE_DIR / "static" / "staff"

# These are the PWA's own "is there a new deploy?" entry points. Flutter's
# service worker versions everything else (main.dart.js, canvaskit/, assets/)
# by content hash internally, but it can only discover a new version by
# actually re-fetching these from the network. If a browser's plain HTTP
# cache serves any of them from disk, the service worker's update check never
# even runs and the PWA can keep showing an old build indefinitely — this is
# the likely cause of a staff device showing stale data (e.g. 12 demo tables
# after seed_bar already created 30) even after the server has a fresh build.
_NO_CACHE_STAFF_FILES = {"index.html", "flutter_service_worker.js", "flutter_bootstrap.js", "version.json"}


def staff_app(request, path=""):
    """Serve the compiled Flutter staff PWA. Unknown paths fall back to index.html
    so Flutter's own router handles in-app navigation."""
    base = _STAFF_BUILD.resolve()
    # Resolve before serving: `<path:path>` accepts `..` and absolute paths, so
    # without this guard `/staff/../backend_core/settings.py` (or `/staff//etc/
    # passwd`) would be read straight off the container filesystem.
    target = (base / path).resolve() if path else base / "index.html"
    if not target.is_relative_to(base) or not target.is_file():
        target = base / "index.html"
    if not target.is_file():
        # No compiled staff build deployed yet (static/staff/ is gitignored).
        # A missing build must be a clear 404, not a FileNotFoundError 500.
        raise Http404("Staff PWA build is not deployed. See RUNBOOK.md.")
    content_type, _ = mimetypes.guess_type(str(target))
    response = FileResponse(open(target, "rb"), content_type=content_type or "application/octet-stream")
    if target.name in _NO_CACHE_STAFF_FILES:
        response["Cache-Control"] = "no-cache, must-revalidate"
    return response


# ---------------------------------------------------------------------------
# Guest forms
# ---------------------------------------------------------------------------

@require_POST
def create_guest_order(request):
    table_id = request.POST.get("table")
    is_fetch = request.headers.get("X-Requested-With") == "fetch"
    # Only numeric ids can match rows; anything else in pk__in raises a 500.
    selected_ids = [s for s in request.POST.getlist("items") if s.isdigit()]

    if not table_id or not selected_ids:
        if is_fetch:
            return JsonResponse({"ok": False, "error": "empty"}, status=400)
        messages.error(request, "Choose a table and at least one item.")
        return _redirect_menu(table_id)

    with transaction.atomic():
        # table_id and quantities come straight from the guest's browser: a
        # non-numeric id or quantity must produce a friendly error, not a 500.
        try:
            table = Table.objects.select_for_update().get(pk=table_id)
        except (Table.DoesNotExist, ValueError):
            if is_fetch:
                return JsonResponse({"ok": False, "error": "table"}, status=404)
            messages.error(request, "Table not found. Please scan the QR code again.")
            return _redirect_menu(None)

        menu_items = [
            item
            for item in MenuItem.objects.filter(pk__in=selected_ids, is_available=True)
            if not _menu_item_expired(item)
        ]
        order_items = []
        for item in menu_items:
            try:
                quantity = int(request.POST.get(f"quantity_{item.pk}", "1") or 1)
            except ValueError:
                quantity = 1
            # Clamp: nobody orders 500 espressos; huge numbers are either a
            # typo or abuse, and both would flood the kitchen feed.
            quantity = min(max(quantity, 1), 50)
            order_items.append(
                OrderItem(
                    menu_item=item,
                    quantity=quantity,
                    unit_price=item.price,
                    station=item.station,  # was missing — all items defaulted to KITCHEN
                )
            )
        if not order_items:
            if is_fetch:
                return JsonResponse({"ok": False, "error": "unavailable"}, status=400)
            messages.error(request, "The selected items are no longer available.")
            return _redirect_menu(table_id)

        # Guest-web orders wait for a waiter to approve them before the
        # kitchen/bar ever see them (source stays guest_web via the model
        # default). A waiter confirms via POST /api/orders/<id>/confirm/.
        order = Order.objects.create(
            table=table,
            status=Order.Status.AWAITING,
            guest_name=request.POST.get("guest_name", "").strip()[:120],
            notes=request.POST.get("notes", "").strip()[:2000],
        )
        for order_item in order_items:
            order_item.order = order
        OrderItem.objects.bulk_create(order_items)

        stations = {oi.station for oi in order_items}
        if len(stations) == 1:
            order.station_scope = stations.pop()
        elif len(stations) > 1:
            order.station_scope = Order.StationScope.MIXED
        order.save(update_fields=["station_scope", "updated_at"])

        # Guests placed an order themselves -> a waiter has to come: WAITING.
        table.status = Table.Status.WAITING
        table.guest_count = max(table.guest_count, 1)
        table.opened_at = table.opened_at or timezone.now()
        table.save(update_fields=["status", "guest_count", "opened_at", "updated_at"])

    broadcast_order_event("created", order)
    broadcast_table_event(table)
    _remember_guest_order(request, order.pk)
    if is_fetch:
        return JsonResponse({"ok": True, "order": _guest_order_payload(order)})
    messages.success(request, f"Order #{order.pk} was sent to staff.")
    return _redirect_menu(table_id)


@require_GET
def guest_order_status(request, order_id):
    if order_id not in request.session.get("guest_orders", []):
        raise Http404("Order is not available in this session.")
    order = get_object_or_404(
        Order.objects.select_related("table").prefetch_related("items", "items__menu_item"),
        pk=order_id,
    )
    return JsonResponse({"ok": True, "order": _guest_order_payload(order)})


@require_POST
def create_attention_signal(request):
    """Guest pressed "Call waiter" (or another signal button).

    Sets the table into the WAITING status, notifies every staff device over
    the realtime feed and answers JSON when called via fetch() so the guest
    page can show an inline confirmation without a full reload.
    """
    table_id = request.POST.get("table")
    table = get_object_or_404(Table, pk=table_id)
    signal_type = request.POST.get("signal_type")
    is_fetch = request.headers.get("X-Requested-With") == "fetch"

    # Per-IP rate limit: every signal pings every staff device, so a stuck
    # button (or someone poking the endpoint) must not flood the floor.
    rate_key = f"attn-rate:{request.META.get('REMOTE_ADDR', '?')}"
    cache.add(rate_key, 0, 60)
    if cache.incr(rate_key) > 6:
        if is_fetch:
            return JsonResponse({"ok": False, "error": "rate limited"}, status=429)
        messages.error(request, "Too many requests. Please wait a minute.")
        return _redirect_menu(table_id)
    if signal_type not in AttentionSignal.Type.values:
        if is_fetch:
            return JsonResponse({"ok": False, "error": "unknown signal"}, status=400)
        messages.error(request, "Unknown signal type.")
        return _redirect_menu(table_id)

    signal = AttentionSignal.objects.create(
        table=table,
        signal_type=signal_type,
        reason=request.POST.get("reason", "").strip(),
    )
    table = apply_signal_to_table(signal, table)
    broadcast_attention_event("created", signal)
    broadcast_table_event(table)
    if is_fetch:
        # signal id lets the guest cancel their own call from the page.
        return JsonResponse(
            {"ok": True, "table_status": table.status, "signal": signal.pk}
        )
    messages.success(request, "A waiter is on the way.")
    return _redirect_menu(table_id)


@require_POST
def cancel_attention_signal(request):
    """Guest pressed "Cancel call" on their own pending signal.

    Marks the signal acknowledged (nobody has to walk over anymore) and rolls
    the table badge back, broadcasting to staff devices — the same path a
    waiter's "Acknowledge" action takes, so the two can't diverge.
    """
    signal_id = request.POST.get("signal")
    signal = get_object_or_404(AttentionSignal, pk=signal_id)
    is_fetch = request.headers.get("X-Requested-With") == "fetch"
    if not signal.ack:
        signal.acknowledge(None)
        table = acknowledge_signal_on_table(signal.table)
        broadcast_attention_event("acked", signal)
        broadcast_table_event(table)
    if is_fetch:
        return JsonResponse({"ok": True})
    return _redirect_menu(signal.table_id)


def _redirect_menu(table_id):
    """Redirect to the table-scoped page when we have a table_id, generic menu otherwise."""
    try:
        return redirect("guest_web:menu-for-table", table_id=int(table_id))
    except (TypeError, ValueError):
        return redirect("guest_web:menu")


def _menu_visual(category):
    return MENU_VISUALS.get((category or "").strip().lower(), ("default", "🍽"))


def _menu_item_expired(item, today=None):
    today = today or timezone.localdate()
    for tag in item.tags or []:
        if not isinstance(tag, str) or not tag.startswith(VALID_UNTIL_TAG):
            continue
        try:
            valid_until = date.fromisoformat(tag.removeprefix(VALID_UNTIL_TAG))
        except ValueError:
            continue
        if today > valid_until:
            return True
    return False


def _menu_item_archived(item):
    return "archived" in (item.tags or [])


def _menu_item_is_daily(item):
    return item.category == "Menu del giorno" or "daily" in (item.tags or [])


def _remember_guest_order(request, order_id):
    orders = request.session.get("guest_orders", [])
    if order_id not in orders:
        request.session["guest_orders"] = (orders + [order_id])[-10:]
        request.session.modified = True


def _guest_order_payload(order):
    return {
        "id": order.pk,
        "status": order.status,
        "statusLabel": ORDER_STATUS_LABELS.get(order.status, "Order accepted"),
        "total": f"{order.total:.2f}",
        "items": [
            {
                "name": menu_item_labels(item.menu_item)["name_en"],
                "quantity": item.quantity,
                "lineTotal": f"{item.line_total:.2f}",
            }
            for item in order.items.all()
        ],
        "createdAt": order.created_at.isoformat(),
    }
