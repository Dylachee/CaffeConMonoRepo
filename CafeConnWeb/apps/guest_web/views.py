from django.conf import settings
from django.contrib import messages
from django.db import transaction
from django.http import FileResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from apps.api.events import broadcast_attention_event, broadcast_order_event
from apps.core.models import AttentionSignal, MenuItem, Order, OrderItem, Table


def menu_page(request):
    menu_items = MenuItem.objects.filter(is_available=True).order_by("category", "name")
    tables = Table.objects.exclude(status=Table.Status.CLOSED)
    categories = menu_items.values_list("category", flat=True).distinct()
    return render(
        request,
        "guest_web/menu.html",
        {
            "menu_items": menu_items,
            "tables": tables,
            "categories": categories,
        },
    )


def prototype_page(request):
    prototype_path = settings.BASE_DIR / "static" / "prototypes" / "guest.html"
    return FileResponse(open(prototype_path, "rb"), content_type="text/html; charset=utf-8")


@require_POST
def create_guest_order(request):
    table_id = request.POST.get("table")
    selected_ids = request.POST.getlist("items")

    if not table_id or not selected_ids:
        messages.error(request, "Выберите стол и хотя бы одно блюдо.")
        return redirect("guest_web:menu")

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
                )
            )
        OrderItem.objects.bulk_create(order_items)
        stations = {item.station for item in order_items}
        if len(stations) == 1:
            order.station_scope = stations.pop()
        elif len(stations) > 1:
            order.station_scope = Order.StationScope.MIXED
        order.save(update_fields=["station_scope", "updated_at"])

        table.status = Table.Status.NEW_ORDER
        table.guest_count = max(table.guest_count, 1)
        table.save(update_fields=["status", "guest_count", "updated_at"])

    broadcast_order_event("created", order)
    messages.success(request, f"Заказ #{order.pk} отправлен персоналу.")
    return redirect("guest_web:menu")


@require_POST
def create_attention_signal(request):
    table = get_object_or_404(Table, pk=request.POST.get("table"))
    signal_type = request.POST.get("signal_type")
    if signal_type not in AttentionSignal.Type.values:
        messages.error(request, "Неизвестный тип сигнала.")
        return redirect("guest_web:menu")

    signal = AttentionSignal.objects.create(
        table=table,
        signal_type=signal_type,
        reason=request.POST.get("reason", "").strip(),
    )
    table.attention = {
        AttentionSignal.Type.ARRIVED: Table.Attention.ARRIVED,
        AttentionSignal.Type.CALL_WAITER: Table.Attention.CALL,
        AttentionSignal.Type.BILL_REQUEST: Table.Attention.BILL,
    }[signal.signal_type]
    table.attention_reason = signal.reason
    table.attention_acknowledged = False
    if signal.signal_type == AttentionSignal.Type.ARRIVED and table.status == Table.Status.FREE:
        table.status = Table.Status.OCCUPIED
    table.save(update_fields=["attention", "attention_reason", "attention_acknowledged", "status", "updated_at"])
    broadcast_attention_event("created", signal)
    messages.success(request, "Сигнал отправлен персоналу.")
    return redirect("guest_web:menu")
