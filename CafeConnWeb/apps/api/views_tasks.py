"""Staff tasks REST — the same StaffTask objects behind chat bubbles and the
owner planner.

Permission matrix (also backstopped in apps.core.chatbot):
  * `manage` — create/assign/edit/cancel anything, including recurrence rules;
  * everyone else — create SELF-tasks, complete tasks assigned to them or
    unassigned. Reading is open to all staff (the chat shows the bubbles
    anyway; the app decides between Planner and "My tasks").
"""

import datetime

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.serializers import ChatMessageSerializer, StaffTaskSerializer
from apps.api.tenant import (
    capabilities_for_request,
    employee_for_request,
    restaurant_for_request,
)
from apps.core import chatbot
from apps.core.chat_commands import CommandError, EmployeeRef, parse_command
from apps.core.chatbot import TaskPermissionError
from apps.core.models import ChatMessage, Employee, StaffTask, TaskEvent


def _employee_or_none(request):
    return employee_for_request(request)


def _caps(request):
    return capabilities_for_request(request)


class StaffTasksView(APIView):
    """GET: the planner's day view (default today, venue-local) — open tasks
    due that day, everything overdue, dueless open tasks and tasks completed
    that day. POST: quick-add using the /task syntax or structured fields."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        restaurant = restaurant_for_request(request)
        employee = _employee_or_none(request)
        date_text = request.query_params.get("date", "")
        try:
            day = (
                datetime.date.fromisoformat(date_text)
                if date_text
                else timezone.localtime().date()
            )
        except ValueError:
            return Response(
                {"detail": "date must be YYYY-MM-DD."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        tz = timezone.get_current_timezone()
        day_start = datetime.datetime.combine(day, datetime.time.min, tzinfo=tz)
        day_end = day_start + datetime.timedelta(days=1)

        instances = StaffTask.objects.filter(
            restaurant=restaurant,
            recurrence=StaffTask.Recurrence.NONE
        ).select_related("assignee", "created_by", "done_by", "template_item__template")
        if not _caps(request)["manage"]:
            instances = instances.filter(
                Q(
                    assignee=employee,
                    status__in=[
                        StaffTask.Status.AVAILABLE,
                        StaffTask.Status.IN_PROGRESS,
                        StaffTask.Status.OPEN,
                    ],
                )
                | Q(
                    assignee__isnull=True,
                    status__in=[StaffTask.Status.AVAILABLE, StaffTask.Status.OPEN],
                )
                | Q(status=StaffTask.Status.DONE, done_by=employee)
            )
        tasks = instances.filter(
            # Open and relevant to this day: due on it, overdue before it,
            # or dueless (created on/before the day).
            status__in=[
                StaffTask.Status.AVAILABLE,
                StaffTask.Status.IN_PROGRESS,
                StaffTask.Status.OPEN,
            ],
            created_at__lt=day_end,
        ).exclude(due_at__gte=day_end) | instances.filter(
            status=StaffTask.Status.DONE,
            done_at__gte=day_start,
            done_at__lt=day_end,
        )
        if _caps(request)["manage"]:
            tasks = tasks | instances.filter(
                status=StaffTask.Status.CANCELLED,
                updated_at__gte=day_start,
                updated_at__lt=day_end,
            )
        payload = StaffTaskSerializer(
            tasks.distinct().order_by("due_at", "id"), many=True
        ).data
        rules = []
        if _caps(request)["manage"]:
            rules = StaffTaskSerializer(
                StaffTask.objects.exclude(recurrence=StaffTask.Recurrence.NONE)
                .filter(restaurant=restaurant)
                .select_related("assignee", "created_by", "done_by")
                .order_by("id"),
                many=True,
            ).data
        return Response(
            {
                "date": day.isoformat(),
                "tasks": payload,
                "assignees": list(
                    Employee.objects.filter(restaurant=restaurant)
                    .order_by("-is_on_shift", "name")
                    .values("id", "name", "role", "is_on_shift")
                ),
                "mine": [item for item in payload if employee and item.get("assignee") == employee.pk],
                "available": [item for item in payload if not item.get("assignee")],
                "done": [item for item in payload if item.get("status") == StaffTask.Status.DONE],
                "cancelled": [
                    item for item in payload
                    if item.get("status") == StaffTask.Status.CANCELLED
                ],
                "rules": rules,
            }
        )

    def post(self, request):
        restaurant = restaurant_for_request(request)
        employee = _employee_or_none(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        manage = _caps(request)["manage"]

        raw_input = (request.data.get("input") or "").strip()
        if raw_input:
            # The planner quick-add speaks the SAME syntax as /task.
            text = raw_input if raw_input.startswith("/") else f"/task {raw_input}"
            employees = [
                EmployeeRef(id=e.pk, name=e.name, username=e.user.username)
                for e in Employee.objects.filter(restaurant=restaurant).select_related("user")
            ]
            try:
                parsed = parse_command(
                    text, employees=employees, now=timezone.localtime()
                )
            except CommandError as error:
                return Response(
                    {"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST
                )
            if parsed.name != "task":
                return Response(
                    {"detail": "Only /task syntax works here."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            assignee = (
                Employee.objects.filter(
                    restaurant=restaurant, pk=parsed.assignee.id
                ).first()
                if parsed.assignee
                else None
            )
            if assignee is not None and assignee.pk != employee.pk and not manage:
                return Response(
                    {"detail": "Only a manager can assign tasks to others."},
                    status=status.HTTP_403_FORBIDDEN,
                )
            if assignee is None and not manage:
                assignee = employee  # self-task; managers may leave it open
            task = chatbot.create_task(
                title=parsed.title,
                author=employee,
                assignee=assignee,
                due_at=parsed.due_at,
                source=StaffTask.Source.PLANNER,
            )
            return Response(
                {"task": StaffTaskSerializer(task).data},
                status=status.HTTP_201_CREATED,
            )

        # Structured create (the manager's full form, incl. recurrence rules).
        serializer = StaffTaskSerializer(
            data=request.data, context={"restaurant": restaurant}
        )
        serializer.is_valid(raise_exception=True)
        assignee = serializer.validated_data.get("assignee")
        if not manage:
            if assignee is not None and assignee.pk != employee.pk:
                return Response(
                    {"detail": "Only a manager can assign tasks to others."},
                    status=status.HTTP_403_FORBIDDEN,
                )
            if serializer.validated_data.get("recurrence", StaffTask.Recurrence.NONE) != StaffTask.Recurrence.NONE:
                return Response(
                    {"detail": "Only a manager can create recurring tasks."},
                    status=status.HTTP_403_FORBIDDEN,
                )
        task = serializer.save(
            restaurant=restaurant,
            created_by=employee,
            assignee=assignee if (assignee is not None or manage) else employee,
            status=(
                StaffTask.Status.IN_PROGRESS
                if (assignee is not None or not manage)
                else StaffTask.Status.AVAILABLE
            ),
            source=StaffTask.Source.PLANNER,
        )
        TaskEvent.objects.create(
            restaurant=restaurant,
            task=task,
            actor=employee,
            action=TaskEvent.Action.CREATED,
        )
        if not task.is_recurring_rule:
            chatbot.post_task_bubble(task, author=employee)
        elif task.recurrence_enabled:
            venue_tz = timezone.get_current_timezone()
            selected_day = (
                timezone.localtime(task.due_at, venue_tz).date()
                if task.due_at is not None
                else timezone.localdate()
            )
            chatbot.materialize_recurring_task(task, selected_day)
        return Response(
            {"task": StaffTaskSerializer(task).data}, status=status.HTTP_201_CREATED
        )


class StaffTaskDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, pk):
        if not _caps(request)["manage"]:
            return Response(
                {"detail": "Only a manager can edit tasks."},
                status=status.HTTP_403_FORBIDDEN,
            )
        restaurant = restaurant_for_request(request)
        task = get_object_or_404(StaffTask, restaurant=restaurant, pk=pk)
        previous_assignee = task.assignee
        serializer = StaffTaskSerializer(
            task,
            data=request.data,
            partial=True,
            context={"restaurant": restaurant},
        )
        serializer.is_valid(raise_exception=True)
        task = serializer.save()
        if task.assignee_id != (previous_assignee.pk if previous_assignee else None):
            TaskEvent.objects.create(
                restaurant=restaurant,
                task=task,
                actor=_employee_or_none(request),
                action=TaskEvent.Action.REASSIGNED,
                detail=(
                    f"{previous_assignee.name if previous_assignee else 'Available'} → "
                    f"{task.assignee.name if task.assignee else 'Available'}"
                ),
            )
        from apps.api.events import broadcast_task_event

        broadcast_task_event("updated", task)
        return Response({"task": StaffTaskSerializer(task).data})

    def delete(self, request, pk):
        if not _caps(request)["manage"]:
            return Response(
                {"detail": "Only a manager can cancel tasks."},
                status=status.HTTP_403_FORBIDDEN,
            )
        restaurant = restaurant_for_request(request)
        task = get_object_or_404(StaffTask, restaurant=restaurant, pk=pk)
        task.status = StaffTask.Status.CANCELLED
        if task.is_recurring_rule:
            task.recurrence_enabled = False
        task.save(update_fields=["status", "recurrence_enabled", "updated_at"])
        TaskEvent.objects.create(
            restaurant=restaurant,
            task=task,
            actor=_employee_or_none(request),
            action=TaskEvent.Action.CANCELLED,
        )
        from apps.api.events import broadcast_task_event

        broadcast_task_event("updated", task)
        return Response({"task": StaffTaskSerializer(task).data})


class StaffTaskDoneView(APIView):
    """POST {done: true|false} — the big checkbox on task bubbles and planner
    rows. Completion permission follows the matrix; errors surface verbatim."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        employee = _employee_or_none(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        task = get_object_or_404(
            StaffTask, restaurant=restaurant_for_request(request), pk=pk
        )
        wants_done = bool(request.data.get("done", True))
        try:
            if wants_done:
                task = chatbot.mark_task_done(task, employee)
            else:
                if (
                    not _caps(request)["manage"]
                    and task.done_by is not None
                    and task.done_by.pk != employee.pk
                ):
                    return Response(
                        {"detail": "Only a manager can reopen someone else's tick."},
                        status=status.HTTP_403_FORBIDDEN,
                    )
                task = chatbot.reopen_task(task)
        except TaskPermissionError as error:
            return Response({"detail": str(error)}, status=status.HTTP_403_FORBIDDEN)
        return Response({"task": StaffTaskSerializer(task).data})


