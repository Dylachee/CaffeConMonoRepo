import datetime

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from apps.core import chatbot
from apps.core.chatbot import TaskPermissionError
from apps.core.models import (
    BotJobRun,
    BotReminder,
    ChatMessage,
    ChecklistTemplate,
    Employee,
    StaffTask,
    VenueSettings,
)

User = get_user_model()


def make_employee(username: str, role: str = Employee.Role.WAITER, **flags) -> Employee:
    user = User.objects.create_user(username=f"tstb-{username}", password="x-test-pass-1")
    return Employee.objects.create(user=user, name=username, role=role, **flags)


def local(hour: int, minute: int = 0, *, day_offset: int = 0) -> datetime.datetime:
    base = timezone.localtime()
    return timezone.make_aware(
        datetime.datetime.combine(
            base.date() + datetime.timedelta(days=day_offset),
            datetime.time(hour, minute),
        )
    )


class HandleCommandTests(TestCase):
    def setUp(self):
        self.waiter = make_employee("waiter")
        self.manager = make_employee("manager-b", role=Employee.Role.MANAGER)

    def test_task_command_creates_task_and_live_bubble(self):
        message = chatbot.handle_command(
            text="/task wipe the terrace 21:30",
            author=self.manager,
            channel=ChatMessage.Channel.GENERAL,
        )
        self.assertEqual(message.kind, ChatMessage.Kind.TASK)
        task = message.task
        self.assertIsNotNone(task)
        self.assertEqual(task.title, "wipe the terrace")
        self.assertEqual(task.source, StaffTask.Source.CHAT)
        self.assertEqual(timezone.localtime(task.due_at).hour, 21)

    def test_waiter_cannot_assign_to_others_manager_can(self):
        refused = chatbot.handle_command(
            text=f"/task polish glasses @{self.manager.name.split()[0]}",
            author=self.waiter,
            channel=ChatMessage.Channel.GENERAL,
        )
        self.assertEqual(refused.kind, ChatMessage.Kind.SYSTEM)
        self.assertIn("manager", refused.body)
        self.assertEqual(StaffTask.objects.count(), 0)

        allowed = chatbot.handle_command(
            text="/task polish glasses @waiter",
            author=self.manager,
            channel=ChatMessage.Channel.GENERAL,
        )
        self.assertEqual(allowed.task.assignee, self.waiter)

    def test_waiter_task_without_mention_is_self_task(self):
        message = chatbot.handle_command(
            text="/task check napkins",
            author=self.waiter,
            channel=ChatMessage.Channel.GENERAL,
        )
        self.assertEqual(message.task.assignee, self.waiter)

    def test_malformed_command_gets_a_bot_reply_not_silence(self):
        message = chatbot.handle_command(
            text="/task",
            author=self.waiter,
            channel=ChatMessage.Channel.GENERAL,
        )
        self.assertEqual(message.kind, ChatMessage.Kind.SYSTEM)
        self.assertTrue(message.body)

    def test_done_in_thread_completes_task_with_audit(self):
        bubble = chatbot.handle_command(
            text="/task clean fryer @waiter",
            author=self.manager,
            channel=ChatMessage.Channel.GENERAL,
        )
        reply = chatbot.handle_command(
            text="/done",
            author=self.waiter,
            channel=ChatMessage.Channel.GENERAL,
            reply_to=bubble,
        )
        task = StaffTask.objects.get(pk=bubble.task.pk)
        self.assertEqual(task.status, StaffTask.Status.DONE)
        self.assertEqual(task.done_by, self.waiter)
        self.assertIsNotNone(task.done_at)
        self.assertEqual(reply.reply_to, bubble)

    def test_done_permission_backstop(self):
        other = make_employee("other-w")
        task = StaffTask.objects.create(title="x", assignee=other)
        with self.assertRaises(TaskPermissionError):
            chatbot.mark_task_done(task, self.waiter)
        # Unassigned tasks must be explicitly taken before completion.
        free_task = StaffTask.objects.create(title="y")
        with self.assertRaises(TaskPermissionError):
            chatbot.mark_task_done(free_task, self.waiter)
        free_task.assignee = self.waiter
        free_task.status = StaffTask.Status.IN_PROGRESS
        free_task.save(update_fields=["assignee", "status"])
        chatbot.mark_task_done(free_task, self.waiter)
        free_task.refresh_from_db()
        self.assertEqual(free_task.done_by, self.waiter)

    def test_remind_schedules_a_bot_reminder(self):
        chatbot.handle_command(
            text="/remind 23:55 lock the terrace door",
            author=self.waiter,
            channel=ChatMessage.Channel.BAR,
        )
        reminder = BotReminder.objects.get()
        self.assertEqual(reminder.channel, ChatMessage.Channel.BAR)
        self.assertEqual(reminder.text, "lock the terrace door")


