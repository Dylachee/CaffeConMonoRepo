import json

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from rest_framework.renderers import JSONRenderer

from apps.core import push
from apps.core.models import Order
from apps.api.serializers import (
    AttentionSignalSerializer,
    ChatMessageSerializer,
    OrderSerializer,
    StaffTaskSerializer,
    TableSerializer,
)


def broadcast_chat_event(action: str, message) -> None:
    """chat.message / chat.updated — new bubbles and re-rendered task bubbles."""
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    payload = {
        "event": f"chat.{action}",
        "message": json.loads(JSONRenderer().render(ChatMessageSerializer(message).data)),
    }
    async_to_sync(channel_layer.group_send)(
        "staff",
        {"type": "chat.event", "payload": payload},
    )


def broadcast_task_event(action: str, task) -> None:
    """task.updated — planner rows and task bubbles stay live everywhere."""
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    payload = {
        "event": f"task.{action}",
        "task": json.loads(JSONRenderer().render(StaffTaskSerializer(task).data)),
    }
    async_to_sync(channel_layer.group_send)(
        "staff",
        {"type": "chat.event", "payload": payload},
    )


def broadcast_order_event(action: str, order) -> None:
    channel_layer = get_channel_layer()
    if channel_layer is not None:
        payload = {
            "event": f"order.{action}",
            "order": json.loads(JSONRenderer().render(OrderSerializer(order).data)),
        }
        async_to_sync(channel_layer.group_send)(
            "staff",
            {
                "type": "order.event",
                "payload": payload,
            },
        )

    # TRUE background delivery for the guest-order alert lifecycle only:
    # a new AWAITING order wakes locked on-shift phones; escalation re-alerts.
    # (No-op with no VAPID keys in env — see apps.core.push.)
    if action == "created" and order.status == Order.Status.AWAITING:
        push.push_to_on_shift(push.awaiting_order_payload("created", order))
    elif action == "escalated":
        push.push_to_on_shift(push.awaiting_order_payload("escalated", order))


def notify_order_alert_handled(order) -> None:
    """A guest order left AWAITING (confirmed/rejected): tell background
    devices so their OS banners close. Live tabs learn via the normal
    order.updated WS event."""
    push.push_to_on_shift(push.awaiting_order_payload("handled", order))


def broadcast_table_event(table) -> None:
    """Push the table's current state to every staff device.

    This is the missing half of realtime sync: order/attention events already
    flowed, but a plain status change (waiter frees a table, guest calls a
    waiter) never reached other devices until they re-logged-in.
    """
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

    payload = {
        "event": "table.updated",
        "table": json.loads(JSONRenderer().render(TableSerializer(table).data)),
    }
    async_to_sync(channel_layer.group_send)(
        "staff",
        {
            "type": "table.event",
            "payload": payload,
        },
    )


def broadcast_attention_event(action: str, signal) -> None:
    channel_layer = get_channel_layer()
    if channel_layer is not None:
        payload = {
            "event": f"attention.{action}",
            "signal": json.loads(JSONRenderer().render(AttentionSignalSerializer(signal).data)),
        }
        async_to_sync(channel_layer.group_send)(
            "staff",
            {
                "type": "attention.event",
                "payload": payload,
            },
        )

    # Background push mirrors the alert lifecycle: created wakes phones,
    # acked closes their OS banners (same tag), escalated re-alerts.
    if action in ("created", "acked", "escalated"):
        push.push_to_on_shift(push.attention_payload(action, signal))
