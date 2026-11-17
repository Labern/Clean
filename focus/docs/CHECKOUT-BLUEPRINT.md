# The checkout blueprint (★★★★★ × PARADOX)

Labern, 17 Nov 2026, of the live Focus checkout (paradoxica.uk/focus/checkout, real Stripe): "the layout, the design,
and the touches are so good. Save this as my blueprint going forward for all apps… I love it. It's really fucking good."
Every app under the brand sells through a checkout built like this. The code is saved beside this file in
`blueprints/checkout/` (and `~/.claude/blueprints/checkout/`). Source: Labern/paradoxica-hub,
`sites/paradoxica.uk/focus/checkout/index.html` (copy it, change the app).

## The shape
- **Stripe's split:** left pane black (what you're buying), right pane white (how you pay), a hairline shadow between.
- **Our page, Stripe's fields:** Checkout Sessions with `ui_mode: "elements"`: Stripe's Payment Element and Express
  Checkout Element inside our own layout. Card details never touch our servers; every total shown is Stripe's own.
  Fallback while the API is down: Stripe's hosted page for the same plan (Payment Links), so buying never breaks.
- **Prices come from the app's `pricing.json`**, generated into the page; never typed by hand.

## Left: what you're buying
1. Back arrow · the app's mark and name · a TEST MODE pill (test only).
2. The app icon tile beside a two-line pitch, in his words ("Too many apps? Save them for later." / "The app Mac should
   come with." — the dropped article is deliberate; never correct his brand lines).
3. Product name with the **Pro box**; the **big price in whole pounds** (£50, not £50.00) with the **anchor struck through**
   beside it (£99).
4. **Plans as stacked, selectable cards:** Monthly ("£5 a month · cancel any time"), Yearly ("£50 a year · save 17%"),
   One-time purchase with a white tag ("£50 FOR A LIMITED TIME") and "Yours forever". The chosen card is outlined.
5. **The code chip:** dashed EARLY + green "Applied ✓". One tap copies and applies it; it switches to the one-off it's for.
6. **Order summary:** icon, name + Pro box, "Yours forever", price; Subtotal; the code line ("EARLY · Early adopter gift
   −£49.00"); **Total due today**.

## Right: how you pay
1. **Express wallets first, one full-width button per row:** Apple Pay, Google Pay, PayPal, Link (Klarna when eligible).
   Never remove a way to pay on a hunch.
2. "Or pay with card" divider · Email · the applied code (dashed chip, what it gives, × to remove) · the Payment Element
   as full-width accordion bars (no radios) · Country · optional "save my information".
3. Pay; Stripe's wording and the legal links under Pay, on the white side. A success page after.

## The selling logic (his "ultimate version")
- **Anchor:** the one-off's list price (£99) struck through beside the real price (£50) — half price at a glance.
- **A year's money for forever:** the one-off costs what one year of Yearly costs, so "yours forever" is the obvious pick.
- **A soft entry:** Monthly at £5, so the one-off feels like the grown-up choice.
- **No friction, a reason to act now:** the code pre-applied, "for a limited time", "yours forever".
- Every price a buyer pays is round (5s and 0s); the anchor is the one exception.
