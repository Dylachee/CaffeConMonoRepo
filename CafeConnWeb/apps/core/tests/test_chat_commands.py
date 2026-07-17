from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from django.test import SimpleTestCase

from apps.core.chat_commands import (
    CommandError,
    EmployeeRef,
    is_command,
    parse_command,
    parse_when,
)

TZ = ZoneInfo("Europe/Rome")
NOW = datetime(2026, 7, 17, 15, 0, tzinfo=TZ)

STAFF = [
    EmployeeRef(id=1, name="Tony Espresso", username="tony"),
    EmployeeRef(id=2, name="Alina Rossi", username="alina"),
    EmployeeRef(id=3, name="Alessandro Bianchi", username="ale"),
]


def parse(text: str):
    return parse_command(text, employees=STAFF, now=NOW)


class ParseWhenTests(SimpleTestCase):
    def test_future_time_today(self):
        due, rest = parse_when("clean fryer 21:30", now=NOW)
        self.assertEqual(rest, "clean fryer")
        self.assertEqual((due.hour, due.minute, due.date()), (21, 30, NOW.date()))

    def test_past_time_rolls_to_tomorrow(self):
        due, _ = parse_when("check stock 09:00", now=NOW)  # 9:00 already passed
        self.assertEqual(due.date(), NOW.date() + timedelta(days=1))

    def test_explicit_tomorrow(self):
        due, rest = parse_when("order flour tomorrow 10:00", now=NOW)
        self.assertEqual(rest, "order flour")
        self.assertEqual(due.date(), NOW.date() + timedelta(days=1))
        self.assertEqual(due.hour, 10)

    def test_bare_tomorrow_defaults_to_ten(self):
        due, rest = parse_when("call supplier tomorrow", now=NOW)
        self.assertEqual(rest, "call supplier")
        self.assertEqual((due.date(), due.hour), (NOW.date() + timedelta(days=1), 10))

    def test_invalid_time_is_a_human_error(self):
        with self.assertRaises(CommandError):
            parse_when("x 25:99", now=NOW)

    def test_no_time_returns_none(self):
        due, rest = parse_when("just a title", now=NOW)
        self.assertIsNone(due)
        self.assertEqual(rest, "just a title")


class TaskCommandTests(SimpleTestCase):
    def test_plain_task(self):
        parsed = parse("/task wipe the terrace tables")
        self.assertEqual(parsed.name, "task")
        self.assertEqual(parsed.title, "wipe the terrace tables")
        self.assertIsNone(parsed.assignee)
        self.assertIsNone(parsed.due_at)

    def test_task_with_mention_and_time(self):
        parsed = parse("/task clean the fryer @tony 21:30")
        self.assertEqual(parsed.title, "clean the fryer")
        self.assertEqual(parsed.assignee.id, 1)
        self.assertEqual(parsed.due_at.hour, 21)

    def test_mention_by_first_name_prefix(self):
        parsed = parse("/task restock napkins @alina")
        self.assertEqual(parsed.assignee.id, 2)

    def test_ambiguous_mention_is_an_error_with_names(self):
        with self.assertRaises(CommandError) as ctx:
            parse("/task something @al")  # Alina vs Alessandro
        self.assertIn("ambiguous", str(ctx.exception))

    def test_unknown_mention(self):
        with self.assertRaises(CommandError):
            parse("/task something @nobody")

    def test_missing_title(self):
        with self.assertRaises(CommandError):
            parse("/task @tony 21:30")

    def test_empty_task(self):
        with self.assertRaises(CommandError):
            parse("/task")


class OtherCommandTests(SimpleTestCase):
    def test_remind_time_first(self):
        parsed = parse("/remind 21:30 take out the bins")
        self.assertEqual(parsed.name, "remind")
        self.assertEqual(parsed.title, "take out the bins")
        self.assertEqual(parsed.due_at.hour, 21)

    def test_remind_time_last_also_accepted(self):
        parsed = parse("/remind take out the bins 21:30")
        self.assertEqual(parsed.title, "take out the bins")
        self.assertEqual(parsed.due_at.minute, 30)

    def test_remind_without_time_is_an_error(self):
        with self.assertRaises(CommandError):
            parse("/remind do the thing")

    def test_bare_commands(self):
        for name in ("done", "open", "close"):
            with self.subTest(name=name):
                self.assertEqual(parse(f"/{name}").name, name)

    def test_unknown_command_lists_known_ones(self):
        with self.assertRaises(CommandError) as ctx:
            parse("/frobnicate now")
        self.assertIn("/task", str(ctx.exception))

    def test_is_command(self):
        self.assertTrue(is_command("  /task x"))
        self.assertFalse(is_command("hello /task"))
