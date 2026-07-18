import json
import os
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.core import push
from apps.core.models import AttentionSignal, Employee, Order, PushSubscription, Table

User = get_user_model()

FAKE_ENV = {
    "VAPID_PRIVATE_KEY": "fake-private-key",
    "VAPID_PUBLIC_KEY": "fake-public-key",
    "VAPID_ADMIN_EMAIL": "alerts@sissi.example",
}


def make_employee(username: str, *, on_shift: bool) -> Employee:
    user = User.objects.create_user(username=f"tstp-{username}", password="x-test-pass-1")
    return Employee.objects.create(
        user=user, name=username, role=Employee.Role.WAITER, is_on_shift=on_shift
    )


def make_subscription(employee: Employee, endpoint_suffix: str = "a") -> PushSubscription:
    return PushSubscription.objects.create(
        employee=employee,
        endpoint=f"https://push.example/send/{employee.pk}-{endpoint_suffix}",
        p256dh="p256dh-key",
        auth="auth-secret",
    )


class PushFeatureFlagTests(TestCase):
    def test_without_keys_everything_is_a_silent_noop(self):
        employee = make_employee("w1", on_shift=True)
        make_subscription(employee)
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("VAPID_PRIVATE_KEY", None)
            os.environ.pop("VAPID_PUBLIC_KEY", None)
            self.assertFalse(push.push_configured())
            with mock.patch("pywebpush.webpush") as webpush_mock:
                sent = push.push_to_on_shift({"kind": "attention"})
        self.assertEqual(sent, 0)
        webpush_mock.assert_not_called()


@mock.patch.dict(os.environ, FAKE_ENV)
class PushDeliveryTests(TestCase):
    def test_pushes_only_to_on_shift_with_correct_payload(self):
        on_shift = make_employee("on", on_shift=True)
        off_shift = make_employee("off", on_shift=False)
        active_sub = make_subscription(on_shift)
        make_subscription(off_shift, "b")

        payload = {"kind": "attention", "action": "created", "signalId": 7, "tag": "attention-7"}
        with mock.patch("pywebpush.webpush") as webpush_mock:
            sent = push.push_to_on_shift(payload)

        self.assertEqual(sent, 1)
        webpush_mock.assert_called_once()
        kwargs = webpush_mock.call_args.kwargs
        self.assertEqual(kwargs["subscription_info"]["endpoint"], active_sub.endpoint)
        self.assertEqual(
            kwargs["subscription_info"]["keys"],
            {"p256dh": "p256dh-key", "auth": "auth-secret"},
        )
        self.assertEqual(json.loads(kwargs["data"]), payload)
        self.assertEqual(kwargs["vapid_private_key"], "fake-private-key")
        self.assertEqual(kwargs["vapid_claims"]["sub"], "mailto:alerts@sissi.example")
        self.assertEqual(kwargs["ttl"], 120)

    def test_dead_subscription_is_garbage_collected(self):
        from pywebpush import WebPushException

        employee = make_employee("gc", on_shift=True)
        subscription = make_subscription(employee)
        gone = WebPushException("gone", response=mock.Mock(status_code=410))
        with mock.patch("pywebpush.webpush", side_effect=gone):
            sent = push.push_to_on_shift({"kind": "attention"})
        self.assertEqual(sent, 0)
        self.assertFalse(PushSubscription.objects.filter(pk=subscription.pk).exists())

    def test_transient_failure_keeps_the_subscription(self):
        from pywebpush import WebPushException

        employee = make_employee("keep", on_shift=True)
        subscription = make_subscription(employee)
        busy = WebPushException("busy", response=mock.Mock(status_code=503))
        with mock.patch("pywebpush.webpush", side_effect=busy):
            push.push_to_on_shift({"kind": "attention"})
        self.assertTrue(PushSubscription.objects.filter(pk=subscription.pk).exists())


@mock.patch.dict(os.environ, FAKE_ENV)
class AlertEventPushTests(TestCase):
    """The events.py choke points fan alerts out to background devices."""

    def setUp(self):
        self.table = Table.objects.get_or_create(number=970, defaults={"capacity": 2})[0]
        self.waiter = make_employee("evt", on_shift=True)
        make_subscription(self.waiter)

    def test_attention_created_and_acked_push_with_tag(self):
        from apps.api.events import broadcast_attention_event

        signal = AttentionSignal.objects.create(
            table=self.table, signal_type=AttentionSignal.Type.CALL_WAITER
        )
        with mock.patch("pywebpush.webpush") as webpush_mock:
            broadcast_attention_event("created", signal)
            signal.acknowledge(self.waiter)
            broadcast_attention_event("acked", signal)

        self.assertEqual(webpush_mock.call_count, 2)
        first = json.loads(webpush_mock.call_args_list[0].kwargs["data"])
        second = json.loads(webpush_mock.call_args_list[1].kwargs["data"])
        self.assertEqual(first["action"], "created")
        self.assertEqual(second["action"], "acked")
        # Same tag both times: the ack push replaces/closes the banner.
        self.assertEqual(first["tag"], second["tag"])
        self.assertEqual(first["table"], self.table.number)

    def test_awaiting_order_pushes_but_staff_order_does_not(self):
        from apps.api.events import broadcast_order_event

        awaiting = Order.objects.create(table=self.table, status=Order.Status.AWAITING)
        staff_order = Order.objects.create(table=self.table, status=Order.Status.NEW)
        with mock.patch("pywebpush.webpush") as webpush_mock:
            broadcast_order_event("created", awaiting)
            broadcast_order_event("created", staff_order)
        self.assertEqual(webpush_mock.call_count, 1)
        payload = json.loads(webpush_mock.call_args.kwargs["data"])
        self.assertEqual(payload["kind"], "order")
        self.assertEqual(payload["orderId"], awaiting.pk)