class StaffTaskTakeView(APIView):
    """Claim an available task before working on it."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, pk):
        employee = _employee_or_none(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        restaurant = restaurant_for_request(request)
        task = get_object_or_404(
            StaffTask.objects.select_for_update(), restaurant=restaurant, pk=pk
        )
        if task.assignee_id not in (None, employee.pk):
            return Response(
                {"detail": "This task was already taken."},
                status=status.HTTP_409_CONFLICT,
            )
        if task.status not in {StaffTask.Status.AVAILABLE, StaffTask.Status.OPEN}:
            return Response(
                {"detail": "Only an available task can be taken."},
                status=status.HTTP_409_CONFLICT,
            )
        task.assignee = employee
        task.status = StaffTask.Status.IN_PROGRESS
        task.save(update_fields=["assignee", "status", "updated_at"])
        TaskEvent.objects.create(
            restaurant=restaurant,
            task=task,
            actor=employee,
            action=TaskEvent.Action.TAKEN,
        )
        from apps.api.events import broadcast_task_event

        broadcast_task_event("updated", task)
        return Response({"task": StaffTaskSerializer(task).data})


class StaffTaskLeaveView(APIView):
    """Return the signed-in employee's task to the available pool."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        employee = _employee_or_none(request)
        restaurant = restaurant_for_request(request)
        task = get_object_or_404(StaffTask, restaurant=restaurant, pk=pk)
        if employee is None or task.assignee_id != employee.pk:
            return Response(
                {"detail": "Only the assigned employee can leave this task."},
                status=status.HTTP_403_FORBIDDEN,
            )
        note = (request.data.get("note") or "").strip()[:255]
        task.assignee = None
        task.status = StaffTask.Status.AVAILABLE
        task.save(update_fields=["assignee", "status", "updated_at"])
        TaskEvent.objects.create(
            restaurant=restaurant,
            task=task,
            actor=employee,
            action=TaskEvent.Action.LEFT,
            detail=note,
        )
        from apps.api.events import broadcast_task_event

        broadcast_task_event("updated", task)
        return Response({"task": StaffTaskSerializer(task).data})


class StaffTaskThreadView(APIView):
    """The task's chat thread (its bubble + replies) — what the planner opens
    when the owner taps a task."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        restaurant = restaurant_for_request(request)
        task = get_object_or_404(StaffTask, restaurant=restaurant, pk=pk)
        bubble = task.messages.order_by("id").first()
        if bubble is None:
            return Response({"message": None, "replies": []})
        replies = (
            ChatMessage.objects.filter(restaurant=restaurant, reply_to=bubble)
            .select_related("author", "task")
            .order_by("id")
        )
        return Response(
            {
                "message": ChatMessageSerializer(bubble).data,
                "replies": ChatMessageSerializer(replies, many=True).data,
            }
        )
