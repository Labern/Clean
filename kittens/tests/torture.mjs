import { chromium } from 'playwright';
import { createRequire } from 'module'; const require = createRequire(import.meta.url);
const aedes = require('aedes')(); const { WebSocketServer, createWebSocketStream } = require('ws');
const srv = require('http').createServer(); new WebSocketServer({ server: srv }).on('connection', ws => aedes.handle(createWebSocketStream(ws)));
await new Promise(r => srv.listen(8888, r));
const SP = process.argv[2], B = 'http://localhost:8765/kittens/', b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const errs = [], R = {}, wait = ms => new Promise(r => setTimeout(r, ms));
const silo = async () => { const c = await b.newContext({ viewport: { width: 1100, height: 900 } }); await c.addInitScript(() => { window.KT_BROKERS = ['ws://localhost:8888']; }); return c; };
const page = async (c, u, t = 1500) => { const p = await c.newPage(); p.on('pageerror', e => errs.push(e.message)); p.on('dialog', d => { R.lastDialog = d.message().slice(0, 60); d.accept(); }); await p.goto(u); await p.waitForTimeout(t); return p; };
const state = p => p.evaluate(() => JSON.parse(localStorage.getItem('kittens.state.v1')));
const imgs = p => p.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('kittens.img.')).length);
const find = (s, col, pred) => Object.entries(s[col] || {}).find(([, r]) => r && pred(r.del ? (r.was || {}) : r));
// ── phone A: the original app
const A = await silo(), a1 = await page(A, B), aStale = await page(A, B);           // + a stale second tab opened early
for (const [k, d, g] of [['penpen', '2026-10-12', 900], ['penpen', '2026-10-24', 1140], ['misato', '2026-10-24', 1280]]) { await a1.selectOption('#wK', k); await a1.fill('#wDate', d); await a1.fill('#wG', String(g)); await a1.click('#wAdd'); await wait(120); }
await a1.selectOption('#pK', 'penpen'); await a1.fill('#pCap', 'A wall photo'); await a1.setInputFiles('#pFile', SP + '/pp.jpg'); await a1.click('#pAdd'); await wait(400);
await a1.fill('#eText', 'A moment'); await a1.setInputFiles('#ePhoto', SP + '/ms.jpg'); await a1.click('#eAdd'); await wait(300);
await a1.fill('#fName', 'A food'); await a1.click('#fAdd'); await a1.fill('#msgText', 'A chat'); await a1.click('#msgSend');
await a1.fill('#cWhat', 'A cost'); await a1.fill('#cAmt', '9'); await a1.click('#cAddCost'); await wait(2500);
const SA = await a1.evaluate(() => localStorage.getItem('kittens.secret'));
// ── phone B: the other phone, pairs with A, uses v2 and the weight app
const Bc = await silo(), b1 = await page(Bc, B + 'v2/#pair=' + SA, 4500);
await b1.click('#wKseg button[data-k="misato"]'); await b1.fill('#wDate', '2026-10-25'); await b1.fill('#wG', '1300'); await b1.click('#wAdd');
await b1.click('#bScore button[data-n="4"]'); await b1.fill('#bText', 'B bond'); await b1.click('#bAdd'); await wait(300);
const b2 = await page(Bc, B + 'weight/', 2500); await b2.click('#kpick button[data-k="penpen"]'); await b2.click('#lcd'); await b2.fill('#lcdIn', '1175'); await b2.dispatchEvent('#lcdIn', 'change');
await b2.click('details.more summary'); await b2.fill('#qNote', 'B weight-app note'); await b2.setInputFiles('#qPhoto', SP + '/pp.jpg'); await b2.click('#qSave'); await wait(3000);
// ── the split hazard: a cold browser C (own key) — B then opens a link carrying C's key
const Cc = await silo(), c1 = await page(Cc, B + 'v2/', 3000); const SC = await c1.evaluate(() => localStorage.getItem('kittens.secret'));
const b3 = await page(Bc, B + 'weight/#pair=' + SC, 5000);
R.B_remembers_both_keys = await b3.evaluate(([a, c]) => { const k = JSON.parse(localStorage.getItem('kittens.secrets')); return k.includes(a) && k.includes(c); }, [SA, SC]);
// A keeps writing on its key → must still reach B
await a1.selectOption('#wK', 'penpen'); await a1.fill('#wDate', '2026-10-26'); await a1.fill('#wG', '1190'); await a1.click('#wAdd'); await wait(4000);
R.B_still_gets_A_after_split = !!find(await state(b3), 'weights', r => r.g === 1190);
R.C_got_everything_via_B = !!find(await state(c1), 'weights', r => r.g === 1175) && !!find(await state(c1), 'weights', r => r.g === 1190);
// stale A tab writes something — must not clobber anything
await aStale.fill('#sTitle', 'stale tab item'); await aStale.click('#sAdd'); await wait(2500);
// deletes go to the bin, photo image kept, restorable
const sA = await state(a1); const wDel = find(sA, 'weights', r => r.g === 900)[0]; const pDel = find(sA, 'photos', r => r.caption === 'A wall photo')[0];
await a1.reload(); await wait(1200);
await a1.locator(`#wlist [data-del="${wDel}"]`).click(); await wait(200); await a1.locator(`#wall [data-del="${pDel}"]`).click(); await wait(3000);
const sA2 = await state(a1); R.delete_keeps_content = !!(sA2.weights[wDel].del && sA2.weights[wDel].was && sA2.weights[wDel].was.g === 900);
R.deleted_photo_image_kept = await a1.evaluate(id => !!localStorage.getItem('kittens.img.' + id), pDel);
const ck = await page(Bc, B + 'check/', 4000); R.bin_on_other_phone = (await ck.textContent('#bin')).includes('900 g');
await ck.locator('#bin button').first().click(); await ck.locator('#bin button').first().click().catch(() => {}); await wait(4000);
const sA3 = await state(a1); R.restore_from_bin_reaches_A = !sA3.weights[wDel].del && !sA3.photos[pDel].del;
// final: every record on A exists on B and vice versa; markers present everywhere
const fa = await state(a1), fb = await state(b3), fc = await state(c1), ids = s => Object.keys(s).filter(c => s[c] && typeof s[c] === 'object').flatMap(c => Object.keys(s[c]).map(id => c + '/' + id));
const IA = new Set(ids(fa)), IB = new Set(ids(fb)), IC = new Set(ids(fc));
R.A_missing_from_B = [...IA].filter(x => !IB.has(x)).length; R.B_missing_from_A = [...IB].filter(x => !IA.has(x)).length; R.A_missing_from_C = [...IA].filter(x => !IC.has(x)).length;
const markers = s => ({ wA: !!find(s, 'weights', r => r.g === 1140), wB: !!find(s, 'weights', r => r.note === 'B weight-app note'), bond: !!find(s, 'bond', r => r.text === 'B bond'), msg: !!find(s, 'msgs', r => r.text === 'A chat'), cost: !!find(s, 'costs', r => r.what === 'A cost'), food: !!find(s, 'foods', r => r.name === 'A food'), stale: !!find(s, 'shop', r => r.title === 'stale tab item') });
R.markers = { A: markers(fa), B: markers(fb), C: markers(fc) }; R.images = { A: await imgs(a1), B: await imgs(b3), C: await imgs(c1) };
{ const fa = (await (await page(A, B + 'check/', 2500)).textContent('#fp')).split(' · '), fb = (await ck.textContent('#fp')).split(' · '); R.fingerprint_overlap_A_B = fa.some(x => fb.includes(x)); }
R.snapshot_taken = await a1.evaluate(() => Object.keys(localStorage).some(k => k.startsWith('kittens.snap.')));
// storage full: v1 must shout, not silently drop the weigh-in
const Dc = await silo(), d1 = await page(Dc, B, 6000);
await d1.evaluate(() => { let i = 0; for (let size = 1 << 20; size >= 64; size >>= 1) { const junk = 'x'.repeat(size); while (true) { try { localStorage.setItem('zz.junk' + (i++), junk); } catch (e) { break; } } } });
R.lastDialog = null; await d1.selectOption('#wK', 'penpen'); await d1.fill('#wG', '1234'); await d1.click('#wAdd'); await wait(500);
R.full_storage_warned = R.lastDialog; R.full_storage_saved_anyway = await d1.evaluate(() => { const s = JSON.parse(localStorage.getItem('kittens.state.v1') || 'null'); return !!(s && Object.values(s.weights).some(w => w.g === 1234)); });
console.log(JSON.stringify(R, null, 1)); console.log('errs', errs.filter(e => !/WebSocket/.test(e))); await b.close(); process.exit(0);
