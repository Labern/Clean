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


def queued(entry):
    """True when a transcript line records a message being sent (newer transcripts log every one)."""
    if entry.get("type") != "queue-operation" or entry.get("operation") != "enqueue":
        return False
    content = entry.get("content")
    return isinstance(content, str) and bool(content.strip()) and not content.strip().startswith(NOT_TYPED)


def count(root, days=60, now=None):
    now = now or datetime.datetime.now().astimezone()
    first = (now - datetime.timedelta(days=days - 1)).date()
    messages, sessions = {}, {}
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        try:
            if datetime.date.fromtimestamp(os.path.getmtime(path)) < first:
                continue
            handle = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        # Two ways a message shows up. Newer transcripts log each one as it is
        # sent, including those sent while Claude is still working; older ones
        # only have the turn itself. A file is counted one way, never both.
        sent, turns, seen = [], [], set()
        with handle:
            for line in handle:
                if '"user"' not in line and '"enqueue"' not in line:
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if queued(entry):
                    bucket = sent
                elif typed(entry):
                    key = entry.get("uuid") or entry.get("timestamp")
                    if key in seen:
                        continue
                    seen.add(key)
                    bucket = turns
                else:
                    continue
                try:
                    when = datetime.datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00")).astimezone()
                except (KeyError, ValueError, AttributeError):
                    continue
                bucket.append((when.date(), entry.get("sessionId") or path))
        for day, session in (sent or turns):
            if day < first or day > now.date():
                continue
            messages[day] = messages.get(day, 0) + 1
            sessions.setdefault(day, set()).add(session)
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
