from collections import defaultdict

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.core.models import MenuFamily, MenuItem, Order, Table
from apps.core.sissi_menu import MANUAL_CHECK_TAG, STATION_CHECK_TAG, catalog_items, menu_families


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

        orders = Order.objects.count()
        # Order delete cascades OrderItem + OrderEvent; removing the OrderItems
        # frees the PROTECT on MenuItem so the menu can be replaced.
        Order.objects.all().delete()

        # No orders left, so free every table.
        Table.objects.update(
            status=Table.Status.FREE,
            guest_count=0,
            opened_at=None,
            attention=Table.Attention.NONE,
            attention_reason="",
            attention_acknowledged=False,
        )

        old_menu = MenuItem.objects.count()
        MenuItem.objects.all().delete()

        families = self._sync_menu_families()
        stats = {
            "created": defaultdict(int),
            "updated": defaultdict(int),
            "categories": defaultdict(set),
        }
        check_items = []

        for item in catalog_items():
            family_key = item.pop("family_key")
            item["family"] = families[family_key]
            was_created = self._upsert_menu_item(item)
            station = item["station"]
            stats["created" if was_created else "updated"][station] += 1
            stats["categories"][station].add(item["category"])
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

    def _upsert_menu_item(self, data):
        lookup = {
            "station": data["station"],
            "category": data["category"],
            "name": data["name"],
        }
        defaults = {key: value for key, value in data.items() if key not in lookup}
        _, created = MenuItem.objects.update_or_create(**lookup, defaults=defaults)
        return created
