/* Once — the engine.
   Reads any form by meaning and fills what you already know. No site lists,
   no per-site setup: every field is classified from its own markup.

   Signal order, strongest first:
     1. the autocomplete attribute (the standard the site itself declared)
     2. type=email
     3. the field's machine names  (name, id)
     4. the field's human text     (label, aria-label, placeholder, title)
   Within 3 and 4 the rules run in order and the first match wins, with the
   "skip" rule first so card/phone/company/friend fields are never touched.

   Shared verbatim by the extension (content.js runs after this file) and the
   bookmarklet (tools/build.mjs wraps it). Pure DOM, no dependencies. */
(function (root) {
  'use strict';

  // autocomplete tokens → our keys ('skip' = a known token we must not fill)
  const AC = {
    'email': 'email', 'username': 'username',
    'name': 'name', 'given-name': 'first', 'family-name': 'last',
    'street-address': 'line1', 'address-line1': 'line1', 'address-line2': 'line2',
    'address-line3': 'skip', 'address-level2': 'city', 'address-level1': 'county',
    'address-level3': 'skip', 'address-level4': 'skip',
    'postal-code': 'postcode', 'country-name': 'country', 'country': 'country',
  };
  const AC_SKIP = /^(tel|cc-|new-password|current-password|one-time-code|organization|honorific|additional-name|nickname|bday|sex|url|photo|impp|transaction|language|webauthn)/;

  const SKIP_TYPES = /^(hidden|password|submit|button|reset|image|file|checkbox|radio|range|color|date|datetime-local|month|week|time|tel|url)$/;

  // Words that mean "this field is about something other than you".
  const SKIP = /\b(search|q|query|keywords?|coupon|promo|voucher|discount|gift|captcha|otp|one time|verification|verify code|card|cvv|cvc|expiry|expiration|iban|swift|sort code|account number|phone|mobile|tel|telephone|fax|birth|dob|age|company|organi[sz]ation|business|employer|job|website|url|message|comment|subject|vat|tax|referr?al|nick ?name|middle|friend|recipient|referee|emergency|guardian|parent|kin|file|pet|team|product|project|domain|shop|store|brand|amount|quantity|qty|cardholder|holder)\b/;
  const SOMEONE_ELSE = /\b(friend|recipient|referee|guardian|parent|kin|emergency|gift)\b/;

  const RULES = [
    ['email',    /\be ?mail|\bmail address\b/],
    ['username', /\b(user ?name|user ?id|login|log in|sign ?in|identifier|account)\b/],
    ['line2',    /\baddr(ess)? ?(line ?)?2\b|\bline ?2\b|\bapartment\b|\bapt\b|\bsuite\b|\bflat\b|\bunit\b|\bbuilding name\b|\bsecond line\b/],
    ['houseNo',  /\bhouse ?(number|no|num|nr|name ?(or|and) ?number)\b|\b(building|street) ?(number|no|nr)\b|^(house|no|number|nr)$/],
    ['postcode', /\bpost ?code\b|\bpostal\b|\bzip|\bpost ?cd\b|\bpcode\b|\beircode\b/],
    ['city',     /\b(city|town|locality|suburb|address level ?2)\b/],
    ['county',   /\b(county|state|province|region|address level ?1)\b/],
    ['country',  /\b(country|nation)\b/],
    ['line1',    /\baddr(ess)? ?(line ?)?1\b|\bline ?1\b|\bstreet ?address\b|\bfirst line\b|\baddress ?first\b/],
    ['first',    /\bfirst ?name\b|\bfore ?names?\b|\bgiven ?names?\b|\bfname\b|\bfirst\b|\bchristian name\b/],
    ['last',     /\blast ?name\b|\bsur ?name\b|\bfamily ?name\b|\blname\b|\blast\b|\bsecond name\b/],
    ['street',   /\bstreet\b|\broad\b/],
    ['line1',    /\baddress\b|\baddr\b/],
    ['name',     /\bname\b|\bfull ?name\b|\byour ?name\b/],
  ];

  // first, last, … are only "strong" (enough to fill a form unprompted) in company
  const STRONG = new Set(['first', 'last', 'name', 'email', 'line1', 'street', 'houseNo', 'city', 'postcode', 'line2', 'county']);

  const norm = s => (s || '')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/([a-zA-Z])(\d)/g, '$1 $2')
    .toLowerCase()
    .replace(/[^a-z0-9@]+/g, ' ')
    .trim();

  function textAround(el) {
    const out = [];
    if (el.labels) for (const l of el.labels) out.push(l.textContent);
    const by = el.getAttribute('aria-labelledby');
    if (by) for (const id of by.split(/\s+/)) {
      const n = el.ownerDocument.getElementById(id);
      if (n) out.push(n.textContent);
    }
    if (!out.length) {
      // no <label>: the nearest wrapper that holds only this field and some text
      let p = el.parentElement;
      for (let i = 0; p && i < 3; i++, p = p.parentElement) {
        if (p.querySelectorAll('input,select,textarea').length > 1) break;
        const t = p.textContent.replace(el.textContent, '').trim();
        if (t) { out.push(t.slice(0, 80)); break; }
      }
    }
    out.push(el.getAttribute('aria-label'), el.getAttribute('placeholder'), el.getAttribute('title'));
    return out.filter(Boolean).join(' ');
  }

  function rule(sig) {
    if (!sig) return null;
    if (SKIP.test(sig)) return 'skip';
    for (const [k, re] of RULES) if (re.test(sig)) return k;
    return null;
  }

  function classify(el) {
    const tag = el.tagName;
    const type = (el.getAttribute('type') || 'text').toLowerCase();
    if (tag === 'INPUT' && SKIP_TYPES.test(type)) return null;
    if (el.closest('[data-once-off]')) return null;
    if (type === 'search' || el.getAttribute('role') === 'searchbox' || el.closest('[role=search]')) return null;

    const ac = (el.getAttribute('autocomplete') || '').toLowerCase().split(/\s+/).pop();
    if (AC[ac]) return AC[ac] === 'skip' ? null : AC[ac];
    if (AC_SKIP.test(ac)) return null;

    let k = type === 'email' ? 'email' : null;
    if (!k) {
      const attrs = norm([el.name, el.id].join(' '));
      k = rule(attrs);
      // machine names are terse ("addr", "q"); when they say nothing, ask the label
      if (!k) k = rule(norm(textAround(el)));
    } else if (SOMEONE_ELSE.test(norm(textAround(el) + ' ' + el.name + ' ' + el.id))) {
      return null; // someone else's email
    }
    if (k === 'skip') return null;
    if (tag === 'TEXTAREA') return k === 'line1' || k === 'street' ? 'fulladdress' : null;
    if (tag === 'SELECT') return k === 'country' || k === 'county' ? k : null;
    if (type === 'number' && k !== 'houseNo') return null;
    return k;
  }

  function visible(el) {
    if (el.disabled || el.readOnly) return false;
    if (el.closest('[aria-hidden="true"],[hidden],[inert]')) return false;
    if (el.checkVisibility && !el.checkVisibility({ opacityProperty: true, visibilityProperty: true })) return false;
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return false;
    const w = el.ownerDocument.defaultView;
    // honeypots live off-canvas
    if (r.right < 0 || r.bottom + w.scrollY < 0 || r.left > Math.max(w.innerWidth, el.ownerDocument.documentElement.scrollWidth)) return false;
    return true;
  }

  // every field in a document, through open shadow roots
  function allFields(root) {
    const out = [];
    (function walk(n) {
      for (const el of n.querySelectorAll('*')) {
        if (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA') out.push(el);
        if (el.shadowRoot) walk(el.shadowRoot);
      }
    })(root);
    return out;
  }

  // the set of fields that belong together: the form, else the whole document
  function groupOf(el) {
    return el.form || el.getRootNode().host?.closest?.('form') || el.ownerDocument;
  }

  function groups(doc) {
    const m = new Map();
    for (const el of allFields(doc)) {
      const g = groupOf(el);
      if (!m.has(g)) m.set(g, []);
      m.get(g).push(el);
    }
    return m;
  }

  // classify a group and resolve the keys that depend on their neighbours
  function plan(els) {
    const items = [];
    let hasPw = false;
    for (const el of els) {
      if (el.tagName === 'INPUT' && (el.type === 'password') && visible(el)) hasPw = true;
      const key = classify(el);
      if (key && visible(el)) items.push({ el, key });
    }
    const keys = new Set(items.map(i => i.key));
    for (const i of items) {
      if (i.key === 'username' && keys.has('email')) i.key = null;          // signup handle: not ours
      else if (i.key === 'username') i.key = 'email';                        // login: email works as username
      if (i.key === 'line1' && keys.has('houseNo') && !keys.has('street')) i.key = 'street';
      if (i.key === 'street' && !keys.has('houseNo')) i.key = 'line1';
    }
    const live = items.filter(i => i.key);
    const strong = new Set(live.map(i => i.key).filter(k => STRONG.has(k)));
    return { items: live, hasPw, eager: strong.size >= 2 || (hasPw && strong.has('email')) };
  }

  function values(p, email) {
    const m = /^(\d+[a-z]?)[,\s]+(.+)$/i.exec(p.line1 || '');
    return {
      email,
      first: p.first, last: p.last,
      name: [p.first, p.last].filter(Boolean).join(' '),
      line1: p.line1, line2: p.line2 || '',
      houseNo: m ? m[1] : '', street: m ? m[2] : p.line1,
      city: p.city, county: p.county, postcode: p.postcode, country: p.country || 'United Kingdom',
      fulladdress: [p.line1, p.line2, p.city, p.county, p.postcode].filter(Boolean).join('\n'),
    };
  }

  const COUNTRY_ALIASES = {
    'united kingdom': ['united kingdom', 'uk', 'gb', 'gbr', 'great britain', 'united kingdom of great britain and northern ireland', 'england', 'britain'],
  };

  function pickOption(sel, value) {
    const want = norm(value);
    const cands = COUNTRY_ALIASES[want] || [want];
    const opts = [...sel.options];
    for (const c of cands) {
      const o = opts.find(o => norm(o.text) === c || norm(o.value) === c);
      if (o) return o;
    }
    return opts.find(o => norm(o.text).startsWith(want)) || null;
  }

  function setValue(el, v) {
    let p = Object.getPrototypeOf(el), d;
    while (p && !(d = Object.getOwnPropertyDescriptor(p, 'value'))) p = Object.getPrototypeOf(p);
    if (d && d.set) d.set.call(el, v); else el.value = v;
    for (const t of ['input', 'change']) el.dispatchEvent(new Event(t, { bubbles: true }));
    el.dispatchEvent(new Event('blur'));
    try { el.animate([{ boxShadow: '0 0 0 2px #5eead4' }, { boxShadow: '0 0 0 2px transparent' }], { duration: 900 }); } catch (e) {}
  }

  // fill one plan. Only empty fields, never ones in `skip` (a WeakSet the
  // caller keeps of fields the user has taken back). Returns what changed.
  function fill(items, profile, email, skip) {
    const v = values(profile, email);
    const done = [];
    for (const { el, key } of items) {
      if (skip && skip.has(el)) continue;
      const val = v[key];
      if (!val) continue;
      if (el.tagName === 'SELECT') {
        const cur = el.options[el.selectedIndex];
        if (cur && cur.value && el.selectedIndex > 0) continue;
        const o = pickOption(el, val);
        if (!o) continue;
        setValue(el, o.value);
      } else {
        if (el.value.trim()) continue;
        setValue(el, val);
      }
      done.push({ el, key });
    }
    return done;
  }

  const isEmailField = el => el.tagName === 'INPUT' && /^(email|username)$/.test(classify(el) || '');

  // the email the page already holds (index into emails), or -1
  function currentEmail(doc, emails) {
    for (const el of allFields(doc)) if (isEmailField(el) && emails.includes(el.value)) return emails.indexOf(el.value);
    return -1;
  }

  // change every email field of yours holding one of your emails to `to`
  function swapEmail(doc, emails, to) {
    let n = 0;
    for (const el of allFields(doc)) {
      if (isEmailField(el) && emails.includes(el.value) && el.value !== to) { setValue(el, to); n++; }
    }
    return n;
  }

  root.Once = { classify, plan, groups, groupOf, allFields, fill, swapEmail, currentEmail, values, visible };
})(typeof globalThis !== 'undefined' ? globalThis : this);
