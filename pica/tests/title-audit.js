// ─────────────────────────────────────────────────────────────────────────────
// THE TITLE BEGINS WHERE THE CHARACTER NAMES BEGIN.
//
// The contract: the screenplay title's FIRST CHARACTER sits on the character-cue
// column — the same x every cue starts at (3.5" on Final Draft's grid). Every cue
// shares that x exactly, so it is a hard vertical line down the script.
//
// It is NOT centred on the cues' optical centre. That was the bug: it put the
// title's left edge ~95px left of the column, so nothing shared an edge even
// though the centres agreed to 1.7px.
//
// The check this replaced compared the title against the same formula that
// positioned it, so it could only ever agree with itself. This one measures
// against a cue as actually DRAWN. Never test a placement against its own arithmetic.
//
// RUN IT
//   every install:  ./mac/build.sh --install   (a red result refuses the install)
//   by hand:        node tests/chrome-run.mjs title-audit.js __titleAudit
//
// The comments teach the SYNTAX. Each construct is explained the first time it
// appears; after that only what is new on the line is called out.
// ─────────────────────────────────────────────────────────────────────────────

// ASSIGNMENT STATEMENT.  Grammar:  target = expression ;
//   The `=` is assignment, not equality (equality is `===`). The expression on the
//   right is evaluated, and the result is stored in the target on the left.
//   Every statement ends in a semicolon.
// `window` is an object supplied by the browser — the global object. `window.__titleAudit`
// uses DOT NOTATION (`object.property`) to name a property on it; assigning to a property
// that does not exist yet CREATES it. So this hangs our function off the global object,
// which is how the harnesses reach it after injecting this file.
//
// FUNCTION EXPRESSION.  Grammar:  function ( parameters ) { body }
//   Used as a value here rather than declared with a name — the name it is stored under
//   is enough. `async` in front changes two things: the function now always returns a
//   Promise, and the keyword `await` becomes legal inside it. The parentheses are empty
//   because this function takes no arguments. `{` opens the body; the matching `}` at the
//   very bottom of the file closes it.
window.__titleAudit = async function () {
  // DECLARATION with `const`.  Grammar:  const name = expression ;
  //   `const` creates a name and BINDS it to a value, once. The binding cannot be
  //   reassigned afterwards — `T = something` later would throw. (`let` makes a binding
  //   you may reassign; `var` is the obsolete third form, avoid it.) A `const` binding
  //   only protects the NAME: if the value is an object, the object's insides can still
  //   change. Bindings are block-scoped — they exist only inside the nearest `{ }`.
  // Here: read the property `test` of the object `PICA_API`, which is itself a property of
  // `window`, and bind the result to the name `T`. Dot notation chains left to right.
  const T = window.PICA_API.test;
  // Same grammar, no new syntax: a shorter alias for the app's public surface.
  const API = window.PICA_API;
  // ARROW FUNCTION.  Grammar:  parameters => expression      (a "concise body")
  //                       or:  parameters => { statements }  (a "block body")
  //   With one parameter the parentheses may be dropped, so `ms => …` means "a function
  //   taking one argument called ms". With a concise body the expression's value is
  //   returned automatically — there is no `return` keyword and there must be no braces.
  // NEW OPERATOR.  Grammar:  new Constructor( arguments )
  //   Builds an object from a constructor. `Promise` takes one argument: a function which
  //   itself receives a function to call when the work is done (named `r` here).
  // So: `wait` is a function that, given a number of milliseconds, returns a Promise that
  // settles after that long. Deliberately setTimeout and not requestAnimationFrame —
  // rAF never fires in a windowless WKWebView, so an rAF wait would hang, not fail.
  const wait = ms => new Promise(r => setTimeout(r, ms));
  // NUMBER LITERAL. No quotes, so this is the number 1.5 rather than the text "1.5".
  // SCREAMING_CASE carries no meaning to the language; it is a convention for "fixed setting".
  const TOLERANCE = 1.5;

  // ── the measurement ──────────────────────────────────────────────────────────

  // An arrow function with EMPTY parameters — `()` is required when there are none — and a
  // BLOCK body, so its statements run in order and it returns only where `return` says so.
  const gap = () => {
    // Taking the line you asked about apart:
    //   const   — declare a new binding (see above)
    //   tEl     — the name being bound; an identifier of your choosing
    //   =       — assignment
    //   document                  — an object the browser provides: the page itself
    //   .getElementById           — dot notation naming a FUNCTION stored on that object
    //   ('docTitle')              — CALL EXPRESSION: parentheses invoke it, and the text
    //                               in quotes is the one argument passed in
    //   ;       — end of statement
    // A method call is an expression: it evaluates to whatever the function hands back.
    // `getElementById` searches the page for an element whose id attribute is "docTitle"
    // and returns that element object — or `null` if there is no such element.
    const tEl = document.getElementById('docTitle');
    // IF STATEMENT.  Grammar:  if ( condition ) statement
    //   Braces may be omitted when the body is a single statement, as here.
    // LOGICAL NOT.  Grammar:  ! expression
    //   Flips a value to the opposite boolean. JavaScript does not require a real boolean:
    //   every value is "truthy" or "falsy". `null`, `undefined`, `0`, `NaN`, `''` and
    //   `false` are falsy; everything else is truthy. So `!tEl` reads "tEl is missing".
    // RETURN STATEMENT.  Grammar:  return expression ;
    //   Ends the function immediately and hands the expression back to the caller.
    if (!tEl) return 'no-title';
    // NESTED CALLS. Grammar is just substitution: the inner call runs first and its result
    // becomes the input to the outer one. Read right to left:
    //   getComputedStyle(tEl)  → an object of every style in force on the element
    //   .paddingLeft           → one of its properties, a STRING such as "11.2px"
    //   parseFloat( … )        → reads the leading number out of that string → 11.2
    // LOGICAL OR.  Grammar:  a || b
    //   Evaluates to `a` if `a` is truthy, otherwise to `b`. It yields the VALUE, not a
    //   boolean, which is why `x || 0` is the standard "default if missing" idiom —
    //   `parseFloat` returns `NaN` (falsy) when there is no number to find.
    const padL = parseFloat(getComputedStyle(tEl).paddingLeft) || 0;
    // Method call, then a property read, then arithmetic. `+` on two numbers adds them.
    // `getBoundingClientRect()` asks the browser where the element really is on screen
    // right now, returning an object with left/top/width/height in CSS pixels. Adding the
    // padding gives the x of the first CHARACTER, because the glyph starts inside the box.
    const textLeft = tEl.getBoundingClientRect().left + padL;
    // Property chain, three deep. `elements` is an ARRAY — an ordered list — of the objects
    // the script is made of.
    const els = window.__pica.doc.elements;
    // FOR-OF LOOP.  Grammar:  for ( const name of iterable ) { body }
    //   Runs the body once per value in the iterable, binding each value to `name` in turn.
    //   (`for...in` is a different statement that walks KEYS — the wrong tool here.)
    //   The `const` inside the parentheses is a fresh binding on every pass.
    // `querySelectorAll` takes a CSS SELECTOR as text and returns every matching element.
    //   `#pages`      — the element whose id is "pages"
    //   ` `           — a space means "somewhere inside that"
    //   `div[data-el]` — any <div> that HAS an attribute called data-el
    for (const d of document.querySelectorAll('#pages div[data-el]')) {
      // `.find(callback)` is a method on arrays. It calls the callback once per item and
      // returns the FIRST item for which the callback is truthy — or `undefined` if none is.
      // The callback here is an arrow function: parameter `e`, concise body, so its
      // comparison is returned automatically.
      // STRICT EQUALITY.  Grammar:  a === b
      //   True when both are the same type AND the same value. Always prefer it to `==`,
      //   which converts types first and produces surprises.
      // `d.dataset.el` reads the element's `data-el` attribute: the browser exposes every
      // `data-*` attribute on a `dataset` object, converting data-foo-bar to fooBar.
      const el = els.find(e => e.id === d.dataset.el);
      // Three conditions joined by `||`, so the body runs if ANY of them holds.
      // STRICT INEQUALITY `!==` is the negation of `===`.
      // CONTINUE STATEMENT.  Grammar:  continue ;
      //   Abandons this pass of the loop and starts the next one.
      // Meaning: skip lines we cannot identify, lines that are not character cues, and
      // dual-dialogue cues, which sit in their own two-column geometry and would mislead.
      if (!el || el.type !== 'character' || el.dual) continue;
      // Where this cue is actually drawn.
      const r = d.getBoundingClientRect();
      // `r.width` used directly as a condition relies on truthiness: 0 is falsy, so this
      // reads "if it has any width", i.e. if it is really laid out.
      // `Math` is a built-in object of maths functions; `abs` returns a value's distance
      // from zero, so the result is positive whichever side the title fell on.
      // Returning inside a loop ends the loop AND the function — one good reading suffices.
      if (r.width) return Math.abs(textLeft - r.left);
    }
    // Reached only if the loop completed without finding a cue. A STRING is returned where
    // the other exit returns a NUMBER; the verdict below distinguishes them, and treats
    // this as a failure — a measurement that never happened must not read as success.
    return 'no-cue';
  };

  // ARRAY LITERAL.  Grammar:  [ ] or [ item, item, … ]
  //   Creates an ordered list; `[]` is an empty one. Note this is `const` yet we add to it
  //   below: `const` freezes the BINDING, never the object's contents.
  const readings = [];
  // The other line you asked about. Its shape is:
  //   const note = why => { … };
  //   ├ const note      — declare the binding `note`
  //   ├ =               — assign to it
  //   ├ why             — the arrow function's single parameter (no parentheses needed)
  //   ├ =>              — "is a function that does"
  //   └ { … }           — a BLOCK body: statements, and nothing is returned unless a
  //                       `return` says so. This one returns nothing; it exists for its
  //                       side effect of appending to `readings`.
  const note = why => {
    // Call `gap()` and keep its answer. `()` with nothing inside means "no arguments".
    // `g` therefore holds EITHER a number (a distance) or a string (a reason).
    const g = gap();
    // One statement, four pieces of grammar. Innermost first:
    //   typeof g            — TYPEOF OPERATOR. Grammar: typeof expression. Yields a string
    //                         naming the kind of value: 'number', 'string', 'object'…
    //   … === 'number'      — strict equality against that string, so: "is g a number?"
    //   cond ? a : b        — CONDITIONAL (TERNARY) OPERATOR, the only operator taking
    //                         three operands. If the condition is truthy it evaluates to
    //                         `a`, otherwise to `b`. Here: format the number, or pass the
    //                         reason string through untouched.
    //   g.toFixed(1)        — a method on numbers: format to one decimal place, returning
    //                         a STRING ('62' becomes '62.0').
    //   why + '=' + …       — `+` between strings CONCATENATES them. Because one side is a
    //                         string, JavaScript converts the other side to a string too.
    //                         So this builds text like 'zoomed-in=62.0'.
    //   readings.push( … )  — a method on arrays: append the value to the end. It changes
    //                         the array in place (unlike `filter` further down, which
    //                         builds a new one).
    readings.push(why + '=' + (typeof g === 'number' ? g.toFixed(1) : g));
  };

  // ── build a script that has cues in it ───────────────────────────────────────
  // Two names of very different lengths: the old centring bug moved the axis with the
  // average cue length, so a mix of long and short is what exposes it.

  // AWAIT OPERATOR.  Grammar:  await expression
  //   Legal only inside an `async` function. Pauses this function until the promise the
  //   expression produces settles, then continues with its value. Without it the next line
  //   would run while the document was still being replaced.
  await T.reset();
  // A call with two arguments, separated by a comma: put the caret in element 0, offset 0.
  T.caret(0, 0);
  // A single string argument. Typing "int." makes the app promote this to a Scene Heading.
  T.type('INT. ROOM - DAY');
  // No arguments: dismiss the autocomplete popup the slugline opened.
  T.esc();
  // Press Enter. Off a slug, the app's grammar hands you an Action element.
  T.enter();
  T.type('A door.');
  T.esc();
  // Enter off Action gives another Action…
  T.enter();
  // BOOLEAN LITERAL. `false` and `true` are values of their own type. Here it means
  // "not Shift+Tab". Tab in a BLANK Action converts it into a Character cue.
  T.tab(false);
  // The short cue — 3 characters.
  T.type('SAM');
  T.esc();
  // Enter off a cue gives Dialogue.
  T.enter();
  T.type('One.');
  T.esc();
  T.enter();
  T.tab(false);
  // The long cue — 14 characters against SAM's 3.
  T.type('ALEXANDRA-JANE');
  T.esc();
  T.enter();
  T.type('Two.');
  T.esc();
  // Pause 40ms so the app can repaginate and redraw before anything is measured.
  await wait(40);
  // Reading 1: at rest, freshly typed.
  note('typed');

  // ── everything that moves the page under the title ──────────────────────────
  // The title sits in the header, the cues on the page. Anything that shifts or rescales
  // the page must move the title with it, or the two part company.

  // Three statements on ONE line, separated by semicolons — legal, and done here because
  // they are one thought: change something, wait for the redraw, measure. The sidebar
  // occupies horizontal space, so hiding it slides the whole page sideways.
  API.toggleRail(); await wait(40); note('rail-hidden');
  // And back, which must RESTORE the alignment, not merely avoid breaking it.
  API.toggleRail(); await wait(40); note('rail-shown');

  // The axis is held in page points and multiplied by the zoom factor, so a wrong
  // multiplication stays invisible until the zoom is something other than 1.
  API.zoom(0.12);  await wait(30); note('zoomed-in');
  // UNARY MINUS: `-0.24` is a negative number literal. Net -0.12, so both directions run.
  API.zoom(-0.24); await wait(30); note('zoomed-out');
  API.zoomFit();   await wait(30); note('zoom-fit');

  // Showing the title page inserts a page BEFORE the script, shifting every page index —
  // and the positioning code finds the page it measures against by index.
  API.toggleTitlePage(); await wait(40); note('titlepage-on');
  API.toggleTitlePage(); await wait(40); note('titlepage-off');

  const canvas = document.getElementById('canvas');
  // PROPERTY ASSIGNMENT.  Grammar:  object.property = expression ;
  //   Writing to a DOM property is not just bookkeeping — the browser acts on it, so this
  //   genuinely scrolls the container, exactly as a wheel would.
  canvas.scrollTop = 140; await wait(40); note('scrolled');
  // Put the scroll back, so the next condition starts from a known state.
  canvas.scrollTop = 0;   await wait(30);

  // ── a long title must still BEGIN on the column ─────────────────────────────
  // The condition centring fails hardest: a centred box grows in BOTH directions, so its
  // left edge walks further left the longer the title gets — 167px here against 53px above.

  // Keep the real title so it can be restored; a test must not leave the document altered.
  const was = window.__pica.doc.title;
  // Write to the model…
  window.__pica.doc.title = 'A VERY LONG TITLE INDEED THAT KEEPS GOING';
  // …and to the visible element. `textContent` sets an element's TEXT. (`innerHTML` would
  // parse the string as HTML — never use it for plain text.)
  document.getElementById('docTitle').textContent = window.__pica.doc.title;
  // Force a full re-render, which is what repositions the title.
  API.zoomFit();
  await wait(40);
  note('long-title');
  // Restore both, exactly as found.
  window.__pica.doc.title = was;
  document.getElementById('docTitle').textContent = was;
  API.zoomFit(); await wait(30);

  // ── and it must not be achieved by centring ─────────────────────────────────
  // A structural check rather than a measurement: even with every reading above passing, a
  // CSS change back to a centred box would make the alignment coincidence, not contract.

  const cs = getComputedStyle(document.getElementById('docTitle'));
  // Read this inside-out.
  //   The bracketed expression describes what CORRECT looks like.
  //   LOGICAL AND.  Grammar:  a && b
  //     Truthy only if both sides are. It SHORT-CIRCUITS: if `a` is falsy, `b` is never
  //     evaluated at all.
  //   The leading `!` inverts the whole thing, so the binding is named for the FAULT:
  //   `centred` is true when the layout is wrong.
  //   Two spellings of "no transform" are accepted because browsers disagree — some report
  //   the keyword `none`, others the identity matrix, which means the same thing.
  //   A line may be broken wherever a token ends; the statement continues to its semicolon.
  const centred = !(cs.textAlign === 'left'
    && (cs.transform === 'none'
      || cs.transform === 'matrix(1, 0, 0, 1, 0, 0)'));

  // ── the verdict ─────────────────────────────────────────────────────────────

  // `.filter(callback)` is an array method: it calls the callback once per item and returns
  // a NEW array holding only the items for which it was truthy. `readings` is untouched.
  const failed = readings.filter(r => {
    // `indexOf('=')` returns the position of the first match (or -1 if absent). `slice(n)`
    // returns the part of the string from position n onwards. `+ 1` steps past the '='
    // itself. So 'zoomed-in=62.0' yields '62.0'.
    const v = r.slice(r.indexOf('=') + 1);
    // REGULAR-EXPRESSION LITERAL.  Grammar:  /pattern/flags
    //   Delimited by slashes rather than quotes, so it is a pattern object, not text.
    //   `^`      anchor to the start
    //   [\d.]    a character class: any digit (`\d`) or a literal dot
    //   +        one or more of the preceding item
    //   $        anchor to the end
    //   `.test(v)` returns true when the whole string matches, so this asks "purely numeric?"
    // `!` inverts it: a value like 'no-cue' is a FAILURE, not a skip.
    // `parseFloat(v) >= TOLERANCE` — RELATIONAL OPERATOR on numbers: too far off counts too.
    return !/^[\d.]+$/.test(v) || parseFloat(v) >= TOLERANCE;
  });
  // `.length` is the number of items in an array. 0 is falsy, so `!failed.length` reads
  // "nothing failed". With `&& !centred`, that is the pass condition.
  if (!failed.length && !centred) return 'aligned';
  // Otherwise hand back every reading, so the failure names the condition and the distance.
  // `.join(' ')` glues an array into one string with that separator between items. The
  // ternary at the end contributes the CSS note only when that is what went wrong.
  return 'OFF ' + readings.join(' ') + (centred ? ' · placed by centring, not by edge' : '');
};
