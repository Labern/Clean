# Focus — pricing thoughts

His thinking on how Focus is sold, gathered in one place (2026-11-15). The newest ideas come first. None of it is
built yet; the app only shows the parts that are visible, and those are placeholders.

## The pricing play (his, 2026-11-15, latest; remember it)
- **Nominal prices on the site: Pro £5 a month, Max £10 a month.** Free exists but is **very limited**.
- **Lured in by the cheap price, people go to pay, and only then see they can pay a multiple instead:**
  **one-off at 10x (Pro £50, Max £100): theirs forever**, or yearly. "For £50 they get it forever": an extremely
  enticing sell.
- The site shows only the monthly prices; the checkout offers Monthly (default) and One-off ("Best value").
- **Yearly: undecided, removed from the checkout.** He's weighing **£50 a year**, with the one-off at some higher **£X**.
- **Max: nobody should ever want to buy it, but it needs full functionality.** It exists to make Pro the obvious buy.

## New features (his, 2026-11-15) — Pro and Max only; for the app session to build
1. **Open apps at a set time**, e.g. fun apps like Discord at 5:30 PM.
2. **Block apps you choose** (other apps do this; here it's part of Pro and Max).
3. **A Max badge**, in the same place as the Pro badge (top left, beside the Focus name), for Max licences. **Built in the app (0.18.65):** a white "Max" box where "Pro" goes, read live from `focusTier` = "max". Max has
   full functionality; nobody should ever want it.
- The site's pricing table already lists 1 and 2 under Pro and Max.

## Decided and live on the site (2026-11-15, evening)
- **Lead with the subscription: £5 a month.** Buy Now on the site is "Buy Now – £5/month" and opens the checkout on
  Pro, monthly. The one-off and yearly prices appear only in the checkout (see "The pricing play").
- **Pro is what we want them on; Max is there to direct them to it.**
- **Free is partial, and not by much.** Every copy starts with **14 days of Pro**, then drops to Free.
- **The trial takes an email.** The site's trial dialog collects it (filed on the server as `focus-signup`), then
  promises the download link by email.
- **What Free gets (on the site now):** sessions, but **only up to 2 apps kept open** during a session; Basic
  appearance; no Tools, Modes, History or custom shortcuts. Pro and Max: any number of apps.
  - Why "apps kept open" and not "one session": a session is one start→end cycle; you're either in one or not, so
    "one session" vs "unlimited sessions" limits nothing real (a daily cap would punish the habit). The number of
    apps you can keep is felt every time and tightens as you rely on it. Easy to change if he prefers another lever.
- The pricing table (Free / Pro / Max, Monthly | One-off switch, Monthly first) and the header Pricing link are live.

## Tiers: Free, Pro, Max (latest)
- **Three tiers: Free, Pro and Max.**
- **Pro is the one to buy.** The tiers are arranged so that Pro reads as the better deal, because it is. Max sits above
  it as the anchor: it makes Pro look as good as it is, without being what most people should pick.
- **Pro is paid either way:**
  - **£50 up front**, once; or
  - **a smaller monthly amount** (he suggested £5 a month). Ten months of £5 equals buying outright, which makes the
    one-off price the obvious deal for anyone who stays.
- He likes having both, up front and monthly.
- Still open: what Max includes and costs, what exactly is free, and the monthly figure.

- **On the page:** Pro gets the emphasis (highlighted column, "Best value" or similar); Max is shown honestly,
  just not pushed. It has to be honest: "no bullshit, minimalistic, honest".
- Still open on payment: can a subscriber convert to the one-off with what they've paid credited (suggestion: yes)?
  When a subscription lapses, back to Free (the same rule as the Pro Preview ending)? A yearly option or not
  (suggestion: not; it muddies "once or monthly")?

## On the site now (paradoxica.uk/focus; the "Focus Site" session owns it)
- £5 a month first, £50 once beside it. Buy Now → a dummy Stripe checkout at `/focus/checkout/` (nothing is charged). Trial button: "14-Day Free
  Trial · Everything in Pro" (to align with the app's "Pro Preview" naming once he confirms).
- Free / Pro / Max table with a Monthly | One-off switch, and a header "Pricing" link: **live**. `#buy` stays the buy anchor.

## Earlier tier sketches (kept for the record)
- **Free / Medium / Pro:** Free is a session only (no modes, no tools, minimal appearance changes). Medium is session
  plus Tools. Pro is unlimited sessions plus Tools, Modes and appearance. "Unlimited" was never defined.
- **Modes alone aren't strong enough to carry Pro** ("not that good and not worth the money"). That's why a middle
  tier, or the key features held back for the top tier, came up.
- **First split I suggested:** Free is sessions (⌘⇧F, choosing apps, Critical System Processes, everything reopening).
  Pro is modes and their keys, History and snapshots, Tools, Appearance, and custom shortcuts.

## How someone moves through it
1. **Pro Preview:** a free trial of Pro, 14 days, everything unlocked from the first launch. ("Free trial" was
   renamed Pro Preview: being let in early, not being tested.)
2. **When the Pro Preview ends, Focus drops to the free version:** still usable, free for good, but Pro features
   lock.
3. **Pay (once, or monthly) to get Pro back.** On the free version the button should invite people back, e.g.
   "Get Focus Pro back".
- Why: it shows the whole product, allows free use, and makes Pro something people miss.

## In the app (placeholders until licences exist)
- **During the Pro Preview:** the foot of the sidebar shows "14 Days of Pro Left — Buy Now" (white, square-ish
  corners). It opens paradoxica.co.uk/focus#buy, the same place the site's own Buy link goes. He chose this wording
  over four others.
- **Bought:** the top left reads **Focus Pro**, a small white "Pro" box beside the name. It switches live the moment the
  purchase is recorded (the `focusPro` flag).
- **For now** the build shows both, and the day count is a stand-in 14.

## Price rules
- **Round numbers only: 5s and 0s.** No prices ending in 9.
- **Not pay-what-you-want** and no free-for-all: it undersells a premium product. Paying more than the price can be
  an option, never less.
- **Don't price against other apps.** "I'm on a different level." The one comparison he made himself: Wispr Flow is
  £15 a month or £150 a year, so £50 once is a bargain.
- Figures along the way: £5 (the site, still to change), £99, £55, £100 (my suggestion), then £50 once or £5 a month.

## Teams
- Per seat, sold in packs, round figures; once or monthly, matching the personal prices. To work out at £50 / £5.

## Purchase flow
- Built from the Tesla research, Stripe and the MAKE book: the trial, sign-up, paying, refunds and using it must each
  be one obvious step. There's a 30-day refund. The Hub session handles Stripe, downloads and notarisation.
