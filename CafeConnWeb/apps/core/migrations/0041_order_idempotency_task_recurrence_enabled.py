from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [("core", "0040_seed_guest_popular_images")]

    operations = [
        migrations.AddField(
            model_name="order",
            name="client_request_id",
            field=models.CharField(blank=True, max_length=96, null=True),
        ),
        migrations.AddConstraint(
            model_name="order",
            constraint=models.UniqueConstraint(
                condition=models.Q(("client_request_id__isnull", False)),
                fields=("restaurant", "client_request_id"),
                name="order_rest_client_request_unique",
            ),
        ),
        migrations.AddField(
            model_name="stafftask",
            name="recurrence_enabled",
            field=models.BooleanField(default=True),
        ),
    ]
