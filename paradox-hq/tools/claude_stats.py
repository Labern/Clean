#!/usr/bin/env python3
"""Count the messages Labern sends to Claude, per day, and publish the count.

PARADOX HQ's Work tab shows "Claude messages". There is no public API for that,
but every Claude Code and Claude desktop conversation on this Mac is kept as a
transcript under ~/.claude/projects. This reads them, counts the messages he
typed (not tool results, not the system's own notes), and writes

    {"updated": "...", "days": [{"day": "2026-11-17", "messages": 212, "sessions": 9}, ...]}

Only the counts leave the Mac: no words from any conversation.

    claude_stats.py                       print the JSON
    claude_stats.py --publish --remote URL
        also push it as claude.json, the only file on the branch stats/claude,
        which the app reads. It uses a small repo of its own in ~/.paradox/stats,
        so it never touches a working checkout (or the Desktop folder, which a
        background job may not read).

Conversations that ran in the cloud are not on this Mac and are not counted.
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
    """The messages in one transcript, as (day, session) pairs.

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
            when = datetime.datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00")).astimezone()
        except (KeyError, ValueError, AttributeError):
            continue
        kind.setdefault(words(entry), []).append((when.date(), entry.get("sessionId")))
    counted = []
    for text in set(turns) | set(sent):
        a, b = turns.get(text, []), sent.get(text, [])
        counted += a if len(a) >= len(b) else b
    return counted


def count(root, days=60, now=None):
    now = now or datetime.datetime.now().astimezone()
    first = (now - datetime.timedelta(days=days - 1)).date()
    messages, sessions = {}, {}
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        try:
            if datetime.date.fromtimestamp(os.path.getmtime(path)) < first:
                continue
            with open(path, encoding="utf-8", errors="replace") as handle:
                counted = tally(handle)
        except OSError:
            continue
        for day, session in counted:
            if day < first or day > now.date():
                continue
            messages[day] = messages.get(day, 0) + 1
            sessions.setdefault(day, set()).add(session or path)
    return {
        "updated": now.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "days": [{"day": day.isoformat(), "messages": messages[day], "sessions": len(sessions[day])}
                 for day in sorted(messages)],
    }


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
    args = parser.parse_args()
    data = count(args.root, args.days)
    if args.publish:
        if not args.remote:
            sys.exit("--publish needs --remote (the Clean repo's push address)")
        commit = publish(data, args.remote, args.workdir)
        total = sum(day["messages"] for day in data["days"])
        print(f"published {commit[:7]}: {total} messages over {len(data['days'])} days")
    else:
        print(json.dumps(data, indent=1))


if __name__ == "__main__":
    main()
