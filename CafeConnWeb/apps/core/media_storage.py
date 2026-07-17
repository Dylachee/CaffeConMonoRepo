"""Thin storage layer for venue media (logo / cover).

Render's disk is ephemeral, so uploads work locally through MEDIA_ROOT today
but will move to S3/Cloudinary later. Every file access for venue media goes
through this module so that swap is one function, not a rewrite: point
`venue_media_storage` at another django Storage backend and everything —
ImageField saves, URL generation, deletes — follows.
"""

import io
import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage


def venue_media_storage():
    """The Storage backend for venue images. Passed as a callable to
    ImageField(storage=...), so changing this return value re-targets the
    fields without a migration."""
    return default_storage


def venue_image_path(instance, filename: str) -> str:
    """Stable, collision-free path under MEDIA_ROOT (or the future bucket)."""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpg"
    return f"venue/{uuid.uuid4().hex}.{ext}"


# Upload guardrails: what the /api/staff/venue/ upload endpoints accept.
ALLOWED_IMAGE_FORMATS = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}
MAX_UPLOAD_BYTES = 8 * 1024 * 1024  # a phone photo, not a video

# Longest edge after resize. Covers are wide, logos small — both far below
# these caps render crisply on a phone at 2-3x DPR.
MAX_EDGE = {"logo": 512, "cover": 1600}


class ImageValidationError(ValueError):
    """Invalid uploaded image. `str(error)` is safe to show to a human."""


def process_uploaded_image(uploaded_file, kind: str) -> ContentFile:
    """Validate type/size and resize an uploaded logo/cover with Pillow.

    Returns a ContentFile (with a generated name) ready to assign to the
    ImageField. Raises ImageValidationError with a human-readable message on
    anything unusable — the API surfaces it verbatim as a 400.
    """
    from PIL import Image, UnidentifiedImageError

    if kind not in MAX_EDGE:
        raise ImageValidationError("Unknown image kind.")
    size = getattr(uploaded_file, "size", None)
    if size is not None and size > MAX_UPLOAD_BYTES:
        raise ImageValidationError("Image is too large (max 8 MB).")

    try:
        image = Image.open(uploaded_file)
        image.load()
    except (UnidentifiedImageError, OSError):
        raise ImageValidationError("The file is not a readable image (JPEG/PNG/WebP).")

    source_format = (image.format or "").upper()
    if source_format not in ALLOWED_IMAGE_FORMATS:
        raise ImageValidationError("Use a JPEG, PNG or WebP image.")

    max_edge = MAX_EDGE[kind]
    if max(image.size) > max_edge:
        image.thumbnail((max_edge, max_edge), Image.LANCZOS)

    # Re-encode through Pillow: strips anything that is not pixels and makes
    # the stored bytes our own, never the raw upload.
    buffer = io.BytesIO()
    if source_format == "JPEG":
        image = image.convert("RGB")
        image.save(buffer, format="JPEG", quality=88, optimize=True)
    else:
        image.save(buffer, format=source_format)
    ext = ALLOWED_IMAGE_FORMATS[source_format]
    return ContentFile(buffer.getvalue(), name=f"{kind}.{ext}")
