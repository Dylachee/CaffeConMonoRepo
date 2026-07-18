"""Optional in-process scheduler ticker for single-instance deployments.

Opt-in via CAFECONNECT_BOT_TICKER=1 (set on the Render web service). Runs the
same idempotent pass as `manage.py process_due_bot_jobs` every minute in a
daemon thread; the BotJobRun unique keys guarantee that the ticker and any
cron job can coexist without double-posting. Never enabled during tests or
one-off management commands (they don't set the env flag).
"""

import logging
import os
import threading
import time

logger = logging.getLogger(__name__)

_started = False
_TICK_SECONDS = 60


def start_ticker_once() -> None:
    global _started
    if _started or os.getenv("CAFECONNECT_BOT_TICKER", "").strip() not in ("1", "true", "yes"):
        return
    _started = True

    def _loop():
        # Late imports: Django is fully loaded by the time the thread ticks.
        from django.db import close_old_connections

        from apps.core.chatbot import run_due_bot_jobs

        while True:
            time.sleep(_TICK_SECONDS)
            try:
                close_old_connections()
                run_due_bot_jobs()
            except Exception as error:  # never kill the thread — log and retry
                logger.warning("bot ticker pass failed: %s", error)

    thread = threading.Thread(target=_loop, name="cafebot-ticker", daemon=True)
    thread.start()
    logger.info("CafeBot in-process ticker started (every %ss)", _TICK_SECONDS)
