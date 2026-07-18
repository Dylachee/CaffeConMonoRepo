"""Generate a VAPID key pair for Web Push and print the env lines to set.

Run once per deployment:

    python manage.py generate_vapid_keys

Copy the three lines into the Render environment (or .env). Without them the
push feature stays silently off — nothing else breaks (see apps/core/push.py).
"""

import base64

from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Generate a VAPID key pair for Web Push and print env values."

    def handle(self, *args, **options):
        try:
            from py_vapid import Vapid02, b64urlencode
        except ImportError:
            self.stderr.write(
                "py_vapid is not installed — run: pip install pywebpush"
            )
            return

        vapid = Vapid02()
        vapid.generate_keys()

        # Private key: raw 32-byte scalar, base64url — the form pywebpush accepts.
        private_value = vapid.private_key.private_numbers().private_value
        private_b64 = b64urlencode(private_value.to_bytes(32, "big"))

        # Public key: uncompressed EC point (65 bytes), base64url — the
        # applicationServerKey the browser's pushManager.subscribe() needs.
        from cryptography.hazmat.primitives import serialization

        public_bytes = vapid.public_key.public_bytes(
            serialization.Encoding.X962,
            serialization.PublicFormat.UncompressedPoint,
        )
        public_b64 = base64.urlsafe_b64encode(public_bytes).rstrip(b"=").decode()

        self.stdout.write(self.style.SUCCESS("Add these to the environment:"))
        self.stdout.write(f"VAPID_PRIVATE_KEY={private_b64}")
        self.stdout.write(f"VAPID_PUBLIC_KEY={public_b64}")
        self.stdout.write("VAPID_ADMIN_EMAIL=staff@your-venue.example")
