// Persistent settings in localStorage, hydrated over defaults so a new field
// never loses an old user's data (house pattern from command-centre/kittens).

export const KEY = 'raven_v1';

export const DEFAULTS = {
  theme: 'auto',            // 'auto' | 'night' | 'day'
  ui: 1.5,                  // --ui scale
  units: 'mi',              // 'mi' | 'km'
  currency: 'GBP',
  server: '',               // https://<mac>.<tailnet>.ts.net (empty = no server)
  key: '',                  // APP_SECRET, set once via ?key=
  places: [                 // saved places for the map chips
    { id: 'home', name: 'Home', lat: null, lng: null },
    { id: 'work', name: 'Work', lat: null, lng: null },
  ],
  home: { lat: 51.5074, lng: -0.1278 }, // map default (London) until a fix arrives
  chime: true,
};

export function merge(def, got) {
  if (Array.isArray(def)) return Array.isArray(got) ? got : def;
  if (def && typeof def === 'object') {
    const out = {};
    for (const k of Object.keys(def)) out[k] = merge(def[k], got?.[k]);
    if (got && typeof got === 'object') for (const k of Object.keys(got)) if (!(k in out)) out[k] = got[k];
    return out;
  }
  return got === undefined || got === null ? def : got;
}

function read(storage) {
  try { return JSON.parse(storage.getItem(KEY) || 'null'); } catch { return null; }
}

export function createStore(storage = globalThis.localStorage) {
  const state = merge(DEFAULTS, storage ? read(storage) : null);
  let timer = null;
  const listeners = new Set();

  function save() {
    if (!storage) return;
    try { storage.setItem(KEY, JSON.stringify(state)); } catch (e) { console.warn('[store] save failed', e); }
  }
  function schedule() {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => { timer = null; save(); }, 150);
  }

  return {
    state,
    get: (k) => state[k],
    set(k, v) {
      state[k] = v;
      schedule();
      for (const fn of listeners) fn(k, v);
    },
    patch(obj) { for (const [k, v] of Object.entries(obj)) this.set(k, v); },
    onChange: (fn) => { listeners.add(fn); return () => listeners.delete(fn); },
    flush: save,
  };
}
