"""iCloud Mail over IMAP (read) and SMTP (send).

iCloud specifics, all verified against Apple's published settings:
  IMAP  imap.mail.me.com:993  SSL
  SMTP  smtp.mail.me.com:587  STARTTLS
  Auth  full iCloud address + an app-specific password (appleid.apple.com).
Folder names are discovered via SPECIAL-USE flags; iCloud's defaults are
"Sent Messages", "Drafts", "Archive", "Deleted Messages", "Junk".

A fresh connection per call: iCloud drops idle IMAP sessions aggressively and
a hosted connector is stateless anyway.
"""
from __future__ import annotations

import email
import email.policy
import html
import imaplib
import os
import re
import smtplib
import time
from contextlib import contextmanager
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import getaddresses, make_msgid, formatdate, parsedate_to_datetime, parseaddr

IMAP_HOST = os.environ.get("ICLOUD_IMAP_HOST", "imap.mail.me.com")
IMAP_PORT = int(os.environ.get("ICLOUD_IMAP_PORT", "993"))
SMTP_HOST = os.environ.get("ICLOUD_SMTP_HOST", "smtp.mail.me.com")
SMTP_PORT = int(os.environ.get("ICLOUD_SMTP_PORT", "587"))

FALLBACK_FOLDERS = {
    "sent": "Sent Messages",
    "drafts": "Drafts",
    "archive": "Archive",
    "trash": "Deleted Messages",
    "junk": "Junk",
}
SPECIAL_USE = {"\\Sent": "sent", "\\Drafts": "drafts", "\\Archive": "archive",
               "\\Trash": "trash", "\\Junk": "junk"}

# Senders that are machines, not people: never "needs your reply".
AUTOMATED = re.compile(
    r"(no-?reply|do-?not-?reply|notifications?|mailer-daemon|bounce|newsletter|"
    r"updates?@|news@|info@|marketing|alerts?@|support@.*zendesk|@email\.|@mail\.|@e\.)",
    re.I,
)


def _creds() -> tuple[str, str]:
    user = os.environ.get("ICLOUD_EMAIL", "").strip()
    pw = os.environ.get("ICLOUD_APP_PASSWORD", "").strip().replace(" ", "")
    if not user or not pw:
        raise RuntimeError(
            "ICLOUD_EMAIL and ICLOUD_APP_PASSWORD must be set. Create an "
            "app-specific password at appleid.apple.com → Sign-In and Security."
        )
    return user, pw


def me() -> str:
    return _creds()[0].lower()


# ---------- parsing (pure, unit-tested) ----------

@dataclass
class Summary:
    folder: str
    uid: str
    date: str
    sender: str
    sender_name: str
    to: list[str]
    cc: list[str]
    subject: str
    message_id: str
    in_reply_to: str
    references: str
    unread: bool
    flagged: bool
    automated: bool
    snippet: str = ""
    ts: float = 0.0

    def public(self) -> dict:
        d = asdict(self)
        d.pop("ts", None)
        d.pop("references", None)
        return d


def _addr_list(v) -> list[str]:
    return [a.lower() for _, a in getaddresses([str(v)] if v else []) if a]


def _date(msg) -> tuple[str, float]:
    raw = msg.get("Date")
    try:
        dt = parsedate_to_datetime(str(raw))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.isoformat(), dt.timestamp()
    except Exception:
        return str(raw or ""), 0.0


def html_to_text(s: str) -> str:
    s = re.sub(r"(?is)<(script|style|head).*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</tr>|</li>", "\n", s)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t\xa0]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n\n", s).strip()


def body_text(msg) -> str:
    """Best plain-text rendering of a message body."""
    plain, rich = None, None
    for part in (msg.walk() if msg.is_multipart() else [msg]):
        if part.is_multipart() or part.get_content_disposition() == "attachment":
            continue
        ctype = part.get_content_type()
        try:
            payload = part.get_content()
        except Exception:
            raw = part.get_payload(decode=True) or b""
            payload = raw.decode(part.get_content_charset() or "utf-8", "replace")
        if not isinstance(payload, str):
            continue
        if ctype == "text/plain" and plain is None:
            plain = payload
        elif ctype == "text/html" and rich is None:
            rich = payload
    if plain and plain.strip():
        return plain.strip()
    return html_to_text(rich or "")


def strip_quoted(text: str) -> str:
    """Drop the quoted history so a brief shows only what's new."""
    out = []
    for line in text.splitlines():
        if re.match(r"^\s*>", line):
            continue
        if re.match(r"^\s*On .+ wrote:\s*$", line) or re.match(r"^-{2,}\s*Original Message", line, re.I):
            break
        if re.match(r"^\s*From: .+", line) and out and not out[-1].strip():
            break
        out.append(line)
    return "\n".join(out).strip()


def attachments(msg) -> list[dict]:
    res = []
    for part in msg.walk():
        if part.get_content_disposition() in ("attachment", "inline") and part.get_filename():
            res.append({"filename": part.get_filename(), "type": part.get_content_type(),
                        "bytes": len(part.get_payload(decode=True) or b"")})
    return res


