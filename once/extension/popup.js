const ext = globalThis.browser || globalThis.chrome;
const app = document.getElementById('app');
const SETUP_URL = 'https://labern.github.io/Clean/once/';

(async () => {
  const [tab] = await ext.tabs.query({ active: true, currentWindow: true });
  let host = '';
  try { host = new URL(tab.url).hostname; } catch (e) {}
  const v = await ext.storage.local.get(['profile', 'sites', 'def', 'eager', 'off']);
  const p = v.profile, sites = v.sites || {}, off = v.off || [];
  if (!p) {
    app.innerHTML = `<p class="empty">No details yet.</p><button id="go">Set up (once)</button>`;
    document.getElementById('go').onclick = () => ext.tabs.create({ url: SETUP_URL });
    return;
  }
  const cur = sites[host] ?? v.def ?? 0;
  app.innerHTML = `
    ${host ? `<div class="host">Email on <b>${host}</b></div>` : ''}
    ${(p.emails || []).map((e, i) => `<label><input type="radio" name="e" value="${i}" ${i === cur ? 'checked' : ''}>${e}</label>`).join('')}
    <label><input type="checkbox" id="off" ${off.includes(host) ? 'checked' : ''}>Off on this site</label>
    <label><input type="checkbox" id="eager" ${v.eager !== false ? 'checked' : ''}>Fill forms on sight</label>
    <button id="fill">Fill this page <kbd>⌥⇧F</kbd></button>
    <div class="row"><span>${p.first} ${p.last} · ${p.postcode}</span><a href="#" id="edit">Edit</a></div>`;
  app.querySelectorAll('input[name=e]').forEach(r => r.onchange = () => {
    sites[host] = +r.value; ext.storage.local.set({ sites });
  });
  document.getElementById('off').onchange = e => {
    const o = new Set(off); e.target.checked ? o.add(host) : o.delete(host);
    ext.storage.local.set({ off: [...o] });
  };
  document.getElementById('eager').onchange = e => ext.storage.local.set({ eager: e.target.checked });
  document.getElementById('fill').onclick = () => { ext.tabs.sendMessage(tab.id, 'fill').catch(() => {}); window.close(); };
  document.getElementById('edit').onclick = e => { e.preventDefault(); ext.tabs.create({ url: SETUP_URL }); };
})();
