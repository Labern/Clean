# iCloud connector for Claude

A hosted MCP server that gives Claude direct access to iCloud Mail and Calendar
on every device, including the Claude app on iPhone. Nothing runs on your Mac.

```
iPhone Claude app ─┐
claude.ai (web)    ├─► claude.ai connector ─► https://<you>.onrender.com/<token>/mcp
Claude desktop     ┘                             │
                                                  ├─ IMAP  imap.mail.me.com:993  (read, search, move, flag, drafts)
                                                  ├─ SMTP  smtp.mail.me.com:587  (send, reply in-thread)
                                                  └─ CalDAV caldav.icloud.com    (events)
```

## Setup (about 5 minutes, all doable from a phone)

1. **App-specific password.** Go to appleid.apple.com → Sign-In and Security →
   App-Specific Passwords → Generate. Name it "Claude". Copy the 16 characters.
2. **Deploy.** Open
   `https://render.com/deploy?repo=https://github.com/Labern/Clean/tree/claude/youthful-wozniak-y3hqdc`
   and fill in three values:
   - `ICLOUD_EMAIL`: your iCloud address
   - `ICLOUD_APP_PASSWORD`: the password from step 1
   - `ICLOUD_MCP_TOKEN`: a long random string (letters/digits/-/_ only, 24+ chars).
     This is the key to your mailbox, so never share the URL.
3. **Connect.** claude.ai → Settings → Connectors → Add custom connector →
   URL `https://<service>.onrender.com/<ICLOUD_MCP_TOKEN>/mcp`. Then enable it
   in a chat (the "+" / tools menu). It syncs to the iPhone app automatically.
4. Say: **"brief me"**.

## What it does

| Tool | Purpose |
|---|---|
| `daily_brief` | The scan: who is waiting on you, who you are waiting on, flagged items, automated mail skipped |
| `awaiting_replies` | Chase list: everything you sent that nobody answered, with days waiting |
| `search_mail`, `read_email`, `conversation_with` | Find and read; quoted history is stripped |
| `send_email`, `reply`, `save_draft` | Act; replies thread correctly (Re:, In-Reply-To, References) and are saved to Sent |
| `mark`, `move_email`, `list_folders` | Triage: read/unread/flag, archive/trash/junk |
| `calendar_events`, `create_event` | iCloud Calendar |

The server ships its own operating instructions (chief-of-staff behaviour:
brief by person, write in your voice, track and chase), so any Claude client
that connects gets the assistant, not just the tools.

## Notes

- Sent copies: the server appends each sent message to "Sent Messages" so the
  chase list sees it. If you ever see duplicates in Sent, set `ICLOUD_SAVE_SENT=0`.
- Render Starter (~$7/mo) is used because the free tier sleeps and blocks SMTP.
- Local use in Claude Code also works: `pip install ./assistant/icloud-mcp`, then
  `claude mcp add icloud -e ICLOUD_EMAIL=… -e ICLOUD_APP_PASSWORD=… -- icloud-mcp`.
- Tests: `python3 assistant/icloud-mcp/tests/test_mail.py`.
