/* Sunpowers Store Admin — 🗺️ कहाँ बेचना है (Round 60)
   Har item (product / service / project) ke liye: Poora Bharat / State (sab ziley ya ziley-wise) — har jagah ke liye
   delivery ke din + payment tarika (COD / pura payment pehle) + "abhi band" switch. Emergency switch: ek click me sab out of stock
   (customer ko pin / location dene ke baad dikhta hai; price dikhta rahta hai, order nahi hota).
   Data tables: sp_sell, sp_sell_cfg (SQL part U30). Server order ke time bhi dobara check karta hai (sp_pin_unavail / sp_sell_pay_guard). */
(function () {
'use strict';
var X = null;
var ST = { info: null, ov: null, cfg: null, tab: 'bulk', sel: {}, q: '', mode: 'merge', edObj: null, pl: { s: '', d: '', rows: null }, err: '', loading: false };
var $ = function (s, r) { return (r || document).querySelector(s); };
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
function tc(s) { return String(s || '').toLowerCase().replace(/(^|[\s(\-.])([a-z])/g, function (m, a, b) { return a + b.toUpperCase(); }); }
function call(fn, args, ms) { return X.rpc(fn, Object.assign({ p_pass: X.pass() }, args || {}), ms || 60000); }
function prods() { return (X.products() || []).filter(function (p) { return p && p.id; }); }
function pname(id) { var p = prods().filter(function (x) { return x.id === id; })[0]; return p ? (p.title || id) : id; }
function errMsg(e) { return String((e && e.message) || e || '').replace(/^.*?ERROR:\s*/, '').slice(0, 240); }

var CSS = '.sl-box{border:2px solid #d98a00;border-radius:12px;padding:14px;margin-top:14px;background:#fffdf6}.sl-box h3{margin:0 0 4px;font-size:16px}' +
  '.sl-sub{font-size:12px;color:#5c6573;line-height:1.5;margin-bottom:10px}.sl-card{border:1px solid #e0dacb;border-radius:10px;background:#fff;padding:10px 12px;margin-top:10px}' +
  '.sl-card.off{background:#fbf2f0;border-color:#e7bdb6}.sl-h{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-weight:700}.sl-h .sp{flex:1}' +
  '.sl-f{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:8px}.sl-f label{font-size:12px;color:#5c6573;font-weight:600}' +
  '.sl-f input[type=number]{width:74px}.sl-f select{max-width:100%}.sl-sw{border:1px solid #1f6b3a;background:#e6f3ea;color:#1f6b3a;font-weight:700;border-radius:8px;padding:6px 10px;cursor:pointer;min-height:36px}' +
  '.sl-sw.off{border-color:#9a3b2e;background:#f8e7e4;color:#9a3b2e}.sl-seg{display:inline-flex;border:1px solid #c9c3b3;border-radius:8px;overflow:hidden}' +
  '.sl-seg button{border:0;background:#fff;padding:7px 12px;cursor:pointer;font-weight:600;min-height:36px}.sl-seg button.on{background:#1b2430;color:#fff}' +
  '.sl-x{border:0;background:none;cursor:pointer;color:#9a3b2e;font-size:16px;min-width:36px;min-height:36px}.sl-d{margin-left:14px;border-left:3px solid #ebddb5;padding-left:10px}' +
  '.sl-warn{background:#fff4e0;border:1px solid #f0d49a;color:#7a4b00;border-radius:8px;padding:8px 10px;font-size:13px;line-height:1.5}' +
  '.sl-emg{border:2px solid #9a3b2e;background:#fbf2f0;border-radius:12px;padding:12px;margin-bottom:12px}.sl-emg.on{background:#9a3b2e;color:#fff}.sl-emg.on small{color:#fbe4df}' +
  '.sl-list{max-height:280px;overflow:auto;border:1px solid #e0dacb;border-radius:10px;background:#fff}.sl-list label{display:flex;gap:8px;align-items:center;padding:7px 10px;border-bottom:1px solid #f0ece0;cursor:pointer}' +
  '.sl-tbl{width:100%;border-collapse:collapse}.sl-tbl td,.sl-tbl th{padding:8px;border-bottom:1px solid #eee;text-align:left;font-size:13px}';

/* ------------------------------ data model <-> rows ------------------------------ */
function rule(r) { return { eta_min: r && r.eta_min ? +r.eta_min : '', eta_max: r && r.eta_max ? +r.eta_max : '', pay: r && r.pay === 'prepaid' ? 'prepaid' : 'both', off: !!(r && r.off) }; }
function toModel(rows) {
  var M = { india: null, states: [] }, idx = {};
  function st(n) { if (idx[n] == null) { idx[n] = M.states.length; M.states.push({ name: n, all: null, dists: [] }); } return M.states[idx[n]]; }
  (rows || []).forEach(function (r) {
    if (r.scope === 'all') M.india = rule(r);
    else if (r.scope === 'state') st(r.value).all = rule(r);
    else { var a = String(r.value).split('|'); st(a[0]).dists.push(Object.assign({ name: a[1] || '' }, rule(r))); }
  });
  return M;
}
function toRow(scope, value, r) {
  var mn = Math.max(0, Math.min(365, parseInt(r.eta_min, 10) || 0)), mx = Math.max(0, Math.min(365, parseInt(r.eta_max, 10) || 0));
  if (mx < mn) mx = mn;
  return { scope: scope, value: value, eta_min: mn, eta_max: mx, pay: r.pay === 'prepaid' ? 'prepaid' : 'both', off: !!r.off };
}
function toRows(M) {
  var out = []; if (M.india) out.push(toRow('all', '*', M.india));
  M.states.forEach(function (s) { if (s.all) out.push(toRow('state', s.name, s.all)); s.dists.forEach(function (d) { out.push(toRow('district', s.name + '|' + d.name, d)); }); });
  return out;
}
function statesList() { return (ST.info && ST.info.states) || []; }
function distsOf(sn) { var s = statesList().filter(function (x) { return x.s === sn; })[0]; return s ? (s.d || []) : []; }
function getRule(M, p) {
  if (p === 'i') return M.india;
  var m = /^s(\d+)(?:d(\d+))?$/.exec(p); if (!m) return null;
  var s = M.states[+m[1]]; if (!s) return null; return m[2] != null ? s.dists[+m[2]] : s.all;
}

/* ------------------------------ editor (one item or many) ------------------------------ */
function ruleHtml(p, r) {
  return '<div class="sl-f"><label>डिलीवरी</label><input class="inp" type="number" min="0" max="365" data-sl-f="eta_min" data-sl-p="' + p + '" value="' + esc(r.eta_min) + '" aria-label="कम से कम दिन" placeholder="10"> <label>से</label>' +
    '<input class="inp" type="number" min="0" max="365" data-sl-f="eta_max" data-sl-p="' + p + '" value="' + esc(r.eta_max) + '" aria-label="ज़्यादा से ज़्यादा दिन" placeholder="15"> <label>दिन</label></div>' +
    '<div class="sl-f"><label>पेमेंट</label><select class="inp" data-sl-f="pay" data-sl-p="' + p + '" aria-label="पेमेंट"><option value="both"' + (r.pay === 'both' ? ' selected' : '') + '>COD भी चलेगा</option><option value="prepaid"' + (r.pay === 'prepaid' ? ' selected' : '') + '>सिर्फ़ पूरा पेमेंट पहले</option></select></div>';
}
function swHtml(p, r) { return '<button type="button" class="sl-sw' + (r.off ? ' off' : '') + '" data-sl-a="off" data-sl-p="' + p + '" aria-pressed="' + (r.off ? 'true' : 'false') + '" title="इस जगह पर अभी बंद / चालू">' + (r.off ? '⛔ अभी बंद' : '✅ चालू') + '</button>'; }
function edHtml(E) {
  var M = E.M, h = '';
  if (!(ST.info && ST.info.master)) h += '<div class="sl-warn">⚠️ पिनकोड मास्टर (State / District की सूची) अभी लोड नहीं है। पहले <b>📍 पिनकोड → मास्टर</b> में फ़ाइल अपलोड करें, तभी राज्य और ज़िले चुन पाएँगे। तब तक सिर्फ़ <b>पूरा भारत</b> चुन सकते हैं।</div>';
  if (!M.india && !M.states.length) h += '<div class="sl-warn" style="margin-top:8px">ℹ️ अभी कोई जगह नहीं चुनी। ' + (E.multi ? 'इन आइटम की जगह नहीं बदलेगी जब तक आप नीचे कुछ चुनें।' : 'जगह चुनते ही यह <b>सिर्फ़ चुनी हुई जगह</b> पर बिकेगा; जो जगह नहीं चुनी वहाँ ग्राहक को “इस पिन कोड पर उपलब्ध नहीं” दिखेगा। कुछ न चुनें तो यह अभी की तरह सब जगह चलता रहेगा।') + '</div>';
  h += '<div class="sl-card' + (M.india && M.india.off ? ' off' : '') + '"><div class="sl-h"><label style="display:flex;gap:8px;align-items:center;cursor:pointer"><input type="checkbox" data-sl-a="india" ' + (M.india ? 'checked' : '') + '> 🇮🇳 पूरा भारत</label><span class="sp"></span>' + (M.india ? swHtml('i', M.india) : '') + '</div>' +
    (M.india ? ruleHtml('i', M.india) : '<div class="sl-sub" style="margin:6px 0 0">टिक करने पर पूरे भारत के लिए एक ही नियम (दिन + पेमेंट) लगेगा। नीचे राज्य / ज़िले जोड़कर किसी जगह का अलग नियम या बंद भी कर सकते हैं।</div>') + '</div>';
  M.states.forEach(function (s, i) {
    var P = 's' + i, all = !!s.all, avail = distsOf(s.name).filter(function (d) { return !s.dists.some(function (x) { return x.name === d; }); });
    h += '<div class="sl-card' + (s.all && s.all.off ? ' off' : '') + '"><div class="sl-h">📍 ' + esc(tc(s.name)) + '<span class="sp"></span>' + (all ? swHtml(P, s.all) : '') + '<button type="button" class="sl-x" data-sl-a="state-del" data-sl-i="' + i + '" aria-label="राज्य हटाएँ">✕</button></div>' +
      '<div class="sl-f"><span class="sl-seg"><button type="button" class="' + (all ? 'on' : '') + '" data-sl-a="mode-all" data-sl-i="' + i + '">सब ज़िले</button><button type="button" class="' + (all ? '' : 'on') + '" data-sl-a="mode-dist" data-sl-i="' + i + '">ज़िलेवार</button></span></div>' +
      (all ? ruleHtml(P, s.all) + '<div class="sl-sub" style="margin:8px 0 0">किसी ज़िले का अलग नियम / बंद करना हो तो नीचे जोड़ें:</div>' : (s.dists.length ? '' : '<div class="sl-sub" style="margin:8px 0 0">नीचे से वे ज़िले जोड़ें जहाँ बेचना है। जो ज़िला नहीं जोड़ेंगे वहाँ “उपलब्ध नहीं” दिखेगा।</div>'));
    s.dists.forEach(function (d, j) {
      var Q = P + 'd' + j;
      h += '<div class="sl-card sl-d' + (d.off ? ' off' : '') + '"><div class="sl-h">' + esc(tc(d.name)) + '<span class="sp"></span>' + swHtml(Q, d) + '<button type="button" class="sl-x" data-sl-a="dist-del" data-sl-i="' + i + '" data-sl-j="' + j + '" aria-label="ज़िला हटाएँ">✕</button></div>' + ruleHtml(Q, d) + '</div>';
    });
    if (avail.length) h += '<div class="sl-f"><select class="inp" data-sl-sel="d' + i + '" aria-label="ज़िला चुनें"><option value="">➕ ज़िला जोड़ें…</option>' + avail.map(function (d) { return '<option value="' + esc(d) + '">' + esc(tc(d)) + '</option>'; }).join('') + '</select></div>';
    h += '</div>';
  });
  var left = statesList().filter(function (s) { return !M.states.some(function (x) { return x.name === s.s; }); });
  if (left.length) h += '<div class="sl-f" style="margin-top:12px"><select class="inp" data-sl-sel="state" aria-label="राज्य चुनें"><option value="">➕ राज्य जोड़ें…</option>' + left.map(function (s) { return '<option value="' + esc(s.s) + '">' + esc(tc(s.s)) + '</option>'; }).join('') + '</select></div>';
  return h;
}
function mountEditor(host, rows, opt) {
  opt = opt || {};
  var E = { M: opt.M || toModel(rows), multi: !!opt.multi, dirty: false, loaded: true, host: host };
  E.rows = function () { return toRows(E.M); };
  E.render = function () { host.innerHTML = edHtml(E); };
  var touch = function () { E.dirty = true; if (opt.onChange) opt.onChange(E); };
  host.addEventListener('input', function (e) {
    var t = e.target, f = t.getAttribute && t.getAttribute('data-sl-f'); if (!f) return;
    var r = getRule(E.M, t.getAttribute('data-sl-p')); if (!r) return;
    r[f] = f === 'pay' ? t.value : t.value; touch();
  });
  host.addEventListener('change', function (e) {
    var t = e.target, sel = t.getAttribute && t.getAttribute('data-sl-sel');
    if (sel && t.value) {
      if (sel === 'state') { if (!E.M.states.some(function (s) { return s.name === t.value; })) E.M.states.push({ name: t.value, all: rule(), dists: [] }); }
      else { var s = E.M.states[+sel.slice(1)]; if (s && !s.dists.some(function (d) { return d.name === t.value; })) s.dists.push(Object.assign({ name: t.value }, rule())); }
      touch(); E.render(); return;
    }
    if (t.getAttribute && t.getAttribute('data-sl-a') === 'india') { E.M.india = t.checked ? rule() : null; touch(); E.render(); }
  });
  host.addEventListener('click', function (e) {
    var b = e.target.closest('[data-sl-a]'); if (!b || b.tagName === 'INPUT') return;
    var a = b.getAttribute('data-sl-a'), i = +b.getAttribute('data-sl-i'), j = +b.getAttribute('data-sl-j');
    if (a === 'off') { var r = getRule(E.M, b.getAttribute('data-sl-p')); if (r) r.off = !r.off; }
    else if (a === 'state-del') E.M.states.splice(i, 1);
    else if (a === 'dist-del') E.M.states[i].dists.splice(j, 1);
    else if (a === 'mode-all') { if (!E.M.states[i].all) E.M.states[i].all = rule(); }
    else if (a === 'mode-dist') E.M.states[i].all = null;
    else return;
    touch(); E.render();
  });
  E.render(); return E;
}

/* ------------------------------ product form block ------------------------------ */
function ensureCss() { if (!$('#slCss')) { var s = document.createElement('style'); s.id = 'slCss'; s.textContent = CSS; document.head.appendChild(s); } }
function hostHtml() { ensureCss(); return '<div class="sl-box"><h3>🗺️ कहाँ बेचना है</h3><div class="sl-sub">किस जगह यह आइटम बिकेगा, कितने दिन में पहुँचेगा और पेमेंट कैसे होगा। ग्राहक पिन कोड डालते ही यही देखता है।</div><div class="slHost"><span class="spin"></span> लोड हो रहा है…</div></div>'; }
async function loadInfo(force) {
  if (ST.info && !force) return ST.info;
  ST.info = await call('sp_pin_admin_info'); return ST.info;
}
async function mount(body, itemId) {
  var host = $('.slHost', body); if (!host) return;
  try {
    await loadInfo();
    var rows = itemId ? await call('sp_sell_get', { p_item: itemId }) : [];
    var E = mountEditor(host, rows || []); body.__sl = E;
  } catch (e) {
    host.innerHTML = /Could not find|PGRST202|schema cache|does not exist/i.test(e.message || '') ? '<div class="sl-warn">⚠️ यह सुविधा चालू करने के लिए Supabase में नया SQL (<b>ROUND-40-60-SQL-ONLY.sql</b>) एक बार चलाएँ।</div>' : '<div class="sl-warn">' + esc(errMsg(e)) + '</div>';
  }
}
async function saveFor(id, body) {
  var E = body && body.__sl; if (!E || !E.dirty || !id) return;
  try { await call('sp_sell_apply', { p_items: [id], p_rows: E.rows(), p_mode: 'replace' }); E.dirty = false; ST.ov = null; }
  catch (e) { X.toast('जगह सेव नहीं हुई: ' + errMsg(e), true); }
}

/* ------------------------------ emergency ------------------------------ */
async function loadCfg(force) { if (ST.cfg && !force) return ST.cfg; ST.cfg = await call('sp_sell_cfg_get'); return ST.cfg; }
function emgToggle() {
  return loadCfg(true).then(async function (c) {
    var on = !c.emergency;
    var ok = await X.ask(on ? '🚨 <b>EMERGENCY</b>: पूरी वेबसाइट के Shop पेज और Store App पर सारे आइटम “उपलब्ध नहीं” हो जाएँगे।<br><small>ग्राहक को यह सीधे नहीं दिखेगा — पिन कोड / लोकेशन डालने के बाद दिखेगा। कीमत दिखती रहेगी, ऑर्डर नहीं हो पाएगा। कभी भी वापस चालू कर सकते हैं।</small>' : 'Emergency बंद करें? जो जगह / आइटम पहले से चालू थे वे वापस सामान्य हो जाएँगे।', on ? 'हाँ, सब बंद करो' : 'हाँ, वापस चालू', on);
    if (!ok) return null;
    ST.cfg = await call('sp_sell_cfg_set', { p: { emergency: on } });
    X.toast(on ? '🚨 Emergency चालू — सब आइटम Out of Stock' : '✅ Emergency बंद — सामान्य चालू'); return ST.cfg;
  });
}
function emgBar() { ensureCss(); return '<span class="slEmg" style="display:inline-flex"></span>'; }
function emgBind(root) {
  var s = $('.slEmg', root); if (!s) return;
  function paint() {
    var c = ST.cfg || {}; s.innerHTML = '<button type="button" class="btn ' + (c.emergency ? 'red' : 'out') + '" style="' + (c.emergency ? '' : 'border-color:#9a3b2e;color:#9a3b2e;') + '">' + (c.emergency ? '🚨 Emergency चालू है — वापस चालू करें' : '🚨 Emergency: सब Out of Stock') + '</button>';
    $('button', s).onclick = async function () { try { var r = await emgToggle(); if (r) { paint(); if (X.render) X.render(); } } catch (e) { X.toast(errMsg(e), true); } };
  }
  paint(); loadCfg().then(paint, function () { s.innerHTML = ''; });
}

/* ------------------------------ overview chips (product list) ------------------------------ */
async function loadOv(force) { if (ST.ov && !force) return ST.ov; try { var r = await call('sp_sell_overview'); ST.ov = {}; (r || []).forEach(function (x) { ST.ov[x.item_id] = x; }); } catch (e) { ST.ov = {}; } return ST.ov; }
function chip(id) {
  if (!ST.ov) return '';
  var o = ST.ov[id];
  if (!o) return '<span class="tag o" title="जगह नहीं चुनी — अभी सब जगह चल रहा है">🗺️ जगह नहीं चुनी</span>';
  var t = [];
  if (o.all) t.push(o.all_off ? '🇮🇳 बंद' : '🇮🇳 भारत'); if (o.states) t.push(o.states + ' राज्य'); if (o.dists) t.push(o.dists + ' ज़िले'); if (o.off) t.push('⛔ ' + o.off + ' बंद');
  return '<span class="tag b" title="कहाँ बेचना है">🗺️ ' + esc(t.join(' • ')) + '</span>';
}

/* ------------------------------ tab: कहाँ बेचना है ------------------------------ */
async function boot() {
  if (ST.loading) return; ST.loading = true; ST.err = '';
  try { await Promise.all([loadInfo(true), loadCfg(true), loadOv(true)]); }
  catch (e) { ST.err = /Could not find|PGRST202|schema cache|does not exist/i.test(e.message || '') ? 'missing' : errMsg(e); }
  ST.loading = false; X.render();
}
function html() {
  ensureCss();
  if (!ST.info && !ST.err) { boot(); return '<div class="empty"><span class="spin"></span> लोड हो रहा है…</div>'; }
  if (ST.err === 'missing') return '<div class="note r">⚠️ यह सुविधा चालू करने के लिए Supabase → SQL Editor में <b>ROUND-40-60-SQL-ONLY.sql</b> एक बार चलाएँ।</div>';
  if (ST.err) return '<div class="note r">⚠️ ' + esc(ST.err) + '</div><button class="btn" data-sl="retry">🔄 दोबारा कोशिश</button>';
  var c = ST.cfg || {}, h = '<div class="sl-emg' + (c.emergency ? ' on' : '') + '"><div class="sl-h"><span style="font-size:18px">🚨 Emergency</span><span class="sp"></span><button class="btn ' + (c.emergency ? '' : 'red') + '" data-sl="emg">' + (c.emergency ? 'वापस चालू करें' : 'सब Out of Stock करें') + '</button></div>' +
    '<small>' + (c.emergency ? '<b>चालू है:</b> Shop पेज और Store App पर हर आइटम अभी Out of Stock है (पिन / लोकेशन डालने के बाद ग्राहक को दिखता है; कीमत दिखती है, ऑर्डर नहीं होता)।' : 'ऐसे हालात के लिए (जैसे स्टॉक/गोडाउन की दिक्कत): एक क्लिक में पूरा Shop पेज + Store App बंद। ग्राहक को पहले से नहीं दिखता, पिन / लोकेशन डालने पर दिखता है।') + '</small>' +
    '<div class="sl-f"><input class="inp" id="slNote" maxlength="200" placeholder="ग्राहक को छोटा संदेश (वैकल्पिक), जैसे: स्टॉक अपडेट चल रहा है" value="' + esc(c.note || '') + '" style="flex:1;min-width:200px"><button class="btn out sm" data-sl="note">संदेश सेव</button></div></div>';
  h += '<div class="sl-card" style="margin:0 0 12px"><label style="display:flex;gap:8px;align-items:flex-start;cursor:pointer"><input type="checkbox" data-sl="chosen" ' + (c.only_chosen ? 'checked' : '') + '> <span><b>जिस आइटम की कोई जगह नहीं चुनी वह कहीं नहीं बिकेगा</b><br><small>बंद रखें तो बिना जगह वाले आइटम अभी की तरह सब जगह चलते हैं। चालू करें तो नया आइटम तभी बिकेगा जब आप जगह चुनें।</small></span></label></div>';
  h += '<div class="bar"><button class="tab' + (ST.tab === 'bulk' ? ' on' : '') + '" data-sl="tab" data-t="bulk">📦 कई आइटम एक साथ</button><button class="tab' + (ST.tab === 'place' ? ' on' : '') + '" data-sl="tab" data-t="place">📍 जगह-वार</button><button class="tab' + (ST.tab === 'list' ? ' on' : '') + '" data-sl="tab" data-t="list">📋 सारे आइटम</button></div>';
  return h + (ST.tab === 'place' ? placeHtml() : ST.tab === 'list' ? listHtml() : bulkHtml());
}
function filtered() { var q = ST.q.toLowerCase(); return prods().filter(function (p) { return !q || (p.title + ' ' + (p.titleEn || '') + ' ' + (p.sku || '')).toLowerCase().indexOf(q) >= 0; }); }
function bulkHtml() {
  var all = prods(), list = filtered(), n = Object.keys(ST.sel).filter(function (k) { return ST.sel[k]; }).length;
  return '<div class="card"><h2>📦 कई आइटम एक साथ</h2><div class="sl-sub">आइटम टिक करें → नीचे जगह भरें → “लगाएँ”। 50 आइटम के लिए 50 बार नहीं भरना।</div>' +
    '<div class="bar"><input class="inp grow" id="slQ" placeholder="🔍 आइटम खोजें" value="' + esc(ST.q) + '"><button class="btn out sm" data-sl="selall">दिख रहे सब चुनें</button><button class="btn out sm" data-sl="selnone">कोई नहीं</button><button class="btn out sm" data-sl="selnoplace">जगह-रहित चुनें</button></div>' +
    '<div class="sl-list" role="group" aria-label="आइटम">' + (list.length ? list.slice(0, 400).map(function (p) { return '<label><input type="checkbox" data-sl="pick" data-id="' + esc(p.id) + '" ' + (ST.sel[p.id] ? 'checked' : '') + '> <span style="flex:1;min-width:0">' + esc(p.title || p.id) + '</span>' + chip(p.id) + '</label>'; }).join('') : '<div class="empty">कोई आइटम नहीं मिला</div>') + '</div>' +
    '<div class="sl-sub" style="margin-top:6px">चुने हुए: <b id="slCnt">' + n + '</b> / ' + all.length + '</div>' +
    '<div class="sl-box" style="margin-top:8px"><h3>जगह भरें</h3><div id="slBulkEd"></div></div>' +
    '<div class="sl-f" style="margin-top:10px"><span class="sl-seg"><button type="button" class="' + (ST.mode === 'merge' ? 'on' : '') + '" data-sl="mode" data-m="merge">इन जगहों को जोड़ें / बदलें</button><button type="button" class="' + (ST.mode === 'replace' ? 'on' : '') + '" data-sl="mode" data-m="replace">इनकी बाकी सब जगह हटाकर सिर्फ़ यही</button></span></div>' +
    '<div class="bar" style="margin-top:10px"><button class="btn" data-sl="apply">✅ चुने हुए आइटम पर लगाएँ</button></div></div>';
}
function placeHtml() {
  var sts = statesList(), s = ST.pl.s, ds = s ? distsOf(s) : [];
  var h = '<div class="card"><h2>📍 जगह-वार</h2><div class="sl-sub">कोई राज्य / ज़िला चुनें और देखें वहाँ कौन से आइटम बिक रहे हैं। यहीं से उस जगह के सारे आइटम एक साथ बंद / चालू करें, या हर आइटम का अलग।</div>';
  if (!sts.length) return h + '<div class="sl-warn">पहले 📍 पिनकोड → मास्टर में फ़ाइल अपलोड करें।</div></div>';
  h += '<div class="sl-f"><select class="inp" id="slPs" aria-label="राज्य"><option value="">राज्य चुनें…</option>' + sts.map(function (x) { return '<option value="' + esc(x.s) + '"' + (x.s === s ? ' selected' : '') + '>' + esc(tc(x.s)) + '</option>'; }).join('') + '</select>' +
    '<select class="inp" id="slPd" aria-label="ज़िला"' + (s ? '' : ' disabled') + '><option value="">पूरा राज्य</option>' + ds.map(function (d) { return '<option value="' + esc(d) + '"' + (d === ST.pl.d ? ' selected' : '') + '>' + esc(tc(d)) + '</option>'; }).join('') + '</select></div>';
  if (!s) return h + '</div>';
  var rows = ST.pl.rows, label = ST.pl.d ? tc(ST.pl.d) + ', ' + tc(s) : tc(s);
  if (!rows) return h + '<div class="empty"><span class="spin"></span> लोड हो रहा है…</div></div>';
  h += '<div class="bar" style="margin-top:10px"><button class="btn red sm" data-sl="placeoff">⛔ ' + esc(label) + ': सारे आइटम बंद</button><button class="btn out sm" data-sl="placeon">✅ इस जगह के सब आइटम चालू</button></div>';
  if (!rows.length) return h + '<div class="empty">इस जगह के लिए किसी आइटम में अलग नियम नहीं है (जो आइटम “पूरा भारत” या ऊपर के राज्य के नियम पर हैं वे यहाँ नहीं गिने गए)।</div></div>';
  return h + '<div style="overflow-x:auto"><table class="sl-tbl"><thead><tr><th>आइटम</th><th>डिलीवरी</th><th>पेमेंट</th><th></th></tr></thead><tbody>' + rows.map(function (r) {
    return '<tr><td><b>' + esc(pname(r.item_id)) + '</b></td><td>' + (r.eta_max ? (r.eta_min && r.eta_min !== r.eta_max ? r.eta_min + '–' : '') + r.eta_max + ' दिन' : '—') + '</td><td>' + (r.pay === 'prepaid' ? 'सिर्फ़ पूरा पेमेंट' : 'COD भी') + '</td><td><button type="button" class="sl-sw' + (r.off ? ' off' : '') + '" data-sl="rowoff" data-id="' + esc(r.item_id) + '" data-off="' + (r.off ? 0 : 1) + '">' + (r.off ? '⛔ बंद' : '✅ चालू') + '</button></td></tr>';
  }).join('') + '</tbody></table></div></div>';
}
function listHtml() {
  var list = prods();
  return '<div class="card"><h2>📋 सारे आइटम</h2>' + (list.length ? list.map(function (p) {
    return '<div class="row"><div class="rm"><b>' + esc(p.title || p.id) + '</b><small>' + chip(p.id) + '</small></div><div class="acts"><button class="btn out sm" data-sl="edit" data-id="' + esc(p.id) + '">✏️ जगह बदलें</button></div></div>';
  }).join('') : '<div class="empty">कोई आइटम नहीं</div>') + '</div>';
}
async function loadPlace() {
  var sc = ST.pl.d ? 'district' : 'state', val = ST.pl.d ? ST.pl.s + '|' + ST.pl.d : ST.pl.s;
  ST.pl.rows = null; X.render();
  try { ST.pl.rows = await call('sp_sell_place_list', { p_scope: sc, p_value: val }) || []; } catch (e) { ST.pl.rows = []; X.toast(errMsg(e), true); }
  X.render();
}
function editModal(id) {
  ensureCss();
  X.modal('🗺️ कहाँ बेचना है — ' + esc(pname(id)), '<div class="slHost"><span class="spin"></span> लोड हो रहा है…</div>', [{ l: 'रद्द करें', cls: 'gray' }, { l: '✅ सेव करें', id: 'slSave', fn: async function (md) {
    if (!md.body.__sl) { X.toast('अभी लोड हो रहा है', true); return false; }
    try { await call('sp_sell_apply', { p_items: [id], p_rows: md.body.__sl.rows(), p_mode: 'replace' }); ST.ov = null; await loadOv(true); X.toast('✅ जगह सेव हो गई'); X.render(); }
    catch (e) { X.toast(errMsg(e), true); return false; }
  } }], function (md) { mount(md.body, id); });
}
function bind(m) {
  var host = $('#slBulkEd', m);
  if (host) ST.edObj = mountEditor(host, [], { multi: true, M: ST.edObj && ST.edObj.M });
  var q = $('#slQ', m); if (q) q.addEventListener('input', function () { ST.q = q.value; var pos = q.selectionStart; X.render(); var q2 = $('#slQ'); if (q2) { q2.focus(); try { q2.setSelectionRange(pos, pos); } catch (e) {} } });
  var ps = $('#slPs', m), pd = $('#slPd', m);
  if (ps) ps.onchange = function () { ST.pl.s = ps.value; ST.pl.d = ''; ST.pl.rows = null; if (ps.value) loadPlace(); else X.render(); };
  if (pd) pd.onchange = function () { ST.pl.d = pd.value; loadPlace(); };
  m.addEventListener('change', function (e) {
    var t = e.target;
    if (t.getAttribute && t.getAttribute('data-sl') === 'pick') { ST.sel[t.getAttribute('data-id')] = t.checked; var cb = $('#slCnt', m); if (cb) cb.textContent = Object.keys(ST.sel).filter(function (k) { return ST.sel[k]; }).length; }
    else if (t.getAttribute && t.getAttribute('data-sl') === 'chosen') {
      call('sp_sell_cfg_set', { p: { only_chosen: t.checked } }).then(function (c) { ST.cfg = c; X.toast(t.checked ? '✅ अब बिना जगह वाले आइटम कहीं नहीं बिकेंगे' : '✅ बिना जगह वाले आइटम पहले की तरह सब जगह चलेंगे'); X.render(); }, function (er) { X.toast(errMsg(er), true); t.checked = !t.checked; });
    }
  });
  m.addEventListener('click', async function (e) {
    var b = e.target.closest('[data-sl]'); if (!b || b.tagName === 'INPUT' || b.tagName === 'SELECT') return;
    var k = b.getAttribute('data-sl');
    try {
      if (k === 'retry') { ST.err = ''; ST.info = null; X.render(); }
      else if (k === 'emg') { var r = await emgToggle(); if (r) X.render(); }
      else if (k === 'note') { ST.cfg = await call('sp_sell_cfg_set', { p: { note: $('#slNote', m).value } }); X.toast('✅ संदेश सेव हो गया'); }
      else if (k === 'tab') { ST.tab = b.getAttribute('data-t'); if (ST.tab === 'list') await loadOv(true); X.render(); }
      else if (k === 'selall') { filtered().forEach(function (p) { ST.sel[p.id] = true; }); X.render(); }
      else if (k === 'selnone') { ST.sel = {}; X.render(); }
      else if (k === 'selnoplace') { await loadOv(true); ST.sel = {}; prods().forEach(function (p) { if (!ST.ov[p.id]) ST.sel[p.id] = true; }); X.render(); }
      else if (k === 'mode') { ST.mode = b.getAttribute('data-m'); X.render(); }
      else if (k === 'apply') {
        var ids = Object.keys(ST.sel).filter(function (x) { return ST.sel[x]; }), rows = ST.edObj ? ST.edObj.rows() : [];
        if (!ids.length) return X.toast('पहले आइटम चुनें', true);
        if (!rows.length && ST.mode === 'merge') return X.toast('नीचे कम से कम एक जगह भरें', true);
        if (ST.mode === 'replace' && !rows.length && !(await X.ask('<b>' + ids.length + '</b> आइटम की सारी जगह हटेंगी — वे फिर पहले की तरह सब जगह चलेंगे। ठीक है?', 'हाँ, हटाएँ', true))) return;
        var res = await call('sp_sell_apply', { p_items: ids, p_rows: rows, p_mode: ST.mode });
        ST.ov = null; await loadOv(true); X.toast('✅ ' + res.items + ' आइटम पर ' + res.rows + ' जगह लग गई'); X.render();
      }
      else if (k === 'rowoff') { await call('sp_sell_off', { p_items: [b.getAttribute('data-id')], p_scope: ST.pl.d ? 'district' : 'state', p_value: ST.pl.d ? ST.pl.s + '|' + ST.pl.d : ST.pl.s, p_off: b.getAttribute('data-off') === '1' }); ST.ov = null; await loadPlace(); }
      else if (k === 'placeoff' || k === 'placeon') {
        var off = k === 'placeoff', lbl = ST.pl.d ? tc(ST.pl.d) + ', ' + tc(ST.pl.s) : tc(ST.pl.s), all = prods().map(function (p) { return p.id; });
        if (off && !(await X.ask('<b>' + esc(lbl) + '</b> में <b>सारे ' + all.length + ' आइटम</b> अभी बंद करें? बाकी जगह पर कुछ नहीं बदलेगा।', 'हाँ, बंद करो', true))) return;
        var chunksz = 400; for (var i = 0; i < all.length; i += chunksz) await call('sp_sell_off', { p_items: all.slice(i, i + chunksz), p_scope: ST.pl.d ? 'district' : 'state', p_value: ST.pl.d ? ST.pl.s + '|' + ST.pl.d : ST.pl.s, p_off: off });
        ST.ov = null; X.toast(off ? '⛔ ' + lbl + ': सब बंद' : '✅ ' + lbl + ': सब चालू'); await loadPlace();
      }
      else if (k === 'edit') editModal(b.getAttribute('data-id'));
    } catch (er) { console.error(er); X.toast(errMsg(er), true); }
  });
}
window.SPSELL = {
  init: function (ctx) { X = ctx; ensureCss(); }, html: html, bind: bind, reset: function () { ST.info = null; ST.ov = null; ST.cfg = null; ST.err = ''; ST.loading = false; ST.pl = { s: '', d: '', rows: null }; },
  hostHtml: hostHtml, mount: mount, saveFor: saveFor, emgBar: emgBar, emgBind: emgBind, chip: chip, loadOv: loadOv, edit: editModal,
  _toModel: toModel, _toRows: toRows
};
})();
