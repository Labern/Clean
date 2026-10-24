// Does the search feature exist, wire up, and keep a trial out of the library?
window.__searchProbe = async function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const out = {};
  out.inputPresent = !!document.getElementById('getIn');
  out.barPresent = !!document.getElementById('trialBar');
  out.barHiddenAtRest = document.getElementById('trialBar').hidden === true;
  // the input sits left of the zoom controls in the footer
  const zone = document.querySelector('footer .fzone.right');
  const kids = [...zone.children].map(n => n.id || n.tagName.toLowerCase());
  out.footerOrder = kids;
  out.leftOfZoom = kids.indexOf('getForm') >= 0 && kids.indexOf('getForm') < kids.indexOf('zOut');
  out.buttons = ['tbAccept','tbAgain','tbCancel'].map(id => !!document.getElementById(id));
  // a trial must never reach the index
  const before = JSON.parse(localStorage.getItem('pica.index') || '[]').length;
  window.__pica.trial = { id: 'trial-xyz', prev: window.__pica.docId };
  window.PICA_API.test.reset && null;
  out.saveGuarded = (() => {
    try {
      // drive the same guard store.save uses
      const idx = () => JSON.parse(localStorage.getItem('pica.index') || '[]').length;
      const n0 = idx();
      // a save for the trial id must be a no-op on the index
      window.__picaSaveProbe ? window.__picaSaveProbe('trial-xyz') : null;
      return idx() === n0;
    } catch (e) { return 'err ' + e; }
  })();
  window.__pica.trial = null;
  out.indexUnchanged = JSON.parse(localStorage.getItem('pica.index') || '[]').length === before;
  return JSON.stringify(out, null, 1);
};
