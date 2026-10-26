// PlayStation connect wizard: four steps with live checks. The browser can't
// talk to Sony (no CORS), so the web app connects through the bridge on your
// Mac, which the live site finds automatically on localhost. Phones get the
// result through cloud save. Native shells skip the bridge step.
import { html, raw, toast } from './util.js';
import * as store from './state.js';
import * as connect from './connect.js';
import * as sync from './sync.js';
import { probe, bridgeBase } from './telemetry.js';
import { isNative } from './platform.js';

const CMD = 'curl -fsSL https://labern.github.io/Clean/gt7/bridge/install.sh | sh';
const isPhone = () => /iPhone|iPad|Android/i.test(navigator.userAgent) || (matchMedia('(pointer: coarse)').matches && innerWidth < 900);
const isSafari = () => /Safari/.test(navigator.userAgent) && !/Chrome|Chromium|Edg|Firefox/.test(navigator.userAgent);
export const extractNpsso = (txt) => { const t = String(txt || '').trim(); const m = t.match(/"npsso"\s*:\s*"([A-Za-z0-9]{40,100})"/); if (m) return m[1]; return /^[A-Za-z0-9]{40,100}$/.test(t) ? t : null; };

let bridge = null, opened = {}, busy = false, err = '';

const step = (n, state, title, body) => html`<div class="wz-step ${state}"><span class="wz-n">${state === 'done' ? '✓' : n}</span><div class="wz-b"><h3>${title}</h3>${body}</div></div>`;

export function psnWizard() {
  const native = isNative();
  const phone = !native && isPhone();
  const ready = native || bridge === true;
  const info = sync.info();
  const b1 = native ? '' : bridge === null ? html`<p class="muted">Looking for the bridge on this computer…</p>`
    : bridge ? html`<p class="ok-t">Bridge found at <b>${bridgeBase() || location.host}</b>. You're set.</p>`
    : phone ? html`<p>Sony only lets the PlayStation App's sign-in run from a real computer, so this step happens once <b>on your Mac</b>. Your PlayStation data then appears on this phone automatically through cloud save${info.user ? '' : html` (<a href="#/account" style="text-decoration:underline">sign in to cloud save</a> on both)`}.</p>
        <p class="muted small">On the Mac: open this page, follow these steps, done. Nothing to type here.</p>`
    : html`<p>Paste this into Terminal on your Mac. It downloads the bridge (3 small files, no installs) and starts it:</p>
        <div class="wz-cmd"><code>${CMD}</code><button class="btn" id="wz-copy" type="button">Copy</button></div>
        <p class="muted small">Needs Node 18+ (<code>brew install node</code>). This page spots the bridge by itself within a few seconds.${isSafari() ? raw(' Safari blocks the live site from talking to it: once it\'s running, open <a href="http://localhost:8787/#/connect" style="text-decoration:underline">localhost:8787</a> instead.') : ''}</p>`;
  return html`<div class="wz">
    ${native ? '' : step(1, bridge ? 'done' : 'now', bridge ? 'Bridge running' : phone ? 'Do this on your Mac' : 'Start the bridge on your Mac', b1)}
    ${step(native ? 1 : 2, !ready ? 'wait' : opened.psn ? 'done' : 'now', 'Sign in to PlayStation', html`<p>Opens Sony's own sign-in. Use your usual PSN account.</p><button class="btn ${opened.psn ? 'ghost' : 'red'}" id="wz-psn" type="button" ${ready ? '' : raw('disabled')}>Open PlayStation sign-in ↗</button>`)}
    ${step(native ? 2 : 3, !ready ? 'wait' : opened.code ? 'done' : opened.psn ? 'now' : 'wait', 'Copy your sign-in code', html`<p>Sony shows a line like <code>{"npsso":"…"}</code>. Select all of it and copy (⌘A, ⌘C). No need to trim it.</p><button class="btn ${opened.code ? 'ghost' : 'red'}" id="wz-code" type="button" ${ready ? '' : raw('disabled')}>Open the code page ↗</button>`)}
    ${step(native ? 3 : 4, !ready ? 'wait' : opened.code ? 'now' : 'wait', 'Paste and connect', html`<button class="btn red xl" id="wz-paste" type="button" ${ready && !busy ? '' : raw('disabled')}>${busy ? 'Connecting…' : 'Paste & connect'}</button>
      <label class="f" style="margin-top:12px">…or paste it here<input type="password" id="wz-input" placeholder='{"npsso":"…"} or just the code' autocomplete="off" ${ready ? '' : raw('disabled')}></label>
      ${err ? html`<p class="wz-err">${err}</p>` : ''}
      <p class="muted small" style="margin-top:10px">${native ? 'The sign-in stays on this device.' : 'The sign-in stays on your Mac (in ~/GT7Laps, readable only by you). Only the results (profile, trophies, play time) go into your save.'} It lasts about two months; the app tells you when to redo it.</p>`)}
  </div>`;
}

export function wireWizard(root, rerender) {
  const $ = (s) => root.querySelector(s);
  const recheck = async () => { const was = bridge; bridge = await probe(); if (was !== bridge) rerender(); };
  if (!isNative()) {
    if (bridge === null) recheck();
    clearInterval(wireWizard.t);
    wireWizard.t = setInterval(() => { if (!root.querySelector('.wz')) return clearInterval(wireWizard.t); if (!bridge) recheck(); }, 3000);
  }
  $('#wz-copy')?.addEventListener('click', async () => { try { await navigator.clipboard.writeText(CMD); toast('Copied. Paste it into Terminal.'); } catch { toast('Select the command and copy it'); } });
  $('#wz-psn')?.addEventListener('click', () => { window.open('https://my.playstation.com/', '_blank', 'noopener'); opened.psn = true; rerender(); });
  $('#wz-code')?.addEventListener('click', () => { window.open(connect.NPSSO_URL, '_blank', 'noopener'); opened.code = true; opened.psn = true; rerender(); });
  const go = async (txt) => {
    const npsso = extractNpsso(txt);
    if (!npsso) { err = 'That doesn\'t look like the sign-in code. Open the code page, select everything it shows and copy it again.'; return rerender(); }
    busy = true; err = ''; rerender();
    try { await connect.connectPSN(npsso); busy = false; opened = {}; toast('PlayStation connected'); rerender(); }
    catch (e) {
      busy = false;
      const m = String(e.message || e);
      err = /bridge/i.test(m) ? 'Lost the bridge. Is the Terminal window still open?' : /40[01]|invalid|expired|npsso|code/i.test(m) ? 'Sony rejected that code: it expires quickly after you sign in again elsewhere. Open the code page and copy the fresh one.' : 'Couldn\'t reach Sony: ' + m;
      rerender();
    }
  };
  $('#wz-paste')?.addEventListener('click', async () => {
    try { const t = await navigator.clipboard.readText(); await go(t); }
    catch { err = 'This browser didn\'t let the page read your clipboard. Paste into the box below instead.'; rerender(); setTimeout(() => root.querySelector('#wz-input')?.focus(), 50); }
  });
  $('#wz-input')?.addEventListener('paste', (e) => { const t = e.clipboardData?.getData('text'); if (t) { e.preventDefault(); go(t); } });
  $('#wz-input')?.addEventListener('change', (e) => go(e.target.value));
}
