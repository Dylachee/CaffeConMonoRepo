"""Single place for table-state transitions.

The 3-status model (free / occupied / waiting) is enforced here so the API,
the guest web forms and the admin dashboard cannot drift apart. Every caller
that changes a table MUST also broadcast a table event (apps.api.events) so
all staff devices stay in sync — the helpers return the saved table to make
that convenient.
"""

from django.utils import timezone

from apps.core.models import AttentionSignal, Order, Table

ATTENTION_BY_SIGNAL = {
    AttentionSignal.Type.ARRIVED: Table.Attention.ARRIVED,
    AttentionSignal.Type.CALL_WAITER: Table.Attention.CALL,
    AttentionSignal.Type.BILL_REQUEST: Table.Attention.BILL,
}


def apply_signal_to_table(signal: AttentionSignal, table: Table) -> Table:
    """Reflect a guest signal on the table: badge + 3-state status.

    call_waiter / bill_request -> WAITING (guests want a waiter now);
    arrived -> OCCUPIED when the table was free.
    """
    table.attention = ATTENTION_BY_SIGNAL.get(signal.signal_type, Table.Attention.NONE)
    table.attention_reason = signal.reason
    table.attention_acknowledged = False
    if signal.signal_type == AttentionSignal.Type.ARRIVED:
        if table.status == Table.Status.FREE:
            table.status = Table.Status.OCCUPIED
    else:
        table.status = Table.Status.WAITING
    if table.opened_at is None and table.status != Table.Status.FREE:
        table.opened_at = timezone.now()
    table.save(
        update_fields=[
            "attention",
            "attention_reason",
            "attention_acknowledged",
            "status",
            "opened_at",
            "updated_at",
        ]
    )
    return table


def acknowledge_signal_on_table(table: Table) -> Table:
    """Waiter pressed "Acknowledge": clear the badge; WAITING becomes OCCUPIED."""
    table.attention = Table.Attention.NONE
    table.attention_reason = ""
    table.attention_acknowledged = True
    if table.status == Table.Status.WAITING:
        table.status = Table.Status.OCCUPIED
    table.save(
        update_fields=[
            "attention",
            "attention_reason",
            "attention_acknowledged",
            "status",
            "updated_at",
        ]
    )
    return table


def reset_free_table(table: Table) -> Table:
    """A table set back to FREE drops all per-visit state.

    The visit's orders are archived to PAID here: bootstrap and the station
    feeds exclude PAID/CANCELLED, so "clear table" is the single moment an
    order history leaves the staff screens. Until then delivered (COMPLETED)
    orders stay visible in the table's history.
    """
    table.orders.exclude(
        status__in=[Order.Status.PAID, Order.Status.CANCELLED]
    ).update(status=Order.Status.PAID, updated_at=timezone.now())
    table.guest_count = 0
    table.attention = Table.Attention.NONE
    table.attention_reason = ""
    table.attention_acknowledged = False
    table.opened_at = None
    table.save(
        update_fields=[
            "guest_count",
            "attention",
            "attention_reason",
            "attention_acknowledged",
            "opened_at",
            "updated_at",
        ]
    )
    return table


def sync_order_status_from_items(order: Order) -> Order:
    """Derive the order lifecycle from item-level station/delivery flags."""
    if hasattr(order, "_prefetched_objects_cache"):
        order._prefetched_objects_cache.pop("items", None)
    items = list(order.items.all())
    if not items or order.status in [Order.Status.PAID, Order.Status.CANCELLED]:
        return order

    if all(item.done for item in items):
        next_status = Order.Status.COMPLETED
    elif all(item.ready for item in items):
        next_status = Order.Status.READY
    elif any(item.ready for item in items):
        next_status = Order.Status.COOKING
    else:
        next_status = order.status if order.status == Order.Status.COOKING else Order.Status.NEW

    if order.status != next_status:
        order.status = next_status
        order.save(update_fields=["status", "updated_at"])
    return order
