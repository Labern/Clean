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

## 3. Pricing
- **Round numbers only: 5s and 0s, never 9s.** No pay-what-you-want. Never price by comparison with other apps.
- **Focus:** Basic £0 (10 sessions a week); Pro £5 a month / £50 a year / £75 once, with £50 once for early adopters (code EARLY: "if they're sneaky… I want them to feel they're clever"); Enterprise "Coming soon".
- **One source of truth:** a `pricing.json` on the site; the app ships a copy and refreshes it. Tests prove the two match.

## 4. Sign-in and data
- **Email is the only thing required.** Sign in with a code sent to the email. No phone number. A name only when the app needs one; a photo is optional.
- **"Absolutely NO excessive info requested or stored."** Ask the fewest times, never with a long series of forms.
- **"Done professionally — no AI junk. Watertight."**

## 5. Visual
- **Power, simplicity, style**, all three at once.
- **Clutter is the enemy, not the design.** When something feels wrong, remove; don't restyle. "It's not the DESIGN that's wrong — there's just too much clutter." And the opposite failure: "You've gone too far, again." When asked to tone something down, adjust that one thing, not everything.
- **Light mode is a first-class look,** not an inverted afterthought:
  - Solids are **soft grey, not black**.
  - **No shadows.**
  - Every preview and swatch must read on a light ground ("white on grey" was a bug).
- **No unreadable pairings, ever:** no white on white, no black on black. Enforce it in code (pick the readable text colour automatically) and in a test, for every colour offered.
- **Headings:** large, white, with a white line under.
- **Links always show the hand cursor.** Hover feedback on every unselected button.
- **Align to the content's own geometry** (the page, the column), not the window.
- **Wording:** plain, human, no AI phrasing ("What the fuck is this? Who wrote this?"). Copy the headings the product already uses, e.g. "Apps in Session". Don't put "click to" in labels.

## 6. Behaviour
- **Never change a fundamental behaviour without asking** (e.g. quit vs hide). Ask one plain question and wait.
- **Some things are sacred:** the session animation stays untouched without his explicit consent.
- **Category-standard features are mandatory:** ⌘Z undoes; the window remembers where it was.
- **Never lose the user's progress** across updates.
- **Rejected:** an end-of-session summary ("cringe"). Sound is undecided: build none until he decides.

## 7. Process
- **Done means seen** in the real app, both looks, as both Basic and Pro.
- **Every rule gets a test** where it can (contrast, pricing match, Pro locks, tag alignment, Light/Dark).
- **Fix the whole category, not the one instance:** "You should check and fix these kinds of issues."
- **Mockups as artifacts** before big visual decisions; he picks.
- **A developer "View As" panel** (Actual / Basic / Pro) to see every tier, and it must *really* lock what's locked: "You don't even have the app working."
- **Remember his decisions, criticisms and praise:** in this file and in CLAUDE.md.
