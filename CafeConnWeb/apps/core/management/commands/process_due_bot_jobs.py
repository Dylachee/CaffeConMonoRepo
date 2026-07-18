"""Run one idempotent CafeBot scheduler pass.

Posts due checklists, deadline nudges, overdue-task thread nudges, /remind
messages and recurring-task instances. Every job claims a unique BotJobRun
key first, so running this twice (or alongside the in-process ticker) posts
everything exactly once.

Deployment options:
  * Render Cron Job:  */5 * * * *  python manage.py process_due_bot_jobs
  * or set CAFECONNECT_BOT_TICKER=1 on the web service — apps.core starts a
    daemon ticker thread calling the same pass every minute (idempotent, so
    running both is safe).
"""

from django.core.management.base import BaseCommand

from apps.core.chatbot import run_due_bot_jobs


class Command(BaseCommand):
    help = "Run one idempotent CafeBot scheduler pass (checklists, nudges, reminders)."

    def handle(self, *args, **options):
        stats = run_due_bot_jobs()
        self.stdout.write(self.style.SUCCESS(f"bot pass: {stats}"))
