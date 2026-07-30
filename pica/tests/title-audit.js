// ─────────────────────────────────────────────────────────────────────────────
// THE TITLE BEGINS WHERE THE CHARACTER NAMES BEGIN.
//
// The contract: the screenplay title's FIRST CHARACTER sits on the character-cue
// column — the same x every cue starts at (3.5" on Final Draft's grid). Every cue
// shares that x exactly, so it is a hard vertical line running the length of the
// script, and it is the line the eye follows.
//
// It is NOT centred on the cues' optical centre. That was the bug: it put the
// title's left edge ~95px left of the column and its right edge past the cues'
// ragged ends, so nothing shared an edge even though the centres agreed to 1.7px.
//
// The check this replaced compared the title against the same formula that
// positioned it, so it could only ever agree with itself — a visibly misaligned
// title passed the suite for days. This one measures against a cue as actually
// DRAWN. Never test a placement against its own arithmetic.
//
// RUN IT
//   every install:  ./mac/build.sh --install   (the smoketest injects this file;
//                                               a red result refuses the install)
//   by hand:        node tests/chrome-run.mjs title-audit.js __titleAudit
//
// Returns 'aligned', or 'OFF <reading> …' naming every condition that failed.
//
// The comments below explain the JavaScript itself, line by line.
// ─────────────────────────────────────────────────────────────────────────────

