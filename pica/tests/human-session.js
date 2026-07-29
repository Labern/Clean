// A human writes a screenplay in PICA.
//
// Not an API test — every keystroke below goes through the same DOM events a
// real keyboard produces (keydown → beforeinput), at human speed AND at burst
// speed, with typos, corrections, undo, and every emphasis feature. If a
// character the typist pressed does not end up in the model, this says so.
//
// Loaded and driven by tests/human-session.swift (headless WKWebView, no window).
window.__humanSession = async function () {
  const pages = document.getElementById('pages');
  const T = window.PICA_API.test;
  const log = [], err = [];
  // yield a frame — but fall back to a timer, because a headless WKWebView with
  // no on-screen window never fires requestAnimationFrame at all
  const raf = () => new Promise(r => {
    let done = false;
    const fire = () => { if (!done) { done = true; r(); } };
    requestAnimationFrame(fire);
    setTimeout(fire, 8);
  });
  window.__hsProgress = [];
  const t0 = Date.now();
  const beat = m => { window.__hsProgress.push('+' + (Date.now() - t0) + 'ms ' + m); };
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---------- what the typist's hands do ----------
  function kd(key, opts) {
    return pages.dispatchEvent(new KeyboardEvent('keydown',
      Object.assign({ key, bubbles: true, cancelable: true, composed: true }, opts || {})));
  }
  function bi(inputType, data) {
    return pages.dispatchEvent(new InputEvent('beforeinput',
      { inputType, data: data === undefined ? null : data, bubbles: true, cancelable: true, composed: true }));
  }
  // slow = a considered typist: a frame and a beat between keys, so every
  // re-render, selectionchange and caret restore lands between characters.
  // fast = a burst nothing can keep up with: no yield at all between keys.
  async function type(str, speed) {
    for (const ch of str) {
      kd(ch); bi('insertText', ch);
      if (speed === 'slow') { await raf(); await sleep(12); }
      else if (speed !== 'fast') await sleep(0);
    }
    if (speed === 'fast') await sleep(30); // let the burst settle before reading
  }
  async function back(n, speed) {
    for (let i = 0; i < (n || 1); i++) {
      kd('Backspace'); bi('deleteContentBackward');
      if (speed === 'slow') { await raf(); await sleep(12); } else if (speed !== 'fast') await sleep(0);
    }
    if (speed === 'fast') await sleep(30);
  }
  async function wordBack(n) {
    for (let i = 0; i < (n || 1); i++) { kd('Backspace', { altKey: true }); bi('deleteWordBackward'); await sleep(0); }
  }
  async function enter() { kd('Enter'); await sleep(0); await raf(); }
  async function tab(shift) { kd('Tab', { shiftKey: !!shift }); await sleep(0); await raf(); }
  async function cmd(letter) { kd(letter, { metaKey: true }); await sleep(0); }

  // ---------- where the typist's caret is ----------
  function lineDivs() {
    return [...pages.querySelectorAll('div[data-el]')].filter(d => {
      const k = d.dataset.kind; return k !== 'more' && k !== 'contcue' && k !== 'pn' && k !== 'rev';
    });
  }
  function textNodeAt(div, at) {
    const w = document.createTreeWalker(div, NodeFilter.SHOW_TEXT);
    let n, acc = 0;
    while ((n = w.nextNode())) {
      const L = n.nodeValue.length;
      if (at <= acc + L) return { node: n, off: at - acc };
      acc += L;
    }
    return null;
  }
  // click into element index `i` at model offset `off`, the way a mouse would
  async function click(i, off) {
    const st = T.state();
    const els = window.__pica.doc.elements;
    const el = els[i]; if (!el) return false;
    if (off == null) off = el.text.length;
    for (const d of lineDivs()) {
      if (d.dataset.el !== el.id) continue;
      const start = +d.dataset.off || 0, len = d.textContent.length;
      if (off >= start && off <= start + len) {
        const t = textNodeAt(d, off - start); if (!t) continue;
        const r = document.createRange(); r.setStart(t.node, t.off); r.collapse(true);
        const s = getSelection(); s.removeAllRanges(); s.addRange(r);
        pages.focus();
        await sleep(0); await raf();
        return true;
      }
    }
    return false;
  }
  // drag-select a model range inside one element
  async function select(i, a, b) {
    const el = window.__pica.doc.elements[i]; if (!el) return false;
    let A = null, B = null;
    for (const d of lineDivs()) {
      if (d.dataset.el !== el.id) continue;
      const s = +d.dataset.off || 0, len = d.textContent.length;
      if (!A && a >= s && a <= s + len) A = textNodeAt(d, a - s);
      if (b >= s && b <= s + len) B = textNodeAt(d, b - s);
    }
    if (!A || !B) return false;
    const r = document.createRange(); r.setStart(A.node, A.off); r.setEnd(B.node, B.off);
    const s = getSelection(); s.removeAllRanges(); s.addRange(r);
    pages.focus();
    await sleep(0); await raf();
    return true;
  }

  // ---------- what the typist checks ----------
  function txt(i) { const s = T.state()[i] || ''; return s.slice(s.indexOf('|') + 1); }
  function kind(i) { const s = T.state()[i] || ''; return s.slice(0, s.indexOf('|')); }
  function check(name, ok, detail) {
    (ok ? log : err).push((ok ? 'ok   ' : 'FAIL ') + name + (detail ? ' — ' + detail : ''));
    return ok;
  }
  // the eaten-input assertion: every character pressed survived, in order.
  // scene headings are upper-cased by the engine, so compare case-insensitively.
  function typed(name, i, expected) {
    const got = txt(i);
    return check(name, got.toUpperCase() === expected.toUpperCase(),
      got === expected ? '' : 'typed ' + JSON.stringify(expected) + ' got ' + JSON.stringify(got));
  }

  await T.reset();
  await sleep(200);

  // ═════════ 1. the slug — typed slowly, with a typo caught mid-word ═════════
  beat('1.the slug — typed slowly, with a typo caught mid-word');
  await click(0, 0);
  await type('int. radoi', 'slow');
  await back(2, 'slow');                       // "radoi" → "rad"
  await type('io observatory - night', 'slow');
  typed('slug typed slowly, typo corrected', 0, 'INT. RADIO OBSERVATORY - NIGHT');
  check('slug became a scene heading', kind(0) === 'scene', kind(0));

  // ═════════ 2. action — a burst nothing can keep up with ═════════
  beat('2.action — a burst nothing can keep up with');
  await enter();
  check('Enter off a slug gives Action', kind(1) === 'action', kind(1));
  const A1 = 'A dish the size of a cathedral tips toward a dead patch of sky.';
  await type(A1, 'fast');
  typed('action survives a full-speed burst', 1, A1);

  // ═════════ 3. full stops and spaces, at speed — his exact complaint ═════════
  beat('3.full stops and spaces, at speed — his exact complaint');
  await enter(); beat('3a enter');
  const A2 = 'Dust. Wind. Nothing. Then. Something. A. B. C. D. E.';
  await type(A2, 'fast'); beat('3b fast typed');
  typed('full stops and spaces are never eaten (fast)', 2, A2); beat('3c checked');
  await enter(); beat('3d enter2');
  const A3 = 'Slowly now. With gaps. And full stops. And  double  spaces.';
  await type(A3, 'slow'); beat('3e slow typed');
  typed('full stops and spaces are never eaten (slow)', 3, A3); beat('3f checked');

  // ═════════ 4. a character cue ═════════
  beat('4.a character cue');
  await enter();
  await tab();
  check('Tab in blank Action gives Character', kind(4) === 'character', kind(4));
  await type('maya', 'fast');
  typed('cue typed', 4, 'MAYA');

  // ═════════ 5. dialogue, then a parenthetical that must be visible at once ═════
  beat('5.dialogue, then a parenthetical that must be visible at once');
  await enter();
  check('Enter off a cue gives Dialogue', kind(5) === 'dialogue', kind(5));
  await type('It repeated.', 'slow');
  await enter();
  await tab();
  check('Tab gives a Parenthetical', kind(6) === 'paren', kind(6));
  check('blank parenthetical shows () before a key is pressed', txt(6) === '()', JSON.stringify(txt(6)));
  check('caret sits between the parens', T.caretAt() === '6:1', T.caretAt());
  await type('not looking up', 'slow');
  typed('parenthetical typed inside its own brackets', 6, '(not looking up)');

  // ═════════ 6. THE italics beat: on, then OFF, mid-sentence ═════════
  beat('6.THE italics beat: on, then OFF, mid-sentence');
  await enter();
  check('Enter off a parenthetical gives Dialogue', kind(7) === 'dialogue', kind(7));
  await type('The signal repeats ', 'slow');
  await cmd('i');
  await type('every', 'slow');
  await cmd('i');                              // ← turn it OFF
  await type(' ninety seconds.', 'slow');
  typed('italic sentence typed', 7, 'The signal repeats every ninety seconds.');
  {
    const m = T.marks(7), t = txt(7);
    const iOn = t.indexOf('every'), iOff = iOn + 5;
    const runOK = m.slice(iOn, iOff).split('').every(c => c === 'i');
    const offOK = m.slice(iOff).split('').every(c => c === '.');
    const preOK = m.slice(0, iOn).split('').every(c => c === '.');
    check('italic turns ON where asked', runOK, m);
    check('italic turns OFF where asked', offOK, m.slice(iOff));
    check('italic did not leak backwards', preOK, m.slice(0, iOn));
    const ital = [...pages.querySelectorAll('i')].map(n => n.textContent).join('|');
    check('what is painted matches the model', ital.includes('every') && !ital.includes('ninety'), ital);
  }

  // ═════════ 7. bold + italic together, then both off ═════════
  beat('7.bold + italic together, then both off');
  await enter();
  await type('Say it ', 'slow');
  await cmd('b'); await cmd('i');
  await type('twice', 'fast');
  await cmd('b'); await cmd('i');
  await type(' and mean it.', 'fast');
  typed('bold+italic sentence typed', 8, 'Say it twice and mean it.');
  {
    const m = T.marks(8), t = txt(8), a = t.indexOf('twice'), b = a + 5;
    check('bold+italic both apply', m.slice(a, b).split('').every(c => c === 'bi'.split('').join('') || c === 'bi'), m);
    check('bold+italic both release', m.slice(b).split('').every(c => c === '.'), m.slice(b));
  }

  // ═════════ 8. underline by selection, the other way in ═════════
  beat('8.underline by selection, the other way in');
  await select(8, 0, 6);                       // "Say it"
  await cmd('u');
  await sleep(30);
  {
    const m = T.marks(8);
    check('selection underline paints exactly the selection',
      m.slice(0, 6).split('').every(c => c.includes('u')) && !m.slice(6).split('').some(c => c.includes('u')), m);
  }

  // ═════════ 9. a correction with ⌥⌫, mid-flow ═════════
  beat('9.a correction with ⌥⌫, mid-flow');
  await click(8, txt(8).length);
  await type(' Absolutely dreadful', 'fast');
  await wordBack(2);
  await type('perfectly clear.', 'fast');
  typed('word-delete correction lands cleanly', 8, 'Say it twice and mean it. perfectly clear.');

  // ═════════ 10. typing into the MIDDLE of a finished paragraph ═════════
  beat('10.typing into the MIDDLE of a finished paragraph');
  await click(1, 2);                           // after "A "
  await type('vast ', 'slow');
  typed('insertion mid-paragraph goes exactly where the caret was', 1,
    'A vast dish the size of a cathedral tips toward a dead patch of sky.');

  // ═════════ 11. splitting a styled line with Enter — style must survive ═════
  beat('11.splitting a styled line with Enter — style must survive');
  const before8 = T.marks(8);
  await click(8, 8);                           // inside "twice", after "Say it t"
  await enter();
  {
    const head = T.marks(8), tail = T.marks(9);
    check('split keeps the head\'s styling', head === before8.slice(0, 8), head + ' vs ' + before8.slice(0, 8));
    check('split keeps the tail\'s styling', tail === before8.slice(8), tail + ' vs ' + before8.slice(8));
  }
  // ...and merging it back must restore exactly what was there
  await click(9, 0);
  await back(1);
  check('merge restores the styling unchanged', T.marks(8) === before8, T.marks(8) + ' vs ' + before8);

  // ═════════ 12. undo storm, then redo ═════════
  beat('12.undo storm, then redo');
  const snapshot = T.state().join('\n');
  await click(3, txt(3).length);
  await type(' Extra words that will be undone.', 'fast');
  for (let i = 0; i < 40; i++) { window.PICA_API.undo(); await sleep(0); }
  await sleep(60);
  check('undo unwinds without throwing', true);
  for (let i = 0; i < 60; i++) { window.PICA_API.redo(); await sleep(0); }
  await sleep(60);
  check('redo restores the document', T.state().join('\n').includes('Extra words that will be undone.'),
    T.state().slice(0, 5).join(' / '));

  // ═════════ 13. a transition, and the scene it hands to ═════════
  beat('13.a transition, and the scene it hands to');
  await click(T.state().length - 1, null);
  await enter(); await enter();                // out of dialogue, into action
  let n = T.state().length - 1;
  await tab(); await tab();                    // action → character → transition? walk to it
  const walked = kind(n);
  await T.reset === null;                      // no-op guard
  log.push('note  Tab walk from blank action landed on: ' + walked);

  // ═════════ 14. the marathon — write until the page breaks, at speed ═══════
  beat('14.the marathon — write until the page breaks, at speed');
  await T.reset();
  await sleep(150);
  await click(0, 0);
  await type('int. corridor - later', 'fast');
  await enter();
  const LINE = 'She walks. The lights stutter behind her, one panel at a time.';
  for (let i = 0; i < 26; i++) {
    await type(LINE, 'fast');
    await enter();
  }
  await sleep(120);
  {
    const st = T.state();
    const bad = [];
    for (let i = 1; i < st.length; i++) {
      const t = st[i].slice(st[i].indexOf('|') + 1);
      if (t && t !== LINE) bad.push(i + ':' + JSON.stringify(t.slice(0, 70)));
    }
    check('26 full-speed paragraphs, every character intact', bad.length === 0, bad.slice(0, 4).join(' | '));
    check('the marathon spilled onto more than one page',
      document.querySelectorAll('.pageWrap').length > 1, document.querySelectorAll('.pageWrap').length + ' pages');
  }

  // ═════════ 15. typing across the page break, slowly ═════════
  beat('15.typing across the page break, slowly');
  {
    const st = T.state();
    const last = st.length - 2;
    await click(last, txt(last).length);
    await type(' She does not look back.', 'slow');
    typed('typing at the page break keeps every character', last, LINE + ' She does not look back.');
    check('caret is still where the typist left it', T.caretAt() === last + ':' + txt(last).length, T.caretAt());
  }

  // ═════════ 16. anything the page itself complained about ═════════
  beat('16.anything the page itself complained about');
  const thrown = (window.__errs || []).filter(e => !/favicon|pdf\.worker/i.test(e));
  check('the app threw nothing while being written in', thrown.length === 0, thrown.slice(0, 3).join(' ; '));

  return JSON.stringify({ log, err }, null, 1);
};
