from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0001_initial"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name="menuitem",
            name="allergens",
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name="menuitem",
            name="composition",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="menuitem",
            name="is_promoted",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="menuitem",
            name="station",
            field=models.CharField(
                choices=[("kitchen", "Kitchen"), ("bar", "Bar")],
                db_index=True,
                default="kitchen",
                max_length=24,
            ),
        ),
        migrations.AddField(
            model_name="menuitem",
            name="tags",
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name="table",
            name="attention",
            field=models.CharField(
                blank=True,
                choices=[("", "None"), ("arrived", "Arrived"), ("call", "Call waiter"), ("bill", "Bill requested")],
                default="",
                max_length=24,
            ),
        ),
        migrations.AddField(
            model_name="table",
            name="attention_acknowledged",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="table",
            name="attention_reason",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="table",
            name="color_tag",
            field=models.CharField(blank=True, max_length=24),
        ),
        migrations.AddField(
            model_name="table",
            name="guest_count",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="table",
            name="opened_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="table",
            name="waiter",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="tables",
                to="core.employee",
            ),
        ),
        migrations.AddField(
            model_name="order",
            name="source",
            field=models.CharField(
                choices=[("guest_web", "Guest web"), ("staff_app", "Staff app"), ("admin_web", "Admin web")],
                db_index=True,
                default="guest_web",
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name="order",
            name="station_scope",
            field=models.CharField(
                choices=[("mixed", "Mixed"), ("kitchen", "Kitchen"), ("bar", "Bar")],
                db_index=True,
                default="mixed",
                max_length=24,
            ),
        ),
        migrations.AlterField(
            model_name="order",
            name="status",
            field=models.CharField(
                choices=[
                    ("new", "New"),
                    ("pending", "Pending"),
                    ("cooking", "Cooking"),
                    ("preparing", "Preparing"),
                    ("ready", "Ready"),
                    ("delivered", "Delivered"),
                    ("completed", "Completed"),
                    ("paid", "Paid"),
                    ("cancelled", "Cancelled"),
                ],
                db_index=True,
                default="new",
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name="orderitem",
            name="created_at",
            field=models.DateTimeField(auto_now_add=True, null=True),
        ),
        migrations.AddField(
            model_name="orderitem",
            name="done",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="orderitem",
            name="ready",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="orderitem",
            name="station",
            field=models.CharField(
                choices=[("kitchen", "Kitchen"), ("bar", "Bar")],
                db_index=True,
                default="kitchen",
                max_length=24,
            ),
        ),
        migrations.AddField(
            model_name="orderitem",
            name="updated_at",
            field=models.DateTimeField(auto_now=True, null=True),
        ),
        migrations.AlterField(
            model_name="orderitem",
            name="notes",
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.CreateModel(
            name="StaffPreference",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("sound_arrival", models.BooleanField(default=True)),
                ("sound_call", models.BooleanField(default=True)),
                ("sound_bill", models.BooleanField(default=True)),
                ("haptics", models.BooleanField(default=True)),
                ("volume", models.PositiveSmallIntegerField(default=70)),
                ("sort_undelivered", models.BooleanField(default=True)),
                ("show_ready", models.BooleanField(default=True)),
                ("confirm_clear", models.BooleanField(default=True)),
                ("theme", models.CharField(default="light", max_length=16)),
                ("text_size", models.CharField(default="m", max_length=8)),
                ("high_contrast", models.BooleanField(default=False)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="staff_preferences",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "cafe_staff_preferences"},
        ),
        migrations.CreateModel(
            name="AttentionSignal",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "signal_type",
                    models.CharField(
                        choices=[
                            ("arrived", "Arrived"),
                            ("call_waiter", "Call waiter"),
                            ("bill_request", "Bill request"),
                        ],
                        db_index=True,
                        max_length=24,
                    ),
                ),
                ("reason", models.CharField(blank=True, max_length=255)),
                ("ack", models.BooleanField(default=False)),
                ("acked_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                (
                    "acknowledged_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="acknowledged_signals",
                        to="core.employee",
                    ),
                ),
                (
                    "table",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="attention_signals",
                        to="core.table",
                    ),
                ),
            ],
            options={"ordering": ["-created_at"], "db_table": "cafe_attention_signals"},
        ),
    ]
