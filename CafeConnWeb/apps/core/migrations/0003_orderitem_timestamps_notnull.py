from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0002_staff_realtime_domain"),
    ]

    operations = [
        migrations.RunSQL(
            # CURRENT_TIMESTAMP (== NOW() on Postgres) so the suite can also
            # run the chain on SQLite; identical behavior on the real DB.
            sql=[
                "UPDATE cafe_order_items SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL",
                "UPDATE cafe_order_items SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL",
            ],
            reverse_sql=migrations.RunSQL.noop,
        ),
        migrations.AlterField(
            model_name="orderitem",
            name="created_at",
            field=models.DateTimeField(auto_now_add=True),
        ),
        migrations.AlterField(
            model_name="orderitem",
            name="updated_at",
            field=models.DateTimeField(auto_now=True),
        ),
    ]
