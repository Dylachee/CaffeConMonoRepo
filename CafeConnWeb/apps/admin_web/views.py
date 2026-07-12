from django.conf import settings
from django.contrib.admin.views.decorators import staff_member_required
from django.contrib import messages
from django.db.models import Count, DecimalField, ExpressionWrapper, F, Max, Sum
from django.http import FileResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils.text import slugify
from django.views.decorators.http import require_POST

from apps.api.events import broadcast_attention_event, broadcast_order_event, broadcast_table_event
from apps.core.menu_catalog import CLIENT_MENU_TAG
from apps.core.models import AttentionSignal, MenuCategory, MenuItem, Order, Table
from apps.core.services import acknowledge_signal_on_table


@staff_member_required(login_url="/system-admin/login/")
def dashboard(request):
    orders = Order.objects.select_related("table").prefetch_related("items", "items__menu_item")
    menu_list = [item for item in MenuItem.objects.all() if "archived" not in (item.tags or [])]
    line_total = ExpressionWrapper(
        F("items__unit_price") * F("items__quantity"),
        output_field=DecimalField(max_digits=12, decimal_places=2),
    )
    context = {
        "orders_total": orders.count(),
        "orders_pending": orders.filter(status=Order.Status.NEW).count(),
        "orders_ready": orders.filter(status=Order.Status.READY).count(),
        "active_tables": Table.objects.exclude(status=Table.Status.FREE).count(),
        "menu_items": len(menu_list),
        "sales_total": orders.aggregate(total=Sum(line_total))["total"] or 0,
        "orders_by_status": orders.values("status").annotate(total=Count("id")).order_by("status"),
        "latest_orders": orders[:10],
        "active_signals": AttentionSignal.objects.select_related("table").filter(ack=False)[:8],
        "tables": Table.objects.select_related("waiter").all(),
        "menu_list": menu_list[:80],
        "menu_categories": MenuCategory.objects.annotate(
            item_count=Count("items")
        ).order_by("sort_order", "name"),
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
        messages.error(request, "Unknown order status.")
        return redirect("admin_web:dashboard")

    order.status = next_status
    order.save(update_fields=["status", "updated_at"])
    broadcast_order_event("updated", order)
    messages.success(request, f"Order #{order.id} updated.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def toggle_menu_item(request, item_id):
    item = get_object_or_404(MenuItem, pk=item_id)
    item.is_available = not item.is_available
    item.save(update_fields=["is_available", "updated_at"])
    messages.success(request, f"{item.name}: {'available' if item.is_available else 'stop-listed'}.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def create_menu_item(request):
    tags = [CLIENT_MENU_TAG] if request.POST.get("is_client_visible") == "on" else []
    category_id = request.POST.get("category")
    if not category_id:
        messages.error(request, "Create a category before adding menu items.")
        return redirect("admin_web:dashboard")
    category = get_object_or_404(MenuCategory, pk=category_id)
    item = MenuItem.objects.create(
        name=request.POST.get("name", "").strip(),
        description=request.POST.get("description", "").strip(),
        composition=request.POST.get("composition", "").strip(),
        price=request.POST.get("price") or 0,
        category=category,
        station=request.POST.get("station") or "kitchen",
        tags=tags,
        is_available=request.POST.get("is_available") == "on",
    )
    messages.success(request, f"Item {item.name} added.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def create_menu_category(request):
    name = request.POST.get("name", "").strip()
    if not name:
        messages.error(request, "Category name is required.")
        return redirect("admin_web:dashboard")
    color = request.POST.get("color", "#DFAF2B").strip() or "#DFAF2B"
    base = slugify(name)[:40] or "category"
    key = base
    suffix = 2
    while MenuCategory.objects.filter(key=key).exists():
        tail = f"-{suffix}"
        key = f"{base[:40 - len(tail)]}{tail}"
        suffix += 1
    sort_order = (
        MenuCategory.objects.aggregate(max_order=Max("sort_order"))["max_order"] or 0
    ) + 1
    MenuCategory.objects.create(key=key, name=name, color=color, sort_order=sort_order)
    messages.success(request, f"Category {name} added.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def update_menu_category(request, category_id):
    category = get_object_or_404(MenuCategory, pk=category_id)
    name = request.POST.get("name", "").strip()
    if not name:
        messages.error(request, "Category name is required.")
        return redirect("admin_web:dashboard")
    category.name = name
    category.color = request.POST.get("color", category.color).strip() or category.color
    category.save(update_fields=["name", "color", "updated_at"])
    messages.success(request, f"Category {category.name} updated.")
    return redirect("admin_web:dashboard")


@staff_member_required(login_url="/system-admin/login/")
@require_POST
def delete_menu_category(request, category_id):
    category = get_object_or_404(MenuCategory, pk=category_id)
    if category.items.exists():
        messages.error(request, "Move items out of this category before deleting it.")
        return redirect("admin_web:dashboard")
    name = category.name
    category.delete()
    messages.success(request, f"Category {name} deleted.")
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
    table = acknowledge_signal_on_table(signal.table)
    broadcast_attention_event("acked", signal)
    broadcast_table_event(table)
    messages.success(request, f"Signal for {signal.table} acknowledged.")
    return redirect("admin_web:dashboard")
