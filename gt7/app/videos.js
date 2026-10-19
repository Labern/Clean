// Track videos: real YouTube results (data/videos.js), grouped by what they are,
// plus a search link per kind so there's always more.
import { $$, html, raw } from './util.js';
import { VIDEOS, VIDEO_KINDS } from '../data/videos.js';

const Q = {
  guide: (t) => `GT7 ${t} track guide`,
  hotlap: (t) => `GT7 ${t} hot lap`,
  setup: (t) => `GT7 ${t} best car tune`,
  race: (t) => `GT7 ${t} daily race onboard`,
  real: (t) => `${t} onboard lap`,
  history: (t) => `${t} history`,
};
const yt = (q) => 'https://www.youtube.com/results?search_query=' + encodeURIComponent(q);

export function videosSection(track) {
  const list = VIDEOS[track.id] || [];
  const real = track.country !== 'GT original';
  const kinds = VIDEO_KINDS.filter(([k]) => list.some((v) => v.kind === k));
  const name = track.short;
  return html`<section class="section" id="videos">
    <div class="head"><h2>Videos</h2><span class="muted small">${list.length} picked from YouTube · guides, records, cars, races${real ? ', the real thing' : ''}</span></div>
    <div class="seg vid-tabs" style="margin-bottom:16px"><button data-vk="all" class="on">All</button>${kinds.map(([k, l]) => html`<button data-vk="${k}">${l}</button>`)}</div>
    <div class="grid g4 vid-grid">${list.map((v) => html`<a class="card vid" data-kind="${v.kind}" href="https://www.youtube.com/watch?v=${v.id}" target="_blank" rel="noopener">
      <div class="th"><img loading="lazy" src="https://i.ytimg.com/vi/${v.id}/mqdefault.jpg" alt=""><span class="dur">${v.dur}</span><span class="vk">${(VIDEO_KINDS.find(([k]) => k === v.kind) || [, ''])[1]}</span></div>
      <div class="body"><div class="t">${v.title}</div><div class="muted small">${v.channel} · ${v.views} views${v.age ? ' · ' + v.age : ''}</div></div></a>`)}</div>
    <div class="row vid-more" style="margin-top:14px">${VIDEO_KINDS.filter(([k]) => real || k !== 'real').map(([k, l]) => html`<a class="chip" href="${yt(Q[k](k === 'real' || k === 'history' ? track.name : name))}" target="_blank" rel="noopener">More ${l.toLowerCase()} ↗</a>`)}</div>
  </section>`;
}

export function wireVideos(root) {
  $$('[data-vk]', root).forEach((b) => (b.onclick = () => {
    const k = b.dataset.vk;
    $$('[data-vk]', root).forEach((x) => x.classList.toggle('on', x === b));
    $$('.vid', root).forEach((c) => { c.hidden = k !== 'all' && c.dataset.kind !== k; });
  }));
}
