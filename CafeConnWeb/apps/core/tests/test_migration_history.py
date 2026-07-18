from django.db import connection
from django.db.migrations.loader import MigrationLoader
from django.test import SimpleTestCase


class DeployedMigrationHistoryTests(SimpleTestCase):
    """The production database records these names; never renumber them."""

    databases = {"default"}

    def test_deployed_core_chain_remains_addressable(self):
        loader = MigrationLoader(connection, ignore_no_migrations=True)
        deployed_names = {
            "0008_ensure_django_admin_superuser",
            "0009_sync_printed_sissi_menu",
            "0010_seed_waiter_accounts",
            "0011_order_awaiting_status",
            "0012_employee_capabilities",
            "0013_reset_sissi_menu",
            "0014_reset_staff_accounts",
            "0015_order_event",
            "0016_dedupe_menu_items",
            "0017_dedupe_menu_by_label",
            "0018_archive_obsolete_menu_items",
            "0019_archive_unavailable_menu_items",
            "0020_reload_sissi_menu",
            "0021_raw_staff_menu_client_tags",
            "0022_printed_menu_categories",
            "0023_order_accepted_at",
            "0024_seed_popular_tags",
            "0025_menu_families",
            "0026_menu_categories",
            "0027_normalize_sissi_menu",
            "0028_social_posts_venue_settings_smm",
            "0029_seed_venue_settings",
            "0030_coupons_wallets_discount",
            "0031_alerts_push_escalation",
            "0032_chat_tasks_checklists",
            "0033_seed_checklists",
        }
        disk_names = {
            name for app, name in loader.disk_migrations if app == "core"
        }
        self.assertTrue(deployed_names.issubset(disk_names))

        restaurant_migration = loader.disk_migrations[
            (
                "core",
                "0034_restaurant_employee_can_manage_employee_can_reports_and_more",
            )
        ]
        self.assertIn(
            ("core", "0033_seed_checklists"), restaurant_migration.dependencies
        )
