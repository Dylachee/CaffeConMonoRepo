"""Staff chat REST: history with cursor pagination, sending (text and slash
commands), threads, read marks. Live delivery rides the `chat_event` fan-out
on StaffConsumer; these endpoints are the source of truth that survives
reloads. Chat is append-only — no edit/delete endpoints by design.
"""

from django.db.models import Count
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.api.serializers import ChatMessageSerializer
from apps.core import chatbot
from apps.core.chat_commands import is_command
from apps.core.models import ChatMessage, ChatReadMark

_PAGE_MAX = 100
_PAGE_DEFAULT = 30

CHANNELS = [choice[0] for choice in ChatMessage.Channel.choices]


def _employee_or_none(request):
    from apps.api.views import employee_for_user

    return employee_for_user(request.user)


def _messages_queryset():
    return (
        ChatMessage.objects.select_related(
            "author",
            "task",
            "task__assignee",
            "task__created_by",
            "task__done_by",
            "task__template_item__template",
            "reply_to",
            "reply_to__author",
            "reply_to__task",
        )
        .annotate(reply_count_annotated=Count("replies"))
        # Explicit: the GROUP BY from annotate() can drop Meta.ordering.
        .order_by("-id")
    )


class StaffChatMessagesView(APIView):
    """GET: one channel's history, newest first, cursor by id (imitates the
    guest feed). POST: send text or a slash command."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        channel = request.query_params.get("channel", "")
        if channel not in CHANNELS:
            return Response(
                {"detail": f"channel must be one of {', '.join(CHANNELS)}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            limit = int(request.query_params.get("limit", _PAGE_DEFAULT))
        except (TypeError, ValueError):
            limit = _PAGE_DEFAULT
        limit = min(max(limit, 1), _PAGE_MAX)

        queryset = _messages_queryset().filter(channel=channel)
        cursor = request.query_params.get("cursor", "")
        if cursor.isdigit():
            queryset = queryset.filter(id__lt=int(cursor))
        page = list(queryset[: limit + 1])
        has_more = len(page) > limit
        page = page[:limit]

        return Response(
            {
                "messages": ChatMessageSerializer(page, many=True).data,
                "nextCursor": page[-1].pk if page and has_more else None,
                "hasMore": has_more,
            }
        )

    def post(self, request):
        employee = _employee_or_none(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        channel = request.data.get("channel", "")
        if channel not in CHANNELS:
            return Response(
                {"detail": f"channel must be one of {', '.join(CHANNELS)}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        body = (request.data.get("body") or "").strip()
        if not body:
            return Response(
                {"detail": "The message is empty."}, status=status.HTTP_400_BAD_REQUEST
            )
        reply_to = None
        reply_to_id = request.data.get("reply_to")
        if reply_to_id:
            reply_to = get_object_or_404(ChatMessage, pk=reply_to_id)
            if reply_to.channel != channel:
                return Response(
                    {"detail": "You can only reply within the same channel."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        if is_command(body):
            # The command itself appears as the author's message (Telegram
            # style), then the bot answers — result bubble or readable error.
            own = chatbot.post_message(
                channel=channel, body=body, author=employee, reply_to=reply_to
            )
            result = chatbot.handle_command(
                text=body, author=employee, channel=channel, reply_to=reply_to
            )
            return Response(
                {
                    "message": ChatMessageSerializer(own).data,
                    "result": ChatMessageSerializer(result).data,
                },
                status=status.HTTP_201_CREATED,
            )

        message = chatbot.post_message(
            channel=channel, body=body[:2000], author=employee, reply_to=reply_to
        )
        return Response(
            {"message": ChatMessageSerializer(message).data},
            status=status.HTTP_201_CREATED,
        )


class StaffChatThreadView(APIView):
    """A message and its replies, oldest first — the expanded thread."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        parent = get_object_or_404(_messages_queryset(), pk=pk)
        replies = _messages_queryset().filter(reply_to=parent).order_by("id")
        return Response(
            {
                "message": ChatMessageSerializer(parent).data,
                "replies": ChatMessageSerializer(replies, many=True).data,
            }
        )


class StaffChatReadView(APIView):
    """Unread badges: GET current counts, POST the high-water mark."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        employee = _employee_or_none(request)
        if employee is None:
            return Response({"unread": {}, "marks": {}})
        marks = {
            mark.channel: mark.last_read_message_id
            for mark in employee.chat_read_marks.all()
        }
        unread = {}
        for channel in CHANNELS:
            last_read = marks.get(channel, 0)
            unread[channel] = (
                ChatMessage.objects.filter(channel=channel, id__gt=last_read)
                .exclude(author=employee)
                .count()
            )
        return Response({"unread": unread, "marks": marks})

    def post(self, request):
        employee = _employee_or_none(request)
        if employee is None:
            return Response(
                {"detail": "This account has no staff profile."},
                status=status.HTTP_403_FORBIDDEN,
            )
        channel = request.data.get("channel", "")
        if channel not in CHANNELS:
            return Response(
                {"detail": f"channel must be one of {', '.join(CHANNELS)}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            last_read = int(request.data.get("last_read_message_id", 0))
        except (TypeError, ValueError):
            return Response(
                {"detail": "last_read_message_id must be a number."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        mark, _ = ChatReadMark.objects.get_or_create(
            employee=employee, channel=channel
        )
        # Monotonic: a stale tab can't roll the badge state backwards.
        if last_read > mark.last_read_message_id:
            mark.last_read_message_id = last_read
            mark.save(update_fields=["last_read_message_id", "updated_at"])
        return Response({"ok": True, "last_read_message_id": mark.last_read_message_id})
