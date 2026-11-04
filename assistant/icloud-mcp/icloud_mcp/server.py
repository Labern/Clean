"""iCloud connector: an MCP server Claude can use from any device.

Remote (phone/web/desktop):  ICLOUD_MCP_TOKEN=... icloud-mcp --http
  → add https://<host>/<token>/mcp in claude.ai → Settings → Connectors.
Local (Claude Code):         icloud-mcp            (stdio)
"""
from __future__ import annotations

import email
import email.policy
import os
import re
import sys

from mcp.server.fastmcp import FastMCP

from . import calendar as cal
from . import mail as M

INSTRUCTIONS = """\
You are the user's personal assistant with direct access to their iCloud Mail
and Calendar. The whole point: the user never has to read or write email
themselves. Work like a chief of staff, not a mail client.

Briefing
- Start with `daily_brief`. Report people, not messages: who wants what, by
  when, and what you recommend. One line each. Never paste raw email unless
  asked. Group: needs a decision from you / I can handle / waiting on others.
- Skip newsletters, receipts and notifications unless they contain a deadline,
  a payment problem or a security alert.

Acting
- When the user tells you what to do, write the email yourself in their voice:
  short, direct, polite, no filler, British English. Sign off with their first
  name only.
- Show the user the final text in one short block and send it on their word.
  If they have said "just send it" or "handle it", send without asking again.
- After sending, the reply is tracked automatically: `awaiting_replies` shows
  everyone who hasn't answered. Offer to chase anything older than 3 days.

Liaising
- When someone replies, summarise their answer in one line and propose the
  next move. Keep going back and forth until the thing is done.
- Never invent facts, commitments, prices or dates on the user's behalf. If
  the other person needs something only the user knows, ask the user one
  precise question.
"""

mcp = FastMCP("iCloud", instructions=INSTRUCTIONS)


def _cap(items, n):
    return items[: int(n)] if n else items


# ---------------- the assistant's core loop ----------------

@mcp.tool()
def daily_brief(days: int = 2, sent_days: int = 14, limit: int = 40) -> dict:
    """The daily scan. Returns: people waiting on the user (human mail with no
    reply yet), people the user is waiting on (sent mail with no answer), flagged
    items, and a count of automated mail skipped. Use this first, every time."""
    me = M.me()
    with M.imap() as c:
        inbound = M.search(c, "INBOX", since_days=days, limit=200)
        sent = M.search(c, "sent", since_days=max(sent_days, days), limit=300)
        # Inbound from the longer window too, so "awaiting" knows who answered.
        inbound_long = M.search(c, "INBOX", since_days=sent_days, limit=400, peek_bytes=4096)
        flagged = M.search(c, "INBOX", flagged_only=True, limit=20, peek_bytes=4096)
    return {
        "account": me,
        "needs_your_reply": _cap(M.needs_reply(inbound, sent, me), limit),
        "waiting_on_others": _cap(M.awaiting_reply(sent, inbound_long, me), limit),
        "flagged": [f.public() for f in flagged],
        "unread_total": sum(1 for m in inbound if m.unread),
        "automated_skipped": sum(1 for m in inbound if m.automated),
        "automated_subjects": [f"{m.sender_name or m.sender}: {m.subject}"
                               for m in inbound if m.automated][:30],
    }


@mcp.tool()
def awaiting_replies(days: int = 21) -> list[dict]:
    """Everything the user sent in the last N days that nobody has replied to:
    the chase list, with days_waiting per item."""
    me = M.me()
    with M.imap() as c:
        sent = M.search(c, "sent", since_days=days, limit=400, peek_bytes=4096)
        inbound = M.search(c, "INBOX", since_days=days, limit=600, peek_bytes=4096)
    return M.awaiting_reply(sent, inbound, me)


# ---------------- reading ----------------

@mcp.tool()
def search_mail(query: str = "", sender: str = "", to: str = "", subject: str = "",
                folder: str = "INBOX", since_days: int = 30, unread_only: bool = False,
                limit: int = 25) -> list[dict]:
    """Search a folder (INBOX, sent, archive, drafts, trash, junk or any folder
    name). `query` matches anywhere in the message. Results are newest first,
    each with folder+uid for read_email/reply."""
    with M.imap() as c:
        res = M.search(c, folder, query=query or None, sender=sender or None, to=to or None,
                       subject=subject or None, since_days=since_days or None,
                       unread_only=unread_only, limit=limit)
    return [r.public() for r in res]


@mcp.tool()
def read_email(folder: str, uid: str, include_quoted: bool = False, mark_read: bool = False) -> dict:
    """Full text of one email. Quoted history is stripped unless include_quoted."""
    with M.imap() as c:
        box, raw, flags = M.fetch_full(c, folder, uid)
        if mark_read:
            M.store_flags(c, box, [uid], "+FLAGS", "(\\Seen)")
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    s = M.summarise(box, uid, raw, flags)
    body = M.body_text(msg)
    return {**s.public(), "body": body if include_quoted else M.strip_quoted(body),
            "attachments": M.attachments(msg)}


@mcp.tool()
def conversation_with(person: str, days: int = 120, limit: int = 40) -> list[dict]:
    """Every email to or from a person (address or name fragment), both
    directions, oldest first: the whole relationship at a glance."""
    with M.imap() as c:
        got = M.search(c, "INBOX", sender=person, since_days=days, limit=limit)
        got += M.search(c, "sent", to=person, since_days=days, limit=limit)
        got += M.search(c, "archive", sender=person, since_days=days, limit=limit) \
            if "archive" in [x.lower() for x in M.folders(c)["all"]] else []
    seen, out = set(), []
    for m in sorted(got, key=lambda x: x.ts):
        if m.message_id in seen:
            continue
        seen.add(m.message_id)
        out.append(m.public())
    return out[-int(limit):]


