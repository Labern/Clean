/* Once — runs on every page, in every frame, after engine.js.

   Fills on sight: any form with two or more things it knows about you
   (signup, checkout, address) or a login form, the moment it appears —
   including forms an SPA renders late. Anything else (a lone email box)
   fills the moment you click into it.

   Never overwrites what's there, never refills a field you cleared or
   edited, never touches invisible fields (honeypots). */
(() => {
  const ext = globalThis.browser || globalThis.chrome;
  const host = location.hostname;
  const taken = new WeakSet();   // fields the user has taken back: never touch again
  const ours = new WeakSet();    // fields we filled
  let S = null;                  // { profile, sites, def, eager, off }

  const SETUP = location.origin === 'https://labern.github.io' && location.pathname.startsWith('/Clean/once/');

  function emailFor() {
    const e = S.profile.emails || [];
    return e[S.sites[host] ?? S.def ?? 0] || e[0] || '';
  }

  function run(groupFilter, force) {
    if (!S || !S.profile || S.off.includes(host)) return 0;
    let n = 0, emailEl = null;
    for (const [g, els] of Once.groups(document)) {
      if (groupFilter && g !== groupFilter) continue;
      const p = Once.plan(els);
      if (!force && !groupFilter && !(S.eager && p.eager)) continue;
      const done = Once.fill(p.items, S.profile, emailFor(), taken);
      for (const d of done) { ours.add(d.el); if (d.key === 'email' && !emailEl) emailEl = d.el; }
      n += done.length;
    }
    if (emailEl && (S.profile.emails || []).length > 1) chip(emailEl);
    return n;
  }

  // ---- the chip: one tap swaps gmail ⇄ icloud for this site, and remembers
  let chipHost = null, chipAnchor = null;
  function chip(anchor) {
    chipAnchor = anchor;
    if (!chipHost) {
      chipHost = document.createElement('once-chip');
      const sh = chipHost.attachShadow({ mode: 'closed' });
      sh.innerHTML = `<style>
        :host{all:initial;position:absolute;z-index:2147483647}
        button{all:unset;cursor:pointer;font:600 11px/1 -apple-system,system-ui,sans-serif;
          color:#0b0f14;background:#5eead4;padding:5px 9px;border-radius:999px;
          box-shadow:0 2px 10px rgba(0,0,0,.25);white-space:nowrap}
        button:hover{background:#99f6e4}</style><button title="Once: use your other email here"></button>`;
      chipHost._btn = sh.querySelector('button');
      chipHost._btn.addEventListener('mousedown', e => e.preventDefault());
      chipHost._btn.addEventListener('click', swap);
    }
    const r = anchor.getBoundingClientRect();
    const other = S.profile.emails.find(e => e !== emailFor()) || '';
    chipHost._btn.textContent = '⇄ ' + other.split('@')[1];
    chipHost.style.left = Math.max(0, r.right + scrollX - 4) + 'px';
    chipHost.style.top = (r.top + scrollY - 10) + 'px';
    chipHost.style.transform = 'translateX(-100%)';
    document.documentElement.appendChild(chipHost);
    clearTimeout(chipHost._t);
    chipHost._t = setTimeout(() => chipHost.remove(), 6000);
  }

  function swap() {
    const emails = S.profile.emails || [];
    if (emails.length < 2) return;
    const i = (emails.indexOf(emailFor()) + 1) % emails.length;
    S.sites[host] = i;
    ext.storage.local.set({ sites: S.sites });
    Once.swapEmail(document, emails, emails[i]);
    if (chipAnchor?.isConnected) chip(chipAnchor);
  }

  // ---- the user is in charge
  document.addEventListener('input', e => {
    const el = e.composedPath()[0];
    if (!e.isTrusted || !S) return;
    if (ours.has(el)) taken.add(el);
    // typed one of your emails by hand → that's the one for this site
    const i = (S.profile?.emails || []).indexOf(el.value);
    if (i >= 0 && S.sites[host] !== i) { S.sites[host] = i; ext.storage.local.set({ sites: S.sites }); }
  }, true);

  document.addEventListener('focusin', e => {
    const el = e.composedPath()[0];
    if (!S || !el || !/^(INPUT|SELECT|TEXTAREA)$/.test(el.tagName)) return;
    const emails = S.profile?.emails || [];
    if (ours.has(el)) { if (emails.length > 1 && emails.includes(el.value)) chip(el); return; }
    if (taken.has(el) || el.value) return;
    if (Once.classify(el)) run(Once.groupOf(el));
  }, true);

  // ---- forms that appear late (SPAs, modals, multi-step checkouts)
  let t = 0, runs = 0;
  const later = () => { clearTimeout(t); t = setTimeout(() => { if (runs++ < 200) run(); }, 350); };
  new MutationObserver(later).observe(document.documentElement, { childList: true, subtree: true });

  ext.runtime.onMessage.addListener((m) => {
    if (m === 'fill') run(null, true);
    if (m === 'swap') swap();
  });

  ext.storage.onChanged.addListener(load);
  function load() {
    ext.storage.local.get(['profile', 'sites', 'def', 'eager', 'off'], v => {
      const before = S && S.profile && emailFor();
      S = { profile: v.profile || null, sites: v.sites || {}, def: v.def || 0, eager: v.eager !== false, off: v.off || [] };
      // email choice changed (popup, another tab): move this page over too
      if (before && S.profile && emailFor() !== before) Once.swapEmail(document, S.profile.emails || [], emailFor());
      run();
    });
  }
  load();

  // ---- setup handoff: the Once page passes your details straight in
  if (SETUP) {
    window.addEventListener('message', e => {
      if (e.source !== window || !e.data || e.data.type !== 'once-profile') return;
      const p = e.data.profile;
      if (!p || typeof p !== 'object') return;
      ext.storage.local.set({ profile: p }, () => window.postMessage({ type: 'once-ack' }, location.origin));
    });
    window.postMessage({ type: 'once-ready' }, location.origin);
  }
})();
