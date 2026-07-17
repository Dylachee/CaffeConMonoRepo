"""Guest-facing JSON endpoint for the venue's social feed.

Loaded lazily by the Feed tab on the guest page — never during the initial
/menu/ render. Cursor pagination by id over the unpinned stream; pinned posts
(few by design, capped by the pinned limit) ride along on the first page only,
ahead of everything else.
"""

from django.http import JsonResponse
from django.views.decorators.http import require_GET

from apps.core.models import SocialPost
from apps.core.social_embed import EMBED_SCRIPTS, domain_for_display

_PAGE_MAX = 30
_PAGE_DEFAULT = 6


def _post_payload(post: SocialPost) -> dict:
    try:
        domain = domain_for_display(post.source_url)
    except ValueError:
        domain = ""
    return {
        "id": post.pk,
        "platform": post.platform,
        "url": post.source_url,
        "domain": domain,
        # Backend-generated markup only (apps.core.social_embed) — safe to
        # inject on the guest page.
        "embed": post.embed_html,
        "pinned": post.is_pinned,
        "createdAt": post.created_at.isoformat(),
    }


@require_GET
def feed_posts(request):
    try:
        limit = int(request.GET.get("limit", _PAGE_DEFAULT))
    except (TypeError, ValueError):
        limit = _PAGE_DEFAULT
    limit = min(max(limit, 1), _PAGE_MAX)

    cursor = request.GET.get("cursor", "")
    visible = SocialPost.objects.filter(is_hidden=False)

    pinned = []
    if not cursor:
        pinned = [
            _post_payload(post)
            for post in visible.filter(is_pinned=True).order_by("-pinned_at", "-id")
        ]

    unpinned = visible.filter(is_pinned=False).order_by("-id")
    if cursor.isdigit():
        unpinned = unpinned.filter(id__lt=int(cursor))
    page = list(unpinned[: limit + 1])
    has_more = len(page) > limit
    page = page[:limit]

    return JsonResponse(
        {
            "ok": True,
            "pinned": pinned,
            "posts": [_post_payload(post) for post in page],
            "nextCursor": page[-1].pk if page and has_more else None,
            "hasMore": has_more,
            # Official widget script per platform — the page loads each one
            # lazily, at most once, and only for platforms actually present.
            "scripts": EMBED_SCRIPTS,
        }
    )
