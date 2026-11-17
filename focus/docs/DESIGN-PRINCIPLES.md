# Labern's software design principles

Learned building Focus (Nov 2026). This is the playbook for shipping every PARADOX app with its site, its app and its payment system.
Each rule is his decision, criticism or praise, in his words where possible. Add to it; never delete. If a rule changes, strike it through and date it.

## 1. The core idea: fair, and a reward
- **The free tier is genuinely usable; payment unlocks the full thing.** "The app IS usable free — but the full features come with payment. It's fair and reasonable."
- **Upgrading is a reward, never a punishment.** "It should be a reward, not a punishment. This is a core part of my philosophy." Hover states on upgrade buttons get *more* inviting: they fill, lift or glow, and they never scold.
- **Limit how often, never what.** Basic gets 10 sessions a week; a session itself is never crippled.
- **Tease with taste.** Give free users a *tantalisingly small* number of tasteful options (e.g. 3 colours); the rest are visible, greyed and unlockable. The real draw of Pro is *total* customisation (any colour).
- **Let them see it before they buy.** A locked page opens and shows what it does, greyed beneath. "Don't make the app horrible. Let them open it to see what it will do."

## 2. The funnel
- **Praised: the Upgrade panel** (two cards, Basic and Pro, a Monthly/Yearly/Once switch, a gift badge, one Buy button, the code to copy). "This is FANTASTIC."
- **It isn't a pop-up; it's already on the screen.** A Pro page on Basic shows the plans right there, ready to check out, with the feature greyed beneath it.
- **Mark Pro things before they're clicked:** a small, quiet Pro tag, always in the same right-hand column. "It looks stupid if they're not in the same place."
- **Open on the lowest number** (Monthly).
- **"Current Plan", not "Your plan".**
- **Don't overwhelm at the point of sale:** no Enterprise strip in the in-app funnel.
- **Name the free tier, don't apologise for it:** "Basic", in a white outlined box beside the name. White, solid, is reserved for Pro: the reward.
- **Show the plan quietly, once:** two stacked lines above Feedback/Manual ("9 Sessions left this week" / "14 Days of Pro left"), with Upgrade Now to their right. They brighten only near the end.
- **Criticised:** a wide "X days remaining" button ("too wide… the whole problem"), "Pro" repeated everywhere ("so many times is fucking stupid"), counters after every heading ("stupid"), the Basic badge being too loud, and the countdown sharing the reward's white.
- **Research rule:** "Go online and find out what other apps do." Persistent means subtle; loud means closeable.

- **The upgrade flow is the product's story (2026-11-16):** "Use it > love it > run out > look to upgrade > see a better
  deal > buy. It's simple, ethical, and clear. This is the principle." Running out is a clear event: "0 sessions
  remaining this week — resets XX:XX", then the plans, with the small monthly number first and the permanent deal one
  click away. Waiting for the reset is always a fair choice.
