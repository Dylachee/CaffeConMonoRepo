"""CafeBot: applies chat commands, posts checklists, nudges overdue tasks.

Everything that WRITES chat/task state funnels through here so the REST
views, the WS layer and the scheduler cannot drift apart:

  * post_message / post_task_bubble — create + broadcast in one step;
  * handle_command — applies a parsed slash command (or replies with the
    human-readable error, never silence);
  * mark_task_done / reopen_task — the one place task status flips;
  * run_due_jobs — the idempotent scheduler pass (checklists at their
    VenueSettings times, ONE nudge per checklist deadline, ONE overdue nudge
    per task posted as a reply into the task's own thread, /remind posts,
    recurrence materialization). Every job writes a BotJobRun key first —
    the unique constraint makes double runs (cron + ticker) post once.

Task-permission matrix (enforced in apps.api.views_tasks, asserted here in
mark_task_done as the last line of defense): `manage` does anything;
everyone else creates self-tasks and completes tasks assigned to them or
unassigned.
"""

import logging
from datetime import datetime, timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.core.chat_commands import (
    CommandError,
    EmployeeRef,
    parse_command,
)
from apps.core.models import (
    BotJobRun,
    BotReminder,
    ChatMessage,
    ChecklistTemplate,
    Employee,
    StaffTask,
    VenueSettings,
)

logger = logging.getLogger(__name__)


def _broadcast_message(message: ChatMessage, action: str = "message") -> None:
    from apps.api.events import broadcast_chat_event  # late import: no cycles

    broadcast_chat_event(action, message)


def _broadcast_task(task: StaffTask) -> None:
    from apps.api.events import broadcast_task_event

    broadcast_task_event("updated", task)


def post_message(
    *,
    channel: str,
    body: str,
    author: Employee | None = None,
    kind: str = ChatMessage.Kind.TEXT,
    task: StaffTask | None = None,
    reply_to: ChatMessage | None = None,
) -> ChatMessage:
    message = ChatMessage.objects.create(
        channel=channel,
        author=author,
        kind=kind,
        body=body,
        task=task,
        reply_to=reply_to,
    )
    _broadcast_message(message)
    return message


def post_task_bubble(
    task: StaffTask,
    *,
    channel: str = ChatMessage.Channel.GENERAL,
    author: Employee | None = None,
) -> ChatMessage:
    """Every task gets exactly one live bubble in chat — the single source of
    truth the planner links back to."""
    return post_message(
        channel=channel,
        body=task.title,
        author=author,
        kind=ChatMessage.Kind.TASK,
        task=task,
    )


def _employee_refs() -> list[EmployeeRef]:
    return [
        EmployeeRef(id=e.pk, name=e.name, username=e.user.username)
        for e in Employee.objects.select_related("user").all()
    ]


def create_task(
    *,
    title: str,
    author: Employee | None,
    assignee: Employee | None = None,
    due_at: datetime | None = None,
    category: str = StaffTask.Category.OTHER,
    note: str = "",
    source: str = StaffTask.Source.CHAT,
    channel: str = ChatMessage.Channel.GENERAL,
    recurrence: str = StaffTask.Recurrence.NONE,
    recurrence_weekdays: list | None = None,
) -> StaffTask:
    """Create a task + its chat bubble (single source of truth for both the
    chat and the planner)."""
    task = StaffTask.objects.create(
        title=title,
        note=note,
        category=category,
        assignee=assignee,
        created_by=author,
        due_at=due_at,
        source=source,
        recurrence=recurrence,
        recurrence_weekdays=recurrence_weekdays or [],
    )
    post_task_bubble(task, channel=channel, author=author)
    return task


class TaskPermissionError(Exception):
    """str() is safe to surface to the staff member."""


