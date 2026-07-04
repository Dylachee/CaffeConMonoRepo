import mimetypes

from django.conf import settings
from django.contrib import messages
from django.db import transaction
from django.http import FileResponse, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.api.events import broadcast_attention_event, broadcast_order_event, broadcast_table_event
from apps.core.models import AttentionSignal, MenuItem, Order, OrderItem, Table
from apps.core.services import acknowledge_signal_on_table, apply_signal_to_table


# Venue "storefront" shown on the guest page. Static for now — when venues
# become configurable this moves to a model; keeping it in one place makes
# that swap a one-liner in menu_page.
VENUE = {
    "name": "Sissi Bistro Bar",
    "tagline": "Бистро и бар · европейская кухня · уютный зал",
    "about": (
        "Небольшое бистро в центре. Готовим из сезонных продуктов, "
        "варим спешелти-кофе и держим короткую, честную барную карту."
    ),
    "address": "ул. Киевская 77 · 1 этаж",
    "hours": "Ежедневно 10:00 – 23:00",
    "badges": ["Веган-опции", "Спешелти-кофе", "Завтраки весь день"],
}


def menu_page(request, table_id=None, table_number=None):
    """Guest page v3 «Меню и точка»: the menu itself, immediately.

    Owner's brief (2026-07-02): минимальный порог входа — between the QR scan
    and the first dish there must be nothing. No cover, no mood engine, no
    client-side dish payload; the template renders everything server-side and
    ships as a single self-contained document.

    Guests still see stop-listed dishes (greyed, at the end of their section) —
    the web menu must never look shorter than the printed one.
    """
    menu_items = MenuItem.objects.order_by("category", "name")
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
    for item in menu_items:
        # Printed-menu price style: comma decimal, always two digits («4,50»).
        item.price_str = f"{item.price:.2f}".replace(".", ",")
        if not sections or sections[-1]["name"] != item.category:
            sections.append({"name": item.category, "items": []})
        sections[-1]["items"].append(item)
    for section in sections:
        section["items"].sort(key=lambda i: not i.is_available)  # stable

    return render(
        request,
        "guest_web/menu.html",
        {"menu_sections": sections, "table": table, "venue": VENUE},
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
    target = _STAFF_BUILD / path if path else _STAFF_BUILD / "index.html"
    if not target.is_file():
        target = _STAFF_BUILD / "index.html"
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
    selected_ids = request.POST.getlist("items")

    if not table_id or not selected_ids:
        messages.error(request, "Выберите стол и хотя бы одно блюдо.")
        return _redirect_menu(table_id)

    with transaction.atomic():
        table = Table.objects.select_for_update().get(pk=table_id)
        order = Order.objects.create(
            table=table,
            guest_name=request.POST.get("guest_name", "").strip(),
            notes=request.POST.get("notes", "").strip(),
        )

        menu_items = MenuItem.objects.filter(pk__in=selected_ids, is_available=True)
        order_items = []
        for item in menu_items:
            quantity = int(request.POST.get(f"quantity_{item.pk}", "1") or 1)
            order_items.append(
                OrderItem(
                    order=order,
                    menu_item=item,
                    quantity=max(quantity, 1),
                    unit_price=item.price,
                    station=item.station,  # was missing — all items defaulted to KITCHEN
                )
            )
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
    messages.success(request, f"Заказ #{order.pk} отправлен персоналу.")
    return _redirect_menu(table_id)


@require_POST
def create_attention_signal(request):
    """Guest pressed "Позвать официанта" (or another signal button).

    Sets the table into the WAITING status, notifies every staff device over
    the realtime feed and answers JSON when called via fetch() so the guest
    page can show an inline confirmation without a full reload.
    """
    table_id = request.POST.get("table")
    table = get_object_or_404(Table, pk=table_id)
    signal_type = request.POST.get("signal_type")
    is_fetch = request.headers.get("X-Requested-With") == "fetch"
    if signal_type not in AttentionSignal.Type.values:
        if is_fetch:
            return JsonResponse({"ok": False, "error": "unknown signal"}, status=400)
        messages.error(request, "Неизвестный тип сигнала.")
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
    messages.success(request, "Официант уже идёт к вам.")
    return _redirect_menu(table_id)


@require_POST
def cancel_attention_signal(request):
    """Guest pressed «Отменить вызов» on their own pending signal.

    Marks the signal acknowledged (nobody has to walk over anymore) and rolls
    the table badge back, broadcasting to staff devices — the same path a
    waiter's «Принял» takes, so the two can't diverge.
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
