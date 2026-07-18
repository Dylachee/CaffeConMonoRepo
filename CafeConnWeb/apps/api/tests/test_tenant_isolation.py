from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core.models import Employee, MenuCategory, Restaurant, Table


User = get_user_model()


def client_for(username, restaurant, *, superuser=False):
    if superuser:
        user = User.objects.create_superuser(username, f"{username}@test.local", "pass")
    else:
        user = User.objects.create_user(username=username, password="pass")
        Employee.objects.create(
            user=user,
            restaurant=restaurant,
            name=username,
            role=Employee.Role.MANAGER,
        )
    token = Token.objects.create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client


class RestaurantIsolationTests(TestCase):
    def setUp(self):
        self.alpha = Restaurant.objects.create(name="Alpha", slug="alpha")
        self.beta = Restaurant.objects.create(name="Beta", slug="beta")
        self.alpha_table = Table.objects.create(restaurant=self.alpha, number=1)
        self.beta_table = Table.objects.create(restaurant=self.beta, number=1)
        MenuCategory.objects.create(restaurant=self.alpha, key="food", name="Alpha food")
        MenuCategory.objects.create(restaurant=self.beta, key="food", name="Beta food")
        self.alpha_client = client_for("alpha-manager", self.alpha)

    def test_same_business_keys_are_allowed_in_different_restaurants(self):
        self.assertEqual(Table.objects.filter(number=1).count(), 2)
        self.assertEqual(MenuCategory.objects.filter(key="food").count(), 2)

    def test_lists_and_object_ids_are_scoped_to_route_restaurant(self):
        response = self.alpha_client.get("/api/restaurants/alpha/tables/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [item["id"] for item in response.json()["results"]],
            [self.alpha_table.pk],
        )

        response = self.alpha_client.patch(
            f"/api/restaurants/alpha/tables/{self.beta_table.pk}/",
            {"label": "leaked"},
            format="json",
        )
        self.assertEqual(response.status_code, 404)

    def test_employee_cannot_enter_another_restaurants_route(self):
        response = self.alpha_client.get("/api/restaurants/beta/staff/bootstrap/")
        self.assertEqual(response.status_code, 403)

    def test_platform_owner_can_list_all_restaurants(self):
        owner = client_for("platform-owner", self.alpha, superuser=True)
        response = owner.get("/api/platform/restaurants/")
        self.assertEqual(response.status_code, 200)
        slugs = {item["slug"] for item in response.json()["restaurants"]}
        self.assertTrue({"alpha", "beta"}.issubset(slugs))
