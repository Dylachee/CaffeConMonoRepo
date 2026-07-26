from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core.menu_catalog import CLIENT_MENU_TAG
from apps.core.models import Employee, MenuCategory, MenuItem, Order, OrderItem, Restaurant, Table


User = get_user_model()


class OrderConsistencyTests(TestCase):
    def setUp(self):
        self.restaurant = Restaurant.objects.create(name="Test Cafe", slug="test-cafe")
        self.table = Table.objects.create(
            restaurant=self.restaurant,
            number=3,
            status=Table.Status.OCCUPIED,
            opened_at=timezone.now(),
        )
        category = MenuCategory.objects.create(
            restaurant=self.restaurant, key="food", name="Food"
        )
        self.kitchen_item = MenuItem.objects.create(
            restaurant=self.restaurant,
            category=category,
            name="Toast",
            price=Decimal("5.00"),
            station="kitchen",
            tags=[CLIENT_MENU_TAG],
        )
        self.bar_item = MenuItem.objects.create(
            restaurant=self.restaurant,
            category=category,
            name="Water",
            price=Decimal("2.50"),
            station="bar",
            tags=[CLIENT_MENU_TAG],
        )
        user = User.objects.create_user(username="order-waiter", password="x")
        self.employee = Employee.objects.create(
            user=user,
            restaurant=self.restaurant,
            name="Waiter",
            role=Employee.Role.WAITER,
        )
        token = Token.objects.create(user=user)
        self.staff = APIClient()
        self.staff.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        self.api_root = "/api/restaurants/test-cafe"

    def test_same_request_key_creates_one_mixed_station_order(self):
        payload = {
            "table_id": self.table.pk,
            "client_request_id": "table-3-send-1",
            "items": [
                {"menu_item_id": self.kitchen_item.pk, "quantity": 1},
                {"menu_item_id": self.bar_item.pk, "quantity": 2},
            ],
        }
        first = self.staff.post(f"{self.api_root}/orders/", payload, format="json")
        second = self.staff.post(f"{self.api_root}/orders/", payload, format="json")

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["id"], second.json()["id"])
        order = Order.objects.get()
        self.assertEqual(order.station_scope, Order.StationScope.MIXED)
        self.assertEqual(order.items.count(), 2)

    def test_kitchen_can_read_today_history_without_financial_data(self):
        kitchen_user = User.objects.create_user(username="cook-history", password="x")
        Employee.objects.create(
            user=kitchen_user,
            restaurant=self.restaurant,
            name="Cook",
            role=Employee.Role.KITCHEN,
        )
        token = Token.objects.create(user=kitchen_user)
        kitchen = APIClient()
        kitchen.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        order = Order.objects.create(
            restaurant=self.restaurant,
            table=self.table,
            status=Order.Status.COMPLETED,
        )
        OrderItem.objects.create(
            order=order,
            menu_item=self.kitchen_item,
            quantity=1,
            unit_price=self.kitchen_item.price,
            station="kitchen",
            ready=True,
            done=True,
        )
        OrderItem.objects.create(
            order=order,
            menu_item=self.bar_item,
            quantity=1,
            unit_price=self.bar_item.price,
            station="bar",
        )

        response = kitchen.get(f"{self.api_root}/staff/station-history/?station=kitchen")

        self.assertEqual(response.status_code, 200)
        ticket = response.json()["orders"][0]
        self.assertEqual(ticket["tableNumber"], 3)
        self.assertEqual([item["name"] for item in ticket["items"]], ["Toast"])
        self.assertNotIn("total", ticket)
        self.assertNotIn("price", ticket["items"][0])
