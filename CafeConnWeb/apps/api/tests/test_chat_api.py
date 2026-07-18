from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from apps.core import chatbot
from apps.core.models import ChatMessage, Employee, StaffTask

User = get_user_model()


def make_client(username: str, role: str = Employee.Role.WAITER, **flags):
    username = f"tstch-{username}"
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    employee = Employee.objects.create(user=user, name=username, role=role, **flags)
    token, _ = Token.objects.get_or_create(user=user)
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
    return client, employee


def send(client, body, channel="general", reply_to=None):
    payload = {"channel": channel, "body": body}
    if reply_to is not None:
        payload["reply_to"] = reply_to
    return client.post("/api/staff/chat/messages/", payload, format="json")


class ChatMessagesApiTests(TestCase):
    def setUp(self):
        self.client_w, self.waiter = make_client("w1")
        self.client_m, self.manager = make_client("m1", role=Employee.Role.MANAGER)

    def test_history_survives_reload_and_paginates_by_cursor(self):
        for i in range(35):
            send(self.client_w, f"message {i}")
        first = self.client_w.get(
            "/api/staff/chat/messages/?channel=general&limit=30"
        ).json()
        self.assertEqual(len(first["messages"]), 30)
        self.assertTrue(first["hasMore"])
        self.assertEqual(first["messages"][0]["body"], "message 34")  # newest first

        second = self.client_w.get(
            f"/api/staff/chat/messages/?channel=general&limit=30&cursor={first['nextCursor']}"
        ).json()
        self.assertEqual(len(second["messages"]), 5)
        self.assertFalse(second["hasMore"])
        ids_first = {m["id"] for m in first["messages"]}
        ids_second = {m["id"] for m in second["messages"]}
        self.assertFalse(ids_first & ids_second)

    def test_channels_are_isolated_and_capability_gated(self):
        self.assertEqual(
            send(self.client_w, "kitchen note", channel="kitchen").status_code,
            403,
        )
        self.assertEqual(
            send(self.client_w, "floor note", channel="floor").status_code,
            201,
        )
        send(self.client_m, "kitchen note", channel="kitchen")
        general = self.client_w.get(
            "/api/staff/chat/messages/?channel=general"
        ).json()["messages"]
        self.assertFalse(any(m["body"] == "kitchen note" for m in general))
        bad = self.client_w.get("/api/staff/chat/messages/?channel=nope")
        self.assertEqual(bad.status_code, 400)

    def test_unavailable_channels_do_not_leak_through_reads(self):
        send(self.client_m, "station secret", channel="kitchen")
        self.assertEqual(
            self.client_w.get("/api/staff/chat/messages/?channel=kitchen").status_code,
            403,
        )
        unread = self.client_w.get("/api/staff/chat/read/").json()["unread"]
        self.assertNotIn("kitchen", unread)

    def test_reply_threads_with_preview_and_count(self):
        parent_id = send(self.client_w, "who takes table 5?").json()["message"]["id"]
        send(self.client_m, "I do", reply_to=parent_id)
        send(self.client_w, "thanks!", reply_to=parent_id)

        listing = self.client_w.get(
            "/api/staff/chat/messages/?channel=general"
        ).json()["messages"]
        parent = next(m for m in listing if m["id"] == parent_id)
        self.assertEqual(parent["reply_count"], 2)
        reply = next(m for m in listing if m["body"] == "I do")
        self.assertEqual(reply["reply_preview"]["id"], parent_id)
        self.assertIn("who takes", reply["reply_preview"]["body"])

        thread = self.client_w.get(f"/api/staff/chat/thread/{parent_id}/").json()
        self.assertEqual(len(thread["replies"]), 2)
        self.assertEqual(thread["replies"][0]["body"], "I do")  # oldest first

    def test_slash_command_posts_own_message_and_live_task_bubble(self):
        response = send(self.client_m, "/task wipe terrace @tstch-w1 21:30")
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(body["message"]["body"], "/task wipe terrace @tstch-w1 21:30")
        self.assertEqual(body["result"]["kind"], "task")
        task = body["result"]["task"]
        self.assertEqual(task["title"], "wipe terrace")
        self.assertEqual(task["assignee_name"], "tstch-w1")
        self.assertEqual(StaffTask.objects.count(), 1)

    def test_malformed_command_returns_readable_bot_reply(self):
        body = send(self.client_w, "/task").json()
        self.assertEqual(body["result"]["kind"], "system")
        self.assertTrue(body["result"]["body"])

    def test_unread_badges_and_monotonic_marks(self):
        first_id = send(self.client_m, "hello floor").json()["message"]["id"]
        second_id = send(self.client_m, "one more").json()["message"]["id"]

        unread = self.client_w.get("/api/staff/chat/read/").json()["unread"]
        self.assertEqual(unread["general"], 2)
        # Own messages never count as unread for their author.
        self.assertEqual(
            self.client_m.get("/api/staff/chat/read/").json()["unread"]["general"], 0
        )

        self.client_w.post(
            "/api/staff/chat/read/",
            {"channel": "general", "last_read_message_id": second_id},
            format="json",
        )
        self.assertEqual(
            self.client_w.get("/api/staff/chat/read/").json()["unread"]["general"], 0
        )
        # A stale tab posting an older mark cannot roll the badge back.
        self.client_w.post(
            "/api/staff/chat/read/",
            {"channel": "general", "last_read_message_id": first_id},
            format="json",
        )
        marks = self.client_w.get("/api/staff/chat/read/").json()["marks"]
        self.assertEqual(marks["general"], second_id)


