from django.core.management.base import BaseCommand
from django.db import transaction

from apps.core.menu_catalog import CLIENT_MENU_TAG, catalog_items
from apps.core.models import MenuItem, Order, Table


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

        objs = [MenuItem(**item) for item in catalog_items()]
        MenuItem.objects.bulk_create(objs)
        client_visible = sum(1 for item in objs if CLIENT_MENU_TAG in item.tags)

        self.stdout.write(
            self.style.SUCCESS(
                f"Deleted {orders} orders and {old_menu} old menu items. "
                f"Created {len(objs)} menu items "
                f"({client_visible} client-visible, all available)."
            )
        )
