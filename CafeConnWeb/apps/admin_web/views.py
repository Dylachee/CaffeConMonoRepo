from django.conf import settings
from django.contrib.admin.views.decorators import staff_member_required
from django.contrib import messages
from django.db.models import Count, DecimalField, ExpressionWrapper, F, Sum
from django.http import FileResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from apps.api.events import broadcast_attention_event, broadcast_order_event
from apps.core.models import AttentionSignal, MenuItem, Order, Table


@staff_member_required(login_url="/system-admin/login/")
def dashboard(request):
    orders = Order.objects.select_related("table").prefetch_related("items", "items__menu_item")
    line_total = ExpressionWrapper(
        F("items__unit_price") * F("items__quantity"),
        output_field=DecimalField(max_digits=12, decimal_places=2),
    )
    context = {
        "orders_total": orders.count(),
        "orders_pending": orders.filter(status=Order.Status.PENDING).count(),
        "orders_ready": orders.filter(status=Order.Status.READY).count(),
        "active_tables": Table.objects.exclude(status=Table.Status.FREE).count(),
        "menu_items": MenuItem.objects.count(),
        "sales_total": orders.aggregate(total=Sum(line_total))["total"] or 0,
        "orders_by_status": orders.values("status").annotate(total=Count("id")).order_by("status"),
        "latest_orders": orders[:10],
        "active_signals": AttentionSignal.objects.select_related("table").filter(ack=False)[:8],
        "tables": Table.objects.select_related("waiter").all(),
        "menu_list": MenuItem.objects.all()[:80],
        "order_statuses": Order.Status.choices,
        "stations": MenuItem._meta.get_field("station").choices,
    }
    return render(request, "admin_web/dashboard.html", context)


@staff_member_required(login_url="/system-admin/login/")
def prototype_page(request):
    prototype_path = settings.BASE_DIR / "static" / "prototypes" / "accounting.html"
    return FileResponse(open(prototype_path, "rb"), content_type="text/html; charset=utf-8")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def update_order_status(request, order_id):
    order = get_object_or_404(Order, pk=order_id)
    next_status = request.POST.get("status")
    if next_status not in Order.Status.values:
        messages.error(request, "Неизвестный статус заказа.")
        return redirect("admin_web:dashboard")

    order.status = next_status
    order.save(update_fields=["status", "updated_at"])
    broadcast_order_event("updated", order)
    messages.success(request, f"Заказ #{order.id} обновлен.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def toggle_menu_item(request, item_id):
    item = get_object_or_404(MenuItem, pk=item_id)
    item.is_available = not item.is_available
    item.save(update_fields=["is_available", "updated_at"])
    messages.success(request, f"{item.name}: {'в наличии' if item.is_available else 'стоп-лист'}.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def create_menu_item(request):
    item = MenuItem.objects.create(
        name=request.POST.get("name", "").strip(),
        description=request.POST.get("description", "").strip(),
        composition=request.POST.get("composition", "").strip(),
        price=request.POST.get("price") or 0,
        category=request.POST.get("category", "Меню").strip() or "Меню",
        station=request.POST.get("station") or "kitchen",
        is_available=request.POST.get("is_available") == "on",
    )
    messages.success(request, f"Позиция {item.name} добавлена.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def ack_attention_signal(request, signal_id):
    signal = get_object_or_404(AttentionSignal.objects.select_related("table"), pk=signal_id)
    try:
        employee = request.user.employee_profile
    except Exception:
        employee = None
    signal.acknowledge(employee)
    signal.table.attention_acknowledged = True
    signal.table.save(update_fields=["attention_acknowledged", "updated_at"])
    broadcast_attention_event("acked", signal)
    messages.success(request, f"Сигнал по {signal.table} принят.")
    return redirect("admin_web:dashboard")
