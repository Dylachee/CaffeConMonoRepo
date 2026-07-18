"""Slash-command parser for the staff chat bot.

Pure parsing only — no database access, no side effects — so every rule is
unit-testable in isolation. apps.core.chatbot applies the parsed result.

Grammar (Telegram-style, forgiving):

    /task <title> [@name] [21:30 | today 18:00 | tomorrow 10:00]
    /remind <21:30 | tomorrow 10:00> <text>
    /done                (as a thread reply to a task bubble)
    /open                (bot lists today's open tasks)
    /close               (bot posts the closing checklist now)

`@name` matches employee names/usernames case-insensitively by prefix.
Malformed input raises CommandError with a bilingual, human-readable message
— the bot replies with it, never with silence.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime, time, timedelta

KNOWN_COMMANDS = ("task", "remind", "done", "open", "close")


class CommandError(Exception):
    """Human-readable (EN · IT) parse failure — the bot posts str(error)."""


@dataclass
class EmployeeRef:
    """The minimum the parser needs to know about a person."""

    id: int
    name: str
    username: str = ""


@dataclass
class ParsedCommand:
    name: str  # one of KNOWN_COMMANDS
    title: str = ""  # /task title or /remind text
    assignee: EmployeeRef | None = None
    due_at: datetime | None = None
    mentions: list[EmployeeRef] = field(default_factory=list)


_TIME_RE = re.compile(
    r"(?:\b(today|tomorrow|oggi|domani)\s+)?\b(\d{1,2}):(\d{2})\b\s*$",
    re.IGNORECASE,
)
_DAY_ONLY_RE = re.compile(r"\b(tomorrow|domani)\s*$", re.IGNORECASE)
_MENTION_RE = re.compile(r"@([\w.\-]+)")


def is_command(text: str) -> bool:
    return text.strip().startswith("/")


def resolve_mention(handle: str, employees: list[EmployeeRef]) -> EmployeeRef:
    """Case-insensitive prefix match on name or username. Ambiguity and
    misses are errors the person can act on."""
    needle = handle.lower()
    matches = [
        employee
        for employee in employees
        if employee.name.lower().startswith(needle)
        or (employee.username and employee.username.lower().startswith(needle))
        or any(part.lower().startswith(needle) for part in employee.name.split())
    ]
    # Exact match wins over prefix collisions ("ann" vs "anna").
    exact = [
        e for e in matches
        if e.name.lower() == needle or e.username.lower() == needle
    ]
    if exact:
        return exact[0]
    if not matches:
        raise CommandError(
            f"I don't know anyone called @{handle}. · Non conosco nessun @{handle}."
        )
    if len({e.id for e in matches}) > 1:
        names = ", ".join(sorted({e.name for e in matches})[:4])
        raise CommandError(
            f"@{handle} is ambiguous ({names}) — type more letters. · "
            f"@{handle} è ambiguo ({names}) — scrivi qualche lettera in più."
        )
    return matches[0]


def parse_when(text: str, *, now: datetime) -> tuple[datetime | None, str]:
    """Pull a trailing time expression off `text`. Returns (due_at, rest).

    "21:30" → today at 21:30, or tomorrow if that moment already passed;
    "today 18:00" / "tomorrow 10:00" pin the day explicitly; a bare
    "tomorrow" means tomorrow 10:00. `now` must be venue-local time.
    """
    match = _TIME_RE.search(text)
    if match:
        day_word, hours_text, minutes_text = match.groups()
        hours, minutes = int(hours_text), int(minutes_text)
        if hours > 23 or minutes > 59:
            raise CommandError(
                f"{hours_text}:{minutes_text} is not a valid time. · "
                f"{hours_text}:{minutes_text} non è un orario valido."
            )
        day = now.date()
        if day_word and day_word.lower() in ("tomorrow", "domani"):
            day += timedelta(days=1)
        due = datetime.combine(day, time(hours, minutes), tzinfo=now.tzinfo)
        if day_word is None and due <= now:
            due += timedelta(days=1)  # "21:30" said at 22:00 means tomorrow
        return due, text[: match.start()].strip()

    day_match = _DAY_ONLY_RE.search(text)
    if day_match:
        due = datetime.combine(
            now.date() + timedelta(days=1), time(10, 0), tzinfo=now.tzinfo
        )
        return due, text[: day_match.start()].strip()
    return None, text.strip()


def parse_command(
    text: str,
    *,
    employees: list[EmployeeRef],
    now: datetime,
) -> ParsedCommand:
    """Parse one slash command. Raises CommandError for anything a human
    should be told about; unknown commands are errors too (with the list)."""
    stripped = text.strip()
    if not stripped.startswith("/"):
        raise CommandError("Commands start with /. · I comandi iniziano con /.")

    head, _, rest = stripped[1:].partition(" ")
    name = head.lower()
    rest = rest.strip()

    if name not in KNOWN_COMMANDS:
        known = ", ".join(f"/{c}" for c in KNOWN_COMMANDS)
        raise CommandError(
            f"Unknown command /{head}. I know: {known}. · "
            f"Comando /{head} sconosciuto. Conosco: {known}."
        )

    if name in ("done", "open", "close"):
        return ParsedCommand(name=name)

    if name == "remind":
        due, remaining = parse_when(rest, now=now)
        if due is None:
            # /remind wants the time FIRST: "/remind 21:30 close the terrace".
            leading = re.match(
                r"^(?:(today|tomorrow|oggi|domani)\s+)?(\d{1,2}):(\d{2})\s+(.+)$",
                rest,
                re.IGNORECASE,
            )
            if leading:
                day_word, hours_text, minutes_text, tail = leading.groups()
                due, _ = parse_when(
                    f"{day_word or ''} {hours_text}:{minutes_text}".strip(), now=now
                )
                remaining = tail.strip()
        if due is None or not remaining:
            raise CommandError(
                "Use: /remind 21:30 take out the bins. · "
                "Usa: /remind 21:30 porta fuori i rifiuti."
            )
        return ParsedCommand(name=name, title=remaining[:300], due_at=due)

    # ---- /task -------------------------------------------------------------
    if not rest:
        raise CommandError(
            "Use: /task title @name 21:30 (name and time optional). · "
            "Usa: /task titolo @nome 21:30 (nome e orario facoltativi)."
        )
    due, remaining = parse_when(rest, now=now)

    assignee: EmployeeRef | None = None
    mentions: list[EmployeeRef] = []
    for handle in _MENTION_RE.findall(remaining):
        resolved = resolve_mention(handle, employees)
        mentions.append(resolved)
        assignee = assignee or resolved  # first mention is the assignee
    title = _MENTION_RE.sub("", remaining).strip()
    title = re.sub(r"\s{2,}", " ", title)
    if not title:
        raise CommandError(
            "The task needs a title. · Il compito ha bisogno di un titolo."
        )
    return ParsedCommand(
        name="task",
        title=title[:200],
        assignee=assignee,
        due_at=due,
        mentions=mentions,
    )
