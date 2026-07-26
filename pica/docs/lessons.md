# Lessons — what building PICA taught us

*One session, one app. These are the lessons worth keeping: first the craft, then the
collaboration. Companion to `BUILD-CONVERSATION.md` (the record) and `TEN-THINGS.md`
(the person).*

## What we learned building the thing

1. **Pick one impossible-sounding acceptance test and never let it go.** "The output,
   when complete, should be identical" became a machine gate: 5,907/5,907 lines of
   Tenet, run before every ship. Every later feature had to pass under it, which is why
   the core never regressed while the app grew twentyfold around it.

2. **Ground truth beats memory, every time.** The Final Draft grammar wasn't
   remembered or googled into shape — it was read out of FD's own shipped template
   (`ReturnKey=` in the XML) and its manual. Two independent research passes agreed
   before a line of grammar code changed. When a spacing question came up later, the
   answer came from the same template (72pt margins), not intuition.

3. **Real-world input is a bestiary; classify by evidence, not format.** Production
   drafts carry revision headers, scene-number gutters, CONTINUED markers, provenance
   stamps, bare page numbers, smeared glyph origins, and fonts with no character map at
   all. The robust detectors keyed on *behaviour* (repeats at the same height across
   pages; a gutter where nearly everything is a number) rather than on any format
   guess — and one of them ended up cracking substitution-ciphered text statistically.

4. **The bug you can't reproduce is an environment difference.** "Blank imports" passed
   in every fresh test and failed only on the real machine — because the real machine's
   localStorage was full. WebKit's ~5MB quota silently rejected saves while the index
   still recorded them. Lesson: test against *filled* state, and when a save can fail,
   it must say so and record nothing.

5. **WKWebView keeps a little list of betrayals.** `evaluateJavaScript` silently drops
   screenplay-sized base64 arguments; `confirm()`/`prompt()` return false/nil without
   dialog delegates; Escape dies in the responder chain before the DOM; new-tab clicks
   go nowhere without a UI delegate; iCloud-synced folders re-tag files mid-codesign.
   Every one was found by reproducing, and each fix now lives in a permanent test.

6. **Make the screen the artifact.** Rendering every wrapped line at its true pt
   coordinates means screen, print, export and source PDF are one layout — WYSIWYG by
   construction, not by promise. The model owns all editing; contenteditable is only a
   caret.

7. **Never lose a word — structurally, not aspirationally.** IndexedDB for bodies,
   synchronous index metadata with rollback, snapshots inside the ring, drafts inside
   the document itself, an emergency mirror on the way out, and a reader mode whose
   edit-lock sits at the model layer so no code path can slip past it.

8. **Automate the checking of what the user reported.** Every bug he found — parenthetical
   Tab, index delete via the real right-click sequence, the grammar table — became a
   permanent machine check the same day. "Don't make me manually test all of this" is a
   spec, and it was met with a suite that drives the real UI headlessly.

9. **Small aligned touches out-punch features.** The single most-praised moment wasn't
   an engine feat — it was centring the title over the *page* instead of the window.
   Anchor chrome to the content's own geometry.

10. **Ship to the surface the user actually lives on.** The native app is the thing he
    uses: every change built, installed and relaunched there first, web second — and
    nothing called done until he could see it running.

## What Claude learned about working with Labern

- **Corrections are the steering wheel.** Terse, sometimes sharp ("hideous",
  "diabolical", "you fucked up") — and always containing the exact spec. Build the
  named thing immediately; don't defend, don't mourn.
- **Never build past the ask.** The one unrequested feature (an index filter) was
  ordered removed on sight. Propose freely, ship only what's confirmed.
- **He is the QA loop, live.** He exercised every feature within minutes and found
  real bugs each time. Expect it; make his findings permanent tests.
- **Defaults off, options on.** Chrome earns its place: every element of the interface
  ended up individually toggleable, minimal by default, everything reversible —
  "if I revert, just undo all."
- **Honesty converts directly into work.** Admitting what was actually broken (my
  test bypassed the bug; the quota was the cause; FD still does revisions better) was
  never punished and always turned into the next order.
- **The instrument matters as much as the tool.** Reader mode's melt, the one-sheet,
  the redacted icon — he wants power wearing a considered face. Power, simplicity,
  and style, all three at once.