def summarise(folder: str, uid: str, raw: bytes, flags: str) -> Summary:
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    name, addr = parseaddr(str(msg.get("From", "")))
    iso, ts = _date(msg)
    auto = bool(AUTOMATED.search(addr)) or bool(msg.get("List-Unsubscribe")) or \
        str(msg.get("Precedence", "")).lower() in ("bulk", "list", "junk") or \
        bool(msg.get("Auto-Submitted") and str(msg.get("Auto-Submitted")).lower() != "no")
    snippet = ""
    try:
        snippet = re.sub(r"\s+", " ", strip_quoted(body_text(msg)))[:280]
    except Exception:
        pass
    return Summary(
        folder=folder, uid=uid, date=iso, sender=addr.lower(), sender_name=name,
        to=_addr_list(msg.get("To")), cc=_addr_list(msg.get("Cc")),
        subject=str(msg.get("Subject", "")), message_id=str(msg.get("Message-ID", "")).strip(),
        in_reply_to=str(msg.get("In-Reply-To", "")).strip(),
        references=str(msg.get("References", "")),
        unread="\\Seen" not in flags, flagged="\\Flagged" in flags,
        automated=auto, snippet=snippet, ts=ts,
    )


def norm_subject(s: str) -> str:
    return re.sub(r"^\s*((re|fwd?|aw|sv)\s*:\s*)+", "", s or "", flags=re.I).strip().lower()


def awaiting_reply(sent: list[Summary], inbound: list[Summary], my_addr: str) -> list[dict]:
    """Messages I sent that nobody has answered yet: the chase list."""
    out = []
    for s in sent:
        recips = [a for a in s.to + s.cc if a != my_addr]
        if not recips:
            continue
        # A reply of mine that asks nothing ("Yes, Thursday works") closes the
        # loop; only chase things I started or questions I asked.
        if s.in_reply_to and "?" not in s.snippet:
            continue
        answered = any(
            m.ts >= s.ts and (
                (s.message_id and (s.message_id in m.in_reply_to or s.message_id in m.references))
                or (m.sender in recips and norm_subject(m.subject) == norm_subject(s.subject))
            )
            for m in inbound
        )
        if not answered:
            days = max(0, int((time.time() - s.ts) // 86400)) if s.ts else None
            out.append({**s.public(), "waiting_on": recips, "days_waiting": days})
    # Collapse to the latest message per conversation.
    seen, uniq = set(), []
    for item in sorted(out, key=lambda x: x["date"], reverse=True):
        key = (norm_subject(item["subject"]), tuple(item["waiting_on"]))
        if key not in seen:
            seen.add(key)
            uniq.append(item)
    return uniq


def needs_reply(inbound: list[Summary], sent: list[Summary], my_addr: str) -> list[dict]:
    """Human mail to me that I haven't answered since it arrived."""
    out, seen = [], set()
    for m in sorted(inbound, key=lambda x: x.ts, reverse=True):
        if m.automated or m.sender == my_addr:
            continue
        key = (m.sender, norm_subject(m.subject))
        if key in seen:
            continue
        seen.add(key)
        replied = any(
            s.ts >= m.ts and (
                (m.message_id and (m.message_id in s.in_reply_to or m.message_id in s.references))
                or (m.sender in s.to + s.cc and norm_subject(s.subject) == norm_subject(m.subject))
            )
            for s in sent
        )
        if not replied:
            out.append(m.public())
    return out


def build_message(sender: str, to: list[str], subject: str, body: str, cc=None, bcc=None,
                  reply_to: Summary | None = None, html_body: str | None = None) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = ", ".join(to)
    if cc:
        msg["Cc"] = ", ".join(cc)
    if bcc:
        msg["Bcc"] = ", ".join(bcc)
    if reply_to:
        subj = reply_to.subject
        msg["Subject"] = subj if re.match(r"^\s*re:", subj, re.I) else f"Re: {subj}"
        if reply_to.message_id:
            msg["In-Reply-To"] = reply_to.message_id
            refs = (reply_to.references + " " + reply_to.message_id).strip()
            msg["References"] = " ".join(refs.split()[-20:])
    else:
        msg["Subject"] = subject
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=sender.split("@")[-1])
    msg.set_content(body)
    if html_body:
        msg.add_alternative(html_body, subtype="html")
    return msg


# ---------- IMAP plumbing ----------

def _q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


@contextmanager
def imap():
    user, pw = _creds()
    conn = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT, timeout=30)
    try:
        conn.login(user, pw)
        yield conn
    finally:
        try:
            conn.logout()
        except Exception:
            pass


