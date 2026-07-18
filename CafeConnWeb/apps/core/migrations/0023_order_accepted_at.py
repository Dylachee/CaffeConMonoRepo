from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0022_printed_menu_categories"),
    ]

    operations = [
        migrations.AddField(
            model_name="order",
            name="accepted_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
