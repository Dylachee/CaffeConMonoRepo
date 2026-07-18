"""Staff management of the venue's social feed: /api/staff/feed/…

Gated on the `content` capability (or `manage`) — see HasContentCapability.
Post markup is generated exclusively by apps.core.social_embed from a
whitelist-validated URL; a bad link is a 400 with a human-readable message,
exceeding the pinned limit is a 409, never a 500.
"""

from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.permissions import HasContentCapability
from apps.api.serializers import SocialPostSerializer
from apps.api.tenant import employee_for_request, restaurant_for_request
from apps.core.models import SocialPost, VenueSettings
from apps.core.social_embed import SocialEmbedError, build_embed, detect_platform


class _ContentView(APIView):
    permission_classes = [permissions.IsAuthenticated, HasContentCapability]


class StaffFeedView(_ContentView):
    """GET: the whole feed as staff sees it (hidden posts included), pinned
    first. POST: create a post from a pasted URL."""

    def get(self, request):
        restaurant = restaurant_for_request(request)
        posts = SocialPost.objects.filter(restaurant=restaurant).select_related("created_by")[:200]
        return Response(
            {
                "posts": SocialPostSerializer(posts, many=True).data,
                "pinnedLimit": VenueSettings.get_solo(restaurant.slug).pinned_posts_limit,
            }
        )

    def post(self, request):
        restaurant = restaurant_for_request(request)
        url = (request.data.get("url") or "").strip()
        try:
            platform, normalized = detect_platform(url)
        except SocialEmbedError as error:
            return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)

        existing = SocialPost.objects.filter(
            restaurant=restaurant, source_url=normalized
        ).first()
        if existing is not None:
            return Response(
                {"detail": "This post is already on the feed."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        post = SocialPost.objects.create(
            restaurant=restaurant,
            source_url=normalized,
            platform=platform,
            embed_html=build_embed(platform, normalized),
            created_by=employee_for_request(request),
        )
        return Response(SocialPostSerializer(post).data, status=status.HTTP_201_CREATED)


class StaffFeedDetailView(_ContentView):
    def delete(self, request, pk):
        post = get_object_or_404(
            SocialPost, restaurant=restaurant_for_request(request), pk=pk
        )
        post.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class StaffFeedPinView(_ContentView):
    def post(self, request, pk):
        restaurant = restaurant_for_request(request)
        post = get_object_or_404(SocialPost, restaurant=restaurant, pk=pk)
        limit = VenueSettings.get_solo(restaurant.slug).pinned_posts_limit
        pinned = SocialPost.objects.filter(
            restaurant=restaurant, is_pinned=True
        ).exclude(pk=post.pk).count()
        if not post.is_pinned and pinned >= limit:
            return Response(
                {
                    "detail": (
                        f"Pinned limit reached ({limit}). "
                        "Unpin another post first, or raise the limit in Storefront settings."
                    )
                },
                status=status.HTTP_409_CONFLICT,
            )
        post.pin()
        return Response(SocialPostSerializer(post).data)


class StaffFeedUnpinView(_ContentView):
    def post(self, request, pk):
        post = get_object_or_404(
            SocialPost, restaurant=restaurant_for_request(request), pk=pk
        )
        post.unpin()
        return Response(SocialPostSerializer(post).data)


class StaffFeedHideView(_ContentView):
    """Toggle a post's guest visibility (hide/unhide)."""

    def post(self, request, pk):
        post = get_object_or_404(
            SocialPost, restaurant=restaurant_for_request(request), pk=pk
        )
        post.is_hidden = not post.is_hidden
        post.save(update_fields=["is_hidden"])
        return Response(SocialPostSerializer(post).data)
