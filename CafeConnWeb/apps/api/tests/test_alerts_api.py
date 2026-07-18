from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core.models import AttentionSignal, Employee, Order, PushSubscription, Table

User = get_user_model()


def make_client(username: str, role: str = Employee.Role.WAITER, **flags):
    username = f"tstal-{username}"
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    employee = Employee.objects.create(user=user, name=username, role=role, **flags)
    token, _ = Token.objects.get_or_create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client, employee


def make_table(number=971) -> Table:
    return Table.objects.get_or_create(number=number, defaults={"capacity": 2})[0]


class ShiftToggleTests(TestCase):
    def test_shift_toggle_roundtrip(self):
        client, employee = make_client("shift")
        self.assertFalse(employee.is_on_shift)

    def test_shift_ignores_legacy_area_picker_payload(self):
        client, employee = make_client("simple-shift", role=Employee.Role.MANAGER)
        response = client.post(
            "/api/staff/shift/", {"on": True, "areas": ["bar"]}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["areas"], [])
        employee.refresh_from_db()
        self.assertEqual(employee.shift_areas, [])
        on = client.post("/api/staff/shift/", {"on": True}, format="json")
        self.assertEqual(on.status_code, 200)
        self.assertTrue(on.json()["on"])
        employee.refresh_from_db()
        self.assertTrue(employee.is_on_shift)

        off = client.post("/api/staff/shift/", {"on": False}, format="json")
        self.assertFalse(off.json()["on"])
        employee.refresh_from_db()
        self.assertFalse(employee.is_on_shift)

    def test_bootstrap_reports_shift_and_push_config(self):
        client, employee = make_client("boot")
        employee.is_on_shift = True
        employee.save(update_fields=["is_on_shift"])
        body = client.get("/api/staff/bootstrap/").json()
        self.assertTrue(body["currentUser"]["isOnShift"])
        self.assertIn("push", body)
        self.assertIn("enabled", body["push"])
        self.assertIn("publicKey", body["push"])


class PushSubscriptionApiTests(TestCase):
    def setUp(self):
        self.client_w, self.employee = make_client("subs")
        self.payload = {
            "endpoint": "https://push.example/send/abc123",
            "keys": {"p256dh": "pk", "auth": "au"},
        }

    def test_subscribe_upserts_by_endpoint(self):
        first = self.client_w.post(
            "/api/staff/push-subscriptions/", self.payload, format="json"
        )
        self.assertEqual(first.status_code, 201)
        again = self.client_w.post(
            "/api/staff/push-subscriptions/", self.payload, format="json"
        )
        self.assertEqual(again.status_code, 200)
        self.assertEqual(PushSubscription.objects.count(), 1)
        subscription = PushSubscription.objects.get()
        self.assertEqual(subscription.employee, self.employee)
        self.assertEqual(subscription.p256dh, "pk")

    def test_missing_fields_are_400(self):
        response = self.client_w.post(
            "/api/staff/push-subscriptions/", {"endpoint": "https://x"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(response.json()["detail"])

    def test_unsubscribe_deletes_own_subscription(self):
        self.client_w.post("/api/staff/push-subscriptions/", self.payload, format="json")
        response = self.client_w.delete(
            "/api/staff/push-subscriptions/",
            {"endpoint": self.payload["endpoint"]},
            format="json",
        )
        self.assertEqual(response.status_code, 204)
        self.assertEqual(PushSubscription.objects.count(), 0)

    def test_cannot_delete_another_employees_subscription(self):
        self.client_w.post("/api/staff/push-subscriptions/", self.payload, format="json")
        other, _ = make_client("other")
        other.delete(
            "/api/staff/push-subscriptions/",
            {"endpoint": self.payload["endpoint"]},
            format="json",
        )
        # Still there: a non-manager can only remove their own device.
        self.assertEqual(PushSubscription.objects.count(), 1)


class EscalateEndpointTests(TestCase):
    def setUp(self):
        self.client_w, self.employee = make_client("esc")
        self.table = make_table()

    def test_signal_escalate_is_idempotent_and_blocked_after_ack(self):
        signal = AttentionSignal.objects.create(
            table=self.table, signal_type=AttentionSignal.Type.CALL_WAITER
        )
        first = self.client_w.post(f"/api/attention-signals/{signal.pk}/escalate/")
        self.assertEqual(first.status_code, 200)
        self.assertTrue(first.json()["alert_escalated"])
        again = self.client_w.post(f"/api/attention-signals/{signal.pk}/escalate/")
        self.assertEqual(again.status_code, 200)

        signal.acknowledge(self.employee)
        blocked = self.client_w.post(f"/api/attention-signals/{signal.pk}/escalate/")
        self.assertEqual(blocked.status_code, 409)
        self.assertIn("already", blocked.json()["detail"])

    def test_order_escalate_only_while_awaiting(self):
        awaiting = Order.objects.create(table=self.table, status=Order.Status.AWAITING)
        response = self.client_w.post(f"/api/orders/{awaiting.pk}/escalate/")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["alert_escalated"])

        handled = Order.objects.create(table=self.table, status=Order.Status.NEW)
        blocked = self.client_w.post(f"/api/orders/{handled.pk}/escalate/")
        self.assertEqual(blocked.status_code, 409)

    def test_bootstrap_carries_escalation_on_unacked_signal(self):
        signal = AttentionSignal.objects.create(
            table=self.table, signal_type=AttentionSignal.Type.CALL_WAITER, alert_escalated=True
        )
        self.table.attention = Table.Attention.CALL
        self.table.save(update_fields=["attention"])
        body = self.client_w.get("/api/staff/bootstrap/").json()
        row = next(t for t in body["tables"] if t["number"] == self.table.number)
        self.assertTrue(row["attentionEscalated"])
        self.assertEqual(row["attentionSignalId"], str(signal.pk))
