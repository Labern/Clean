# Focus desktop app — GUI tests

    Focus.app/Contents/MacOS/Focus --selftest-gui            # all checks
    Focus.app/Contents/MacOS/Focus --selftest-gui --only=1,8 # some

All checks run off-screen: nothing is shown, no session starts, no app closes, so they're safe to run while he's at
the Mac. Each prints `gui: PASS|FAIL  n. what — detail`; the exit code is the number of failures. Settings a check
touches (Width, text size, the Focus Pro flag, text colour) are put back afterwards. The menu's own tests are still
`--selftest-stress` (see STRESS-TEST.md).

Every check that looks at the window runs in **both Light and Dark** (1, 8, 9, 12, 13, 14).

**Mechanical**
1. **The sidebar is never squashed at the opening size.** On a 14" MacBook screen with 0, 2, 4 and 6 modes, the
   window is drawn at the size it opens at, and the room between the sidebar's last row and its foot is measured in
   the picture (at least 12 pt).
2. **The opening size fits the screen.** Small, 14" and 27" screens, with 0, 4 and 10 modes, in Default and Minimal:
   never off-screen, never under the 600 × 420 minimum, and at least 1100 × 780 where there's room.
3. **Width options.** Default has 36 pt margins; Wide and Minimal have none. Only Minimal changes the window, by
   292 pt either way. Unset means Default.
4. **Text size.** One stop is one ⌘+. The label reads "Default", "Default +2" or "Default −1", and the size stops at
   0.8 and 1.6.
5. **The session line's path** starts at the top centre, sets off anticlockwise, and ends 2 pt past its start.
6. **The Buy button's words** in his chosen wording, singular and plural.
7. **The pressure squares** come in the same number each side, all between the edge and the title and clear of the
   key, with at least one each side on the narrowest button.
8. **Focus Pro** reads the purchase live (`focusTier`, the older `focusPro`, or an old "max" licence, which counts as Pro), and the box appears by the name in the drawn window.
9. **Colour.** The Appearance colour reaches the big button (measured in the picture), and Text colour is obeyed.
10. **The Manual** has nine sections, numbered down the Contents (1–5, then 6–9), and none of the wording he's
    removed ("this window", "Then F.", "Click to", "trial").
11. **Modes reorder** in the order the window and the menu list, and nothing starts.
12. **Every page draws** (Session, In session, Mode, Settings, Shortcuts, Tools, History, Manual, Feedback) at the
    smallest window and in each Width, without coming out blank.
13. **A tick on the button in a session:** in a session a filled tick-in-a-circle sits before "End Session" (a solid
    disc taller than any capital); out of a session there is none. Light and Dark.
14. **Light and Dark:** five pages (Feedback shades the page on purpose, so it is left out) in each look draw on the right ground (white or black), with a readable title.
15. **Basic's weekly sessions** are counted since Monday 00:00 (Quit All clean-ups don't count), reset next Monday
    00:00, and never go below zero.

16. **View As** shows the window as a Free or Pro user (an old "max" reads as Pro); Actual goes back to the real licence.

**Pricing** (pricing.json, from paradoxica.uk/focus/pricing.json, is the one source; the site is built from it)
17. **His price rules** (decided 2026-11-15) in the shipped copy: Basic (free) and Pro only. Pro is £5 a month,
    £50 a year (under 12 months) or £75 once (over a year). While the launch is on, the one-off is the early adopter
    gift at less than £75 (£50). Round numbers. Enterprise is listed as coming soon. 14 days of Pro. 10 sessions a
    week.
18. **The app uses the file:** the weekly count and the Preview's days come from it, and each plan's checkout link
    is `paradoxica.uk/focus/checkout/?tier=…&plan=…`.
19. **The shipped copy matches the live site.** If it differs, the site has moved on: refresh `focus/pricing.json`
    and release. Offline, it's noted, not failed.
20. **The Pro tags match the site's table:** Tools, Modes, History and custom shortcuts are limited on Free and
    included in Pro and Max; sessions a week reads 10 / Unlimited.
21. **Upgrade page and Basic unlock panel:** the Upgrade page draws in Light and Dark; History shows its unlock panel
    (a band at least 30 pt tall) as Basic and not as Pro.

**New touches**
22. **Type to add an app** finds apps on the Mac by name, open or not, best match first ("text" → TextEdit), and
    adding one that isn't open puts it in the session's apps.
23. **⌘Z** after ending a session is offered only within 20 seconds of the end, and never during a session.
24. **The window remembers its page** and reopens on it; the Session Editor is the default.
25. **Basic really locks Pro:** a Pro action (modes, tools, shortcuts, width, icon styles, colours) goes to the
    Upgrade page instead of happening; as Pro it happens. (Text colour is not Pro.)
26. **The big button's text always reads:** for every colour offered, plus plain white and black, whichever text colour
    is stored, the text it actually gets has contrast 3:1 or better. No white on white, no black on black.
27. **Light and Dark both read:** the default icon colour (previews, swatches), the plans' solid colour and the text
    on it all stand out from the page in each look.

**Not covered** (needs the real screen or a pointer): hover states, the hand cursor, drag to reorder, the pressure
build and release over time, the click line animating, ⌘Q/⌘H in a live window. Check these by eye.

28. **Becoming Pro removes every upgrade request:** open Upgrade as Basic, switch View As to Pro: the Upgrade page
    closes back to where it came from, nothing is locked, Upgrade can't reopen, Upgrade is never saved as the page,
    and Tools draws no plans as Pro.
29. **Out of sessions opens the plans:** Basic with the week's sessions used can't start one; the plans open headed
    "0 sessions remaining this week"; Pro is unlimited and closes them.
30. **A gap between Settings and Modes:** at least 10 pt of clear sidebar between them.
31. **The free reset:** at 0 on Basic with the gift unused, the gift shows before the plans; taking it gives the
    week's sessions back once; the next time out, the plans.
