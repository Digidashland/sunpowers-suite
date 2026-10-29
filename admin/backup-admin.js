/* Sunpowers Admin — 💾 Backup / Restore for each section (Website · Web Shop Page · App Store).
   Menu items (☰): "Get full backup" (summary + download + restore) and "Download backup" (one tap).
   Each backup is its own file, so one section can be restored without touching the others.
   scope 'site'  = Website Management  (all website texts / photos / slides / menu / pages — without the Shop page)
   scope 'shop'  = Web Shop Page       (Web Shop Page Builder layout + Shop page texts / cart-section settings)
   scope 'store' = App Store           (whole store data: products, sections, settings, Store App Page Builder layout)
   Restore first downloads a "before-restore" safety copy of what is live now. */
(function () {
'use strict';
var H = null;
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
var clone = function (o) { return JSON.parse(JSON.stringify(o == null ? null : o)); };
var isO = function (o) { return o && typeof o === 'object' && !Array.isArray(o); };
var NAMES = { site: 'Website', shop: 'Web Shop Page', store: 'App Store' };
var FILES = { site: 'website', shop: 'web-shop-page', store: 'app-store' };
var SHOPK = /(^|~)shop:/;

/* ---------- live data ---------- */
async function liveWeb() { var w = await H.rpc('sp_get_web', {}); return isO(w) ? w : {}; }
async function liveStore() { var d = await H.rpc('sp_get_store', {}); return H.normalize(isO(d) && Array.isArray(d.layout) ? d : H.demo()); }

/* ---------- website data split: shop-page parts vs the rest ---------- */
function pick(o, test, want) { var r = {}; Object.keys(isO(o) ? o : {}).forEach(function (k) { if (test(k) === want) r[k] = clone(o[k]); }); return r; }
function webPart(W, part) {            // part: 'shop' = Shop page bits, 'site' = everything else
  var shop = part === 'shop', out = clone(W) || {};
  ['text', 'img'].forEach(function (k) { out[k] = pick(W[k], function (x) { return SHOPK.test(x); }, shop); });
  out.pg = pick(W.pg, function (x) { return x === 'shop'; }, shop);
  if (shop) { out = { text: out.text, img: out.img, pg: out.pg, shop: clone(W.shop || {}) }; } else delete out.shop;
  return out;
}
function webMerge(live, bak, part) {  // live W with the `part` replaced by the backup's
  var out = clone(live) || {}, shop = part === 'shop', keepLive = webPart(live, shop ? 'site' : 'shop');
  if (!shop) { var nb = clone(bak); Object.keys(nb).forEach(function (k) { if (k !== 'text' && k !== 'img' && k !== 'pg') out[k] = nb[k]; }); }
  ['text', 'img'].forEach(function (k) { out[k] = Object.assign({}, pick(live[k], function (x) { return SHOPK.test(x); }, !shop), bak[k] || {}); });
  out.pg = Object.assign({}, pick(live.pg, function (x) { return x === 'shop'; }, !shop), bak.pg || {});
  if (shop) out.shop = clone(bak.shop || {}); else if (live.shop) out.shop = clone(live.shop);
  void keepLive; return out;
}

/* ---------- Page Builder data split (comps/order for one page) ---------- */
function builderPart(raw, pg) {
  var c = SPBLD.norm(raw), o = { on: !!c.on[pg], order: (c.order[pg] || []).slice(), comps: {}, ctr: clone(c.ctr) };
  o.order.forEach(function (id) { if (c.comps[id]) o.comps[id] = clone(c.comps[id]); });
  o.web = {}; Object.keys(c.web || {}).forEach(function (f) { var a = c.web[f].filter(function (x) { return o.comps[x.id]; }).map(clone); if (a.length) o.web[f] = a; });   /* sections placed on website pages */
  return o;
}
function builderMerge(raw, part, pg) {
  var c = SPBLD.norm(raw), other = pg === 'shop' ? 'store' : 'shop', map = {};
  (c.order[pg] || []).slice().forEach(function (id) { var o = c.comps[id]; if (!o) return; if (o.pages[other]) o.pages[pg] = false; else delete c.comps[id]; });
  c.order[pg] = [];
  (part.order || []).forEach(function (id) {
    var src = part.comps && part.comps[id]; if (!src) return;
    var cur = c.comps[id], nid = id;
    if (cur && !(cur.pages[other] && cur.type === src.type)) {          // id already used by something else → new id
      var t = src.type, n = (c.ctr[t] || 0); do { n++; nid = t + '_' + n; } while (c.comps[nid]); c.ctr[t] = n;
    }
    map[id] = nid;
    if (c.comps[nid]) { c.comps[nid].pages[pg] = true; }
    else { var k = clone(src); k.id = nid; k.pages = {}; k.pages[pg] = true; k.pages[other] = false; c.comps[nid] = k; }
    c.order[pg].push(nid);
  });
  c.on[pg] = !!part.on;
  c.web = c.web || {};
  Object.keys(part.web || {}).forEach(function (f) { (part.web[f] || []).forEach(function (x) { var nid = map[x.id]; if (!nid) return; var a = c.web[f] = c.web[f] || []; if (!a.some(function (y) { return y.id === nid; })) a.push(Object.assign({}, x, { id: nid })); }); });
  Object.keys(part.ctr || {}).forEach(function (t) { c.ctr[t] = Math.max(c.ctr[t] || 0, part.ctr[t] || 0); });
  return SPBLD.norm(c);
}

/* ---------- build / summarise ---------- */
async function make(scope) {
  var f = { app: 'sunpowers-admin-backup', v: 1, scope: scope, title: NAMES[scope], at: new Date().toISOString() };
  if (scope === 'site') { f.web = webPart(await liveWeb(), 'site'); }
  else if (scope === 'shop') { var W = await liveWeb(), D = await liveStore(); f.web = webPart(W, 'shop'); f.builder = builderPart(D.builder, 'shop'); }
  else { var S = await liveStore(), b = builderPart(S.builder, 'store'); delete S.builder; f.store = S; f.builder = b; }
  return f;
}
function count(o) { return isO(o) ? Object.keys(o).length : 0; }
function lines(f) {
  var L = [];
  if (f.scope === 'site') { var w = f.web || {}; L.push(['📝 बदले हुए शब्द', count(w.text)], ['🖼️ बदली हुई फ़ोटो', count(w.img)], ['🎞️ हीरो स्लाइड', (w.slides || []).length], ['📄 नए पेज', (w.pages || []).length], ['🧭 मेन्यू बदलाव', ((w.menu && w.menu.add) || []).length + ((w.menu && w.menu.hide) || []).length], ['🔗 लिंक', count(w.links)]); }
  else if (f.scope === 'shop') { L.push(['🧱 Web Shop Page Builder के सेक्शन', (f.builder && f.builder.order || []).length], ['📝 Shop पेज के बदले शब्द', count(f.web && f.web.text)], ['🛒 कार्ट-सेक्शन सेटिंग', count(f.web && f.web.shop)]); }
  else { var s = f.store || {}; L.push(['📦 प्रोडक्ट', (s.products || []).length], ['🗂️ सेक्शन', (s.sections || []).length], ['🧱 Store App Page Builder के सेक्शन', (f.builder && f.builder.order || []).length], ['📄 पेज/पॉलिसी', (s.pages || []).length]); }
  return L;
}
function fname(f) { return 'sunpowers-' + FILES[f.scope] + '-backup-' + f.at.slice(0, 10) + '-' + f.at.slice(11, 16).replace(':', '') + '.json'; }
function save(f) { H.download(new Blob([JSON.stringify(f, null, 1)], { type: 'application/json' }), fname(f)); }

/* ---------- restore ---------- */
async function apply(f) {
  var scope = f.scope;
  if (scope === 'site') { var W = await liveWeb(); await H.rpc('sp_save_web', { p_pass: H.pass(), p_data: webMerge(W, f.web || {}, 'site') }, 60000); try { localStorage.removeItem('sp_web_cache_v1'); } catch (e) {} }
  else if (scope === 'shop') {
    var W2 = await liveWeb(); await H.rpc('sp_save_web', { p_pass: H.pass(), p_data: webMerge(W2, f.web || {}, 'shop') }, 60000); try { localStorage.removeItem('sp_web_cache_v1'); } catch (e) {}
    var D = await liveStore(); D.builder = builderMerge(D.builder, f.builder || { order: [], comps: {} }, 'shop'); await H.rpc('sp_save_store', { p_pass: H.pass(), p_data: H.normalize(D) }, 60000); H.setD(D);
  } else {
    var cur = await liveStore(), N = H.normalize(clone(f.store || {}));
    N.builder = builderMerge(cur.builder, { on: false, order: [], comps: {} }, 'store');        // keep the Shop page part of the live builder
    N.builder = builderMerge(N.builder, f.builder || { order: [], comps: {} }, 'store');
    await H.rpc('sp_save_store', { p_pass: H.pass(), p_data: H.normalize(N) }, 60000); H.setD(N);
  }
}
function readFile(file) { return new Promise(function (res, rej) { var r = new FileReader(); r.onload = function () { res(String(r.result || '')); }; r.onerror = function () { rej(new Error('फ़ाइल पढ़ी नहीं जा सकी')); }; r.readAsText(file); }); }
function parse(text, scope) {
  var f; try { f = JSON.parse(text); } catch (e) { throw new Error('यह बैकअप फ़ाइल नहीं है (JSON ख़राब)'); }
  if (!isO(f) || f.app !== 'sunpowers-admin-backup') throw new Error('यह Sunpowers का सेक्शन-बैकअप नहीं है');
  if (f.scope !== scope) throw new Error('यह ' + (NAMES[f.scope] || '?') + ' का बैकअप है — यहाँ ' + NAMES[scope] + ' का बैकअप चाहिए');
  return f;
}
function restoreBox(scope, m) {
  var inp = m.body.querySelector('#bkFile'), info = m.body.querySelector('#bkInfo'), go = m.body.querySelector('#bkGo'), cur = null;
  inp.onchange = async function () {
    cur = null; go.disabled = true; info.innerHTML = '';
    var file = inp.files && inp.files[0]; if (!file) return;
    try { var f = parse(await readFile(file), scope); cur = f; info.innerHTML = '<div class="note g">✅ ' + esc(f.title) + ' बैकअप • ' + esc(new Date(f.at).toLocaleString()) + '<br>' + lines(f).map(function (x) { return esc(x[0]) + ': <b>' + x[1] + '</b>'; }).join(' • ') + '</div>'; go.disabled = false; }
    catch (e) { info.innerHTML = '<div class="note r">❌ ' + esc(e.message) + '</div>'; }
  };
  go.onclick = async function () {
    if (!cur) return;
    if (!(await H.ask('♻️ ' + NAMES[scope] + ' को इस बैकअप (' + esc(new Date(cur.at).toLocaleDateString()) + ') से वापस लाएँ?<br><small>अभी लाइव जो है, उसकी एक सेफ़्टी कॉपी पहले अपने-आप डाउनलोड होगी। फिर ' + NAMES[scope] + ' बैकअप जैसा हो जाएगा।' + (scope === 'shop' ? ' (Web Shop Page का ही हिस्सा बदलेगा।)' : '') + '</small>', '♻️ हाँ, वापस लाएँ', true))) return;
    go.disabled = true; go.innerHTML = '<span class="spin"></span>';
    try { var safe = await make(scope); safe.title += ' (restore से पहले)'; H.download(new Blob([JSON.stringify(safe, null, 1)], { type: 'application/json' }), fname(safe).replace('-backup-', '-before-restore-')); await apply(cur); m.close(); H.toast('♻️ ' + NAMES[scope] + ' बैकअप से वापस आ गया'); H.reopen(scope); }
    catch (e) { go.disabled = false; go.innerHTML = '♻️ वापस लाएँ'; H.toast('❌ ' + e.message, true); }
  };
}

/* ---------- screens ---------- */
async function center(scope) {
  var m = H.modal('💾 ' + NAMES[scope] + ' — Full backup', '<div id="bkSum"><span class="spin"></span> लाइव डेटा पढ़ा जा रहा है…</div>' +
    '<hr style="border:0;border-top:1px solid var(--line);margin:12px 0"><b>♻️ बैकअप से वापस लाएँ</b><div class="fld full" style="margin-top:6px"><input type="file" id="bkFile" accept=".json,application/json"></div><div id="bkInfo"></div><div class="bar" style="margin:8px 0"><button class="btn out" id="bkGo" disabled>♻️ वापस लाएँ</button></div>' +
    '<small style="color:var(--mut)">सिर्फ़ ' + NAMES[scope] + ' का बैकअप चलेगा — बाकी सेक्शन नहीं बदलेंगे।</small>',
    [{ l: 'बंद करें', cls: 'gray' }, { l: '⬇️ Download backup', id: 'bkDl', fn: async function () { var f = await make(scope); save(f); H.toast('⬇️ ' + NAMES[scope] + ' बैकअप डाउनलोड हो गया'); return false; } }]);
  restoreBox(scope, m);
  try { var f = await make(scope); m.body.querySelector('#bkSum').innerHTML = '<div class="note g">अभी लाइव ' + esc(NAMES[scope]) + ' में:<br>' + lines(f).map(function (x) { return esc(x[0]) + ': <b>' + x[1] + '</b>'; }).join('<br>') + '</div><small style="color:var(--mut)">"Download backup" दबाते ही ये सब एक फ़ाइल में आ जाएगा — फ़ाइल संभालकर रखें।</small>'; }
  catch (e) { m.body.querySelector('#bkSum').innerHTML = '<div class="note r">❌ ' + esc(e.message) + '</div>'; }
}
async function quick(scope) { try { var f = await make(scope); save(f); H.toast('⬇️ ' + NAMES[scope] + ' बैकअप डाउनलोड हो गया'); } catch (e) { H.toast('❌ बैकअप नहीं बन पाया: ' + e.message, true); } }

window.SPBK = {
  init: function (h) { H = h; },
  items: function (scope) { return [{ group: 'Backup', ic: '💾', l: 'Get full backup', kw: 'backup restore', fn: function () { center(scope); } }, { group: 'Backup', ic: '⬇️', l: 'Download backup', kw: 'backup download', fn: function () { quick(scope); } }]; },
  /* exposed for tests */ _make: make, _apply: apply, _parse: parse, _builderMerge: builderMerge, _webMerge: webMerge, _webPart: webPart
};
})();
