import json
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from apps.core.menu_snapshots import menu_snapshot_payload
from apps.core.models import Restaurant


class Command(BaseCommand):
    help = "Export one restaurant's complete menu as a deterministic seed snapshot."

    def add_arguments(self, parser):
        parser.add_argument("--restaurant", required=True, help="Restaurant slug.")
        parser.add_argument("--output", help="Destination JSON path.")

    def handle(self, *args, **options):
        slug = options["restaurant"]
        try:
            restaurant = Restaurant.objects.get(slug=slug)
        except Restaurant.DoesNotExist as error:
            raise CommandError(f"Unknown restaurant: {slug}") from error

        payload = menu_snapshot_payload(restaurant)
        output = Path(options.get("output") or (
            settings.BASE_DIR / "apps" / "core" / "menu_snapshots" / f"{slug}.json"
        ))
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        self.stdout.write(
            self.style.SUCCESS(
                f"Exported {len(payload['categories'])} categories and "
                f"{len(payload['items'])} items to {output}."
            )
        )
