/* Sunpowers Store Admin — 📍 पिनकोड (pincode-wise availability)
   Rules live in Supabase tables sp_pin_* (see crm/phase7-pincode.sql). The storefront asks sp_pin_check() for the
   customer's pincode and the server re-checks at order time. Nothing here is stored in the browser except UI state. */
(function () {
'use strict';
var X = null;
var ST = { tab: 'rules', info: null, sum: null, areas: null, loading: false, pf: '', sf: '', err: '' };
var SCOPES = { all: 'सभी पिनकोड', state: 'State', district: 'District', area: 'Custom Area', pin: 'पिनकोड' };
var $ = function (s, r) { return (r || document).querySelector(s); };
var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
var nf = function (n) { return Number(n || 0).toLocaleString('en-IN'); };
function tc(s) { return String(s || '').toLowerCase().replace(/(^|[\s(\-.])([a-z])/g, function (m, a, b) { return a + b.toUpperCase(); }); }
function call(fn, args, ms) { return X.rpc(fn, Object.assign({ p_pass: X.pass() }, args || {}), ms || 60000); }
function prods() { return (X.products() || []).filter(function (p) { return p && p.id; }); }
function pname(id) {
  if (id === '*') return 'सभी प्रोडक्ट';
  var p = prods().filter(function (x) { return x.id === id; })[0];
  return p ? (p.title || id) : id + ' (हटाया हुआ प्रोडक्ट)';
}
function valLabel(scope, v) {
  if (scope === 'all') return 'सभी पिनकोड';
  if (scope === 'district') { var a = String(v).split('|'); return tc(a[1] || '') + ', ' + tc(a[0] || ''); }
  if (scope === 'pin') return String(v);
  return tc(v);
}
function chunks(a, n) { var r = []; for (var i = 0; i < a.length; i += n) r.push(a.slice(i, i + n)); return r; }

/* ---------- pincode text / file parsing ---------- */
function parsePins(text) {
  var out = [], seen = {}, bad = 0, s = String(text == null ? '' : text);
  s = s.replace(/([1-9]\d{5})\s*[-–—]\s*([1-9]\d{5})/g, function (m, a, b) {
    a = +a; b = +b; if (b < a || b - a > 3000) { bad++; return ' '; }
    var t = []; for (var k = a; k <= b; k++) t.push(k); return ' ' + t.join(' ') + ' ';
  });
  s.split(/[\s,;|]+/).forEach(function (t) {
    if (!t) return;
    if (/^[1-9]\d{5}$/.test(t)) { if (!seen[t]) { seen[t] = 1; out.push(t); } } else if (/\d/.test(t)) bad++;
  });
  return { pins: out, bad: bad };
}
async function fileToText(file) {
  if (/\.xlsx$/i.test(file.name)) {
    var wb = await XLSXLite.read(await file.arrayBuffer()), t = [];
    Object.keys(wb).forEach(function (k) { wb[k].forEach(function (r) { t.push(r.join(' ')); }); });
    return t.join('\n');
  }
  return await file.text();
}
function parseCsv(text) {
  var rows = [], row = [], cur = '', q = false, i = 0, n = text.length, c;
  if (text.charCodeAt(0) === 0xFEFF) i = 1;
  for (; i < n; i++) {
    c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur); rows.push(row); row = []; cur = ''; }
    else if (c !== '\r') cur += c;
  }
  if (cur !== '' || row.length) { row.push(cur); rows.push(row); }
  return rows;
}

/* ---------- loading ---------- */
async function load(force) {
  if (ST.loading) return; if (ST.info && !force) return;
  ST.loading = true; ST.err = '';
  try {
    var r = await Promise.all([call('sp_pin_admin_info'), call('sp_pin_rules_summary'), call('sp_pin_area_list')]);
    ST.info = r[0]; ST.sum = r[1] || []; ST.areas = r[2] || [];
  } catch (e) {
    ST.err = /Could not find|PGRST202|schema cache|does not exist/i.test(e.message || '') ? 'missing' : (e.message || String(e));
  }
  ST.loading = false; X.render();
}
function reload() { ST.info = null; return load(true); }

/* ---------- main page ---------- */
function html() {
  if (!ST.info && !ST.err) { load(); return '<div class="empty"><span class="spin"></span> लोड हो रहा है…</div>'; }
  if (ST.err === 'missing') return '<div class="note r">⚠️ पिनकोड सुविधा का डेटाबेस हिस्सा अभी नहीं लगा है। Supabase → SQL Editor में <b>MASTER-UPDATE.sql</b> एक बार चलाएँ, फिर यहाँ वापस आएँ।</div>';
  if (ST.err) return '<div class="note r">⚠️ ' + esc(ST.err) + '</div><button class="btn" data-pn="retry">🔄 दोबारा कोशिश</button>';
  var I = ST.info, only = (I.modes || []).filter(function (m) { return m.mode === 'only'; });
  var h = '<div class="stats"><div class="stat"><b>' + nf(I.rules) + '</b><small>कुल नियम</small></div><div class="stat"><b>' + nf(I.areas) + '</b><small>Custom Area</small></div>' +
    '<div class="stat"><b>' + nf(I.master) + '</b><small>पिनकोड मास्टर (State/District के लिए)</small></div><div class="stat"><b>' + only.length + '</b><small>"सिर्फ़ चुने पिनकोड" वाले प्रोडक्ट</small></div></div>' +
    '<div class="bar"><button class="btn" data-pn="wiz">➕ आउट-ऑफ़-स्टॉक / उपलब्धता सेट करें</button><button class="btn out" data-pn="xdown">📥 सारे नियम Excel में</button><span class="btn out upl">📤 Excel से अपलोड<input type="file" accept=".xlsx" data-pn="xup"></span></div>' +
    '<div class="bar"><button class="tab' + (ST.tab === 'rules' ? ' on' : '') + '" data-pn="tab" data-t="rules">📋 नियम</button><button class="tab' + (ST.tab === 'areas' ? ' on' : '') + '" data-pn="tab" data-t="areas">📌 Custom Area</button><button class="tab' + (ST.tab === 'master' ? ' on' : '') + '" data-pn="tab" data-t="master">🗺️ पिनकोड मास्टर</button></div>';
  if (ST.tab === 'areas') return h + areasHtml();
  if (ST.tab === 'master') return h + masterHtml();
  return h + rulesHtml(only);
}
function rulesHtml(only) {
  var h = '<div class="card"><h2>🧪 जाँच करें — इस पिनकोड पर प्रोडक्ट दिखेगा या नहीं?</h2><div class="bar"><input class="inp grow" id="pnTestPin" inputmode="numeric" maxlength="6" placeholder="6 अंक का पिनकोड" style="max-width:200px"><select class="inp grow" id="pnTestProd" style="max-width:340px"><option value="">— प्रोडक्ट चुनें —</option>' +
    prods().map(function (p) { return '<option value="' + esc(p.id) + '">' + esc(p.title || p.id) + '</option>'; }).join('') + '</select><button class="btn sm" data-pn="test">जाँचें</button></div><div id="pnTestOut" style="font-size:14px"></div></div>';
  if (only.length) h += '<div class="note g">🎯 <b>सिर्फ़ चुने पिनकोड पर ऑनलाइन:</b> ' + only.map(function (m) { return '<span class="tag b">' + esc(pname(m.product_id)) + ' <button class="ib" style="width:20px;height:20px;border-radius:6px;font-size:11px" data-pn="onlyoff" data-id="' + esc(m.product_id) + '" title="सबके लिए खोलें">✕</button></span>'; }).join(' ') + '<br><small>इन प्रोडक्ट का एक भी "उपलब्ध" नियम जिस पिनकोड पर नहीं है, वहाँ ये नहीं बिकेंगे।</small></div>';
  var pids = {}; ST.sum.forEach(function (g) { pids[g.product_id] = 1; });
  h += '<div class="bar"><select class="inp grow" id="pnPf" style="max-width:300px"><option value="">सभी प्रोडक्ट के नियम</option>' + Object.keys(pids).map(function (id) { return '<option value="' + esc(id) + '"' + (ST.pf === id ? ' selected' : '') + '>' + esc(pname(id)) + '</option>'; }).join('') + '</select>' +
    '<select class="inp grow" id="pnSf" style="max-width:200px"><option value="">आउट + इन दोनों</option><option value="out"' + (ST.sf === 'out' ? ' selected' : '') + '>❌ सिर्फ़ आउट-ऑफ़-स्टॉक</option><option value="in"' + (ST.sf === 'in' ? ' selected' : '') + '>✅ सिर्फ़ उपलब्ध</option></select>' +
    (ST.sum.length ? '<button class="btn red sm" data-pn="delall">🗑 सारे नियम हटाएँ</button>' : '') + '</div>';
  var list = ST.sum.filter(function (g) { return (!ST.pf || g.product_id === ST.pf) && (!ST.sf || g.status === ST.sf); });
  if (!list.length) return h + '<div class="empty">' + (ST.sum.length ? 'इस फ़िल्टर में कोई नियम नहीं' : 'अभी कोई नियम नहीं है — सभी प्रोडक्ट सभी पिनकोड पर उपलब्ध हैं। ऊपर "➕ आउट-ऑफ़-स्टॉक / उपलब्धता सेट करें" दबाएँ।') + '</div>';
  return h + list.map(function (g, i) {
    var sample = g.sample.map(function (v) { return valLabel(g.scope, v); }).join(', ') + (g.n > g.sample.length ? ' … +' + nf(g.n - g.sample.length) + ' और' : '');
    return '<div class="row"><div class="th" style="font-size:22px">' + (g.status === 'out' ? '❌' : '✅') + '</div><div class="rm"><b>' + esc(pname(g.product_id)) + ' — ' + (g.status === 'out' ? 'उपलब्ध नहीं' : 'उपलब्ध') + '</b><small>' + esc(SCOPES[g.scope]) + ' (' + nf(g.n) + '): ' + esc(sample) + '</small></div>' +
      '<div class="acts"><button class="ib" data-pn="view" data-i="' + ST.sum.indexOf(g) + '" title="सब देखें / चुनकर हटाएँ">👁</button><button class="ib red" data-pn="delg" data-i="' + ST.sum.indexOf(g) + '" title="ये पूरा समूह हटाएँ">🗑</button></div></div>';
  }).join('');
}
function areasHtml() {
  var h = '<div class="bar"><button class="btn" data-pn="areaNew">➕ नया Area</button><span class="btn out upl">📤 Excel से Area (area, pincode)<input type="file" accept=".xlsx" data-pn="areaXup"></span><button class="btn out" data-pn="areaXdown">📥 सारे Area Excel में</button></div>' +
    '<div class="note g">📌 <b>Custom Area</b> = पिनकोड का अपना समूह (जैसे "Lucknow City", "Hardoi belt")। एक बार बनाएँ, फिर किसी भी प्रोडक्ट के लिए चुनें। पिनकोड मैन्युअल लिखें, या Excel/CSV से डालें — रेंज (226001-226030) भी चलती है।</div>';
  if (!ST.areas.length) return h + '<div class="empty">अभी कोई Area नहीं बना</div>';
  return h + ST.areas.map(function (a, i) {
    return '<div class="row"><div class="th">📌</div><div class="rm"><b>' + esc(a.label) + '</b><small>' + nf(a.n) + ' पिनकोड • ' + nf(a.rules) + ' नियम इस Area पर लगे हैं</small></div>' +
      '<div class="acts"><button class="ib" data-pn="areaEdit" data-i="' + i + '" title="एडिट">✏️</button><button class="ib" data-pn="areaDown" data-i="' + i + '" title="Excel डाउनलोड">📥</button><button class="ib red" data-pn="areaDel" data-i="' + i + '" title="हटाएँ">🗑</button></div></div>';
  }).join('');
}
function masterHtml() {
  var I = ST.info, h = '<div class="card"><h2>🗺️ पिनकोड मास्टर (State / District पहचानने के लिए)</h2>';
  h += I.master ? '<p>✅ <b>' + nf(I.master) + '</b> पिनकोड लोड हैं • <b>' + nf((I.states || []).length) + '</b> State/UT • <b>' + nf((I.states || []).reduce(function (s, x) { return s + (x.d || []).length; }, 0)) + '</b> District.</p>' :
    '<p>⚠️ अभी मास्टर लोड नहीं है — इसके बिना <b>State-wise</b> और <b>District-wise</b> नियम नहीं बन सकते। (All, Custom Area, और पिनकोड-वार नियम बिना मास्टर के चलते हैं।)</p>';
  h += '<div class="note">📥 <b>कैसे लोड करें (एक ही बार):</b> सरकारी <b>data.gov.in</b> पर "All India Pincode Directory" (India Post) की CSV फ़ाइल मुफ़्त डाउनलोड करें और नीचे अपलोड करें। CSV में <i>pincode, district, statename</i> कॉलम होने चाहिए (officename हो तो अच्छा)। Excel (.xlsx) भी चलती है पर इतनी बड़ी फ़ाइल के लिए CSV तेज़ है। फ़ाइल सिर्फ़ आपके ब्राउज़र में पढ़ी जाती है; सिर्फ़ पिनकोड-State-District डेटाबेस में जाता है।</div>' +
    '<div class="bar"><span class="btn upl">📤 पिनकोड फ़ाइल चुनें (CSV / XLSX)<input type="file" accept=".csv,.xlsx,.txt" data-pn="masterUp"></span>' + (I.master ? '<button class="btn red" data-pn="masterClear">🗑 मास्टर हटाएँ</button>' : '') + '</div><div id="pnMasterOut" style="font-size:14px"></div></div>';
  return h;
}

/* ---------- checklist widget ---------- */
function checklist(id, items, opts) {
  opts = opts || {};
  return '<div data-ck="' + id + '"><div class="bar" style="margin-bottom:6px"><input class="inp grow" data-flt placeholder="🔎 खोजें…" style="max-width:260px"><button type="button" class="btn gray sm" data-ckall>दिखे हुए सब चुनें</button><button type="button" class="btn gray sm" data-ckclr>सब हटाएँ</button><small data-ckn style="color:var(--mut)"></small></div>' +
    '<div class="secs" style="max-height:' + (opts.h || 200) + 'px">' + items.map(function (it) { return '<label data-t="' + esc(String(it.l).toLowerCase()) + '"><input type="checkbox" value="' + esc(it.v) + '"' + (it.on ? ' checked' : '') + '> <span>' + esc(it.l) + '</span></label>'; }).join('') + '</div></div>';
}
function ckBind(root, onchange) {
  $$('[data-ck]', root).forEach(function (w) {
    var upd = function () { var n = $$('input[type=checkbox]:checked', w).length; var s = $('[data-ckn]', w); if (s) s.textContent = n ? n + ' चुने' : ''; if (onchange) onchange(); };
    $('[data-flt]', w).addEventListener('input', function (e) { var q = e.target.value.trim().toLowerCase(); $$('label', w).forEach(function (l) { l.style.display = !q || l.getAttribute('data-t').indexOf(q) >= 0 ? '' : 'none'; }); });
    $('[data-ckall]', w).addEventListener('click', function () { $$('label', w).forEach(function (l) { if (l.style.display !== 'none') $('input', l).checked = true; }); upd(); });
    $('[data-ckclr]', w).addEventListener('click', function () { $$('input', w).forEach(function (i) { if (i.type === 'checkbox') i.checked = false; }); upd(); });
    w.addEventListener('change', upd); upd();
  });
}
function ckVals(root, id) { var w = $('[data-ck="' + id + '"]', root); return w ? $$('input[type=checkbox]:checked', w).map(function (i) { return i.value; }) : []; }

/* ---------- wizard: out-of-stock / availability ---------- */
function wizard() {
  var I = ST.info, hasMaster = I.master > 0, areas = ST.areas || [], P = prods();
  var states = (I.states || []), dist = [];
  states.forEach(function (s) { (s.d || []).forEach(function (d) { dist.push({ v: s.s + '|' + d, l: tc(d) + ', ' + tc(s.s) }); }); });
  var body = '<div class="fld"><label class="l">1) किन प्रोडक्ट के लिए?</label><label class="chk"><input type="checkbox" id="wzAllP"> सभी प्रोडक्ट (एक नियम सब पर)</label><div id="wzPwrap">' +
    checklist('prod', P.map(function (p) { return { v: p.id, l: (p.title || p.id) + (p.sku ? ' • ' + p.sku : '') }; }), { h: 170 }) + '</div></div>' +
    '<div class="fld" style="margin-top:12px"><label class="l">2) क्या करना है?</label>' +
    '<label class="chk"><input type="radio" name="wzAct" value="out" checked> ❌ आउट-ऑफ़-स्टॉक / "इस पिनकोड पर उपलब्ध नहीं"</label>' +
    '<label class="chk"><input type="radio" name="wzAct" value="in"> ✅ उपलब्ध / इन-स्टॉक (बाक़ी जगह के नियम के ऊपर अपवाद)</label>' +
    '<label class="chk"><input type="radio" name="wzAct" value="only"> 🎯 सिर्फ़ इन पिनकोड पर ऑनलाइन दिखाओ (बाक़ी जगह नहीं बिकेगा)</label>' +
    '<label class="chk"><input type="radio" name="wzAct" value="del"> 🗑 इन जगहों से नियम हटाओ</label></div>' +
    '<div class="fld" style="margin-top:12px"><label class="l">3) कहाँ?</label>' +
    '<label class="chk"><input type="radio" name="wzSc" value="all" checked> 🌍 सभी पिनकोड (पूरे देश में)</label>' +
    '<label class="chk"><input type="radio" name="wzSc" value="state"> 🗺️ State-wise' + (hasMaster ? '' : ' <small>(पहले पिनकोड मास्टर लोड करें)</small>') + '</label>' +
    '<label class="chk"><input type="radio" name="wzSc" value="district"> 🏙️ District-wise' + (hasMaster ? '' : ' <small>(पहले पिनकोड मास्टर लोड करें)</small>') + '</label>' +
    '<label class="chk"><input type="radio" name="wzSc" value="area"> 📌 Custom Area</label>' +
    '<label class="chk"><input type="radio" name="wzSc" value="pin"> 🔢 ख़ास पिनकोड (मैन्युअल लिखें या Excel/CSV से)</label>' +
    '<div id="wzS_state" class="hide">' + checklist('state', states.map(function (s) { return { v: s.s, l: tc(s.s) }; })) + '</div>' +
    '<div id="wzS_district" class="hide">' + checklist('district', dist) + '</div>' +
    '<div id="wzS_area" class="hide">' + (areas.length ? checklist('area', areas.map(function (a) { return { v: a.name, l: a.label + ' (' + a.n + ' पिन)' }; })) : '<div class="note">अभी कोई Area नहीं है — "📌 Custom Area" टैब में पहले बनाएँ, या "ख़ास पिनकोड" चुनें।</div>') + '</div>' +
    '<div id="wzS_pin" class="hide"><textarea class="inp" id="wzPins" rows="4" placeholder="226001, 226002 226010-226020 …   (कॉमा / स्पेस / नई लाइन / रेंज चलेगा)"></textarea><div class="bar" style="margin-top:6px"><span class="btn out sm upl">📤 Excel/CSV से पिनकोड जोड़ें<input type="file" accept=".xlsx,.csv,.txt" id="wzPinFile"></span><small id="wzPinN" style="color:var(--mut)"></small></div></div></div>' +
    '<div class="note g" id="wzPrev" style="margin-top:12px"></div>';
  X.modal('📍 पिनकोड के हिसाब से उपलब्धता', body, [{ l: 'रद्द करें', cls: 'gray' }, { l: 'लागू करें', id: 'wzGo', fn: function (md) { return wizGo(md); } }], function (md) {
    var b = md.body;
    var rd = function (n) { var r = $('input[name=' + n + ']:checked', b); return r ? r.value : ''; };
    var scopeRows = function () {
      var sc = rd('wzSc'), v = [];
      if (sc === 'all') v = ['*']; else if (sc === 'state') v = ckVals(b, 'state'); else if (sc === 'district') v = ckVals(b, 'district'); else if (sc === 'area') v = ckVals(b, 'area');
      else { var pr = parsePins($('#wzPins', b).value); v = pr.pins; $('#wzPinN', b).textContent = pr.pins.length ? nf(pr.pins.length) + ' पिनकोड' + (pr.bad ? ' • ' + pr.bad + ' गलत छोड़े' : '') : ''; }
      return { sc: sc, v: v };
    };
    var prev = function () {
      var sc = rd('wzSc'), act = rd('wzAct'), np = $('#wzAllP', b).checked ? 1 : ckVals(b, 'prod').length, loc = scopeRows().v.length;
      ['state', 'district', 'area', 'pin'].forEach(function (k) { $('#wzS_' + k, b).classList.toggle('hide', sc !== k); });
      $('#wzPwrap', b).classList.toggle('hide', $('#wzAllP', b).checked);
      var allR = $('input[name=wzSc][value=all]', b); if (act === 'only') { if (sc === 'all') { var f = $('input[name=wzSc][value=pin]', b); f.checked = true; return prev(); } allR.disabled = true; } else allR.disabled = false;
      $('#wzPrev', b).textContent = '👉 ' + (np ? ($('#wzAllP', b).checked ? 'सभी प्रोडक्ट' : nf(np) + ' प्रोडक्ट') : 'कोई प्रोडक्ट नहीं चुना') + ' × ' + nf(loc) + ' जगह = ' + nf(np * loc) + ' नियम' + (act === 'del' ? ' (हटेंगे)' : '');
    };
    ckBind(b, prev);
    b.addEventListener('input', prev); b.addEventListener('change', prev);
    $('#wzPinFile', b).addEventListener('change', async function (e) {
      var f = e.target.files[0]; if (!f) return;
      try { var t = await fileToText(f), ta = $('#wzPins', b); ta.value = (ta.value.trim() ? ta.value.trim() + '\n' : '') + parsePins(t).pins.join(', '); prev(); X.toast('✅ फ़ाइल से पिनकोड जुड़ गए'); } catch (er) { X.toast('❌ ' + er.message, true); }
      e.target.value = '';
    });
    prev();
  });
}
async function wizGo(md) {
  var b = md.body, rd = function (n) { var r = $('input[name=' + n + ']:checked', b); return r ? r.value : ''; };
  var sc = rd('wzSc'), act = rd('wzAct'), allP = $('#wzAllP', b).checked, pids = allP ? ['*'] : ckVals(b, 'prod'), v = [];
  if (!pids.length) { X.toast('कम से कम एक प्रोडक्ट चुनें (या "सभी प्रोडक्ट")', true); return false; }
  if (sc === 'all') v = ['*']; else if (sc === 'state') v = ckVals(b, 'state'); else if (sc === 'district') v = ckVals(b, 'district'); else if (sc === 'area') v = ckVals(b, 'area'); else v = parsePins($('#wzPins', b).value).pins;
  if (!v.length) { X.toast('कम से कम एक जगह चुनें / लिखें', true); return false; }
  if (act === 'only' && sc === 'all') { X.toast('"सिर्फ़ इन पिनकोड" के लिए All नहीं चलेगा', true); return false; }
  if (pids.length * v.length > 150000) { X.toast('इतने सारे नियम एक साथ नहीं — "सभी प्रोडक्ट" चुनें या जगह कम करें', true); return false; }
  var rows = [];
  pids.forEach(function (pid) { v.forEach(function (x) { rows.push({ product_id: pid, scope: sc, value: x, status: act === 'out' ? 'out' : 'in', action: act === 'del' ? 'delete' : '' }); }); });
  if (act === 'del' && !(await X.ask('चुनी हुई जगहों से <b>' + nf(rows.length) + '</b> नियम हटाए जाएँगे। ठीक है?', 'हाँ, हटाएँ', true))) return false;
  var res = await applyAll(rows, null);
  if (act === 'only') for (var i = 0; i < pids.length; i++) await call('sp_pin_mode_set', { p_product_id: pids[i], p_mode: 'only' });
  await reload(); showResult(res, act === 'only' ? pids.length + ' प्रोडक्ट "सिर्फ़ चुने पिनकोड" मोड में किए गए' : '');
  return true;
}
async function applyAll(rows, replaceProducts) {
  var tot = { added: 0, updated: 0, deleted: 0, replaced: 0, bad: 0, errors: [] }, parts = chunks(rows, 4000);
  for (var i = 0; i < parts.length; i++) {
    X.toast('⏳ लागू हो रहा है… ' + (i + 1) + '/' + parts.length);
    var r = await call('sp_pin_rules_apply', { p_rows: parts[i], p_replace_products: i === 0 && replaceProducts && replaceProducts.length ? replaceProducts : null });
    ['added', 'updated', 'deleted', 'replaced', 'bad'].forEach(function (k) { tot[k] += r[k] || 0; });
    (r.errors || []).forEach(function (e) { if (tot.errors.length < 60) tot.errors.push(e); });
  }
  return tot;
}
function showResult(r, extra) {
  var h = '<p style="font-size:16px">✅ <b>' + nf(r.added) + '</b> नए • <b>' + nf(r.updated) + '</b> बदले • <b>' + nf(r.deleted) + '</b> हटे' + (r.replaced ? ' • <b>' + nf(r.replaced) + '</b> पुराने बदले गए' : '') + (r.bad ? ' • <b style="color:var(--red)">' + nf(r.bad) + '</b> गलत छोड़े' : '') + '</p>' + (extra ? '<p>' + esc(extra) + '</p>' : '');
  if (r.errors && r.errors.length) h += '<div class="note r" style="max-height:220px;overflow:auto">' + r.errors.map(function (e) { return esc(e); }).join('<br>') + '</div>';
  X.modal('नतीजा', h, [{ l: 'ठीक है' }]);
}

/* ---------- view / delete a group ---------- */
async function viewGroup(g) {
  var F = { product_id: g.product_id, scope: g.scope, status: g.status, q: '', limit: 200, offset: 0 }, sel = {};
  var m = X.modal(pname(g.product_id) + ' — ' + SCOPES[g.scope] + ' — ' + (g.status === 'out' ? 'उपलब्ध नहीं' : 'उपलब्ध'), '<div id="vgBody"><span class="spin"></span></div>', [{ l: 'बंद करें', cls: 'gray' }, { l: '🗑 चुने हुए हटाएँ', cls: 'red', id: 'vgDel', fn: async function () {
    var ids = Object.keys(sel); if (!ids.length) { X.toast('पहले कुछ चुनें', true); return false; }
    var r = await call('sp_pin_rules_delete', { p_f: { ids: ids } }); X.toast('🗑 ' + nf(r.deleted) + ' नियम हटे'); await reload(); return true;
  } }]);
  async function draw() {
    var r = await call('sp_pin_rules_list', { p_f: F }), body = $('#vgBody', m.el);
    body.innerHTML = '<div class="bar"><input class="inp grow" id="vgQ" placeholder="🔎 खोजें" value="' + esc(F.q) + '" style="max-width:240px"><small>' + nf(r.total) + ' नियम' + (r.total > F.limit ? ' • ' + (F.offset + 1) + '–' + Math.min(r.total, F.offset + F.limit) : '') + '</small>' +
      '<button class="btn gray sm" id="vgAll">इस पेज के सब चुनें</button>' + (F.offset > 0 ? '<button class="btn gray sm" id="vgPrev">◀</button>' : '') + (F.offset + F.limit < r.total ? '<button class="btn gray sm" id="vgNext">▶</button>' : '') + '</div>' +
      '<div class="secs" style="max-height:340px">' + r.rows.map(function (x) { return '<label><input type="checkbox" data-id="' + x.id + '"' + (sel[x.id] ? ' checked' : '') + '> <span>' + esc(valLabel(x.scope, x.value)) + '</span></label>'; }).join('') + '</div>';
    $$('input[data-id]', body).forEach(function (c) { c.onchange = function () { if (c.checked) sel[c.getAttribute('data-id')] = 1; else delete sel[c.getAttribute('data-id')]; }; });
    $('#vgAll', body).onclick = function () { $$('input[data-id]', body).forEach(function (c) { c.checked = true; sel[c.getAttribute('data-id')] = 1; }); };
    var q = $('#vgQ', body); q.onchange = function () { F.q = q.value.trim(); F.offset = 0; draw(); };
    var pv = $('#vgPrev', body), nx = $('#vgNext', body); if (pv) pv.onclick = function () { F.offset = Math.max(0, F.offset - F.limit); draw(); }; if (nx) nx.onclick = function () { F.offset += F.limit; draw(); };
  }
  try { await draw(); } catch (e) { X.toast(e.message, true); }
}

/* ---------- areas ---------- */
function areaModal(a) {
  var pre = null;
  var body = '<div class="fg"><div class="fld full"><label class="l">Area का नाम *</label><input type="text" id="arName" maxlength="60" value="' + esc(a ? a.label : '') + '" placeholder="जैसे: Lucknow City"' + (a ? ' readonly' : '') + '><span class="help">' + (a ? 'नाम बदलने के लिए नया Area बनाकर पुराना हटाएँ।' : 'यही नाम नियम बनाते समय दिखेगा।') + '</span></div>' +
    '<div class="fld full"><label class="l">पिनकोड</label><textarea id="arPins" rows="6" placeholder="226001, 226002 226010-226020 …"></textarea><span class="help" id="arN"></span></div>' +
    '<div class="fld full"><span class="btn out sm upl">📤 Excel/CSV से पिनकोड जोड़ें<input type="file" accept=".xlsx,.csv,.txt" id="arFile"></span></div></div>';
  X.modal(a ? '✏️ Area एडिट' : '➕ नया Area', body, [{ l: 'रद्द करें', cls: 'gray' }, { l: 'सेव करें', id: 'arSave', fn: async function (md) {
    var nm = $('#arName', md.body).value.trim(), pr = parsePins($('#arPins', md.body).value);
    if (!nm) { X.toast('Area का नाम लिखें', true); return false; } if (!pr.pins.length) { X.toast('कम से कम एक सही पिनकोड डालें', true); return false; }
    var r = await call('sp_pin_area_save', { p_label: nm, p_pins: pr.pins, p_add: false }); X.toast('✅ ' + nf(r.n) + ' पिनकोड का Area सेव हुआ'); await reload(); return true;
  } }], async function (md) {
    var ta = $('#arPins', md.body), n = $('#arN', md.body), upd = function () { var pr = parsePins(ta.value); n.textContent = pr.pins.length ? nf(pr.pins.length) + ' पिनकोड' + (pr.bad ? ' • ' + pr.bad + ' गलत' : '') : ''; };
    ta.addEventListener('input', upd);
    $('#arFile', md.body).addEventListener('change', async function (e) { var f = e.target.files[0]; if (!f) return; try { var t = await fileToText(f); ta.value = (ta.value.trim() ? ta.value.trim() + '\n' : '') + parsePins(t).pins.join(', '); upd(); } catch (er) { X.toast('❌ ' + er.message, true); } e.target.value = ''; });
    if (a) { try { var r = await call('sp_pin_area_get', { p_name: a.name }); ta.value = r.pins.join(', '); upd(); } catch (er) { X.toast(er.message, true); } }
  });
}
function normN(x) { return String(x == null ? '' : x).trim().toLowerCase(); }
async function areaDown(list) {
  var rows = [];
  for (var i = 0; i < list.length; i++) { var r = await call('sp_pin_area_get', { p_name: list[i].name }); r.pins.forEach(function (p) { rows.push([r.label, p]); }); }
  var out = await SPSH.dl('Area पिनकोड', { head: ['area', 'pincode'], rows: rows }, { lock: ['area', 'pincode'], okLabel: '⬇️ Area शीट डाउनलोड' });
  if (!out) return;
  var labels = {}; out.rows.forEach(function (r) { labels[r[0]] = 1; });
  var iss = await SPSH.issue('sp_pin', [], Object.keys(labels).map(function (l) { return 'area:' + normN(l); }), out.desc);
  X.download(XLSXLite.write([{ name: 'Areas', rows: [out.head].concat(out.rows), widths: [26, 12] }, SPSH.metaSheet(iss.code)]), 'sunpowers-pincode-areas-' + X.today() + '.xlsx'); X.toast('📥 Area शीट डाउनलोड हो गई');
}
function sheetAreas(wb) {
  var s = wb.Areas || wb.Area; if (!s || !s.length) return null;
  var hd = (s[0] || []).map(function (x) { return String(x).trim().toLowerCase(); }), ai = hd.indexOf('area'), pi = Math.max(hd.indexOf('pincode'), hd.indexOf('pin'));
  if (ai < 0 || pi < 0) return null; var map = {}, ord = [];
  for (var i = 1; i < s.length; i++) { var nm = String(s[i][ai] || '').trim(); if (!nm) continue; if (!map[nm]) { map[nm] = []; ord.push(nm); } map[nm].push(String(s[i][pi] == null ? '' : s[i][pi])); }
  return ord.map(function (n) { return { label: n, pins: parsePins(map[n].join(' ')).pins }; });
}
async function areaXup(file) {
  var wb; try { wb = await XLSXLite.read(await file.arrayBuffer()); } catch (e) { return X.toast('❌ ' + e.message, true); }
  var areas = sheetAreas(wb) || (function () { var s = wb[Object.keys(wb)[0]] || []; var hd = (s[0] || []).map(function (x) { return String(x).trim().toLowerCase(); }); if (hd.indexOf('area') < 0) return null; return sheetAreas({ Areas: s }); })();
  if (!areas || !areas.length) return X.toast('❌ शीट में "area" और "pincode" कॉलम चाहिए', true);
  var code = SPSH.codeOf(wb), allowed = null;
  if (code) { var sc = await SPSH.check(code, 'sp_pin'); allowed = {}; (sc.cols || []).forEach(function (c) { allowed[String(c).replace(/^area:/, '')] = 1; }); }
  var existing = {}; (ST.areas || []).forEach(function (a) { existing[normN(a.name)] = 1; existing[normN(a.label)] = 1; });
  var blocked = [];
  areas = areas.filter(function (a) { var k = normN(a.label); if (!existing[k]) return true; if (allowed && allowed[k]) return true; blocked.push(a.label); return false; });
  if (blocked.length) X.toast('⚠️ ' + blocked.length + ' मौजूदा Area छोड़े गए (' + (code ? 'इस शीट के दायरे में नहीं' : '"बिना कोड की शीट"') + '): ' + blocked.slice(0, 3).join(', '), true);
  if (!areas.length) return X.toast('❌ बदलने लायक कोई Area नहीं — ' + (code ? 'कोई Area शीट के दायरे में नहीं' : 'मौजूदा Area बदलने के लिए "Area शीट डाउनलोड" वाली शीट ही चाहिए'), true);
  var ok = await X.ask('<b>' + areas.length + '</b> Area मिले (' + nf(areas.reduce(function (s, a) { return s + a.pins.length; }, 0)) + ' पिनकोड)। इसी नाम के पुराने Area के पिनकोड <b>बदल</b> दिए जाएँगे; नए बन जाएँगे।', 'हाँ, लागू करें');
  if (!ok) return;
  var n = 0; for (var i = 0; i < areas.length; i++) { if (!areas[i].pins.length) continue; await call('sp_pin_area_save', { p_label: areas[i].label, p_pins: areas[i].pins, p_add: false }); n++; }
  X.toast('✅ ' + n + ' Area सेव हुए'); await reload();
}

/* ---------- excel: rules ---------- */
async function rulesDown() {
  X.toast('⏳ तैयार हो रहा है…');
  var rows = await call('sp_pin_rules_export', { p_f: {} }, 120000), P = prods(), nm = {};
  P.forEach(function (p) { nm[p.id] = p.title || p.id; }); nm['*'] = 'सभी प्रोडक्ट';
  var rr = [['product_id', 'product_name (सिर्फ़ जानकारी)', 'scope', 'value', 'status', 'action']];
  rows.forEach(function (r) { rr.push([r[0], nm[r[0]] || '(हटाया हुआ)', r[1], r[1] === 'district' ? String(r[2]).replace('|', ' | ') : r[2], r[3], '']); });
  var fo = await SPSH.dl('पिनकोड नियम', { head: rr[0], rows: rr.slice(1) }, { lock: rr[0], okLabel: '⬇️ Excel डाउनलोड' });
  if (!fo) return;
  rr = [fo.head].concat(fo.rows);
  var pidSet = {}; fo.rows.forEach(function (r) { pidSet[String(r[0])] = 1; });
  var ar = [['area', 'pincode']], aLab = {};
  for (var i = 0; i < (ST.areas || []).length; i++) { var a = await call('sp_pin_area_get', { p_name: ST.areas[i].name }); a.pins.forEach(function (p) { ar.push([a.label, p]); }); aLab['area:' + normN(a.label)] = 1; }
  var iss = await SPSH.issue('sp_pin', Object.keys(pidSet), ['rules'].concat(Object.keys(aLab)), fo.desc);
  var guide = [['पिनकोड नियम Excel — कैसे भरें'], [''],
    ['Rules शीट: हर लाइन = एक नियम। कॉलम: product_id, scope, value, status, action'],
    ['product_id: Products शीट वाली id, या * (सभी प्रोडक्ट)'],
    ['scope: all | state | district | area | pin'],
    ['value: all के लिए * ; state के लिए UTTAR PRADESH ; district के लिए UTTAR PRADESH | LUCKNOW ; area के लिए Area का नाम ; pin के लिए 6 अंक का पिनकोड'],
    ['status: out (उपलब्ध नहीं) या in (उपलब्ध)'],
    ['action: ख़ाली = जोड़ो/बदलो ; delete = ये नियम हटाओ'],
    ['वही नियम दोबारा अपलोड करने पर डुप्लीकेट नहीं बनता — सिर्फ़ status बदलता है।'],
    ['Areas शीट: area, pincode (एक लाइन = एक पिनकोड)। अपलोड पर इसी नाम का Area बदल जाता है।'],
    ['अपलोड करते समय "Replace" चुनें तो शीट में जिन प्रोडक्ट के नियम हैं, उनके पुराने सारे नियम हटकर शीट जैसे हो जाएँगे।']];
  X.download(XLSXLite.write([{ name: 'Rules', rows: rr, widths: [18, 34, 10, 34, 8, 10] }, { name: 'Areas', rows: ar, widths: [26, 12] },
    { name: 'Products', rows: [['id', 'title']].concat(P.map(function (p) { return [p.id, p.title || '']; })), widths: [18, 50] }, { name: 'Guide', rows: guide, widths: [120] }, SPSH.metaSheet(iss.code)]), 'sunpowers-pincode-rules-' + X.today() + '.xlsx');
  X.toast('📥 Excel डाउनलोड हो गई (' + nf(fo.rows.length) + ' नियम)');
}
async function rulesUp(file) {
  var wb; try { wb = await XLSXLite.read(await file.arrayBuffer()); } catch (e) { return X.toast('❌ ' + e.message, true); }
  var code = SPSH.codeOf(wb); if (!code) return X.toast('❌ ये शीट बिना कोड की है — सिर्फ़ "Excel डाउनलोड" / "Area शीट डाउनलोड" से बनी शीट ही वापस ली जाएगी।', true);
  var sc; try { sc = await SPSH.check(code, 'sp_pin'); } catch (e) { return X.toast('❌ ' + e.message, true); }
  var scP = {}, scA = {}; (sc.ids || []).forEach(function (i) { scP[String(i)] = 1; }); (sc.cols || []).forEach(function (c) { c = String(c); if (c.indexOf('area:') === 0) scA[c.slice(5)] = 1; });
  var sh = wb.Rules || wb[Object.keys(wb)[0]]; if (!sh || sh.length < 2) return X.toast('❌ "Rules" शीट नहीं मिली / ख़ाली है', true);
  var hd = sh[0].map(function (x) { return String(x).trim().toLowerCase(); }), col = function () { for (var a = 0; a < arguments.length; a++) { var i = hd.indexOf(arguments[a]); if (i >= 0) return i; } return -1; };
  var ci = { p: col('product_id', 'product id', 'id'), s: col('scope'), v: col('value'), t: col('status'), a: col('action') };
  if (ci.p < 0 || ci.s < 0 || ci.t < 0) return X.toast('❌ कॉलम चाहिए: product_id, scope, value, status', true);
  var rows = [], cnt = { out: 0, in: 0, del: 0 }, scn = {}, pids = {}, outScope = 0;
  for (var i = 1; i < sh.length; i++) {
    var r = sh[i]; if (!r || r.every(function (x) { return x === '' || x == null; })) continue;
    var o = { product_id: String(r[ci.p] == null ? '' : r[ci.p]).trim(), scope: String(r[ci.s] == null ? '' : r[ci.s]).trim(), value: ci.v >= 0 ? String(r[ci.v] == null ? '' : r[ci.v]).trim() : '', status: String(r[ci.t] == null ? '' : r[ci.t]).trim() || 'out', action: ci.a >= 0 ? String(r[ci.a] == null ? '' : r[ci.a]).trim() : '' };
    if (o.scope.toLowerCase() === 'all' && !o.value) o.value = '*';
    if (!scP[o.product_id]) { outScope++; continue; }
    rows.push(o); pids[o.product_id] = 1; scn[o.scope.toLowerCase()] = (scn[o.scope.toLowerCase()] || 0) + 1;
    if (/^(delete|del|remove|hatao)$/i.test(o.action)) cnt.del++; else if (/^(in|available|yes)/i.test(o.status)) cnt.in++; else cnt.out++;
  }
  var areas = sheetAreas(wb), existingA = {}; (ST.areas || []).forEach(function (a) { existingA[normN(a.name)] = 1; existingA[normN(a.label)] = 1; });
  var areaSkip = 0; if (areas) areas = areas.filter(function (a) { var k = normN(a.label); if (!existingA[k] || scA[k]) return true; areaSkip++; return false; });
  if (!rows.length && !(areas && areas.length)) return X.toast('❌ शीट में दायरे के अंदर कोई लाइन नहीं मिली' + (outScope ? ' (' + outScope + ' लाइनें दायरे से बाहर थीं)' : ''), true);
  var body = '<p>📄 <b>' + nf(rows.length) + '</b> नियम-लाइन • <b>' + Object.keys(pids).length + '</b> प्रोडक्ट' + (areas ? ' • <b>' + areas.length + '</b> Area' : '') + '</p><p>❌ उपलब्ध नहीं: <b>' + nf(cnt.out) + '</b> • ✅ उपलब्ध: <b>' + nf(cnt.in) + '</b> • 🗑 हटाने वाली: <b>' + nf(cnt.del) + '</b></p>' + (outScope || areaSkip ? '<div class="note">⚠️ दायरे से बाहर होने के कारण छोड़ा गया: ' + outScope + ' नियम-लाइन' + (areaSkip ? ', ' + areaSkip + ' Area' : '') + '</div>' : '') + '<p><small>शीट कोड ' + esc(code) + '</small></p><p><small>' +
    Object.keys(scn).map(function (k) { return esc(k) + ': ' + nf(scn[k]); }).join(' • ') + '</small></p>' +
    '<label class="chk"><input type="radio" name="upm" value="merge" checked> जोड़ें / बदलें (Merge) — बाक़ी नियम वैसे ही रहेंगे</label>' +
    '<label class="chk"><input type="radio" name="upm" value="replace"> Replace — शीट के प्रोडक्ट के पुराने <b>सारे</b> नियम हटाकर शीट जैसा कर दें</label>';
  X.modal('📤 Excel अपलोड — जाँच', body, [{ l: 'रद्द करें', cls: 'gray' }, { l: 'लागू करें', fn: async function (md) {
    var rep = $('input[name=upm]:checked', md.body).value === 'replace';
    if (areas) for (var j = 0; j < areas.length; j++) if (areas[j].pins.length) await call('sp_pin_area_save', { p_label: areas[j].label, p_pins: areas[j].pins, p_add: false });
    var res = await applyAll(rows, rep ? Object.keys(pids).filter(function (x) { return x; }) : null); await reload(); showResult(res, ''); return true;
  } }]);
}

/* ---------- master ---------- */
async function masterUp(file) {
  var out = $('#pnMasterOut'); var say = function (t) { if (out) out.innerHTML = t; };
  say('<span class="spin"></span> फ़ाइल पढ़ी जा रही है…');
  var rows;
  try { rows = /\.xlsx$/i.test(file.name) ? (function (wb) { return wb[Object.keys(wb)[0]] || []; })(await XLSXLite.read(await file.arrayBuffer())) : parseCsv(await file.text()); } catch (e) { return say('<div class="note r">❌ ' + esc(e.message) + '</div>'); }
  if (rows.length < 2) return say('<div class="note r">❌ फ़ाइल ख़ाली है</div>');
  var hd = rows[0].map(function (x) { return String(x).trim().toLowerCase().replace(/[\s_]/g, ''); });
  var fi = function (names) { for (var a = 0; a < names.length; a++) { var i = hd.indexOf(names[a]); if (i >= 0) return i; } return -1; };
  var cp = fi(['pincode', 'pin', 'pincodeno', 'postalcode']), cs = fi(['statename', 'state']), cd = fi(['district', 'districtname']), co = fi(['officename', 'office', 'postoffice']);
  if (cp < 0 || cs < 0 || cd < 0) return say('<div class="note r">❌ कॉलम चाहिए: pincode, district, statename (आपकी फ़ाइल में: ' + esc(rows[0].slice(0, 12).join(', ')) + ')</div>');
  var seen = {}, list = [];
  for (var i = 1; i < rows.length; i++) {
    var r = rows[i], pin = String(r[cp] == null ? '' : r[cp]).replace(/\D/g, ''); if (!/^[1-9]\d{5}$/.test(pin) || seen[pin]) continue;
    var st = String(r[cs] || '').trim(), di = String(r[cd] || '').trim(); if (!st) continue; seen[pin] = 1;
    list.push({ p: pin, o: co >= 0 ? String(r[co] || '').trim() : '', d: di, s: st });
  }
  if (!list.length) return say('<div class="note r">❌ एक भी सही पिनकोड नहीं मिला</div>');
  if (!(await X.ask('<b>' + nf(list.length) + '</b> अलग-अलग पिनकोड मिले। मौजूदा मास्टर इनसे <b>बदल</b> दिया जाएगा (नियम वैसे ही रहेंगे)।', 'हाँ, लोड करें'))) return say('');
  var parts = chunks(list, 5000), ok = 0, bad = 0;
  try {
    for (var k = 0; k < parts.length; k++) { say('<span class="spin"></span> अपलोड… ' + (k + 1) + '/' + parts.length); var r2 = await call('sp_pin_master_load', { p_rows: parts[k], p_clear: k === 0 }); ok += r2.ok; bad += r2.bad; }
  } catch (e) { return say('<div class="note r">❌ ' + esc(e.message) + '</div>'); }
  say('<div class="note g">✅ ' + nf(ok) + ' पिनकोड लोड हो गए' + (bad ? ' • ' + nf(bad) + ' छोड़े' : '') + '</div>'); X.toast('✅ पिनकोड मास्टर तैयार'); await reload();
}

/* ---------- binding ---------- */
function bind(m) {
  var act = async function (el, ev) {
    var k = el.getAttribute('data-pn');
    try {
      if (k === 'retry') { ST.err = ''; ST.info = null; X.render(); }
      else if (k === 'tab') { ST.tab = el.getAttribute('data-t'); X.render(); }
      else if (k === 'wiz') wizard();
      else if (k === 'xdown') await rulesDown();
      else if (k === 'xup') { /* handled on change */ }
      else if (k === 'view') viewGroup(ST.sum[+el.getAttribute('data-i')]);
      else if (k === 'delg') {
        var g = ST.sum[+el.getAttribute('data-i')];
        if (await X.ask('<b>' + esc(pname(g.product_id)) + '</b> के ' + nf(g.n) + ' नियम (' + esc(SCOPES[g.scope]) + ', ' + (g.status === 'out' ? 'उपलब्ध नहीं' : 'उपलब्ध') + ') हटाएँ?', 'हाँ, हटाएँ', true)) { var r = await call('sp_pin_rules_delete', { p_f: { product_id: g.product_id, scope: g.scope, status: g.status } }); X.toast('🗑 ' + nf(r.deleted) + ' नियम हटे'); await reload(); }
      }
      else if (k === 'delall') {
        if (await X.ask('⚠️ <b>सारे</b> पिनकोड-नियम हट जाएँगे — सब प्रोडक्ट फिर हर पिनकोड पर उपलब्ध हो जाएँगे। Custom Area वैसे ही रहेंगे।', 'आगे बढ़ें', true) &&
            await X.ask('पक्का? ये वापस नहीं आएगा (पहले Excel डाउनलोड कर लें तो बैकअप रहेगा)।', 'हाँ, सब हटाएँ', true)) { var r2 = await call('sp_pin_rules_delete', { p_f: { all: true } }); X.toast('🗑 ' + nf(r2.deleted) + ' नियम हटे'); await reload(); }
      }
      else if (k === 'onlyoff') { await call('sp_pin_mode_set', { p_product_id: el.getAttribute('data-id'), p_mode: 'default' }); X.toast('✅ अब ये प्रोडक्ट सब जगह खुला है (उपलब्ध-नियम वैसे ही हैं)'); await reload(); }
      else if (k === 'test') {
        var pin = ($('#pnTestPin').value || '').replace(/\D/g, ''), pid = $('#pnTestProd').value, o = $('#pnTestOut');
        if (!/^[1-9]\d{5}$/.test(pin)) { o.innerHTML = '<span style="color:var(--red)">6 अंक का सही पिनकोड लिखें</span>'; return; } if (!pid) { o.innerHTML = '<span style="color:var(--red)">प्रोडक्ट चुनें</span>'; return; }
        var c = await X.rpc('sp_pin_check', { p_pin: pin, p_ids: [pid] }), bad = (c.bad || []).indexOf(pid) >= 0;
        o.innerHTML = (bad ? '❌ <b>उपलब्ध नहीं</b>' : '✅ <b>उपलब्ध</b>') + ' — ' + esc(c.known ? (tc(c.district) + ', ' + tc(c.state)) : 'पिनकोड मास्टर में नहीं मिला') + '<br><small>(स्टॉक "ख़त्म" वाले प्रोडक्ट हर जगह उपलब्ध नहीं दिखते।)</small>';
      }
      else if (k === 'areaNew') areaModal(null);
      else if (k === 'areaEdit') areaModal(ST.areas[+el.getAttribute('data-i')]);
      else if (k === 'areaDown') await areaDown([ST.areas[+el.getAttribute('data-i')]]);
      else if (k === 'areaXdown') { if (!ST.areas.length) return X.toast('अभी कोई Area नहीं', true); await areaDown(ST.areas); }
      else if (k === 'areaDel') {
        var a = ST.areas[+el.getAttribute('data-i')];
        if (await X.ask('Area <b>' + esc(a.label) + '</b> हटाएँ? इस पर लगे ' + nf(a.rules) + ' नियम भी हट जाएँगे।', 'हाँ, हटाएँ', true)) { await call('sp_pin_area_delete', { p_name: a.name }); X.toast('🗑 Area हट गया'); await reload(); }
      }
      else if (k === 'masterClear') {
        if (await X.ask('पिनकोड मास्टर हटाएँ? State/District वाले नियम तब तक काम नहीं करेंगे जब तक मास्टर दोबारा न डालें।', 'हाँ, हटाएँ', true)) { await call('sp_pin_master_clear'); X.toast('🗑 मास्टर हट गया'); await reload(); }
      }
    } catch (e) { console.error(e); X.toast(e.message || String(e), true); }
  };
  m.addEventListener('click', function (e) { var el = e.target.closest('[data-pn]'); if (!el || el.tagName === 'INPUT') return; act(el, e); });
  m.addEventListener('change', async function (e) {
    var t = e.target, k = t.getAttribute && t.getAttribute('data-pn');
    if (t.id === 'pnPf') { ST.pf = t.value; return X.render(); }
    if (t.id === 'pnSf') { ST.sf = t.value; return X.render(); }
    if (!k || !t.files || !t.files[0]) return;
    var f = t.files[0]; t.value = '';
    try { if (k === 'xup') await rulesUp(f); else if (k === 'areaXup') await areaXup(f); else if (k === 'masterUp') await masterUp(f); } catch (er) { console.error(er); X.toast(er.message || String(er), true); }
  });
}

window.SPPIN = { init: function (ctx) { X = ctx; }, html: html, bind: bind, reset: function () { ST.info = null; ST.err = ''; ST.loading = false; }, _parsePins: parsePins, _parseCsv: parseCsv };
})();
