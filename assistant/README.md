# iCloud connector for Claude

A hosted MCP server that gives Claude direct access to iCloud Mail and Calendar
on every device, including the Claude app on iPhone. Nothing runs on your Mac.

```
iPhone Claude app ─┐
claude.ai (web)    ├─► claude.ai connector ─► https://<project>.vercel.app/<token>/mcp
Claude desktop     ┘                             │
                                                  ├─ IMAP  imap.mail.me.com:993  (read, search, move, flag, drafts)
                                                  ├─ SMTP  smtp.mail.me.com:587  (send, reply in-thread)
                                                  └─ CalDAV caldav.icloud.com    (events)
```

## Setup (free, no card, about 5 minutes on a phone)

1. **App-specific password.** appleid.apple.com → Sign-In and Security →
   App-Specific Passwords → **+** → name it "Claude" → copy the code.
2. **Deploy to Vercel (free Hobby plan).** Open
   `https://vercel.com/new/clone?repository-url=https://github.com/Labern/Clean/tree/claude/youthful-wozniak-y3hqdc/assistant/icloud-mcp&env=ICLOUD_EMAIL,ICLOUD_APP_PASSWORD,ICLOUD_MCP_TOKEN&project-name=icloud-connector`
   → sign in with GitHub → fill the three values → Deploy.
   - `ICLOUD_MCP_TOKEN`: 24+ letters/digits/-/_. It is the key to your mailbox.
3. **Connect.** claude.ai → Settings → Connectors → Add custom connector →
   `https://<project>.vercel.app/<ICLOUD_MCP_TOKEN>/mcp`. It appears in the
   iPhone app automatically.
4. Say **"brief me"**.

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
- Runs as a stateless serverless function: no server to keep alive, nothing on your Mac.
- Local use in Claude Code also works: `pip install ./assistant/icloud-mcp`, then
  `claude mcp add icloud -e ICLOUD_EMAIL=… -e ICLOUD_APP_PASSWORD=… -- icloud-mcp`.
- Tests: `python3 assistant/icloud-mcp/tests/test_mail.py`.
