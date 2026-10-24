/* Sunpowers Admin — 🧱 पेज बिल्डर (Store page + Shop page)
   Uses the shared engine sp-builder.js (window.SPBLD). All data lives in D.builder inside the normal store JSON.
   Nothing old is touched: builder OFF = the old layout keeps working exactly as before. No keys, no network calls here. */
(function () {
'use strict';
var H = null, PG = 'store', BC = null, DIRTY = false, PT = [], LOCK = false, PVF = '';
var $ = function (s, r) { return (r || document).querySelector(s); };
var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
var clone = function (o) { return JSON.parse(JSON.stringify(o)); };
function D() { return H.D(); }
function cfg() { if (!BC) BC = SPBLD.norm(D().builder); return BC; }
function touch() { D().builder = BC; DIRTY = true; }
function sections() { return D().sections || []; }
function secTitle(id) { var s = sections().filter(function (x) { return x.id === id; })[0]; return s ? s.title : ''; }
function secOpts(blank) { return (blank === false ? [] : [['', blank || '— कोई नहीं —']]).concat(sections().map(function (s) { return [s.id, (s.icon ? s.icon + ' ' : '') + s.title]; })); }
var RULES = [['manual', '✋ हाथ से — नीचे चुने सेक्शन के प्रोडक्ट'], ['discount', '🔥 सबसे ज़्यादा छूट (अपने-आप)'], ['newest', '🆕 सबसे नए (अपने-आप)'], ['all', '📦 सारे प्रोडक्ट (सेक्शन चुनें तो उसी के)']];
var POS = [['bc', 'नीचे-बीच'], ['bl', 'नीचे-बाएँ'], ['br', 'नीचे-दाएँ'], ['cc', 'बीच'], ['cl', 'बीच-बाएँ'], ['cr', 'बीच-दाएँ'], ['tc', 'ऊपर-बीच'], ['tl', 'ऊपर-बाएँ'], ['tr', 'ऊपर-दाएँ'], ['custom', 'अपनी जगह (X% / Y%)']];

/* ---------- small list editor (slides / boxes / buttons) ---------- */
function ListEd(el, arr, o) {
  function paint() {
    el.innerHTML = (arr.length ? arr.map(function (it, i) {
      return '<div class="row' + (it.visible === false ? ' dim' : '') + '"><div class="rm">' + o.row(it, i) + '</div><div class="acts"><button type="button" class="ib" data-up="' + i + '" title="ऊपर">▲</button><button type="button" class="ib" data-dn="' + i + '" title="नीचे">▼</button><button type="button" class="ib" data-ed="' + i + '" title="एडिट">✏️</button><button type="button" class="ib red" data-rm="' + i + '" title="हटाएँ">🗑</button></div></div>';
    }).join('') : '<div class="empty" style="padding:10px">' + esc(o.empty || 'अभी कुछ नहीं') + '</div>') + (arr.length < (o.max || 99) ? '<button type="button" class="btn sm out" data-add>➕ ' + esc(o.addLabel || 'जोड़ें') + '</button>' : '');
  }
  el.onclick = function (e) {
    var b = e.target.closest('button'); if (!b) return; e.preventDefault(); e.stopPropagation();
    var g = function (k) { return b.hasAttribute(k) ? +b.getAttribute(k) : null; }, i;
    if (b.hasAttribute('data-add')) o.edit(null, function (it) { arr.push(it); paint(); if (o.change) o.change(); });
    else if ((i = g('data-ed')) !== null) o.edit(arr[i], function () { paint(); if (o.change) o.change(); });
    else if ((i = g('data-rm')) !== null) { arr.splice(i, 1); paint(); if (o.change) o.change(); }
    else if ((i = g('data-up')) !== null && i > 0) { arr.splice(i - 1, 0, arr.splice(i, 1)[0]); paint(); if (o.change) o.change(); }
    else if ((i = g('data-dn')) !== null && i < arr.length - 1) { arr.splice(i + 1, 0, arr.splice(i, 1)[0]); paint(); if (o.change) o.change(); }
  };
  paint(); return { paint: paint };
}
function subModal(title, fields, obj, ok, extraHtml, onOpen) {
  H.modal(title, H.FA(fields, obj) + (extraHtml || ''), [{ l: 'रद्द करें', cls: 'gray' }, { l: '✅ ठीक है', fn: function (md) { var v = H.readForm(md.body, fields); if (!v) return false; return ok(v, md); } }], function (md) { H.bindForm(md.body); if (onOpen) onOpen(md); });
}

/* ---------- editors for sub-items ---------- */
var BTN_F = [
  { k: 'label', l: 'बटन पर क्या लिखा हो', t: 'text', req: true, max: 30, ph: 'जैसे: अभी ख़रीदें' },
  { k: 'link', l: 'बटन दबाने पर कहाँ जाए', t: 'link' },
  { k: 'pos', l: 'बटन कहाँ दिखे', t: 'select', o: POS, d: 'bc' },
  { k: 'x', l: 'X % (सिर्फ़ "अपनी जगह" में, 0-100)', t: 'number', d: 50, min: 0, max: 100 },
  { k: 'y', l: 'Y % (सिर्फ़ "अपनी जगह" में, 0-100)', t: 'number', d: 90, min: 0, max: 100 },
  { k: 'style', l: 'रंग', t: 'select', o: [['green', '🟢 हरा'], ['light', '⚪ सफ़ेद']], d: 'green' }
];
function btnList(el, arr, max) {
  return ListEd(el, arr, { max: max, addLabel: 'बटन जोड़ें', empty: 'कोई बटन नहीं (बिना बटन भी चलेगा)',
    row: function (b) { return '<b>' + esc(b.label || '(बिना नाम)') + '</b><small>' + esc(b.pos || 'bc') + ' • ' + esc(b.linkType || 'none') + '</small>'; },
    edit: function (it, done) { var n = it || { pos: 'bc', style: 'green' }; subModal(it ? '✏️ बटन' : '➕ बटन', BTN_F, n, function (v) { if (v.linkType === 'none') { H.toast('बटन का लिंक चुनें', true); return false; } Object.assign(n, v); done(n); }); } });
}
var SLIDE_F = [
  { k: 'title', l: 'हेडिंग', t: 'text', max: 60 }, { k: 'sub', l: 'छोटी लाइन', t: 'text', max: 100 },
  { k: 'image', l: 'स्लाइड की फ़ोटो (चौड़ी, साफ़)', t: 'image' }, { k: 'bg', l: 'बैकग्राउंड रंग (फ़ोटो न हो तो)', t: 'color', d: '#1b5e20' },
  { k: 'emoji', l: 'Emoji (फ़ोटो न हो तो)', t: 'text', max: 6, adv: true }, { k: 'link', l: 'पूरी स्लाइड दबाने पर (वैकल्पिक)', t: 'link', adv: true },
  { k: 'visible', l: 'दिखाएँ', t: 'check', d: true }
];
function slideEdit(it, done) {
  var n = it || { btns: [], visible: true }, w = clone(n); if (!Array.isArray(w.btns)) w.btns = [];
  subModal(it ? '✏️ स्लाइड' : '➕ स्लाइड', SLIDE_F, n, function (v) { Object.assign(n, v, { btns: w.btns }); if (!n.id) n.id = 'sl' + Math.random().toString(36).slice(2, 7); done(n); },
    '<div class="fld full"><label class="l">🔘 इस स्लाइड पर बटन (अधिकतम 3)</label><div data-bl></div></div>', function (md) { btnList($('[data-bl]', md.body), w.btns, 3); });
}
var BOX_F = [
  { k: 'name', l: 'नाम (हिंदी/मुख्य)', t: 'text', req: true, max: 30, ph: 'जैसे: सोलर पैनल' }, { k: 'nameEn', l: 'English नाम', t: 'text', max: 30, adv: true },
  { k: 'image', l: 'फ़ोटो (चौकोर अच्छी)', t: 'image' }, { k: 'emoji', l: 'Emoji (फ़ोटो न हो तो)', t: 'text', max: 6, d: '☀️' }, { k: 'bg', l: 'रंग', t: 'color', d: '#eaf4ec', adv: true },
  { k: 'sec', l: 'दबाने पर कौन-सा सेक्शन खुले? (प्रोडक्ट इसी सेक्शन में रखे जाते हैं)', t: 'select', o: null },
  { k: 'link', l: 'या कोई और लिंक (सेक्शन न चुना हो तभी)', t: 'link', adv: true }, { k: 'visible', l: 'दिखाएँ', t: 'check', d: true }
];
function boxEdit(c) {
  return function (it, done) {
    var n = it || { visible: true, emoji: '☀️', bg: '#eaf4ec' }, f = BOX_F.map(function (x) { return x.k === 'sec' ? Object.assign({}, x, { o: [['', '— कोई सेक्शन नहीं —'], ['__new', '✨ इसी नाम का नया सेक्शन अपने-आप बनाएँ']].concat(secOpts(false)) }) : x; });
    subModal(it ? '✏️ Raw Category बॉक्स' : '➕ Raw Category बॉक्स', f, n, function (v) {
      if (v.sec === '__new') { var s = Object.assign(clone(SP.SECTION_DEF), { id: SP.uid('sec'), title: v.name, titleEn: v.nameEn || '', icon: v.emoji || '', kind: 'category', limit: 8, visible: true, via: 'box' }); D().sections.push(s); v.sec = s.id; H.toast('✨ सेक्शन "' + s.title + '" बन गया'); }
      Object.assign(n, v); if (!n.id) n.id = SPBLD.nextBox(c); done(n);
    });
  };
}
/* ---------- component settings ---------- */
function fieldsFor(c) {
  var t = c.type, nm = [{ k: 'name', l: 'सेक्शन का नाम (हिंदी/मुख्य)', t: 'text', max: 60 }, { k: 'nameEn', l: 'English नाम', t: 'text', max: 60 }];
  if (t === 'search_bar') return [{ k: 'ph', l: 'सर्च बॉक्स में हल्का लिखा टेक्स्ट', t: 'text', max: 50, ph: 'Search solar panel, inverter…' }];
  if (t === 'slideshow_banner') return nm.slice(0, 0).concat([{ k: 'height', l: 'ऊँचाई (px)', t: 'number', d: 190, min: 100, max: 600 }, { k: 'interval', l: 'कितने सेकंड में बदले', t: 'number', d: 4, min: 1, max: 60 }, { k: 'autoplay', l: 'अपने-आप चले', t: 'check', d: true }]);
  if (t === 'raw_category') return nm.concat([{ k: 'cols', l: 'एक लाइन में कितने बॉक्स', t: 'select', o: [[2, '2'], [3, '3'], [4, '4']], d: 3 }]);
  if ((T(t).def && T(t).def.rule !== undefined) || t === 'product_row') return nm.concat([{ k: 'rule', l: 'कौन-से प्रोडक्ट दिखें', t: 'select', o: RULES, d: 'manual' }, { k: 'sec', l: 'सेक्शन', t: 'select', o: secOpts() }, { k: 'limit', l: 'अधिकतम कितने प्रोडक्ट', t: 'number', d: 8, min: 1, max: 40 }, { k: 'layout', l: 'दिखावट', t: 'select', o: [['scroll', '↔️ साइड में स्क्रोल'], ['grid', '▦ ग्रिड (कॉलम नीचे चुनें)']], d: 'scroll' }, { k: 'cols', l: 'ग्रिड में एक लाइन में कितने कार्ड (मोबाइल पर अपने-आप 2)', t: 'select', o: [[0, 'अपने-आप'], [2, '2'], [3, '3'], [4, '4']], d: 0 }, { k: 'b_buy', l: 'हर कार्ड पर "अभी ख़रीदें" बटन (कार्ट का + हमेशा रहता है)', t: 'check', d: true }, { k: 'b_view', l: 'हर कार्ड पर "देखें" बटन', t: 'check', d: false }, { k: 'b_wa', l: 'हर कार्ड पर WhatsApp बटन', t: 'check', d: false }]);
  if (t === 'video_section') return nm.concat([{ k: 'url', l: 'वीडियो का लिंक (YouTube या .mp4)', t: 'text', ph: 'https://youtu.be/…', h: 'YouTube लिंक डालें — वीडियो अपने सर्वर पर सेव नहीं होता।' }, { k: 'poster', l: 'कवर फ़ोटो (वैकल्पिक)', t: 'image', adv: true }]);
  if (t === 'youtube_section') return nm.concat([{ k: 'channel', l: 'आपके YouTube चैनल का लिंक', t: 'text', ph: 'https://www.youtube.com/@sunpowers' }, { k: 'vids', l: 'वीडियो के लिंक — हर लाइन में एक। नाम चाहें तो लिंक के बाद | लगाकर लिखें', t: 'lines', rows: 6, ph: 'https://youtu.be/XXXXXXXXXXX | सोलर कैसे लगता है', h: 'चैनल से अपने-आप वीडियो खींचने के लिए सर्वर/Key चाहिए, इसलिए अभी लिंक खुद डालें।' }]);
  if (t === 'delivery_bar') return [{ k: 'text', l: 'डिलीवरी की लाइन', t: 'text', max: 120, ph: 'लखनऊ व UP में होम डिलीवरी' }, { k: 'pin', l: 'पिनकोड चेक का बटन भी दिखाएँ', t: 'check', d: true }];
  if (t === 'offer_strip') return [{ k: 'text', l: 'ऑफ़र की लाइन', t: 'text', max: 120 }, { k: 'link', l: 'दबाने पर', t: 'link' }, { k: 'bg', l: 'पीछे का रंग', t: 'color', d: '#1b5e20' }, { k: 'fg', l: 'अक्षर का रंग', t: 'color', d: '#ffffff' }, { k: 'ticker', l: 'चलती हुई पट्टी', t: 'check', d: true }];
  if (t === 'custom_section') return nm.concat([{ k: 'title', l: 'हेडिंग', t: 'text', max: 60 }, { k: 'text', l: 'टेक्स्ट (हर लाइन अलग पैराग्राफ़)', t: 'textarea', rows: 4 }, { k: 'img', l: 'फ़ोटो', t: 'image' }, { k: 'btn', l: 'बटन का नाम', t: 'text', max: 30 }, { k: 'link', l: 'बटन का लिंक', t: 'link' }, { k: 'bg', l: 'रंग', t: 'color', d: '#f1f7f2' }]);
  return nm;
}
function T(t) { return SPBLD.TYPES[t] || {}; }
/* the same, for one component: Shop-page parts say "Shop पेज का हिस्सा" */
function TC(c) { var t = T(c.type); return c.type === 'store_block' && /^shop_/.test((c.cfg || {}).kind || '') ? Object.assign({}, t, { label: 'Shop पेज का हिस्सा', icon: '🛍️' }) : t; }
function settings(id) {
  var c = cfg().comps[id]; if (!c) return;
  if (c.lock) return H.toast('🔒 ये लॉक है — पहले 🔓 खोलें', true);
  PVF = id; paintPreview();
  var f = fieldsFor(c), flat = Object.assign({ name: c.name, nameEn: c.nameEn }, clone(c.cfg), { b_buy: (c.cfg.btns || []).indexOf('buy') >= 0, b_view: (c.cfg.btns || []).indexOf('view') >= 0, b_wa: (c.cfg.btns || []).indexOf('wa') >= 0 }), extra = '', onOpen = null, w = clone(c);
  f = f.concat([{ k: '_pages', l: 'किस builder की लिस्ट में रहे (छुपाना 📍 बटन से, हर जगह अलग)', t: 'select', o: [['both', 'Store + Shop दोनों की लिस्ट में'], ['store', 'सिर्फ़ Store पेज'], ['shop', 'सिर्फ़ Shop पेज']], d: c.pages.store && c.pages.shop ? 'both' : (c.pages.store ? 'store' : 'shop') }]);
  if (c.type === 'store_block') { f = f.filter(function (x) { return x.k !== '_pages'; }); var K = { services: '🛠️ सर्विसेज़', chips: 'अपने-आप (सेक्शन की कैटेगरी)', form: '📝 फ़ॉर्म व गाइड', howto: '📝 फ़ॉर्म व गाइड', feedback: '⭐ फ़ीडबैक', videos: '🖼️ App मीडिया', shop_services: '🛠️ सर्विसेज़ (Store मेन्यू से)', shop_howto: '📝 ऑर्डर कैसे करें (Store मेन्यू से)', shop_feedback: '⭐ फ़ीडबैक (Store मेन्यू से)', shop_videos: '▶️ वीडियो (Store मेन्यू से)', shop_bp: 'Project Blueprint कार्ड', shop_dt: 'Solar Error Detector कार्ड', shop_bar: 'अपने-आप', shop_chips: 'अपने-आप (सेक्शन की कैटेगरी)', shop_grid: 'अपने-आप (प्रोडक्ट्स)' }; extra = /^shop_/.test(c.cfg.kind) ? '<div class="note">🛍️ ये Shop पेज का मौजूदा हिस्सा है — प्रोडक्ट और सेक्शन <b>अपने-आप</b> आते हैं (मेन्यू: प्रोडक्ट्स / सेक्शन)। यहाँ से नाम, क्रम और 👁 छुपाना/दिखाना होता है।</div>' : '<div class="note">📱 ये Store App का पुराना हिस्सा है। इसकी <b>सामग्री</b> मेन्यू <b>' + esc(K[c.cfg.kind] || '') + '</b> से बदलती है; यहाँ से नाम, क्रम और 👁 छुपाना/दिखाना होता है।</div>'; }
  if (c.type === 'slideshow_banner') { extra = '<div class="fld full"><label class="l">🖼️ स्लाइड्स</label><div data-sl></div></div>'; onOpen = function (md) { ListEd($('[data-sl]', md.body), w.cfg.slides, { addLabel: 'स्लाइड जोड़ें', empty: 'कोई स्लाइड नहीं', edit: slideEdit, max: 12, row: function (s) { return '<b>' + esc(s.title || '(बिना हेडिंग)') + '</b><small>' + (SP.isImg(s.image) ? '🖼️ फ़ोटो' : 'रंग') + ' • 🔘 ' + (s.btns || []).length + ' बटन</small>'; } }); }; }
  if (c.type === 'raw_category') { extra = '<div class="fld full"><label class="l">🧩 बॉक्स (हर बॉक्स = एक सेक्शन/कैटेगरी)</label><div data-bx></div></div>'; onOpen = function (md) { ListEd($('[data-bx]', md.body), w.cfg.boxes, { addLabel: 'Add Box', empty: 'कोई बॉक्स नहीं', edit: boxEdit(w), max: 24, row: function (b) { return '<b>' + esc((b.emoji || '') + ' ' + b.name) + '</b><small>' + esc(b.id || 'नया') + ' • ' + (b.sec ? '🗂️ ' + esc(secTitle(b.sec)) : 'लिंक') + '</small>'; } }); }; }
  if (c.type === 'video_section') { extra = '<div class="fld full"><label class="l">🔘 वीडियो पर बटन (अधिकतम 2)</label><div data-bl></div></div>'; onOpen = function (md) { btnList($('[data-bl]', md.body), w.cfg.btns, 2); }; }
  H.modal((TC(c).icon || '') + ' ' + TC(c).label + ' — सेटिंग्स  (' + c.id + ')', H.FA(f, flat) + extra, [{ l: 'रद्द करें', cls: 'gray' }, { l: '💾 ठीक है', fn: function (md) {
    var v = H.readForm(md.body, f); if (!v) return false;
    var pages = v._pages; delete v._pages; if (v.b_buy !== undefined) { v.btns = ['buy', 'view', 'wa'].filter(function (k) { return v['b_' + k]; }); c.cfg.btns = v.btns; } delete v.b_buy; delete v.b_view; delete v.b_wa; if (c.type === 'raw_category' || c.type === 'slideshow_banner' || c.type === 'video_section') { v.slides = w.cfg.slides; v.boxes = w.cfg.boxes; v.btns = w.cfg.btns; v.bctr = w.cfg.bctr; }
    if (v.name !== undefined) c.name = v.name || T(c.type).name; if (v.nameEn !== undefined) c.nameEn = v.nameEn; delete v.name; delete v.nameEn;
    Object.keys(v).forEach(function (k) { if (v[k] === undefined || (k === 'slides' && c.type !== 'slideshow_banner') || (k === 'boxes' && c.type !== 'raw_category') || (k === 'btns' && c.type !== 'video_section') || (k === 'bctr' && c.type !== 'raw_category')) return; c.cfg[k] = v[k]; });
    if (c.type === 'raw_category') c.cfg.bctr = Math.max(c.cfg.bctr || 0, w.cfg.bctr || 0);
    c.pages = c.type === 'store_block' ? { store: !/^shop_/.test(c.cfg.kind), shop: /^shop_/.test(c.cfg.kind) } : { store: pages !== 'shop', shop: pages !== 'store' };
    BC = SPBLD.norm(BC); touch(); refresh(); H.toast('✅ बदलाव हुआ — ऊपर "💾 सेव" दबाएँ');
  } }], function (md) { H.bindForm(md.body); if (onOpen) onOpen(md); });
}

/* ---------- actions ---------- */
function move(id, d) {
  var o = cfg().order[PG], i = o.indexOf(id), j = i + d; if (i < 0 || j < 0 || j >= o.length) return;
  if (cfg().comps[id].lock) return H.toast('🔒 लॉक है', true);
  o.splice(j, 0, o.splice(i, 1)[0]); touch(); refresh();
}
function dropTo(id, before) {
  var o = cfg().order[PG], i = o.indexOf(id), j = o.indexOf(before); if (i < 0 || j < 0 || i === j) return;
  if (cfg().comps[id].lock) return H.toast('🔒 लॉक है', true);
  o.splice(i, 1); o.splice(o.indexOf(before), 0, id); touch(); refresh();
}
function addComp(type) {
  var c = SPBLD.add(cfg(), type); if (!c) return H.toast('ये सेक्शन पहले से जुड़ा है', true);
  cfg().order.store = cfg().order.store.filter(function (x) { return x !== c.id; }); cfg().order.shop = cfg().order.shop.filter(function (x) { return x !== c.id; });
  cfg().order[PG].push(c.id); c.pages = { store: PG === 'store', shop: PG === 'shop' };
  PVF = c.id; touch(); refresh(); H.toast('➕ ' + c.name + ' जुड़ गया (' + c.id + ')');
}
function dupComp(id) {
  var c = SPBLD.dup(cfg(), id); if (!c) return H.toast('ये हिस्सा सिर्फ़ एक बार ही रह सकता है — कॉपी नहीं बनती', true); PVF = c.id; touch(); refresh(); H.toast('⧉ कॉपी बन गई: ' + c.name + ' (' + c.id + ') — ⚙️ से अपने हिसाब से बदलें और 💾 सेव करें');
}
function rename(id) {
  var c = cfg().comps[id]; if (!c) return; if (c.lock) return H.toast('🔒 ये लॉक है', true);
  var f = [{ k: 'name', l: 'नया नाम (हिंदी/मुख्य)', t: 'text', req: true, max: 60 }, { k: 'nameEn', l: 'English नाम', t: 'text', max: 60 }];
  H.modal('✏️ नाम बदलें  (' + c.id + ')', H.F(f, c) + '<div class="note g">अंदरूनी नाम <b>' + esc(c.id) + '</b> कभी नहीं बदलता — सिर्फ़ ग्राहक को दिखने वाला नाम बदलता है।</div>', [{ l: 'रद्द करें', cls: 'gray' }, { l: 'ठीक है', fn: function (md) { var v = H.readForm(md.body, f); if (!v) return false; c.name = v.name; c.nameEn = v.nameEn; touch(); refresh(); } }], function (md) { H.bindForm(md.body); });
}
async function del(id) {
  var c = cfg().comps[id]; if (!c) return; if (c.lock) return H.toast('🔒 लॉक है — पहले 🔓 खोलें', true);
  if (!(await H.ask('"<b>' + esc(c.name) + '</b>" (' + esc(c.id) + ') हटाएँ?<br><small>बाद में दोबारा जोड़ने पर इसका नया नंबर बनेगा; पुराना नाम दोबारा नहीं आता।</small>', 'हाँ, हटाएँ', true))) return;
  SPBLD.remove(cfg(), id); touch(); refresh();
}

/* ---------- preview ---------- */
function pcard(p) {
  var pr = SP.price ? SP.price(p) : (p.offer || p.mrp), d = SP.discount ? SP.discount(p) : 0;
  return '<div class="apc"><div class="pi" style="background:' + esc(p.bg || '#e8f5e9') + '">' + (SP.isImg(p.image) ? '<img src="' + esc(p.image) + '" alt="" loading="lazy" onerror="this.remove()">' : '<em>' + esc(p.emoji || '☀️') + '</em>') + (d ? '<i>' + d + '%</i>' : '') + '</div><b>' + esc(p.title) + '</b><span>' + (SP.money ? SP.money(pr) : '₹' + pr) + (d ? ' <s>' + (SP.money ? SP.money(p.mrp) : p.mrp) + '</s>' : '') + '</span></div>';
}
function pctx() {
  var S = Object.assign({}, D(), { products: (D().products || []).map(function (p) { return p.demo ? Object.assign({}, p, { visible: true }) : p; }) });
  return { S: S, admin: true, lang: function () { return 'hi'; }, t: function () { return 'Search products…'; }, card: pcard, pinChip: function () { return '<span class="apin">📍 पिनकोड</span>'; }, timer: function (t) { PT.push(t); }, link: function () {} };
}
function paintPreview() {
  var h = $('#bldPrv'); if (!h) return;
  PT.forEach(clearInterval); PT = [];
  var c = cfg(), all = SPBLD.list(c, PG, true);
  if (PVF && !c.comps[PVF]) PVF = '';
  var view = c, one = PVF ? c.comps[PVF] : null;
  if (one) { view = { on: c.on, comps: c.comps, order: { store: [], shop: [] } }; view.order[PG] = [PVF]; }
  var inner = SPBLD.render(view, PG, pctx());
  var bar = $('#bPvBar');
  if (bar) bar.innerHTML = one ? '<b>🔎 सिर्फ़: ' + esc((T(one.type).icon || '') + ' ' + one.name) + '</b> <button type="button" class="btn sm out" data-pvall>📄 पूरा पेज देखें</button>' : '<span style="color:var(--mut)">पूरे पेज का लेआउट — किसी सेक्शन में ⚙️ दबाएँ या नया जोड़ें तो प्रीव्यू सिर्फ़ वही सेक्शन दिखाएगा</span>';
  h.innerHTML = inner || (all.length ? '<div class="empty">इस सेक्शन में अभी दिखाने लायक कुछ नहीं — ⚙️ से टेक्स्ट / फ़ोटो / प्रोडक्ट भरें</div>' : '<div class="empty">अभी कोई सेक्शन नहीं — बाईं तरफ़ से जोड़ें</div>');
  SPBLD.mount(h, pctx());
}

/* ---------- copy one page's layout onto the other page (real data, independent copies) ---------- */
function otherPg(pg) { return pg === 'shop' ? 'store' : 'shop'; }
/* Web Shop Page Builder: opens with the parts the live Shop page shows today (search + pincode, category chips, all products); no copy of the Store page. */
var SEEDED = false, SEEDNOTE = false;
function autoSeed() {
  if (PG === 'store') {   /* Store page: every block customers see today comes into the builder once (hidden ones stay hidden) */
    var c0 = cfg(); if (c0.sv) return;
    /* already built by hand (real content sections exist) = leave it alone; only a lone Search / Delivery / Offer / Custom row does not count */
    if (SPBLD.list(c0, 'store', true).some(function (x) { return ['search_bar', 'delivery_bar', 'offer_strip', 'custom_section'].indexOf(x.type) < 0; })) return;
    if (SPBLD.seedStore(c0, D())) { touch(); SEEDED = true; SEEDNOTE = true; }
    return;
  }
  if (PG !== 'shop' || !LOCK) return;
  var c1 = cfg(); if (c1.ssv >= 2) return;
  if (SPBLD.seedShop(c1, D())) { touch(); SEEDED = true; SEEDNOTE = true; }
}

/* ---------- Round 22: 📍 where is this section shown (per place show/hide, website pages, copy) ---------- */
var WEB_NO = { 'shop.html': 1, 'privacy.html': 1, 'terms.html': 1, 'refund-policy.html': 1, 'shipping-policy.html': 1 };
function webPages() { var S = window.CMS_SECS || {}; var a = Object.keys(S).filter(function (f) { return !WEB_NO[f]; }).map(function (f) { return [f, S[f].title || f]; }); a.sort(function (x, y) { return x[0] === 'index.html' ? -1 : y[0] === 'index.html' ? 1 : 0; }); return a; }
function webSecs(file) { var S = (window.CMS_SECS || {})[file]; return (S && S.secs || []).map(function (x) { return [x.id, String(x.label || x.id).slice(0, 48)]; }); }
function secName(file, ref) { var f = webSecs(file).filter(function (x) { return x[0] === ref; })[0]; return f ? f[1] : ref; }
function posText(w) { return w.pos === 'top' ? 'पेज के सबसे ऊपर' : w.pos === 'end' ? 'पेज के सबसे नीचे' : '“' + secName(w.file, w.ref) + '” के ' + (w.pos === 'above' ? 'ऊपर' : 'नीचे'); }
function webBadge(c) { var n = SPBLD.webOf(cfg(), c.id).length; return n ? ' • 🌐 वेबसाइट ' + n + ' पेज पर' : ''; }
function placeBody(id) {
  var c = cfg().comps[id], t = TC(c), web = SPBLD.webOf(cfg(), id), fromStore = c.pages.store && !c.pages.shop, can = SPBLD.canWeb(c.type);
  function row(ic, nm, on, attr, sub) { return '<div class="row' + (on ? '' : ' dim') + '"><div class="th">' + ic + '</div><div class="rm"><b>' + nm + '</b>' + (sub ? '<small>' + sub + '</small>' : '') + '</div><div class="acts"><button class="btn sm ' + (on ? '' : 'gray') + '" ' + attr + '>' + (on ? '👁 दिख रहा — छुपाएँ' : '🚫 छुपा — दिखाएँ') + '</button></div></div>'; }
  var h = '<div class="card" style="margin:0 0 10px"><b>जहाँ अभी लगा है</b><small style="display:block;color:var(--mut);margin:2px 0 6px">हर जगह का Show/Hide अलग है — एक जगह छुपाने से बाकी जगह पर कुछ नहीं बदलता।</small>' +
    (c.pages.store ? row('📱', 'Store App पेज', SPBLD.vis(c, 'store'), 'data-pv="store"') : '') + (c.pages.shop ? row('🛍️', 'Web Shop पेज', SPBLD.vis(c, 'shop'), 'data-pv="shop"') : '') +
    web.map(function (w, i) { return row('🌐', esc(w.file) + ' — ' + esc(((window.CMS_SECS || {})[w.file] || {}).title || ''), w.show !== false, 'data-wv="' + i + '"', esc(posText(w)) + (fromStore ? ' • ऐप-डाउनलोड वाली झलक' : '')) .replace('</div></div>', '<button class="ib red" data-wd="' + i + '" title="इस पेज से हटाएँ">🗑</button></div></div>'); }).join('') + '</div>';
  if (!can) return h + '<div class="note r">ℹ️ ' + esc(t.label) + ' सिर्फ़ Shop पेज / Store App में चल सकता है — वेबसाइट के बाकी पेज पर नहीं।</div>';
  var pg = webPages();
  h += '<div class="card" style="margin:0 0 10px"><b>➕ वेबसाइट के किसी पेज पर लगाएँ</b>' + (fromStore ? '<div class="note" style="margin:6px 0">📱 ये Store App का सेक्शन है — वेबसाइट पर इसके प्रोडक्ट/सेक्शन <b>नहीं</b> दिखते — सिर्फ़ एक <b>“Sunpowers App · जल्द आ रहा है”</b> कार्ड दिखेगा (हर पेज पर एक ही)। Play Store / App Store की लिंक जुड़ते ही उसी कार्ड पर “Download” बटन आ जाएगा। प्रोडक्ट दिखाने हों तो Web Shop Page Builder का सेक्शन लगाएँ।</div>' : '') +
    '<div class="fg"><div class="fld"><label class="l">कौन-सा पेज</label><select class="inp" id="plPg">' + pg.map(function (x) { return '<option value="' + esc(x[0]) + '">' + esc(x[0] === 'index.html' ? '🏠 Home Page (index.html)' : x[0] + ' — ' + x[1]) + '</option>'; }).join('') + '</select></div>' +
    '<div class="fld"><label class="l">कहाँ</label><select class="inp" id="plMode"><option value="below">किसी सेक्शन के नीचे</option><option value="above">किसी सेक्शन के ऊपर</option><option value="top">पेज के सबसे ऊपर</option><option value="end">पेज के सबसे नीचे</option></select></div>' +
    '<div class="fld full" id="plRefW"><label class="l">कौन-से सेक्शन के पास</label><select class="inp" id="plRef"></select></div></div><button class="btn" id="plAdd">➕ लगाएँ</button></div>';
  return h;
}
function placeModal(id) {
  var c = cfg().comps[id]; if (!c) return;
  H.modal('📍 ' + (TC(c).icon || '') + ' ' + c.name + ' — कहाँ-कहाँ दिखे  (' + c.id + ')', '<div id="plBox"></div>', [{ l: '✅ ठीक है', cls: '' }], function (md) {
    var box = $('#plBox', md.body);
    function fillRef() { var f = $('#plPg', box), m = $('#plMode', box); if (!f) return; var r = $('#plRef', box), need = m.value === 'above' || m.value === 'below'; $('#plRefW', box).style.display = need ? '' : 'none'; r.innerHTML = webSecs(f.value).map(function (x) { return '<option value="' + esc(x[0]) + '">' + esc(x[1]) + '</option>'; }).join(''); }
    function paint() { box.innerHTML = placeBody(id); fillRef(); }
    paint();
    box.addEventListener('change', function (e) { if (e.target.id === 'plPg' || e.target.id === 'plMode') fillRef(); });
    box.addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return; e.preventDefault();
      if (b.hasAttribute('data-pv')) { var pgk = b.getAttribute('data-pv'); c.hide = c.hide || { store: false, shop: false }; c.hide[pgk] = !c.hide[pgk]; touch(); refresh(); paint(); }
      else if (b.hasAttribute('data-wv')) { var w = SPBLD.webOf(cfg(), id)[+b.getAttribute('data-wv')]; if (w) { var x = cfg().web[w.file].filter(function (y) { return y.id === id; })[0]; x.show = x.show === false; touch(); refresh(); paint(); } }
      else if (b.hasAttribute('data-wd')) { var w2 = SPBLD.webOf(cfg(), id)[+b.getAttribute('data-wd')]; if (w2) { SPBLD.webDel(cfg(), id, w2.file); touch(); refresh(); paint(); } }
      else if (b.id === 'plAdd') {
        var file = $('#plPg', box).value, mode = $('#plMode', box).value, ref = $('#plRef', box).value;
        if ((mode === 'above' || mode === 'below') && !ref) return H.toast('सेक्शन चुनें', true);
        if (SPBLD.webOf(cfg(), id).some(function (y) { return y.file === file; })) return H.toast('ये सेक्शन इस पेज पर पहले से लगा है — पहले उसे हटाएँ', true);
        SPBLD.webPut(cfg(), id, file, ref, mode); touch(); refresh(); paint(); H.toast('✅ ' + file + ' पर जुड़ गया — ऊपर "💾 सेव" दबाएँ');
      }
    });
  });
}

