from apps.core.models import MenuCategory, MenuItem


def menu_snapshot_payload(restaurant):
    categories = MenuCategory.objects.filter(restaurant=restaurant).order_by(
        "sort_order", "id"
    )
    items = MenuItem.objects.filter(restaurant=restaurant).select_related(
        "category"
    ).order_by("category__sort_order", "category_id", "name", "id")
    return {
        "version": 1,
        "restaurant": restaurant.slug,
        "categories": [
            {
                "key": category.key,
                "name": category.name,
                "color": category.color,
                "sort_order": category.sort_order,
            }
            for category in categories
        ],
        "items": [
            {
                "name": item.name,
                "description": item.description,
                "price": str(item.price),
                "category": item.category.key,
                "image_url": item.image_url,
                "station": item.station,
                "tags": item.tags,
                "composition": item.composition,
                "allergens": item.allergens,
                "is_available": item.is_available,
                "is_promoted": item.is_promoted,
                "preparation_minutes": item.preparation_minutes,
                "portion_weight": item.portion_weight,
                "calories": item.calories,
            }
            for item in items
        ],
    }
