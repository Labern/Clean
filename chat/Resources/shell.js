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

  const cfg = Object.assign({ theme: 'stock', hide: {}, privacy: false },
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
      notificationShim: window.Notification === ShellNotification,
      unread:      lastBadge < 0 ? 0 : lastBadge,
      chat:        currentChatName(),
      rows:        visibleRows().length,
      navItems:    document.querySelectorAll('[data-navbar-item]').length
    };
  }

  /* ── 9. boot ───────────────────────────────────────────────────────────── */

  installCSS();
  applyTheme(cfg.theme);
  applyHide(cfg.hide);
  applyPrivacy(cfg.privacy);

  window.__shell = {
    applyTheme, applyHide, applyPrivacy, openChat, currentChatName,
    focusSearch, newChat, notificationClicked, checkPrivacyCoverage, state
  };

  let announcedLink = false;
  setInterval(() => {
    installCSS();
    ensureAttributes();
    pumpBadge();
    tagConvoPane();
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
