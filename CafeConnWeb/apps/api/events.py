import json

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from rest_framework.renderers import JSONRenderer

from apps.api.serializers import AttentionSignalSerializer, OrderSerializer


def broadcast_order_event(action: str, order) -> None:
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

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


def broadcast_attention_event(action: str, signal) -> None:
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return

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