class TasksApiTests(TestCase):
    def setUp(self):
        self.client_w, self.waiter = make_client("tw")
        self.client_m, self.manager = make_client("tm", role=Employee.Role.MANAGER)

    def test_quick_add_uses_task_syntax_and_posts_bubble(self):
        response = self.client_m.post(
            "/api/staff/tasks/",
            {"input": "restock oat milk @tstch-tw 18:00"},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        task = response.json()["task"]
        self.assertEqual(task["title"], "restock oat milk")
        self.assertEqual(task["assignee_name"], "tstch-tw")
        self.assertEqual(task["source"], "planner")
        # The bubble landed in general — single source of truth.
        bubble = ChatMessage.objects.get(kind=ChatMessage.Kind.TASK)
        self.assertEqual(bubble.task_id, task["id"])
        self.assertEqual(bubble.channel, ChatMessage.Channel.GENERAL)

    def test_waiter_cannot_assign_others_or_create_rules_or_edit(self):
        refused = self.client_w.post(
            "/api/staff/tasks/", {"input": "polish @tstch-tm"}, format="json"
        )
        self.assertEqual(refused.status_code, 403)

        rule = self.client_w.post(
            "/api/staff/tasks/",
            {"title": "daily sweep", "recurrence": "daily"},
            format="json",
        )
        self.assertEqual(rule.status_code, 403)

        task = StaffTask.objects.create(title="x", assignee=self.waiter)
        edit = self.client_w.patch(
            f"/api/staff/tasks/{task.pk}/", {"title": "y"}, format="json"
        )
        self.assertEqual(edit.status_code, 403)

    def test_waiter_quick_add_defaults_to_self_manager_leaves_open(self):
        waiter_task = self.client_w.post(
            "/api/staff/tasks/", {"input": "check napkins"}, format="json"
        ).json()["task"]
        self.assertEqual(waiter_task["assignee_name"], "tstch-tw")

        manager_task = self.client_m.post(
            "/api/staff/tasks/", {"input": "water the plants"}, format="json"
        ).json()["task"]
        self.assertEqual(manager_task["assignee_name"], "")

    def test_done_matrix_and_thread(self):
        other, other_emp = make_client("other")
        mine = StaffTask.objects.create(title="mine", assignee=self.waiter)
        theirs = StaffTask.objects.create(title="theirs", assignee=other_emp)
        free = StaffTask.objects.create(title="free")
        chatbot.post_task_bubble(mine)

        self.assertEqual(
            self.client_w.post(f"/api/staff/tasks/{mine.pk}/done/", {}, format="json").status_code,
            200,
        )
        blocked = self.client_w.post(f"/api/staff/tasks/{theirs.pk}/done/", {}, format="json")
        self.assertEqual(blocked.status_code, 403)
        self.assertTrue(blocked.json()["detail"])
        self.assertEqual(
            self.client_w.post(f"/api/staff/tasks/{free.pk}/done/", {}, format="json").status_code,
            403,
        )
        self.assertEqual(
            self.client_w.post(f"/api/staff/tasks/{free.pk}/take/", {}, format="json").status_code,
            200,
        )
        self.assertEqual(
            self.client_w.post(f"/api/staff/tasks/{free.pk}/done/", {}, format="json").status_code,
            200,
        )
        # Managers still preserve task ownership; reassignment is explicit.
        self.assertEqual(
            self.client_m.post(f"/api/staff/tasks/{theirs.pk}/done/", {}, format="json").status_code,
            403,
        )

        thread = self.client_m.get(f"/api/staff/tasks/{mine.pk}/thread/").json()
        self.assertEqual(thread["message"]["task"]["id"], mine.pk)
        self.assertEqual(thread["message"]["task"]["status"], "done")

    def test_day_view_buckets_and_rules_for_manage_only(self):
        StaffTask.objects.create(title="open today", assignee=self.waiter)
        rule = StaffTask.objects.create(
            title="rule", recurrence=StaffTask.Recurrence.DAILY
        )
        waiter_view = self.client_w.get("/api/staff/tasks/").json()
        self.assertTrue(any(t["title"] == "open today" for t in waiter_view["tasks"]))
        self.assertFalse(any(t["id"] == rule.pk for t in waiter_view["tasks"]))
        self.assertEqual(waiter_view["rules"], [])

        manager_view = self.client_m.get("/api/staff/tasks/").json()
        self.assertTrue(any(r["id"] == rule.pk for r in manager_view["rules"]))

    def test_regular_staff_only_receive_mine_available_and_own_done(self):
        _, other = make_client("hidden")
        StaffTask.objects.create(title="other active", assignee=other, status="in_progress")
        StaffTask.objects.create(title="available", status="available")
        StaffTask.objects.create(
            title="other done", assignee=other, done_by=other, status="done",
            done_at=timezone.now(),
        )
        StaffTask.objects.create(
            title="my done", assignee=self.waiter, done_by=self.waiter, status="done",
            done_at=timezone.now(),
        )
        titles = {task["title"] for task in self.client_w.get("/api/staff/tasks/").json()["tasks"]}
        self.assertEqual(titles, {"available", "my done"})

    def test_manager_reassignment_is_audited_and_cancelled_is_in_history(self):
        from apps.core.models import TaskEvent

        _, other = make_client("reassigned")
        task = StaffTask.objects.create(
            title="move me", assignee=self.waiter, status="in_progress"
        )
        response = self.client_m.patch(
            f"/api/staff/tasks/{task.pk}/", {"assignee": other.pk}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        event = TaskEvent.objects.get(task=task, action=TaskEvent.Action.REASSIGNED)
        self.assertIn("tstch-tw", event.detail)
        self.assertIn("tstch-reassigned", event.detail)

        self.client_m.delete(f"/api/staff/tasks/{task.pk}/")
        payload = self.client_m.get("/api/staff/tasks/").json()
        self.assertIn(task.pk, {item["id"] for item in payload["cancelled"]})

    def test_overdue_nudge_flow_reply_lands_in_thread(self):
        # The full B2 story: task bubble -> bot nudge as reply -> assignee answers.
        import datetime

        from django.utils import timezone

        bubble = chatbot.handle_command(
            text="/task descale machine @tstch-tw",
            author=self.manager,
            channel=ChatMessage.Channel.GENERAL,
        )
        task = bubble.task
        task.due_at = timezone.now() - datetime.timedelta(hours=1)
        task.save(update_fields=["due_at"])
        chatbot.run_due_bot_jobs()

        answer = send(
            self.client_w, "fryer was broken, doing it now", reply_to=bubble.pk
        )
        self.assertEqual(answer.status_code, 201)

        thread = self.client_m.get(f"/api/staff/tasks/{task.pk}/thread/").json()
        bodies = [r["body"] for r in thread["replies"]]
        self.assertTrue(any("due" in b for b in bodies))  # the bot nudge
        self.assertIn("fryer was broken, doing it now", bodies)  # the answer
