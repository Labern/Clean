/* ─────────────────────────────────────────────────────────────────────────────
   shell.js — the page half of the app. Injected into web.whatsapp.com at
   document start, before WhatsApp's own bundle runs.

   It does five things the browser cannot do for us:
     1. Gives the page a Notification API. WKWebView has none at all, so an
        unpatched WhatsApp Web is silent forever — it feature-detects, finds
        nothing, and never even offers to notify. We implement the API and
        forward to real macOS notifications.
     2. Mirrors the unread count (WhatsApp writes it into document.title as
        "(3) WhatsApp") onto the Dock tile.
     3. Applies the theme / hidden-furniture / privacy attributes that theme.css
        keys off, and re-asserts them if the SPA rewrites <html>.
     4. Opens a chat by name, for the ⌘1–9 pins — first by clicking a rendered
        row, then via WhatsApp's own search if the chat has scrolled out of the
        virtualised list.
     5. Verifies that privacy mode's selectors actually matched something, and
        escalates to blurring the whole pane if not. A privacy control that
        silently fails is worse than no privacy control.

   Naming note: everything here is namespaced `shell`, deliberately free of the
   app's name, so renaming the app never touches this file.
   ───────────────────────────────────────────────────────────────────────── */

(() => {
  'use strict';
  if (window.__shell) return;

  const HIDEABLE = ['calls', 'status', 'channels', 'communities', 'media',
                    'metaai', 'filters', 'archived', 'promos'];

  const cfg = Object.assign({ theme: 'stock', hide: {}, privacy: false,
                              compact: false, font: '', msgSize: 0,
                              nameSize: 0, msgGap: 0, sounds: false,
                              focus: false, pins: [] },
                            window.__SHELL_CONFIG || {});

  const native = (() => { try { return window.webkit.messageHandlers.shell } catch (e) { return null } })();
  const post   = (msg) => { try { native && native.postMessage(msg) } catch (e) {} };
  const R      = () => document.documentElement;
  const sleep  = (ms) => new Promise(r => setTimeout(r, ms));
  const norm   = (s) => (s || '').replace(/ /g, ' ').replace(/\s+/g, ' ').trim().toLowerCase();

  /* ── 1. stylesheet ─────────────────────────────────────────────────────────
     Appended to documentElement rather than head, because at document start
     head may not exist yet. Re-asserted on the pump below in case WhatsApp
     replaces the head wholesale on boot. */

  function installCSS() {
    if (document.getElementById('shell-style')) return;
    const s = document.createElement('style');
    s.id = 'shell-style';
    s.textContent = window.__SHELL_CSS || '';
    (document.head || document.documentElement).appendChild(s);
  }

  /* ── 2. attributes: theme, hidden furniture, privacy ─────────────────────── */

  function applyTheme(name) {
    cfg.theme = name || 'stock';
    R().setAttribute('data-shell-theme', cfg.theme);
    return cfg.theme;
  }

  function applyHide(flags) {
    cfg.hide = flags || {};
    for (const k of HIDEABLE) {
      if (cfg.hide[k]) R().setAttribute('data-shell-hide-' + k, '');
      else             R().removeAttribute('data-shell-hide-' + k);
    }
    return cfg.hide;
  }

  function applyPrivacy(on) {
    cfg.privacy = !!on;
    if (cfg.privacy) R().setAttribute('data-shell-privacy', '');
    else {
      R().removeAttribute('data-shell-privacy');
      R().removeAttribute('data-shell-privacy-fallback');
    }
    checkPrivacyCoverage();
    return cfg.privacy;
  }

  // Re-assert everything; the SPA occasionally rewrites attributes on <html>.
  function ensureAttributes() {
    if (R().getAttribute('data-shell-theme') !== cfg.theme) applyTheme(cfg.theme);
    for (const k of HIDEABLE) {
      const want = !!cfg.hide[k], has = R().hasAttribute('data-shell-hide-' + k);
      if (want !== has) applyHide(cfg.hide);
    }
    if (cfg.privacy !== R().hasAttribute('data-shell-privacy')) applyPrivacy(cfg.privacy);
  }

  /* ── 3. the conversation pane ──────────────────────────────────────────────
     WhatsApp has long called it #main, but that is an id we do not control, and
     privacy mode must not quietly stop working if it is renamed. So we locate
     the pane ourselves and tag it with data-shell-convo, which the CSS also
     keys off. Heuristic: the tall, wide ancestor of the message composer. */

  function convoPane() {
    const byId = document.querySelector('#main');
    if (byId) return byId;
    const composer = document.querySelector('footer [contenteditable="true"]')
                  || document.querySelector('[contenteditable="true"]');
    if (!composer) return null;
    let p = composer.parentElement;
    while (p && p !== document.body) {
      const r = p.getBoundingClientRect();
      if (r.height > window.innerHeight * 0.6 && r.width > window.innerWidth * 0.3) return p;
      p = p.parentElement;
    }
    return null;
  }

  function tagConvoPane() {
    const pane = convoPane();
    const tagged = document.querySelector('[data-shell-convo]');
    if (tagged && tagged !== pane) tagged.removeAttribute('data-shell-convo');
    if (pane && !pane.hasAttribute('data-shell-convo')) pane.setAttribute('data-shell-convo', '');
    return pane;
  }

  // Did privacy mode's per-message selectors actually match anything? If not,
  // escalate to the coarse whole-pane blur rather than pretending to be on.
  function checkPrivacyCoverage() {
    if (!cfg.privacy) return { on: false };
    const pane = tagConvoPane();
    if (!pane) { R().removeAttribute('data-shell-privacy-fallback'); return { on: true, pane: false } }
    const hit = pane.querySelector('[role="row"], [data-id], .message-in, .message-out');
    if (hit) R().removeAttribute('data-shell-privacy-fallback');
    else     R().setAttribute('data-shell-privacy-fallback', '');
    return { on: true, pane: true, perMessage: !!hit, fallback: !hit };
  }

  /* ── 3b. the nav rail and the list pane ────────────────────────────────────
     Companion mode has to collapse both, and neither has a stable hook: the
     rail's container is an obfuscated div (verified live), and while the list
     currently sits in #side that is an id we don't control. So find them and tag
     them, exactly as with the conversation pane. */

  function tagRail() {
    if (document.querySelector('[data-shell-rail]')) return true;
    const items = Array.from(document.querySelectorAll('[data-navbar-item]'));
    if (!items.length) return false;
    // walk up until one ancestor holds every nav item — that is the rail
    let p = items[0].parentElement;
    while (p && p !== document.body && !items.every(i => p.contains(i))) p = p.parentElement;
    if (!p || p === document.body) return false;
    p.setAttribute('data-shell-rail', '');
    return true;
  }

  function tagList() {
    if (document.querySelector('[data-shell-list]')) return true;
    const list = document.querySelector('[data-testid="chat-list"]');
    const side = document.querySelector('#side') || (list && list.closest('div[class]'));
    if (!side) return false;

    // Tag the whole left COLUMN, not just the list. Measured live: #side is the
    // list (453px wide) and its parent is the column (454px) holding a 64px
    // search header above it. Hiding only #side would leave that header behind
    // as an orphaned strip down the side of companion mode. The width test is
    // what distinguishes "the column" from some broader layout wrapper.
    let pane = side;
    const p = side.parentElement;
    if (p && p !== document.body && p.id !== 'app' &&
        p.offsetWidth > 0 && p.offsetWidth <= side.offsetWidth * 1.15) {
      pane = p;
    }
    pane.setAttribute('data-shell-list', '');
    return true;
  }

  /* Remove the leftover column. Tagging the rail and the list by name is not
     enough — anything else WhatsApp puts beside the conversation stays behind as
     an empty strip. So walk from the conversation up to the app root and hide
     every SIBLING on the way: whatever is left is, by construction, only the
     conversation and its ancestors.

     Guarded so it cannot break the app: overlays and popover hosts (anything
     positioned fixed/absolute, WhatsApp's #wa-popovers-bucket, our own bar) are
     left alone, or the "more" menu and every WhatsApp dialog would stop working. */
  function collapseChrome() {
    const pane = tagConvoPane();
    const open = !!(pane && pane.getBoundingClientRect().width > 60);
    // The gate the CSS keys off: no conversation, no collapsing, so he can still
    // pick a chat from the list.
    if (open) R().setAttribute('data-shell-convo-open', '');
    else { R().removeAttribute('data-shell-convo-open'); clearCollapsed(); return 0 }
    if (!pane) return 0;
    let hidden = 0;
    let el = pane;
    while (el && el.parentElement && el.parentElement !== document.body) {
      for (const sib of Array.from(el.parentElement.children)) {
        if (sib === el || sib.id === 'shell-bar') continue;
        if (sib.id && sib.id.startsWith('wa-popovers')) continue;
        const cs = getComputedStyle(sib);
        if (cs.position === 'fixed' || cs.position === 'absolute') continue;
        if (sib.getBoundingClientRect().width <= 0) continue;
        if (!sib.hasAttribute('data-shell-collapsed')) { sib.setAttribute('data-shell-collapsed', ''); hidden++ }
      }
      el = el.parentElement;
    }
    return hidden;
  }

  /* Tag the conversation's ancestors. The doodle wallpaper and the stray vertical
     lines are painted by layers BEHIND the pane — the diagnostics found no thin
     element and no background-image anywhere inside it, and collapseChrome skips
     absolutely-positioned elements on purpose (popovers and dialogs live there).
     So instead of hiding those layers, focus mode just stops them painting. */
  function tagAncestors() {
    const pane = document.querySelector('[data-shell-convo]');
    if (!pane) return 0;
    let n = 0, el = pane.parentElement;
    while (el && el !== document.documentElement) {
      if (!el.hasAttribute('data-shell-ancestor')) { el.setAttribute('data-shell-ancestor', ''); n++ }
      el = el.parentElement;
    }
    return n;
  }

  /* "The pin section should be removed." It has no id or testid, so find it by
     shape: a full-width direct child of the conversation about a header's height
     tall, that isn't the header, the footer, or the (much taller) message list. */
  function tagPinStrip() {
    const pane = document.querySelector('[data-shell-convo]');
    if (!pane) return false;
    const paneW = pane.getBoundingClientRect().width;
    for (const el of pane.children) {
      if (el.tagName === 'HEADER' || el.tagName === 'FOOTER') continue;
      if (el.hasAttribute('data-shell-pinstrip')) return true;
      const r = el.getBoundingClientRect();
      if (r.height >= 28 && r.height <= 80 && r.width >= paneW - 4) {
        el.setAttribute('data-shell-pinstrip', '');
        return true;
      }
    }
    return false;
  }

  /* The doodle is not CSS. Setting background-image:none on every element changed
     nothing and the probes found no background-image anywhere — so WhatsApp paints
     it as an <svg>/<img> layer. Find that layer by shape: a big svg/img/canvas
     covering most of the pane, outside any dialog (so the media viewer is safe). */
  function tagWallpaper() {
    const pane = document.querySelector('[data-shell-convo]');
    if (!pane) return 0;
    const pr = pane.getBoundingClientRect();
    let n = 0;
    for (const el of document.querySelectorAll('svg, img, canvas')) {
      if (el.closest('[role="dialog"]') || el.closest('#shell-bar')) continue;
      const r = el.getBoundingClientRect();
      if (r.width >= pr.width * 0.8 && r.height >= pr.height * 0.5) {
        if (!el.hasAttribute('data-shell-wallpaper')) { el.setAttribute('data-shell-wallpaper', ''); n++ }
      }
    }
    return n;
  }

  function clearWallpaper() {
    for (const el of document.querySelectorAll('[data-shell-wallpaper]')) {
      el.removeAttribute('data-shell-wallpaper');
    }
  }

  function clearPinStrip() {
    for (const el of document.querySelectorAll('[data-shell-pinstrip]')) {
      el.removeAttribute('data-shell-pinstrip');
    }
  }

  function clearAncestors() {
    for (const el of document.querySelectorAll('[data-shell-ancestor]')) {
      el.removeAttribute('data-shell-ancestor');
    }
  }

  function clearCollapsed() {
    for (const el of document.querySelectorAll('[data-shell-collapsed]')) {
      el.removeAttribute('data-shell-collapsed');
    }
  }

  /* Companion mode. The list is only allowed to collapse once a conversation is
     open AND still has width without it — otherwise the companion window would
     be an empty box with no way to choose a chat. Re-checked on the pump. */
  function setCompact(on) {
    cfg.compact = !!on;
    if (!cfg.compact) {
      R().removeAttribute('data-shell-compact');
      R().removeAttribute('data-shell-compact-list');
      R().removeAttribute('data-shell-compact-more');
      clearBubbleTags();
      clearCollapsed();
      R().removeAttribute('data-shell-convo-open');
      clearAncestors();
      clearPinStrip();
      clearWallpaper();
      for (const el of document.querySelectorAll('[data-shell-out],[data-shell-in]')) {
        el.removeAttribute('data-shell-out'); el.removeAttribute('data-shell-in');
      }
      ensureCompactBar();                 // removes it
      return { compact: false };
    }
    tagRail(); tagList();
    R().setAttribute('data-shell-compact', '');
    const state = reconsiderCompactList();
    ensureCompactBar();
    tagBubbles();
    collapseChrome();
    tagAncestors();
    tagPinStrip();
    tagWallpaper();
    return Object.assign(state, compactMetrics());
  }

  function reconsiderCompactList() {
    if (!cfg.compact) return { compact: false };
    const pane = tagConvoPane();
    if (!pane) {                                   // nothing open: keep the list
      R().removeAttribute('data-shell-compact-list');
      return { compact: true, listHidden: false, reason: 'no conversation open' };
    }
    R().setAttribute('data-shell-compact-list', '');
    // If collapsing the list somehow collapsed the conversation too, undo it
    // rather than leaving him with a blank panel.
    if (pane.offsetWidth < 80) {
      R().removeAttribute('data-shell-compact-list');
      return { compact: true, listHidden: false, reason: 'conversation lost width' };
    }
    return { compact: true, listHidden: true };
  }

  /* ── 3b2. how wide WhatsApp insists on being ───────────────────────────────
     Companion mode asks the app to squeeze into a narrow panel. WhatsApp's
     layout has desktop minimums, and when it cannot meet them the webview clips
     rather than reflows. theme.css strips those minimums; this reports whatever
     width it still demands so the app can scale the page to fit instead of
     leaving him with a cropped corner. */

  function compactMetrics() {
    const pane = tagConvoPane();
    const r = pane ? pane.getBoundingClientRect() : null;
    return {
      hasConvo:   !!(r && r.width > 60),
      convoLeft:  r ? Math.round(r.left)  : 0,
      convoWidth: r ? Math.round(r.width) : 0,
      inner:      window.innerWidth,
      scroll:     Math.max(document.documentElement.scrollWidth, document.body.scrollWidth || 0),
      bubbles:    document.querySelectorAll('[data-shell-bubble]').length,
      railTagged: !!document.querySelector('[data-shell-rail]'),
      listTagged: !!document.querySelector('[data-shell-list]'),
      collapsed:  document.querySelectorAll('[data-shell-collapsed]').length,
      // Hairline hunt: any element inside the pane that is a thin, tall sliver is
      // almost certainly the stray vertical line. Also list the pane's top-level
      // children so decorative strips can be identified.
      thin: (() => {
        // Document-wide, not pane-only: collapseChrome deliberately skips
        // absolutely-positioned elements, so a stray rule can live outside.
        const pane = document.body;
        if (!pane) return [];
        return Array.from(pane.querySelectorAll('*')).filter(e => {
          const r = e.getBoundingClientRect();
          return r.width > 0 && r.width <= 3 && r.height > 40;
        }).slice(0, 6).map(e => {
          const r = e.getBoundingClientRect();
          const cs = getComputedStyle(e);
          return { tag: e.tagName, cls: String(e.className || '').slice(0, 26),
                   x: Math.round(r.left), w: +r.width.toFixed(1), h: Math.round(r.height),
                   bg: cs.backgroundColor, bl: cs.borderLeftWidth, pos: cs.position };
        });
      })(),
      // Who is still painting the doodle wallpaper?
      bgimg: (() => {
        const pane = document.querySelector('[data-shell-convo]');
        if (!pane) return [];
        const out = [];
        for (const e of [pane, ...pane.querySelectorAll('*')]) {
          const cs = getComputedStyle(e);
          if (cs.backgroundImage && cs.backgroundImage !== 'none') {
            const r = e.getBoundingClientRect();
            out.push({ tag: e.tagName, cls: String(e.className || '').slice(0, 22),
                       w: Math.round(r.width), h: Math.round(r.height),
                       img: cs.backgroundImage.slice(0, 40), op: cs.opacity, pos: cs.position });
          }
          if (out.length >= 5) break;
        }
        // pseudo-elements too
        for (const which of ['::before', '::after']) {
          const cs = getComputedStyle(pane, which);
          if (cs.backgroundImage && cs.backgroundImage !== 'none') {
            out.push({ tag: 'pane' + which, img: cs.backgroundImage.slice(0, 40), op: cs.opacity });
          }
        }
        return out;
      })(),
      // Exactly which element between the row and the bubble holds the dead space
      // on the right? Measured instead of guessed.
      outChain: (() => {
        const row = document.querySelector('[role="row"][data-shell-out]');
        const bub = row && row.querySelector('[data-shell-bubble]');
        if (!row || !bub) return [];
        const out = [];
        let el = bub;
        while (el && el !== row.parentElement) {
          const r = el.getBoundingClientRect();
          const cs = getComputedStyle(el);
          out.push({ tag: el.TAG || el.tagName, right: Math.round(r.right), w: Math.round(r.width),
                     pr: cs.paddingRight, mr: cs.marginRight, disp: cs.display,
                     jc: cs.justifyContent, mw: cs.maxWidth });
          el = el.parentElement;
        }
        return out;
      })(),
      viewportRight: Math.round(window.innerWidth),
      wallpapers: document.querySelectorAll('[data-shell-wallpaper]').length,
      kids: (() => {
        const pane = document.querySelector('[data-shell-convo]');
        if (!pane) return [];
        return Array.from(pane.children).map(e => {
          const r = e.getBoundingClientRect();
          return { tag: e.tagName, cls: String(e.className || '').slice(0, 20),
                   x: Math.round(r.left), w: Math.round(r.width), h: Math.round(r.height) };
        });
      })(),
      // What is painting at these x positions?
      probe: [0.06, 0.12, 0.56].map(f => {
        const x = Math.round(window.innerWidth * f);
        const y = Math.round(window.innerHeight * 0.5);
        const el = document.elementFromPoint(x, y);
        if (!el) return { x, el: null };
        const cs = getComputedStyle(el);
        return { x, tag: el.tagName, cls: String(el.className || '').slice(0, 26),
                 bl: cs.borderLeftWidth, br: cs.borderRightWidth, bg: cs.backgroundColor,
                 w: Math.round(el.getBoundingClientRect().width) };
      })
    };
  }

  /* Widen the bubbles. WhatsApp caps each one at max-width:65% on a single div
     inside the row (depth 5, obfuscated class — measured live). The class name
     churns between deploys, so find it by what it DOES: the descendant whose
     computed max-width is a percentage under 100. Tag it, and theme.css widens
     whatever was tagged. Rows are recycled, so this is idempotent per row. */
  function tagBubbles() {
    if (!cfg.compact) return 0;
    const pane = document.querySelector('[data-shell-convo]');
    if (!pane) return 0;
    let tagged = 0;
    for (const row of pane.querySelectorAll('[role="row"]:not([data-shell-out]):not([data-shell-in])')) {
      row.setAttribute('data-shell-bubbled', '');
      for (const el of row.querySelectorAll('div')) {
        const mw = getComputedStyle(el).maxWidth;
        if (mw && mw.endsWith('%') && parseFloat(mw) < 100) {
          el.setAttribute('data-shell-bubble', '');
          tagged++;
          // Which side is it on? First ask WhatsApp: it draws a "tail-out" glyph
          // on his own messages and "tail-in" on the other person's (both seen
          // live). Only if neither is present fall back to geometry — and compare
          // the LEFT gap against the RIGHT gap rather than the bubble's centre,
          // because at 97% width every centre lands on the pane's centre, which
          // is why an earlier centre-based test tagged nothing at all.
          if (row.querySelector('[data-icon="tail-out"]')) {
            row.setAttribute('data-shell-out', '');
          } else if (row.querySelector('[data-icon="tail-in"]')) {
            row.setAttribute('data-shell-in', '');
          } else {
            const b = el.getBoundingClientRect();
            const p = pane.getBoundingClientRect();
            if (b.width > 0) {
              const gapLeft = b.left - p.left, gapRight = p.right - b.right;
              row.setAttribute(gapRight <= gapLeft ? 'data-shell-out' : 'data-shell-in', '');
            }
          }
          break;                       // the outermost capped div is the bubble
        }
      }
    }
    return tagged;
  }

  function clearBubbleTags() {
    for (const el of document.querySelectorAll('[data-shell-bubbled]')) el.removeAttribute('data-shell-bubbled');
    for (const el of document.querySelectorAll('[data-shell-bubble]'))  el.removeAttribute('data-shell-bubble');
  }

  /* The companion bar: just the name, a way back to all chats, and a way to get
     WhatsApp's own header back when he wants to call or search. Lives in <body>
     rather than inside the conversation, because React owns that subtree and
     would eventually strip out a foreign child. */
  function ensureCompactBar() {
    let bar = document.getElementById('shell-bar');
    if (!cfg.compact) { if (bar) bar.remove(); return false }

    if (!bar) {
      bar = document.createElement('div');
      bar.id = 'shell-bar';

      const back = document.createElement('button');
      back.id = 'shell-back';
      back.textContent = '‹';
      back.title = 'Back to all chats';
      back.addEventListener('click', (e) => {
        e.preventDefault(); e.stopPropagation();
        post({ type: 'exitCompact' });
      });

      const name = document.createElement('span');
      name.id = 'shell-name';

      const more = document.createElement('button');
      more.id = 'shell-more';
      more.textContent = '⋯';
      more.title = 'Show more';
      more.addEventListener('click', (e) => {
        e.preventDefault(); e.stopPropagation();
        R().toggleAttribute('data-shell-compact-more');
      });

      bar.append(back, name, more);
      document.body.appendChild(bar);
    }

    const label = bar.querySelector('#shell-name');
    const who = currentChatName() || 'No chat open';
    if (label && label.textContent !== who) label.textContent = who;
    return true;
  }

  /* ── 3b3. silence ──────────────────────────────────────────────────────────
     WhatsApp plays its own message beep through an <audio> element, entirely
     separately from the macOS notification sound — and that beep is the loud one.
     Muting all audio would break voice notes and calls, so this blocks only
     PROGRAMMATIC playback: sound WhatsApp starts by itself with no recent user
     gesture. Pressing play on a voice note is a gesture, so it still plays. And
     looping audio is let through, because that is what a ringtone is — an
     incoming call should still be able to ring. */

  let lastGesture = 0;
  for (const ev of ['pointerdown', 'mousedown', 'keydown', 'touchstart']) {
    window.addEventListener(ev, () => { lastGesture = Date.now() }, true);
  }

  let audioPatched = false;
  function setSounds(on) {
    cfg.sounds = !!on;
    if (audioPatched) return cfg.sounds;      // patched once; the patch reads cfg live
    try {
      const proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
      if (!proto || !proto.play) return cfg.sounds;
      const originalPlay = proto.play;
      proto.play = function () {
        // 250ms, not 1000ms. A click that starts a voice note calls play() within
        // a few milliseconds; a full second was wide enough that any incoming
        // message arriving while he typed got its beep through — which is exactly
        // what he kept hearing.
        const programmatic = Date.now() - lastGesture > 250;
        if (!cfg.sounds && programmatic && !this.loop) {
          try { this.pause(); this.currentTime = 0 } catch (e) {}
          return Promise.resolve();           // resolve so WhatsApp's own code doesn't throw
        }
        return originalPlay.apply(this, arguments);
      };
      // Belt and braces: a beep played through Web Audio would bypass the
      // media-element patch entirely.
      const ABSN = window.AudioBufferSourceNode && window.AudioBufferSourceNode.prototype;
      if (ABSN && ABSN.start) {
        const originalStart = ABSN.start;
        ABSN.start = function () {
          if (!cfg.sounds && Date.now() - lastGesture > 250) return;
          return originalStart.apply(this, arguments);
        };
      }
      audioPatched = true;
    } catch (e) {}
    return cfg.sounds;
  }

  /* ── 3c. typography ────────────────────────────────────────────────────────── */

  function setFont(family) {
    cfg.font = family || '';
    if (cfg.font) {
      R().style.setProperty('--shell-font', cfg.font);
      R().setAttribute('data-shell-font', '');
    } else {
      R().style.removeProperty('--shell-font');
      R().removeAttribute('data-shell-font');
    }
    return cfg.font;
  }

  // All three typography controls share this shape: a number in px, where 0 means
  // "leave WhatsApp's own value alone" — so every one of them has an off switch
  // rather than a "close enough to default" setting.
  function setPixelVar(value, cssVar, attr, key) {
    cfg[key] = Number(value) || 0;
    if (cfg[key] > 0) {
      R().style.setProperty(cssVar, cfg[key] + 'px');
      R().setAttribute(attr, '');
    } else {
      R().style.removeProperty(cssVar);
      R().removeAttribute(attr);
    }
    return cfg[key];
  }

  function setMsgSize(px)  { return setPixelVar(px, '--shell-msg-size',  'data-shell-msgsize',  'msgSize') }
  function setNameSize(px) { return setPixelVar(px, '--shell-name-size', 'data-shell-namesize', 'nameSize') }
  function setMsgGap(px)   { return setPixelVar(px, '--shell-msg-gap',   'data-shell-msggap',   'msgGap') }


  /* ── 4. notifications ──────────────────────────────────────────────────────
     WKWebView exposes no Notification API, so we install one unconditionally
     (rather than only when missing) — a half-working native implementation that
     reports permission "denied" would leave him silently un-notified, which is
     the exact failure this app exists to fix. */

  let seq = 0;
  const live = new Map();

  function ShellNotification(title, opts) {
    opts = opts || {};
    const id = 'n' + (++seq);
    this.title = String(title == null ? '' : title);
    this.body  = String(opts.body || '');
    this.tag   = String(opts.tag  || '');
    this.icon  = String(opts.icon || '');
    this.data  = opts.data;
    this.onclick = this.onclose = this.onerror = this.onshow = null;
    this._id = id;
    live.set(id, this);
    post({ type: 'notify', id, title: this.title, body: this.body, tag: this.tag });
    if (live.size > 64) live.delete(live.keys().next().value);
    setTimeout(() => { if (typeof this.onshow === 'function') try { this.onshow({}) } catch (e) {} }, 0);
  }
  ShellNotification.prototype.close = function () {
    post({ type: 'notify-close', id: this._id, tag: this.tag });
    live.delete(this._id);
    if (typeof this.onclose === 'function') try { this.onclose({}) } catch (e) {}
  };
  ShellNotification.prototype.addEventListener = function (t, fn) { this['on' + t] = fn };
  ShellNotification.prototype.removeEventListener = function (t) { this['on' + t] = null };
  ShellNotification.prototype.dispatchEvent = function () { return true };
  Object.defineProperty(ShellNotification, 'permission', { get: () => 'granted', configurable: true });
  ShellNotification.maxActions = 0;
  ShellNotification.requestPermission = function (cb) {
    if (typeof cb === 'function') { try { cb('granted') } catch (e) {} }
    return Promise.resolve('granted');
  };

  try {
    Object.defineProperty(window, 'Notification',
      { value: ShellNotification, writable: true, configurable: true });
  } catch (e) { window.Notification = ShellNotification }

  // Some builds notify through the service worker instead.
  try {
    const P = window.ServiceWorkerRegistration && window.ServiceWorkerRegistration.prototype;
    if (P && !P.showNotification) {
      P.showNotification   = function (t, o) { new ShellNotification(t, o); return Promise.resolve() };
      P.getNotifications   = function () { return Promise.resolve([]) };
    }
  } catch (e) {}

  // Native → page: the user clicked a macOS notification.
  function notificationClicked(id, chat) {
    const n = live.get(id);
    if (n && typeof n.onclick === 'function') {
      try { n.onclick({ target: n, preventDefault() {}, stopPropagation() {} }); return true } catch (e) {}
    }
    if (chat) { openChat(chat); return true }   // fall back to opening it ourselves
    return false;
  }

  /* ── 5. Dock badge ─────────────────────────────────────────────────────────
     WhatsApp maintains the aggregate itself in the document title — "(3)
     WhatsApp" — which is more reliable than summing per-row unread pills
     (those include muted chats and only the rendered slice of the list). */

  let lastBadge = -1;
  function pumpBadge() {
    const m = /^\((\d+)\)/.exec(document.title || '');
    const n = m ? parseInt(m[1], 10) : 0;
    if (n !== lastBadge) { lastBadge = n; post({ type: 'badge', count: n }) }
  }

  /* ── 6. driving the UI: open a chat, focus search, start a new chat ─────── */

  function realClick(el) {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    const o = { bubbles: true, cancelable: true, view: window,
                clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
    for (const t of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
      try {
        el.dispatchEvent(t.startsWith('pointer') ? new PointerEvent(t, o) : new MouseEvent(t, o));
      } catch (e) { try { el.click() } catch (_) {} }
    }
    return true;
  }

  function rowTitle(row) {
    const cell = row.querySelector('[data-testid="cell-frame-title"]');
    if (!cell) return '';
    const span = cell.querySelector('span[title]');
    if (span) return span.getAttribute('title') || span.textContent || '';
    return cell.textContent || '';
  }

  function visibleRows() {
    return Array.from(document.querySelectorAll(
      '[data-testid^="list-item-"], #pane-side [role="listitem"], #pane-side [role="row"]'));
  }

  function clickRowMatching(name) {
    const want = norm(name);
    if (!want) return false;
    for (const row of visibleRows()) {
      if (norm(rowTitle(row)) === want) {
        realClick(row.querySelector('[data-testid="cell-frame-container"]') || row);
        return true;
      }
    }
    return false;
  }

  function searchInput() { return document.querySelector('input[data-tab="3"]') }

  // React owns this input's value, so assigning .value directly is ignored —
  // the native setter plus a bubbling 'input' event is what actually registers.
  function setSearch(input, text) {
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    input.focus();
    setter.call(input, text);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }

  async function openChat(name) {
    if (!name) return false;
    if (clickRowMatching(name)) return true;

    const input = searchInput();
    if (!input) return false;
    setSearch(input, name);

    let opened = false;
    for (let i = 0; i < 20 && !opened; i++) {
      await sleep(90);
      opened = clickRowMatching(name);
    }
    if (!opened) {
      // No exact title match surfaced; take the first result rather than nothing.
      opened = realClick(document.querySelector('[data-testid="cell-frame-container"]'));
    }
    setTimeout(() => { try { setSearch(input, ''); input.blur() } catch (e) {} }, 300);
    return opened;
  }

  function focusSearch() { const i = searchInput(); if (i) { i.focus(); return true } return false }

  function newChat() {
    const icon = document.querySelector('[data-icon="new-chat-outline"]');
    const btn = icon && (icon.closest('button, [role="button"]') || icon);
    return realClick(btn);
  }

  /* ── 7. which chat is open (so "Pin This Chat" needs no typing) ─────────── */

  function currentChatName() {
    const pane = convoPane();
    if (pane) {
      const header = pane.querySelector('header');
      if (header) {
        const titled = header.querySelector('span[title]');
        if (titled) {
          const t = titled.getAttribute('title') || titled.textContent;
          if (t && t.trim()) return t.trim();
        }
        // Measured live: this build puts the chat name in a span[dir="auto"] with
        // no title attribute — which is why the span[title] lookup above found
        // nothing and "Pin This Chat" kept asking him to type the name instead.
        const dirAuto = header.querySelector('span[dir="auto"]');
        if (dirAuto && dirAuto.textContent.trim()) return dirAuto.textContent.trim();
        const span = header.querySelector('span');
        if (span && span.textContent.trim()) return span.textContent.trim();
      }
    }
    // Fall back to whichever chat-list row is marked selected.
    for (const row of visibleRows()) {
      const selected = row.getAttribute('aria-selected') === 'true'
                    || !!row.querySelector('[aria-selected="true"]');
      if (selected) { const t = rowTitle(row); if (t && t.trim()) return t.trim() }
    }
    return '';
  }

  /* ── 7b. sending a reply, verified before it goes ──────────────────────────
     Used by "reply from the notification". Sending the wrong thing to a real
     person is unacceptable, so this NEVER presses send unless the composer holds
     exactly the text it was given — and reports why if it doesn't. */

  function composerBox() {
    const pane = convoPane();
    return pane ? pane.querySelector('[contenteditable="true"]') : null;
  }

  function sendButton() {
    const pane = convoPane() || document;
    return pane.querySelector('[data-icon="send"], button[aria-label="Send"], [role="button"][aria-label="Send"]');
  }

  async function replyTo(chat, text) {
    if (!text) return { ok: false, reason: 'empty message' };
    if (chat) {
      const opened = await openChat(chat);
      if (!opened) return { ok: false, reason: 'could not open ' + chat };
      await sleep(450);
    }
    const box = composerBox();
    if (!box) return { ok: false, reason: 'no composer found' };
    box.focus();

    // execCommand('insertText') raises real beforeinput/input events, which is
    // what WhatsApp's editor listens for. Assigning textContent is ignored.
    let inserted = false;
    try { inserted = document.execCommand('insertText', false, text) } catch (e) {}
    if (!inserted) {
      try {
        const dt = new DataTransfer();
        dt.setData('text/plain', text);
        box.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
        inserted = true;
      } catch (e) {}
    }
    await sleep(200);

    const got = norm(box.innerText || box.textContent || '');
    if (got !== norm(text)) {
      return { ok: false, reason: 'composer did not take the text — left it open, nothing sent' };
    }

    const btn = sendButton();
    if (btn) realClick(btn);
    else {
      for (const t of ['keydown', 'keypress', 'keyup']) {
        box.dispatchEvent(new KeyboardEvent(t, { key: 'Enter', code: 'Enter',
                                                 keyCode: 13, which: 13,
                                                 bubbles: true, cancelable: true }));
      }
    }
    await sleep(300);
    const cleared = norm(box.innerText || box.textContent || '') === '';
    return cleared ? { ok: true } : { ok: false, reason: 'composer never cleared — may not have sent' };
  }

  /* ── 8. state, for the app and for the headless smoke test ─────────────── */

  function state() {
    return {
      linked:      !!document.querySelector('#pane-side'),
      cssInstalled: !!document.getElementById('shell-style'),
      tokensFound: !!getComputedStyle(R()).getPropertyValue('--WDS-accent').trim(),
      theme:       R().getAttribute('data-shell-theme') || 'stock',
      hidden:      HIDEABLE.filter(k => R().hasAttribute('data-shell-hide-' + k)),
      privacy:     R().hasAttribute('data-shell-privacy'),
      privacyFallback: R().hasAttribute('data-shell-privacy-fallback'),
      convoTagged: !!document.querySelector('[data-shell-convo]'),
      railTagged:  !!document.querySelector('[data-shell-rail]'),
      listTagged:  !!document.querySelector('[data-shell-list]'),
      compact:     R().hasAttribute('data-shell-compact'),
      compactList: R().hasAttribute('data-shell-compact-list'),
      font:        R().style.getPropertyValue('--shell-font') || '',
      msgSize:     R().style.getPropertyValue('--shell-msg-size') || '',
      nameSize:    R().style.getPropertyValue('--shell-name-size') || '',
      msgGap:      R().style.getPropertyValue('--shell-msg-gap') || '',
      sounds:      cfg.sounds === true,
      collapsed:   document.querySelectorAll('[data-shell-collapsed]').length,
      storageShim: true,
      errors:      errCount,
      notificationShim: window.Notification === ShellNotification,
      unread:      lastBadge < 0 ? 0 : lastBadge,
      chat:        currentChatName(),
      rows:        visibleRows().length,
      navItems:    document.querySelectorAll('[data-navbar-item]').length
    };
  }

  /* ── 8b. storage persistence ───────────────────────────────────────────────
     WhatsApp asks for persistent storage on boot. WKWebView has no such API, and
     even Chrome declines it (observed live in his browser: "storage bucket
     persistence denied"). Left unanswered, WhatsApp logs an error every launch
     and may trim its caches. Answering yes is accurate here for a different
     reason than in a browser: this data store is the app's own container, not
     site data competing for a shared quota, so nothing is going to evict it. */

  try {
    if (window.StorageManager && StorageManager.prototype) {
      StorageManager.prototype.persist = function () { return Promise.resolve(true) };
      StorageManager.prototype.persisted = function () { return Promise.resolve(true) };
    }
    if (!navigator.storage) {
      Object.defineProperty(navigator, 'storage', {
        value: {
          persist:   () => Promise.resolve(true),
          persisted: () => Promise.resolve(true),
          estimate:  () => Promise.resolve({ quota: 0, usage: 0 })
        }, configurable: true
      });
    }
  } catch (e) {}

  /* ── 8c. page errors → the app ─────────────────────────────────────────────
     A WKWebView has no visible console, so page errors are otherwise invisible.
     Forward them (capped, so a shouting page can't flood) — the app logs them and
     the smoke test asserts on them. */

  let errCount = 0;
  const MAX_ERRORS = 40;
  function reportError(kind, msg) {
    if (errCount++ >= MAX_ERRORS) return;
    post({ type: 'pageerror', kind, message: String(msg).slice(0, 400) });
  }
  window.addEventListener('error', e =>
    reportError('error', e.message || (e.error && e.error.message) || 'script error'));
  window.addEventListener('unhandledrejection', e =>
    reportError('rejection', (e.reason && (e.reason.message || e.reason)) || 'unhandled rejection'));
  const origConsoleError = console.error;
  console.error = function (...a) {
    try { reportError('console', a.map(x => (x && x.message) || String(x)).join(' ')) } catch (e) {}
    return origConsoleError.apply(this, a);
  };

  /* ── 9. boot ───────────────────────────────────────────────────────────── */

  installCSS();
  applyTheme(cfg.theme);
  applyHide(cfg.hide);
  applyPrivacy(cfg.privacy);
  setFont(cfg.font || '');
  setMsgSize(cfg.msgSize || 0);
  setNameSize(cfg.nameSize || 0);
  setMsgGap(cfg.msgGap || 0);
  setSounds(cfg.sounds === true);
  if (cfg.compact) setCompact(true);

  window.__shell = {
    applyTheme, applyHide, applyPrivacy, openChat, currentChatName,
    focusSearch, newChat, notificationClicked, checkPrivacyCoverage, state,
    setCompact, setFont, setMsgSize, setNameSize, setMsgGap, replyTo,
    setSounds, compactMetrics, tagBubbles
  };

  let announcedLink = false;
  setInterval(() => {
    installCSS();
    ensureAttributes();
    pumpBadge();
    tagConvoPane();
    tagRail();
    tagList();
    if (cfg.compact) { reconsiderCompactList(); ensureCompactBar(); tagBubbles(); collapseChrome(); tagAncestors(); tagPinStrip(); tagWallpaper() }
    if (cfg.privacy) checkPrivacyCoverage();
    if (!announcedLink && document.querySelector('#pane-side')) {
      announcedLink = true;
      post({ type: 'linked' });
    }
  }, 1000);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => { installCSS(); ensureAttributes() }, { once: true });
  }
  post({ type: 'ready' });
})();
