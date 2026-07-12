from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from rest_framework.authtoken.models import Token

from apps.core.models import Employee, MenuFamily, MenuItem, Table
from apps.core.sissi_menu import catalog_items, menu_families

User = get_user_model()


class Command(BaseCommand):
    help = "Seed production data for Sissi Bistro Bar."

    def handle(self, *args, **options):
        self._create_staff()
        self._create_tables()
        self._create_menu()
        self._cleanup_demo_items()
        self.stdout.write(self.style.SUCCESS("Sissi Bistro Bar — ready."))

    def _create_staff(self):
        # (username, display name, role, is_staff, is_superuser, default password)
        # Passwords are set ONLY at first creation. Change them before go-live.
        staff = [
            ("tony", "Tony", Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("ibi", "Ibi", Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("alina", "Alina", Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("uluk", "Uluk", Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("manager", "Manager", Employee.Role.MANAGER, True, False, "Manager2026!"),
            ("waiter", "Waiter", Employee.Role.WAITER, False, False, "Waiter2026!"),
            ("cook", "Cook", Employee.Role.KITCHEN, False, False, "Cook2026!"),
            ("bartender", "Bartender", Employee.Role.BAR, False, False, "Bartender2026!"),
        ]
        for username, name, role, is_staff, is_superuser, password in staff:
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    "first_name": name,
                    "is_staff": is_staff,
                    "is_superuser": is_superuser,
                },
            )
            if created:
                user.set_password(password)
                user.save()
            Employee.objects.update_or_create(
                user=user,
                defaults={"name": name, "role": role, "is_on_shift": True},
            )
            token, _ = Token.objects.get_or_create(user=user)
            self.stdout.write(f"  {username}: Token {token.key}")

    def _create_tables(self):
        for number in range(1, 31):
            Table.objects.update_or_create(
                number=number,
                defaults={
                    "label": f"Table {number:02d}",
                    "capacity": 4,
                },
            )

    def _create_menu(self):
        active_keys = set()
        created = updated = 0
        families = self._sync_menu_families()
        for item in catalog_items():
            family_key = item.pop("family_key")
            item["family"] = families[family_key]
            self._enrich_menu_item(item)
            active_keys.add((item["station"], item["category"], item["name"]))
            was_created = self._upsert_menu_item(item)
            created += int(was_created)
            updated += int(not was_created)

        removed = self._archive_missing_menu_items(active_keys)
        self.stdout.write(
            f"  menu: {created} created, {updated} updated, {removed} old rows removed/archived"
        )

    def _upsert_menu_item(self, data):
        matches = list(
            MenuItem.objects.filter(
                station=data["station"], category=data["category"], name=data["name"]
            ).order_by("id")
        )
        active = [item for item in matches if "archived" not in (item.tags or [])]
        if not active:
            MenuItem.objects.create(**data)
            return True

        item = active[0]
        for field, value in data.items():
            setattr(item, field, value)
        item.save(update_fields=[*data.keys(), "updated_at"])
        for duplicate in active[1:]:
            self._archive_or_delete(duplicate)
        return False

    def _archive_missing_menu_items(self, active_keys):
        removed = 0
        for item in list(MenuItem.objects.all()):
            if (item.station, item.category, item.name) in active_keys:
                continue
            if "archived" in (item.tags or []):
                continue
            self._archive_or_delete(item)
            removed += 1
        return removed

    def _archive_or_delete(self, item):
        if item.order_items.exists():
            tags = list(item.tags or [])
            if "archived" not in tags:
                tags.append("archived")
            item.tags = tags
            item.is_available = False
            item.save(update_fields=["tags", "is_available", "updated_at"])
            self.stdout.write(f"  [menu cleanup] '{item.name}' — archived")
            return
        item.delete()
        self.stdout.write(f"  [menu cleanup] '{item.name}' — deleted")

    def _enrich_menu_item(self, item):
        item.setdefault("is_promoted", False)
        item.setdefault("composition", item.get("description", ""))
        item.setdefault("allergens", self._infer_allergens(item))
        item.setdefault("portion_weight", self._default_portion(item))
        item.setdefault("calories", self._default_calories(item))
        item.setdefault("preparation_minutes", self._default_prep(item))

    def _infer_allergens(self, item):
        text = f"{item['name']} {item.get('description', '')}".lower()
        allergens = []
        if any(
            word in text
            for word in [
                "latte",
                "cappuccino",
                "milk",
                "formaggio",
                "mozzarella",
                "panna",
                "gelato",
                "cheesecake",
                "cioccolata",
                "bombardino",
                "frappè",
            ]
        ):
            allergens.append("Milk")
        if any(
            word in text
            for word in [
                "croissant",
                "toast",
                "cotoletta",
                "hamburger",
                "burger",
                "club sandwich",
                "panino",
                "piadina",
                "nuggets",
                "strudel",
                "sacher",
                "crostata",
                "crepes",
                "torta",
                "birra",
            ]
        ):
            allergens.append("Gluten")
        if any(word in text for word in ["uova", "omelette", "crema", "maionese", "crepes", "sacher", "torta"]):
            allergens.append("Eggs")
        if any(word in text for word in ["noci", "nutella"]):
            allergens.append("Nuts")
        if "senape" in text:
            allergens.append("Mustard")
        if item["category"] == "Vino":
            allergens.append("Sulphites")
        return allergens

    def _default_portion(self, item):
        category = item["category"]
        name = item["name"].lower()
        if "0,5" in name or "media" in name:
            return "500 ml"
        if "piccola" in name or "0,25" in name:
            return "250 ml"
        if category in {"Caffetteria", "Bevande", "Birra", "Aperitivi", "Cocktails", "Vino", "Liquori"}:
            return "150-250 ml"
        if category in {"Colazione", "Dolci", "Gelati"}:
            return "1 portion"
        return "1 plate"

    def _default_calories(self, item):
        category = item["category"]
        text = f"{item['name']} {item.get('description', '')}".lower()
        if category == "Caffetteria":
            if "espresso" in text or "caffè" == text or "tè" in text or "tisana" in text:
                return 5
            if "cioccolata" in text or "bombardino" in text:
                return 260
            return 130
        if category in {"Bevande", "Aperitivi", "Cocktails", "Vino", "Birra", "Liquori"}:
            if "acqua" in text:
                return 0
            return 160
        if category == "Colazione":
            return 320
        if category in {"Cucina", "Food", "Panini", "Menu del giorno"}:
            return 650
        return 360

    def _default_prep(self, item):
        if item["category"] in {"Cucina", "Food", "Panini", "Menu del giorno"}:
            return 12
        if item["category"] in {"Colazione", "Dolci", "Gelati"}:
            return 7
        return 5

    def _cleanup_demo_items(self):
        """Remove seed_demo placeholder items that don't belong to Sissi Bistro Bar."""
        demo_names = [
            "Флэт уайт",
            "Капучино",
            "Круассан",
            "Бенедикт с лососем",
            "Лимонад",
        ]
        for name in demo_names:
            try:
                item = MenuItem.objects.get(name=name)
            except MenuItem.DoesNotExist:
                continue
            self._archive_or_delete(item)

    def _sync_menu_families(self):
        families = {}
        for family in menu_families():
            obj, _ = MenuFamily.objects.update_or_create(
                key=family["key"],
                defaults={
                    "name": family["name"],
                    "color": family["color"],
                    "sort_order": family["sort_order"],
                },
            )
            families[family["key"]] = obj
        return families
