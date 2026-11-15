# Focus — pricing thoughts

His thinking on how Focus is sold, in one place. **Nothing here is decided or built**: he's working on it.
Newest first. Ask before building any of it.

## Current favourites (2026-11-15) — he likes both

### 1. Free, Pro, Max — Pro is the one to buy
- Three tiers, laid out so the buyer lands on **Pro**: it's presented as the best deal, because it is.
- **Max is the anchor (the decoy).** It sits above Pro, costs noticeably more, and adds comparatively little.
  Its job is to make Pro look like the smart choice, not to sell many copies.
- On the page: Pro gets the emphasis (highlighted column, "Best value" or similar); Max is shown honestly, just
  not pushed.
- Honest framing matters to him ("no bullshit, minimalistic, honest"): Pro really must be the best value.

### 2. Pay once, or subscribe
- **£50 up front, or a smaller amount monthly** (£5/month was his first figure).
- £5/month reaches £50 at month 10, so paying once reads as the obvious deal; monthly lowers the barrier to £5.
- Stripe handles both: one product, a one-time Price and a recurring Price.
- Open: can a subscriber convert to the one-off with what they've paid credited? What happens when a subscription
  lapses (suggestion: back to Free, the same rule as the trial ending)? A yearly option (e.g. £40) or not?

The two combine: Free / Pro / Max, with Pro (and Max) payable once or monthly.

## Earlier in the day (2026-11-15), still relevant

### What's in each tier — his sketch
- **Free:** Session only. No modes, no tools, minimal appearance changes.
- **Middle (was "Medium"):** Session plus Tools.
- **Top:** Session *unlimited* plus Tools plus Modes, plus appearance.
- Open: what "unlimited" lifts. Suggestion: limit scale (e.g. apps kept per session, number of saved sessions),
  never frequency (sessions per day) — that punishes the habit.
- Note: with Free / Pro / Max, this maps as Free / Pro / Max, or Pro takes the full set and Max adds extras.

### Modes aren't strong enough alone
- "Modes is actually not that good and not worth the money": they can't justify a paid tier on their own.
  Either a middle tier carries them, or the key features are held back for the top tier.

### The model underneath (unchanged)
- **14-day free trial = the full package** (everything in the top paid tier) from first launch.
- **When the trial ends, Focus drops to Free:** a limited subset, free forever.
- **Pay → licence shown in the app:** the top left reads **Focus Pro** (white "Pro" box, `focusPro` flag).
- **Price anchor: £50 one-off.** Round numbers only (5s and 0s), never ending in 9.
- Why it's a bargain: Wispr Flow does one thing and costs £15/month or £150/year, every year.
- Earlier figures for the record: £5 (old site), £55 (first decision), £100 (suggested after Wispr comparison).
- Teams: per seat, sold in packs, round figures (earlier suggestion at £55: 5 £275 · 20 £1,000 · 50 £2,250).

## What's on the site now (paradoxica.uk/focus)
- £50, Buy Now → dummy Stripe checkout (`/focus/checkout/`), trial button "14-Day Free Trial · Everything in Pro".
- A two-column Free | Pro table + header "Pricing" link, **off** behind `SHOW_PRICING` (preview: `?pricing`).
  Becomes Free / Pro / Max with a once/monthly toggle when he settles this.
