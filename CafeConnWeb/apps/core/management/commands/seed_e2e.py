import json
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction
from rest_framework.authtoken.models import Token

from apps.core.menu_catalog import CLIENT_MENU_TAG
from apps.core.models import AttentionSignal, Employee, MenuItem, Order, Table

User = get_user_model()

E2E_TABLE_NUMBERS = [901, 902, 903]
E2E_PASSWORD = "CafeConnectE2E!"


class Command(BaseCommand):
    help = "Reset and seed deterministic data for Playwright E2E tests."

    def add_arguments(self, parser):
        parser.add_argument("--json", action="store_true", help="Print machine-readable seed details.")

    @transaction.atomic
    def handle(self, *args, **options):
        self._reset_e2e_rows()
        users = self._create_staff()
        tables = self._create_tables()
        menu = self._create_menu()

        payload = {
            "basePassword": E2E_PASSWORD,
            "users": users,
            "tables": {str(table.number): table.id for table in tables},
            "menu": {item.name: item.id for item in menu},
        }
        if options["json"]:
            self.stdout.write(json.dumps(payload, sort_keys=True))
        else:
            self.stdout.write(self.style.SUCCESS("E2E data ready."))

    def _reset_e2e_rows(self):
        tables = Table.objects.filter(number__in=E2E_TABLE_NUMBERS)
        AttentionSignal.objects.filter(table__in=tables).delete()
        Order.objects.filter(table__in=tables).delete()
        tables.update(
            status=Table.Status.FREE,
            guest_count=0,
            waiter=None,
            opened_at=None,
            attention=Table.Attention.NONE,
            attention_reason="",
            attention_acknowledged=False,
        )

    def _create_staff(self):
        specs = [
            ("e2e_manager", "E2E Manager", Employee.Role.MANAGER),
            ("e2e_waiter", "E2E Waiter", Employee.Role.WAITER),
            ("e2e_kitchen", "E2E Kitchen", Employee.Role.KITCHEN),
            ("e2e_bar", "E2E Bar", Employee.Role.BAR),
        ]
        result = {}
        for username, name, role in specs:
            user, _ = User.objects.update_or_create(
                username=username,
                defaults={
                    "first_name": name,
                    "is_staff": role == Employee.Role.MANAGER,
                    "is_superuser": False,
                },
            )
            user.set_password(E2E_PASSWORD)
            user.save(update_fields=["password", "first_name", "is_staff", "is_superuser"])
            employee, _ = Employee.objects.update_or_create(
                user=user,
                defaults={
                    "name": name,
                    "role": role,
                    "is_on_shift": True,
                    "can_wait": False,
                    "can_bar": False,
                    "can_kitchen": False,
                    "can_manage_menu": False,
                },
            )
            token, _ = Token.objects.get_or_create(user=user)
            result[username] = {
                "id": employee.id,
                "role": role,
                "token": token.key,
            }
        return result

    def _create_tables(self):
        tables = []
        for number in E2E_TABLE_NUMBERS:
            table, _ = Table.objects.update_or_create(
                number=number,
                defaults={
                    "label": f"E2E Table {number}",
                    "capacity": 4,
                    "status": Table.Status.FREE,
                    "guest_count": 0,
                    "waiter": None,
                    "attention": Table.Attention.NONE,
                    "attention_reason": "",
                    "attention_acknowledged": False,
                },
            )
            tables.append(table)
        return tables

    def _create_menu(self):
        specs = [
            {
                "name": "E2E Kitchen Item",
                "description": "Kitchen item visible to guests.",
                "price": Decimal("11.00"),
                "category": "E2E Food",
                "station": "kitchen",
                "tags": [CLIENT_MENU_TAG, "e2e"],
                "is_available": True,
                "preparation_minutes": 9,
            },
            {
                "name": "E2E Bar Drink",
                "description": "Bar item visible to guests.",
                "price": Decimal("6.00"),
                "category": "E2E Drinks",
                "station": "bar",
                "tags": [CLIENT_MENU_TAG, "e2e"],
                "is_available": True,
                "preparation_minutes": 4,
            },
            {
                "name": "E2E Staff Hidden Item",
                "description": "Staff-only item that guests must not see.",
                "price": Decimal("13.00"),
                "category": "E2E Staff",
                "station": "kitchen",
                "tags": ["e2e"],
                "is_available": True,
                "preparation_minutes": 10,
            },
            {
                "name": "E2E Stopped Item",
                "description": "Guest-visible item that is temporarily stopped.",
                "price": Decimal("7.00"),
                "category": "E2E Drinks",
                "station": "bar",
                "tags": [CLIENT_MENU_TAG, "e2e"],
                "is_available": False,
                "preparation_minutes": 4,
            },
        ]
        items = []
        for data in specs:
            item, _ = MenuItem.objects.update_or_create(
                name=data["name"],
                defaults={
                    **data,
                    "image_url": "",
                    "composition": data["description"],
                    "allergens": [],
                    "is_promoted": data["name"] in {"E2E Kitchen Item", "E2E Bar Drink"},
                    "portion_weight": "1 portion",
                    "calories": 100,
                },
            )
            items.append(item)
        return items
