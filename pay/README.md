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
| **Bacs Direct Debit** | **1%, capped at £4.00** |

No monthly fee, no setup fee.

**Card fees are uncapped.** That is the whole problem at four figures: £9,999 on
a UK debit card costs £150.19, and there is no ceiling. Bacs Direct Debit is 1%
**capped at £4.00**, so the same £9,999 costs £4 — a 97% saving. Bacs clears in
days rather than seconds and is recallable, which is the trade.

The **cover the fees** tickbox is the other lever: it grosses the charge up so
the typed amount is what lands.

`charge = (net + 0.20) / (1 - 0.015)` — not `net × 1.015 + 0.20`, which
under-collects because the percentage applies to the larger number. At £1000
the naive version leaves you 23p short.

UK law bans *mandatory* surcharging on consumer cards (PSR 2017). This is an
optional tickbox, off by default, which is a different thing.

## Two rails

The page offers the payer a choice, with the real saving shown live:

| £9,999 via | Fee | |
|---|---|---|
| 🏦 Bank transfer (open banking) | **£0.20** | flat, whatever the amount |
| 💳 Card (Stripe) | **£150.18** | 1.5% + 20p, no ceiling |

Bank transfer is the default. Cards stay as the option for anyone who insists.

### 🏦 Open banking — `OPENBANKING_ENDPOINT`

The payer is redirected to **their own bank**, approves with their normal
biometrics, and their bank executes a Faster Payment. No card network, so no
interchange and no scheme fees — which is the entire reason it is ~20p flat
rather than a percentage.

1. Sign up at [TrueLayer](https://console.truelayer.com) and create an app.
   Start in **sandbox**; there are test banks with fake credentials.
2. Generate an EC **P-521** key pair and upload the public key:
   ```
   openssl ecparam -genkey -name secp521r1 -noout -out ec512-private.pem
   openssl ec -in ec512-private.pem -pubout -out ec512-public.pem
   ```
   ES512 requires P-521 specifically. Any other curve fails to sign.
3. **Verify signing before anything else:**
   ```
   node pay/tools/verify-signing.mjs                       # local checks
   TL_KID=<key-uuid> TL_PRIVATE_KEY="$(cat ec512-private.pem)" \
     node pay/tools/verify-signing.mjs --remote            # TrueLayer's own check
   ```
   The remote check hits TrueLayer's `/v1/test-signature`. A 204 means your
   signature is correct. Do this first — a signing bug otherwise surfaces as an
   opaque 401 during a real payment.
4. Deploy `api/openbanking.js` and set:

   | Variable | |
   |---|---|
   | `TL_CLIENT_ID` / `TL_CLIENT_SECRET` | from the console |
   | `TL_KID` | the signing key's UUID |
   | `TL_PRIVATE_KEY` | the PEM (escaped newlines are handled) |
   | `TL_RETURN_URI` | where the payer comes back to |
   | `TL_ENV` | `sandbox` (default) or `live` |
   | `TL_MERCHANT_ACCOUNT_ID` | **or** the three below |
   | `TL_SORT_CODE` / `TL_ACCOUNT_NUMBER` / `TL_ACCOUNT_NAME` | paid bank-to-bank, straight to you |

   Setting the sort code and account number means the money goes **directly**
   into your account and TrueLayer never holds it. A merchant account parks it
   with them first, which you want only if you need refunds or batched payouts.
5. Paste the function URL into `CONFIG.OPENBANKING_ENDPOINT`.

### 💳 Cards

Configured in the `CONFIG` block at the bottom of `index.html`.

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

`CURRENCY` · `SYMBOL` · `MIN` · `MAX` · `PICKS` (quick-pick buttons — set to
£1,000 / £5,000 / £9,999; note `MAX` must clear the top pick, since £9,999 with
fees covered grosses to £10,151.47) ·
`DESCRIPTION` (shown at Checkout) · `FEE_PCT` / `FEE_FIXED` (gross-up maths
only) · `TITLE` · `SUBTITLE`.

## The regulatory line

**Never let the money land in an account you control before it reaches its
destination.** The moment it does, you are conducting regulated payment
services or issuing e-money and need FCA permission.

Open banking *initiation* doesn't cross that line: the payment goes payer's
bank → your bank directly, and you only initiate and reconcile. That's what
keeps this setup unregulated. Becoming the platform others use — a PISP in your
own right — is £50,000 initial capital, professional indemnity insurance, and
6–10 months of FCA review plus 4–8 weeks preparing the application.

## Before taking real money

Stripe requires a clear description of what is being sold; `DESCRIPTION` is
the field for it. A page that charges arbitrary amounts with no stated purpose
can get an account flagged. Test with `sk_test_` keys first.

## Notes

Deliberately ignores the repo's terminal house style — it was asked for in
lemon, Comic Sans and rainbow. Comic Neue loads from Google Fonts so it still
reads as Comic Sans on Linux and Android.
