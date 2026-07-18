from django.apps import AppConfig


class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.core"
    verbose_name = "CafeConnect Core"

    def ready(self):
        # Opt-in CafeBot scheduler thread (CAFECONNECT_BOT_TICKER=1). A no-op
        # otherwise — tests and management commands never start it.
        from apps.core.bot_ticker import start_ticker_once

        start_ticker_once()
