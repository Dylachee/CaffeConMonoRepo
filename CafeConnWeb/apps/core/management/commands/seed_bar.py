from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from rest_framework.authtoken.models import Token

from apps.core.models import Employee, MenuItem, Station, Table

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
        # Passwords are set ONLY at first creation. Change them before go-live:
        #   docker compose exec web python manage.py changepassword <username>
        staff = [
            ("tony",  "Tony",  Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("ibi",   "Ibi",   Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("alina", "Alina", Employee.Role.ADMIN, True, False, "cafeconnect"),
            ("uluk",  "Uluk",  Employee.Role.ADMIN, True, False, "cafeconnect"),
            # One account per position so the floor can work (and the app can
            # later gate features) per role. Manager gets dashboard access.
            ("manager",   "Manager",   Employee.Role.MANAGER, True,  False, "Manager2026!"),
            ("waiter",    "Waiter",    Employee.Role.WAITER,  False, False, "Waiter2026!"),
            ("cook",      "Cook",      Employee.Role.KITCHEN, False, False, "Cook2026!"),
            ("bartender", "Bartender", Employee.Role.BAR,     False, False, "Bartender2026!"),
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
        items = [
            # ── CAFFETTERIA (bar) ─────────────────────────────────────────────
            {
                "name": "Caffè espresso",
                "description": "Classico espresso italiano.",
                "price": Decimal("1.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Caffè macchiato",
                "description": "Espresso con una macchia di latte.",
                "price": Decimal("2.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Americano",
                "description": "Caffè americano lungo.",
                "price": Decimal("2.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Decaffeinato",
                "description": "Caffè decaffeinato.",
                "price": Decimal("2.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Caffè con panna",
                "description": "Espresso con panna.",
                "price": Decimal("2.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Cappuccino",
                "description": "Espresso con schiuma di latte vellutata.",
                "price": Decimal("3.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
                "tags": ["popular"],
            },
            {
                "name": "Cappuccino miele e cannella",
                "description": "Cappuccino con miele e cannella.",
                "price": Decimal("4.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Flat White",
                "description": "Doppio espresso con latte cremoso.",
                "price": Decimal("3.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Latte Macchiato",
                "description": "Latte caldo con un tocco di espresso.",
                "price": Decimal("3.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Babycino",
                "description": "Latte montato per bambini.",
                "price": Decimal("3.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Punch",
                "description": "Punch caldo.",
                "price": Decimal("5.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Cioccolata calda",
                "description": "Cioccolata calda densa e cremosa.",
                "price": Decimal("5.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Bombardino",
                "description": "Classica bevanda calda alcolica invernale.",
                "price": Decimal("5.00"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Tè / Tisana",
                "description": "Selezione di tè e tisane artigianali.",
                "price": Decimal("3.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            {
                "name": "Tè freddo",
                "description": "Tè freddo in bottiglia.",
                "price": Decimal("4.50"),
                "category": "Caffetteria",
                "station": Station.BAR,
            },
            # ── BEVANDE (bar) ─────────────────────────────────────────────────
            {
                "name": "Acqua naturale 0,5l",
                "description": "Acqua minerale naturale Pejo.",
                "price": Decimal("2.50"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Acqua frizzante 0,5l",
                "description": "Acqua minerale frizzante Pejo.",
                "price": Decimal("2.50"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Coca Cola",
                "description": "Coca Cola in bottiglia.",
                "price": Decimal("4.50"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Limonata",
                "description": "Limonata fresca.",
                "price": Decimal("4.50"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Aranciata",
                "description": "Aranciata San Pellegrino.",
                "price": Decimal("4.50"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Spremuta d'arancia",
                "description": "Succo di arancia fresco.",
                "price": Decimal("6.00"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Red Bull",
                "description": "Energy drink.",
                "price": Decimal("4.00"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            {
                "name": "Milkshake",
                "description": "Milkshake cremoso.",
                "price": Decimal("7.00"),
                "category": "Bevande",
                "station": Station.BAR,
            },
            # ── BIRRA (bar) ───────────────────────────────────────────────────
            {
                "name": "Birra piccola alla spina",
                "description": "Kronenbourg 1664 alla spina 0,25l.",
                "price": Decimal("4.00"),
                "category": "Birra",
                "station": Station.BAR,
            },
            {
                "name": "Birra media alla spina",
                "description": "Kronenbourg 1664 alla spina 0,5l.",
                "price": Decimal("7.00"),
                "category": "Birra",
                "station": Station.BAR,
            },
            {
                "name": "Birra Forst in bottiglia",
                "description": "Birra Forst in bottiglia.",
                "price": Decimal("5.00"),
                "category": "Birra",
                "station": Station.BAR,
            },
            {
                "name": "Peroni Doppio Malto",
                "description": "Birra Peroni Gran Riserva in bottiglia.",
                "price": Decimal("5.00"),
                "category": "Birra",
                "station": Station.BAR,
            },
            # ── APERITIVI (bar) ───────────────────────────────────────────────
            {
                "name": "Aperol Spritz",
                "description": "Aperol, Prosecco, soda.",
                "price": Decimal("8.00"),
                "category": "Aperitivi",
                "station": Station.BAR,
                "tags": ["popular"],
            },
            {
                "name": "Hugo",
                "description": "Prosecco, sciroppo di fiori di sambuco, menta, soda.",
                "price": Decimal("10.00"),
                "category": "Aperitivi",
                "station": Station.BAR,
            },
            {
                "name": "Campari Soda",
                "description": "Campari con soda.",
                "price": Decimal("6.00"),
                "category": "Aperitivi",
                "station": Station.BAR,
            },
            {
                "name": "Campari Shakerato",
                "description": "Campari agitato con ghiaccio.",
                "price": Decimal("7.00"),
                "category": "Aperitivi",
                "station": Station.BAR,
            },
            {
                "name": "Limoncello Spritz",
                "description": "Limoncello, Prosecco, soda.",
                "price": Decimal("10.00"),
                "category": "Aperitivi",
                "station": Station.BAR,
            },
            {
                "name": "Negroni",
                "description": "Gin, Campari, Vermouth rosso.",
                "price": Decimal("14.00"),
                "category": "Aperitivi",
                "station": Station.BAR,
            },
            # ── COCKTAILS (bar) ───────────────────────────────────────────────
            {
                "name": "Moscow Mule",
                "description": "Vodka, ginger beer, lime.",
                "price": Decimal("12.00"),
                "category": "Cocktails",
                "station": Station.BAR,
            },
            {
                "name": "Margarita",
                "description": "Tequila, triple sec, lime.",
                "price": Decimal("12.00"),
                "category": "Cocktails",
                "station": Station.BAR,
            },
            {
                "name": "Bloody Mary",
                "description": "Vodka, succo di pomodoro, spezie.",
                "price": Decimal("12.00"),
                "category": "Cocktails",
                "station": Station.BAR,
            },
            {
                "name": "Cuba Libre",
                "description": "Rum, Coca Cola, lime.",
                "price": Decimal("12.00"),
                "category": "Cocktails",
                "station": Station.BAR,
            },
            {
                "name": "Caipirinha",
                "description": "Cachaca, lime, zucchero di canna.",
                "price": Decimal("12.00"),
                "category": "Cocktails",
                "station": Station.BAR,
            },
            {
                "name": "Sissi Signature Cocktail",
                "description": "Il cocktail della casa — chiedi al barman.",
                "price": Decimal("14.00"),
                "category": "Cocktails",
                "station": Station.BAR,
            },
            # ── VINO (bar) ────────────────────────────────────────────────────
            {
                "name": "Pinot Grigio al calice",
                "description": "Pinot Grigio locale.",
                "price": Decimal("6.00"),
                "category": "Vino",
                "station": Station.BAR,
            },
            {
                "name": "Gewürztraminer al calice",
                "description": "Aromatico e floreale.",
                "price": Decimal("6.00"),
                "category": "Vino",
                "station": Station.BAR,
            },
            {
                "name": "Lagrain al calice",
                "description": "Rosso trentino corposo.",
                "price": Decimal("6.00"),
                "category": "Vino",
                "station": Station.BAR,
            },
            {
                "name": "Prosecco Valdobbiadene",
                "description": "Prosecco DOC al calice.",
                "price": Decimal("6.00"),
                "category": "Vino",
                "station": Station.BAR,
            },
            # ── COLAZIONE — breakfast 8–12 (kitchen) ─────────────────────────
            {
                "name": "Croissant crema",
                "description": "Krapfen croissant con crema pasticcera.",
                "price": Decimal("2.50"),
                "category": "Colazione",
                "station": Station.KITCHEN,
            },
            {
                "name": "Croissant marmellata",
                "description": "Krapfen croissant con marmellata.",
                "price": Decimal("2.50"),
                "category": "Colazione",
                "station": Station.KITCHEN,
            },
            {
                "name": "Croissant vegano",
                "description": "Croissant vegano senza lattosio.",
                "price": Decimal("3.00"),
                "category": "Colazione",
                "station": Station.KITCHEN,
            },
            {
                "name": "French Toast con miele",
                "description": "French toast servito con miele o Nutella.",
                "price": Decimal("7.00"),
                "category": "Colazione",
                "station": Station.KITCHEN,
            },
            {
                "name": "Uova bacon",
                "description": "Uova strapazzate con bacon croccante.",
                "price": Decimal("13.00"),
                "category": "Colazione",
                "station": Station.KITCHEN,
            },
            {
                "name": "Omelette cotto e formaggio",
                "description": "Omelette con prosciutto cotto e formaggio.",
                "price": Decimal("8.50"),
                "category": "Colazione",
                "station": Station.KITCHEN,
            },
            # ── CUCINA — kitchen 12–16 (kitchen) ─────────────────────────────
            {
                "name": "Tortel di patate con salsiccia",
                "description": "Tortel di patate trentino con salsiccia.",
                "price": Decimal("18.00"),
                "category": "Cucina",
                "station": Station.KITCHEN,
            },
            {
                "name": "Tortel di patate con caprese",
                "description": "Tortel di patate con mozzarella e pomodoro.",
                "price": Decimal("14.00"),
                "category": "Cucina",
                "station": Station.KITCHEN,
            },
            {
                "name": "Cotoletta con patatine fritte",
                "description": "Cotoletta alla milanese con patatine fritte.",
                "price": Decimal("16.00"),
                "category": "Cucina",
                "station": Station.KITCHEN,
                "tags": ["popular"],
            },
            {
                "name": "Patatine fritte",
                "description": "Patatine fritte croccanti.",
                "price": Decimal("5.50"),
                "category": "Cucina",
                "station": Station.KITCHEN,
            },
            # ── MENU DEL GIORNO — 05/07, hidden after 2026-07-05 ──────────────
            {
                "name": "Spiedino di pollo con patatine fritte",
                "description": "Spiedino di pollo servito con patatine fritte.",
                "price": Decimal("14.00"),
                "category": "Menu del giorno",
                "station": Station.KITCHEN,
                "tags": ["daily", "valid_until:2026-07-05"],
                "is_promoted": True,
            },
            {
                "name": "Caprese",
                "description": "Pomodoro, mozzarella e basilico.",
                "price": Decimal("12.00"),
                "category": "Menu del giorno",
                "station": Station.KITCHEN,
                "tags": ["daily", "valid_until:2026-07-05"],
                "is_promoted": True,
            },
            {
                "name": "Cestino di insalata verde rucola e pomodoro",
                "description": "Insalata verde con rucola e pomodoro.",
                "price": Decimal("12.00"),
                "category": "Menu del giorno",
                "station": Station.KITCHEN,
                "tags": ["daily", "valid_until:2026-07-05"],
                "is_promoted": True,
            },
            {
                "name": "Nuggets di pollo",
                "description": "Nuggets di pollo.",
                "price": Decimal("6.00"),
                "category": "Menu del giorno",
                "station": Station.KITCHEN,
                "tags": ["daily", "valid_until:2026-07-05"],
                "is_promoted": True,
            },
            {
                "name": "Piadina tacchino pomodoro insalata",
                "description": "Piadina con tacchino, pomodoro e insalata.",
                "price": Decimal("8.50"),
                "category": "Menu del giorno",
                "station": Station.KITCHEN,
                "tags": ["daily", "valid_until:2026-07-05"],
                "is_promoted": True,
            },
            # ── PANINI (kitchen) ──────────────────────────────────────────────
            {
                "name": "Hamburger Sissi",
                "description": "Hamburger di manzo, cipolla fritta, insalata.",
                "price": Decimal("14.00"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            {
                "name": "Hamburger vegetariano",
                "description": "Burger vegetale, mozzarella, pomodoro, insalata.",
                "price": Decimal("8.00"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            {
                "name": "Club Sandwich",
                "description": "Pane, pollo, bacon, lattuga, pomodoro, maionese.",
                "price": Decimal("8.00"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            {
                "name": "Panino Speck",
                "description": "Speck Alto Adige, formaggio e verdure.",
                "price": Decimal("8.80"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            {
                "name": "Montanaro",
                "description": "Panino con speck, formaggi e noci.",
                "price": Decimal("12.00"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            {
                "name": "Snowboard",
                "description": "Cotoletta, maionese, pomodoro, insalata, cipolla.",
                "price": Decimal("13.00"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            {
                "name": "Tirolese",
                "description": "Panino con speck, crauti e senape.",
                "price": Decimal("12.00"),
                "category": "Panini",
                "station": Station.KITCHEN,
            },
            # ── DOLCI (bar — dessert station is at the bar in this venue) ────
            {
                "name": "Strudel di mele",
                "description": "Strudel di mele con vaniglia e panna.",
                "price": Decimal("6.50"),
                "category": "Dolci",
                "station": Station.BAR,
                "tags": ["popular"],
            },
            {
                "name": "Cheesecake Sissi",
                "description": "Cheesecake della casa.",
                "price": Decimal("6.50"),
                "category": "Dolci",
                "station": Station.BAR,
            },
            {
                "name": "Sacher",
                "description": "Torta Sacher con salsa di vaniglia e panna.",
                "price": Decimal("6.00"),
                "category": "Dolci",
                "station": Station.BAR,
            },
            {
                "name": "Crostata del giorno",
                "description": "Crostata con marmellata di stagione.",
                "price": Decimal("3.50"),
                "category": "Dolci",
                "station": Station.BAR,
            },
            {
                "name": "Crepes con Nutella",
                "description": "Crepes calde con Nutella.",
                "price": Decimal("7.00"),
                "category": "Dolci",
                "station": Station.BAR,
            },
            {
                "name": "Torta di carote",
                "description": "Torta di carote con panna.",
                "price": Decimal("6.00"),
                "category": "Dolci",
                "station": Station.BAR,
            },
            # ── GELATI (bar) ──────────────────────────────────────────────────
            {
                "name": "Gelato cono / coppetta (1 gusto)",
                "description": "Un gusto a scelta.",
                "price": Decimal("2.00"),
                "category": "Gelati",
                "station": Station.BAR,
            },
            {
                "name": "Gelato coppetta (2 gusti)",
                "description": "Due gusti a scelta.",
                "price": Decimal("3.50"),
                "category": "Gelati",
                "station": Station.BAR,
            },
            {
                "name": "Coppa gelato",
                "description": "Coppa di gelato con tre gusti e panna.",
                "price": Decimal("6.50"),
                "category": "Gelati",
                "station": Station.BAR,
            },
            {
                "name": "Affogato al caffè",
                "description": "Gelato alla vaniglia con espresso caldo.",
                "price": Decimal("4.00"),
                "category": "Gelati",
                "station": Station.BAR,
            },
            {
                "name": "Frappè",
                "description": "Gelato frullato con latte.",
                "price": Decimal("8.50"),
                "category": "Gelati",
                "station": Station.BAR,
            },
        ]

        for item in items:
            self._enrich_menu_item(item)
            obj, created = MenuItem.objects.update_or_create(
                name=item["name"], defaults=item
            )
            status = "created" if created else "updated"
            self.stdout.write(f"  [{item['category']}] {item['name']} — {status}")

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
        if any(word in text for word in ["latte", "cappuccino", "milk", "formaggio", "mozzarella", "panna", "gelato", "cheesecake", "cioccolata", "bombardino", "frappè"]):
            allergens.append("Milk")
        if any(word in text for word in ["croissant", "toast", "cotoletta", "hamburger", "burger", "club sandwich", "panino", "piadina", "nuggets", "strudel", "sacher", "crostata", "crepes", "torta", "birra"]):
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
        if "0,5l" in name or "media" in name:
            return "500 ml"
        if "piccola" in name or "0,25l" in name:
            return "250 ml"
        if category in {"Caffetteria", "Bevande", "Birra", "Aperitivi", "Cocktails", "Vino"}:
            return "150-250 ml"
        if category in {"Colazione", "Dolci", "Gelati"}:
            return "1 portion"
        return "1 plate"

    def _default_calories(self, item):
        category = item["category"]
        text = f"{item['name']} {item.get('description', '')}".lower()
        if category == "Caffetteria":
            if "espresso" in text or "tè" in text or "tisana" in text:
                return 5
            if "cioccolata" in text or "bombardino" in text:
                return 260
            return 130
        if category in {"Bevande", "Aperitivi", "Cocktails", "Vino", "Birra"}:
            if "acqua" in text:
                return 0
            return 160
        if category == "Colazione":
            return 320
        if category in {"Cucina", "Panini", "Menu del giorno"}:
            return 650
        return 360

    def _default_prep(self, item):
        if item["category"] in {"Cucina", "Panini", "Menu del giorno"}:
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
            if item.order_items.exists():
                item.is_available = False
                item.save(update_fields=["is_available", "updated_at"])
                self.stdout.write(f"  [demo cleanup] '{name}' — hidden (has order history, not deleted)")
            else:
                item.delete()
                self.stdout.write(f"  [demo cleanup] '{name}' — deleted")
