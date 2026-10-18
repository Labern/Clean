// Everything the app remembers, kept on this device (localStorage). One object,
// one key, so a later native port or a sync layer swaps a single module.
const KEY = 'gt7-endgame-v1';

const DEFAULTS = {
  onboarded: false,
  credits: null,        // current credits, as typed by the player
  owned: [],            // car ids
  wish: [],             // car ids, in priority order
  prices: {},           // car id -> price seen in game (overrides data)
  done: {},             // roadmap step id -> true
  lessons: {},          // lesson id -> true
  pbs: {},              // track id -> { class: 'm:ss.s' }
  focus: ['collect', 'sport', 'pace', 'tune', 'wheel', 'heritage'],
  wheelBase: 'logitech-rs50', // the owner drives a Logitech G PRO
  wheelNotes: '',
  grind: { payouts: {}, minutes: {}, clean: true, log: [] },
  trackNotes: {},
  updatedAt: 0,         // ms; newest copy wins when devices sync
};

let state = load();
const subs = new Set();

function load() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) || 'null');
    return raw ? { ...structuredClone(DEFAULTS), ...raw, grind: { ...DEFAULTS.grind, ...(raw.grind || {}) } } : structuredClone(DEFAULTS);
  } catch {
    return structuredClone(DEFAULTS);
  }
}

export const get = () => state;

function persist() {
  try { localStorage.setItem(KEY, JSON.stringify(state)); } catch { /* private mode: keep in memory */ }
}

// Local edit: bump updatedAt so this copy wins the next sync.
export function set(fn) {
  fn(state);
  state.updatedAt = Date.now();
  persist();
  subs.forEach((f) => f(state, 'local'));
}

// A newer copy arrived from another device: take it wholesale (one user).
export function replace(doc) {
  state = { ...structuredClone(DEFAULTS), ...doc, grind: { ...DEFAULTS.grind, ...(doc.grind || {}) } };
  persist();
  subs.forEach((f) => f(state, 'remote'));
}

export const subscribe = (f) => (subs.add(f), () => subs.delete(f));

export function reset() {
  state = structuredClone(DEFAULTS);
  try { localStorage.removeItem(KEY); } catch { /* ignore */ }
  subs.forEach((f) => f(state));
}

export const exportJSON = () => JSON.stringify(state, null, 1);
export function importJSON(text) {
  const raw = JSON.parse(text);
  set((s) => Object.assign(s, structuredClone(DEFAULTS), raw));
}
