from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [("core", "0036_remove_accountant_add_floor_chat")]

    operations = [
        migrations.CreateModel(
            name="TableWaiterEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("action", models.CharField(choices=[("first_order", "Claimed by first order"), ("takeover", "Taken over"), ("assigned", "Assigned by manager")], max_length=24)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("actor", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="table_handoffs_made", to="core.employee")),
                ("previous_waiter", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="table_handoffs_from", to="core.employee")),
                ("restaurant", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="table_waiter_events", to="core.restaurant")),
                ("table", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="waiter_events", to="core.table")),
                ("waiter", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="table_handoffs_to", to="core.employee")),
            ],
            options={"db_table": "cafe_table_waiter_events", "ordering": ["created_at"]},
        ),
    ]
