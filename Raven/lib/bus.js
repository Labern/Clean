// Tiny event bus. Everything in Raven talks through this: the link layer
// publishes server events, widgets subscribe, the shell publishes UI events.

const handlers = new Map();
const last = new Map();

export function on(type, fn) {
  if (!handlers.has(type)) handlers.set(type, new Set());
  handlers.get(type).add(fn);
  return () => handlers.get(type)?.delete(fn);
}

export function emit(type, data) {
  last.set(type, data);
  const set = handlers.get(type);
  if (!set) return 0;
  for (const fn of [...set]) {
    try { fn(data, type); } catch (e) { console.error(`[bus] ${type}`, e); }
  }
  return set.size;
}

// Last value seen for a type, so a widget mounted late can render immediately.
export function latest(type) { return last.get(type); }

export function reset() { handlers.clear(); last.clear(); }
