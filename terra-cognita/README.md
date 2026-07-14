# Terra Cognita — an atlas of everything you've asked

A single-file web app that turns an AI conversation export into an **antique
cartographic atlas**. Every conversation becomes a settlement; related
conversations cluster into **named territories** (islands with contour
coastlines); and a **spyglass search** runs full-text over every word you've
ever asked. Click an island in the legend to sail to it; click a settlement to
read the whole conversation.

Everything runs **in the browser** — your export is parsed locally and never
uploaded anywhere.

## Use it

Open `index.html` (or the hosted artifact) and **drop your export JSON** onto the
page. Until you do, it shows a stable *sample atlas* so the map is alive on first
load. Accepts either format, and multiple files at once:

- **ChatGPT** export — the `conversations-*.json` files (node-`mapping` tree).
- **Claude** export — `conversations.json` (`chat_messages` array).

## How it works

1. **Parse** each export format into `{title, time, messages[]}`.
2. **Index** — TF-IDF vector per conversation + inverted index for instant search.
3. **Cluster** — cosine **k-means** groups by theme; each cluster is auto-named
   from its most *distinctive* terms.
4. **Chart** — phyllotaxis + repulsion layout, angular-max-radius contoured hulls.
5. **Render** — Canvas cartography: pan/zoom, hover, fly-to, and a token-driven
   light **Parchment** / dark **Night** chart theme.

No build step, no dependencies, no network. One HTML file.
