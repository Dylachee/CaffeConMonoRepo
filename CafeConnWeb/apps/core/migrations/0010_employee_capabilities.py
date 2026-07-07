from django.db import migrations, models


class Migration(migrations.Migration):
    """Per-employee capability grants a manager can toggle on top of the role."""

    dependencies = [
        ("core", "0009_order_awaiting_status"),
    ]

    operations = [
        migrations.AddField(
            model_name="employee",
            name="can_wait",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="employee",
            name="can_bar",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="employee",
            name="can_kitchen",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="employee",
            name="can_manage_menu",
            field=models.BooleanField(default=False),
        ),
    ]
