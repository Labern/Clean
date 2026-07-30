// ─────────────────────────────────────────────────────────────────────────────
// THE TITLE BEGINS WHERE THE CHARACTER NAMES BEGIN.
//
// The title's FIRST CHARACTER sits on the character-cue column — the x every cue
// starts at (3.5" on Final Draft's grid). Cues all share that x, so it is a hard
// vertical line down the script.
//
// It is NOT centred on the cues' optical centre. That was the bug: it left the
// title's left edge ~95px off the column even though the centres agreed to 1.7px.
//
// The old check compared the title against the same formula that positioned it,
// so it could only agree with itself. This measures a cue as actually DRAWN.
//
// RUN
//   ./mac/build.sh --install                              (a red result blocks it)
//   node tests/chrome-run.mjs title-audit.js __titleAudit
//
// Returns 'aligned', or 'OFF <reading> …'.
// Comments explain the syntax, each construct the first time it appears.
// ─────────────────────────────────────────────────────────────────────────────

// ASSIGNMENT   target = expression ;
//   `=` assigns. (Equality is `===`.) Dot notation `a.b` names a property, and
//   assigning to one that doesn't exist creates it. `window` is the browser's
//   global object, so this hangs the function where the harnesses can find it.
//
// FUNCTION EXPRESSION   function ( params ) { body }
//   A function used as a value. `async` makes it return a Promise and allows
//   `await` inside. Empty `()` = no parameters.
window.__titleAudit = async function () {

  // CONST   const name = expression ;
  //   Binds a name once; it can't be reassigned (`let` can, `var` is obsolete).
  //   It freezes the NAME, not the value — an object's insides can still change.
  //   Block-scoped: it exists only inside the nearest `{ }`.
  const T = window.PICA_API.test;
  const API = window.PICA_API;

  // ARROW FUNCTION   params => expression   |   params => { statements }
  //   One parameter needs no parentheses. A bare expression is returned
  //   automatically; a `{ }` body returns only where `return` says so.
  //
  // NEW   new Constructor( args )
  //   A Promise is work that finishes later. `await wait(40)` pauses 40ms.
  //   setTimeout, not requestAnimationFrame: rAF never fires in a windowless
  //   WKWebView, so an rAF wait would hang rather than fail.
  const wait = ms => new Promise(r => setTimeout(r, ms));

  // Number literal — no quotes, so a number rather than text.
  const TOLERANCE = 1.5;

  // ── the measurement ────────────────────────────────────────────────────────
  // Returns a number (the distance) or a string (why it couldn't measure).

  const gap = () => {

    // CALL EXPRESSION   object.method( args )
    //   `const tEl` declares · `=` assigns · `document` is the page ·
    //   `.getElementById` is a function on it · `('docTitle')` invokes it with
    //   one argument. Returns the element, or `null` if there is none.
    const tEl = document.getElementById('docTitle');

    // IF   if ( condition ) statement          — braces optional for one statement
    // NOT  ! expression                        — flips truthiness
    //   Falsy: null, undefined, 0, NaN, '', false. So `!tEl` = "no element".
    // RETURN   return expression ;             — exits the function now
    if (!tEl) return 'no-title';

    // Nested calls run inside-out: getComputedStyle gives the styles in force,
    // `.paddingLeft` is a string like "11.2px", parseFloat pulls out 11.2.
    //
    // OR   a || b
    //   Yields `a` if truthy, else `b` — the standard "default if missing" idiom,
    //   because parseFloat returns NaN (falsy) when there is no number.
    const padL = parseFloat(getComputedStyle(tEl).paddingLeft) || 0;

    // getBoundingClientRect() asks where the element really is on screen now.
    // Plus the padding = the x of the first CHARACTER, since the glyph starts
    // inside the box.
    const textLeft = tEl.getBoundingClientRect().left + padL;

    // The document model: an array of the elements the script is made of.
    const els = window.__pica.doc.elements;

    // FOR-OF   for ( const name of iterable ) { body }
    //   Walks values. (`for...in` walks keys — wrong tool here.)
    //   Selector: `#pages` = that id · space = "inside it" · `div[data-el]` =
    //   any div HAVING a data-el attribute, which is how a drawn line is marked.
    for (const d of document.querySelectorAll('#pages div[data-el]')) {

      // `.find(cb)` returns the first item the callback likes, else undefined.
      // STRICT EQUALITY  a === b   — same type and value. Never use `==`.
      // `d.dataset.el` reads the data-el attribute (data-foo-bar → fooBar).
      const el = els.find(e => e.id === d.dataset.el);

      // `||` chains three conditions. `!==` is the negation of `===`.
      // CONTINUE   continue ;   — abandon this pass, start the next.
      // Skip unidentifiable lines, non-cues, and dual cues (own geometry).
      if (!el || el.type !== 'character' || el.dual) continue;

      const r = d.getBoundingClientRect();

      // `r.width` as a condition uses truthiness: 0 is falsy, so "if laid out".
      // Math.abs makes the distance positive either way. Returning here ends the
      // loop and the function — every cue shares this edge, so one reading does.
      if (r.width) return Math.abs(textLeft - r.left);
    }

    // Only reached if no cue was found. A string, not a number — the verdict
    // treats that as a failure: a measurement that never happened isn't a pass.
    return 'no-cue';
  };

  // ARRAY LITERAL   [ ]
  //   `const` yet we push to it below: const freezes the binding, not contents.
  const readings = [];

  // const note = why => { … };
  //   `const note` declares · `=` assigns · `why` is the one parameter ·
  //   `=>` "is a function that does" · `{ }` a block body, returning nothing —
  //   it exists for its side effect of appending to `readings`.
  const note = why => {

    // `()` = no arguments. `g` holds a number or a string.
    const g = gap();

    // TYPEOF     typeof x        — names the kind of value: 'number', 'string'…
    // TERNARY    c ? a : b       — the only three-operand operator
    // toFixed(1) formats a number to 1dp, returning a STRING.
    // `+` between strings concatenates → 'zoomed-in=62.0'.
    // `.push` appends, changing the array in place (unlike filter, which copies).
    readings.push(why + '=' + (typeof g === 'number' ? g.toFixed(1) : g));
  };

  // ── build a script with cues in it ─────────────────────────────────────────
  // Two very different name lengths: the old bug moved the axis with the average
  // cue length, so a mix is what exposes it.

  // AWAIT   await expression
  //   Only inside `async`. Pauses until the promise settles — without it the next
  //   line would run while the document was still being replaced.
  await T.reset();

  T.caret(0, 0);                  // two arguments: element 0, offset 0
  T.type('INT. ROOM - DAY');      // typing "int." promotes it to a Scene Heading
  T.esc();                        // dismiss the autocomplete the slug opened

  T.enter();                      // off a slug, the grammar gives Action
  T.type('A door.');
  T.esc();

  T.enter();
  T.tab(false);                   // BOOLEAN LITERAL: not Shift+Tab. Tab in a
                                  // blank Action makes it a Character cue.
  T.type('SAM');                  // the short cue — 3 characters
  T.esc();

  T.enter();                      // off a cue, Dialogue
  T.type('One.');
  T.esc();

  T.enter();
  T.tab(false);
  T.type('ALEXANDRA-JANE');       // the long cue — 14 against SAM's 3
  T.esc();

  T.enter();
  T.type('Two.');
  T.esc();

  await wait(40);                 // let it repaginate and redraw
  note('typed');                  // reading 1: at rest

  // ── everything that moves the page under the title ─────────────────────────
  // The title is in the header, the cues on the page. Anything that shifts or
  // rescales the page must move the title with it.

  // Three statements on one line, separated by semicolons: change, wait, measure.
  // The sidebar takes horizontal space, so hiding it slides the page sideways.
  API.toggleRail(); await wait(40); note('rail-hidden');
  API.toggleRail(); await wait(40); note('rail-shown');

  // The axis is in page points times the zoom, so a bad multiplication only
  // shows once zoom isn't 1. `-0.24` is a negative literal: net -0.12.
  API.zoom(0.12);  await wait(30); note('zoomed-in');
  API.zoom(-0.24); await wait(30); note('zoomed-out');
  API.zoomFit();   await wait(30); note('zoom-fit');

  // A title page inserts a page BEFORE the script, shifting every page index —
  // and the positioning code finds its page by index.
  API.toggleTitlePage(); await wait(40); note('titlepage-on');
  API.toggleTitlePage(); await wait(40); note('titlepage-off');

  const canvas = document.getElementById('canvas');

  // PROPERTY ASSIGNMENT   object.property = expression ;
  //   Writing a DOM property has an EFFECT: this really scrolls the container.
  canvas.scrollTop = 140; await wait(40); note('scrolled');
  canvas.scrollTop = 0;   await wait(30);

  // ── a long title must still BEGIN on the column ────────────────────────────
  // Where centring fails hardest: a centred box grows both ways, so its left edge
  // walks further left the longer the title — 167px here against 53px above.

  const was = window.__pica.doc.title;

  window.__pica.doc.title = 'A VERY LONG TITLE INDEED THAT KEEPS GOING';

  // `textContent` sets an element's TEXT. (`innerHTML` would parse it as HTML —
  // never use that for plain text.)
  document.getElementById('docTitle').textContent = window.__pica.doc.title;

  API.zoomFit();                  // forces the re-render that repositions it
  await wait(40);
  note('long-title');

  window.__pica.doc.title = was;  // leave the document exactly as found
  document.getElementById('docTitle').textContent = was;
  API.zoomFit(); await wait(30);

  // ── and it must not be achieved by centring ────────────────────────────────
  // Structural, not measured: every reading could pass while a CSS change made
  // the alignment coincidence rather than contract.

  const cs = getComputedStyle(document.getElementById('docTitle'));

  // AND   a && b   — truthy only if both; short-circuits, so `b` may never run.
  //   The bracketed part describes CORRECT. The leading `!` inverts it, so the
  //   name reads as the fault: `centred` is true when the layout is wrong.
  //   Two spellings of "no transform" — browsers report either the keyword or
  //   the identity matrix. A statement may break across lines until its `;`.
  const centred = !(cs.textAlign === 'left'
    && (cs.transform === 'none'
      || cs.transform === 'matrix(1, 0, 0, 1, 0, 0)'));

  // ── the verdict ────────────────────────────────────────────────────────────

  // `.filter(cb)` returns a NEW array of the items the callback liked.
  const failed = readings.filter(r => {

    // indexOf gives the position of the first '='; slice takes from there on.
    // `+ 1` steps past it. So 'zoomed-in=62.0' → '62.0'.
    const v = r.slice(r.indexOf('=') + 1);

    // REGEX LITERAL   /pattern/
    //   Slashes, not quotes. `^` start · `[\d.]` digit or dot · `+` one or more ·
    //   `$` end. So `.test(v)` asks "purely numeric?".
    //   `!` inverts it: 'no-cue' is a FAILURE, not a skip.
    return !/^[\d.]+$/.test(v) || parseFloat(v) >= TOLERANCE;
  });

  // `.length` is the item count; 0 is falsy, so this reads "nothing failed".
  if (!failed.length && !centred) return 'aligned';

  // Otherwise hand back every reading, naming the condition and the distance.
  // `.join(' ')` glues an array into one string.
  return 'OFF ' + readings.join(' ') + (centred ? ' · placed by centring, not by edge' : '');
};