@mcp.tool()
def list_folders() -> dict:
    """All mailbox folders and which one is Sent/Drafts/Archive/Trash/Junk."""
    with M.imap() as c:
        return M.folders(c)


# ---------------- acting ----------------

def _deliver(msg, save_sent: bool = True) -> dict:
    M.smtp_send(msg)
    saved = None
    if save_sent and os.environ.get("ICLOUD_SAVE_SENT", "1") != "0":
        with M.imap() as c:
            saved, _ = M.append(c, "sent", msg, "(\\Seen)")
    return {"sent": True, "to": msg["To"], "cc": msg.get("Cc"), "subject": msg["Subject"],
            "message_id": msg["Message-ID"], "saved_to": saved}


@mcp.tool()
def send_email(to: list[str], subject: str, body: str, cc: list[str] | None = None,
               bcc: list[str] | None = None) -> dict:
    """Send a new email from the user's iCloud address. Plain text body."""
    msg = M.build_message(M.me(), to, subject, body, cc=cc, bcc=bcc)
    return _deliver(msg)


@mcp.tool()
def reply(folder: str, uid: str, body: str, reply_all: bool = False,
          extra_cc: list[str] | None = None) -> dict:
    """Reply in-thread to an email (keeps Re:, In-Reply-To and References so it
    threads properly on the other side). Marks the original read."""
    me = M.me()
    with M.imap() as c:
        box, raw, flags = M.fetch_full(c, folder, uid)
        M.store_flags(c, box, [uid], "+FLAGS", "(\\Seen \\Answered)")
    orig = M.summarise(box, uid, raw, flags)
    msgobj = email.message_from_bytes(raw, policy=email.policy.default)
    reply_to = M._addr_list(msgobj.get("Reply-To")) or [orig.sender]
    to = [a for a in reply_to if a != me] or [orig.sender]
    cc = []
    if reply_all:
        cc = [a for a in orig.to + orig.cc if a != me and a not in to]
    cc += extra_cc or []
    msg = M.build_message(me, to, "", body, cc=cc or None, reply_to=orig)
    return _deliver(msg)


@mcp.tool()
def save_draft(to: list[str], subject: str, body: str, cc: list[str] | None = None) -> dict:
    """Put a draft in iCloud Drafts (visible in Mail on iPhone) without sending."""
    msg = M.build_message(M.me(), to, subject, body, cc=cc)
    with M.imap() as c:
        box, _ = M.append(c, "drafts", msg, "(\\Draft \\Seen)")
    return {"draft_saved": box, "subject": subject}


@mcp.tool()
def mark(folder: str, uids: list[str], action: str) -> dict:
    """action: read | unread | flag | unflag."""
    ops = {"read": ("+FLAGS", "(\\Seen)"), "unread": ("-FLAGS", "(\\Seen)"),
           "flag": ("+FLAGS", "(\\Flagged)"), "unflag": ("-FLAGS", "(\\Flagged)")}
    op, fl = ops[action]
    with M.imap() as c:
        M.store_flags(c, folder, uids, op, fl)
    return {"ok": True, "action": action, "count": len(uids)}


@mcp.tool()
def move_email(folder: str, uids: list[str], destination: str) -> dict:
    """Move to archive | trash | junk | any folder name."""
    with M.imap() as c:
        dest = M.move(c, folder, uids, destination)
    return {"moved": len(uids), "to": dest}


# ---------------- calendar ----------------

@mcp.tool()
def calendar_events(days_ahead: int = 7, days_back: int = 0, calendar: str = "") -> list[dict]:
    """iCloud Calendar events in a window around now."""
    return cal.events(days_ahead, days_back, calendar or None)


@mcp.tool()
def create_event(title: str, start: str, end: str, calendar: str = "",
                 location: str = "", notes: str = "") -> dict:
    """Create an iCloud Calendar event. start/end are ISO 8601 with offset,
    e.g. 2026-11-05T14:00:00+00:00."""
    return cal.create_event(title, start, end, calendar or None, location, notes)


# ---------------- entry point ----------------

def main():
    if "--http" not in sys.argv and not os.environ.get("PORT"):
        mcp.run()  # stdio
        return
    import uvicorn
    from starlette.responses import PlainTextResponse

    token = os.environ.get("ICLOUD_MCP_TOKEN", "").strip()
    if len(token) < 24 or not re.fullmatch(r"[A-Za-z0-9_-]+", token):
        sys.exit("Set ICLOUD_MCP_TOKEN to a long random string (≥24 chars, letters, "
                 "digits, - and _ only). It is the only thing standing between the "
                 "internet and your mailbox.")
    mcp.settings.host = "0.0.0.0"
    mcp.settings.port = int(os.environ.get("PORT", "8000"))
    mcp.settings.stateless_http = True
    mcp.settings.streamable_http_path = f"/{token}/mcp"

    @mcp.custom_route("/", methods=["GET"])
    async def health(_req):
        return PlainTextResponse("ok")

    uvicorn.run(mcp.streamable_http_app(), host="0.0.0.0", port=mcp.settings.port,
                proxy_headers=True, forwarded_allow_ips="*")


if __name__ == "__main__":
    main()
