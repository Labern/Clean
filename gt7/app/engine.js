// The "what do I do next" brain, plus credit maths.
import { PHASES } from '../data/roadmap.js';
import { GRINDS, CLEAN_BONUS } from '../data/grinds.js';
import { carById } from '../data/cars.js';
import { TRACKS } from '../data/tracks.js';

export const priceOf = (s, id) => s.prices[id] ?? carById[id]?.price ?? null;

export function grindRows(s) {
  return GRINDS.map((g) => {
    const payout = s.grind.payouts[g.id] ?? g.payout;
    const minutes = s.grind.minutes[g.id] ?? g.minutes;
    const per = payout == null ? null : payout * (s.grind.clean ? 1 + CLEAN_BONUS : 1);
    const perHour = per == null ? null : per / (minutes / 60);
    return { ...g, payout, minutes, per, perHour };
  }).sort((a, b) => (b.perHour ?? -1) - (a.perHour ?? -1));
}

export const bestRate = (s) => grindRows(s).find((r) => r.perHour)?.perHour ?? null;

export function hoursFor(s, amount) {
  const r = bestRate(s);
  if (!r || amount <= 0) return 0;
  return amount / r;
}

const allSteps = () => PHASES.flatMap((p) => p.steps.map((st) => ({ ...st, phase: p })));

export function isDone(s, step) {
  if (s.done[step.id]) return true;
  if (step.car && s.owned.includes(step.car)) return true;
  return false;
}

export function progress(s) {
  const steps = allSteps();
  const d = steps.filter((st) => isDone(s, st)).length;
  return { done: d, total: steps.length, pct: Math.round((d / steps.length) * 100) };
}

// Ranked suggestions. Each: { kind, title, why, href, cta, step? }
export function nextSteps(s, n = 3) {
  const out = [];
  if (!s.onboarded) {
    out.push({ kind: 'setup', title: 'Tell the app where you are', why: 'Credits, the cars you own and what you\'re chasing. Every recommendation adapts to it.', href: '#/setup', cta: 'Set up' });
  }
  const credits = s.credits ?? 0;

  // Wishlist: buy what you can afford, else show the gap.
  const wish = s.wish.filter((id) => !s.owned.includes(id) && carById[id]);
  const affordable = wish.find((id) => (priceOf(s, id) ?? Infinity) <= credits);
  if (affordable) {
    const c = carById[affordable];
    out.push({ kind: 'buy', title: `Buy the ${c.name}`, why: `You have the credits (${Math.round(priceOf(s, affordable) / 1000).toLocaleString()}k). It's top of your wishlist. Find it at ${c.where}.`, href: `#/car/${c.id}`, cta: 'Open car', car: c.id });
  } else if (wish.length) {
    const id = wish[0], c = carById[id], gap = (priceOf(s, id) ?? 0) - credits;
    const h = hoursFor(s, gap);
    out.push({ kind: 'grind', title: `Grind ${Math.round(gap / 1e6 * 10) / 10}M for the ${c.name}`, why: h ? `About ${h < 10 ? h.toFixed(1) : Math.round(h)} hours of your best grind at the current clean-race rate.` : 'Set a payout in the Credit Engine to get an estimate.', href: '#/credits', cta: 'Credit Engine', car: c.id });
  }

  // Roadmap: lowest priority number first, boosted by your focus.
  const focus = new Set(s.focus);
  const pending = allSteps().filter((st) => !isDone(s, st)).map((st) => {
    let score = st.prio - (st.focus?.some((f) => focus.has(f)) ? 8 : 0);
    if (st.car) {
      const p = priceOf(s, st.car);
      if (p != null && p > credits) score += 6; // can't buy yet: push down a little
    }
    return { st, score };
  }).sort((a, b) => a.score - b.score);
  for (const { st } of pending) {
    if (out.length >= n) break;
    const p = st.car ? priceOf(s, st.car) : null;
    out.push({
      kind: 'step', title: st.title, step: st.id,
      why: st.how + (p != null && p > credits ? ` (You need ${(p - credits).toLocaleString()} more Cr.)` : ''),
      href: st.car ? `#/car/${st.car}` : st.id.startsWith('lic') || st.id.startsWith('ce') ? '#/roadmap' : st.id === 'wheel-setup' ? '#/wheel' : st.id === 'academy' ? '#/academy' : st.id.startsWith('tune') ? '#/tuning' : st.id.startsWith('sport') ? '#/sport' : '#/roadmap',
      cta: 'Go', phase: st.phase.title,
    });
  }
  return out.slice(0, n);
}

// The track you should drive today: no PB yet, famous first, Sport staples first.
export function trackOfTheDay(s) {
  const day = Math.floor(Date.now() / 864e5);
  const pool = TRACKS.filter((t) => !s.pbs[t.id] || !Object.keys(s.pbs[t.id]).length);
  const list = (pool.length ? pool : TRACKS).slice().sort((a, b) => b.fame - a.fame);
  const top = list.filter((t) => t.fame >= (list[0]?.fame ?? 0) - 1);
  return top[day % top.length];
}
