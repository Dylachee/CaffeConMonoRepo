from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core.models import Employee, Order, Restaurant, Table, TableWaiterEvent


User = get_user_model()


def staff_client(username, restaurant):
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    employee = Employee.objects.create(
        user=user, restaurant=restaurant, name=username, role=Employee.Role.WAITER
    )
    token = Token.objects.create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client, employee


class TableOwnershipTests(TestCase):
    def setUp(self):
        self.restaurant = Restaurant.objects.create(name="Ownership", slug="ownership")
        self.table = Table.objects.create(restaurant=self.restaurant, number=1)
        self.first_client, self.first = staff_client("first-waiter", self.restaurant)
        self.second_client, self.second = staff_client("second-waiter", self.restaurant)
        self.root = "/api/restaurants/ownership"

    def test_acknowledging_call_does_not_claim_table(self):
        response = self.first_client.post(
            f"{self.root}/attention-signals/",
            {"table_id": self.table.pk, "signal_type": "call_waiter"},
            format="json",
        )
        signal_id = response.json()["id"]
        self.first_client.post(f"{self.root}/attention-signals/{signal_id}/ack/")
        self.table.refresh_from_db()
        self.assertIsNone(self.table.waiter_id)

    def test_approving_first_order_claims_table(self):
        order = Order.objects.create(
            restaurant=self.restaurant,
            table=self.table,
            status=Order.Status.AWAITING,
            source=Order.Source.GUEST_WEB,
        )
        response = self.first_client.post(f"{self.root}/orders/{order.pk}/confirm/")
        self.assertEqual(response.status_code, 200)
        self.table.refresh_from_db()
        self.assertEqual(self.table.waiter, self.first)
        event = TableWaiterEvent.objects.get(table=self.table)
        self.assertEqual(event.action, TableWaiterEvent.Action.FIRST_ORDER)

    def test_takeover_requires_confirmation_and_audits_both_waiters(self):
        self.table.waiter = self.first
        self.table.save(update_fields=["waiter"])
        url = f"{self.root}/tables/{self.table.pk}/takeover/"
        self.assertEqual(self.second_client.post(url, {}, format="json").status_code, 400)
        response = self.second_client.post(url, {"confirmed": True}, format="json")
        self.assertEqual(response.status_code, 200)
        self.table.refresh_from_db()
        self.assertEqual(self.table.waiter, self.second)
        event = TableWaiterEvent.objects.get(table=self.table)
        self.assertEqual(event.previous_waiter, self.first)
        self.assertEqual(event.waiter, self.second)
        self.assertEqual(event.actor, self.second)

    def test_manual_claim_is_not_allowed(self):
        response = self.first_client.post(f"{self.root}/tables/{self.table.pk}/claim/")
        self.assertEqual(response.status_code, 409)
        self.table.refresh_from_db()
        self.assertIsNone(self.table.waiter_id)
