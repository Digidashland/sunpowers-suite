/* Sunpowers Store Admin — 🏛️ सब्सिडी (Round 61)
   Sarkari subsidy sirf JANKARI ke liye: Central (PM Surya Ghar) ki dar + har rajya ki subsidy. Bill / quotation / project page par dikhti hai,
   bill ki rakam me se kam NAHI hoti. Sirf Residential + On-Grid / Hybrid project par. Sunpowers koi subsidy nahi deta.
   Tables: sp_sub_cfg, sp_sub_state (SQL part U31). Hisab: sp_sub_calc (public, sirf padhta hai). */
(function () {
'use strict';
var X = null;
var ST = { data: null, err: '', loading: false, q: '', only: false, calc: { kw: '3', sys: 'on', state: 'Uttar Pradesh', out: null } };
var $ = function (s, r) { return (r || document).querySelector(s); };
var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
function call(fn, args, ms) { return X.rpc(fn, Object.assign({ p_pass: X.pass() }, args || {}), ms || 60000); }
function errMsg(e) { return String((e && e.message) || e || '').replace(/^.*?ERROR:\s*/, '').slice(0, 240); }
function inr(n) { n = Math.round(+n || 0); return '₹' + n.toLocaleString('en-IN'); }

var CSS = '.sb-card{border:1px solid #e0dacb;border-radius:10px;background:#fff;padding:12px;margin-top:10px}.sb-card.on{border-color:#1f6b3a;background:#f4fbf6}' +
  '.sb-h{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-weight:700}.sb-h .sp{flex:1}' +
  '.sb-g{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;margin-top:8px}.sb-g label{font-size:12px;color:#5c6573;font-weight:600;display:block;margin-bottom:2px}' +
  '.sb-g input,.sb-g select{width:100%;min-width:0}.sb-note{background:#fff4e0;border:1px solid #f0d49a;color:#7a4b00;border-radius:8px;padding:8px 10px;font-size:13px;line-height:1.5;margin-top:10px}' +
  '.sb-ok{background:#e6f3ea;border:1px solid #bfdcc8;color:#14532d;border-radius:8px;padding:8px 10px;font-size:13px;line-height:1.5;margin-top:10px}' +
  '.sb-box{border:2px solid #1f6b3a;border-radius:12px;padding:14px;margin-top:14px;background:#f4fbf6}.sb-box h3{margin:0 0 4px;font-size:16px}.sb-sub{font-size:12px;color:#5c6573;line-height:1.5;margin-bottom:8px}' +
  '.sb-chk{display:flex;gap:6px;align-items:center;font-size:13px;cursor:pointer}.sb-tag{font-size:11px;border-radius:6px;padding:2px 6px;font-weight:700}.sb-tag.g{background:#e6f3ea;color:#1f6b3a}.sb-tag.o{background:#fff4e0;color:#7a4b00}.sb-tag.m{background:#eee;color:#555}';
function ensureCss() { if (!$('#sbCss')) { var s = document.createElement('style'); s.id = 'sbCss'; s.textContent = CSS; document.head.appendChild(s); } }

async function boot() {
  if (ST.loading) return; ST.loading = true;
  try { ST.data = await call('sp_sub_admin_get'); ST.err = ''; }
  catch (e) { var m = errMsg(e); ST.err = /sp_sub_admin_get|does not exist|Could not find/i.test(String(e && e.message || e)) ? 'missing' : m; }
  ST.loading = false; X.render();
}

/* ------------------------------ tab ------------------------------ */
function stateCard(s) {
  var amt = +s.fixed > 0 ? inr(s.fixed) + ' (तय)' : +s.per_kw > 0 ? inr(s.per_kw) + '/kW' + (+s.cap > 0 ? ', अधिकतम ' + inr(s.cap) : '') : 'कोई राज्य सब्सिडी नहीं भरी';
  return '<div class="sb-card' + (s.active ? ' on' : '') + '" data-sb-st="' + esc(s.state_u) + '"><div class="sb-h"><span>' + esc(s.state) + '</span>' +
    (s.special ? '<span class="sb-tag o">Special category (+10%)</span>' : '') + (s.active ? '<span class="sb-tag g">ग्राहक को दिखती है</span>' : '<span class="sb-tag m">बंद</span>') +
    (s.verified ? '<span class="sb-tag g">✔ पक्का किया</span>' : '<span class="sb-tag o">पक्का करना बाकी</span>') + '<span class="sp"></span><small style="font-weight:400;color:#5c6573">' + esc(amt) + '</small></div>' +
    '<div class="sb-g"><div><label>प्रति kW (₹)</label><input class="inp" type="number" min="0" step="any" data-f="per_kw" value="' + (+s.per_kw || '') + '"></div>' +
    '<div><label>अधिकतम (₹) — 0 = सीमा नहीं</label><input class="inp" type="number" min="0" step="any" data-f="cap" value="' + (+s.cap || '') + '"></div>' +
    '<div><label>तय रक़म (₹) — भरी तो प्रति-kW की जगह यही</label><input class="inp" type="number" min="0" step="any" data-f="fixed" value="' + (+s.fixed || '') + '"></div></div>' +
    '<div class="sb-g"><div style="grid-column:1/-1"><label>नोट (शर्त) — बिल/पेज पर नहीं छपता, सिर्फ़ ग्राहक को राज्य-लाइन के साथ दिखता है</label><input class="inp" data-f="note" maxlength="300" value="' + esc(s.note) + '"></div>' +
    '<div style="grid-column:1/-1"><label>स्रोत (official लिंक / नाम)</label><input class="inp" data-f="src" maxlength="200" value="' + esc(s.src) + '" placeholder="जैसे: upneda.org.in"></div></div>' +
    '<div class="sb-h" style="margin-top:8px;font-weight:400"><label class="sb-chk"><input type="checkbox" data-f="special"' + (s.special ? ' checked' : '') + '> Special category (NE, उत्तराखंड, हिमाचल, J&amp;K, लद्दाख, A&amp;N, लक्षद्वीप)</label>' +
    '<label class="sb-chk"><input type="checkbox" data-f="verified"' + (s.verified ? ' checked' : '') + '> official साइट से पक्का किया</label>' +
    '<label class="sb-chk"><input type="checkbox" data-f="active"' + (s.active ? ' checked' : '') + '> <b>ग्राहक को दिखाएँ</b></label><span class="sp"></span><button class="btn" data-sb="save">💾 सेव</button></div></div>';
}
function calcHtml() {
  var c = ST.calc, sts = (ST.data && ST.data.states) || [], o = c.out, r = '';
  if (o) r = o.ok ? '<div class="sb-ok"><b>Central ' + inr(o.central) + '</b>' + (o.state > 0 ? ' + <b>राज्य ' + inr(o.state) + '</b>' : '') + ' = <b>कुल ' + inr(o.total) + '</b>' + (o.special ? ' (Special category दर)' : '') + (o.hybrid_note ? '<br>Hybrid: राज्य बिजली आयोग की मंज़ूरी पर निर्भर' : '') + (o.state === 0 ? '<br>इस राज्य की सब्सिडी अभी चालू नहीं है — सिर्फ़ Central जुड़ेगी।' : '') + '</div>'
    : '<div class="sb-note">कोई subsidy नहीं जुड़ेगी — ' + ({ offgrid: 'Off-Grid पर CFA नहीं मिलता', not_res: 'सिर्फ़ घरेलू (Residential) पर', nokw: 'kW भरें', off: 'सुविधा बंद है' }[o.reason] || esc(o.reason)) + '</div>';
  return '<div class="sb-card"><div class="sb-h"><span>🧮 जाँच-कैलकुलेटर</span><span class="sp"></span><small style="font-weight:400;color:#5c6573">ग्राहक को ठीक यही हिसाब दिखेगा</small></div><div class="sb-g">' +
    '<div><label>प्लांट (kW)</label><input class="inp" type="number" min="0" step="any" id="sbCkw" value="' + esc(c.kw) + '"></div>' +
    '<div><label>System type</label><select class="inp" id="sbCsys"><option value="on"' + (c.sys === 'on' ? ' selected' : '') + '>On-Grid</option><option value="hy"' + (c.sys === 'hy' ? ' selected' : '') + '>Hybrid</option><option value="off"' + (c.sys === 'off' ? ' selected' : '') + '>Off-Grid</option></select></div>' +
    '<div><label>राज्य</label><select class="inp" id="sbCst">' + sts.map(function (s) { return '<option' + (s.state === c.state ? ' selected' : '') + '>' + esc(s.state) + '</option>'; }).join('') + '</select></div>' +
    '<div style="align-self:end"><button class="btn" data-sb="calc">हिसाब देखें</button></div></div>' + r + '</div>';
}
function html() {
  ensureCss();
  if (!ST.data && !ST.err) { boot(); return '<div class="empty"><span class="spin"></span> लोड हो रहा है…</div>'; }
  if (ST.err === 'missing') return '<div class="note r">⚠️ यह सुविधा चालू करने के लिए Supabase → SQL Editor में <b>ROUND-40-61-SQL-ONLY.sql</b> एक बार चलाएँ।</div>';
  if (ST.err) return '<div class="note r">⚠️ ' + esc(ST.err) + '</div><button class="btn" data-sb="retry">🔄 दोबारा कोशिश</button>';
  var c = ST.data.cfg || {}, sts = ST.data.states || [], q = ST.q.toLowerCase();
  var list = sts.filter(function (s) { return (!q || s.state.toLowerCase().indexOf(q) >= 0) && (!ST.only || s.active); });
  var nAct = sts.filter(function (s) { return s.active; }).length;
  return '<div class="sb-ok" style="margin-top:0"><b>🏛️ सरकारी सब्सिडी — सिर्फ़ जानकारी।</b> यह रक़म बिल / कोटेशन में से घटाई नहीं जाती। Sunpowers कोई सब्सिडी नहीं देता — सरकार शर्तें पूरी होने पर सीधा ग्राहक के बैंक खाते में देती है। सिर्फ़ <b>घरेलू (Residential) On-Grid / Hybrid</b> प्रोजेक्ट पर दिखती है; Off-Grid, Commercial, Industrial पर नहीं।</div>' +
    '<div class="sb-card"><div class="sb-h"><span>🇮🇳 Central — PM Surya Ghar (MNRE)</span><span class="sp"></span><label class="sb-chk"><input type="checkbox" id="sbEn"' + (c.enabled ? ' checked' : '') + '> <b>सुविधा चालू</b></label></div>' +
    '<div class="sb-g"><div><label>पहले 2 kW: ₹ प्रति kW</label><input class="inp" type="number" min="0" id="sbR1" value="' + (+c.r1 || 0) + '"></div><div><label>तीसरा kW: ₹ प्रति kW</label><input class="inp" type="number" min="0" id="sbR2" value="' + (+c.r2 || 0) + '"></div>' +
    '<div><label>Special category: पहले 2 kW</label><input class="inp" type="number" min="0" id="sbR1s" value="' + (+c.r1_sp || 0) + '"></div><div><label>Special category: तीसरा kW</label><input class="inp" type="number" min="0" id="sbR2s" value="' + (+c.r2_sp || 0) + '"></div>' +
    '<div><label>इससे ऊपर के kW पर कुछ नहीं</label><input class="inp" type="number" min="0" step="any" id="sbCap" value="' + (+c.cap_kw || 0) + '"></div></div>' +
    '<div class="sb-g"><div style="grid-column:1/-1"><label>सब पर लगने वाला नोट (वैकल्पिक, ग्राहक को राज्य-लाइन के साथ दिखता है)</label><input class="inp" id="sbNote" maxlength="400" value="' + esc(c.note) + '"></div></div>' +
    '<div class="sb-h" style="margin-top:8px"><small style="font-weight:400;color:#5c6573">3 kW पर Central = 2×30,000 + 1×18,000 = ₹78,000 (MNRE guidelines)। नीति बदले तो यहीं बदलें।</small><span class="sp"></span><button class="btn" data-sb="cfg">💾 Central सेव</button></div></div>' +
    calcHtml() +
    '<div class="bar" style="margin-top:14px"><input class="inp grow" id="sbQ" placeholder="🔍 राज्य खोजें" value="' + esc(ST.q) + '"><label class="sb-chk"><input type="checkbox" id="sbOnly"' + (ST.only ? ' checked' : '') + '> सिर्फ़ चालू (' + nAct + ')</label></div>' +
    '<div class="sb-note">⚠️ राज्य की रक़म तभी <b>“ग्राहक को दिखाएँ”</b> करें जब आप राज्य की official साइट / नोडल एजेंसी से पक्का कर लें। जिस राज्य की रक़म नहीं भरी, वहाँ सिर्फ़ Central जुड़ती है।</div>' +
    list.map(stateCard).join('');
}
function bind(m) {
  m.addEventListener('input', function (e) {
    if (e.target.id === 'sbQ') { ST.q = e.target.value; clearTimeout(bind._t); bind._t = setTimeout(function () { var p = e.target.selectionStart; X.render(); var q = $('#sbQ'); if (q) { q.focus(); try { q.setSelectionRange(p, p); } catch (x) {} } }, 250); }
  });
  m.addEventListener('change', function (e) {
    var t = e.target;
    if (t.id === 'sbOnly') { ST.only = t.checked; X.render(); }
    else if (t.id === 'sbCkw') ST.calc.kw = t.value; else if (t.id === 'sbCsys') ST.calc.sys = t.value; else if (t.id === 'sbCst') ST.calc.state = t.value;
  });
  m.addEventListener('click', async function (e) {
    var b = e.target.closest('[data-sb]'); if (!b) return; var a = b.getAttribute('data-sb');
    try {
      if (a === 'retry') { ST.err = ''; ST.data = null; ST.loading = false; X.render(); }
      else if (a === 'cfg') {
        await call('sp_sub_admin_cfg_set', { p: { enabled: $('#sbEn', m).checked, r1: $('#sbR1', m).value, r2: $('#sbR2', m).value, r1_sp: $('#sbR1s', m).value, r2_sp: $('#sbR2s', m).value, cap_kw: $('#sbCap', m).value, note: $('#sbNote', m).value } });
        ST.data = null; ST.loading = false; X.toast('✅ Central की दरें सेव हो गईं'); X.render();
      } else if (a === 'save') {
        var card = b.closest('[data-sb-st]'), su = card.getAttribute('data-sb-st'), row = ST.data.states.filter(function (s) { return s.state_u === su; })[0], p = { state: row.state };
        $$('[data-f]', card).forEach(function (i) { var k = i.getAttribute('data-f'); p[k] = i.type === 'checkbox' ? i.checked : i.value; });
        if (p.active && !p.verified && !(await X.ask('यह राज्य official साइट से <b>पक्का नहीं</b> किया गया। फिर भी ग्राहक को दिखाएँ? गलत रक़म दिखाना ठीक नहीं है।', 'हाँ, दिखाएँ'))) return;
        await call('sp_sub_admin_state_set', { p: p }); ST.data = null; ST.loading = false; X.toast('✅ ' + row.state + ' सेव हो गया'); X.render();
      } else if (a === 'calc') {
        var c = ST.calc; ST.calc.out = await X.rpc('sp_sub_calc', { p_state: c.state, p_kw: +c.kw || 0, p_sys: c.sys, p_res: true }, 15000); X.render();
      }
    } catch (x) { X.toast('⚠️ ' + errMsg(x), true); }
  });
}

/* ------------------------------ product form block (sirf project ke liye) ------------------------------ */
function hostHtml(obj) {
  if (!obj || !(obj.proj || obj.sub)) return '';
  ensureCss();
  var s = obj.sub || {}, sys = s.sys || 'on', res = obj.sub ? s.res !== false : true;
  return '<div class="sb-box" id="sbProd"><h3>🏛️ सरकारी सब्सिडी (सिर्फ़ जानकारी)</h3><div class="sb-sub">ग्राहक पिन कोड डालते ही इस प्रोजेक्ट पर Central + राज्य की अनुमानित सब्सिडी दिखती है। कीमत में से घटती नहीं।</div>' +
    '<div class="sb-g"><div><label>प्लांट (kW)</label><input class="inp" type="number" min="0" step="any" id="sbPkw" value="' + (+s.kw || '') + '" placeholder="जैसे 3"></div>' +
    '<div><label>System type</label><select class="inp" id="sbPsys"><option value="on"' + (sys === 'on' ? ' selected' : '') + '>On-Grid</option><option value="hy"' + (sys === 'hy' ? ' selected' : '') + '>Hybrid (battery + grid)</option><option value="off"' + (sys === 'off' ? ' selected' : '') + '>Off-Grid (subsidy नहीं)</option></select></div></div>' +
    '<label class="sb-chk" style="margin-top:8px"><input type="checkbox" id="sbPres"' + (res ? ' checked' : '') + '> घरेलू (Residential) प्रोजेक्ट — Commercial / Industrial पर सब्सिडी नहीं मिलती</label>' +
    '<div class="sb-sub" style="margin-top:6px">kW खाली छोड़ेंगे तो इस प्रोजेक्ट पर सब्सिडी नहीं दिखेगी।</div></div>';
}
/* returns undefined (block nahi hai), null (kW khali -> subsidy nahi), ya {kw, sys, res} */
function read(body) {
  var box = $('#sbProd', body); if (!box) return undefined;
  var kw = parseFloat($('#sbPkw', box).value);
  if (!(kw > 0)) return null;
  return { kw: Math.round(Math.min(kw, 10000) * 100) / 100, sys: $('#sbPsys', box).value, res: $('#sbPres', box).checked };
}
function fromCrm(d) {
  if (!d || d.type !== 'project') return undefined;
  var kw = parseFloat(d.kw); if (!(kw > 0)) return undefined;
  return { kw: kw, sys: ['on', 'hy', 'off'].indexOf(d.sys) >= 0 ? d.sys : 'on', res: d.category === 'Residential' };
}

window.SPSUB = {
  init: function (ctx) { X = ctx; ensureCss(); }, html: html, bind: bind, reset: function () { ST.data = null; ST.err = ''; ST.loading = false; },
  hostHtml: hostHtml, read: read, fromCrm: fromCrm
};
})();