- **Unlock messages are contextual and bigger:** say what this place unlocks ("Unlock your full session history by
  upgrading to Pro"), with a real button that isn't the main one.
- **Becoming Pro must remove every request to upgrade, instantly.** "Don't make me ask again."
- **Reward people who play around (BUILT 2026-11-16):** a one-time free weekly reset for first-time users who used
  their sessions up exploring, with a celebratory animation (10 tokens added, the count rising).

## 3. Pricing
- **Round numbers only: 5s and 0s, never 9s** — ~~for every price~~ for every price a buyer *pays*. **Exception (his
  call, 17 Nov 2026):** the one-off's list price is **£99**, an anchor struck through beside the **£50** early-adopter
  price (code EARLY = −£49), so £50 reads as half price and equals one year of Yearly: "yours forever" for a year's money. No pay-what-you-want. Never price by comparison with other apps.
- **Focus:** Basic £0 (10 sessions a week); Pro £5 a month / £50 a year / ~~£75~~ **£99** once (17 Nov), with £50 once for early adopters (code EARLY: "if they're sneaky… I want them to feel they're clever"); Enterprise "Coming soon".
- **One source of truth:** a `pricing.json` on the site; the app ships a copy and refreshes it. Tests prove the two match.

## 4. Sign-in and data
- **Email is the only thing required.** Sign in with a code sent to the email. No phone number. A name only when the app needs one; a photo is optional.
- **"Absolutely NO excessive info requested or stored."** Ask the fewest times, never with a long series of forms.
- **"Done professionally — no AI junk. Watertight."**

- **Never ask for what you already have** (2026-11-16): the email was given at sign-up, so no form asks again; and no
  small print explaining what a form sends.
- **Help and feedback (2026-11-16):** every app under the brand sends to **help@paradoxica.co.uk**. Subject: the app's
  name in capitals, a space, then the rest ("FOCUS The Dock icon stayed"). The user's email address always travels with
  it, taken from their account: they gave it at sign-up, so a form never asks again ("You idiot", 2026-11-16).

## 5. Visual
- **Power, simplicity, style**, all three at once.
- **Clutter is the enemy, not the design.** When something feels wrong, remove; don't restyle. "It's not the DESIGN that's wrong — there's just too much clutter." And the opposite failure: "You've gone too far, again." When asked to tone something down, adjust that one thing, not everything.
- **Light mode is a first-class look,** not an inverted afterthought:
  - Solids are **soft grey, not black**.
  - **No shadows.**
  - Every preview and swatch must read on a light ground ("white on grey" was a bug).
- **No unreadable pairings, ever:** no white on white, no black on black. Enforce it in code (pick the readable text colour automatically) and in a test, for every colour offered.
- **Every window matches the app** (2026-11-16): no stock system windows, lists or switches beside the custom UI.
- **Adding comes after the list,** not above it.
- **Headings:** large, white, with a white line under.
- **Links always show the hand cursor.** Hover feedback on every unselected button.
- **Align to the content's own geometry** (the page, the column), not the window.
- **Wording:** plain, human, no AI phrasing ("What the fuck is this? Who wrote this?"). Copy the headings the product already uses, e.g. "Apps in Session". Don't put "click to" in labels.

## 6. Behaviour
- **Never change a fundamental behaviour without asking** (e.g. quit vs hide). Ask one plain question and wait.
- **Some things are sacred:** the session animation stays untouched without his explicit consent.
- **Category-standard features are mandatory:** ⌘Z undoes; the window remembers where it was.
- **Never lose the user's progress** across updates.
- **Show what's happening, live, where people look:** under the session button, "Closing Safari… 2 of 6", app by app
  like a terminal, then "Session started". A button press must visibly change the button (a tick in a circle).
- **Delicate features wait for the wording:** hiding the app itself (Pro) goes under critical system processes only
  with very careful words ("Do you want to hide this app? Use menu or shortcut to end session"). Not yet.
- **Rejected:** an end-of-session summary ("cringe"). Sound is undecided: build none until he decides.

## 7. Process
- **Never ask him to run a command (2026-11-16):** "I don't ever want to have to run anything in the command line… Do it
  your fucking self." Anything a terminal can do, Claude does.
- **When he gives an order, follow it exactly, in his order** ("light and dark first, then colours, then icon").
- **Done means seen** in the real app, both looks, as both Basic and Pro.
- **Spacing regressions are flaws, not details:** "This is a flaw that crept in. Don't let this happen." Guard layout
  (gaps, alignment) with tests.
- **Visualisations must explain themselves:** thick enough to read, labelled, linked to the list on hover, and optional.
- **Tests never touch the user's real settings** without restoring them.
- **A test must measure the real thing:** a check that passes while the feature is missing is worse than none.
- **Every rule gets a test** where it can (contrast, pricing match, Pro locks, tag alignment, Light/Dark).
- **Fix the whole category, not the one instance:** "You should check and fix these kinds of issues."
- **Mockups as artifacts** before big visual decisions; he picks.
- **A developer "View As" panel** (Actual / Basic / Pro) to see every tier, and it must *really* lock what's locked: "You don't even have the app working."
- **Remember his decisions, criticisms and praise:** in this file and in CLAUDE.md.