// `window` is the global object in a browser: anything attached to it is reachable from
// anywhere on the page. Assigning a function to `window.__titleAudit` is how the two test
// harnesses reach this code after injecting the file — there are no imports/exports here.
// `async function` means the function always returns a Promise, and inside it we may use
// `await` to pause until something finishes. We need that because the app redraws between
// our measurements. `function () {}` is an anonymous function — it needs no name because
// the name it is stored under (`__titleAudit`) is how it is called.
window.__titleAudit = async function () {
  // `const` declares a name that cannot be reassigned (unlike `let`, which can be, or the
  // old `var`, which you should never use). This just keeps a shorter alias to the app's
  // test surface, so the lines below read `T.type(...)` rather than the full path.
  const T = window.PICA_API.test;
  // The same again for the app's public surface — the very calls its own menus make.
  const API = window.PICA_API;
  // An arrow function: `ms => ...` is shorthand for `function (ms) { return ...; }`.
  // A `Promise` represents work that finishes later; the function passed to `new Promise`
  // receives a `resolve` callback (here named `r`) which we hand to `setTimeout`, so the
  // promise settles after `ms` milliseconds. `await wait(40)` then pauses this function
  // for 40ms. Deliberately setTimeout and NOT requestAnimationFrame: rAF never fires in a
  // windowless WKWebView, so an rAF wait would hang the smoketest forever instead of failing.
  const wait = ms => new Promise(r => setTimeout(r, ms));
  // A plain number constant. SCREAMING_CASE is only a convention meaning "fixed setting".
  const TOLERANCE = 1.5;

  // ── the measurement ──────────────────────────────────────────────────────────

  // A function stored in a `const`. It closes over nothing but the page itself, and returns
  // EITHER a number (the distance we care about) OR a string explaining why it could not
  // measure. JavaScript is dynamically typed, so one function may return either — the
  // verdict code at the bottom checks which came back.
  const gap = () => {
    // `document` is the page. `getElementById` finds one element by its id attribute.
    // Returns the element, or `null` if there is no such element.
    const tEl = document.getElementById('docTitle');
    // `!tEl` is truthiness: `null` is "falsy", so this reads "if there is no title element".
    // `return` exits `gap` immediately with that string.
    if (!tEl) return 'no-title';
    // `getComputedStyle(el)` gives the styles actually in force after all CSS is applied
    // (not just inline styles). `.paddingLeft` comes back as a string like "11.2px", so
    // `parseFloat` pulls the leading number out of it. `|| 0` is the default-value idiom:
    // if the left side is falsy (NaN or empty), use 0 instead. We need the padding because
    // the glyph starts INSIDE the box, so the box edge is not where the T begins.
    const padL = parseFloat(getComputedStyle(tEl).paddingLeft) || 0;
    // `getBoundingClientRect()` returns the element's real position and size on screen right
    // now, in CSS pixels relative to the viewport. `.left` plus the padding = the x of the
    // first character. This is a measurement of the live page, not a calculation.
    const textLeft = tEl.getBoundingClientRect().left + padL;
    // Reach into the app's state (exposed for debugging) for the document model — the array
    // of elements the script is made of. We need it to know what each drawn line IS.
    const els = window.__pica.doc.elements;
    // `querySelectorAll` finds every element matching a CSS selector; `div[data-el]` means
    // "any div that has a data-el attribute" — that is how the app marks a drawn script line.
    // `for...of` loops over the values in that collection (as opposed to `for...in`, which
    // loops over keys and is the wrong tool here).
    for (const d of document.querySelectorAll('#pages div[data-el]')) {
      // `d.dataset.el` reads the `data-el` attribute (dataset converts data-foo-bar to
      // fooBar). `.find(fn)` walks the array and returns the FIRST element for which the
      // callback returns true, or `undefined` if none does. So this maps a drawn line back
      // to the model element it came from.
      const el = els.find(e => e.id === d.dataset.el);
      // `||` chains conditions: skip this line if we could not identify it, or it is not a
      // character cue, or it is a dual-dialogue cue (those sit in their own two-column
      // geometry and would give a false reading). `continue` jumps to the next loop iteration.
      if (!el || el.type !== 'character' || el.dual) continue;
      // Measure where this cue is ACTUALLY drawn.
      const r = d.getBoundingClientRect();
      // A width of 0 means it is not really laid out, so ignore it. Otherwise: every cue
      // starts at the same x, so the first real one gives us the column. `Math.abs` makes
      // the distance positive regardless of which side the title fell on. Returning here
      // ends the loop and the function — one good reading is all we need.
      if (r.width) return Math.abs(textLeft - r.left);
    }
    // Reached only if the loop found no cue at all. Returning a string, not a number, so the
    // verdict code treats it as a failure: a measurement that never happened is not a pass.
    return 'no-cue';
  };

  // An array literal. `const` stops the NAME being reassigned; the array's contents can
  // still change (`push` below), which is the usual JavaScript gotcha with const.
  const readings = [];
  // Takes a reading and labels it, so a failure can name the condition that broke.
  const note = why => {
    // Call the measurement defined above.
    const g = gap();
    // `typeof g === 'number'` asks what kind of value came back — a distance or a reason.
    // `toFixed(1)` formats a number to one decimal place (and returns a string).
    // `? :` is the ternary conditional: condition ? valueIfTrue : valueIfFalse.
    // `+` concatenates strings. `push` appends to the end of the array.
    readings.push(why + '=' + (typeof g === 'number' ? g.toFixed(1) : g));
  };

  // ── build a script that has cues in it ───────────────────────────────────────
  // Two names of very different lengths: under the old centring bug the axis moved with the
  // average cue length, so a mix of long and short is what exposes it.

  // `await` pauses here until the promise `reset()` returns has settled. Without `await` the
  // next line would run while the document was still being replaced.
  await T.reset();
  // Put the caret in element 0 at offset 0 — the top of the empty script.
  T.caret(0, 0);
  // Type characters through the app's real input path. Typing "int." promotes the element
  // to a Scene Heading, which is the app's own grammar doing its job.
  T.type('INT. ROOM - DAY');
  // Dismiss the autocomplete popup a slugline opens, so it cannot swallow the next keys.
  T.esc();
  // Press Enter. Off a slug, the app's grammar gives you an Action element.
  T.enter();
  // Some action text, so the page is not made only of headings.
  T.type('A door.');
  T.esc();
  // Enter again: off Action you get another Action…
  T.enter();
  // …and Tab in a BLANK Action converts it to a Character cue. `false` means "not Shift+Tab".
  T.tab(false);
  // The short cue — 3 characters.
  T.type('SAM');
  T.esc();
  // Enter off a cue gives Dialogue.
  T.enter();
  T.type('One.');
  T.esc();
  // Enter off Dialogue gives Action, then Tab makes it a cue again.
  T.enter();
  T.tab(false);
  // The long cue — 14 characters against SAM's 3.
  T.type('ALEXANDRA-JANE');
  T.esc();
  T.enter();
  T.type('Two.');
  T.esc();
  // Give the app 40ms to repaginate and redraw before we measure anything.
  await wait(40);
  // Reading 1: at rest, freshly typed.
  note('typed');

  // ── everything that moves the page under the title ──────────────────────────
  // The title lives in the header; the cues live on the page. Anything that shifts or
  // rescales the page has to move the title with it, or the two part company.

  // Several statements on one line, separated by semicolons — done here because they are one
  // thought: perform the change, wait for the redraw, measure. The sidebar occupies
  // horizontal space, so hiding it slides the whole page sideways.
  API.toggleRail(); await wait(40); note('rail-hidden');
  // And back again, which must restore the alignment rather than merely not break it.
  API.toggleRail(); await wait(40); note('rail-shown');

  // The axis is held in page points and multiplied by the zoom factor, so a wrong
  // multiplication is invisible until the zoom is something other than 1.
  API.zoom(0.12);  await wait(30); note('zoomed-in');
  // Negative delta: net -0.12, i.e. smaller than we started, exercising both directions.
  API.zoom(-0.24); await wait(30); note('zoomed-out');
  // Back to fit-to-width, the app's default scale.
  API.zoomFit();   await wait(30); note('zoom-fit');

  // Showing the title page inserts a page BEFORE the script, shifting every page index —
  // and the positioning code finds the page it measures against by index.
  API.toggleTitlePage(); await wait(40); note('titlepage-on');
  API.toggleTitlePage(); await wait(40); note('titlepage-off');

  // The scrolling container that holds the pages.
  const canvas = document.getElementById('canvas');
  // Setting `scrollTop` scrolls it programmatically, exactly as a wheel would. This proves
  // the title is not pinned to the first page's geometry.
  canvas.scrollTop = 140; await wait(40); note('scrolled');
  // Put the scroll back where it was, so the next condition starts clean.
  canvas.scrollTop = 0;   await wait(30);

  // ── a long title must still BEGIN on the column ─────────────────────────────
  // The condition centring fails hardest: a centred box grows in BOTH directions, so its
  // left edge walks further left the longer the title gets — 167px here against 53px above.

  // Keep the real title so we can put it back; this test must not leave the document changed.
  const was = window.__pica.doc.title;
  // Change the model…
  window.__pica.doc.title = 'A VERY LONG TITLE INDEED THAT KEEPS GOING';
  // …and the visible element. `textContent` sets an element's text (unlike `innerHTML`,
  // which would parse the string as HTML — never use innerHTML for plain text).
  document.getElementById('docTitle').textContent = window.__pica.doc.title;
  // Force a full re-render, which is what repositions the title.
  API.zoomFit();
  await wait(40);
  note('long-title');
  // Restore the document exactly as it was found.
  window.__pica.doc.title = was;
  document.getElementById('docTitle').textContent = was;
  API.zoomFit(); await wait(30);

  // ── and it must not be achieved by centring ─────────────────────────────────
  // A structural check rather than a measurement: even if every reading above passed, a CSS
  // change back to a centred box would mean the alignment is coincidence, not contract, and
  // would break the moment the title text changed.

  // The styles actually in force on the title right now.
  const cs = getComputedStyle(document.getElementById('docTitle'));
  // Read this inside-out. The bracketed part is what CORRECT looks like: text aligned left
  // AND no transform shifting the box. `&&` is logical AND, and it short-circuits — if the
  // first test fails the second is never evaluated. The leading `!` inverts the whole thing,
  // so `centred` is true when the layout is WRONG. Two spellings of "no transform" are
  // accepted because some browsers report the identity matrix instead of the keyword.
  const centred = !(cs.textAlign === 'left'
    && (cs.transform === 'none'
      || cs.transform === 'matrix(1, 0, 0, 1, 0, 0)'));

  // ── the verdict ─────────────────────────────────────────────────────────────

  // `.filter(fn)` returns a NEW array of the items for which the callback is true — it does
  // not modify `readings`. So `failed` ends up holding only the bad readings.
  const failed = readings.filter(r => {
    // `indexOf('=')` finds the position of the first '='; `slice` takes everything after it.
    // So 'zoomed-in=62.0' becomes '62.0'.
    const v = r.slice(r.indexOf('=') + 1);
    // A regular expression: `^` start, `[\d.]+` one or more digits or dots, `$` end — so
    // `.test(v)` asks "is this purely numeric?". If it is NOT, the value is 'no-cue' or
    // 'no-title', which counts as a FAILURE, not a skip: a measurement that never happened
    // must never read as success. Otherwise convert it to a number and compare to tolerance.
    return !/^[\d.]+$/.test(v) || parseFloat(v) >= TOLERANCE;
  });
  // `failed.length` is 0 when the array is empty, and 0 is falsy — so `!failed.length` reads
  // "nothing failed". Combined with "and it is not centred", that is a pass.
  if (!failed.length && !centred) return 'aligned';
  // Otherwise hand back every reading so the failure says which condition broke and by how
  // much. `.join(' ')` glues the array into one space-separated string. The trailing ternary
  // appends the CSS note only when that is what went wrong.
  return 'OFF ' + readings.join(' ') + (centred ? ' · placed by centring, not by edge' : '');
};