/* ---------- main view ---------- */
function injectCss() {
  if (document.getElementById('bldA-css')) return;
  var s = document.createElement('style'); s.id = 'bldA-css';
  s.textContent = '.bgrid{display:grid;grid-template-columns:minmax(0,1.1fr) minmax(0,360px);gap:14px;align-items:start}@media(max-width:900px){.bgrid{grid-template-columns:minmax(0,1fr)}}' +
    '.blib{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:6px;margin:8px 0}.blib button{text-align:left}.blib button[disabled]{opacity:.5}' +
    '.bcomp{cursor:grab}.bcomp.over{outline:2px dashed var(--g,#1b6b3a)}.bcomp .dr{color:#9aa;font-size:18px;padding:0 6px;cursor:grab;user-select:none}' +
    '.bphone{width:100%;max-width:360px;border:8px solid #14231a;border-radius:26px;background:#fff;padding:10px;max-height:78vh;overflow:auto;box-sizing:border-box;margin:0 auto}.bphone .bld-b{margin-bottom:12px}' +
    '.apc{flex:0 0 140px;border:1px solid #e3ebe3;border-radius:12px;padding:6px;font-size:12px;background:#fff;box-sizing:border-box}.apc .pi{position:relative;display:grid;place-items:center;aspect-ratio:1;border-radius:9px;overflow:hidden}.apc .pi img{width:100%;height:100%;object-fit:cover}.apc .pi em{font-style:normal;font-size:34px}.apc .pi i{position:absolute;left:4px;top:4px;background:#c62828;color:#fff;font-style:normal;font-size:10px;padding:1px 5px;border-radius:6px}.apc b{display:block;margin:5px 0 2px;line-height:1.2;font-size:12px}.apc span{color:#1b5e20;font-weight:700}.apc s{color:#888;font-weight:400}' +
    '.apin{background:#fff;border:1px solid #cfe0d2;border-radius:999px;padding:2px 9px;font-size:12px}';
  document.head.appendChild(s);
}
/* sections that are switched on but have nothing to show: the real app / website draws NOTHING for them (the preview only shows a grey hint) */
function emptyWhy(c) {
  try {
    var g = c.cfg || {}, t = c.type;
    if (t === 'offer_strip') return !String(g.text || '').trim() ? 'text नहीं' : '';
    if (t === 'custom_section') return (!g.title && !g.text && !SP.isImg(g.img)) ? 'title/text नहीं' : '';
    if (t === 'slideshow_banner') return !(g.slides || []).some(function (x) { return x.visible !== false; }) ? 'slide नहीं' : '';
    if (t === 'raw_category') return !(g.boxes || []).some(function (x) { return x.visible !== false; }) ? 'box नहीं' : '';
    if (t === 'product_row') return SPBLD.products(c, pctx()).length ? '' : (g.rule === 'manual' && !g.sec ? 'section चुना नहीं' : 'कोई product नहीं');
  } catch (e) {}
  return '';
}
function listHtml() {
  var o = SPBLD.list(cfg(), PG, true);
  if (!o.length) return '<div class="empty">इस पेज पर अभी कोई सेक्शन नहीं है। नीचे "सेक्शन जोड़ें" से शुरू करें, या "☀️ Solar टेम्पलेट" दबाएँ।</div>';
  return o.map(function (c, i) {
    var t = TC(c);
    return '<div class="row bcomp' + (!SPBLD.vis(c, PG) ? ' dim' : '') + '" draggable="true" data-bc="' + esc(c.id) + '"><span class="dr" title="पकड़कर खींचें">⠿</span><div class="rm"><b>' + esc(t.icon || '') + ' ' + esc(c.name) + '</b><small><code>' + esc(c.id) + '</code> • ' + esc(t.label) + (c.pages.store && c.pages.shop ? ' • Store+Shop' : (c.pages.store ? ' • Store' : ' • Shop')) + (!SPBLD.vis(c, PG) ? ' • <span class="tag r">यहाँ छुपा</span>' : '') + webBadge(c) + (SPBLD.vis(c, PG) && emptyWhy(c) ? ' • <span class="tag r" title="असली app/website में यह सेक्शन दिखेगा ही नहीं">खाली — ' + esc(emptyWhy(c)) + ', app में नहीं दिखेगा</span>' : '') + (c.lock ? ' • 🔒' : '') + '</small></div>' +
      '<div class="acts"><button class="ib" data-bm="-1" title="ऊपर"' + (i ? '' : ' disabled') + '>▲</button><button class="ib" data-bm="1" title="नीचे"' + (i < o.length - 1 ? '' : ' disabled') + '>▼</button><button class="ib" data-bv title="इस पेज पर दिखाएँ / छुपाएँ (बाकी जगह पर कोई असर नहीं)">' + (!SPBLD.vis(c, PG) ? '🚫' : '👁') + '</button><button class="ib" data-bp title="📍 कहाँ-कहाँ दिखे">📍</button><button class="ib" data-bl title="लॉक">' + (c.lock ? '🔒' : '🔓') + '</button><button class="ib" data-bn title="नाम बदलें">🏷️</button><button class="ib" data-bdup title="Duplicate">⧉</button><button class="ib" data-bs title="सेटिंग्स">⚙️</button><button class="ib red" data-bd title="हटाएँ">🗑</button></div></div>';
  }).join('');
}
function libHtml() {
  return '<div class="blib">' + SPBLD.ORDER.map(function (t) {
    var T0 = T(t), have = T0.fixed && cfg().comps[t];
    return '<button class="btn sm out" data-badd="' + t + '"' + (have ? ' disabled title="पहले से जुड़ा है"' : '') + '>' + esc(T0.icon) + ' ' + esc(T0.label) + (have ? ' ✓' : '') + '</button>';
  }).join('') + '</div>';
}
function html() {
  injectCss(); autoSeed(); var on = !!cfg().on[PG], n = SPBLD.list(cfg(), PG, true).length;
  return '<div class="bar">' + (LOCK ? '<b style="font-size:16px">' + (PG === 'shop' ? '🛍️ Shop पेज (वेबसाइट)' : '🏪 Store पेज') + '</b>' : '<button class="btn ' + (PG === 'store' ? '' : 'out') + '" data-bpg="store">🏪 Store पेज</button><button class="btn ' + (PG === 'shop' ? '' : 'out') + '" data-bpg="shop">🛍️ Shop पेज (वेबसाइट)</button>') + '<span class="grow"></span>' +
    '<label class="chk" style="margin:0"><input type="checkbox" id="bOn"' + (on ? ' checked' : '') + '> इस पेज पर बिल्डर <b>चालू</b></label><button class="btn" id="bSave">💾 सेव</button></div>' +
    '<div class="note' + (on ? ' g' : '') + '" id="bState">' + (on ? '✅ बिल्डर चालू है — ' + (PG === 'store' ? 'स्टोर' : 'वेबसाइट Shop') + ' पेज अब नीचे बने क्रम में दिखेगा।' : '💤 बिल्डर बंद है — अभी पुराना लेआउट ही दिख रहा है (कुछ बदला नहीं)। पहले बनाएँ → प्रीव्यू देखें → फिर चालू करें।') + (DIRTY ? ' <b style="color:#c62828">• बदलाव सेव नहीं हुए</b>' : '') + '</div>' +
    (SEEDNOTE && PG === 'store' ? '<div class="note" style="border-color:#f9a825">📥 <b>पहली बार खोला:</b> Store पेज पर ग्राहकों को जो-जो सेक्शन अभी दिख रहे हैं, वे सब इसी क्रम में यहाँ आ गए और सेव हो गए। अब किसी सेक्शन का <b>👁 दबाकर छुपाएँ</b> तो वह Store पेज पर भी नहीं दिखेगा; ▲▼ से क्रम बदलें, ⚙️ से बदलाव करें।</div>' : '') +
    (SEEDNOTE && PG === 'shop' ? '<div class="note" style="border-color:#f9a825">📥 <b>पहली बार खोला:</b> Shop पेज (वेबसाइट) पर ग्राहकों को जो-जो हिस्से अभी दिख रहे हैं — सर्च + पिनकोड, कैटेगरी चिप्स, सारे प्रोडक्ट — वे यहाँ आ गए और सेव हो गए। अब 👁 से किसी को छुपाएँ तो वह Shop पेज से भी हट जाएगा; ▲▼ से क्रम बदलें; ऊपर की लिस्ट से नए सेक्शन जोड़ें। Store App का कुछ यहाँ कॉपी नहीं होता।</div>' : '') +
    '<div class="bgrid"><div><b>📚 सेक्शन जोड़ें</b>' + libHtml() + '<div class="bar" style="margin-top:4px"><button class="btn sm out" data-btpl>☀️ Solar टेम्पलेट + शुरुआती प्रोडक्ट</button><button class="btn sm gray" data-bdemo-rm>🧹 शुरुआती हटाएँ</button></div>' +
    '<b>🧱 इस पेज के सेक्शन (' + n + ')</b><div id="bList" style="margin-top:6px">' + listHtml() + '</div></div>' +
    '<div><b>👁 लाइव प्रीव्यू</b> <small style="color:var(--mut)">(क्लिक बंद हैं)</small><div id="bPvBar" class="bar" style="margin:6px 0 0"></div><div class="bphone" id="bldPrv" style="margin-top:6px"></div></div></div>';
}
function refresh() {
  var l = $('#bList'); if (l) l.innerHTML = listHtml();
  var lb = $('.blib'); if (lb) lb.outerHTML = libHtml();
  var st = $('#bState'); if (st) { var on = !!cfg().on[PG]; st.className = 'note' + (on ? ' g' : ''); st.innerHTML = (on ? '✅ बिल्डर चालू है — ' + (PG === 'store' ? 'स्टोर' : 'वेबसाइट Shop') + ' पेज अब नीचे बने क्रम में दिखेगा।' : '💤 बिल्डर बंद है — अभी पुराना लेआउट ही दिख रहा है (कुछ बदला नहीं)। पहले बनाएँ → प्रीव्यू देखें → फिर चालू करें।') + (DIRTY ? ' <b style="color:#c62828">• बदलाव सेव नहीं हुए</b>' : ''); }
  paintPreview();
}
function bind(m) {
  paintPreview();
  if (SEEDED) { SEEDED = false; H.save(PG === 'store' ? '📥 Store पेज के सारे मौजूदा सेक्शन Page Builder में आ गए और सेव हो गए' : '📥 Shop पेज के मौजूदा हिस्से Page Builder में आ गए और सेव हो गए').then(function () { DIRTY = false; }); }
  m.addEventListener('click', async function (e) {
    var b, id;
    if ((b = e.target.closest('[data-bpg]'))) { PG = b.getAttribute('data-bpg'); PVF = ''; H.render(); return; }
    if (e.target.closest('[data-pvall]')) { PVF = ''; paintPreview(); return; }
    if ((b = e.target.closest('[data-badd]'))) { addComp(b.getAttribute('data-badd')); return; }
    if (e.target.closest('#bSave')) {
      touch(); await H.save('✅ पेज बिल्डर सेव हो गया'); DIRTY = false; refresh(); return;
    }
    if ((b = e.target.closest('[data-btpl]'))) { template(); return; }
    if ((b = e.target.closest('[data-bdemo-rm]'))) { removeDemo(); return; }
    var row = e.target.closest('[data-bc]'); if (!row) return; id = row.getAttribute('data-bc');
    if ((b = e.target.closest('[data-bm]'))) move(id, +b.getAttribute('data-bm'));
    else if (e.target.closest('[data-bv]')) { var hc = cfg().comps[id]; hc.hide = hc.hide || { store: false, shop: false }; hc.hide[PG] = !hc.hide[PG]; touch(); refresh(); }
    else if (e.target.closest('[data-bp]')) placeModal(id);
    else if (e.target.closest('[data-bl]')) { cfg().comps[id].lock = !cfg().comps[id].lock; touch(); refresh(); }
    else if (e.target.closest('[data-bdup]')) dupComp(id);
    else if (e.target.closest('[data-bn]')) rename(id);
    else if (e.target.closest('[data-bs]')) settings(id);
    else if (e.target.closest('[data-bd]')) del(id);
  });
  m.addEventListener('change', function (e) { if (e.target.id === 'bOn') { cfg().on[PG] = e.target.checked; touch(); refresh(); } });
  var drag = null;
  m.addEventListener('dragstart', function (e) { var r = e.target.closest && e.target.closest('[data-bc]'); if (!r) return; drag = r.getAttribute('data-bc'); try { e.dataTransfer.setData('text/plain', drag); e.dataTransfer.effectAllowed = 'move'; } catch (x) {} });
  m.addEventListener('dragover', function (e) { var r = e.target.closest && e.target.closest('[data-bc]'); if (r && drag) { e.preventDefault(); $$('.bcomp.over', m).forEach(function (x) { x.classList.remove('over'); }); r.classList.add('over'); } });
  m.addEventListener('drop', function (e) { var r = e.target.closest && e.target.closest('[data-bc]'); if (r && drag) { e.preventDefault(); var t = r.getAttribute('data-bc'); var d0 = drag; drag = null; dropTo(d0, t); } });
  m.addEventListener('dragend', function () { drag = null; $$('.bcomp.over', m).forEach(function (x) { x.classList.remove('over'); }); });
}

