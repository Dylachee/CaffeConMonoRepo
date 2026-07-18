from django.db import migrations, models


def freeze_existing_terms(apps, schema_editor):
    IssuedCoupon = apps.get_model("core", "IssuedCoupon")
    for coupon in IssuedCoupon.objects.select_related("campaign").iterator():
        campaign = coupon.campaign
        coupon.title_snapshot = campaign.title
        coupon.title_it_snapshot = campaign.title_it
        coupon.description_snapshot = campaign.description
        coupon.description_it_snapshot = campaign.description_it
        coupon.discount_type_snapshot = campaign.discount_type
        coupon.discount_value_snapshot = campaign.discount_value
        coupon.valid_from_snapshot = campaign.valid_from
        coupon.valid_until_snapshot = campaign.valid_until
        coupon.save(update_fields=[
            "title_snapshot", "title_it_snapshot", "description_snapshot",
            "description_it_snapshot", "discount_type_snapshot",
            "discount_value_snapshot", "valid_from_snapshot", "valid_until_snapshot",
        ])


class Migration(migrations.Migration):
    dependencies = [("core", "0038_fill_menu_copy_and_allergens")]

    operations = [
        migrations.AddField(model_name="issuedcoupon", name="title_snapshot", field=models.CharField(blank=True, max_length=120)),
        migrations.AddField(model_name="issuedcoupon", name="title_it_snapshot", field=models.CharField(blank=True, max_length=120)),
        migrations.AddField(model_name="issuedcoupon", name="description_snapshot", field=models.TextField(blank=True)),
        migrations.AddField(model_name="issuedcoupon", name="description_it_snapshot", field=models.TextField(blank=True)),
        migrations.AddField(model_name="issuedcoupon", name="discount_type_snapshot", field=models.CharField(blank=True, max_length=16)),
        migrations.AddField(model_name="issuedcoupon", name="discount_value_snapshot", field=models.DecimalField(blank=True, decimal_places=2, max_digits=8, null=True)),
        migrations.AddField(model_name="issuedcoupon", name="valid_from_snapshot", field=models.DateTimeField(blank=True, null=True)),
        migrations.AddField(model_name="issuedcoupon", name="valid_until_snapshot", field=models.DateTimeField(blank=True, null=True)),
        migrations.RunPython(freeze_existing_terms, migrations.RunPython.noop),
    ]
