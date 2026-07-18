from django.db import migrations


def fill_menu_copy_and_allergens(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    from apps.core.menu_content import ALLERGEN_REVIEW_TAG, menu_content

    for item in MenuItem.objects.select_related("category").iterator():
        content = menu_content(item.name, item.category.name)
        fields = []
        if not item.description:
            item.description = content["description"]
            fields.append("description")
        if not item.composition:
            item.composition = content["composition"]
            fields.append("composition")
        if not item.allergens:
            item.allergens = content["allergens"]
            fields.append("allergens")
        tags = list(item.tags or [])
        if ALLERGEN_REVIEW_TAG not in tags:
            item.tags = [*tags, ALLERGEN_REVIEW_TAG]
            fields.append("tags")
        if fields:
            item.save(update_fields=fields)


class Migration(migrations.Migration):
    dependencies = [("core", "0037_tablewaiterevent")]

    operations = [migrations.RunPython(fill_menu_copy_and_allergens, migrations.RunPython.noop)]
