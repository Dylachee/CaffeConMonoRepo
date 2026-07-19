from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from rest_framework.authtoken.models import Token

from apps.core.models import Employee, MenuCategory, MenuItem, Restaurant, Table
from apps.core.sissi_menu import catalog_items, menu_categories

User = get_user_model()


class Command(BaseCommand):
    help = "Seed production data for Sissi Bistro Bar."

    def add_arguments(self, parser):
        parser.add_argument("--restaurant", default="sissy-bar", help="Restaurant slug to seed.")

    def handle(self, *args, **options):
        try:
            self.restaurant = Restaurant.objects.get(slug=options["restaurant"])
        except Restaurant.DoesNotExist as error:
            raise CommandError(f"Unknown restaurant: {options['restaurant']}") from error
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
            username = self._username(username)
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
                restaurant=self.restaurant,
                user=user,
                defaults={"name": name, "role": role, "is_on_shift": True},
            )
            token, _ = Token.objects.get_or_create(user=user)
            self.stdout.write(f"  {username}: Token {token.key}")

    def _create_tables(self):
        for number in range(1, 31):
            Table.objects.update_or_create(
                restaurant=self.restaurant,
                number=number,
                defaults={
                    "label": f"Table {number:02d}",
                    "capacity": 4,
                },
            )

    def _create_menu(self):
        active_keys = set()
        created = updated = 0
        categories = self._sync_menu_categories()
        for item in catalog_items():
            category_key = item.pop("category_key")
            item["category"] = categories[category_key]
            item["restaurant"] = self.restaurant
            self._enrich_menu_item(item)
            active_keys.add((item["station"], item["category"].id, item["name"]))
            was_created = self._upsert_menu_item(item)
            created += int(was_created)
            updated += int(not was_created)

        removed = self._archive_missing_menu_items(active_keys)
        self._cleanup_empty_categories(categories)
        self.stdout.write(
            f"  menu: {created} created, {updated} updated, {removed} old rows removed/archived"
        )

    def _upsert_menu_item(self, data):
        matches = list(
            MenuItem.objects.filter(
                restaurant=self.restaurant,
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
        for item in list(MenuItem.objects.filter(restaurant=self.restaurant)):
            if (item.station, item.category_id, item.name) in active_keys:
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
        if item["category"].name == "Vino":
            allergens.append("Sulphites")
        return allergens

    def _default_portion(self, item):
        category = item["category"].name
        name = item["name"].lower()
        if "0,5" in name or "media" in name:
            return "500 ml"
        if "piccola" in name or "0,25" in name:
            return "250 ml"
        if category in {
            "Caffetteria",
            "Bevande",
            "Analcolici",
            "Birra",
            "Cocktail & Aperitivi",
            "Vino",
            "Liquori/Grappe/Amari",
        }:
            return "150-250 ml"
        if category in {"Pasticceria", "Dolci", "Gelati"}:
            return "1 portion"
        return "1 plate"

    def _default_calories(self, item):
        category = item["category"].name
        text = f"{item['name']} {item.get('description', '')}".lower()
        if category == "Caffetteria":
            if "espresso" in text or "caffè" == text or "tè" in text or "tisana" in text:
                return 5
            if "cioccolata" in text or "bombardino" in text:
                return 260
            return 130
        if category in {
            "Bevande",
            "Analcolici",
            "Cocktail & Aperitivi",
            "Vino",
            "Birra",
            "Liquori/Grappe/Amari",
        }:
            if "acqua" in text:
                return 0
            return 160
        if category == "Pasticceria":
            return 320
        if category in {
            "Panini",
            "Piadine",
            "Tortel",
            "Secondi",
            "Uova/colazione salata",
            "Toast",
            "Fritti/stuzzichini",
        }:
            return 650
        return 360

    def _default_prep(self, item):
        if item["category"].name in {
            "Panini",
            "Piadine",
            "Tortel",
            "Secondi",
            "Uova/colazione salata",
            "Toast",
            "Fritti/stuzzichini",
        }:
            return 12
        if item["category"].name in {"Pasticceria", "Dolci", "Gelati"}:
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
                item = MenuItem.objects.get(restaurant=self.restaurant, name=name)
            except MenuItem.DoesNotExist:
                continue
            self._archive_or_delete(item)

    def _sync_menu_categories(self):
        categories = {}
        for category in menu_categories():
            obj, _ = MenuCategory.objects.update_or_create(
                restaurant=self.restaurant,
                key=category["key"],
                defaults={
                    "name": category["name"],
                    "color": category["color"],
                    "sort_order": category["sort_order"],
                },
            )
            categories[category["key"]] = obj
        return categories

    def _cleanup_empty_categories(self, active_categories):
        MenuCategory.objects.filter(restaurant=self.restaurant).exclude(
            key__in=active_categories.keys()
        ).filter(items__isnull=True).delete()

    def _username(self, base):
        return base if self.restaurant.slug == "sissy-bar" else f"{self.restaurant.slug}-{base}"
