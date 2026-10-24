/* Website: Project Blueprint page (login required — then mounts the blueprint wizard) */
(function () {
  var C = window.SITE || {};
  function rpc(fn, args) {
    return fetch(String(C.SUPABASE_URL || '').replace(/\/+$/, '') + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { apikey: C.SUPABASE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(args) })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok) throw new Error(j.message || 'Request failed'); return j; }); });
  }
  var el = document.getElementById('bp-root'); if (!el || !window.SPBlueprint) return;
  var kw = ''; try { kw = sessionStorage.getItem('sp_calc_kw') || ''; } catch (e) {}
  var shop = String(C.SHOP_URL || '').replace(/\/+$/, '');
  function start(me) {
    me = me || {};
    SPBlueprint.mount(el, { mode: 'public', whatsapp: C.WHATSAPP || '9621050636', pdfLibUrl: 'assets/pdf-lib.min.js', targetKw: kw,
      customer: { name: me.name || '', mobile: me.mobile || '', locked: !!(me.name && me.mobile) },
      links: shop ? { store: shop, storeLabel: 'Go to store' } : {},
      pay: { rpc: function (fn, p) { return rpc(fn, { p: Object.assign({ token: window.SPGate ? SPGate.token() : null }, p || {}) }); }, settings: function () { return window.SPCART && SPCART.load ? SPCART.load().then(function (s) { return (s && s.settings) || {}; }) : Promise.resolve({}); } },
      onSubmit: function (p) { p.from = 'website'; p.token = window.SPGate ? SPGate.token() : null; return rpc('sp_blueprint_submit', { p: p }); } });
    if (window.SPGate) SPGate.log('blueprint', 'Opened Project Blueprint (website)');
  }
  function gate() {
    if (!window.SPGate || !SPGate.active()) { el.innerHTML = '<p>Login could not load. Please refresh.</p>'; return; }
    el.innerHTML = '<div class="bp-gate" style="text-align:center;padding:36px 12px"><p style="font-size:18px;font-weight:700;margin-bottom:6px">🔐 Login to use Project Blueprint</p><p style="color:#5a6b5f;margin-bottom:16px">A quick email OTP login is needed — free for every customer.</p><button type="button" class="btn btn-sun" id="bpLogin">Login &amp; open</button></div>';
    function go() { SPGate.require('blueprint', function (me) { start(me); }); }
    var b = document.getElementById('bpLogin'); if (b) b.onclick = go;
    go();
  }
  gate();
})();
