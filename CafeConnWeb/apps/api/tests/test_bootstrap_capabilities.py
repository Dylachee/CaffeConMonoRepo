from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core.models import (
    Employee,
    MenuCategory,
    MenuItem,
    Order,
    OrderItem,
    Restaurant,
    Table,
)


User = get_user_model()


def client_for(username, restaurant, role):
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    Employee.objects.create(
        user=user, restaurant=restaurant, name=username, role=role
    )
    token = Token.objects.create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client


class BootstrapCapabilityContractTests(TestCase):
    def setUp(self):
        self.restaurant = Restaurant.objects.create(name="Contract", slug="contract")
        self.table = Table.objects.create(restaurant=self.restaurant, number=1)
        category = MenuCategory.objects.create(
            restaurant=self.restaurant, key="food", name="Food"
        )
        kitchen = MenuItem.objects.create(
            restaurant=self.restaurant, category=category, name="Soup", price=8,
            station="kitchen",
        )
        bar = MenuItem.objects.create(
            restaurant=self.restaurant, category=category, name="Tea", price=3,
            station="bar",
        )
        order = Order.objects.create(restaurant=self.restaurant, table=self.table)
        OrderItem.objects.create(order=order, menu_item=kitchen, unit_price=8, station="kitchen")
        OrderItem.objects.create(order=order, menu_item=bar, unit_price=3, station="bar")
        self.url = "/api/restaurants/contract/staff/bootstrap/"

    def test_content_account_receives_no_operational_datasets(self):
        body = client_for("contract-smm", self.restaurant, Employee.Role.SMM).get(self.url).json()
        self.assertEqual(body["tables"], [])
        self.assertEqual(body["menu"], [])
        self.assertEqual(body["orders"], [])
        self.assertEqual(body["history"], [])

    def test_kitchen_receives_only_kitchen_order_lines(self):
        body = client_for("contract-kitchen", self.restaurant, Employee.Role.KITCHEN).get(self.url).json()
        self.assertEqual(body["tables"], [])
        self.assertEqual(body["menu"], [])
        self.assertEqual(
            {item["station"] for order in body["orders"] for item in order["items"]},
            {"kitchen"},
        )

    def test_waiter_receives_floor_and_catalog_datasets(self):
        body = client_for("contract-waiter", self.restaurant, Employee.Role.WAITER).get(self.url).json()
        self.assertEqual(len(body["tables"]), 1)
        self.assertEqual(len(body["menu"]), 2)
        self.assertEqual(len(body["orders"]), 1)
        self.assertEqual(body["history"], [])

    def test_station_worker_cannot_delete_a_billable_order_item(self):
        item = OrderItem.objects.filter(order__restaurant=self.restaurant).first()
        client = client_for("contract-kitchen-delete", self.restaurant, Employee.Role.KITCHEN)

        response = client.delete(f"/api/order-items/{item.pk}/")

        self.assertEqual(response.status_code, 403)
        self.assertTrue(OrderItem.objects.filter(pk=item.pk).exists())
