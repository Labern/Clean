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
window.__titleAudit = async function () {
  const T = window.PICA_API.test;
  const API = window.PICA_API;
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const TOLERANCE = 1.5;                       // px; sub-pixel rounding only

  // How far the title's first character is from where a cue is actually drawn.
  const gap = () => {
    const tEl = document.getElementById('docTitle');
    if (!tEl) return 'no-title';
    // the box carries padding, so its content edge is where the glyph starts
    const padL = parseFloat(getComputedStyle(tEl).paddingLeft) || 0;
    const textLeft = tEl.getBoundingClientRect().left + padL;
    const els = window.__pica.doc.elements;
    for (const d of document.querySelectorAll('#pages div[data-el]')) {
      const el = els.find(e => e.id === d.dataset.el);
      if (!el || el.type !== 'character' || el.dual) continue;   // dual cues have their own columns
      const r = d.getBoundingClientRect();
      if (r.width) return Math.abs(textLeft - r.left);           // every cue shares this edge
    }
    return 'no-cue';                            // nothing to align to: not a pass
  };

  const readings = [];
  const note = why => {
    const g = gap();
    readings.push(why + '=' + (typeof g === 'number' ? g.toFixed(1) : g));
  };

  // ── a script with cues in it, one short name and one long ────────────────────
  await T.reset();
  T.caret(0, 0); T.type('INT. ROOM - DAY'); T.esc();
  T.enter(); T.type('A door.'); T.esc();
  T.enter(); T.tab(false); T.type('SAM'); T.esc();
  T.enter(); T.type('One.'); T.esc();
  T.enter(); T.tab(false); T.type('ALEXANDRA-JANE'); T.esc();
  T.enter(); T.type('Two.'); T.esc();
  await wait(40);
  note('typed');

  // ── everything that moves the page under the title ───────────────────────────
  // the sidebar slides the page sideways
  API.toggleRail(); await wait(40); note('rail-hidden');
  API.toggleRail(); await wait(40); note('rail-shown');
  // the axis is in page points, so it must survive rescaling
  API.zoom(0.12);  await wait(30); note('zoomed-in');
  API.zoom(-0.24); await wait(30); note('zoomed-out');
  API.zoomFit();   await wait(30); note('zoom-fit');
  // a title page shifts every page index beneath it
  API.toggleTitlePage(); await wait(40); note('titlepage-on');
  API.toggleTitlePage(); await wait(40); note('titlepage-off');
  // scrolling through the script
  const canvas = document.getElementById('canvas');
  canvas.scrollTop = 140; await wait(40); note('scrolled');
  canvas.scrollTop = 0;   await wait(30);

  // ── a long title must still BEGIN on the column, not centre itself ───────────
  const was = window.__pica.doc.title;
  window.__pica.doc.title = 'A VERY LONG TITLE INDEED THAT KEEPS GOING';
  document.getElementById('docTitle').textContent = window.__pica.doc.title;
  API.zoomFit();                                // forces a re-render, which repositions
  await wait(40);
  note('long-title');
  window.__pica.doc.title = was;
  document.getElementById('docTitle').textContent = was;
  API.zoomFit(); await wait(30);

  // ── and it must not be achieved by centring ──────────────────────────────────
  const cs = getComputedStyle(document.getElementById('docTitle'));
  const centred = !(cs.textAlign === 'left'
    && (cs.transform === 'none' || cs.transform === 'matrix(1, 0, 0, 1, 0, 0)'));

  const failed = readings.filter(r => {
    const v = r.slice(r.indexOf('=') + 1);
    return !/^[\d.]+$/.test(v) || parseFloat(v) >= TOLERANCE;
  });
  if (!failed.length && !centred) return 'aligned';
  return 'OFF ' + readings.join(' ') + (centred ? ' · placed by centring, not by edge' : '');
};
