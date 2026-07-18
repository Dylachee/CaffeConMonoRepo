from django.db import migrations, models


def promote_accountants(apps, schema_editor):
    Employee = apps.get_model("core", "Employee")
    Employee.objects.filter(role="accountant").update(
        role="manager",
        can_wait=True,
        can_bar=True,
        can_kitchen=True,
        can_manage_menu=True,
        can_content=True,
        can_grant_discount=True,
        can_manage=True,
        can_reports=True,
    )


class Migration(migrations.Migration):
    dependencies = [("core", "0035_taskevent")]

    operations = [
        migrations.RunPython(promote_accountants, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="employee",
            name="role",
            field=models.CharField(
                choices=[
                    ("waiter", "Waiter"),
                    ("kitchen", "Kitchen"),
                    ("bar", "Bar"),
                    ("manager", "Manager"),
                    ("admin", "Admin"),
                    ("smm", "SMM"),
                ],
                db_index=True,
                max_length=32,
            ),
        ),
        migrations.AlterField(
            model_name="chatmessage",
            name="channel",
            field=models.CharField(
                choices=[
                    ("general", "General"),
                    ("floor", "Floor"),
                    ("kitchen", "Kitchen"),
                    ("bar", "Bar"),
                ],
                db_index=True,
                max_length=16,
            ),
        ),
        migrations.AlterField(
            model_name="chatreadmark",
            name="channel",
            field=models.CharField(
                choices=[
                    ("general", "General"),
                    ("floor", "Floor"),
                    ("kitchen", "Kitchen"),
                    ("bar", "Bar"),
                ],
                max_length=16,
            ),
        ),
        migrations.AlterField(
            model_name="botreminder",
            name="channel",
            field=models.CharField(
                choices=[
                    ("general", "General"),
                    ("floor", "Floor"),
                    ("kitchen", "Kitchen"),
                    ("bar", "Bar"),
                ],
                max_length=16,
            ),
        ),
    ]
