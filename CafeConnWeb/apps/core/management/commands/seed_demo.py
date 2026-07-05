from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from rest_framework.authtoken.models import Token

from apps.core.models import Employee, MenuItem, Station, Table

User = get_user_model()


class Command(BaseCommand):
    help = "Create demo CafeConnect data for local development."

    def handle(self, *args, **options):
        self._create_staff()
        self._create_tables()
        self._create_menu()
        self.stdout.write(self.style.SUCCESS("Demo CafeConnect data is ready."))

    def _create_staff(self):
        staff = [
            ("manager", "Alex Rivera", Employee.Role.MANAGER, True, True),
            ("waiter", "Elena Sokolova", Employee.Role.WAITER, True, False),
            ("kitchen", "Ivan Kitchen", Employee.Role.KITCHEN, True, False),
            ("bar", "Sara Bar", Employee.Role.BAR, True, False),
        ]
        for username, name, role, is_staff, is_superuser in staff:
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    "first_name": name.split()[0],
                    "last_name": " ".join(name.split()[1:]),
                    "is_staff": is_staff,
                    "is_superuser": is_superuser,
                },
            )
            if created:
                user.set_password("cafeconnect")
                user.save()
            Employee.objects.update_or_create(
                user=user,
                defaults={"name": name, "role": role, "is_on_shift": True},
            )
            token, _ = Token.objects.get_or_create(user=user)
            self.stdout.write(f"{username}: Token {token.key}")

    def _create_tables(self):
        for number in range(1, 13):
            Table.objects.update_or_create(
                number=number,
                defaults={
                    "label": f"Table {number:02d}",
                    "capacity": 2 if number < 7 else 4,
                    "color_tag": "#221F1A" if number in {1, 5, 9} else "",
                },
            )

    def _create_menu(self):
        items = [
            {
                "name": "Flat white",
                "description": "Double espresso with velvety milk.",
                "price": Decimal("4.50"),
                "category": "Coffee",
                "station": Station.BAR,
                "tags": ["coffee", "milk"],
                "composition": "Espresso, milk.",
                "allergens": ["milk"],
                "image_url": "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?auto=format&fit=crop&w=900&q=80",
                "preparation_minutes": 4,
                "is_promoted": True,
            },
            {
                "name": "Cappuccino",
                "description": "Classic coffee with dense milk foam.",
                "price": Decimal("4.20"),
                "category": "Coffee",
                "station": Station.BAR,
                "tags": ["coffee", "milk"],
                "composition": "Espresso, milk, milk foam.",
                "allergens": ["milk"],
                "image_url": "https://images.unsplash.com/photo-1517701604599-bb29b565090c?auto=format&fit=crop&w=900&q=80",
                "preparation_minutes": 4,
            },
            {
                "name": "Croissant",
                "description": "Puff pastry, butter, crisp crust.",
                "price": Decimal("3.80"),
                "category": "Breakfast",
                "station": Station.KITCHEN,
                "tags": ["pastry"],
                "composition": "Puff pastry, butter.",
                "allergens": ["gluten", "milk"],
                "image_url": "https://images.unsplash.com/photo-1555507036-ab1f4038808a?auto=format&fit=crop&w=900&q=80",
                "preparation_minutes": 3,
            },
            {
                "name": "Salmon benedict",
                "description": "Poached egg, salmon, hollandaise sauce.",
                "price": Decimal("9.90"),
                "category": "Breakfast",
                "station": Station.KITCHEN,
                "tags": ["breakfast", "fish"],
                "composition": "Brioche, egg, salmon, hollandaise sauce.",
                "allergens": ["egg", "fish", "gluten"],
                "image_url": "https://images.unsplash.com/photo-1525351484163-7529414344d8?auto=format&fit=crop&w=900&q=80",
                "preparation_minutes": 10,
            },
            {
                "name": "Lemonade",
                "description": "House lemonade with citrus and mint.",
                "price": Decimal("3.50"),
                "category": "Drinks",
                "station": Station.BAR,
                "tags": ["cold", "citrus"],
                "composition": "Lemon, lime, mint, sparkling water.",
                "allergens": [],
                "image_url": "https://images.unsplash.com/photo-1621263764928-df1444c5e859?auto=format&fit=crop&w=900&q=80",
                "preparation_minutes": 2,
            },
        ]

        for item in items:
            MenuItem.objects.update_or_create(name=item["name"], defaults=item)
