/* Sunpowers Admin — 🌐 Website Admin
   Edits the public website (www) without code. All changes are stored in ONE database row (sp_store id='web')
   and applied live by assets/cms.js on the website. The Online Store data is never touched here. */
(function () {
'use strict';
var A = null, W = null, TAB = 'dash', LASTSCOPE = '', PAGE = 'index', Q = '';
var $ = function (s, r) { return (r || document).querySelector(s); };
var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
var MAN = function () { return (window.CMS_MANIFEST && window.CMS_MANIFEST.pages) || []; };
var DEF = function () { return window.CMS_DEFAULTS || { slides: [], menu: [], pages: [], slugs: [] }; };
var TABS_ALL = [['dash', '📊 डैशबोर्ड'], ['wb', '🧱 Website Builder'], ['menu', '🧭 मेन्यू (हेडर / फ़ुटर के नाम)'], ['pages', '📄 पेज व पॉलिसी'], ['photos', '🖼️ Website Media'], ['cards', '🃏 कार्ड लिंक / मीडिया'], ['links', '🛒 स्टोर लिंक'], ['site', '⭐ रेटिंग, सोशल व ऐप'], ['look', '🎨 वेबसाइट सेटिंग (रंग व ग्रीटिंग)']];
var TABS_SHOP = [['dash', '📊 डैशबोर्ड'], ['builder', '🧱 Web Shop Page Builder'], ['texts', '📝 Shop पेज के शब्द व बटन'], ['shop', '🛍️ कार्ट सेक्शन'], ['photos', '🖼️ Shop Media']];
var SCOPE = 'site', TABS = TABS_ALL;
var WHINTS = {shop: 'On-Grid / Off-Grid / Hybrid / VFD वाले हर सेक्शन में स्टोर के असली प्रोडक्ट और Add to cart दिखता है। यहाँ ऊपर का नाम, कौन-से प्रोडक्ट दिखें और बटन का असली लिंक बदलें।', links: 'वेबसाइट के बटन किस स्टोर पेज पर जाएँ।', banners: 'होम को छोड़कर हर पेज के नीचे 16:9 बैनर — 1 वीडियो या अधिकतम 5 फ़ोटो + 2 बटन। खाली = डिफ़ॉल्ट Sunpowers बैनर (फ्री साइट विज़िट + WhatsApp)। छुपाने के लिए टिक करें।', cards: 'प्रोजेक्ट/ब्रांड/सर्विस कार्ड के अतिरिक्त लिंक व फ़ोटो-वीडियो। खाली = डिफ़ॉल्ट बटन; - लिखें तो बटन छुपेगा। लिंक https:// से शुरू होना चाहिए।', menu: 'ऊपर के मेन्यू के नाम और क्रम।', home: 'होम पेज के सेक्शन दिखाएँ/छुपाएँ।', pages: 'नया पेज बनाएँ — हेडिंग, टेक्स्ट और फ़ोटो जोड़ें।', site: 'रेटिंग, सोशल लिंक और संपर्क जानकारी। असली आँकड़े ही डालें।'};
var SAVED_JSON = '';

function norm(d) {
  d = d && typeof d === 'object' && !Array.isArray(d) ? d : {};
  d.v = 1; ['text', 'img', 'links'].forEach(function (k) { if (!d[k] || typeof d[k] !== 'object' || Array.isArray(d[k])) d[k] = {}; });
  ['banners', 'cards', 'shop'].forEach(function (k) { if (!d[k] || typeof d[k] !== 'object' || Array.isArray(d[k])) d[k] = {}; });
  if (!Array.isArray(d.slides)) d.slides = []; if (!Array.isArray(d.pages)) d.pages = [];
  if (!d.menu || typeof d.menu !== 'object') d.menu = {}; if (!Array.isArray(d.menu.hide)) d.menu.hide = []; if (!Array.isArray(d.menu.add)) d.menu.add = []; if (!d.menu.names || typeof d.menu.names !== 'object') d.menu.names = {};
  if (!d.home || typeof d.home !== 'object') d.home = {}; if (!Array.isArray(d.home.hide)) d.home.hide = []; if (!Array.isArray(d.home.order)) d.home.order = []; if (!Array.isArray(d.home.extra)) d.home.extra = [];
  if (!Array.isArray(d.home.del)) d.home.del = []; if (!Array.isArray(d.home.dup)) d.home.dup = []; if (!d.home.btn || typeof d.home.btn !== 'object' || Array.isArray(d.home.btn)) d.home.btn = {}; if (!d.pg || typeof d.pg !== 'object' || Array.isArray(d.pg)) d.pg = {};
  if (!d.site || typeof d.site !== 'object') d.site = {}; if (!d.site.rating) d.site.rating = {}; if (!d.site.social) d.site.social = {}; if (!d.site.app || typeof d.site.app !== 'object') d.site.app = {};
  return d;
}
function setP(o, p, v) { var k = p.split('.'), i; for (i = 0; i < k.length - 1; i++) { var nx = k[i + 1]; if (o[k[i]] == null || typeof o[k[i]] !== 'object') o[k[i]] = /^\d+$/.test(nx) ? [] : {}; o = o[k[i]]; } o[k[k.length - 1]] = v; }
function getP(o, p) { return p.split('.').reduce(function (a, k) { return a == null ? undefined : a[k]; }, o); }
function https(u) { u = String(u || '').trim(); return !u || /^(https:\/\/|http:\/\/(127\.0\.0\.1|localhost)[:\/])/i.test(u); }
function siteBase() { var u = A.siteLink ? A.siteLink() : ''; return u ? u.replace(/\/+$/, '') + '/' : ''; }

/* ---------- field helpers (value is read back by collect() through data-p) ---------- */
function val(p, d) { var v = getP(W, p); return v == null ? (d == null ? '' : d) : v; }
function tf(p, label, o) {
  /* Round 27: content is written in English only — the Hindi / Hinglish / other-language versions are made automatically on the public side */
  if (/\.hi$/.test(p)) return '';
  label = String(label).replace(/\s*\((English|अंग्रेज़ी)\)/g, '').replace(/^English\s*\(.*?\)\s*/, 'English ');
  o = o || {}; var v = val(p);
  var inner = o.area ? '<textarea class="inp" data-p="' + esc(p) + '" rows="' + (o.rows || 3) + '" placeholder="' + esc(o.ph || '') + '">' + esc(v) + '</textarea>'
    : '<input class="inp" type="text" data-p="' + esc(p) + '" value="' + esc(v) + '" placeholder="' + esc(o.ph || '') + '"' + (o.max ? ' maxlength="' + o.max + '"' : '') + '>';
  return '<div class="fld' + (o.full ? ' full' : '') + '"><label class="l">' + esc(label) + '</label>' + inner + (o.h ? '<small class="help">' + o.h + '</small>' : '') + '</div>';
}
function sel(p, label, opts, o) {
  var v = val(p, opts[0][0]);
  return '<div class="fld' + ((o && o.full) ? ' full' : '') + '"><label class="l">' + esc(label) + '</label><select class="inp" data-p="' + esc(p) + '">' + opts.map(function (x) { return '<option value="' + esc(x[0]) + '"' + (String(v) === String(x[0]) ? ' selected' : '') + '>' + esc(x[1]) + '</option>'; }).join('') + '</select></div>';
}
function chk(p, label) { return '<label class="chk"><input type="checkbox" data-p="' + esc(p) + '" data-bool' + (val(p) === true ? ' checked' : '') + '> ' + esc(label) + '</label>'; }
function imgf(p, label, fallback) {
  var v = val(p), prev = v || fallback || '';
  return '<div class="fld full"><label class="l">' + esc(label) + '</label><div class="imgf"><div class="imgprev" data-prev>' + (/^(https?:|\.\.?\/|[\w\-\/]+\.(jpe?g|png|webp|svg|gif))/i.test(prev) ? '<img src="' + esc(prev) + '" alt="" onerror="this.remove()">' : 'कोई फ़ोटो नहीं') + '</div>' +
    '<div class="imgbtns"><span class="btn sm upl"><b data-ul data-a="📷 फ़ोटो अपलोड" data-b="🔄 फ़ोटो बदलें (Replace)">📷 फ़ोटो अपलोड</b><input type="file" accept="image/*" data-up></span><button type="button" class="btn sm out" data-lnkf>🔗 लिंक से बदलें</button><button type="button" class="btn sm gray" data-clrimg data-del>🗑 हटाएँ (Delete)</button></div>' +
    '<input class="imgurl" type="text" data-p="' + esc(p) + '" data-img value="' + esc(v) + '" placeholder="या फ़ोटो का https:// लिंक paste करें"></div></div>';
}
/* ---------- PDF upload (datasheet etc.): auto-shrink to max 500 KB, then upload ---------- */
var PDF_MAX = 500 * 1024, PDFLIB_URL = 'https://cdnjs.cloudflare.com/ajax/libs/pdf-lib/1.17.1/pdf-lib.min.js';
function pdfField(p, label, h) {
  var v = val(p);
  return '<div class="fld full"><label class="l">' + esc(label) + '</label><div class="imgf"><div class="imgprev" data-pprev>' + (v ? '<a href="' + esc(v) + '" target="_blank" rel="noopener">📄 PDF खोलें</a>' : 'कोई PDF नहीं') + '</div>' +
    '<div class="imgbtns"><span class="btn sm upl">📄 PDF अपलोड<input type="file" accept="application/pdf" data-pup></span><button type="button" class="btn sm gray" data-clrpdf>हटाएँ</button></div>' +
    '<input class="imgurl" type="text" data-p="' + esc(p) + '" data-purl value="' + esc(v) + '" placeholder="या PDF का https:// लिंक paste करें"></div>' +
    '<small class="help">PDF अपने-आप छोटी होने की कोशिश होगी; 500 KB से बड़ी रहे तो अपलोड नहीं होगी.' + (h ? ' ' + h : '') + '</small></div>';
}
function loadPdfLib() {
  if (window.PDFLib) return Promise.resolve(window.PDFLib);
  return new Promise(function (res, rej) {
    var s = document.createElement('script'); s.src = PDFLIB_URL;
    s.onload = function () { window.PDFLib ? res(window.PDFLib) : rej(new Error('pdf tool')); };
    s.onerror = function () { rej(new Error('PDF टूल लोड नहीं हुआ — इंटरनेट जाँचें')); };
    document.head.appendChild(s);
  });
}
async function shrinkPdf(file) {
  if (!/pdf$/i.test(file.type || '') && !/\.pdf$/i.test(file.name || '')) throw new Error('सिर्फ़ PDF फ़ाइल चुनें');
  var buf = await file.arrayBuffer(), out = buf;
  try {
    var L = await loadPdfLib();
    var doc = await L.PDFDocument.load(buf, { ignoreEncryption: true, updateMetadata: false });
    var b = await doc.save({ useObjectStreams: true });
    if (b.byteLength < out.byteLength) out = b;
  } catch (e) { /* tool unavailable: try the original file */ }
  if (out.byteLength > PDF_MAX) throw new Error('PDF ' + Math.round(out.byteLength / 1024) + ' KB है — 500 KB से छोटी PDF चुनें (PDF को छोटा/compress करके दोबारा अपलोड करें)');
  return new Blob([out], { type: 'application/pdf' });
}
function bindPdf(m) {
  m.addEventListener('click', function (e) { var b = e.target.closest('[data-clrpdf]'); if (b) { var box = b.closest('.imgf'); $('[data-purl]', box).value = ''; $('[data-pprev]', box).innerHTML = 'कोई PDF नहीं'; } });
  m.addEventListener('change', async function (e) {
    var f = e.target.closest('[data-pup]'); if (!f || !f.files[0]) return; var file = f.files[0]; f.value = '';
    var box = f.closest('.imgf'), pv = $('[data-pprev]', box); pv.innerHTML = '<span class="spin"></span> PDF छोटी हो रही है…';
    try {
      var blob = await shrinkPdf(file); pv.innerHTML = '<span class="spin"></span> अपलोड हो रही है…';
      var u = await SP.uploadImage(blob); if (!/^https?:/i.test(u)) throw new Error('अपलोड नहीं हुआ');
      $('[data-purl]', box).value = u; pv.innerHTML = '<a href="' + esc(u) + '" target="_blank" rel="noopener">📄 PDF खोलें</a> (' + Math.round(blob.size / 1024) + ' KB)';
      toast('✅ PDF अपलोड हो गई — अब सेव करें');
    } catch (er) { pv.innerHTML = 'कोई PDF नहीं'; toast((er && er.message || 'PDF अपलोड नहीं हुई').slice(0, 160), true); }
  });
  m.addEventListener('input', function (e) { var i = e.target.closest('[data-purl]'); if (i) { var pv = $('[data-pprev]', i.closest('.imgf')); pv.innerHTML = /^https?:\/\//i.test(i.value) ? '<a href="' + esc(i.value) + '" target="_blank" rel="noopener">📄 PDF खोलें</a>' : 'कोई PDF नहीं'; } });
}
function collect(root) {
  $$('[data-p]', root || $('#wmain')).forEach(function (el) {
    var v = el.hasAttribute('data-bool') ? el.checked : (el.value || '').trim();
    if (el.hasAttribute('data-bool') && !v) { var cur = getP(W, el.getAttribute('data-p')); if (cur === undefined) return; }
    var pp = el.getAttribute('data-p');
    if (/\.en$/.test(pp) && !el.hasAttribute('data-bool') && String(getP(W, pp) == null ? '' : getP(W, pp)) !== String(v)) setP(W, pp.replace(/\.en$/, '.hi'), '');
    setP(W, pp, v);
  });
}
function toast(m, e) { A.toast(m, e); }

/* ---------- save ---------- */
var chain = Promise.resolve();
function save(msg) {
  chain = chain.then(async function () {
    var data = norm(JSON.parse(JSON.stringify(W)));
    ['img', 'links'].forEach(function (k) { Object.keys(data[k]).forEach(function (x) { if (!String(data[k][x] || '').trim()) delete data[k][x]; }); });
    try {
      await A.rpc('sp_save_web', { p_pass: A.pass(), p_data: data }, 60000);
      SAVED_JSON = JSON.stringify(data); try { localStorage.removeItem('sp_web_cache_v1'); } catch (e) {}
      toast(msg || '✅ सेव हो गया — वेबसाइट पर लाइव (1–2 मिनट में दिखेगा)');
    } catch (e) {
      if (/wrong password/i.test(e.message)) return A.logout('लॉगिन का समय पूरा — दोबारा लॉगिन करें');
      if (/Could not find|PGRST202|schema cache/i.test(e.message)) toast('❌ पहले Supabase में phase4-website-admin.sql चलाएँ (MASTER-UPDATE.sql में शामिल है)', true);
      else toast('❌ सेव नहीं हुआ: ' + e.message, true);
    }
  });
  return chain;
}

/* ---------- shell ---------- */
function shell() {
  A.setMode(SCOPE === 'shop' ? 'shop' : 'web');
  if (SCOPE === 'shop' && A.builder) A.builder.use(function () { if (TAB === 'builder') draw(); }, 'shop');
  A.app.innerHTML = SPHDR.bar({ title: SCOPE === 'shop' ? 'Shop Page' : 'Website Management', back: true, filter: true }) +
    '<main id="wmain"></main>';
  SPHDR.bind({ back: function () { collect(); A.back(); }, filter: function () { var c = window.SPDASH && SPDASH.ctl; return { ranges: c ? c.ranges() : [], pick: function (v) { var c2 = SPDASH.ctl; if (!c2) return; if (v === 'ref') c2.refresh(); else if (v === 'csv') c2.csv(); else c2.set(v); } }; } }); SPHDR.refresh();
  if (window.SPI18N && SPI18N.refresh) try { SPI18N.refresh(); } catch (e) {}
  draw();
}
function draw() {
  var fb = document.querySelector('.hd [data-hd="filter"]'); if (fb) fb.classList.toggle('hide', TAB !== 'dash');
  var ttl = document.querySelector('.hd-t span'); if (ttl) ttl.textContent = (SCOPE === 'shop' ? 'Shop Page' : 'Website Management') + ' — ' + ((TABS.filter(function (x) { return x[0] === TAB; })[0] || ['', ''])[1].replace(/^\S+\s/, ''));
  var m = $('#wmain'), old = m, n = old.cloneNode(false); old.parentNode.replaceChild(n, old); m = n;
  try { m.innerHTML = (SCOPE === 'shop' ? '<div class="via sh"><i></i>🛍️ सिर्फ़ Web Shop पेज (वेबसाइट) <small>— Store App पर असर नहीं</small></div>' : '') + (WHINTS[TAB] ? '<div class="note g" data-hint>💡 ' + esc(WHINTS[TAB]) + '</div>' : '') + VIEW[TAB](); } catch (e) { console.error(e); m.innerHTML = '<div class="note r">Error: ' + esc(e.message) + '</div>'; return; }
  bindCommon(m); if (BIND[TAB]) BIND[TAB](m);
}
/* Round 27: every photo / video box shows "Replace" + "Delete" once it holds a file (and plain "Upload" while it is empty) */
function mstate(root) {
  $$('.imgf', root).forEach(function (box) {
    var u = $('[data-img],[data-vurl]', box), ul = $('[data-ul]', box), dl = $('[data-del]', box), lf = $('[data-lnkf]', box); if (!u || !ul) return;
    var has = !!String(u.value || '').trim(); ul.textContent = has ? ul.getAttribute('data-b') : ul.getAttribute('data-a'); if (dl) dl.hidden = !has; if (lf) lf.hidden = !has;
  });
}
function bindCommon(m) {
  mstate(m);
  ['click', 'input', 'change'].forEach(function (ev) { m.addEventListener(ev, function (e) { var b = e.target.closest && e.target.closest('[data-lnkf]'); if (b) { var u = $('[data-img],[data-vurl]', b.closest('.imgf')); if (u) { u.focus(); u.select(); } } setTimeout(function () { mstate(m); }, 60); setTimeout(function () { mstate(m); }, 1500); }); });
  m.addEventListener('click', async function (e) {
    var b = e.target.closest('[data-clrimg]'); if (b) { var i = $('[data-img]', b.closest('.imgf')); i.value = ''; $('[data-prev]', b.closest('.imgf')).innerHTML = 'कोई फ़ोटो नहीं'; }
  });
  m.addEventListener('input', function (e) { var i = e.target.closest('[data-img]'); if (i) { var pv = $('[data-prev]', i.closest('.imgf')); pv.innerHTML = /^https?:\/\//i.test(i.value) ? '<img src="' + esc(i.value) + '" alt="" onerror="this.remove()">' : 'कोई फ़ोटो नहीं'; } });
  m.addEventListener('change', async function (e) {
    var f = e.target.closest('[data-up]'); if (!f || !f.files[0]) return; var file = f.files[0]; f.value = '';
    var box = f.closest('.imgf'), pv = $('[data-prev]', box); pv.innerHTML = '<span class="spin"></span>';
    try { var u = await A.upload(file); if (!/^https?:/i.test(u)) throw new Error('Cloud storage में अपलोड नहीं हुआ — Supabase storage जाँचें'); $('[data-img]', box).value = u; pv.innerHTML = '<img src="' + esc(u) + '" alt="">'; }
    catch (er) { pv.innerHTML = 'कोई फ़ोटो नहीं'; toast(er.message, true); }
  });
}
var VIEW = {}, BIND = {};
function saveBtn(id, label) { return '<div class="bar" style="margin-top:14px"><button class="btn" id="' + (id || 'wSave') + '">💾 ' + (label || 'सेव करें') + '</button></div>'; }
function help(h) { return '<div class="note g">' + h + '</div>'; }
function mv(arr, i, d) { var j = i + d; if (j < 0 || j >= arr.length) return false; var x = arr.splice(i, 1)[0]; arr.splice(j, 0, x); return true; }

/* ================= 1. hero slides ================= */
var KINDS = [['a', '🔗 वेबसाइट का पेज खोलें'], ['book', '📝 फ़ॉर्म पॉपअप खोलें'], ['shop', '🛒 ऑनलाइन स्टोर खोलें'], ['wa', '💬 WhatsApp खोलें']];
var KHELP = { a: 'पेज का नाम, जैसे calculator.html या page.html?s=आपका-पेज', book: 'फ़ॉर्म का नाम: Site survey / Installation / shifting / Solar panel cleaning / Solar quote', shop: 'खाली = स्टोर का मुख्य पेज, या /?view=categories जैसा रास्ता, या पूरा https:// लिंक', wa: 'WhatsApp पर पहले से लिखा मैसेज' };
function slidesBody() {
  var S = W.slides, custom = S.length > 0;
  var h = help('वेबसाइट के सबसे ऊपर वीडियो पर जो स्लाइड घूमती हैं, उन्हें यहाँ बदलें। हर स्लाइड = हेडलाइन + छोटी लाइन + एक बटन। English और हिंदी दोनों लिखें (हिंदी खाली छोड़ी तो English दिखेगा)।');
  if (!custom) return h + '<div class="card"><h2>🎞️ अभी वेबसाइट की डिफ़ॉल्ट ' + DEF().slides.length + ' स्लाइड चल रही हैं</h2><p style="color:var(--mut);margin:8px 0">बदलना शुरू करने के लिए डिफ़ॉल्ट स्लाइड यहाँ ले आइए, फिर किसी को बदलें, हटाएँ या नई जोड़ें।</p><button class="btn" id="slSeed">✏️ स्लाइड एडिट करना शुरू करें</button></div>';
  return h + '<div class="bar"><button class="btn" id="slAdd">➕ नई स्लाइड</button><button class="btn out" id="slReset">↩️ डिफ़ॉल्ट पर वापस</button></div>' + S.map(function (s, i) {
    var k = s.kind || 'a';
    return '<div class="card" style="' + (s.hide ? 'opacity:.6' : '') + '"><div style="display:flex;gap:8px;align-items:center;justify-content:space-between;flex-wrap:wrap"><b>स्लाइड ' + (i + 1) + '</b><span class="acts">' +
      '<button class="ib" data-slmv="' + i + '" data-d="-1"' + (i === 0 ? ' disabled' : '') + ' title="ऊपर">⬆️</button><button class="ib" data-slmv="' + i + '" data-d="1"' + (i === S.length - 1 ? ' disabled' : '') + ' title="नीचे">⬇️</button><button class="ib" data-sldel="' + i + '" title="हटाएँ">🗑</button></span></div><div class="fg">' +
      tf('slides.' + i + '.title.en', 'हेडलाइन (English)', { max: 90 }) + tf('slides.' + i + '.title.hi', 'हेडलाइन (हिंदी)', { max: 90 }) +
      tf('slides.' + i + '.text.en', 'छोटी लाइन (English)', { area: 1, max: 220 }) + tf('slides.' + i + '.text.hi', 'छोटी लाइन (हिंदी)', { area: 1, max: 220 }) +
      tf('slides.' + i + '.label.en', 'बटन का नाम (English)', { max: 40 }) + tf('slides.' + i + '.label.hi', 'बटन का नाम (हिंदी)', { max: 40 }) +
      sel('slides.' + i + '.kind', 'बटन क्लिक पर क्या हो?', KINDS) + tf('slides.' + i + '.target', 'कहाँ जाए / क्या लिखा हो', { ph: '', h: KHELP[k] }) +
      '</div>' + chk('slides.' + i + '.hide', 'इस स्लाइड को छुपाएँ (डिलीट किए बिना)') + '</div>';
  }).join('');
}
function slRedraw() { var y = window.pageYOffset; draw(); try { window.scrollTo(0, y); } catch (x) {} }
function bindSlides(m) {
  var seed = $('#slSeed'); if (seed) seed.onclick = function () { collect(m); collectTexts(m); W.slides = JSON.parse(JSON.stringify(DEF().slides)); slRedraw(); };
  var add = $('#slAdd'); if (add) add.onclick = function () { collect(m); collectTexts(m); W.slides.push({ title: { en: '', hi: '' }, text: { en: '', hi: '' }, label: { en: 'Know more', hi: 'और जानें' }, kind: 'a', target: 'services.html' }); slRedraw(); };
  var rs = $('#slReset'); if (rs) rs.onclick = async function () { if (!(await A.ask('सारी कस्टम स्लाइड हटाकर वेबसाइट की डिफ़ॉल्ट स्लाइड पर लौटें?', 'हाँ, वापस', true))) return; collect(m); collectTexts(m); W.slides = []; slRedraw(); };
  m.addEventListener('click', async function (e) {
    var b;
    if ((b = e.target.closest('[data-slmv]'))) { collect(m); collectTexts(m); if (mv(W.slides, +b.getAttribute('data-slmv'), +b.getAttribute('data-d'))) slRedraw(); }
    else if ((b = e.target.closest('[data-sldel]'))) { collect(m); collectTexts(m); if (await A.ask('यह स्लाइड हटाएँ?', 'हटाएँ', true)) { W.slides.splice(+b.getAttribute('data-sldel'), 1); slRedraw(); } }
  });
}
function slidesCheck() {
  var bad = '';
  W.slides.forEach(function (s, i) { if (s.hide) return; if (!s.title || !(s.title.en || s.title.hi)) bad = bad || 'स्लाइड ' + (i + 1) + ' की हेडलाइन लिखें'; if (s.kind === 'a' && s.target && /^\s*(javascript|data):/i.test(s.target)) bad = bad || 'स्लाइड ' + (i + 1) + ' का लिंक सही नहीं'; });
  if (!bad && W.slides.length && !W.slides.some(function (s) { return !s.hide; })) bad = 'कम से कम एक स्लाइड दिखनी चाहिए';
  return bad;
}

/* ================= 2. page text ================= */
function pageList() { return MAN().filter(function (p) { return SCOPE === 'shop' ? p.id === 'shop' : p.id !== 'shop'; }); }
function pageOpts() { return pageList().map(function (p) { return '<option value="' + esc(p.id) + '"' + (p.id === PAGE ? ' selected' : '') + '>' + esc(p.file) + ' — ' + esc(p.title) + '</option>'; }).join(''); }
VIEW.texts = function () {
  var pl = pageList(), pg = pl.filter(function (p) { return p.id === PAGE; })[0] || pl[0]; if (!pg) return '<div class="note r">cms-manifest.js नहीं मिला</div>';
  PAGE = pg.id; var q = Q.toLowerCase();
  var rows = pg.texts.filter(function (t) { return !q || (t.en + ' ' + t.hi + ' ' + (W.text[t.k] ? W.text[t.k].en + ' ' + W.text[t.k].hi : '')).toLowerCase().indexOf(q) >= 0; });
  return help('Shop पेज के शब्द बदलें — जिस लाइन को बदलना है उसमें लिखें। <b>सिर्फ़ English</b> में लिखें — हिंदी / Hinglish / दूसरी भाषा अपने-आप बन जाती है। जो बदला नहीं वह वैसा ही रहेगा; "↩️" से डिफ़ॉल्ट वापस आ जाता है। (फोटो-बटन के अंदर का नाम और हेडर मेन्यू के नाम "मेन्यू" टैब से बदलें।)') +
    '<div class="card"><div class="fg"><div class="fld"><label class="l">खोजें</label><input class="inp" id="txQ" type="text" value="' + esc(Q) + '" placeholder="कोई शब्द लिखें…"></div></div>' +
    '<p style="color:var(--mut);font-size:13px;margin:6px 0">' + rows.length + ' / ' + pg.texts.length + ' लाइनें</p>' +
    rows.map(function (t) {
      var o = W.text[t.k], en = o ? o.en : t.en, hi = o ? o.hi : t.hi, mod = !!o;
      return '<div class="row" style="align-items:flex-start;gap:8px;flex-wrap:wrap;' + (mod ? 'background:#fff8e1' : '') + '"><div style="flex:1 1 100%;font-size:12px;color:var(--mut)">&lt;' + esc(t.tag) + '&gt;' + (mod ? ' <b style="color:#b26a00">• बदला हुआ</b>' : '') + ' <button class="ib" data-txr="' + esc(t.k) + '" title="डिफ़ॉल्ट वापस"' +  + '>↩️</button></div>' +
        '<div style="flex:1 1 260px"><label class="l" style="font-size:12px">English</label><textarea class="inp" rows="2" data-tk="' + esc(t.k) + '" data-l="en" data-d="' + esc(t.en) + '">' + esc(en) + '</textarea></div></div>';

    }).join('') + saveBtn() + '</div>';
};
function collectTexts(m) {
  var by = {};
  $$('[data-tk]', m).forEach(function (el) { var k = el.getAttribute('data-tk'); by[k] = by[k] || {}; by[k][el.getAttribute('data-l')] = { v: el.value.trim(), d: el.getAttribute('data-d') }; });
  Object.keys(by).forEach(function (k) {
    var o = by[k], en = o.en.v, old = W.text[k], keepHi = !en || en === o.en.d || (old && old.en === en) ? (old ? old.hi : '') : '';
    if (!en || en === o.en.d) delete W.text[k]; else W.text[k] = { en: en, hi: keepHi || '' };
  });
}
BIND.texts = function (m) {
  $('#txQ').onchange = function () { collectTexts(m); Q = this.value.trim(); draw(); };
  m.addEventListener('click', function (e) { var b = e.target.closest('[data-txr]'); if (b) { collectTexts(m); delete W.text[b.getAttribute('data-txr')]; draw(); } });
  $('#wSave').onclick = function () { collectTexts(m); save('✅ टेक्स्ट सेव हो गया').then(draw); };
};

/* ================= 3. photos / logo ================= */
/* Round 22: media is split per part - Website Media (logo, page photos, home video) and Shop Media (shop page photos only); each has its own download */
function mediaItems() {
  var base = siteBase(), out = [], seen = {};
  function add(kind, name, u, ap, st) { u = String(u || '').trim(); if (!/^(https?:\/\/|\/img\/)/i.test(u) || seen[u]) return; seen[u] = 1; out.push({ kind: kind, name: name, url: u, apply: ap || function () {}, save: st }); }
  function setW(path) { return function (nv) { if (path.length === 1) { if (nv === '') delete W[path[0]]; else W[path[0]] = nv; } else { var o = W[path[0]]; if (nv === '') delete o[path[1]]; else o[path[1]] = nv; } }; }
  if (SCOPE !== 'shop') { add('logo', 'logo', W.img.logo, setW(['img', 'logo'])); add('video', 'home-video', W.site.video, setW(['site', 'video'])); add('poster', 'home-poster', W.site.poster, setW(['site', 'poster'])); }
  pageList().forEach(function (p) { (p.imgs || []).forEach(function (im, i) { add('photos', p.id + '-' + (i + 1), W.img[im.k], setW(['img', im.k])); }); });
  if (SCOPE === 'shop' && A.builder && A.builder.media) A.builder.media('shop').forEach(function (x) { add(x.kind, x.name, x.url, function (nv) { A.builder.mediaSet('shop', x.url, nv); }, function (m) { return A.saveStore(m); }); });
  return out;
}
VIEW.photos = function () {
  var pl = pageList(), pg = pl.filter(function (p) { return p.id === PAGE; })[0] || pl[0], base = siteBase(), shop = SCOPE === 'shop';
  if (pg) PAGE = pg.id;
  var logo = shop ? '' : '<div class="card"><h2>🏷️ लोगो</h2><p style="color:var(--mut);font-size:13px;margin:4px 0">हेडर और फ़ुटर का लोगो। खाली = डिफ़ॉल्ट लोगो। (चौकोर / पारदर्शी PNG सबसे अच्छा)</p><div class="fg">' + imgf('img.logo', 'लोगो की फ़ोटो', base ? base + 'assets/logo-mark.png' : '') + '</div></div>';
  var vid = shop ? '' : '<div class="card"><h2>🎬 होमपेज वीडियो</h2><p style="color:var(--mut);font-size:13px;margin:4px 0">वीडियो Cloudinary (या कहीं भी) पर अपलोड करके उसका <b>https://…mp4</b> लिंक डालें (1920×1080, 10–15 सेकंड, 6–10 MB सबसे अच्छा)। खाली = पुराना वीडियो चलेगा।</p><div class="fg">' + tf('site.video', 'होमपेज वीडियो का लिंक (.mp4)', { full: true, ph: 'https://…/video.mp4' }) + imgf('site.poster', 'वीडियो लोड होने से पहले की फ़ोटो (पोस्टर)', '') + '</div></div>';
  var n = mediaItems().length;
  return help((shop ? '<b>Shop पेज</b> की फ़ोटो बदलें' : '<b>वेबसाइट</b> की फ़ोटो, लोगो और होमपेज वीडियो बदलें') + ' — फ़ोटो अपलोड करें या https:// लिंक डालें। खाली छोड़ेंगे तो डिफ़ॉल्ट फ़ोटो रहेगी। ' + (shop ? 'वेबसाइट के बाकी पेज की फ़ोटो "Website Management → Website Media" में हैं।' : 'Shop पेज की फ़ोटो "Shop Page Management → Shop Media" में हैं।') + '<br>ℹ️ आइकन (छोटे चित्र) कोड के हिसाब से बने हैं, उन्हें बदला नहीं जा सकता।') + logo + vid +
    '<div class="card">' + (shop ? '' : '<div class="fg"><div class="fld"><label class="l">पेज चुनें</label><select class="inp" id="phPage">' + pageOpts() + '</select></div></div>') +
    (shop ? '<div id="mmLib">' + (window.SPMM ? SPMM.html(mediaItems()) : '') + '</div><p style="color:var(--mut);font-size:13px">' + (mediaItems().length ? 'ये Web Shop Page Builder के सेक्शन में लगी फ़ोटो/वीडियो हैं — यहीं से बदलें (Replace) या हटाएँ (Delete); नई जोड़ने के लिए Builder में ✏️ दबाएँ।' : 'Shop पेज की फ़ोटो/वीडियो Web Shop Page Builder के सेक्शन (✏️) से लगती हैं — अभी कोई नहीं लगी।') + '</p>' : pg && pg.imgs.length ? pg.imgs.map(function (im, i) { return imgf('img.' + im.k, 'फ़ोटो ' + (i + 1) + (im.alt ? ' — ' + im.alt : ''), base && !/^https?:/.test(im.src) ? base + im.src : im.src); }).join('') : '<p style="color:var(--mut)">इस पेज पर बदलने लायक फ़ोटो नहीं है।</p>') +
    '<div class="bar">' + saveBtn().replace(/^<div[^>]*>|<\/div>$/g, '') + '<button class="btn out" id="mdDl">⬇️ ' + (shop ? 'Shop' : 'Website') + ' मीडिया डाउनलोड (' + n + ')</button></div></div>' + (shop ? '' : '<div class="card"><h2>🗃️ वेबसाइट की सारी फ़ोटो / वीडियो — बदलें या हटाएँ</h2><div id="mmLib">' + (window.SPMM ? SPMM.html(mediaItems()) : '') + '</div></div>');
};
BIND.photos = function (m) {
  var ph = $('#phPage'); if (ph) ph.onchange = function () { collect(); PAGE = this.value; draw(); };
  var lib = $('#mmLib', m); if (lib && window.SPMM) { var li = mediaItems(); li.forEach(function (x) { x.save = x.save || function (msg) { collect(); return save(msg); }; }); SPMM.bind(lib, li, function () { draw(); }); }
  $('#mdDl').onclick = function () { collect(); A.downloadMedia(mediaItems(), SCOPE === 'shop' ? 'sunpowers-shop-media' : 'sunpowers-website-media'); };
  $('#wSave').onclick = function () {
    collect(); var bad = false;
    Object.keys(W.img).forEach(function (k) { var v = (W.img[k] || '').trim(); if (!v) delete W.img[k]; else if (!https(v)) bad = true; else W.img[k] = v; });
    ['video', 'poster'].forEach(function (k) { var v = String(W.site[k] || '').trim(); if (!v) delete W.site[k]; else if (!https(v)) bad = true; else W.site[k] = v; });
    if (bad) return toast('फ़ोटो / वीडियो का लिंक https:// से शुरू होना चाहिए (या फ़ोटो अपलोड करें)', true);
    save('✅ मीडिया सेव हो गया');
  };
};

/* ================= 4. store links ================= */
var SLUG_NAMES = { 'on-grid-solar': 'On-Grid Solar', 'off-grid-solar': 'Off-Grid Solar', 'hybrid-solar': 'Hybrid Solar', 'residential-solar': 'Residential Solar', 'commercial-solar': 'Commercial Solar', 'industrial-solar': 'Industrial Solar', 'vfd-solar': 'VFD Solar', 'solar-panel-cleaning': 'Solar Panel Cleaning', 'installation-shifting': 'Installation & Shifting', 'solar-maintenance-audit': 'Solar Maintenance & Audit', 'error-detector': 'Error Detector' };
VIEW.links = function () {
  var slugs = DEF().slugs.slice();
  return help('हर प्रोडक्ट / सर्विस पेज पर <b>"Go to Store"</b> बटन है। यहाँ उस बटन का असली स्टोर लिंक डालें। <b>खाली = स्टोर का सामान्य पेज।</b> आप पूरा https:// लिंक या स्टोर का रास्ता (जैसे <code>/?view=categories</code> या <code>/?p=P12</code>) लिख सकते हैं।') +
    '<div class="card"><div class="fg">' + tf('links.*', '⭐ सभी स्टोर बटन का साझा लिंक (जिनका अलग लिंक नहीं है)', { full: true, ph: 'खाली = डिफ़ॉल्ट' }) +
    slugs.map(function (s) { return tf('links.' + s, (SLUG_NAMES[s] || s) + ' — Go to Store', { ph: 'खाली = डिफ़ॉल्ट', full: true }); }).join('') + '</div>' + saveBtn() + '</div>';
};
BIND.links = function () {
  $('#wSave').onclick = function () {
    collect(); var bad = '';
    Object.keys(W.links).forEach(function (k) { var v = (W.links[k] || '').trim(); if (!v) { delete W.links[k]; return; } if (!/^https?:\/\//i.test(v) && v.charAt(0) !== '/') bad = k; else if (/^http:\/\//i.test(v) && !/^http:\/\/(127\.0\.0\.1|localhost)/i.test(v)) bad = k; W.links[k] = v; });
    if (bad) return toast('"' + (SLUG_NAMES[bad] || bad) + '": लिंक https:// से या / से शुरू होना चाहिए', true);
    save('✅ स्टोर लिंक सेव हो गए');
  };
};


/* ================= 4b. page banners (16:9: 1 video OR up to 5 photos + 2 buttons) and 4c. card links / media ================= */
var BN_KINDS = [['page', '🔗 वेबसाइट का पेज'], ['store', '🛒 ऑनलाइन स्टोर'], ['form', '📝 फ़ॉर्म पॉपअप'], ['wa', '💬 WhatsApp'], ['call', '📞 कॉल'], ['url', '🌍 कोई भी लिंक (https://)']];
var BN_HELP = { page: 'पेज का नाम, जैसे calculator.html', store: 'स्टोर का लिंक या खाली (= स्टोर होम)', form: 'फ़ॉर्म का नाम: Site survey / Installation / shifting / Solar panel cleaning / Solar quote', wa: 'WhatsApp पर पहले से लिखा संदेश', call: 'फ़ोन नंबर, जैसे 9621050636', url: 'https:// से शुरू होने वाला लिंक' };
var BNPG = '';
function pageName(stem) { var p = DEF().pages.filter(function (x) { return x.file === stem + '.html'; })[0]; return p ? p.en : stem; }
function videoField(p, label) {
  var v = val(p);
  return '<div class="fld full"><label class="l">' + esc(label) + '</label><div class="imgf"><div class="imgprev" data-vprev>' + (v ? '<video src="' + esc(v) + '" muted playsinline controls style="position:absolute;inset:0;width:100%;height:100%;object-fit:contain"></video>' : 'कोई वीडियो नहीं') + '</div>' +
    '<div class="imgbtns"><span class="btn sm upl"><b data-ul data-a="🎬 वीडियो अपलोड" data-b="🔄 वीडियो बदलें (Replace)">🎬 वीडियो अपलोड</b><input type="file" accept="video/mp4,video/webm" data-vup></span><button type="button" class="btn sm out" data-lnkf>🔗 लिंक से बदलें</button><button type="button" class="btn sm gray" data-clrvid data-del>🗑 हटाएँ (Delete)</button></div>' +
    '<input class="imgurl" type="text" data-p="' + esc(p) + '" data-vurl value="' + esc(v) + '" placeholder="या वीडियो का https:// लिंक (MP4) paste करें — भारी वीडियो के लिए Cloudinary आदि का लिंक"></div>' +
    '<small class="help">बेहतर: 16:9 वीडियो, 10–15 सेकंड, 6–10 MB (MP4). अपलोड की सीमा 50 MB है; उससे बड़ा हो तो लिंक paste करें. मोबाइल पर वीडियो बिना आवाज़ के अपने आप चलता है.</small></div>';
}
function mediaEditor(base, max) {
  var kind = val(base + '.kind', 'images'), h = sel(base + '.kind', 'क्या लगाना है?', [['images', '🖼️ फ़ोटो (1 से ' + max + ' तक — एक से ज़्यादा हों तो स्लाइडशो)'], ['video', '🎬 सिर्फ़ 1 वीडियो']], { full: true });
  if (kind === 'video') return h + videoField(base + '.urls.0', 'वीडियो');
  for (var i = 0; i < max; i++) h += imgf(base + '.urls.' + i, 'फ़ोटो ' + (i + 1) + (i ? ' (ज़रूरी नहीं)' : ''));
  return h;
}
function btnEditor(base, n) {
  var k = val(base + '.kind', 'page'), v = '<div class="card" style="margin:8px 0"><b>बटन ' + n + '</b> <small style="color:var(--mut)">(नाम खाली = बटन नहीं दिखेगा)</small><div class="fg">' +
    tf(base + '.label.en', 'बटन का नाम (English)', { max: 40 }) + tf(base + '.label.hi', 'बटन का नाम (हिंदी)', { max: 40 }) +
    sel(base + '.kind', 'क्लिक पर क्या हो?', BN_KINDS) +
    '<div class="fld"><label class="l">कहाँ जाए / क्या लिखा हो</label><input class="inp" type="text" data-p="' + esc(base + '.target') + '" value="' + esc(val(base + '.target')) + '"' + (k === 'page' ? ' list="bnPages"' : '') + '><small class="help">' + esc(BN_HELP[k] || '') + '</small></div></div></div>';
  return v;
}
VIEW.banners = function () {
  var pgs = DEF().bnpages || []; if (!pgs.length) return '<div class="note r">पेज की सूची नहीं मिली — cms-defaults.js जाँचें</div>';
  if (pgs.indexOf(BNPG) < 0) BNPG = pgs[0];
  var b = 'banners.' + BNPG, on = !!(getP(W, b + '.media.urls') || []).filter(Boolean).length;
  return help('होम पेज को छोड़कर हर पेज के हेडिंग के नीचे <b>16:9 का बैनर</b> लगा सकते हैं — <b>1 वीडियो</b> या <b>5 तक फ़ोटो</b> (एक से ज़्यादा फ़ोटो अपने आप स्लाइड होंगी), और साथ में <b>2 बटन</b> (पेज / स्टोर / फ़ॉर्म / WhatsApp / कॉल). कुछ न भरें तो बैनर दिखेगा ही नहीं और पेज पहले जैसा रहेगा.') +
    '<datalist id="bnPages">' + DEF().pages.map(function (p) { return '<option value="' + esc(p.file) + '">' + esc(p.en) + '</option>'; }).join('') + '</datalist>' +
    '<div class="card"><div class="fg"><div class="fld"><label class="l">पेज चुनें</label><select class="inp" id="bnPage">' + pgs.map(function (s) { return '<option value="' + esc(s) + '"' + (s === BNPG ? ' selected' : '') + '>' + esc(pageName(s)) + ' (' + esc(s) + '.html)' + (getP(W, 'banners.' + s + '.media.urls') && getP(W, 'banners.' + s + '.media.urls').filter(Boolean).length ? ' ✅' : '') + '</option>'; }).join('') + '</select></div></div>' +
    '<div style="margin:10px 0">' + chk(b + '.hide', 'इस पेज का बैनर छुपाएँ') + '</div><h3 style="margin:12px 0 4px">मीडिया <small style="font-weight:400">(खाली = डिफ़ॉल्ट Sunpowers बैनर)</small></h3><div class="fg">' + mediaEditor(b + '.media', 5) + '</div>' + btnEditor(b + '.btns.0', 1) + btnEditor(b + '.btns.1', 2) +
    saveBtn() + (on ? '<div class="bar"><button class="btn out" id="bnClear">🗑️ इस पेज का बैनर हटाएँ</button></div>' : '') + '</div>';
};
function tidyMedia(m) {
  if (!m || typeof m !== 'object') return null;
  var urls = (Array.isArray(m.urls) ? m.urls : []).map(function (u) { return String(u || '').trim(); }).filter(Boolean);
  if (m.kind === 'video') urls = urls.slice(0, 1); else urls = urls.slice(0, 5);
  return urls.length ? { kind: m.kind === 'video' ? 'video' : 'images', urls: urls } : null;
}
function badUrl(v) { return v && !https(v); }
function bindVideo(m) {
  m.addEventListener('click', function (e) { var b = e.target.closest('[data-clrvid]'); if (b) { var box = b.closest('.imgf'); $('[data-vurl]', box).value = ''; $('[data-vprev]', box).innerHTML = 'कोई वीडियो नहीं'; } });
  m.addEventListener('change', async function (e) {
    var f = e.target.closest('[data-vup]'); if (!f || !f.files[0]) return; var file = f.files[0]; f.value = '';
    var box = f.closest('.imgf'), pv = $('[data-vprev]', box); pv.innerHTML = '<span class="spin"></span>';
    try { var u = await A.uploadVideo(file); $('[data-vurl]', box).value = u; pv.innerHTML = '<video src="' + esc(u) + '" muted playsinline controls style="position:absolute;inset:0;width:100%;height:100%;object-fit:contain"></video>'; }
    catch (er) { pv.innerHTML = 'कोई वीडियो नहीं'; toast(er.message, true); }
  });
  m.addEventListener('input', function (e) { var i = e.target.closest('[data-vurl]'); if (i) { var pv = $('[data-vprev]', i.closest('.imgf')); pv.innerHTML = /^https?:\/\//i.test(i.value) ? '<video src="' + esc(i.value) + '" muted playsinline controls style="position:absolute;inset:0;width:100%;height:100%;object-fit:contain"></video>' : 'कोई वीडियो नहीं'; } });
}
function tidyBanners() {
  var bad = '';
    Object.keys(W.banners).forEach(function (s) {
      var b = W.banners[s], md = tidyMedia(b.media); if (md && md.urls.some(badUrl)) bad = pageName(s) + ': मीडिया का लिंक https:// से शुरू होना चाहिए';
      var bt = (Array.isArray(b.btns) ? b.btns : []).slice(0, 2).map(function (x) { x = x || {}; return { label: { en: ((x.label || {}).en || '').trim(), hi: ((x.label || {}).hi || '').trim() }, kind: x.kind || 'page', target: String(x.target || '').trim() }; });
      bt.forEach(function (x) { if ((x.label.en || x.label.hi) && x.kind === 'url' && x.target && !https(x.target)) bad = pageName(s) + ': बटन का लिंक https:// से शुरू होना चाहिए'; if ((x.label.en || x.label.hi) && x.kind === 'call' && !/\d{6,}/.test(x.target)) bad = pageName(s) + ': कॉल बटन में फ़ोन नंबर लिखें'; });
      var any = bt.some(function (x) { return x.label.en || x.label.hi; }), hd = b.hide === true; if (!md && !any && !hd) delete W.banners[s]; else { var o = { btns: any ? bt : [] }; if (md) o.media = md; if (hd) o.hide = true; W.banners[s] = o; }
    });
  return bad;
}
BIND.banners = function (m) {
  bindVideo(m);
  $('#bnPage').onchange = function () { collect(); BNPG = this.value; draw(); };
  m.addEventListener('change', function (e) { if (e.target.matches('select[data-p$=".kind"]')) { collect(); draw(); } });
  var cl = $('#bnClear'); if (cl) cl.onclick = async function () { if (await A.ask('इस पेज का बैनर हटाएँ?', 'हटाएँ', true)) { delete W.banners[BNPG]; draw(); save('✅ बैनर हटा दिया'); } };
  $('#wSave').onclick = function () {
    collect(); var bad = tidyBanners();
    if (bad) return toast(bad, true);
    save('✅ बैनर सेव हो गए').then(draw);
  };
};

var CARD_FIELDS = { project: [['a', '"See full info" बटन का लिंक', 'स्टोर पेज या कोई भी https:// लिंक'], ['b', '"See similar projects" बटन का लिंक', 'स्टोर पेज या कोई भी https:// लिंक']],
  brand: [['ds', 'Technical datasheet का लिंक', 'खाली = अभी जैसा WhatsApp पर पूछना'], ['res', '"Residential" बटन का लिंक', ''], ['com', '"Commercial" बटन का लिंक', '']] };
VIEW.cards = function () {
  var cards = DEF().cards || [], by = { project: [], brand: [], system: [], service: [] };
  cards.forEach(function (c) { (by[c.type] = by[c.type] || []).push(c); });
  function lf(c) { return (CARD_FIELDS[c.type] || []).map(function (f) { if (f[0] === 'ds') return pdfField('cards.' + c.key + '.links.ds', f[1], f[2]); return tf('cards.' + c.key + '.links.' + f[0], f[1], { ph: 'खाली = डिफ़ॉल्ट बटन रहेगा; - (डैश) लिखें तो बटन छुप जाएगा' + (f[2] ? ' (' + f[2] + ')' : ''), full: true }); }).join(''); }
  return help('<b>प्रोजेक्ट कार्ड:</b> "Ask about this project" जैसा है वैसा रहता है; दो और बटन — <b>See full info</b> और <b>See similar projects</b> — का लिंक यहाँ भरें (खाली = बटन नहीं दिखेगा). <b>ब्रांड कार्ड:</b> Technical datasheet, Residential, Commercial का लिंक. <b>सिस्टम / सर्विस कार्ड (On-Grid, Off-Grid, Hybrid…):</b> यहाँ फ़ोटो या वीडियो लगाएँ — लगाते ही कार्ड का छोटा टेक्स्ट हट जाता है और फ़ोटो/वीडियो दिखता है; "Go to Store" बटन का लिंक <b>🛒 स्टोर लिंक</b> टैब में है. बटन के नाम बदलना हो तो <b>📝 पेज का टेक्स्ट</b> टैब में बदलें.') +
    '<div class="card"><h2>🏗️ प्रोजेक्ट कार्ड</h2>' + by.project.map(function (c) { return '<div class="card" style="margin:8px 0"><b>' + esc(c.name) + '</b><div class="fg">' + lf(c) + '</div></div>'; }).join('') + '</div>' +
    '<div class="card"><h2>🏷️ ब्रांड कार्ड</h2>' + by.brand.map(function (c) { return '<div class="card" style="margin:8px 0"><b>' + esc(c.name) + '</b><div class="fg">' + lf(c) + '</div></div>'; }).join('') + '</div>' +
    '<div class="card"><h2>☀️ सिस्टम / सर्विस कार्ड (On-Grid, Off-Grid, Hybrid …) — फ़ोटो या वीडियो</h2><p class="hint">फ़ोटो/वीडियो लगाते ही कार्ड का डिफ़ॉल्ट चित्र बदल जाएगा। "Select project from store" बटन का लिंक <b>🛒 स्टोर लिंक</b> टैब में है।</p>' + by.system.concat(by.service).map(function (c) {
      return '<details class="card" style="margin:8px 0"' + ((getP(W, 'cards.' + c.key + '.media.urls') || []).filter(Boolean).length ? ' open' : '') + '><summary><b>' + esc(c.name) + '</b></summary><div class="fg" style="margin-top:8px">' + mediaEditor('cards.' + c.key + '.media', 5) + '</div></details>';
    }).join('') + '</div>' + saveBtn();
};
BIND.cards = function (m) {
  bindVideo(m); bindPdf(m);
  m.addEventListener('change', function (e) { if (e.target.matches('select[data-p$=".kind"]')) { collect(); draw(); } });
  $('#wSave').onclick = function () {
    collect(); var bad = '';
    Object.keys(W.cards).forEach(function (k) {
      var c = W.cards[k] || {}, L = {};
      Object.keys(c.links || {}).forEach(function (x) { var v = String(c.links[x] || '').trim(); if (!v) return; if (!/^https?:\/\//i.test(v) && v.charAt(0) !== '/' && !/^[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w\-]*)?$/i.test(v)) bad = k; else if (/^http:/i.test(v) && !/localhost|127\.0\.0\.1/.test(v)) bad = k; else L[x] = v; });
      var md = tidyMedia(c.media); if (md && md.urls.some(badUrl)) bad = k;
      var out = {}; if (Object.keys(L).length) out.links = L; if (md) out.media = md;
      if (Object.keys(out).length) W.cards[k] = out; else delete W.cards[k];
    });
    if (bad) { var nm = ((DEF().cards || []).filter(function (c) { return c.key === bad; })[0] || {}).name || bad; return toast('"' + nm + '": लिंक https:// से (या स्टोर के / से, या page.html) शुरू होना चाहिए', true); }
    save('✅ कार्ड सेव हो गए').then(draw);
  };
};

/* ================= 4b. cart sections (real store products on the website) ================= */
var STORE_SEC = null, STORE_LOADING = false, STORE_BLD = null, BLD_LOADING = false;
/* Round 22: sections placed on website pages from Web Shop / Store App Page Builder (read-only here: move + hide only) */
function loadBld() {
  if (STORE_BLD || BLD_LOADING || !A) return; BLD_LOADING = true;
  A.rpc('sp_get_store', {}).then(function (d) { STORE_BLD = (window.SPBLD && d && d.builder) ? SPBLD.norm(d.builder) : { web: {}, comps: {} }; }, function () { STORE_BLD = { web: {}, comps: {} }; })
    .then(function () { BLD_LOADING = false; if (TAB === 'wb') { var y = window.pageYOffset; draw(); try { window.scrollTo(0, y); } catch (e) {} } });
}
function bpList(f) { return STORE_BLD && STORE_BLD.web && window.SPBLD ? SPBLD.webList(STORE_BLD, f, true) : []; }
function bpOf(f, id) { var cid = String(id).slice(3); return bpList(f).filter(function (x) { return x.id === cid; })[0] || null; }
function loadStoreSecs() {
  if (STORE_SEC || STORE_LOADING) return; STORE_LOADING = true;
  A.rpc('sp_get_store', {}).then(function (d) { STORE_SEC = ((d && d.sections) || []).filter(function (x) { return x && x.id && x.kind !== 'update'; }).map(function (x) { return { id: x.id, name: x.titleEn || x.title || x.id }; }); }, function () { STORE_SEC = []; })
    .then(function () { STORE_LOADING = false; if (TAB === 'shop') { collect(); draw(); } });
}
VIEW.shop = function () {
  loadStoreSecs();
  var boxes = DEF().cartBoxes || [], groups = DEF().cartGroups || [];
  if (!boxes.length) return '<div class="note r">कार्ट सेक्शन की सूची नहीं मिली — cms-defaults.js (नया build) जाँचें</div>';
  var gname = {}; groups.forEach(function (g) { gname[g.key] = g; });
  var secOpts = [['', STORE_SEC ? '— अपने-आप (नाम/कीवर्ड से) —' : '… लोड हो रहा है …']].concat((STORE_SEC || []).map(function (x) { return [x.id, x.name]; }));
  var byPage = {}; boxes.forEach(function (b) { (byPage[b.page] = byPage[b.page] || []).push(b); });
  function box(b) {
    var k = 'shop.' + b.key, g = gname[b.group] || {};
    return '<details class="card" style="margin:8px 0"' + (getP(W, k) ? ' open' : '') + '><summary><b>' + esc(b.name) + '</b> <small class="mute">(' + esc(b.key) + ')</small>' + (getP(W, k + '.off') ? ' <span class="pill">छुपा</span>' : '') + '</summary><div class="fg" style="margin-top:8px">' +
      chk(k + '.off', 'यह कार्ट सेक्शन छुपाएँ') +
      tf(k + '.title.en', 'ऊपर का नाम (English)', { ph: g.en || '' }) + tf(k + '.title.hi', 'ऊपर का नाम (हिंदी)', { ph: g.hi || '' }) +
      sel(k + '.section', 'स्टोर का सेक्शन (कौन-से प्रोडक्ट दिखें)', secOpts, { full: true }) +
      tf(k + '.keywords', 'या कीवर्ड (| से अलग)', { ph: g.kw || '', full: true, h: 'सेक्शन न चुनें तो प्रोडक्ट के नाम/सेक्शन में ये शब्द ढूँढकर दिखाए जाते हैं' }) +
      tf(k + '.limit', 'कितने प्रोडक्ट दिखाएँ', { ph: '4' }) + tf(k + '.btn.en', 'बटन का नाम (English)', { ph: 'Add to cart' }) + tf(k + '.btn.hi', 'बटन का नाम (हिंदी)', { ph: 'कार्ट में जोड़ें' }) +
      tf(k + '.link', 'बटन का असली लिंक (स्टोर पेज)', { full: true, ph: 'खाली = कार्ट में जुड़ेगा, फिर स्टोर कार्ट पर जाएगा', h: 'लिंक भरते ही Add to cart बटन सीधे उस लिंक पर ले जाएगा। https://… या स्टोर का /?p={id} / /?s=सेक्शन-id' }) +
      tf(k + '.more', '"शॉप में सब देखें" का लिंक', { full: true, ph: 'खाली = shop.html' }) + '</div></details>';
  }
  return '<div class="card"><h2>🛍️ कार्ट सेक्शन (स्टोर के असली प्रोडक्ट)</h2><p class="hint">प्रोडक्ट स्टोर से ही आते हैं (वही दाम, वही स्टॉक, वही पिन कोड नियम)। किसी प्रोडक्ट को वेबसाइट पर न दिखाना हो तो Store Admin → प्रोडक्ट में "वेबसाइट शॉप में दिखाएँ" का टिक हटाएँ।</p></div>' +
    Object.keys(byPage).map(function (pg) { return '<div class="card"><h2>📄 ' + esc(pageName(pg === 'index' ? 'index' : pg)) + '</h2>' + byPage[pg].map(box).join('') + '</div>'; }).join('') + saveBtn();
};
BIND.shop = function () {
  $('#wSave').onclick = function () {
    collect(); var bad = '';
    Object.keys(W.shop).forEach(function (k) {
      var c = W.shop[k]; if (!c || typeof c !== 'object') { delete W.shop[k]; return; }
      ['title', 'btn'].forEach(function (f) { var o = c[f] || {}; var r = {}; if (o.en) r.en = o.en; if (o.hi) r.hi = o.hi; if (Object.keys(r).length) c[f] = r; else delete c[f]; });
      var n = parseInt(c.limit, 10); if (c.limit === '' || !n) delete c.limit; else c.limit = Math.max(1, Math.min(24, n));
      ['section', 'keywords', 'link', 'more'].forEach(function (f) { if (!String(c[f] || '').trim()) delete c[f]; else c[f] = String(c[f]).trim(); });
      ['link', 'more'].forEach(function (f) { var v = c[f]; if (v && !/^https?:\/\//i.test(v) && v.charAt(0) !== '/' && !/^[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w\-]*)?$/i.test(v)) bad = k; else if (v && /^http:/i.test(v) && !/localhost|127\.0\.0\.1/.test(v)) bad = k; });
      if (!c.off) delete c.off;
      if (!Object.keys(c).length) delete W.shop[k];
    });
    if (bad) return toast('"' + bad + '": लिंक https:// से (या स्टोर के / से, या page.html) शुरू होना चाहिए', true);
    save('✅ कार्ट सेक्शन सेव हो गए').then(draw);
  };
};

/* ================= 5. menu ================= */
function allPageChoices() {
  var out = DEF().pages.map(function (p) { return [p.file, p.file + ' — ' + p.en]; });
  W.pages.forEach(function (p) { if (p.slug) out.push(['page.html?s=' + p.slug, '📄 ' + (p.title && (p.title.en || p.title.hi) || p.slug)]); });
  return out;
}
VIEW.menu = function () {
  var M = W.menu, d = DEF().menu;
  return help('ऊपर के मेन्यू (और मोबाइल के मेन्यू) के नाम बदलें, कोई आइटम छुपाएँ, या अपना नया लिंक जोड़ें। (नया पेज बनाने के लिए "📄 नए पेज" टैब है।)') +
    '<div class="card"><h2>मेन्यू के आइटम</h2>' + d.map(function (m, i) {
      var hid = M.hide.indexOf(m.href) >= 0, nm = M.names[m.href] || {};
      return '<div class="row" style="flex-wrap:wrap;gap:8px;' + (hid ? 'opacity:.6' : '') + '"><div style="flex:1 1 100%"><b>' + esc(m.en) + '</b> <small style="color:var(--mut)">' + esc(m.href) + '</small></div>' +
        '<div style="flex:1 1 200px"><label class="l" style="font-size:12px">नया नाम (English)</label><input class="inp" type="text" data-mn="' + esc(m.href) + '" data-l="en" value="' + esc(nm.en || '') + '" placeholder="' + esc(m.en) + '"></div>' +
        '<div style="flex:1 1 200px"><label class="l" style="font-size:12px">नया नाम (हिंदी)</label><input class="inp" type="text" data-mn="' + esc(m.href) + '" data-l="hi" value="' + esc(nm.hi || '') + '" placeholder="हिंदी नाम"></div>' +
        (m.href === 'index.html' ? '' : '<label class="chk"><input type="checkbox" data-mh="' + esc(m.href) + '"' + (hid ? ' checked' : '') + '> छुपाएँ</label>') + '</div>';
    }).join('') + '</div>' +
    '<div class="card"><h2>➕ अपने नए लिंक</h2>' + (M.add.length ? M.add.map(function (a, i) {
      return '<div class="row" style="flex-wrap:wrap;gap:8px"><div style="flex:1 1 180px">' + tf('menu.add.' + i + '.label.en', 'नाम (English)', { max: 30 }) + '</div><div style="flex:1 1 180px">' + tf('menu.add.' + i + '.label.hi', 'नाम (हिंदी)', { max: 30 }) + '</div>' +
        '<div style="flex:1 1 240px">' + sel('menu.add.' + i + '.href', 'कहाँ खुले', allPageChoices()) + '</div><button class="ib" data-madel="' + i + '" title="हटाएँ">🗑</button></div>';
    }).join('') : '<p style="color:var(--mut)">अभी कोई नया लिंक नहीं।</p>') + '<div class="bar"><button class="btn out" id="maAdd">➕ नया लिंक जोड़ें</button></div></div>' + saveBtn();
};
function collectMenu(m) {
  $$('[data-mn]', m).forEach(function (el) { var h = el.getAttribute('data-mn'), l = el.getAttribute('data-l'); W.menu.names[h] = W.menu.names[h] || {}; W.menu.names[h][l] = el.value.trim(); });
  Object.keys(W.menu.names).forEach(function (h) { var n = W.menu.names[h]; if (!n.en && !n.hi) delete W.menu.names[h]; });
  W.menu.hide = $$('[data-mh]', m).filter(function (c) { return c.checked; }).map(function (c) { return c.getAttribute('data-mh'); });
  collect(m);
}
BIND.menu = function (m) {
  $('#maAdd').onclick = function () { collectMenu(m); W.menu.add.push({ label: { en: '', hi: '' }, href: 'services.html' }); draw(); };
  m.addEventListener('click', function (e) { var b = e.target.closest('[data-madel]'); if (b) { collectMenu(m); W.menu.add.splice(+b.getAttribute('data-madel'), 1); draw(); } });
  $('#wSave').onclick = function () { collectMenu(m); W.menu.add = W.menu.add.filter(function (a) { return a.label && (a.label.en || a.label.hi); }); save('✅ मेन्यू सेव हो गया'); };
};

/* ================= block editor (extra pages + extra home sections) ================= */
var BT = [['h', '🔤 हेडिंग'], ['p', '📃 पैराग्राफ'], ['list', '✅ पॉइंट्स की लिस्ट'], ['img', '🖼️ फ़ोटो'], ['cards', '🗂️ कार्ड्स'], ['btn', '🔘 बटन'], ['slides', '🎞️ स्लाइडशो'], ['video', '🎬 वीडियो'], ['yt', '▶️ YouTube']];
var BKINDS = [['link', '🔗 पेज / लिंक'], ['store', '🛒 स्टोर'], ['form', '📝 फ़ॉर्म पॉपअप'], ['wa', '💬 WhatsApp']];
function blocksEditor(base) {
  var arr = getP(W, base) || [];
  return arr.map(function (b, i) {
    var p = base + '.' + i, h = '';
    if (b.t === 'h') h = '<div class="fg">' + tf(p + '.en', 'हेडिंग (English)') + tf(p + '.hi', 'हेडिंग (हिंदी)') + '</div>';
    else if (b.t === 'p' || b.t === 'list') h = '<div class="fg">' + tf(p + '.en', (b.t === 'list' ? 'पॉइंट्स (English) — हर लाइन एक पॉइंट' : 'पैराग्राफ (English)'), { area: 1, rows: 4, full: true }) + tf(p + '.hi', (b.t === 'list' ? 'पॉइंट्स (हिंदी)' : 'पैराग्राफ (हिंदी)'), { area: 1, rows: 4, full: true }) + '</div>';
    else if (b.t === 'img') h = '<div class="fg">' + imgf(p + '.src', 'फ़ोटो') + tf(p + '.alt.en', 'फ़ोटो का नाम (English)') + tf(p + '.alt.hi', 'फ़ोटो का नाम (हिंदी)') + '</div>';
    else if (b.t === 'slides') { h = '<div class="fg">'; for (var si = 0; si < 6; si++) h += imgf(p + '.urls.' + si, 'फ़ोटो ' + (si + 1) + (si ? ' (ज़रूरी नहीं)' : '') + ' — 2 या ज़्यादा हों तो स्लाइडशो'); h += '</div>'; }
    else if (b.t === 'video') h = '<div class="fg">' + videoField(p + '.urls.0', 'वीडियो (16:9)') + '</div>';
    else if (b.t === 'yt') h = '<div class="fg">' + tf(p + '.url', 'YouTube वीडियो का लिंक', { full: true, ph: 'https://www.youtube.com/watch?v=…  या  https://youtu.be/…' }) + '</div>';
    else if (b.t === 'btn') h = '<div class="fg">' + tf(p + '.label.en', 'बटन का नाम (English)') + tf(p + '.label.hi', 'बटन का नाम (हिंदी)') + sel(p + '.kind', 'क्लिक पर क्या हो?', BKINDS) + tf(p + '.target', 'कहाँ / क्या', { ph: 'पेज: calculator.html • स्टोर: /?view=categories • फ़ॉर्म: Site survey • WhatsApp: मैसेज' }) + '</div>';
    else if (b.t === 'cards') h = (b.items || []).map(function (c, j) {
      var q = p + '.items.' + j;
      return '<div class="row" style="flex-wrap:wrap;gap:8px;background:#f6f9f6"><b style="flex:1 1 100%">कार्ड ' + (j + 1) + ' <button class="ib" data-cdel="' + esc(p) + '|' + j + '" title="कार्ड हटाएँ">🗑</button></b><div class="fg" style="width:100%">' + tf(q + '.title.en', 'टाइटल (English)') + tf(q + '.title.hi', 'टाइटल (हिंदी)') + tf(q + '.text.en', 'टेक्स्ट (English)', { area: 1 }) + tf(q + '.text.hi', 'टेक्स्ट (हिंदी)', { area: 1 }) + imgf(q + '.img', 'फ़ोटो (वैकल्पिक)') + '</div></div>';
    }).join('') + '<div class="bar"><button class="btn sm out" data-cadd="' + esc(p) + '">➕ कार्ड जोड़ें</button></div>';
    return '<div class="card" style="background:#fbfdfb"><div style="display:flex;justify-content:space-between;align-items:center;gap:8px"><b>' + esc((BT.filter(function (x) { return x[0] === b.t; })[0] || ['', b.t])[1]) + '</b><span class="acts"><button class="ib" data-bmv="' + esc(base) + '|' + i + '|-1"' + (i === 0 ? ' disabled' : '') + '>⬆️</button><button class="ib" data-bmv="' + esc(base) + '|' + i + '|1"' + (i === arr.length - 1 ? ' disabled' : '') + '>⬇️</button><button class="ib" data-bdel="' + esc(base) + '|' + i + '">🗑</button></span></div>' + h + '</div>';
  }).join('') + '<div class="bar">' + BT.map(function (t) { return '<button class="btn sm out" data-badd="' + esc(base) + '|' + t[0] + '">➕ ' + esc(t[1]) + '</button>'; }).join('') + '</div>';
}
function newBlock(t) {
  if (t === 'h' || t === 'p' || t === 'list') return { t: t, en: '', hi: '' };
  if (t === 'img') return { t: t, src: '', alt: { en: '', hi: '' } };
  if (t === 'slides') return { t: t, urls: [] };
  if (t === 'video') return { t: t, urls: [''] };
  if (t === 'yt') return { t: t, url: '' };
  if (t === 'btn') return { t: t, label: { en: 'Know more', hi: 'और जानें' }, kind: 'link', target: '' };
  return { t: 'cards', items: [{ title: { en: '', hi: '' }, text: { en: '', hi: '' }, img: '' }] };
}
function bindBlocks(m, redraw) {
  bindVideo(m);
  m.addEventListener('click', async function (e) {
    var b;
    if ((b = e.target.closest('[data-badd]'))) { collect(m); var x = b.getAttribute('data-badd').split('|'); var arr = getP(W, x[0]); if (!Array.isArray(arr)) { setP(W, x[0], []); arr = getP(W, x[0]); } arr.push(newBlock(x[1])); redraw(); }
    else if ((b = e.target.closest('[data-bdel]'))) { collect(m); var y = b.getAttribute('data-bdel').split('|'); if (await A.ask('यह हिस्सा हटाएँ?', 'हटाएँ', true)) { getP(W, y[0]).splice(+y[1], 1); redraw(); } }
    else if ((b = e.target.closest('[data-bmv]'))) { collect(m); var z = b.getAttribute('data-bmv').split('|'); if (mv(getP(W, z[0]), +z[1], +z[2])) redraw(); }
    else if ((b = e.target.closest('[data-cadd]'))) { collect(m); var bl = getP(W, b.getAttribute('data-cadd')); bl.items = bl.items || []; bl.items.push({ title: { en: '', hi: '' }, text: { en: '', hi: '' }, img: '' }); redraw(); }
    else if ((b = e.target.closest('[data-cdel]'))) { collect(m); var c = b.getAttribute('data-cdel').split('|'); getP(W, c[0]).items.splice(+c[1], 1); redraw(); }
  });
}
function cleanBlocks(blocks) {
  var bad = '';
  (blocks || []).forEach(function (b) {
    if (b.t === 'img' && b.src && !https(b.src)) bad = 'फ़ोटो का लिंक https:// से शुरू होना चाहिए';
    if ((b.t === 'slides' || b.t === 'video') && (b.urls || []).some(function (u) { return u && !https(u); })) bad = 'फ़ोटो / वीडियो का लिंक https:// से शुरू होना चाहिए';
    if (b.t === 'yt' && b.url && !/(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)[\w-]{11}/.test(b.url)) bad = 'YouTube का सही लिंक डालें (youtube.com/watch?v=… या youtu.be/…)';
    if (b.t === 'cards') (b.items || []).forEach(function (c) { if (c.img && !https(c.img)) bad = 'कार्ड की फ़ोटो का लिंक https:// से शुरू होना चाहिए'; });
    if (b.t === 'btn' && b.kind === 'link' && b.target && !/^([a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?|page\.html\?s=[a-z0-9\-]+|https?:\/\/\S+|tel:\S+|mailto:\S+)$/i.test(b.target)) bad = 'बटन का लिंक सही नहीं: ' + b.target;
    if (b.t === 'btn' && b.kind === 'store' && b.target && !(b.target.charAt(0) === '/' || /^https:\/\//i.test(b.target))) bad = 'स्टोर लिंक / या https:// से शुरू करें';
  });
  return bad;
}

/* ================= 6. sections + buttons of EVERY page (home included) ================= */
/* Home keeps its data in W.home; every other page in W.pg[<file without .html>]. Same shape for both:
   { order:[ids], hide:[ids], show:[ids], del:[ids], extra:[{after, dark, blocks}], btn:{ <bid>:{ text:{en,hi}, href, hide } } }   */
var SECPG = 'index.html';
function SECS() { return window.CMS_SECS || {}; }
function pgBase(f) { return f === 'index.html' ? 'home' : 'pg.' + f.replace(/\.html$/, ''); }
function pgObj(f) {
  var o; if (f === 'index.html') o = W.home; else { W.pg = W.pg || {}; var k = f.replace(/\.html$/, ''); o = W.pg[k] = W.pg[k] || {}; }
  ['order', 'hide', 'show', 'del', 'extra', 'dup'].forEach(function (x) { if (!Array.isArray(o[x])) o[x] = []; });
  if (!o.btn || typeof o.btn !== 'object' || Array.isArray(o.btn)) o.btn = {}; return o;
}
function pgMan(f) { return SECS()[f] || { title: f, secs: [], btns: [] }; }
function ordIds(f) { var M = pgMan(f), ids = M.secs.map(function (x) { return x.id; }), o = pgObj(f).order.filter(function (i) { return ids.indexOf(i) >= 0; }); ids.forEach(function (i) { if (o.indexOf(i) < 0) o.push(i); }); return o; }
function secsHtml(f, picker) {
  var M = pgMan(f), P = pgObj(f), base = pgBase(f), order = ordIds(f), lab = {}; M.secs.forEach(function (x) { lab[x.id] = x.label; });
  var live = order.filter(function (id) { return P.del.indexOf(id) < 0; }), gone = order.filter(function (id) { return P.del.indexOf(id) >= 0; });
  var pick = picker ? '<div class="card"><h2>📄 कौन-सा पेज?</h2><select class="inp" id="secPg">' + Object.keys(SECS()).sort().map(function (k) { return '<option value="' + esc(k) + '"' + (k === f ? ' selected' : '') + '>' + esc(SECS()[k].title) + ' — ' + esc(k) + '</option>'; }).join('') + '</select><p style="margin-top:8px"><a class="btn sm out" target="_blank" rel="noopener" href="' + esc(siteBase() + (f === 'index.html' ? '' : f)) + '">👁 यह पेज देखें</a></p></div>' : '';
  var rows = live.map(function (id, i) {
    var hid = P.hide.indexOf(id) >= 0;
    return '<div class="row' + (hid ? ' dim' : '') + '"><div class="th" style="font-weight:800">' + (i + 1) + '</div><div class="rm"><b>' + esc(lab[id] || id) + '</b> <small>#' + esc(id) + '</small>' + (hid ? ' <span class="tag">छुपा है</span>' : '') + '</div><div class="acts">' +
      '<button class="ib" data-hmv="' + i + '" data-d="-1"' + (i === 0 ? ' disabled' : '') + ' title="ऊपर">⬆️</button><button class="ib" data-hmv="' + i + '" data-d="1"' + (i === live.length - 1 ? ' disabled' : '') + ' title="नीचे">⬇️</button>' +
      '<button class="ib" data-hhd="' + esc(id) + '" title="' + (hid ? 'दिखाएँ' : 'छुपाएँ') + '">' + (hid ? '🙈' : '👁') + '</button><button class="ib" data-hdel="' + esc(id) + '" title="हटाएँ">🗑</button></div></div>';
  }).join('');
  var gonehtml = gone.length ? '<details style="margin-top:10px"><summary style="cursor:pointer;font-weight:700">🗑 हटाए हुए सेक्शन (' + gone.length + ') — वापस ला सकते हैं</summary>' + gone.map(function (id) { return '<div class="row dim"><div class="rm"><b>' + esc(lab[id] || id) + '</b> <small>#' + esc(id) + '</small></div><div class="acts"><button class="btn sm out" data-hres="' + esc(id) + '">♻️ वापस लाएँ</button></div></div>'; }).join('') + '</details>' : '';
  var after = [['', 'सबसे नीचे']].concat(live.map(function (id) { return [id, 'इसके बाद: ' + (lab[id] || id)]; }));
  var extras = P.extra.length ? P.extra.map(function (x, i) {
    return '<div class="card" style="border:1px dashed #b9cdb9"><div style="display:flex;justify-content:space-between;align-items:center;gap:8px"><b>नया सेक्शन ' + (i + 1) + '</b><span class="acts"><button class="ib" data-hxhd="' + i + '" title="' + (x.hide ? 'दिखाएँ' : 'छुपाएँ') + '">' + (x.hide ? '🙈' : '👁') + '</button><button class="ib" data-hxdel="' + i + '" title="पूरा सेक्शन हटाएँ">🗑</button></span></div>' +
      '<div class="fg">' + sel(base + '.extra.' + i + '.after', 'कहाँ दिखे?', after, { full: true }) + '</div>' + chk(base + '.extra.' + i + '.dark', 'गहरे (dark) बैकग्राउंड में दिखाएँ') + blocksEditor(base + '.extra.' + i + '.blocks') + '</div>';
  }).join('') : '<p style="color:var(--mut)">अभी कोई नया सेक्शन नहीं।</p>';
  var btns = M.btns.length ? M.btns.map(function (b) {
    var o = P.btn[b.id] || {}, q = base + '.btn.' + b.id;
    return '<details class="row' + (o.hide ? ' dim' : '') + '" style="display:block"><summary style="cursor:pointer;display:flex;gap:8px;align-items:center"><b style="flex:1;min-width:0">' + esc(b.label) + '</b><small style="color:var(--mut)">' + esc(b.href.slice(0, 40)) + '</small>' + (o.hide ? '<span class="tag">छुपा</span>' : (o.text || o.href ? '<span class="tag">बदला</span>' : '')) + '</summary>' +
      '<div class="fg" style="margin-top:8px">' + tf(q + '.text.en', 'नया नाम (English) — खाली = जैसा है', { max: 40 }) + tf(q + '.text.hi', 'नया नाम (हिंदी)', { max: 40 }) + tf(q + '.href', 'नया लिंक (खाली = जैसा है)', { ph: b.href, full: true }) + '</div>' +
      '<label class="chk"><input type="checkbox" data-bhd="' + esc(b.id) + '"' + (o.hide ? ' checked' : '') + '> इस बटन को छुपाएँ</label></details>';
  }).join('') : '<p style="color:var(--mut)">इस पेज में अलग से बटन नहीं हैं।</p>';
  return pick + '<div class="card"><h2>🧩 सेक्शन — क्रम, छुपाना, हटाना (' + live.length + ')</h2>' + (rows || '<p style="color:var(--mut)">कोई सेक्शन नहीं</p>') + gonehtml + '</div>' +
    '<div class="card"><h2>➕ अपने नए सेक्शन</h2>' + extras + '<div class="bar"><button class="btn out" id="hxAdd">➕ नया सेक्शन जोड़ें</button></div></div>' +
    '<div class="card"><h2>🔘 बटन — नाम, लिंक, छुपाना (' + M.btns.length + ')</h2><p style="color:var(--mut);font-size:13px;margin-bottom:8px">किसी बटन पर टैप करके उसका नाम / लिंक बदलें या उसे छुपाएँ। (हेडर-फुटर के लिंक "🧭 मेन्यू" से बदलते हैं।)</p>' + btns + '</div>' + saveBtn();
}
function bindSecs(m, getF) {
  function redraw() { draw(); }
  var pg = $('#secPg'); if (pg) pg.onchange = function () { collect(m); SECPG = pg.value; draw(); };
  $('#hxAdd').onclick = function () { collect(m); pgObj(getF()).extra.push({ after: '', blocks: [{ t: 'h', en: '', hi: '' }, { t: 'p', en: '', hi: '' }] }); redraw(); };
  m.addEventListener('click', async function (e) {
    var b, f = getF(), P = pgObj(f);
    if ((b = e.target.closest('[data-hmv]'))) {
      collect(m); var order = ordIds(f), live = order.filter(function (id) { return P.del.indexOf(id) < 0; });
      if (mv(live, +b.getAttribute('data-hmv'), +b.getAttribute('data-d'))) { var k = 0; P.order = order.map(function (id) { return P.del.indexOf(id) < 0 ? live[k++] : id; }); redraw(); }
    }
    else if ((b = e.target.closest('[data-hhd]'))) { collect(m); var id = b.getAttribute('data-hhd'), i = P.hide.indexOf(id); if (i >= 0) { P.hide.splice(i, 1); P.show.push(id); } else { P.hide.push(id); P.show = P.show.filter(function (x) { return x !== id; }); } redraw(); }
    else if ((b = e.target.closest('[data-hdel]'))) { collect(m); var di = b.getAttribute('data-hdel'); if (await A.ask('यह सेक्शन वेबसाइट से हटाएँ? (बाद में "हटाए हुए" से वापस ला सकते हैं)', 'हटाएँ', true)) { if (P.del.indexOf(di) < 0) P.del.push(di); redraw(); } }
    else if ((b = e.target.closest('[data-hres]'))) { collect(m); P.del = P.del.filter(function (x) { return x !== b.getAttribute('data-hres'); }); redraw(); }
    else if ((b = e.target.closest('[data-hxdel]'))) { collect(m); if (await A.ask('यह पूरा सेक्शन हटाएँ?', 'हटाएँ', true)) { P.extra.splice(+b.getAttribute('data-hxdel'), 1); redraw(); } }
    else if ((b = e.target.closest('[data-hxhd]'))) { collect(m); var x = P.extra[+b.getAttribute('data-hxhd')]; if (x) x.hide = !x.hide; redraw(); }
  });
  m.addEventListener('change', function (e) { var c = e.target.closest('[data-bhd]'); if (c) { var P = pgObj(getF()), id = c.getAttribute('data-bhd'); P.btn[id] = P.btn[id] || {}; P.btn[id].hide = c.checked; } });
  bindBlocks(m, redraw);
  $('#wSave').onclick = function () {
    collect(m); var f = getF(), P = pgObj(f), bad = ''; P.extra.forEach(function (x) { bad = bad || cleanBlocks(x.blocks); });
    Object.keys(P.btn).forEach(function (k) { var o = P.btn[k]; if (o.href && !/^(https?:\/\/\S+|tel:\S+|mailto:\S+|#[\w-]+|[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w-]+)?)$/i.test(o.href)) bad = bad || 'बटन का लिंक सही नहीं: ' + o.href; if (!o.hide && !(o.text && (o.text.en || o.text.hi)) && !o.href) delete P.btn[k]; });
    if (bad) return toast(bad, true);
    P.order = ordIds(f); save('✅ पेज के सेक्शन व बटन सेव हो गए');
  };
}

/* ================= 7. new pages ================= */
function slugify(s) { return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40); }
var CUR_PG = -1;
VIEW.pages = function () {
  var P = W.pages;
  if (CUR_PG >= 0 && P[CUR_PG]) {
    var p = P[CUR_PG], i = CUR_PG, link = (siteBase() || '') + 'page.html?s=' + (p.slug || '');
    return '<div class="bar"><button class="btn out" id="pgBack">← सारे पेज</button></div><div class="card"><h2>📄 ' + esc((p.title && (p.title.en || p.title.hi)) || 'नया पेज') + '</h2><div class="fg">' +
      tf('pages.' + i + '.title.en', 'पेज का टाइटल (English)', { max: 70 }) + tf('pages.' + i + '.title.hi', 'पेज का टाइटल (हिंदी)', { max: 70 }) +
      tf('pages.' + i + '.slug', 'पेज का पता (सिर्फ़ a-z, 0-9, -)', { max: 40, h: 'लिंक बनेगा: <code>page.html?s=' + esc(p.slug || '…') + '</code>' }) + tf('pages.' + i + '.sub.en', 'टाइटल के नीचे की लाइन (English)') + tf('pages.' + i + '.sub.hi', 'टाइटल के नीचे की लाइन (हिंदी)') +
      tf('pages.' + i + '.desc.en', 'Google के लिए छोटा विवरण (English)', { area: 1, full: true }) + '</div>' + chk('pages.' + i + '.hide', 'यह पेज बंद रखें (छुपाएँ)') +
      '<p style="font-size:13px;color:var(--mut);margin-top:6px">ℹ️ अपने बनाए पेज सीधे खुलते हैं और काम करते हैं, पर Google में इनका दिखना पक्का नहीं (वह सिर्फ़ मुख्य पेजों का पक्का है)।</p></div>' +
      '<div class="card"><h2>पेज की सामग्री</h2>' + blocksEditor('pages.' + i + '.blocks') + '</div>' + saveBtn('wSave', 'पेज सेव करें') + (p.slug ? '<p style="margin-top:10px"><a class="btn sm out" target="_blank" rel="noopener" href="' + esc(link) + '">👁 पेज देखें</a></p>' : '');
  }
  return help('अपने नए पेज बनाएँ — हेडिंग, पैराग्राफ, फ़ोटो, कार्ड्स, बटन जोड़कर। बनाने के बाद "🧭 मेन्यू" से उसका लिंक मेन्यू में जोड़ सकते हैं, या किसी स्लाइड/बटन में उसका पता (<code>page.html?s=…</code>) डाल सकते हैं।') +
    '<div class="bar"><button class="btn" id="pgNew">➕ नया पेज बनाएँ</button></div>' + (P.length ? P.map(function (p, i) {
      return '<div class="row' + (p.hide ? ' dim' : '') + '"><div class="th">📄</div><div class="rm"><b>' + esc((p.title && (p.title.en || p.title.hi)) || '(बिना नाम)') + '</b><small>page.html?s=' + esc(p.slug || '') + (p.hide ? ' • छुपा' : '') + '</small></div><div class="acts"><button class="ib" data-pge="' + i + '" title="एडिट">✏️</button><button class="ib" data-pgd="' + i + '" title="हटाएँ">🗑</button></div></div>';
    }).join('') : '<p style="color:var(--mut)">अभी कोई नया पेज नहीं बना।</p>');
};
BIND.pages = function (m) {
  var nw = $('#pgNew'); if (nw) nw.onclick = function () { W.pages.push({ slug: '', title: { en: '', hi: '' }, sub: { en: '', hi: '' }, desc: { en: '' }, blocks: [{ t: 'h', en: '', hi: '' }, { t: 'p', en: '', hi: '' }] }); CUR_PG = W.pages.length - 1; draw(); };
  var bk = $('#pgBack'); if (bk) bk.onclick = function () { collect(m); CUR_PG = -1; draw(); };
  m.addEventListener('click', async function (e) {
    var b;
    if ((b = e.target.closest('[data-pge]'))) { CUR_PG = +b.getAttribute('data-pge'); draw(); }
    else if ((b = e.target.closest('[data-pgd]'))) { var i = +b.getAttribute('data-pgd'); if (await A.ask('यह पेज हमेशा के लिए हटाएँ?', 'हटाएँ', true)) { var sl = W.pages[i].slug; W.pages.splice(i, 1); W.menu.add = W.menu.add.filter(function (a) { return a.href !== 'page.html?s=' + sl; }); draw(); save('🗑 पेज हट गया'); } }
  });
  bindBlocks(m, draw);
  var sv = $('#wSave'); if (sv) sv.onclick = function () {
    collect(m); var p = W.pages[CUR_PG]; if (!p) return;
    if (!p.slug) p.slug = slugify(p.title && p.title.en); p.slug = slugify(p.slug);
    if (!(p.title && (p.title.en || p.title.hi))) return toast('पेज का टाइटल लिखें', true);
    if (!p.slug) return toast('पेज का पता (अंग्रेज़ी अक्षरों में) लिखें', true);
    if (W.pages.some(function (x, i) { return i !== CUR_PG && x.slug === p.slug; })) return toast('यह पता पहले से किसी पेज का है — दूसरा लिखें', true);
    var bad = cleanBlocks(p.blocks); if (bad) return toast(bad, true);
    save('✅ पेज सेव हो गया'); draw();
  };
};

/* ================= 8. rating + social + store info ================= */
VIEW.site = function () {
  return help('Google रेटिंग यहाँ <b>हाथ से</b> अपडेट होती है (Google से अपने आप नहीं आती) — असली रेटिंग और रिव्यू की संख्या ही लिखें।') +
    '<div class="card"><h2>⭐ Google रेटिंग</h2><div class="fg">' + tf('site.rating.value', 'रेटिंग (जैसे 5.0)', { max: 4 }) + tf('site.rating.count', 'कुल रिव्यू (जैसे 17)', { max: 6 }) + tf('site.rating.url', 'रिव्यू का लिंक (Google Maps)', { full: true, ph: 'https://…' }) + '</div></div>' +
    '<div class="card"><h2>🔗 सोशल लिंक</h2><div class="fg">' + tf('site.social.youtube', 'YouTube', { ph: 'https://…' }) + tf('site.social.instagram', 'Instagram', { ph: 'https://…' }) + tf('site.social.facebook', 'Facebook', { ph: 'https://…' }) + tf('site.social.gmb', 'Google Business / Maps', { ph: 'https://…' }) + '</div></div>' +
    '<div class="card"><h2>📲 ऐप डाउनलोड लिंक</h2>' + help('ऐप जब Play Store / App Store पर लाइव हो जाए तब यहाँ लिंक डालें — वेबसाइट का <b>"App · Coming soon"</b> बटन अपने आप <b>"Download App"</b> बन जाएगा। Android फ़ोन वाले Play Store पर और iPhone वाले App Store पर अपने आप जाएँगे। दोनों खाली = "Coming soon" दिखता रहेगा। सिर्फ़ एक भरा हो तो सब उसी पर जाएँगे।') + '<div class="fg">' + tf('site.app.android', 'Play Store (Android) लिंक', { full: true, ph: 'https://play.google.com/store/apps/details?id=…' }) + tf('site.app.ios', 'App Store (iPhone) लिंक', { full: true, ph: 'https://apps.apple.com/…' }) + '</div></div>' +
    '<div class="card"><h2>🏪 About पेज — स्टोर की जानकारी</h2><div class="fg">' + tf('site.storeInfo.en', 'English (हर लाइन अलग बात)', { area: 1, rows: 5, full: true }) + tf('site.storeInfo.hi', 'हिंदी', { area: 1, rows: 5, full: true }) + '</div></div>' + saveBtn();
};
BIND.site = function () {
  $('#wSave').onclick = function () {
    collect(); var S = W.site, r = S.rating;
    if (r.value && !/^\d(\.\d)?$/.test(r.value)) return toast('रेटिंग 4.8 या 5.0 जैसी लिखें', true);
    if (r.count && !/^\d{1,6}$/.test(r.count)) return toast('रिव्यू की संख्या अंकों में लिखें', true);
    var bad = ['url'].some(function (k) { return r[k] && !https(r[k]); }) || Object.keys(S.social).some(function (k) { return S.social[k] && !https(S.social[k]); }) || ['android', 'ios'].some(function (k) { return S.app[k] && !https(S.app[k]); });
    if (bad) return toast('लिंक https:// से शुरू होने चाहिए', true);
    save('✅ सेव हो गया');
  };
};

/* ================= Round 18: 🧱 Website Builder ================= */
/* One screen for the whole website: pick a page → list of its components (every section already on the page + your new
   slideshow / video / YouTube / text sections). Edit words, photos, videos and buttons, reorder, hide, delete, DUPLICATE,
   and watch a live preview at the bottom. Data = the same W.* fields the website already reads (text, img, pg/home → order, hide,
   del, extra, btn) plus  dup:[{id,src}]  for copies of built-in sections (their own text/photos/buttons use the key "<id>~<key>"). */
var WB_PG = 'index.html', WB_EDIT = '', WB_REV = 0, WB_DEV = 'm', WB_FRAME = null;
function wbClone(o) { return JSON.parse(JSON.stringify(o)); }
function wbFiles() { var k = Object.keys(SECS()); k.sort(function (a, b) { return a === 'index.html' ? -1 : b === 'index.html' ? 1 : (SECS()[a].title || a).localeCompare(SECS()[b].title || b); }); return k; }
function wbMan(f) { return MAN().filter(function (p) { return p.file === f; })[0] || { texts: [], imgs: [] }; }
function wbRec(f, id) { return pgMan(f).secs.filter(function (x) { return x.id === id; })[0] || { id: id, label: id, t: [], i: [], b: [] }; }
function wbUsed(P, f) { var u = {}; pgMan(f).secs.forEach(function (x) { u[x.id] = 1; }); P.dup.forEach(function (d) { u[d.id] = 1; }); P.extra.forEach(function (x) { if (x.id) u[x.id] = 1; }); return u; }
function wbNewId(P, f, pre) { var u = wbUsed(P, f), n = 1; while (u[pre + n]) n++; return pre + n; }
function wbPrep(f) {
  var P = pgObj(f); P.extra.forEach(function (x, i) { if (!x.id) x.id = wbNewId(P, f, 'x'); }); return P;
}
/* complete order: built-in + copies + new sections, copies/new ones sit after the section they belong to */
function wbOrder(f) {
  var P = wbPrep(f), ids = pgMan(f).secs.map(function (x) { return x.id; }), anchor = {}, all = ids.slice();
  P.dup.forEach(function (d) { all.push(d.id); anchor[d.id] = d.src; }); P.extra.forEach(function (x) { all.push(x.id); if (x.after) anchor[x.id] = x.after; });
  var bpPos = {}; bpList(f).forEach(function (x) { var id = 'bp_' + x.id; all.push(id); bpPos[id] = x; });
  var out = [];
  P.order.forEach(function (i) { if (all.indexOf(i) >= 0 && out.indexOf(i) < 0) out.push(i); });
  ids.forEach(function (i) { if (out.indexOf(i) < 0) out.push(i); });
  all.forEach(function (i) {
    if (out.indexOf(i) >= 0) return;
    if (bpPos[i]) { var b = bpPos[i], q = b.ref ? out.indexOf(b.ref) : -1; if (b.pos === 'top') out.unshift(i); else if (q >= 0) out.splice(b.pos === 'above' ? q : q + 1, 0, i); else out.push(i); return; }
    var p = anchor[i] ? out.indexOf(anchor[i]) : -1; if (p >= 0) out.splice(p + 1, 0, i); else out.push(i);
  });
  return out;
}
function wbItems(f) {
  var P = wbPrep(f), dup = {}, ex = {}; P.dup.forEach(function (d) { dup[d.id] = d; }); P.extra.forEach(function (x, i) { ex[x.id] = { x: x, i: i }; });
  return wbOrder(f).map(function (id) {
    if (id.indexOf('bp_') === 0 && bpOf(f, id)) return { id: id, k: 'bp', gone: false };
    if (dup[id]) return { id: id, k: 'dup', src: dup[id].src, gone: P.del.indexOf(id) >= 0 };
    if (ex[id]) return { id: id, k: 'x', i: ex[id].i, gone: false };
    return { id: id, k: 'sec', gone: P.del.indexOf(id) >= 0 };
  });
}
function bpStore(f, it) { var x = bpOf(f, it.id); return !!(x && x.comp.pages.store && !x.comp.pages.shop); }
function wbTitle(f, it) {
  if (it.k === 'bp') { var x = bpOf(f, it.id); return (x ? x.comp.name : it.id) + (bpStore(f, it) ? ' (Store App)' : ' (Web Shop)'); }
  if (it.k === 'x') { var x = pgObj(f).extra[it.i], h = (x.blocks || []).filter(function (b) { return b.t === 'h' && (b.en || b.hi); })[0]; return h ? (h.en || h.hi) : 'नया सेक्शन'; }
  if (it.k === 'dup') return wbRec(f, it.src).label + ' (कॉपी)';
  return wbRec(f, it.id).label;
}
function wbType(f, it) {
  if (it.k === 'bp') { var x = bpOf(f, it.id), tp = x && SPBLD.TYPES[x.comp.type] ? SPBLD.TYPES[x.comp.type] : {}; return (bpStore(f, it) ? '📱 Store App Page Builder का सेक्शन (वेबसाइट पर झलक — दबाने पर ऐप डाउनलोड)' : '🛍️ Web Shop Page Builder का सेक्शन') + ' · ' + (tp.icon || '') + ' ' + (tp.label || '') + (x && x.show === false ? ' · Builder में छुपा' : ''); }
  if (it.k === 'x') {
    var bl = pgObj(f).extra[it.i].blocks || [], has = function (t) { return bl.some(function (b) { return b.t === t; }); };
    if (has('slides')) return '🎞️ Slideshow'; if (has('video')) return '🎬 Video'; if (has('yt')) return '▶️ YouTube'; if (has('cards')) return '🗂️ कार्ड्स'; return '🧩 नया सेक्शन';
  }
  var r = wbRec(f, it.k === 'dup' ? it.src : it.id);
  if (r.hero) return '🎞️ Slideshow (हीरो)'; if (r.bn) return '🎬 Banner · वीडियो / स्लाइडशो'; if (r.yt) return '▶️ YouTube'; if (r.vid) return '🎬 Video guide';
  return '📝 ' + (r.t || []).length + ' टेक्स्ट · 🖼 ' + (r.i || []).length + ' फ़ोटो · 🔘 ' + (r.b || []).length + ' बटन';
}
/* sections that show the live Web Shop (real store products + Add to cart): in Website Builder they can only be moved / hidden — their content is edited in Web Shop Page Builder */
var SHOPSEC = { 'index.html': ['shop-categories', 'shop-systems', 's13', 's17', 's19', 's21', 's23'], 'shop.html': ['s3'] };
['commercial-solar', 'finance', 'hybrid-solar', 'industrial-solar', 'off-grid-solar', 'on-grid-solar', 'residential-solar', 'services', 'subsidy', 'vfd-solar'].forEach(function (p) { SHOPSEC[p + '.html'] = ['shop-here']; });
function wbShop(f, it) { return it.k === 'bp' || it.k !== 'x' && (SHOPSEC[f] || []).indexOf(it.k === 'dup' ? it.src : it.id) >= 0; }
function wbDyn(f, it) { return it.k === 'bp' ? true : it.k === 'x' ? false : !!wbRec(f, it.k === 'dup' ? it.src : it.id).dyn; }
function wbHidden(f, it) { var P = pgObj(f); return it.k === 'x' ? !!P.extra[it.i].hide : P.hide.indexOf(it.id) >= 0; }

function wbEditor(f, it) {
  var P = pgObj(f), base = pgBase(f);
  if (it.k === 'x') { var q = base + '.extra.' + it.i; return '<div class="wb-ed">' + chk(q + '.dark', 'गहरे (dark) बैकग्राउंड में दिखाएँ') + blocksEditor(q + '.blocks') + '</div>'; }
  var src = it.k === 'dup' ? it.src : it.id, rec = wbRec(f, src), pre = it.k === 'dup' ? it.id + '~' : '', man = wbMan(f), M = pgMan(f), h = '';
  var tdef = {}; man.texts.forEach(function (t) { tdef[t.k] = t; }); var idef = {}; man.imgs.forEach(function (t) { idef[t.k] = t; }); var bdef = {}; M.btns.forEach(function (b) { bdef[b.id] = b; });
  if (rec.hero && it.k === 'sec') h += '<div class="card" style="margin:8px 0"><h3 style="margin:0 0 6px">🎞️ हीरो स्लाइड (ऊपर की घूमती स्लाइड)</h3>' + slidesBody() + '</div>';
  if (rec.bn && it.k === 'sec') {
    var b = 'banners.' + rec.bn, kind = val(b + '.media.kind', 'images');
    h += '<div class="card" style="margin:8px 0"><h3 style="margin:0 0 6px">🎬 बैनर — वीडियो / स्लाइडशो (16:9)</h3><datalist id="bnPages">' + DEF().pages.map(function (p) { return '<option value="' + esc(p.file) + '">' + esc(p.en) + '</option>'; }).join('') + '</datalist>' +
      '<div class="fg">' + mediaEditor(b + '.media', 5) + '</div>' + btnEditor(b + '.btns.0', 1) + btnEditor(b + '.btns.1', 2) + chk(b + '.hide', 'इस बैनर को छुपाएँ') + '</div>';
  }
  if (rec.vid && !rec.bn) h += '<div class="note">🎬 यह <b>वीडियो गाइड</b> सेक्शन वीडियो लाइब्रेरी से अपने-आप बनता है — इसे यहाँ ऊपर-नीचे, छुपा, कॉपी या हटा सकते हैं।</div>';
  if ((rec.t || []).length) {
    h += '<h3 style="margin:12px 0 4px">📝 शब्द <small style="font-weight:400;color:var(--mut)">(English + हिंदी — खाली/जैसा है = बदलाव नहीं)</small></h3>' + rec.t.map(function (k) {
      var t = tdef[k]; if (!t) return ''; var key = pre + k, o = W.text[key], en = o ? o.en : t.en, hi = o ? o.hi : t.hi;
      return '<div class="row" style="align-items:flex-start;gap:8px;flex-wrap:wrap;' + (o ? 'background:#fff8e1' : '') + '"><div style="flex:1 1 100%;font-size:12px;color:var(--mut)">&lt;' + esc(t.tag) + '&gt;' + (o ? ' <b style="color:#b26a00">• बदला हुआ</b>' : '') + '</div>' +
        '<div style="flex:1 1 240px"><label class="l" style="font-size:12px">English</label><textarea class="inp" rows="2" data-tk="' + esc(key) + '" data-l="en" data-d="' + esc(t.en) + '">' + esc(en) + '</textarea></div>' +
        '<div style="flex:1 1 240px"><label class="l" style="font-size:12px">हिंदी</label><textarea class="inp" rows="2" data-tk="' + esc(key) + '" data-l="hi" data-d="' + esc(t.hi) + '">' + esc(hi) + '</textarea></div></div>';
    }).join('');
  }
  if ((rec.i || []).length) {
    var bs = siteBase();
    h += '<h3 style="margin:12px 0 4px">🖼️ फ़ोटो</h3>' + rec.i.map(function (k, n) { var d = idef[k]; return d ? imgf('img.' + pre + k, 'फ़ोटो ' + (n + 1) + (d.alt ? ' — ' + d.alt : ''), bs && !/^https?:/.test(d.src) ? bs + d.src : d.src) : ''; }).join('');
  }
  if ((rec.b || []).length) {
    h += '<h3 style="margin:12px 0 4px">🔘 बटन</h3>' + rec.b.map(function (id) {
      var d = bdef[id]; if (!d) return ''; var qb = base + '.btn.' + pre + id, o = P.btn[pre + id] || {};
      return '<details class="row' + (o.hide ? ' dim' : '') + '" style="display:block"><summary style="cursor:pointer;display:flex;gap:8px;align-items:center"><b style="flex:1;min-width:0">' + esc(d.label) + '</b><small style="color:var(--mut)">' + esc(d.href.slice(0, 40)) + '</small>' + (o.hide ? '<span class="tag">छुपा</span>' : (o.text || o.href ? '<span class="tag">बदला</span>' : '')) + '</summary>' +
        '<div class="fg" style="margin-top:8px">' + tf(qb + '.text.en', 'नया नाम (English) — खाली = जैसा है', { max: 40 }) + tf(qb + '.text.hi', 'नया नाम (हिंदी)', { max: 40 }) + (d.href ? tf(qb + '.href', 'नया लिंक (खाली = जैसा है)', { ph: d.href, full: true }) : '') + '</div>' + chk(qb + '.hide', 'इस बटन को छुपाएँ') + '</details>';
    }).join('');
  }
  if (!h) h = '<p style="color:var(--mut)">इस सेक्शन में बदलने लायक शब्द / फ़ोटो / बटन नहीं हैं — इसे ऊपर-नीचे, छुपा, कॉपी या हटा सकते हैं।</p>';
  return '<div class="wb-ed">' + h + '</div>';
}
var WB_NEW = [['slides', '🎞️ Slideshow', ['slides']], ['video', '🎬 Video', ['video']], ['yt', '▶️ YouTube', ['yt']], ['text', '📝 हेडिंग + टेक्स्ट', ['h', 'p']], ['list', '✅ पॉइंट्स', ['h', 'list']], ['cards', '🗂️ कार्ड्स', ['h', 'cards']], ['img', '🖼️ फ़ोटो', ['img']], ['btn', '🔘 बटन', ['h', 'btn']]];
VIEW.wb = function () {
  WB_REV++; loadBld();
  var files = wbFiles(); if (!files.length) return '<div class="note r">cms-secs.js नहीं मिला</div>';
  if (files.indexOf(WB_PG) < 0) WB_PG = files[0];
  var f = WB_PG, P = wbPrep(f), items = wbItems(f), live = items.filter(function (it) { return !it.gone; }), gone = items.filter(function (it) { return it.gone; });
  var h = help('<b>पेज चुनिए</b> → उसके सारे कंपोनेंट नीचे दिखेंगे। हर कंपोनेंट में <b>✏️ बदलें</b> (शब्द, फ़ोटो, वीडियो, बटन), <b>⬆️⬇️ क्रम</b>, <b>👁 छुपाएँ</b>, <b>⧉ Duplicate</b> (तुरंत कॉपी बनती है — फिर उसे अपने हिसाब से बदलें) और <b>🗑 हटाएँ</b> है। सबसे नीचे लाइव प्रीव्यू है। बदलाव 💾 सेव करने पर ही वेबसाइट पर जाते हैं।');
  h += '<div class="card"><h2>📄 कौन-सा पेज?</h2><div class="fg"><div class="fld full"><select class="inp" id="wbPage">' + files.map(function (k) { return '<option value="' + esc(k) + '"' + (k === f ? ' selected' : '') + '>' + esc(SECS()[k].title) + ' — ' + esc(k) + '</option>'; }).join('') + '</select></div></div>' +
    (siteBase() ? '<p style="margin-top:8px"><a class="btn sm out" target="_blank" rel="noopener" href="' + esc(siteBase() + f) + '">🔗 यह पेज वेबसाइट पर खोलें</a></p>' : '') + '</div>';
  var pvHtml = siteBase() ? '<div id="wbPv" style="margin-top:12px;padding:10px;border:1px dashed var(--line,#cbd8cf);border-radius:12px"><b>👁️ लाइव प्रीव्यू</b> <small style="font-weight:400;color:var(--mut)">(सिर्फ़ यही सेक्शन — बिना सेव किए बदलाव दिखते हैं)</small>' +
    '<div class="bar" style="margin-top:6px"><button class="btn sm' + (WB_DEV === 'm' ? '' : ' out') + '" data-wbdev="m">📱 मोबाइल</button><button class="btn sm' + (WB_DEV === 'd' ? '' : ' out') + '" data-wbdev="d">🖥️ डेस्कटॉप</button><button class="btn sm out" id="wbPvRefresh">🔄 बदलाव प्रीव्यू में देखें</button></div>' +
    '<div style="display:flex;justify-content:center;background:#e8efe9;border-radius:12px;padding:8px;margin-top:8px"><iframe id="wbFrame" title="Section preview" style="border:0;background:#fff;border-radius:8px;height:460px;max-width:100%;width:' + (WB_DEV === 'm' ? '390px' : '100%') + '" src="' + esc(siteBase() + f + '?spprev=1') + '"></iframe></div></div>' : '<div class="note r">वेबसाइट का लिंक set नहीं है — प्रीव्यू नहीं दिखेगा।</div>';
  h += '<div class="card"><h2>🧱 इस पेज के कंपोनेंट (' + live.length + ')</h2>' + (live.length ? live.map(function (it, n) {
    var hid = wbHidden(f, it), ed = WB_EDIT === it.id;
    return '<div class="wb-it' + (ed ? ' open' : '') + '" data-wbit="' + esc(it.id) + '"><div class="row' + (hid ? ' dim' : '') + '" style="margin:0"><div class="th" style="font-weight:800">' + (n + 1) + '</div><div class="rm"><b>' + esc(wbTitle(f, it)) + '</b> <small>#' + esc(it.id) + '</small>' +
      (it.k !== 'sec' && it.k !== 'bp' ? ' <span class="tag">' + (it.k === 'dup' ? 'कॉपी' : 'नया') + '</span>' : '') + (wbShop(f, it) ? ' <span class="tag b">' + (it.k === 'bp' && bpStore(f, it) ? '📱 Store App से जुड़ा' : '🛍️ Web Shop से जुड़ा') + '</span>' : '') + (hid ? ' <span class="tag">छुपा है</span>' : '') + '<br><small>' + esc(wbType(f, it)) + '</small></div><div class="acts">' +
      (wbShop(f, it) ? '<button class="ib" data-wbshop="' + esc(it.id) + '" title="यह Web Shop से जुड़ा है — यहाँ से edit नहीं">🛍️</button>' : '<button class="ib" data-wbed="' + esc(it.id) + '" title="बदलें">' + (ed ? '✖️' : '✏️') + '</button>') +
      '<button class="ib" data-wbmv="' + n + '" data-d="-1"' + (n === 0 ? ' disabled' : '') + ' title="ऊपर">⬆️</button><button class="ib" data-wbmv="' + n + '" data-d="1"' + (n === live.length - 1 ? ' disabled' : '') + ' title="नीचे">⬇️</button>' +
      '<button class="ib" data-wbhd="' + esc(it.id) + '" title="' + (hid ? 'दिखाएँ' : 'छुपाएँ') + '">' + (hid ? '🙈' : '👁') + '</button>' + (wbDyn(f, it) ? '<button class="ib" disabled title="इस सेक्शन में लाइव फ़ीचर (फ़ॉर्म / प्लेयर / कार्ट आदि) है, इसकी कॉपी नहीं बन सकती — ऊपर से नया कंपोनेंट जोड़ें">⧉</button>' : '<button class="ib" data-wbdup="' + esc(it.id) + '" title="Duplicate">⧉</button>') + (wbShop(f, it) ? '<button class="ib" disabled title="Web Shop से जुड़ा सेक्शन यहाँ से हट नहीं सकता — छुपा सकते हैं">🗑</button>' : '<button class="ib" data-wbdel="' + esc(it.id) + '" title="हटाएँ">🗑</button>') + '</div></div>' +
      (ed && !wbShop(f, it) ? wbEditor(f, it) + pvHtml : '') + '</div>';
  }).join('') : '<p style="color:var(--mut)">इस पेज पर कोई कंपोनेंट नहीं — नीचे से जोड़ें।</p>') +
    (gone.length ? '<details style="margin-top:10px"><summary style="cursor:pointer;font-weight:700">🗑 हटाए हुए (' + gone.length + ') — वापस ला सकते हैं</summary>' + gone.map(function (it) { return '<div class="row dim"><div class="rm"><b>' + esc(wbTitle(f, it)) + '</b> <small>#' + esc(it.id) + '</small></div><div class="acts"><button class="btn sm out" data-wbres="' + esc(it.id) + '">↩️ वापस लाएँ</button></div></div>'; }).join('') + '</details>' : '') + '</div>';
  h += '<div class="card"><h2>➕ नया कंपोनेंट जोड़ें</h2><div class="fg"><div class="fld full"><label class="l">कहाँ जुड़े?</label><select class="inp" id="wbAfter"><option value="">सबसे नीचे</option>' + live.filter(function (it) { return it.k !== 'bp'; }).map(function (it) { return '<option value="' + esc(it.id) + '">इसके बाद: ' + esc(wbTitle(f, it)) + '</option>'; }).join('') + '</select></div></div>' +
    '<div class="bar">' + WB_NEW.map(function (t) { return '<button class="btn sm out" data-wbadd="' + t[0] + '">' + esc(t[1]) + '</button>'; }).join('') + '</div></div>';
  h += saveBtn('wbSave', 'सेव करें — वेबसाइट पर लाइव');
  return h;
};
function wbDraft() { var d = norm(wbClone(W)); ['img', 'links'].forEach(function (k) { Object.keys(d[k]).forEach(function (x) { if (!String(d[k][x] || '').trim()) delete d[k][x]; }); }); return d; }
function wbSend() {
  var fr = $('#wbFrame'); if (!fr || !fr.contentWindow || !siteBase()) return; WB_FRAME = fr;
  var org; try { org = new URL(siteBase()).origin; } catch (e) { return; }
  try { fr.contentWindow.postMessage({ sp: 'pv-data', rev: String(WB_REV), data: wbDraft() }, org); } catch (e) {}
  try { fr.contentWindow.postMessage({ sp: 'pv-focus', sid: String(WB_EDIT || '') }, org); } catch (e) {}
}
var WB_MSG = false;
function wbPush(m) { if (m) { collect(m); collectTexts(m); } wbPrep(WB_PG).order = wbOrder(WB_PG); WB_REV++; wbSend(); }
function wbRedraw(m) { var y = window.pageYOffset; wbPush(m); draw(); try { window.scrollTo(0, y); } catch (e) {} }
function wbCopyKeys(P, f, from, to, fromPre, toPre) {
  var rec = wbRec(f, from);
  (rec.t || []).forEach(function (k) { var o = W.text[fromPre + k]; if (o) W.text[toPre + k] = wbClone(o); });
  (rec.i || []).forEach(function (k) { if (W.img[fromPre + k]) W.img[toPre + k] = W.img[fromPre + k]; });
  (rec.b || []).forEach(function (k) { if (P.btn[fromPre + k]) { var c = wbClone(P.btn[fromPre + k]); delete c.hide; P.btn[toPre + k] = c; } });
}
function wbDrop(P, f, id) {
  var p = id + '~'; Object.keys(W.text).forEach(function (k) { if (k.indexOf(p) === 0) delete W.text[k]; }); Object.keys(W.img).forEach(function (k) { if (k.indexOf(p) === 0) delete W.img[k]; }); Object.keys(P.btn).forEach(function (k) { if (k.indexOf(p) === 0) delete P.btn[k]; });
  P.order = P.order.filter(function (x) { return x !== id; }); P.hide = P.hide.filter(function (x) { return x !== id; }); P.show = P.show.filter(function (x) { return x !== id; });
}
function wbValidate(f) {
  var P = wbPrep(f), bad = '';
  P.extra.forEach(function (x) { bad = bad || cleanBlocks(x.blocks); });
  if (f === 'index.html') bad = bad || slidesCheck();
  Object.keys(P.btn).forEach(function (k) { var o = P.btn[k]; if (o.href && !/^(https?:\/\/\S+|tel:\S+|mailto:\S+|#[\w-]+|[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w-]+)?)$/i.test(o.href)) bad = bad || 'बटन का लिंक सही नहीं: ' + o.href; if (!o.hide && !(o.text && (o.text.en || o.text.hi)) && !o.href) delete P.btn[k]; });
  var imgBad = false; Object.keys(W.img).forEach(function (k) { var v = (W.img[k] || '').trim(); if (!v) delete W.img[k]; else if (!https(v)) imgBad = true; else W.img[k] = v; });
  if (imgBad) bad = bad || 'फ़ोटो का लिंक https:// से शुरू होना चाहिए (या फ़ोटो अपलोड करें)';
  bad = bad || tidyBanners();
  return bad;
}
BIND.wb = function (m) {
  if (!WB_MSG) { WB_MSG = true; window.addEventListener('message', function (e) { var fr = $('#wbFrame'); if (fr && e.source === fr.contentWindow && e.data && e.data.sp === 'pv-ready') wbSend(); }); }
  var f = WB_PG, P = wbPrep(f);
  $('#wbPage').onchange = function () { wbPush(m); WB_PG = this.value; WB_EDIT = ''; draw(); };
  bindSlides(m);
  var rf = $('#wbPvRefresh'); if (rf) rf.onclick = function () { wbPush(m); wbSend(); };
  m.addEventListener('change', function (e) { if (e.target.matches('select[data-p$=".kind"]')) wbRedraw(m); });
  m.addEventListener('click', async function (e) {
    var b, id, it, items;
    if ((b = e.target.closest('[data-wbdev]'))) { WB_DEV = b.getAttribute('data-wbdev'); wbRedraw(m); return; }
    if ((b = e.target.closest('[data-wbshop]'))) {
      var bpx = bpOf(f, b.getAttribute('data-wbshop'));
      if (bpx && bpx.comp.pages.store && !bpx.comp.pages.shop) { await A.ask('⚠️ This section can\'t be edited from here.<br>यह <b>Store App Page Builder</b> का सेक्शन है (वेबसाइट पर सिर्फ़ झलक)। यहाँ से सिर्फ़ ऊपर-नीचे और छुपाना/दिखाना हो सकता है।<br><small>बदलने के लिए App Store Management → Store App Page Builder में जाएँ।</small>', 'ठीक है', false); return; }
      if (await A.ask('⚠️ This section can\'t be edited from here.<br>यह सेक्शन Web Shop का असली डेटा दिखाता है — यहाँ से edit नहीं हो सकता।<br><small>यहाँ सिर्फ़ क्रम (ऊपर-नीचे) और छुपाना/दिखाना हो सकता है। बदलने के लिए <b>Web Shop Page Builder</b> में जाएँ। (अभी के बदलाव पहले 💾 सेव कर लें।)</small>', '🛍️ Web Shop Page Builder खोलें', false) && A.openShop) A.openShop();
      return;
    }
    if ((b = e.target.closest('[data-wbed]'))) { id = b.getAttribute('data-wbed'); collect(m); collectTexts(m); WB_EDIT = WB_EDIT === id ? '' : id; var y = window.pageYOffset; draw(); try { window.scrollTo(0, y); } catch (x) {} return; }
    if ((b = e.target.closest('[data-wbmv]'))) {
      collect(m); collectTexts(m); items = wbItems(f); var live = items.filter(function (z) { return !z.gone; }).map(function (z) { return z.id; }), n = +b.getAttribute('data-wbmv');
      if (mv(live, n, +b.getAttribute('data-d'))) { var k = 0, ord = wbOrder(f); P.order = ord.map(function (x) { return items.filter(function (z) { return z.id === x; })[0].gone ? x : live[k++]; }); wbRedraw(m); } return;
    }
    if ((b = e.target.closest('[data-wbhd]'))) {
      collect(m); collectTexts(m); id = b.getAttribute('data-wbhd'); it = wbItems(f).filter(function (z) { return z.id === id; })[0];
      if (it.k === 'x') { P.extra[it.i].hide = !P.extra[it.i].hide; } else { var ix = P.hide.indexOf(id); if (ix >= 0) { P.hide.splice(ix, 1); P.show.push(id); } else { P.hide.push(id); P.show = P.show.filter(function (x) { return x !== id; }); } }
      wbRedraw(m); return;
    }
    if ((b = e.target.closest('[data-wbdup]'))) {
      collect(m); collectTexts(m); id = b.getAttribute('data-wbdup'); it = wbItems(f).filter(function (z) { return z.id === id; })[0]; var nid;
      if (it.k === 'x') { var c = wbClone(P.extra[it.i]); nid = wbNewId(P, f, 'x'); c.id = nid; c.hide = false; delete c.after; P.extra.splice(it.i + 1, 0, c); }
      else { var sid = it.k === 'dup' ? it.src : id; nid = wbNewId(P, f, 'd'); P.dup.push({ id: nid, src: sid }); wbCopyKeys(P, f, sid, nid, it.k === 'dup' ? id + '~' : '', nid + '~'); }
      var ord2 = wbOrder(f).filter(function (x) { return x !== nid; }); ord2.splice(ord2.indexOf(id) + 1, 0, nid); P.order = ord2; WB_EDIT = nid;
      wbRedraw(m); toast('⧉ कॉपी बन गई — अब इसे अपने हिसाब से बदलिए'); return;
    }
    if ((b = e.target.closest('[data-wbdel]'))) {
      id = b.getAttribute('data-wbdel'); if (!(await A.ask('यह कंपोनेंट हटाएँ?' + (wbItems(f).filter(function (z) { return z.id === id; })[0].k === 'sec' ? ' (बाद में "हटाए हुए" से वापस ला सकते हैं)' : ''), 'हटाएँ', true))) return;
      collect(m); collectTexts(m); it = wbItems(f).filter(function (z) { return z.id === id; })[0];
      if (it.k === 'x') { P.extra.splice(it.i, 1); P.order = P.order.filter(function (x) { return x !== id; }); } else if (it.k === 'dup') { P.dup = P.dup.filter(function (d) { return d.id !== id; }); wbDrop(P, f, id); } else if (P.del.indexOf(id) < 0) P.del.push(id);
      if (WB_EDIT === id) WB_EDIT = ''; wbRedraw(m); return;
    }
    if ((b = e.target.closest('[data-wbres]'))) { collect(m); collectTexts(m); P.del = P.del.filter(function (x) { return x !== b.getAttribute('data-wbres'); }); wbRedraw(m); return; }
    if ((b = e.target.closest('[data-wbadd]'))) {
      collect(m); collectTexts(m); var t = WB_NEW.filter(function (z) { return z[0] === b.getAttribute('data-wbadd'); })[0], after = $('#wbAfter').value, nid2 = wbNewId(P, f, 'x');
      var blocks = t[2].map(function (bt) { var nb = newBlock(bt); if (bt === 'btn') nb.label = { en: 'Know more', hi: 'और जानें' }; return nb; });
      var x = { id: nid2, blocks: blocks }; if (after) x.after = after; P.extra.push(x);
      var ord3 = wbOrder(f).filter(function (z) { return z !== nid2; }); var pos = after ? ord3.indexOf(after) + 1 : ord3.length; ord3.splice(pos, 0, nid2); P.order = ord3; WB_EDIT = nid2;
      wbRedraw(m); toast('➕ ' + t[1] + ' जुड़ गया — नीचे भरिए और 💾 सेव करें'); return;
    }
  });
  bindBlocks(m, function () { wbRedraw(m); });
  $('#wbSave').onclick = function () {
    collect(m); collectTexts(m); var bad = wbValidate(f); if (bad) return toast(bad, true);
    P.order = wbOrder(f); save('✅ वेबसाइट पेज सेव हो गया — लाइव (1–2 मिनट में दिखेगा)').then(function () { wbPush(); draw(); });
  };
};

/* ================= dashboard / look / builder (scope aware) ================= */
VIEW.dash = function () { return '<div id="dashHost"></div>'; };
BIND.dash = function (m) { SPDASH.mount($('#dashHost', m), { kind: 'web', onData: function (a) { SPHDR.setAlerts(a); }, rpc: function (fn, p) { return A.rpc(fn, p, 60000); }, pass: A.pass, toast: toast, productTitle: A.productTitle }); };
VIEW.look = function () { return '<div id="lkHost"></div>'; };
BIND.look = function (m) { var io = SPLOOKUI.adminIO(A.rpc, A.pass); SPLOOKUI.mount($('#lkHost', m), { app: 'website', label: 'वेबसाइट', lang: 'hi', load: io.load, save: io.save, users: io.users, toast: toast }); };
VIEW.builder = function () { return A.builder ? A.builder.html() : ''; };
BIND.builder = function (m) { if (A.builder) { A.builder.reset(); A.builder.bind(m); } };

/* ================= entry ================= */
window.SPWEB = {
  /* header ☰ menu while inside Website / Shop management: ONLY this section's own tabs (no Store / other-app items) */
  nav: function () {
    var g = SCOPE === 'shop' ? 'Shop Page' : 'Website Management';
    return TABS.map(function (t) { var i = t[1].indexOf(' '); return { group: g, ic: t[1].slice(0, i), l: t[1].slice(i + 1), kw: t[0], on: TAB === t[0], fn: function () { collect(); TAB = t[0]; draw(); window.scrollTo(0, 0); } }; }).concat(window.SPBK ? SPBK.items(SCOPE === 'shop' ? 'shop' : 'site') : []);
  },
  open: async function (api) {
    STORE_BLD = null; BLD_LOADING = false; A = api; SCOPE = api.scope === 'shop' ? 'shop' : 'site'; TABS = SCOPE === 'shop' ? TABS_SHOP : TABS_ALL; TAB = api.tab && TABS.some(function (t) { return t[0] === api.tab; }) ? api.tab : 'dash'; LASTSCOPE = SCOPE; if (SCOPE === 'shop') { SECPG = 'shop.html'; PAGE = 'shop'; } else if (PAGE === 'shop') PAGE = 'index';
    A.app.innerHTML = '<div class="empty"><span class="spin"></span> लोड हो रहा है…</div>';
    try { W = norm(await A.rpc('sp_get_web', {})); }
    catch (e) { if (/Could not find|PGRST202|schema cache/i.test(e.message)) { W = norm({}); setTimeout(function () { toast('ℹ️ Website Admin चालू करने के लिए Supabase में phase4-website-admin.sql चलाएँ (MASTER-UPDATE.sql में है)', true); }, 600); } else { A.app.innerHTML = '<div class="login"><div class="card"><h2>⚠️ लोड नहीं हुआ</h2><p>' + esc(e.message) + '</p><button class="btn" id="wRt">दोबारा कोशिश</button></div></div>'; $('#wRt').onclick = function () { window.SPWEB.open(A); }; return; } }
    SAVED_JSON = JSON.stringify(W); CUR_PG = -1; shell();
  }
};
})();
