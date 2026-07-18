import mimetypes

from django.conf import settings
from django.contrib import messages
from django.core.cache import cache
from django.db import transaction
from django.http import FileResponse, Http404, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_GET, require_POST

import copy

from apps.api.events import broadcast_attention_event, broadcast_order_event, broadcast_table_event
from apps.api.views_venue import preview_cache_key
from apps.core.menu_i18n import category_labels, menu_item_labels
from apps.core.menu_visibility import (
    guest_visible_menu_items,
    menu_has_client_items,
    menu_item_guest_visible,
)
from apps.core.models import (
    AttentionSignal,
    MenuItem,
    Order,
    OrderItem,
    Restaurant,
    Table,
    VenueSettings,
)
from apps.core.services import acknowledge_signal_on_table, apply_signal_to_table


# The venue "storefront" (name/texts/badges/palette/layout) lives in
# VenueSettings — one editable record, seeded with the approved Sissi design
# by migration 0027. See _venue_for_request below.

POPULAR_ITEM_NAMES = [
    "Cappuccino",
    "Bombardino",
    "Aperol Spritz",
    "Hugo",
    "Analcolico frutta",
    "Strudel di mele",
]

GUEST_CATEGORY_ORDER = [
    "Caffetteria",
    "Bevande",
    "Analcolici",
    "Birra",
    "Vino",
    "Cocktail & Aperitivi",
    "Liquori/Grappe/Amari",
    "Pasticceria",
    "Dolci",
    "Gelati",
    "Panini",
    "Piadine",
    "Tortel",
    "Secondi",
    "Uova/colazione salata",
    "Toast",
    "Fritti/stuzzichini",
]


ORDER_STATUS_LABELS = {
    Order.Status.AWAITING: "Sent — waiting for staff to confirm",
    Order.Status.NEW: "Order accepted",
    Order.Status.COOKING: "Preparing your order",
    Order.Status.READY: "Order is ready",
    Order.Status.COMPLETED: "Order served",
    Order.Status.PAID: "Order paid",
    Order.Status.CANCELLED: "Order cancelled",
}

MENU_VISUALS = {
    "analcolici": ("drink", "🥤"),
    "bevande": ("drink", "🥤"),
    "birra": ("drink", "🍺"),
    "caffetteria": ("coffee", "☕"),
    "cocktail & aperitivi": ("drink", "🍸"),
    "dolci": ("dessert", "🍰"),
    "fritti/stuzzichini": ("hot", "🍟"),
    "gelati": ("dessert", "🍨"),
    "liquori/grappe/amari": ("drink", "🥃"),
    "panini": ("hot", "🍔"),
    "pasticceria": ("breakfast", "🥐"),
    "piadine": ("hot", "🫓"),
    "secondi": ("hot", "🍽"),
    "toast": ("hot", "🥪"),
    "tortel": ("hot", "🍽"),
    "uova/colazione salata": ("breakfast", "🍳"),
    "vino": ("drink", "🍷"),
}


# Fallback colors for legacy/unassigned categories. Current data uses
# MenuCategory.color directly.
_CATEGORY_COLORS = {
    "caffetteria": "#E0823A",
    "bevande": "#5BAEDC",
    "analcolici": "#3E9C63",
    "birra": "#DFAF2B",
    "vino": "#C0463B",
    "cocktail": "#7CC488",
    "liquori": "#8A6FC0",
    "pasticceria": "#B88746",
    "dolci": "#C95F8A",
    "gelati": "#3C7BCF",
    "panini": "#DFAF2B",
    "piadine": "#C9A227",
    "tortel": "#B97832",
    "secondi": "#A94D3E",
    "uova": "#6F8F42",
    "toast": "#9A7A45",
    "fritti": "#B66A2D",
}


def _category_color(category):
    c = (category or "").lower()

    def has(*keys):
        return any(k in c for k in keys)

    if has("caffett", "coffee"):
        return _CATEGORY_COLORS["caffetteria"]
    if has("analcolic"):
        return _CATEGORY_COLORS["analcolici"]
    if has("birra"):
        return _CATEGORY_COLORS["birra"]
    if has("gelat"):
        return _CATEGORY_COLORS["gelati"]
    if has("dolc", "dessert"):
        return _CATEGORY_COLORS["dolci"]
    if has("pasticc", "colazione"):
        return _CATEGORY_COLORS["pasticceria"]
    if has("liquor", "grapp", "amari"):
        return _CATEGORY_COLORS["liquori"]
    if has("vino", "wine"):
        return _CATEGORY_COLORS["vino"]
    if has("aperitiv", "cocktail", "spritz"):
        return _CATEGORY_COLORS["cocktail"]
    if has("bibit", "bevand", "analcolic", "succ"):
        return _CATEGORY_COLORS["bevande"]
    if has("piadine"):
        return _CATEGORY_COLORS["piadine"]
    if has("tortel"):
        return _CATEGORY_COLORS["tortel"]
    if has("secondi"):
        return _CATEGORY_COLORS["secondi"]
    if has("uova"):
        return _CATEGORY_COLORS["uova"]
    if has("toast"):
        return _CATEGORY_COLORS["toast"]
    if has("fritti", "stuzzichini"):
        return _CATEGORY_COLORS["fritti"]
    return _CATEGORY_COLORS["panini"]


