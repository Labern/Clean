#!/usr/bin/env python3
"""Count the messages Labern sends to Claude and publish the counts.

PARADOX HQ's Work tab shows "Claude messages". There is no public API for that,
but every Claude Code and Claude desktop conversation on a machine is kept as a
transcript under ~/.claude/projects. This reads them, counts the messages he
typed (not tool results, not the system's own notes), and writes

    {"updated": "...",
     "sessions": [{"id": "4c98e031", "started": "...Z", "last": "...Z",
                   "hours": {"2026-11-18T01": 5, ...}}, ...],
     "days": [{"day": "2026-11-17", "messages": 212, "sessions": 9}, ...]}

Counts per session per hour (UTC), so the app can show an hour, a session, a
day, a week or a month in the phone's own time zone, and so the same session
reported from two places is only counted once. Only counts and times leave the
machine: no words from any conversation.

    claude_stats.py                          print the JSON
    claude_stats.py --publish --remote URL   (the Mac) push it as claude.json, the only
        file on the branch stats/claude. It uses a small repo of its own in
        ~/.paradox/stats, so it never touches a working checkout.
    claude_stats.py --out FILE --link URL    (a cloud session) merge this machine's
        sessions into FILE, which is committed with the work: paradox-hq/stats/cloud.json.
        URL is the conversation's own address, so the app can tell which changes it made.
        A cloud session's transcript only exists in its own container, so this is the
        only way its messages are ever counted.
"""
import argparse
import datetime
import glob
import json
import os
import subprocess
import sys

# Text the harness writes into the user's turn. None of it was typed by him.
NOT_TYPED = (
    "<system-reminder", "<command-", "<local-command", "<task-notification", "<user-prompt-submit-hook",
    "[SYSTEM NOTIFICATION", "Stop hook feedback", "This session's worker process was restarted",
    "Caveat: The messages below were generated", "[Request interrupted",
)


