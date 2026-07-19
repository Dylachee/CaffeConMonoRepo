from collections import defaultdict

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.models import MenuCategory, MenuItem, Order, Restaurant, Table
from apps.core.sissi_menu import MANUAL_CHECK_TAG, STATION_CHECK_TAG, catalog_items, menu_categories


class Command(BaseCommand):
    help = (
        "DESTRUCTIVE: delete all orders (order history) and all menu items, "
        "then recreate the raw Sissi staff menu. Requires --yes."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--yes",
            action="store_true",
            help="Confirm: this deletes ALL orders and ALL menu items.",
        )
        parser.add_argument("--restaurant", default="sissy-bar", help="Restaurant slug to reload.")

    @transaction.atomic
    def handle(self, *args, **options):
        if not options["yes"]:
            self.stderr.write(
                self.style.ERROR(
                    "Refusing to run without --yes "
                    "(this permanently deletes all orders and menu items)."
                )
            )
            return
        try:
            self.restaurant = Restaurant.objects.get(slug=options["restaurant"])
        except Restaurant.DoesNotExist as error:
            raise CommandError(f"Unknown restaurant: {options['restaurant']}") from error

        orders = Order.objects.filter(restaurant=self.restaurant).count()
        # Order delete cascades OrderItem + OrderEvent; removing the OrderItems
        # frees the PROTECT on MenuItem so the menu can be replaced.
        Order.objects.filter(restaurant=self.restaurant).delete()

        # No orders left, so free every table.
        Table.objects.filter(restaurant=self.restaurant).update(
            status=Table.Status.FREE,
            guest_count=0,
            opened_at=None,
            attention=Table.Attention.NONE,
            attention_reason="",
            attention_acknowledged=False,
        )

        old_menu = MenuItem.objects.filter(restaurant=self.restaurant).count()
        MenuItem.objects.filter(restaurant=self.restaurant).delete()

        categories = self._sync_menu_categories()
        stats = {
            "created": defaultdict(int),
            "updated": defaultdict(int),
            "categories": defaultdict(set),
        }
        check_items = []

        for item in catalog_items():
            category_key = item.pop("category_key")
            item["category"] = categories[category_key]
            item["restaurant"] = self.restaurant
            was_created = self._upsert_menu_item(item)
            station = item["station"]
            stats["created" if was_created else "updated"][station] += 1
            stats["categories"][station].add(item["category"].name)
            if MANUAL_CHECK_TAG in item["tags"] or STATION_CHECK_TAG in item["tags"]:
                check_items.append(f"{item['station']} / {item['category']} / {item['name']}")

        self.stdout.write(
            self.style.SUCCESS(
                f"Deleted {orders} orders and {old_menu} old menu items."
            )
        )
        for station in ("bar", "kitchen"):
            self.stdout.write(
                "  "
                f"{station}: {len(stats['categories'][station])} categories, "
                f"{stats['created'][station]} created, "
                f"{stats['updated'][station]} updated"
            )
        if check_items:
            self.stdout.write("  manual check:")
            for item in check_items:
                self.stdout.write(f"    - {item}")
        self.stdout.write(
            self.style.SUCCESS(
                "Sissi menu reload complete."
            )
        )

    def _sync_menu_categories(self):
        categories = {}
        active_keys = set()
        for category in menu_categories():
            active_keys.add(category["key"])
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
        MenuCategory.objects.filter(restaurant=self.restaurant).exclude(
            key__in=active_keys
        ).filter(items__isnull=True).delete()
        return categories

    def _upsert_menu_item(self, data):
        lookup = {
            "station": data["station"],
            "category": data["category"],
            "name": data["name"],
        }
        defaults = {key: value for key, value in data.items() if key not in lookup}
        _, created = MenuItem.objects.update_or_create(**lookup, defaults=defaults)
        return created
