// Bookmarklet entry. build.mjs puts the engine where ENGINE is, minifies,
// and writes bookmarklet.min.js: one function taking your profile. The page
// bakes your profile into the bookmark itself, so nothing is fetched at run time
// (no CSP can block it) and nothing about you lives on any server.
function (P) {
  var L = {};
  ENGINE
  var O = L.Once, em = P.emails || [], n = 0, docs = [document];
  for (var i = 0; i < frames.length; i++) { try { if (frames[i].document.body) docs.push(frames[i].document); } catch (e) {} }
  var cur = 0;
  docs.forEach(function (d) { var k = O.currentEmail(d, em); if (k >= 0) cur = k; });
  docs.forEach(function (d) {
    O.groups(d).forEach(function (els) { n += O.fill(O.plan(els).items, P, em[cur] || '', null).length; });
  });
  var msg;
  if (n) msg = 'Filled ' + n;
  else if (em.length > 1) {
    // second tap on a filled page: swap to the other email
    var to = em[(cur + 1) % em.length], s = 0;
    docs.forEach(function (d) { s += O.swapEmail(d, em, to); });
    msg = s ? 'Now ' + to : 'Nothing to fill';
  } else msg = 'Nothing to fill';
  var t = document.createElement('div');
  t.textContent = 'Once · ' + msg;
  t.style.cssText = 'all:initial;position:fixed;z-index:2147483647;left:50%;bottom:24px;transform:translateX(-50%);background:#0b0f14;color:#5eead4;font:600 13px -apple-system,system-ui,sans-serif;padding:10px 16px;border-radius:999px;box-shadow:0 6px 24px rgba(0,0,0,.35)';
  document.documentElement.appendChild(t);
  setTimeout(function () { t.remove(); }, 1800);
}