class SchedulerTests(TestCase):
    def setUp(self):
        self.venue = VenueSettings.get_solo()
        self.venue.opening_checklist_time = datetime.time(8, 0)
        self.venue.opening_checklist_deadline = datetime.time(10, 0)
        self.venue.closing_checklist_time = None  # keep runs single-checklist
        self.venue.closing_checklist_deadline = None
        self.venue.save()
        self.waiter = make_employee("sched-w")

    def test_checklist_posts_once_even_when_run_twice(self):
        now = local(8, 5)
        first = chatbot.run_due_bot_jobs(now)
        second = chatbot.run_due_bot_jobs(now)  # cron + ticker double-fire
        self.assertEqual(first["checklists"], 1)
        self.assertEqual(second["checklists"], 0)
        summaries = ChatMessage.objects.filter(kind=ChatMessage.Kind.CHECKLIST)
        self.assertEqual(summaries.count(), 1)
        # Items became live task bubbles in the checklist's thread.
        opening = ChecklistTemplate.objects.get(key="opening")
        item_tasks = StaffTask.objects.filter(template_item__template=opening)
        self.assertEqual(item_tasks.count(), opening.items.count())
        self.assertEqual(
            ChatMessage.objects.filter(reply_to=summaries.get()).count(),
            opening.items.count(),
        )

    def test_checklist_not_posted_before_its_time(self):
        stats = chatbot.run_due_bot_jobs(local(7, 30))
        self.assertEqual(stats["checklists"], 0)

    def test_deadline_nudge_fires_once_and_only_when_unfinished(self):
        chatbot.run_due_bot_jobs(local(8, 5))
        first = chatbot.run_due_bot_jobs(local(10, 5))
        again = chatbot.run_due_bot_jobs(local(10, 20))
        self.assertEqual(first["checklist_nudges"], 1)
        self.assertEqual(again["checklist_nudges"], 0)
        nudge = ChatMessage.objects.filter(
            kind=ChatMessage.Kind.SYSTEM, body__contains="still open"
        ).get()
        summary = ChatMessage.objects.filter(kind=ChatMessage.Kind.CHECKLIST).get()
        self.assertEqual(nudge.reply_to, summary)  # nudge lives in the thread

    def test_no_deadline_nudge_when_everything_ticked(self):
        chatbot.run_due_bot_jobs(local(8, 5))
        for task in StaffTask.objects.filter(template_item__isnull=False):
            task.assignee = self.waiter
            task.status = StaffTask.Status.IN_PROGRESS
            task.save(update_fields=["assignee", "status"])
            chatbot.mark_task_done(task, self.waiter)
        stats = chatbot.run_due_bot_jobs(local(10, 5))
        self.assertEqual(stats["checklist_nudges"], 0)

    def test_overdue_nudge_lands_in_the_tasks_thread_once(self):
        bubble = chatbot.handle_command(
            text="/task descale machine 09:00",
            author=make_employee("sched-m", role=Employee.Role.MANAGER),
            channel=ChatMessage.Channel.GENERAL,
        )
        task = bubble.task
        task.due_at = local(9, 0)
        task.save(update_fields=["due_at"])

        first = chatbot.run_due_bot_jobs(local(9, 30))
        second = chatbot.run_due_bot_jobs(local(9, 45))
        self.assertEqual(first["task_nudges"], 1)
        self.assertEqual(second["task_nudges"], 0)
        nudge = ChatMessage.objects.filter(
            kind=ChatMessage.Kind.SYSTEM, reply_to=bubble
        ).get()
        self.assertIn("due", nudge.body)
        task.refresh_from_db()
        self.assertIsNotNone(task.overdue_nudged_at)

    def test_due_reminder_posts_once(self):
        BotReminder.objects.create(
            channel=ChatMessage.Channel.GENERAL,
            text="take out the bins",
            remind_at=local(9, 0),
            created_by=self.waiter,
        )
        first = chatbot.run_due_bot_jobs(local(9, 1))
        second = chatbot.run_due_bot_jobs(local(9, 2))
        self.assertEqual(first["reminders"], 1)
        self.assertEqual(second["reminders"], 0)
        self.assertTrue(
            ChatMessage.objects.filter(body__contains="take out the bins").exists()
        )

    def test_daily_recurrence_materializes_one_instance_per_day(self):
        rule = StaffTask.objects.create(
            title="Wipe the coffee grinder",
            recurrence=StaffTask.Recurrence.DAILY,
            due_at=local(18, 0),
        )
        first = chatbot.run_due_bot_jobs(local(0, 10))
        second = chatbot.run_due_bot_jobs(local(6, 0))
        self.assertEqual(first["recurrences"], 1)
        self.assertEqual(second["recurrences"], 0)
        instance = StaffTask.objects.get(recurring_parent=rule)
        self.assertEqual(instance.recurrence, StaffTask.Recurrence.NONE)
        self.assertEqual(timezone.localtime(instance.due_at).hour, 18)

    def test_weekly_recurrence_respects_weekdays(self):
        today = timezone.localtime().date().weekday()
        rule = StaffTask.objects.create(
            title="Inventory count",
            recurrence=StaffTask.Recurrence.WEEKLY,
            recurrence_weekdays=[(today + 1) % 7],  # not today
        )
        stats = chatbot.run_due_bot_jobs(local(0, 10))
        self.assertEqual(stats["recurrences"], 0)
        self.assertFalse(StaffTask.objects.filter(recurring_parent=rule).exists())
        # Job key was not burned — the matching day will still materialize it.
        self.assertFalse(
            BotJobRun.objects.filter(job_key__startswith=f"recur:{rule.pk}").exists()
        )