/* ---------- Solar starter template + starter products (all demo items are hidden from customers: visible:false, demo:true) ---------- */
var DEMO_SECS = [['Solar Panels', 'Solar Panels', '☀️', '#fff3cd'], ['Inverters', 'Inverters', '🔌', '#e3f2fd'], ['Batteries', 'Batteries', '🔋', '#e8f5e9'], ['Mounting Structures', 'Structures', '🏗️', '#f3e5f5'], ['Cables & Accessories', 'Cables', '🧵', '#ffebee'], ['Complete Solar Kits', 'Solar Kits', '🏠', '#e0f2f1']];
var DEMO_P = [
  ['Mono PERC Solar Panel 540W', 0, 16500, 13999, 'Waaree / Adani type — 25 saal performance warranty', 'Panel'],
  ['Bifacial Solar Panel 545W', 0, 18200, 15499, 'Dono taraf se bijli banata hai', 'Panel'],
  ['Solar Panel 335W Poly', 0, 9500, 8200, 'Chhote system ke liye', 'Panel'],
  ['Hybrid Solar Inverter 5kW', 1, 62000, 54999, 'On/Off-grid dono, WiFi monitoring', 'Inverter'],
  ['On-Grid Inverter 3kW', 1, 36000, 31500, 'Net-metering ready', 'Inverter'],
  ['Solar PCU 1kVA', 1, 14500, 12800, 'Ghar ke liye, MPPT', 'Inverter'],
  ['Tubular Battery 150Ah', 2, 15800, 14200, '36 mahine warranty', 'Battery'],
  ['Lithium Battery 5kWh', 2, 98000, 89999, 'LiFePO4, 10 saal life', 'Battery'],
  ['GI Mounting Structure 3kW', 3, 21000, 18500, 'Hot-dip galvanised', 'Structure'],
  ['Solar DC Cable 4mm (per meter)', 4, 68, 59, 'UV-resistant, double insulation', 'Cable'],
  ['MC4 Connector Pair', 4, 120, 95, 'IP67', 'Accessory'],
  ['3kW Home Solar Kit (On-Grid)', 5, 215000, 189000, 'Panel + Inverter + Structure + Wiring', 'Kit'],
  ['5kW Hybrid Solar Kit', 5, 385000, 349000, 'Battery-ready complete kit', 'Kit']
];
async function template() {
  if (!(await H.ask('Solar टेम्पलेट बनाएँ?<br><small>6 सेक्शन + 13 शुरुआती प्रोडक्ट जुड़ेंगे। शुरुआती प्रोडक्ट ग्राहकों को <b>नहीं दिखते</b> (सिर्फ़ यहाँ प्रीव्यू में)। बिल्डर चालू नहीं होगा। जब चाहें "🧹 शुरुआती हटाएँ" से सब हट जाएगा।</small>', 'हाँ, बनाएँ'))) return;
  var d = D(), ids = [];
  DEMO_SECS.forEach(function (x) {
    var s = d.sections.filter(function (z) { return z.demo && z.title === x[0]; })[0];
    if (!s) { s = Object.assign(clone(SP.SECTION_DEF), { id: SP.uid('sec'), title: x[0], titleEn: x[0], icon: x[2], kind: 'category', limit: 8, visible: true, demo: true, via: 'starter' }); d.sections.push(s); }
    ids.push(s.id);
  });
  DEMO_P.forEach(function (x, i) {
    if (d.products.some(function (p) { return p.demo && p.title === x[0]; })) return;
    var sc = DEMO_SECS[x[1]];
    d.products.push(Object.assign(clone(SP.PRODUCT_DEF), { id: SP.uid('p'), title: x[0], titleEn: x[0], sections: [ids[x[1]]], mrp: x[2], offer: x[3], tagline: x[4], desc: x[4], emoji: sc[2], bg: sc[3], brand: 'Sunpowers', sku: 'STR-' + (i + 1), sort: i, visible: false, web: true, demo: true, unit: x[5] }));
  });
  var c = cfg();
  if (!Object.keys(c.comps).some(function (k) { return c.comps[k].demo; })) {
    var mk = function (type, name, extra) { var o = SPBLD.add(c, type); if (!o) return null; o.demo = true; if (name) o.name = name; Object.assign(o.cfg, extra || {}); o.pages = { store: true, shop: true }; return o; };
    var order = [];
    var cs = [
      mk('search_bar'),
      mk('slideshow_banner', 'Main Banner', { slides: [
        { id: 'sl_a', title: 'Ghar ki chhat se bijli', sub: 'Free site visit — Lucknow', bg: '#1b5e20', emoji: '☀️', btns: [{ label: 'Shop Now', linkType: 'section', link: ids[0], pos: 'bl', style: 'light' }] },
        { id: 'sl_b', title: 'Hybrid Inverter', sub: 'WiFi monitoring ke saath', bg: '#0d47a1', emoji: '🔌', btns: [{ label: 'Dekhein', linkType: 'section', link: ids[1], pos: 'bl', style: 'light' }] },
        { id: 'sl_c', title: 'Complete Solar Kits', sub: 'Panel + Inverter + Structure', bg: '#e65100', emoji: '🏠', btns: [{ label: 'Kits dekhein', linkType: 'section', link: ids[5], pos: 'bl', style: 'light' }] }] }),
      mk('delivery_bar', 'Delivery', { text: 'Lucknow aur UP me home delivery • Free site visit', pin: true }),
      mk('raw_category', 'Shop by Category', { cols: 3, boxes: [] }),
      mk('product_row', 'Deals of the Day', { sec: '', rule: 'discount', limit: 8 }),
      mk('product_row', 'New Arrivals', { sec: '', rule: 'newest', limit: 8 }),
      mk('offer_strip', 'Offer', { text: 'Free site visit & consultation — Sunpowers Lucknow', bg: '#1b5e20', fg: '#ffffff' }),
      mk('product_row', 'Complete Solar Kits', { rule: 'manual', sec: ids[5], limit: 8 }),
      mk('video_section', 'Our Video', { url: '' }),
      mk('youtube_section', 'Our YouTube', { channel: '', vids: [] })
    ];
    var rc = cs[3];
    DEMO_SECS.forEach(function (x, i) { rc.cfg.boxes.push({ id: SPBLD.nextBox(rc), name: x[1], nameEn: x[1], emoji: x[2], bg: x[3], sec: ids[i], visible: true }); });
    cs.forEach(function (o) { if (o) order.push(o.id); });
    c.order.store = c.order.store.filter(function (id) { return order.indexOf(id) < 0; }).concat(order); c.order.shop = c.order.shop.filter(function (id) { return order.indexOf(id) < 0; }).concat(order);
  }
  touch(); H.render(); H.toast('☀️ टेम्पलेट तैयार — प्रीव्यू देखें, फिर "💾 सेव" दबाएँ');
}
async function removeDemo() {
  var d = D(), np = d.products.filter(function (p) { return p.demo; }).length, ns = d.sections.filter(function (s) { return s.demo; }).length, c = cfg();
  var nc = Object.keys(c.comps).filter(function (k) { return c.comps[k].demo; });
  if (!np && !ns && !nc.length) return H.toast('कोई शुरुआती नहीं मिला');
  if (!(await H.ask('शुरुआती हटाएँ?<br><small>' + np + ' शुरुआती प्रोडक्ट, ' + ns + ' शुरुआती सेक्शन और ' + nc.length + ' टेम्पलेट सेक्शन हटेंगे। आपके असली प्रोडक्ट/सेक्शन नहीं छुए जाएँगे।</small>', 'हाँ, हटाएँ', true))) return;
  var gs = {}; d.sections.forEach(function (s) { if (s.demo) gs[s.id] = 1; });
  d.products = d.products.filter(function (p) { return !p.demo; });
  d.sections = d.sections.filter(function (s) { return !s.demo; });
  d.layout = (d.layout || []).filter(function (b) { return !(b.type === 'section' && gs[b.ref]); });
  d.products.forEach(function (p) { p.sections = (p.sections || []).filter(function (x) { return !gs[x]; }); });
  nc.forEach(function (k) { SPBLD.remove(c, k); });
  Object.keys(c.comps).forEach(function (k) { var o = c.comps[k]; if (o.cfg && Array.isArray(o.cfg.boxes)) o.cfg.boxes = o.cfg.boxes.filter(function (b) { return !gs[b.sec]; }); if (o.cfg && gs[o.cfg.sec]) o.cfg.sec = ''; });
  touch(); H.render(); H.toast('🧹 शुरुआती हट गया — "💾 सेव" दबाएँ');
}

/* ---------- public ---------- */
window.SPBA = {
  init: function (h) { H = h; },
  setPage: function (pg, lock) { PG = pg === 'shop' ? 'shop' : 'store'; LOCK = !!lock; },
  reset: function () { BC = null; DIRTY = false; PT.forEach(clearInterval); PT = []; },
  html: html, bind: bind,
  cfg: cfg,
  /* used by the publish queue: where can a product be placed? → [{id,title,uses:[…]}] */
  placements: function () {
    var c = cfg(), use = {};
    Object.keys(c.comps).forEach(function (k) { var o = c.comps[k]; if (o.type === 'raw_category') o.cfg.boxes.forEach(function (b) { if (b.sec) (use[b.sec] = use[b.sec] || []).push('🧩 ' + o.name + ' › ' + b.name); }); else if (o.cfg && o.cfg.sec) (use[o.cfg.sec] = use[o.cfg.sec] || []).push('🛒 ' + o.name); });
    return sections().map(function (s) { return { id: s.id, title: (s.icon ? s.icon + ' ' : '') + s.title, uses: use[s.id] || [] }; });
  },
  dirty: function () { return DIRTY; }
};
})();