def typed(entry):
    """True when a transcript line is a message the person wrote."""
    if entry.get("type") != "user" or entry.get("isSidechain") or entry.get("isMeta") or entry.get("isCompactSummary"):
        return False
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        texts = [content]
    elif isinstance(content, list):
        if any(isinstance(part, dict) and part.get("type") == "tool_result" for part in content):
            return False
        texts = [part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text"]
    else:
        return False
    texts = [text.strip() for text in texts if text and text.strip()]
    return any(not text.startswith(NOT_TYPED) for text in texts)


def words(entry):
    """What was typed, for telling two records of one message apart from two messages."""
    content = entry.get("content") if entry.get("type") == "queue-operation" else (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        content = " ".join(part.get("text", "") for part in content if isinstance(part, dict) and part.get("type") == "text")
    return " ".join((content or "").split())[:160]


def queued(entry):
    """True when a transcript line records a message being queued for Claude."""
    if entry.get("type") != "queue-operation" or entry.get("operation") != "enqueue":
        return False
    content = entry.get("content")
    return isinstance(content, str) and bool(content.strip()) and not content.strip().startswith(NOT_TYPED)


def tally(lines):
    """The messages in one transcript, as (time, session) pairs.

    A message can be recorded twice: as a turn of its own, and as a queue record
    (always for one typed while Claude was still working, which may never get a
    turn of its own; in some versions for every message). Neither record alone is
    complete, so each distinct message is counted once: for the same words, the
    larger of the two counts.
    """
    turns, sent, seen = {}, {}, set()
    for line in lines:
        if '"user"' not in line and '"enqueue"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if queued(entry):
            kind = sent
        elif typed(entry):
            key = entry.get("uuid") or entry.get("timestamp")
            if key in seen:
                continue
            seen.add(key)
            kind = turns
        else:
            continue
        try:
            when = datetime.datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00"))
        except (KeyError, ValueError, AttributeError):
            continue
        kind.setdefault(words(entry), []).append((when, entry.get("sessionId")))
    counted = []
    for text in set(turns) | set(sent):
        a, b = turns.get(text, []), sent.get(text, [])
        counted += a if len(a) >= len(b) else b
    return counted


UTC = datetime.timezone.utc
STAMP = "%Y-%m-%dT%H:%M:%SZ"


def count(root, days=60, now=None):
    now = now or datetime.datetime.now().astimezone()
    first = (now - datetime.timedelta(days=days - 1)).date()
    sessions = {}
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        try:
            if datetime.date.fromtimestamp(os.path.getmtime(path)) < first:
                continue
            with open(path, encoding="utf-8", errors="replace") as handle:
                counted = tally(handle)
        except OSError:
            continue
        for when, session in counted:
            if when.astimezone().date() < first or when > now:
                continue
            name = (session or os.path.basename(path))[:8]
            held = sessions.setdefault(name, {"id": name, "started": when, "last": when, "hours": {}})
            held["started"] = min(held["started"], when)
            held["last"] = max(held["last"], when)
            hour = when.astimezone(UTC).strftime("%Y-%m-%dT%H")
            held["hours"][hour] = held["hours"].get(hour, 0) + 1
    return shaped(sessions.values(), now)


def shaped(sessions, now):
    """The file's shape, from sessions whose times are datetimes or already text."""
    listed, messages, people = [], {}, {}
    for session in sorted(sessions, key=lambda item: str(item["id"])):
        started, last = (when if isinstance(when, str) else when.astimezone(UTC).strftime(STAMP)
                         for when in (session["started"], session["last"]))
        entry = {"id": session["id"], "started": started, "last": last,
                 "hours": dict(sorted(session["hours"].items()))}
        if session.get("link"):
            entry["link"] = session["link"]
        listed.append(entry)
        for hour, amount in session["hours"].items():
            day = datetime.datetime.strptime(hour, "%Y-%m-%dT%H").replace(tzinfo=UTC).astimezone().date()
            messages[day] = messages.get(day, 0) + amount
            people.setdefault(day, set()).add(session["id"])
    return {
        "updated": now.astimezone(UTC).strftime(STAMP),
        "sessions": listed,
        "days": [{"day": day.isoformat(), "messages": messages[day], "sessions": len(people[day])}
                 for day in sorted(messages)],
    }


def merged(mine, path, now, days=60):
    """This machine's sessions laid over the ones already in `path`: a session
    here replaces the same session there, and ones gone quiet for `days` drop out."""
    held = {}
    try:
        with open(path, encoding="utf-8") as handle:
            held = {session["id"]: session for session in json.load(handle).get("sessions", [])}
    except (OSError, ValueError, KeyError, TypeError):
        pass
    held.update({session["id"]: session for session in mine["sessions"]})
    oldest = (now.astimezone(UTC) - datetime.timedelta(days=days)).strftime(STAMP)
    return shaped([session for session in held.values() if session["last"] >= oldest], now)


def git(*args, cwd, text=None):
    return subprocess.run(["git", *args], cwd=cwd, input=text, capture_output=True, text=True, check=True).stdout.strip()


def publish(data, remote, workdir):
    """Pushes claude.json as the one file of a one-commit branch."""
    os.makedirs(workdir, exist_ok=True)
    if not os.path.isdir(os.path.join(workdir, ".git")):
        git("init", "-q", cwd=workdir)
    blob = git("hash-object", "-w", "--stdin", cwd=workdir, text=json.dumps(data, indent=1) + "\n")
    tree = git("mktree", cwd=workdir, text=f"100644 blob {blob}\tclaude.json\n")
    env = ["-c", "user.name=claude-stats", "-c", "user.email=stats@users.noreply.github.com"]
    commit = git(*env, "commit-tree", tree, "-m", "Claude messages per day", cwd=workdir)
    git("push", "-q", "--force", remote, f"{commit}:refs/heads/stats/claude", cwd=workdir)
    return commit


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    parser.add_argument("--days", type=int, default=60)
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--remote", default="")
    parser.add_argument("--workdir", default=os.path.expanduser("~/.paradox/stats"))
    parser.add_argument("--out", default="", help="merge into this file instead of printing")
    parser.add_argument("--link", default="", help="this conversation's address in Claude (a cloud session knows its own)")
    args = parser.parse_args()
    now = datetime.datetime.now().astimezone()
    data = count(args.root, args.days, now)
    if args.link:
        # A cloud container holds one conversation: its changes carry this same address.
        for session in data["sessions"]:
            session["link"] = args.link
    total = sum(day["messages"] for day in data["days"])
    if args.out:
        data = merged(data, args.out, now, args.days)
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=1)
            handle.write("\n")
        print(f"wrote {args.out}: {len(data['sessions'])} sessions, {sum(d['messages'] for d in data['days'])} messages")
    elif args.publish:
        if not args.remote:
            sys.exit("--publish needs --remote (the Clean repo's push address)")
        commit = publish(data, args.remote, args.workdir)
        print(f"published {commit[:7]}: {total} messages over {len(data['days'])} days, {len(data['sessions'])} sessions")
    else:
        print(json.dumps(data, indent=1))


if __name__ == "__main__":
    main()
