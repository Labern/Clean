# Focus — pricing thoughts

His thinking on how Focus is sold, gathered in one place (2026-11-15). The newest ideas come first. None of it is
built yet; the app only shows the parts that are visible, and those are placeholders.

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
