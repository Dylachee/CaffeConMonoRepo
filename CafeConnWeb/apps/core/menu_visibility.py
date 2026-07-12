from datetime import date

from django.utils import timezone


ARCHIVE_TAG = "archived"
VALID_UNTIL_TAG = "valid_until:"


def menu_item_tags(item):
    tags = getattr(item, "tags", None) or []
    return tags if isinstance(tags, list) else []


def menu_item_archived(item):
    return ARCHIVE_TAG in menu_item_tags(item)


def menu_item_expired(item, today=None):
    today = today or timezone.localdate()
    for tag in menu_item_tags(item):
        if not isinstance(tag, str) or not tag.startswith(VALID_UNTIL_TAG):
            continue
        try:
            valid_until = date.fromisoformat(tag.removeprefix(VALID_UNTIL_TAG))
        except ValueError:
            continue
        if today > valid_until:
            return True
    return False


def menu_item_guest_candidate(item, today=None):
    return (
        getattr(item, "is_available", False)
        and not menu_item_archived(item)
        and not menu_item_expired(item, today=today)
    )


def menu_item_guest_visible(item, today=None):
    return menu_item_guest_candidate(item, today=today)


def guest_visible_menu_items(items, today=None):
    today = today or timezone.localdate()
    return [
        item
        for item in items
        if menu_item_guest_candidate(item, today=today)
    ]