def restaurant_for_guest_request(request) -> Restaurant:
    match = getattr(request, "resolver_match", None)
    slug = match.kwargs.get("restaurant_slug") if match else None
    slug = slug or "sissy-bar"
    restaurant = get_object_or_404(Restaurant, slug=slug, is_active=True)
    request.restaurant = restaurant
    return restaurant


def _venue_for_request(request) -> VenueSettings:
    """The venue settings to render, honoring ?preview=<token> — a staff
    editor's draft stored in the cache by /api/staff/venue/preview/. The draft
    is applied to an in-memory copy only; the saved settings never change."""
    venue = VenueSettings.get_solo(restaurant_for_guest_request(request).slug)
    token = request.GET.get("preview", "")
    if token:
        draft = cache.get(preview_cache_key(token))
        if isinstance(draft, dict) and draft:
            venue = copy.copy(venue)  # never mutate the cached instance
            for field, value in draft.items():
                setattr(venue, field, value)
    return venue


def menu_page(request, table_id=None, table_number=None, restaurant_slug=None):
    """Guest QR page: storefront, menu, cart checkout and service signals."""
    restaurant = restaurant_for_guest_request(request)
    menu_items = MenuItem.objects.filter(restaurant=restaurant).select_related("category").order_by(
        "category__sort_order", "category__name", "-is_available", "name"
    )
    # Two ways to address a table:
    #   /menu/t/<pk>/     — legacy, internal DB id (kept for old links);
    #   /menu/n/<number>/ — the printed table number. QR codes should use this
    #     one: it survives reseeding/recreating the DB, a pk does not.
    if table_number is not None:
        table = get_object_or_404(
            Table, restaurant=restaurant, number=table_number
        )
    else:
        table = (
            get_object_or_404(Table, restaurant=restaurant, pk=table_id)
            if table_id is not None
            else None
        )

    # Prefer the explicit printed/client menu. If a dirty DB has no client tags
    # at all, fall back to all available non-archived items instead of rendering
    # an empty guest page.
    menu_items = guest_visible_menu_items(menu_items)
    # menu_items is ordered by (category, name), so grouping is a single pass.
    sections = []
    sections_by_name = {}
    menu_payload = []
    visible_items = []
    for item in menu_items:
        # Printed-menu price style: comma decimal, always two digits («4,50»).
        item.price_str = f"{item.price:.2f}".replace(".", ",")
        raw_category = item.category.name
        display_category = raw_category
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
                    "color": item.category.color or _category_color(display_category),
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
    sections.sort(key=lambda s: (_guest_category_rank(s["name"]), s["name_it"]))
    # Featured rail: owner-promoted items first (is_promoted — the GUEST
    # popularity flag, deliberately separate from the staff 'popular' tag so
    # the owner can push a product to guests without touching the waiter
    # shelf), then the curated name list, then anything to reach 4+.
    featured_items = [
        item for item in visible_items if item.is_available and item.is_promoted
    ]
    seen = {item.pk for item in featured_items}
    for name in POPULAR_ITEM_NAMES:
        match = next(
            (
                item
                for item in visible_items
                if item.is_available and item.name == name and item.pk not in seen
            ),
            None,
        )
        if match is not None:
            featured_items.append(match)
            seen.add(match.pk)
    if len(featured_items) < 4:
        featured_items.extend(
            item
            for item in visible_items
            if item.is_available and item.pk not in seen
        )
    featured_items = featured_items[:6]

    venue = _venue_for_request(request)
    blocks = venue.blocks()
    block_visible = {block["key"]: block["visible"] for block in blocks}
    # The profile screen renders in two zones: sub-blocks inside the head card
    # (facts / badges / cta) and full-width sections after it (popular /
    # about). Each zone follows the configured order; hidden blocks drop out.
    head_blocks = [b["key"] for b in blocks if b["key"] in ("facts", "badges", "cta") and b["visible"]]
    body_blocks = [b["key"] for b in blocks if b["key"] in ("popular", "about") and b["visible"]]

    return render(
        request,
        "guest_web/menu.html",
        {
            "featured_items": featured_items,
            "menu_sections": sections,
            "menu_items": visible_items,
            "menu_payload": menu_payload,
            "table": table,
            "venue": venue,
            "guest_base": f"/r/{restaurant.slug}/",
            "venue_blocks": block_visible,
            "head_blocks": head_blocks,
            "body_blocks": body_blocks,
        },
    )