def mark_task_done(task: StaffTask, employee: Employee | None) -> StaffTask:
    """Complete a task. Non-manage staff may only complete tasks assigned to
    them or unassigned — the API enforces it too; this is the backstop."""
    if employee is not None and not employee.capabilities["manage"]:
        if task.assignee_id is not None and task.assignee_id != employee.pk:
            raise TaskPermissionError(
                "This task is assigned to someone else. · "
                "Questo compito è assegnato a qualcun altro."
            )
    task.status = StaffTask.Status.DONE
    task.done_by = employee
    task.done_at = timezone.now()
    task.save(update_fields=["status", "done_by", "done_at", "updated_at"])
    _broadcast_task(task)
    for bubble in task.messages.all():
        _broadcast_message(bubble, action="updated")
    return task


def reopen_task(task: StaffTask) -> StaffTask:
    task.status = StaffTask.Status.OPEN
    task.done_by = None
    task.done_at = None
    task.save(update_fields=["status", "done_by", "done_at", "updated_at"])
    _broadcast_task(task)
    for bubble in task.messages.all():
        _broadcast_message(bubble, action="updated")
    return task


def handle_command(
    *,
    text: str,
    author: Employee,
    channel: str,
    reply_to: ChatMessage | None = None,
) -> ChatMessage:
    """Apply one slash command. Always answers with a ChatMessage — either
    the result (task bubble, list, checklist) or a bot reply explaining what
    went wrong. Never silence."""
    now = timezone.localtime()
    try:
        parsed = parse_command(text, employees=_employee_refs(), now=now)
    except CommandError as error:
        return post_message(
            channel=channel,
            body=str(error),
            kind=ChatMessage.Kind.SYSTEM,
            reply_to=reply_to,
        )

    if parsed.name == "task":
        assignee = (
            Employee.objects.filter(pk=parsed.assignee.id).first()
            if parsed.assignee
            else None
        )
        # Non-manage staff create SELF-tasks only (the permission matrix).
        if (
            assignee is not None
            and assignee.pk != author.pk
            and not author.capabilities["manage"]
        ):
            return post_message(
                channel=channel,
                body=(
                    "Only a manager can assign tasks to others. · "
                    "Solo un manager può assegnare compiti agli altri."
                ),
                kind=ChatMessage.Kind.SYSTEM,
            )
        # No mention: non-manage staff create SELF-tasks; a manager's task
        # without a name stays unassigned — anyone on shift may pick it up.
        if assignee is None and not author.capabilities["manage"]:
            assignee = author
        task = StaffTask.objects.create(
            title=parsed.title,
            assignee=assignee,
            created_by=author,
            due_at=parsed.due_at,
            source=StaffTask.Source.CHAT,
        )
        return post_task_bubble(task, channel=channel, author=author)

    if parsed.name == "remind":
        BotReminder.objects.create(
            channel=channel,
            text=parsed.title,
            remind_at=parsed.due_at,
            created_by=author,
        )
        when = timezone.localtime(parsed.due_at).strftime("%H:%M")
        return post_message(
            channel=channel,
            body=f"⏰ Noted — I'll remind at {when}. · Ricevuto — ricordo alle {when}.",
            kind=ChatMessage.Kind.SYSTEM,
        )

    if parsed.name == "done":
        task = reply_to.task if reply_to is not None else None
        if task is None:
            return post_message(
                channel=channel,
                body=(
                    "Reply /done under a task bubble to complete it. · "
                    "Rispondi /done sotto un compito per completarlo."
                ),
                kind=ChatMessage.Kind.SYSTEM,
                reply_to=reply_to,
            )
        try:
            mark_task_done(task, author)
        except TaskPermissionError as error:
            return post_message(
                channel=channel,
                body=str(error),
                kind=ChatMessage.Kind.SYSTEM,
                reply_to=reply_to,
            )
        return post_message(
            channel=channel,
            body=f"✅ {task.title} — {author.name}",
            kind=ChatMessage.Kind.SYSTEM,
            reply_to=reply_to,
            task=task,
        )

    if parsed.name == "open":
        today = timezone.localtime().date()
        open_tasks = StaffTask.objects.filter(
            status=StaffTask.Status.OPEN, recurrence=StaffTask.Recurrence.NONE
        ).order_by("due_at")[:15]
        if not open_tasks:
            body = "Nothing open today. · Niente di aperto oggi."
        else:
            lines = []
            for task in open_tasks:
                due = (
                    timezone.localtime(task.due_at).strftime("%H:%M")
                    if task.due_at
                    else "—"
                )
                who = task.assignee.name if task.assignee else "anyone · chiunque"
                lines.append(f"• {task.title} ({who}, {due})")
            body = f"Open tasks {today:%d.%m} · Compiti aperti:\n" + "\n".join(lines)
        return post_message(channel=channel, body=body, kind=ChatMessage.Kind.SYSTEM)

    # /close — post the closing checklist right now, on demand.
    template = ChecklistTemplate.objects.filter(key="closing", is_active=True).first()
    if template is None:
        return post_message(
            channel=channel,
            body="No closing checklist configured. · Nessuna checklist di chiusura.",
            kind=ChatMessage.Kind.SYSTEM,
        )
    return post_checklist(template, deadline=None)


