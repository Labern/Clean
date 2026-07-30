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
// ragged ends, so nothing shared an edge and the alignment read as broken even
// though the centres agreed to 1.7px.
//
// WHY THIS FILE EXISTS, AND WHY IT MEASURES THE WAY IT DOES
// The check this replaced compared the title against the same formula that
// positioned it, so it could only ever agree with itself — a visibly misaligned
// title passed the suite for days. This one measures the title against a cue as
// actually DRAWN on the page. Never test a placement against its own arithmetic.
//
// It also refuses to pass if the placement has gone back to being achieved by
// centring, because a CSS change alone could silently undo all of it.
//
// RUN IT
//   every install:  ./mac/build.sh --install   (the smoketest injects this file;
//                                               a red result refuses the install)
//   by hand:        node tests/chrome-run.mjs title-audit.js __titleAudit
//
// Returns the string 'aligned', or 'OFF <reading> <reading> …' naming every
// condition that failed and by how much.
// ─────────────────────────────────────────────────────────────────────────────

// Hung off `window` so the harnesses can find it after injecting this file: the
// smoketest calls it inside the built PICA.app, chrome-run.mjs in headless Chromium.
// `async` because each condition needs the app to finish re-rendering before it is measured.
window.__titleAudit = async function () {
  const T = window.PICA_API.test;      // the app's test surface: reset/caret/type/enter/tab/esc
  const API = window.PICA_API;         // the app's public surface: the same calls the menus make
  // Pause and let the app re-render. setTimeout, not requestAnimationFrame: rAF never
  // fires in a windowless WKWebView, so an rAF-based wait would hang the smoketest forever.
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const TOLERANCE = 1.5;               // px allowed; enough for sub-pixel rounding, nothing more

  // ── the measurement ──────────────────────────────────────────────────────────
  // Returns how far the title's first character is from where a character cue is
  // actually drawn — or a string naming why it could not be measured, which never passes.
  const gap = () => {
    const tEl = document.getElementById('docTitle');           // the title element in the header
    if (!tEl) return 'no-title';                               // no title on screen: cannot pass
    // The element has horizontal padding, and the glyph starts inside it — so the box's
    // left edge is NOT where the T of the title begins. Add padding-left to get there.
    const padL = parseFloat(getComputedStyle(tEl).paddingLeft) || 0;
    const textLeft = tEl.getBoundingClientRect().left + padL;  // viewport x of the first character
    const els = window.__pica.doc.elements;                    // the model, to identify each line
    // Walk the drawn lines on the page. Each line div carries data-el = the id of the
    // element it belongs to, which is how a rendered line is traced back to the model.
    for (const d of document.querySelectorAll('#pages div[data-el]')) {
      const el = els.find(e => e.id === d.dataset.el);          // the model element for this line
      // Only a plain character cue defines the column. Dual-dialogue cues sit in their own
      // two-column geometry, so they would give a false reading.
      if (!el || el.type !== 'character' || el.dual) continue;
      const r = d.getBoundingClientRect();                     // where this cue is really drawn
      // Every cue starts at the same x, so the first one on screen gives the column.
      // This is the whole point: a measured edge, not a recomputed formula.
      if (r.width) return Math.abs(textLeft - r.left);          // the distance we are testing
    }
    return 'no-cue';                   // no cue on screen: nothing to align to, so not a pass
  };

  const readings = [];                 // one 'condition=distance' string per measurement
  // Take a reading and label it, so a failure names the condition that broke rather
  // than just saying no.
  const note = why => {
    const g = gap();                                                   // measure now
    readings.push(why + '=' + (typeof g === 'number' ? g.toFixed(1) : g));  // number → 1dp, else the reason
  };

  // ── build a script that has cues in it ───────────────────────────────────────
  // Two names of very different lengths: under the old centring bug the axis moved with
  // the average cue length, so a mix is what exposes it.
  await T.reset();                     // a fresh empty document, so no earlier state leaks in
  T.caret(0, 0);                       // put the caret at the start of the first element
  T.type('INT. ROOM - DAY');           // typing "int." promotes the element to a Scene Heading
  T.esc();                             // dismiss the autocomplete popup the slug opens
  T.enter();                           // Enter off a slug gives an Action element
  T.type('A door.');                   // some action, so the page is not just headings
  T.esc();
  T.enter();                           // Enter off Action gives another Action…
  T.tab(false);                        // …and Tab in a blank Action turns it into a Character cue
  T.type('SAM');                       // the short cue
  T.esc();
  T.enter();                           // Enter off a cue gives Dialogue
  T.type('One.');
  T.esc();
  T.enter();                           // Enter off Dialogue gives Action
  T.tab(false);                        // Tab again for a second cue
  T.type('ALEXANDRA-JANE');            // the long cue — 14 characters against SAM's 3
  T.esc();
  T.enter();
  T.type('Two.');
  T.esc();
  await wait(40);                      // let the pages repaginate and redraw
  note('typed');                       // reading 1: at rest, freshly typed

  // ── everything that moves the page under the title ──────────────────────────
  // The title is in the header; the cues are on the page. Anything that shifts or
  // rescales the page has to move the title with it, or they part company.

  // The sidebar takes horizontal space, so hiding it slides the whole page sideways.
  API.toggleRail(); await wait(40); note('rail-hidden');
  API.toggleRail(); await wait(40); note('rail-shown');   // and back, which must restore it

  // The axis is stored in page points and multiplied by the zoom factor, so a wrong
  // multiplication only shows up once the zoom is not 1.
  API.zoom(0.12);  await wait(30); note('zoomed-in');
  API.zoom(-0.24); await wait(30); note('zoomed-out');    // net -0.12: smaller than we started
  API.zoomFit();   await wait(30); note('zoom-fit');      // back to fit-to-width

  // Showing the title page inserts a page before the script, shifting every page index —
  // and the code finds the page it measures against by index.
  API.toggleTitlePage(); await wait(40); note('titlepage-on');
  API.toggleTitlePage(); await wait(40); note('titlepage-off');

  // Scrolling changes which page is on screen, so the title must not be pinned to the
  // first page's geometry.
  const canvas = document.getElementById('canvas');       // the scrolling container of pages
  canvas.scrollTop = 140; await wait(40); note('scrolled');
  canvas.scrollTop = 0;   await wait(30);                 // put it back for the next condition

  // ── a long title must still BEGIN on the column ─────────────────────────────
  // This is the condition that fails hardest under centring: a centred box grows in both
  // directions, so its left edge walks further left the longer the title gets (167px here).
  const was = window.__pica.doc.title;                    // remember the real title to restore
  window.__pica.doc.title = 'A VERY LONG TITLE INDEED THAT KEEPS GOING';   // 41 characters
  document.getElementById('docTitle').textContent = window.__pica.doc.title;  // and show it
  API.zoomFit();                       // forces a re-render, which is what repositions the title
  await wait(40);
  note('long-title');
  window.__pica.doc.title = was;       // put the document back exactly as it was
  document.getElementById('docTitle').textContent = was;
  API.zoomFit(); await wait(30);

  // ── and it must not be achieved by centring ─────────────────────────────────
  // A structural check, not a measurement. Even if every reading above passed, a CSS
  // change back to a centred box would mean the alignment is coincidence, not contract —
  // and would break the moment the title text changed.
  const cs = getComputedStyle(document.getElementById('docTitle'));
  const centred = !(cs.textAlign === 'left'                       // text must be left-aligned…
    && (cs.transform === 'none'                                   // …and the box not shifted
      || cs.transform === 'matrix(1, 0, 0, 1, 0, 0)'));           // (the identity matrix is 'none')

  // ── the verdict ─────────────────────────────────────────────────────────────
  const failed = readings.filter(r => {
    const v = r.slice(r.indexOf('=') + 1);          // the value side of 'condition=value'
    // A non-numeric value ('no-cue', 'no-title') is a failure, not a skip: it means the
    // measurement never happened, and silence must never read as success.
    return !/^[\d.]+$/.test(v) || parseFloat(v) >= TOLERANCE;
  });
  if (!failed.length && !centred) return 'aligned';   // every condition within tolerance
  // Otherwise hand back every reading, so the failure says which condition and by how much.
  return 'OFF ' + readings.join(' ') + (centred ? ' · placed by centring, not by edge' : '');
};
