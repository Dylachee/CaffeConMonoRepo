"""Web Push (VAPID) delivery to on-shift staff devices.

Feature-flagged by environment: with no VAPID keys configured every function
is a silent no-op and the rest of the alert system (WS ladder, OS banners in
a live tab) keeps working. Keys come from:

    VAPID_PRIVATE_KEY  — base64url-encoded private key (see the
                         `generate_vapid_keys` management command)
    VAPID_PUBLIC_KEY   — matching applicationServerKey for the browser
    VAPID_ADMIN_EMAIL  — contact claim, e.g. staff@cafeconnect.example

Payloads stay minimal (type, table, ids) — the service worker builds the
visible notification text; nothing sensitive travels through the push
service. Delivery is best-effort: failures are logged, dead subscriptions
(404/410 from the push service) are garbage-collected on the spot.

Platform reality (surface this to humans, don't fight it): Android Chrome
delivers with the browser closed; iOS needs 16.4+ AND the PWA installed to
the Home Screen; desktop browsers deliver while running.
"""

import json
import logging
import os

logger = logging.getLogger(__name__)


def vapid_private_key() -> str:
    return os.getenv("VAPID_PRIVATE_KEY", "").strip()


def vapid_public_key() -> str:
    return os.getenv("VAPID_PUBLIC_KEY", "").strip()


def vapid_claims() -> dict:
    email = os.getenv("VAPID_ADMIN_EMAIL", "").strip() or "admin@cafeconnect.local"
    return {"sub": f"mailto:{email}"}


def push_configured() -> bool:
    return bool(vapid_private_key() and vapid_public_key())


def send_to_subscription(subscription, payload: dict) -> bool:
    """Send one push. Returns True on success; deletes the subscription row
    when the push service says it is gone (404/410). Never raises."""
    if not push_configured():
        return False
    try:
        from pywebpush import WebPushException, webpush
    except ImportError:  # pragma: no cover — dependency present in prod
        logger.warning("pywebpush is not installed; skipping web push")
        return False

    try:
        webpush(
            subscription_info={
                "endpoint": subscription.endpoint,
                "keys": {"p256dh": subscription.p256dh, "auth": subscription.auth},
            },
            data=json.dumps(payload),
            vapid_private_key=vapid_private_key(),
            vapid_claims=dict(vapid_claims()),  # pywebpush mutates the dict
            ttl=120,  # an unanswered venue alert is stale after two minutes
        )
        return True
    except WebPushException as error:
        status = getattr(getattr(error, "response", None), "status_code", None)
        if status in (404, 410):
            # The browser unsubscribed/expired — drop the dead row.
            subscription.delete()
            logger.info("push subscription gone (%s), removed", status)
        else:
            logger.warning("web push failed (%s): %s", status, error)
        return False
    except Exception as error:  # pragma: no cover — network weirdness
        logger.warning("web push failed: %s", error)
        return False


def push_to_on_shift(
    payload: dict, *, restaurant_id: int | None = None, employee_id: int | None = None
) -> int:
    """Fan a payload out to every on-shift employee's subscriptions.
    Returns the number of successful sends. No-op when unconfigured."""
    if not push_configured():
        return 0
    from apps.core.models import PushSubscription, Restaurant

    restaurant_id = restaurant_id or Restaurant.get_default().pk

    sent = 0
    subscriptions = PushSubscription.objects.select_related("employee").filter(
        restaurant_id=restaurant_id,
        employee__is_on_shift=True,
    )
    if employee_id is not None:
        subscriptions = subscriptions.filter(employee_id=employee_id)
    for subscription in subscriptions:
        if send_to_subscription(subscription, payload):
            sent += 1
    return sent


# --- alert payload builders (one vocabulary for sw.js and the app) -----------


def attention_payload(action: str, signal) -> dict:
    return {
        "kind": "attention",
        "action": action,  # created | acked | escalated
        "signalId": signal.pk,
        "signalType": signal.signal_type,
        "table": signal.table.number,
        # One tag per signal: repeated pushes REPLACE the OS banner and the
        # ack push closes it — never a stack of stale banners.
        "tag": f"attention-{signal.pk}",
    }


def awaiting_order_payload(action: str, order) -> dict:
    return {
        "kind": "order",
        "action": action,  # created | handled | escalated
        "orderId": order.pk,
        "table": order.table.number,
        "tag": f"order-{order.pk}",
    }