# --- checklists ---------------------------------------------------------------


def post_checklist(
    template: ChecklistTemplate, *, deadline: datetime | None
) -> ChatMessage:
    """Materialize the checklist as one task per item + one summary bubble in
    general. Each tick then records who/when on its own StaffTask."""
    tasks = []
    for item in template.items.all():
        tasks.append(
            StaffTask.objects.create(
                title=item.text if not item.text_it else f"{item.text} · {item.text_it}",
                category=template.task_category,
                due_at=deadline,
                source=StaffTask.Source.BOT,
                template_item=item,
            )
        )
    title = template.title if not template.title_it else f"{template.title} · {template.title_it}"
    message = post_message(
        channel=ChatMessage.Channel.GENERAL,
        body=title,
        kind=ChatMessage.Kind.CHECKLIST,
    )
    for task in tasks:
        post_message(
            channel=ChatMessage.Channel.GENERAL,
            body=task.title,
            kind=ChatMessage.Kind.TASK,
            task=task,
            reply_to=message,  # items live in the checklist's thread
        )
    return message


# --- the scheduler pass -------------------------------------------------------


def _claim_job(job_key: str) -> bool:
    """True when THIS caller owns the job. The unique constraint is the lock:
    a doubled run (cron + in-process ticker) loses the insert and skips."""
    try:
        with transaction.atomic():
            BotJobRun.objects.create(job_key=job_key)
        return True
    except IntegrityError:
        return False