def folders(conn) -> dict:
    typ, data = conn.list()
    names, roles = [], dict(FALLBACK_FOLDERS)
    for line in data or []:
        if not line:
            continue
        s = line.decode("utf-8", "replace")
        m = re.match(r'\((?P<flags>[^)]*)\)\s+(?:"[^"]*"|NIL)\s+(?P<name>.+)$', s)
        if not m:
            continue
        name = m.group("name").strip()
        if name.startswith('"') and name.endswith('"'):
            name = name[1:-1].replace('\\"', '"')
        names.append(name)
        for flag, role in SPECIAL_USE.items():
            if flag.lower() in m.group("flags").lower():
                roles[role] = name
    return {"all": names, **roles}


def resolve_folder(conn, folder: str) -> str:
    if not folder or folder.lower() == "inbox":
        return "INBOX"
    f = folders(conn)
    return f.get(folder.lower(), folder)


def _criteria(query=None, sender=None, to=None, subject=None, since_days=None,
              unread_only=False, flagged_only=False) -> list[str]:
    c = []
    if since_days:
        d = (datetime.now() - timedelta(days=int(since_days))).strftime("%d-%b-%Y")
        c += ["SINCE", d]
    if sender:
        c += ["FROM", _q(sender)]
    if to:
        c += ["TO", _q(to)]
    if subject:
        c += ["SUBJECT", _q(subject)]
    if query:
        c += ["TEXT", _q(query)]
    if unread_only:
        c.append("UNSEEN")
    if flagged_only:
        c.append("FLAGGED")
    return c or ["ALL"]


def _ascii_or_literal(conn, crit: list[str]):
    """iCloud rejects raw UTF-8 in SEARCH; send non-ASCII terms as literals."""
    if all(x.isascii() for x in crit):
        return conn.uid("SEARCH", None, *crit)
    # imaplib sends one literal, appended at the end of the command: move the
    # first non-ASCII key/value pair to the end and send its value as that literal.
    i = next(k for k, x in enumerate(crit) if not x.isascii())
    key, val = crit[i - 1], crit[i]
    rest = [x for k, x in enumerate(crit) if k not in (i - 1, i)]
    rest = [x for x in rest if x.isascii()]
    conn.literal = val.strip('"').replace('\\"', '"').encode("utf-8")
    return conn.uid("SEARCH", "CHARSET", "UTF-8", *rest, key)


def search(conn, folder="INBOX", limit=25, peek_bytes=16384, **kw) -> list[Summary]:
    box = resolve_folder(conn, folder)
    typ, _ = conn.select(_q(box), readonly=True)
    if typ != "OK":
        raise RuntimeError(f"Cannot open folder {box!r}")
    typ, data = _ascii_or_literal(conn, _criteria(**kw))
    uids = (data[0] or b"").split() if data else []
    uids = uids[-int(limit):] if limit else uids
    if not uids:
        return []
    typ, resp = conn.uid("FETCH", b",".join(uids).decode(),
                         f"(UID FLAGS BODY.PEEK[]<0.{int(peek_bytes)}>)")
    res = []
    for item in resp or []:
        if not isinstance(item, tuple):
            continue
        meta = item[0].decode("utf-8", "replace")
        uid = re.search(r"UID (\d+)", meta)
        flags = re.search(r"FLAGS \(([^)]*)\)", meta)
        if uid:
            res.append(summarise(box, uid.group(1), item[1], flags.group(1) if flags else ""))
    res.sort(key=lambda s: s.ts, reverse=True)
    return res


def fetch_full(conn, folder: str, uid: str):
    box = resolve_folder(conn, folder)
    conn.select(_q(box), readonly=True)
    typ, resp = conn.uid("FETCH", str(uid), "(UID FLAGS BODY.PEEK[])")
    for item in resp or []:
        if isinstance(item, tuple):
            meta = item[0].decode("utf-8", "replace")
            flags = re.search(r"FLAGS \(([^)]*)\)", meta)
            return box, item[1], flags.group(1) if flags else ""
    raise RuntimeError(f"No message uid={uid} in {box!r}")


def store_flags(conn, folder: str, uids: list[str], op: str, flags: str):
    box = resolve_folder(conn, folder)
    conn.select(_q(box))
    return conn.uid("STORE", ",".join(map(str, uids)), op, flags)


def move(conn, folder: str, uids: list[str], dest: str) -> str:
    box = resolve_folder(conn, folder)
    target = resolve_folder(conn, dest)
    conn.select(_q(box))
    seq = ",".join(map(str, uids))
    typ, _ = conn.uid("MOVE", seq, _q(target))
    if typ != "OK":  # servers without MOVE
        conn.uid("COPY", seq, _q(target))
        conn.uid("STORE", seq, "+FLAGS", "(\\Deleted)")
        conn.expunge()
    return target


def append(conn, role: str, msg: EmailMessage, flags: str):
    box = resolve_folder(conn, role)
    return box, conn.append(_q(box), flags, imaplib.Time2Internaldate(time.time()),
                            msg.as_bytes(policy=email.policy.SMTP))


def smtp_send(msg: EmailMessage):
    user, pw = _creds()
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as s:
        s.ehlo()
        s.starttls()
        s.ehlo()
        s.login(user, pw)
        s.send_message(msg)