def prototype_page(request, restaurant_slug=None):
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
def create_guest_order(request, restaurant_slug=None):
    restaurant = restaurant_for_guest_request(request)
    table_id = request.POST.get("table")
    is_fetch = request.headers.get("X-Requested-With") == "fetch"
    # Only numeric ids can match rows; anything else in pk__in raises a 500.
    selected_ids = [s for s in request.POST.getlist("items") if s.isdigit()]

    if not table_id or not selected_ids:
        if is_fetch:
            return JsonResponse({"ok": False, "error": "empty"}, status=400)
        messages.error(request, "Choose a table and at least one item.")
        return _redirect_menu(request, table_id)

    with transaction.atomic():
        # table_id and quantities come straight from the guest's browser: a
        # non-numeric id or quantity must produce a friendly error, not a 500.
        try:
            table = Table.objects.select_for_update().get(
                restaurant=restaurant, pk=table_id
            )
        except (Table.DoesNotExist, ValueError):
            if is_fetch:
                return JsonResponse({"ok": False, "error": "table"}, status=404)
            messages.error(request, "Table not found. Please scan the QR code again.")
            return _redirect_menu(request, None)

        has_client_menu = menu_has_client_items(
            MenuItem.objects.filter(restaurant=restaurant).only("tags", "is_available")
        )
        menu_items = [
            item
            for item in MenuItem.objects.filter(
                restaurant=restaurant, pk__in=selected_ids
            ).select_related("category")
            if menu_item_guest_visible(item, has_client_menu=has_client_menu)
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
            return _redirect_menu(request, table_id)

        # Guest-web orders wait for a waiter to approve them before the
        # kitchen/bar ever see them (source stays guest_web via the model
        # default). A waiter confirms via POST /api/orders/<id>/confirm/.
        order = Order.objects.create(
            restaurant=restaurant,
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
    return _redirect_menu(request, table_id)


@require_GET
def guest_order_status(request, order_id, restaurant_slug=None):
    restaurant = restaurant_for_guest_request(request)
    if order_id not in request.session.get("guest_orders", []):
        raise Http404("Order is not available in this session.")
    order = get_object_or_404(
        Order.objects.select_related("table").prefetch_related("items", "items__menu_item"),
        restaurant=restaurant,
        pk=order_id,
    )
    return JsonResponse({"ok": True, "order": _guest_order_payload(order)})


@require_POST
def create_attention_signal(request, restaurant_slug=None):
    """Guest pressed "Call waiter" (or another signal button).

    Sets the table into the WAITING status, notifies every staff device over
    the realtime feed and answers JSON when called via fetch() so the guest
    page can show an inline confirmation without a full reload.
    """
    restaurant = restaurant_for_guest_request(request)
    table_id = request.POST.get("table")
    table = get_object_or_404(Table, restaurant=restaurant, pk=table_id)
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
        return _redirect_menu(request, table_id)
    if signal_type not in AttentionSignal.Type.values:
        if is_fetch:
            return JsonResponse({"ok": False, "error": "unknown signal"}, status=400)
        messages.error(request, "Unknown signal type.")
        return _redirect_menu(request, table_id)

    signal = AttentionSignal.objects.create(
        restaurant=restaurant,
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
    return _redirect_menu(request, table_id)


@require_POST
def cancel_attention_signal(request, restaurant_slug=None):
    """Guest pressed "Cancel call" on their own pending signal.

    Marks the signal acknowledged (nobody has to walk over anymore) and rolls
    the table badge back, broadcasting to staff devices — the same path a
    waiter's "Acknowledge" action takes, so the two can't diverge.
    """
    restaurant = restaurant_for_guest_request(request)
    signal_id = request.POST.get("signal")
    signal = get_object_or_404(
        AttentionSignal, restaurant=restaurant, pk=signal_id
    )
    is_fetch = request.headers.get("X-Requested-With") == "fetch"
    if not signal.ack:
        signal.acknowledge(None)
        table = acknowledge_signal_on_table(signal.table)
        broadcast_attention_event("acked", signal)
        broadcast_table_event(table)
    if is_fetch:
        return JsonResponse({"ok": True})
    return _redirect_menu(request, signal.table_id)


def _redirect_menu(request, table_id):
    """Redirect to the table-scoped page when we have a table_id, generic menu otherwise."""
    restaurant = restaurant_for_guest_request(request)
    try:
        return redirect(f"/r/{restaurant.slug}/t/{int(table_id)}/")
    except (TypeError, ValueError):
        return redirect(f"/r/{restaurant.slug}/")


def _menu_visual(category):
    return MENU_VISUALS.get((category or "").strip().lower(), ("default", "🍽"))


def _guest_category_rank(category):
    try:
        return GUEST_CATEGORY_ORDER.index(category)
    except ValueError:
        return len(GUEST_CATEGORY_ORDER)


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
        "note": order.notes,
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