def run_due_bot_jobs(now: datetime | None = None) -> dict:
    """One idempotent scheduler pass. Timezone-aware: all comparisons happen
    in venue-local time (Django TIME_ZONE). Returns counters for logging."""
    now = timezone.localtime(now or timezone.now())
    today = now.date()
    stats = {"checklists": 0, "checklist_nudges": 0, "task_nudges": 0, "reminders": 0, "recurrences": 0}
    venue = VenueSettings.get_solo()

    # 1) Post checklists at their configured venue-local times.
    schedule = [
        ("opening", venue.opening_checklist_time, venue.opening_checklist_deadline),
        ("closing", venue.closing_checklist_time, venue.closing_checklist_deadline),
    ]
    for key, post_time, deadline_time in schedule:
        if post_time is None or now.time() < post_time:
            continue
        template = ChecklistTemplate.objects.filter(key=key, is_active=True).first()
        if template is None:
            continue
        if not _claim_job(f"checklist:{key}:{today.isoformat()}"):
            continue
        deadline = (
            timezone.make_aware(datetime.combine(today, deadline_time))
            if deadline_time
            else None
        )
        post_checklist(template, deadline=deadline)
        stats["checklists"] += 1

    # 2) Exactly one gentle nudge per checklist at its deadline.
    for key, _post_time, deadline_time in schedule:
        if deadline_time is None or now.time() < deadline_time:
            continue
        template = ChecklistTemplate.objects.filter(key=key, is_active=True).first()
        if template is None:
            continue
        unfinished = StaffTask.objects.filter(
            template_item__template=template,
            status=StaffTask.Status.OPEN,
            created_at__date=today,
        ).count()
        if unfinished == 0:
            continue
        if not _claim_job(f"checklist-nudge:{key}:{today.isoformat()}"):
            continue
        summary = (
            ChatMessage.objects.filter(
                kind=ChatMessage.Kind.CHECKLIST,
                body__startswith=template.title,
                created_at__date=today,
            )
            .order_by("id")
            .first()
        )
        post_message(
            channel=ChatMessage.Channel.GENERAL,
            body=(
                f"🕰 {unfinished} item(s) still open. · "
                f"{unfinished} punti ancora aperti."
            ),
            kind=ChatMessage.Kind.SYSTEM,
            reply_to=summary,
        )
        stats["checklist_nudges"] += 1

    # 3) ONE overdue nudge per task, posted INTO the task's own thread so the
    #    assignee's answer lands where the owner reads the whole story.
    overdue = StaffTask.objects.filter(
        status=StaffTask.Status.OPEN,
        due_at__lt=now,
        overdue_nudged_at__isnull=True,
        recurrence=StaffTask.Recurrence.NONE,
    ).select_related("assignee")
    for task in overdue:
        if not _claim_job(f"task-nudge:{task.pk}"):
            continue
        bubble = task.messages.order_by("id").first()
        who = task.assignee.name if task.assignee else "team"
        due_text = timezone.localtime(task.due_at).strftime("%H:%M")
        post_message(
            channel=bubble.channel if bubble else ChatMessage.Channel.GENERAL,
            body=(
                f"⏳ @{who} — this was due {due_text}. Still on it? · "
                f"@{who} — scadeva alle {due_text}. Ci stai lavorando?"
            ),
            kind=ChatMessage.Kind.SYSTEM,
            reply_to=bubble,
            task=task,
        )
        task.overdue_nudged_at = timezone.now()
        task.save(update_fields=["overdue_nudged_at", "updated_at"])
        stats["task_nudges"] += 1

    # 4) Due /remind posts (compare-and-swap on posted_at).
    for reminder in BotReminder.objects.filter(
        posted_at__isnull=True, remind_at__lte=now
    ):
        claimed = BotReminder.objects.filter(
            pk=reminder.pk, posted_at__isnull=True
        ).update(posted_at=timezone.now())
        if not claimed:
            continue
        post_message(
            channel=reminder.channel,
            body=f"⏰ {reminder.text}",
            kind=ChatMessage.Kind.SYSTEM,
        )
        stats["reminders"] += 1

    # 5) Materialize today's instances of recurring rules.
    rules = StaffTask.objects.exclude(recurrence=StaffTask.Recurrence.NONE)
    for rule in rules:
        weekday_ok = (
            rule.recurrence == StaffTask.Recurrence.DAILY
            or today.weekday() in (rule.recurrence_weekdays or [])
        )
        if not weekday_ok:
            continue
        if not _claim_job(f"recur:{rule.pk}:{today.isoformat()}"):
            continue
        due = None
        if rule.due_at is not None:
            local_due = timezone.localtime(rule.due_at)
            due = timezone.make_aware(datetime.combine(today, local_due.time()))
        instance = StaffTask.objects.create(
            title=rule.title,
            note=rule.note,
            category=rule.category,
            assignee=rule.assignee,
            created_by=rule.created_by,
            due_at=due,
            source=StaffTask.Source.BOT,
            recurring_parent=rule,
        )
        post_task_bubble(instance)
        stats["recurrences"] += 1

    return stats
