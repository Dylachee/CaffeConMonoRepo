# Implements DATABASE_ANALYSIS.md §3.1/§3.2/§3.4 and the guest dish-detail
# fields: collapses the 9 order statuses to the canonical 6, cleans any rows
# that would violate the new CheckConstraints, then adds constraints and the
# hot-path composite indexes.

from django.conf import settings
from django.db import migrations, models

# pending≈new, preparing≈cooking, delivered≈completed (see Order.LEGACY_STATUS_ALIASES)
STATUS_MAP = {"pending": "new", "preparing": "cooking", "delivered": "completed"}


def collapse_statuses_and_clean(apps, schema_editor):
    Order = apps.get_model("core", "Order")
    OrderItem = apps.get_model("core", "OrderItem")
    StaffPreference = apps.get_model("core", "StaffPreference")

    for old, new in STATUS_MAP.items():
        Order.objects.filter(status=old).update(status=new)

    # Rows written before the constraints existed must not break the migration.
    OrderItem.objects.filter(quantity__lt=1).update(quantity=1)
    OrderItem.objects.filter(unit_price__lt=0).update(unit_price=0)
    StaffPreference.objects.filter(volume__gt=100).update(volume=100)


def restore_nothing(apps, schema_editor):
    # The synonyms carried no extra information — nothing to restore.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0005_simplify_table_status"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.RunPython(collapse_statuses_and_clean, restore_nothing),
        migrations.AddField(
            model_name="menuitem",
            name="calories",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="menuitem",
            name="portion_weight",
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AlterField(
            model_name="order",
            name="status",
            field=models.CharField(
                choices=[
                    ("new", "New"),
                    ("cooking", "Cooking"),
                    ("ready", "Ready"),
                    ("completed", "Completed"),
                    ("paid", "Paid"),
                    ("cancelled", "Cancelled"),
                ],
                db_index=True,
                default="new",
                max_length=32,
            ),
        ),
        migrations.AlterField(
            model_name="table",
            name="status",
            field=models.CharField(
                choices=[
                    ("free", "Free"),
                    ("occupied", "Occupied"),
                    ("waiting", "Waiting for waiter"),
                ],
                db_index=True,
                default="free",
                max_length=32,
            ),
        ),
        migrations.AddIndex(
            model_name="attentionsignal",
            index=models.Index(fields=["table", "ack"], name="signal_table_ack_idx"),
        ),
        migrations.AddIndex(
            model_name="order",
            index=models.Index(fields=["status", "-created_at"], name="order_status_created_idx"),
        ),
        migrations.AddConstraint(
            model_name="orderitem",
            constraint=models.CheckConstraint(condition=models.Q(("quantity__gte", 1)), name="orderitem_qty_gte_1"),
        ),
        migrations.AddConstraint(
            model_name="orderitem",
            constraint=models.CheckConstraint(condition=models.Q(("unit_price__gte", 0)), name="orderitem_price_gte_0"),
        ),
        migrations.AddConstraint(
            model_name="staffpreference",
            constraint=models.CheckConstraint(condition=models.Q(("volume__lte", 100)), name="staffpref_volume_lte_100"),
        ),
    ]
