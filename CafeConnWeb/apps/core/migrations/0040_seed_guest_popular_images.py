from django.db import migrations


POPULAR_IMAGES = {
    "Cappuccino": "https://images.unsplash.com/photo-1518810300173-625a9c46f7d2?auto=format&fit=crop&w=900&q=80",
    "Bombardino": "https://images.unsplash.com/photo-1559842590-3696b9eb73b1?auto=format&fit=crop&w=900&q=80",
    "Aperol Spritz": "https://images.unsplash.com/photo-1570598912132-0ba1dc952b7d?auto=format&fit=crop&w=900&q=80",
    "Strudel di mele": "https://images.pexels.com/photos/36414757/pexels-photo-36414757.jpeg?auto=compress&cs=tinysrgb&w=900",
}


def seed_guest_popular_images(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    MenuItem.objects.filter(
        restaurant__slug="sissy-bar", name__in=POPULAR_IMAGES
    ).update(is_promoted=True)
    for name, image_url in POPULAR_IMAGES.items():
        MenuItem.objects.filter(
            restaurant__slug="sissy-bar", name=name, image_url=""
        ).update(image_url=image_url)


class Migration(migrations.Migration):

    dependencies = [("core", "0039_issuedcoupon_frozen_terms")]

    operations = [migrations.RunPython(seed_guest_popular_images, migrations.RunPython.noop)]
