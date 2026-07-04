# Hand-written (no local Django runner). Collapses the nine table statuses
# down to three: free / occupied / waiting ("ждёт официанта").
#
# Old value            -> new value
#   reserved, closed   -> free      (nobody is at the table)
#   ready              -> occupied  (guests are seated, order in progress)
#   new_order, awaiting_payment, needs_service, late -> waiting
#                                   (all of these meant "a waiter must come")

from django.db import migrations, models

OLD_TO_NEW = {
    "reserved": "free",
    "closed": "free",
    "ready": "occupied",
    "new_order": "waiting",
    "awaiting_payment": "waiting",
    "needs_service": "waiting",
    "late": "waiting",
}


def simplify_statuses(apps, schema_editor):
    Table = apps.get_model("core", "Table")
    for old, new in OLD_TO_NEW.items():
        Table.objects.filter(status=old).update(status=new)


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0004_alter_table_status"),
    ]

    operations = [
        migrations.RunPython(simplify_statuses, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="table",
            name="status",
            field=models.CharField(
                choices=[
                    ("free", "Свободен"),
                    ("occupied", "Занят"),
                    ("waiting", "Ждёт официанта"),
                ],
                default="free",
                max_length=32,
            ),
        ),
    ]
