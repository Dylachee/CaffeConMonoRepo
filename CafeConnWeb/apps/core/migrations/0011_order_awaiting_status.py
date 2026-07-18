from django.db import migrations, models


class Migration(migrations.Migration):
    """Adds the 'awaiting' order status (guest orders pending waiter approval).

    Choices are not enforced at the DB level, so this only updates Django's
    field state — no data change. Existing rows keep their status.
    """

    dependencies = [
        ("core", "0010_seed_waiter_accounts"),
    ]

    operations = [
        migrations.AlterField(
            model_name="order",
            name="status",
            field=models.CharField(
                choices=[
                    ("awaiting", "Awaiting waiter"),
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
    ]
