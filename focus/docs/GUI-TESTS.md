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
8. **Focus Pro / Max** read the purchase live (`focusTier`, or the older `focusPro`), and the white box appears by the name in the drawn window.
9. **Colour.** The Appearance colour reaches the big button (measured in the picture), and Text colour is obeyed.
10. **The Manual** has nine sections, numbered down the Contents (1–5, then 6–9), and none of the wording he's
    removed ("this window", "Then F.", "Click to", "trial").
11. **Modes reorder** in the order the window and the menu list, and nothing starts.
12. **Every page draws** (Session, In session, Mode, Settings, Shortcuts, Tools, History, Manual, Feedback) at the
    smallest window and in each Width, without coming out blank.
13. **The Focus mark** shows on the big button, right of the title, during a session.
14. **Light and Dark:** five pages (Feedback shades the page on purpose, so it is left out) in each look draw on the right ground (white or black), with a readable title.
15. **Basic's weekly sessions** are counted since Monday 00:00 (Quit All clean-ups don't count), reset next Monday
    00:00, and never go below zero.

16. **View As** (View menu) shows the window as a Free, Pro or Max user; Actual goes back to the real licence.

**Not covered** (needs the real screen or a pointer): hover states, the hand cursor, drag to reorder, the pressure
build and release over time, the click line animating, ⌘Q/⌘H in a live window. Check these by eye.
