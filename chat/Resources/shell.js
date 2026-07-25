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

  /* Companion mode. The list is only allowed to collapse once a conversation is
     open AND still has width without it — otherwise the companion window would
     be an empty box with no way to choose a chat. Re-checked on the pump. */
  function setCompact(on) {
    cfg.compact = !!on;
    if (!cfg.compact) {
      R().removeAttribute('data-shell-compact');
      R().removeAttribute('data-shell-compact-list');
      return { compact: false };
    }
    tagRail(); tagList();
    R().setAttribute('data-shell-compact', '');
    return reconsiderCompactList();
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

  function compactFit() {
    return {
      inner:  window.innerWidth,
      scroll: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth || 0),
      railTagged: !!document.querySelector('[data-shell-rail]'),
      listTagged: !!document.querySelector('[data-shell-list]'),
      listHidden: R().hasAttribute('data-shell-compact-list'),
      convoWidth: (document.querySelector('[data-shell-convo]') || {}).offsetWidth || 0
    };
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
        const programmatic = Date.now() - lastGesture > 1000;
        if (!cfg.sounds && programmatic && !this.loop) {
          try { this.pause(); this.currentTime = 0 } catch (e) {}
          return Promise.resolve();           // resolve so WhatsApp's own code doesn't throw
        }
        return originalPlay.apply(this, arguments);
      };
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

  /* ── 3d. focus mode — only the pinned chats in the list ───────────────────── */

  function setFocus(on, names) {
    cfg.focus = !!on;
    if (Array.isArray(names)) cfg.pins = names.filter(Boolean).map(norm);
    if (cfg.focus) R().setAttribute('data-shell-focus', '');
    else {
      R().removeAttribute('data-shell-focus');
      for (const row of visibleRows()) row.removeAttribute('data-shell-dim');
    }
    markFocusRows();
    return cfg.focus;
  }

  /* What survives focus mode. Deliberately requires NO setup: an earlier version
     only kept the app's own ⌘1–9 pins, which meant it refused to turn on until
     you had configured a second, parallel notion of "pinned" alongside
     WhatsApp's. Labern's verdict, and he was right: "it shouldn't need to be
     pinned anyway."

     So a row stays if it plausibly wants attention right now:
       · it has unread messages
       · it is the conversation currently open
       · WhatsApp itself has it pinned
       · or it is one of the app's ⌘1–9 pins, if any are set */
  function focusKeep(row, appPins) {
    if (row.querySelector('[data-testid="icon-unread-count"]')) return true;
    if (row.getAttribute('aria-selected') === 'true'
        || row.querySelector('[aria-selected="true"]')) return true;
    try { if (row.querySelector('[data-icon*="pin" i]')) return true } catch (e) {}
    return appPins.size > 0 && appPins.has(norm(rowTitle(row)));
  }

  // Rows are virtualised and recycled, so this has to re-run on the pump.
  function markFocusRows() {
    if (!cfg.focus) return 0;
    const appPins = new Set(cfg.pins || []);
    const rows = visibleRows();
    const keep = rows.filter(r => focusKeep(r, appPins));

    // Nothing demands attention: show everything rather than an empty list. An
    // empty panel reads as "the app broke", not as "you're all caught up".
    if (!keep.length) {
      for (const row of rows) row.removeAttribute('data-shell-dim');
      return 0;
    }
    let hidden = 0;
    for (const row of rows) {
      if (keep.includes(row)) row.removeAttribute('data-shell-dim');
      else { row.setAttribute('data-shell-dim', ''); hidden++ }
    }
    return hidden;
  }

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
      focus:       R().hasAttribute('data-shell-focus'),
      focusHidden: document.querySelectorAll('[data-shell-dim]').length,
      sounds:      cfg.sounds === true,
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
  if (cfg.focus) setFocus(true, cfg.pins || []);

  window.__shell = {
    applyTheme, applyHide, applyPrivacy, openChat, currentChatName,
    focusSearch, newChat, notificationClicked, checkPrivacyCoverage, state,
    setCompact, setFont, setMsgSize, setNameSize, setMsgGap, setFocus, replyTo,
    setSounds, compactFit
  };

  let announcedLink = false;
  setInterval(() => {
    installCSS();
    ensureAttributes();
    pumpBadge();
    tagConvoPane();
    tagRail();
    tagList();
    if (cfg.compact) reconsiderCompactList();
    if (cfg.focus) markFocusRows();
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
