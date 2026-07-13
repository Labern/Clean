const CLAUDE = "https://claude.ai";

// How many transcripts to fetch at once. Kept modest so claude.ai never
// rate-limits a normal-sized history.
const TRANSCRIPT_CONCURRENCY = 5;

async function chosenOrg() {
  const response = await fetch(`${CLAUDE}/api/organizations`, {
    credentials: "include",
    headers: { Accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error("Open claude.ai in this browser and make sure you are signed in.");
  }
  const orgs = await response.json();
  const list = Array.isArray(orgs) ? orgs : [];
  // Prefer the workspace that can actually chat (skips the API-only org).
  const org = list.find((o) => Array.isArray(o.capabilities) && o.capabilities.includes("chat")) || list[0];
  if (!org || !org.uuid) throw new Error("No Claude chat workspace was found for this account.");
  return org.uuid;
}

async function claudeFetch(path) {
  const response = await fetch(`${CLAUDE}${path}`, {
    credentials: "include",
    headers: { Accept: "application/json" },
  });
  if (response.status === 401 || response.status === 403) {
    throw new Error("Claude did not authorise the sync. Open claude.ai, sign in, then try again.");
  }
  if (!response.ok) throw new Error(`Claude returned ${response.status} while reading your conversations.`);
  return response.json();
}

async function fetchConversationIndex(org, port) {
  const items = [];
  let offset = 0;
  const limit = 100;
  while (true) {
    port.postMessage({ type: "status", message: `Reading conversation index… ${items.length.toLocaleString()}` });
    const page = await claudeFetch(`/api/organizations/${org}/chat_conversations?limit=${limit}&offset=${offset}`);
    const batch = Array.isArray(page) ? page : [];
    items.push(...batch);
    if (batch.length < limit) break;
    offset += batch.length;
  }
  return items;
}

async function streamTranscripts(org, index, port) {
  const queue = index.slice();
  const total = index.length;
  let done = 0;

  async function worker() {
    while (queue.length) {
      const conversation = queue.shift();
      try {
        const full = await claudeFetch(
          `/api/organizations/${org}/chat_conversations/${conversation.uuid}?tree=True&rendering_mode=messages&render_all_tools=true`
        );
        port.postMessage({ type: "conversation", raw: full });
      } catch {
        // A single failed conversation should never abort the whole sync.
      }
      done += 1;
      if (done % 4 === 0 || done === total) {
        port.postMessage({ type: "status", message: `Loading transcripts… ${done.toLocaleString()} / ${total.toLocaleString()}` });
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(TRANSCRIPT_CONCURRENCY, total || 1) }, worker));
}

async function runSync(port) {
  const org = await chosenOrg();
  const index = await fetchConversationIndex(org, port);
  // Phase 1: hand over the full index immediately so the calendar fills in.
  port.postMessage({ type: "index", items: index });
  // Phase 2: stream each transcript so the in-app reader works on live data.
  await streamTranscripts(org, index, port);
  port.postMessage({ type: "complete", total: index.length });
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "conversation-calendar-live") return;
  port.onMessage.addListener((message) => {
    if (!message || message.type !== "sync") return;
    runSync(port).catch((error) => {
      port.postMessage({ type: "error", message: (error && error.message) || "Live sync failed." });
    });
  });
});
