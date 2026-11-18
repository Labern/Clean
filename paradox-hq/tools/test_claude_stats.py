#!/usr/bin/env python3
"""python3 paradox-hq/tools/test_claude_stats.py"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claude_stats as stats  # noqa: E402


def turn(text, time, uuid, **extra):
    return json.dumps({"type": "user", "uuid": uuid, "sessionId": "s", "timestamp": time,
                       "message": {"role": "user", "content": text}, **extra})


def queue(text, time):
    return json.dumps({"type": "queue-operation", "operation": "enqueue", "sessionId": "s", "timestamp": time, "content": text})


def result(time, uuid):
    return json.dumps({"type": "user", "uuid": uuid, "sessionId": "s", "timestamp": time,
                       "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}})


T = "2026-11-17T10:0%d:00.000Z"

# Most messages are turns of their own; only ones typed mid-work are queued. A
# transcript with one queue record must not be counted as one message.
mostly_turns = [turn("first", T % 0, "a"), result(T % 1, "b"), turn("second", T % 2, "c"),
                queue("typed while busy", T % 3), turn("third", T % 4, "d")]
assert len(stats.tally(mostly_turns)) == 4, stats.tally(mostly_turns)

# A message recorded both ways is one message.
both = [queue("hello there", T % 0), turn("hello there", T % 1, "a"), queue("again", T % 2), turn("again", T % 3, "b")]
assert len(stats.tally(both)) == 2

# The same words sent twice are two messages.
twice = [turn("continue", T % 0, "a"), turn("continue", T % 5, "b"), queue("continue", T % 5)]
assert len(stats.tally(twice)) == 2

# What the harness writes is not his: tool results, reminders, notifications, side chains.
noise = [result(T % 0, "a"), turn("<system-reminder>x</system-reminder>", T % 1, "b"),
         turn("[SYSTEM NOTIFICATION - NOT USER INPUT]", T % 2, "c"), queue("<task-notification>x", T % 3),
         turn("in a sub-agent", T % 4, "d", isSidechain=True), turn("meta", T % 5, "e", isMeta=True),
         turn("real", T % 6, "f")]
assert len(stats.tally(noise)) == 1

# The same turn written twice in a file is counted once.
assert len(stats.tally([turn("x", T % 0, "a"), turn("x", T % 0, "a")])) == 1
# Counts are kept per session per UTC hour, with when the session began and was last used.
import datetime  # noqa: E402
import tempfile  # noqa: E402

folder = tempfile.mkdtemp()
with open(os.path.join(folder, "one.jsonl"), "w") as handle:
    handle.write("\n".join([turn("a", "2026-11-17T10:05:00.000Z", "a"), turn("b", "2026-11-17T10:40:00.000Z", "b"),
                            turn("c", "2026-11-17T12:01:00.000Z", "c")]))
now = datetime.datetime(2026, 11, 17, 13, 0, tzinfo=datetime.timezone.utc)
data = stats.count(folder, 60, now)
assert data["sessions"] == [{"id": "s", "started": "2026-11-17T10:05:00Z", "last": "2026-11-17T12:01:00Z",
                             "hours": {"2026-11-17T10": 2, "2026-11-17T12": 1}}], data["sessions"]
assert sum(day["messages"] for day in data["days"]) == 3

# Merging into a shared file: the same session is replaced, another is kept, a stale one goes.
shared = os.path.join(folder, "cloud.json")
json.dump({"sessions": [
    {"id": "s", "started": "2026-11-17T10:05:00Z", "last": "2026-11-17T10:05:00Z", "hours": {"2026-11-17T10": 1}},
    {"id": "other", "started": "2026-11-16T09:00:00Z", "last": "2026-11-16T09:30:00Z", "hours": {"2026-11-16T09": 4}},
    {"id": "old", "started": "2026-01-01T09:00:00Z", "last": "2026-01-01T09:30:00Z", "hours": {"2026-01-01T09": 9}},
]}, open(shared, "w"))
both = stats.merged(data, shared, now)
assert [session["id"] for session in both["sessions"]] == ["other", "s"], both["sessions"]
assert sum(day["messages"] for day in both["days"]) == 7
print("claude_stats: 7 checks pass")
