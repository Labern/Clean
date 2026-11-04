"""Run: python -m pytest assistant/icloud-mcp/tests -q   (or python this_file)"""
import email
import email.policy
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
os.environ.setdefault("ICLOUD_EMAIL", "me@icloud.com")
os.environ.setdefault("ICLOUD_APP_PASSWORD", "abcd-efgh-ijkl-mnop")

from icloud_mcp import mail as M  # noqa: E402
from icloud_mcp import server as S  # noqa: E402

NOW = time.time()


def raw(frm, to, subj, body, mid, days_ago, irt="", refs="", extra=""):
    from email.utils import formatdate
    return (f"From: {frm}\r\nTo: {to}\r\nSubject: {subj}\r\nMessage-ID: {mid}\r\n"
            f"Date: {formatdate(NOW - days_ago * 86400)}\r\n"
            + (f"In-Reply-To: {irt}\r\n" if irt else "") + (f"References: {refs}\r\n" if refs else "")
            + extra + f"Content-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n").encode()


INBOX = {
    "11": (raw("Dan Builder <dan@build.co>", "me@icloud.com", "Kitchen quote",
               "Hi, quote is £4,200. Can you confirm by Friday?\n\nOn Mon, Luke wrote:\n> old stuff",
               "<q1@build.co>", 3), "\\Seen"),
    "12": (raw("Amazon <no-reply@amazon.co.uk>", "me@icloud.com", "Your order shipped",
               "Tracking...", "<a1@amazon>", 1, extra="List-Unsubscribe: <x>\r\n"), ""),
    "13": (raw("Sara <sara@agency.com>", "me@icloud.com", "Re: Contract",
               "Signed, attached.", "<s2@agency.com>", 1, irt="<me1@icloud.com>",
               refs="<me1@icloud.com>"), ""),
    "14": (raw("Tom <tom@x.com>", "me@icloud.com", "Dinner?", "Thursday?", "<t1@x.com>", 2), "\\Flagged"),
}
SENT = {
    "5": (raw("me@icloud.com", "sara@agency.com", "Contract", "Please sign.", "<me1@icloud.com>", 4), "\\Seen"),
    "6": (raw("me@icloud.com", "landlord@lets.com", "Boiler", "When is the engineer coming?",
              "<me2@icloud.com>", 5), "\\Seen"),
    "7": (raw("me@icloud.com", "tom@x.com", "Re: Dinner?", "Yes!", "<me3@icloud.com>", 1,
              irt="<t1@x.com>"), "\\Seen"),
}


class FakeIMAP:
    boxes = {"INBOX": INBOX, "Sent Messages": SENT, "Drafts": {}, "Archive": {}}
    appended, stored, literal = [], [], None

    def __init__(self, *a, **k): self.cur = None
    def login(self, u, p): assert u == "me@icloud.com"; return "OK", [b""]
    def logout(self): pass
    def list(self):
        return "OK", [b'(\\HasNoChildren) "/" "INBOX"', b'(\\HasNoChildren \\Sent) "/" "Sent Messages"',
                      b'(\\HasNoChildren \\Drafts) "/" "Drafts"', b'(\\Archive) "/" "Archive"']
    def select(self, box, readonly=False):
        self.cur = box.strip('"'); return ("OK", [b"1"]) if self.cur in self.boxes else ("NO", [b""])
    def append(self, box, flags, date, data):
        self.appended.append((box.strip('"'), flags, data)); return "OK", [b""]
    def expunge(self): return "OK", []

    def uid(self, cmd, *args):
        box = self.boxes[self.cur]
        if cmd == "SEARCH":
            crit = [a for a in args if a]
            uids = []
            for u, (r, fl) in box.items():
                m = email.message_from_bytes(r, policy=email.policy.default)
                ok = True
                for key, field in (("FROM", "From"), ("TO", "To"), ("SUBJECT", "Subject")):
                    if key in crit:
                        v = crit[crit.index(key) + 1].strip('"').lower()
                        ok &= v in str(m.get(field, "")).lower()
                if "UNSEEN" in crit: ok &= "\\Seen" not in fl
                if "FLAGGED" in crit: ok &= "\\Flagged" in fl
                if ok: uids.append(u)
            return "OK", [" ".join(sorted(uids, key=int)).encode()]
        if cmd == "FETCH":
            out = []
            for u in args[0].split(","):
                r, fl = box[u]
                out.append((f"1 (UID {u} FLAGS ({fl}) BODY[] {{{len(r)}}}".encode(), r))
                out.append(b")")
            return "OK", out
        if cmd == "STORE":
            self.stored.append((self.cur, args)); return "OK", []
        if cmd == "MOVE":
            return "OK", []
        raise AssertionError(cmd)


SENT_MAIL = []
M.imaplib.IMAP4_SSL = FakeIMAP
M.smtp_send = lambda msg: SENT_MAIL.append(msg)


def test_parsing_and_quote_strip():
    s = M.summarise("INBOX", "11", INBOX["11"][0], "\\Seen")
    assert s.sender == "dan@build.co" and s.sender_name == "Dan Builder"
    assert "£4,200" in s.snippet and "old stuff" not in s.snippet
    assert not s.unread and not s.automated
    assert M.summarise("INBOX", "12", INBOX["12"][0], "").automated


def test_daily_brief():
    b = S.daily_brief(days=7)
    needs = {m["sender"] for m in b["needs_your_reply"]}
    assert needs == {"dan@build.co", "sara@agency.com"}, needs   # tom answered, amazon is automated
    waiting = {tuple(w["waiting_on"]) for w in b["waiting_on_others"]}
    assert waiting == {("landlord@lets.com",)}, waiting           # sara replied, tom replied
    assert b["automated_skipped"] == 1
    assert [f["sender"] for f in b["flagged"]] == ["tom@x.com"]


def test_reply_threads_and_saves_sent():
    SENT_MAIL.clear(); FakeIMAP.appended.clear()
    r = S.reply("INBOX", "11", "Confirmed, go ahead.")
    msg = SENT_MAIL[-1]
    assert msg["To"] == "dan@build.co"
    assert msg["Subject"] == "Re: Kitchen quote"
    assert msg["In-Reply-To"] == "<q1@build.co>" and "<q1@build.co>" in msg["References"]
    assert FakeIMAP.appended[-1][0] == "Sent Messages"
    assert r["saved_to"] == "Sent Messages"


def test_send_draft_search_conversation():
    S.send_email(["x@y.com"], "Hello", "Body")
    assert SENT_MAIL[-1]["Subject"] == "Hello" and SENT_MAIL[-1]["From"] == "me@icloud.com"
    assert S.save_draft(["x@y.com"], "D", "B")["draft_saved"] == "Drafts"
    assert [m["uid"] for m in S.search_mail(sender="dan")] == ["11"]
    conv = S.conversation_with("sara")
    assert [c["subject"] for c in conv] == ["Contract", "Re: Contract"]
    full = S.read_email("INBOX", "11")
    assert "Friday" in full["body"] and "old stuff" not in full["body"]
    assert S.list_folders()["sent"] == "Sent Messages"


def test_non_ascii_search_uses_literal():
    class C:
        literal = None
        def uid(self, *a): self.args = a; return "OK", [b""]
    c = C()
    M._ascii_or_literal(c, ["SINCE", "01-Nov-2026", "FROM", '"José"'])
    assert c.args == ("SEARCH", "CHARSET", "UTF-8", "SINCE", "01-Nov-2026", "FROM")
    assert c.literal == "José".encode()


if __name__ == "__main__":
    for k, f in list(globals().items()):
        if k.startswith("test_"):
            f(); print("ok", k)
