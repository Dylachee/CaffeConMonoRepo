"""Staff storefront/theme management: /api/staff/venue/…

GET returns the venue settings plus the built-in theme presets; PATCH updates
text/palette/layout (validation lives in VenueSettingsSerializer — bad HEX or
unknown blocks are a 400, surfaced verbatim to the editor). Logo and cover go
through dedicated multipart endpoints with Pillow validation/resize.

POST /preview/ stores a validated draft in the cache for 10 minutes and
returns a token; /menu/?preview=<token> renders the guest page with the draft
applied WITHOUT saving — the staff editor's live preview.
"""

import secrets

from django.core.cache import cache
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.permissions import HasContentCapability
from apps.api.serializers import VenueSettingsSerializer
from apps.core.media_storage import ImageValidationError, process_uploaded_image
from apps.core.models import VenueSettings
from apps.core.theme_presets import THEME_PRESETS

PREVIEW_TTL_SECONDS = 600


def preview_cache_key(token: str) -> str:
    return f"venue-preview:{token}"


class _ContentView(APIView):
    permission_classes = [permissions.IsAuthenticated, HasContentCapability]


class StaffVenueView(_ContentView):
    def get(self, request):
        settings = VenueSettings.get_solo()
        return Response(
            {
                "venue": VenueSettingsSerializer(settings).data,
                "presets": THEME_PRESETS,
            }
        )

    def patch(self, request):
        settings = VenueSettings.get_solo()
        serializer = VenueSettingsSerializer(settings, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()  # save() drops the guest-page cache
        return Response({"venue": serializer.data, "presets": THEME_PRESETS})


class StaffVenueImageView(_ContentView):
    """Upload (POST) or clear (DELETE) the venue logo/cover. `kind` is wired
    from urls.py, so /staff/venue/logo/ and /staff/venue/cover/ share code."""

    parser_classes = [MultiPartParser, FormParser, JSONParser]
    kind = "logo"

    def post(self, request):
        uploaded = request.FILES.get("image") or request.FILES.get("file")
        if uploaded is None:
            return Response(
                {"detail": "Attach the image as multipart field 'image'."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            content = process_uploaded_image(uploaded, self.kind)
        except ImageValidationError as error:
            return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)

        settings = VenueSettings.get_solo()
        field = getattr(settings, self.kind)
        if field:
            field.delete(save=False)  # drop the replaced file via the storage layer
        getattr(settings, self.kind).save(content.name, content, save=False)
        settings.save()
        return Response({"venue": VenueSettingsSerializer(settings).data})

    def delete(self, request):
        settings = VenueSettings.get_solo()
        field = getattr(settings, self.kind)
        if field:
            field.delete(save=False)
            setattr(settings, self.kind, None)
            settings.save()
        return Response({"venue": VenueSettingsSerializer(settings).data})


class StaffVenuePreviewView(_ContentView):
    """Create a short-lived draft-theme token for /menu/?preview=<token>."""

    def post(self, request):
        settings = VenueSettings.get_solo()
        serializer = VenueSettingsSerializer(settings, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)

        token = secrets.token_urlsafe(16)
        # validated_data holds only model-validated, JSON-safe values.
        cache.set(preview_cache_key(token), dict(serializer.validated_data), PREVIEW_TTL_SECONDS)
        return Response(
            {
                "token": token,
                "url": f"/menu/?preview={token}",
                "expiresIn": PREVIEW_TTL_SECONDS,
            }
        )
