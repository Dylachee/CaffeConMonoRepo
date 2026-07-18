import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0014_reset_staff_accounts"),
    ]

    operations = [
        migrations.CreateModel(
            name="OrderEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "action",
                    models.CharField(
                        choices=[
                            ("created", "Created"),
                            ("confirmed", "Confirmed"),
                            ("rejected", "Rejected"),
                            ("item_ready", "Marked ready"),
                            ("item_delivered", "Delivered"),
                            ("item_undelivered", "Undelivered"),
                            ("item_deleted", "Item removed"),
                            ("status", "Status changed"),
                        ],
                        db_index=True,
                        max_length=32,
                    ),
                ),
                ("detail", models.CharField(blank=True, max_length=255)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                (
                    "actor",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="order_events",
                        to="core.employee",
                    ),
                ),
                (
                    "order",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="events",
                        to="core.order",
                    ),
                ),
            ],
            options={
                "db_table": "cafe_order_events",
                "ordering": ["created_at"],
            },
        ),
    ]
