# 🍋 pay

A one-page Stripe payment page. Lemon, Comic Sans, rainbow. Type a number,
press Enter, get charged.

## The fees (Stripe UK, standard pricing)

There is no zero-fee option. Interchange goes to the card networks and the
issuing bank before Stripe takes anything.

| | |
|---|---|
| UK consumer cards | 1.5% + 20p |
| UK premium / commercial | 2.8% + 20p |
| EEA cards | 2.5% + 20p |
| International | 3.15% + 20p |
| Currency conversion | +2% |
| Chargeback | ~£15, win or lose |
| Refund | original fee is **not** returned |
| Standard payout to UK bank | free |

No monthly fee, no setup fee. The **cover the fees** tickbox is the only real
lever: it grosses the charge up so the typed amount is what lands.

`charge = (net + 0.20) / (1 - 0.015)` — not `net × 1.015 + 0.20`, which
under-collects because the percentage applies to the larger number. At £1000
the naive version leaves you 23p short.

UK law bans *mandatory* surcharging on consumer cards (PSR 2017). This is an
optional tickbox, off by default, which is a different thing.

## Wiring it up

Pick one. Both are configured in the `CONFIG` block at the bottom of
`index.html`.

### 1. `CHECKOUT_ENDPOINT` — the real one

Charges exactly what was typed, one click, no retyping.

The browser is not allowed to name the price. If it were, anyone could open
devtools and pay you 1p. So the amount is re-validated server-side.

1. Deploy `api/checkout.js` to Vercel (as `/api/checkout.js`), Netlify, or
   any host that runs a function. It has **no npm dependencies** — it talks to
   Stripe's REST API with `fetch`.
2. Set `STRIPE_SECRET_KEY` in that host's environment. Never in this page.
3. Optionally set `ALLOWED_ORIGIN` to your page's origin to lock down CORS.
4. Paste the function's URL into `CONFIG.CHECKOUT_ENDPOINT`.

Server-side guards: integer minor units only, min 30p, max £10,000.

### 2. `PAYMENT_LINK` — no server at all

Works on GitHub Pages as-is, with one compromise.

Create a Stripe Payment Link using a *"customers choose what to pay"* price,
then paste the `buy.stripe.com/...` URL into `CONFIG.PAYMENT_LINK`.

The compromise: **Payment Links have no amount URL parameter.** Only UTM codes
and `client_reference_id` are supported, so the payer re-enters the amount on
Stripe's page. The number typed here rides along as `client_reference_id`
(`amt_2558`) so you can see what they meant.

## Other config

`CURRENCY` · `SYMBOL` · `MIN` · `MAX` · `PICKS` (quick-pick buttons) ·
`DESCRIPTION` (shown at Checkout) · `FEE_PCT` / `FEE_FIXED` (gross-up maths
only) · `TITLE` · `SUBTITLE`.

## Before taking real money

Stripe requires a clear description of what is being sold; `DESCRIPTION` is
the field for it. A page that charges arbitrary amounts with no stated purpose
can get an account flagged. Test with `sk_test_` keys first.

## Notes

Deliberately ignores the repo's terminal house style — it was asked for in
lemon, Comic Sans and rainbow. Comic Neue loads from Google Fonts so it still
reads as Comic Sans on Linux and Android.
