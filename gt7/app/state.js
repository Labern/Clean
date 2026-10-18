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
  wheelBase: null,
  wheelNotes: '',
  grind: { payouts: {}, minutes: {}, clean: true, log: [] },
  trackNotes: {},
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

export function set(fn) {
  fn(state);
  try { localStorage.setItem(KEY, JSON.stringify(state)); } catch { /* private mode: keep in memory */ }
  subs.forEach((f) => f(state));
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
