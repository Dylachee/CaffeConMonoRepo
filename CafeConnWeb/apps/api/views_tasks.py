"""Staff tasks REST — the same StaffTask objects behind chat bubbles and the
owner planner.

Permission matrix (also backstopped in apps.core.chatbot):
  * `manage` — create/assign/edit/cancel anything, including recurrence rules;
  * everyone else — create SELF-tasks, complete tasks assigned to them or
    unassigned. Reading is open to all staff (the chat shows the bubbles
    anyway; the app decides between Planner and "My tasks").
"""

import datetime

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.serializers import ChatMessageSerializer, StaffTaskSerializer
from apps.core import chatbot
from apps.core.chat_commands import CommandError, EmployeeRef, parse_command
from apps.core.chatbot import TaskPermissionError
from apps.core.models import ChatMessage, Employee, StaffTask


def _employee_or_none(request):
    from apps.api.views import employee_for_user

    return employee_for_user(request.user)


def _caps(request):
    from apps.api.views import caps_for_user

    return caps_for_user(request.user)


class StaffTasksView(APIView):
    """GET: the planner's day view (default today, venue-local) — open tasks
    due that day, everything overdue, dueless open tasks and tasks completed
    that day. POST: quick-add using the /task syntax or structured fields."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
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
            recurrence=StaffTask.Recurrence.NONE
        ).select_related("assignee", "created_by", "done_by", "template_item__template")
        tasks = instances.filter(
            # Open and relevant to this day: due on it, overdue before it,
            # or dueless (created on/before the day).
            status=StaffTask.Status.OPEN,
            created_at__lt=day_end,
        ).exclude(due_at__gte=day_end) | instances.filter(
            status=StaffTask.Status.DONE,
            done_at__gte=day_start,
            done_at__lt=day_end,
        )
        payload = StaffTaskSerializer(
            tasks.distinct().order_by("due_at", "id"), many=True
        ).data
        rules = []
        if _caps(request)["manage"]:
            rules = StaffTaskSerializer(
                StaffTask.objects.exclude(recurrence=StaffTask.Recurrence.NONE)
                .select_related("assignee", "created_by", "done_by")
                .order_by("id"),
                many=True,
            ).data
        return Response({"date": day.isoformat(), "tasks": payload, "rules": rules})

    def post(self, request):
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
                for e in Employee.objects.select_related("user").all()
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
                Employee.objects.filter(pk=parsed.assignee.id).first()
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
        serializer = StaffTaskSerializer(data=request.data)
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
            created_by=employee,
            assignee=assignee if (assignee is not None or manage) else employee,
            source=StaffTask.Source.PLANNER,
        )
        if not task.is_recurring_rule:
            chatbot.post_task_bubble(task, author=employee)
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
        task = get_object_or_404(StaffTask, pk=pk)
        serializer = StaffTaskSerializer(task, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        task = serializer.save()
        from apps.api.events import broadcast_task_event

        broadcast_task_event("updated", task)
        return Response({"task": StaffTaskSerializer(task).data})

    def delete(self, request, pk):
        if not _caps(request)["manage"]:
            return Response(
                {"detail": "Only a manager can cancel tasks."},
                status=status.HTTP_403_FORBIDDEN,
            )
        task = get_object_or_404(StaffTask, pk=pk)
        task.status = StaffTask.Status.CANCELLED
        task.save(update_fields=["status", "updated_at"])
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
        task = get_object_or_404(StaffTask, pk=pk)
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


class StaffTaskThreadView(APIView):
    """The task's chat thread (its bubble + replies) — what the planner opens
    when the owner taps a task."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        task = get_object_or_404(StaffTask, pk=pk)
        bubble = task.messages.order_by("id").first()
        if bubble is None:
            return Response({"message": None, "replies": []})
        replies = (
            ChatMessage.objects.filter(reply_to=bubble)
            .select_related("author", "task")
            .order_by("id")
        )
        return Response(
            {
                "message": ChatMessageSerializer(bubble).data,
                "replies": ChatMessageSerializer(replies, many=True).data,
            }
        )
