/* Sunpowers Store Admin — 🚚 डिलीवरी रेट (pincode-wise delivery charge)
   Rules live in Supabase table sp_ship_rules (MASTER-UPDATE.sql, Round 48). Storefront + checkout ask sp_ship_quote();
   the server re-checks the charge when the order is placed. Delivery charge par GST nahi lagta.
   Niyam: sabse khaas rule jeetta hai (Pincode > Custom Area > District > State > Sab). Complete project (CRM template) par delivery hamesha free. */
(function () {
'use strict';
var X = null;
var ST = { rules: null, err: '', loading: false };
var SCOPES = { all: 'सभी पिनकोड', state: 'State', district: 'District', area: 'Custom Area', pin: 'पिनकोड' };
var $ = function (s, r) { return (r || document).querySelector(s); };
var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
var nf = function (n) { return Number(n || 0).toLocaleString('en-IN'); };
function tc(s) { return String(s || '').toLowerCase().replace(/(^|[\s(\-.])([a-z])/g, function (m, a, b) { return a + b.toUpperCase(); }); }
function call(fn, args, ms) { return X.rpc(fn, Object.assign({ p_pass: X.pass() }, args || {}), ms || 60000); }
function valLabel(scope, v) {
  if (scope === 'all') return 'सभी पिनकोड (बाकी सब जगह)';
  if (scope === 'district') { var a = String(v).split('|'); return tc(a[1] || '') + ', ' + tc(a[0] || ''); }
  if (scope === 'pin') return String(v);
  return tc(v);
}
function load() {
  if (ST.loading) return; ST.loading = true;
  call('sp_ship_rules_list').then(function (r) { ST.rules = r || []; ST.err = ''; }, function (e) {
    ST.err = /does not exist|Could not find|schema cache/i.test(e.message || '') ? 'missing' : (e.message || 'Error');
  }).then(function () { ST.loading = false; X.render(); });
}
function chg(r) {
  if (r.mode === 'self' && !+r.base_charge && !+r.per_kg) return '<b>फ़्री (खुद डिलीवरी)</b>';
  var t = '₹' + nf(r.base_charge) + ' <small>(' + nf(r.base_kg) + ' kg तक)</small>';
  if (+r.per_kg) t += '<br><small>+ ₹' + nf(r.per_kg) + '/kg ऊपर</small>';
  return t;
}
function html() {
  if (!ST.rules && !ST.err) { load(); return '<div class="empty"><span class="spin"></span> लोड हो रहा है…</div>'; }
  if (ST.err === 'missing') return '<div class="note r">⚠️ डिलीवरी रेट का डेटाबेस हिस्सा अभी नहीं लगा है। Supabase में <b>ROUND-40-49-SQL-ONLY.sql</b> (या MASTER-UPDATE.sql) एक बार चलाएँ।</div>';
  if (ST.err) return '<div class="note r">⚠️ ' + esc(ST.err) + '</div><button class="btn" data-sd="retry">🔄 दोबारा कोशिश</button>';
  var R = ST.rules, h = '<div class="note g">🚚 <b>पिनकोड के हिसाब से डिलीवरी चार्ज।</b> चार्ज = बेस चार्ज + (वज़न − बेस kg) ऊपर हर kg × प्रति-kg रेट। '
    + 'सबसे ख़ास नियम जीतता है: पिनकोड → Custom Area → District → State → सभी। <b>डिलीवरी पर GST नहीं।</b> '
    + '<b>कम्प्लीट प्रोजेक्ट (CRM template) पर डिलीवरी हमेशा फ़्री।</b> स्टोर से खुद उठाने पर भी फ़्री। '
    + 'कोई नियम न मिले तो पुरानी स्टोर-सेटिंग (लोकल / बाकी जगह) चलती है। हर प्रोडक्ट में <b>वज़न (kg)</b> भरें, वरना वज़न नहीं जुड़ेगा। '
    + 'बहुत सारे पिनकोड एक साथ के लिए पहले 📍 पिनकोड टैब में “Custom Area” बनाएँ, फिर यहाँ उस Area का नियम लगाएँ।</div>'
    + '<div class="bar"><button class="btn" data-sd="add">➕ नया डिलीवरी नियम</button></div>';
  if (!R.length) return h + '<div class="empty">अभी कोई नियम नहीं। पहले “सभी पिनकोड” का एक नियम बनाएँ (जैसे बाकी भारत: कूरियर ₹400, 5 kg तक + ₹40/kg), फिर Lucknow / UP के लिए ख़ास नियम।</div>' + testHtml();
  h += '<div class="tbl"><table><thead><tr><th>कहाँ</th><th>कैसे</th><th>चार्ज</th><th>फ़्री कब</th><th>दिन</th><th></th></tr></thead><tbody>' + R.map(function (r) {
    return '<tr><td><b>' + esc(valLabel(r.scope, r.value)) + '</b><br><small>' + esc(SCOPES[r.scope]) + '</small></td><td>' + (r.mode === 'self' ? '🛵 खुद डिलीवरी' : '📦 कूरियर' + (r.courier ? '<br><small>' + esc(r.courier) + '</small>' : '')) + '</td><td>' + chg(r) + '</td>'
      + '<td>' + (+r.free_above ? '₹' + nf(r.free_above) + ' से ऊपर' : '—') + '</td><td>' + (r.eta_max ? (r.eta_min && r.eta_min !== r.eta_max ? r.eta_min + '–' : '') + r.eta_max : '—') + '</td>'
      + '<td style="white-space:nowrap"><button class="btn out sm" data-sd="edit" data-id="' + r.id + '">✏️</button> <button class="btn red sm" data-sd="del" data-id="' + r.id + '">🗑️</button></td></tr>';
  }).join('') + '</tbody></table></div>';
  return h + testHtml();
}
function testHtml() {
  return '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:8px">🧪 जाँचें</h3><div class="row2" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px">'
    + '<div class="f"><label>पिनकोड</label><input class="inp" id="sdTPin" inputmode="numeric" maxlength="6" placeholder="226001"></div>'
    + '<div class="f"><label>प्रोडक्ट</label><select class="inp" id="sdTProd">' + ((X.products() || []).map(function (p) { return '<option value="' + esc(p.id) + '">' + esc(p.title || p.id) + '</option>'; }).join('')) + '</select></div>'
    + '<div class="f"><label>मात्रा</label><input class="inp" id="sdTQty" type="number" min="1" value="1"></div></div>'
    + '<div class="bar"><button class="btn out" data-sd="test">जाँचें</button></div><div id="sdTOut" style="margin-top:8px"></div></div>';
}
function form(r) {
  r = r || { scope: 'state', value: '', mode: 'courier', courier: '', base_charge: 0, base_kg: 5, per_kg: 0, free_above: 0, eta_min: 0, eta_max: 0, note: '' };
  var inp = function (id, l, v, t, extra) { return '<div class="f"><label>' + l + '</label><input id="' + id + '" type="' + (t || 'text') + '" value="' + esc(v) + '" ' + (extra || '') + '></div>'; };
  var body = '<div style="display:grid;gap:8px"><div class="f"><label>कहाँ लागू</label><select id="sdScope">' + Object.keys(SCOPES).map(function (k) { return '<option value="' + k + '"' + (k === r.scope ? ' selected' : '') + '>' + SCOPES[k] + '</option>'; }).join('') + '</select></div>'
    + inp('sdVal', 'नाम / पिनकोड', r.scope === 'all' ? '' : r.value, 'text', 'placeholder="State: Uttar Pradesh • District: Uttar Pradesh|Lucknow • Area: नाम • पिनकोड: 226001"')
    + '<div class="f"><label>तरीका</label><select id="sdMode"><option value="courier"' + (r.mode === 'courier' ? ' selected' : '') + '>📦 कूरियर</option><option value="self"' + (r.mode === 'self' ? ' selected' : '') + '>🛵 खुद की डिलीवरी (हमारी गाड़ी)</option></select></div>'
    + inp('sdCour', 'कूरियर का नाम (वैकल्पिक)', r.courier, 'text', 'maxlength="60" placeholder="Delhivery / DTDC / Transport"')
    + '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">' + inp('sdBase', 'बेस चार्ज (₹)', r.base_charge, 'number', 'min="0"') + inp('sdBkg', 'इतने kg तक बेस', r.base_kg, 'number', 'min="0"') + '</div>'
    + '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">' + inp('sdPkg', 'ऊपर हर kg का (₹)', r.per_kg, 'number', 'min="0"') + inp('sdFree', 'इतने ₹ से ऊपर फ़्री (0 = कभी नहीं)', r.free_above, 'number', 'min="0"') + '</div>'
    + '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">' + inp('sdEmin', 'कम से कम दिन', r.eta_min, 'number', 'min="0"') + inp('sdEmax', 'ज़्यादा से ज़्यादा दिन', r.eta_max, 'number', 'min="0"') + '</div>'
    + inp('sdNote', 'नोट (ग्राहक को दिखेगा, वैकल्पिक)', r.note, 'text', 'maxlength="200"') + '</div>';
  X.modal(r.id ? '✏️ डिलीवरी नियम बदलें' : '➕ नया डिलीवरी नियम', body, [{ l: 'रद्द करें', cls: 'gray' }, { l: 'सेव करें', fn: async function (md) {
    var g = function (id) { return ($('#' + id, md.el) || {}).value; }, sc = g('sdScope'), v = (g('sdVal') || '').trim();
    if (sc !== 'all' && !v) { X.toast('नाम / पिनकोड लिखें', true); return false; }
    var p = { id: r.id || null, scope: sc, value: sc === 'all' ? '*' : v, mode: g('sdMode'), courier: g('sdCour'), base_charge: +g('sdBase') || 0, base_kg: +g('sdBkg') || 0, per_kg: +g('sdPkg') || 0, free_above: +g('sdFree') || 0, eta_min: +g('sdEmin') || 0, eta_max: +g('sdEmax') || 0, note: g('sdNote') };
    if (p.eta_max && p.eta_min > p.eta_max) { X.toast('कम से कम दिन, ज़्यादा से ज़्यादा से बड़े नहीं हो सकते', true); return false; }
    await call('sp_ship_rule_save', { p: p }); X.toast('✅ सेव हो गया'); ST.rules = null; X.render();
  } }]);
}
function bind(m) {
  m.addEventListener('click', async function (ev) {
    var el = ev.target.closest('[data-sd]'); if (!el) return; var k = el.getAttribute('data-sd');
    try {
      if (k === 'retry') { ST.err = ''; ST.rules = null; X.render(); }
      else if (k === 'add') form(null);
      else if (k === 'edit') form((ST.rules || []).filter(function (r) { return String(r.id) === el.getAttribute('data-id'); })[0]);
      else if (k === 'del') {
        var r = (ST.rules || []).filter(function (x) { return String(x.id) === el.getAttribute('data-id'); })[0]; if (!r) return;
        if (await X.ask('<b>' + esc(valLabel(r.scope, r.value)) + '</b> का डिलीवरी नियम हटाएँ?', 'हाँ, हटाएँ', true)) { await call('sp_ship_rule_delete', { p_id: r.id }); X.toast('✅ हट गया'); ST.rules = null; X.render(); }
      }
      else if (k === 'test') {
        var pin = ($('#sdTPin').value || '').replace(/\D/g, ''), o = $('#sdTOut');
        if (!/^[1-9]\d{5}$/.test(pin)) { o.innerHTML = '<span style="color:var(--red)">6 अंक का सही पिनकोड लिखें</span>'; return; }
        var pid = $('#sdTProd').value, qty = Math.max(1, +$('#sdTQty').value || 1), pr = (X.products() || []).filter(function (p) { return p.id === pid; })[0] || {}, price = +pr.offer > 0 ? +pr.offer : +pr.price || +pr.mrp || 0;
        var q = await X.rpc('sp_ship_quote', { p_pin: pin, p_items: [{ id: pid, qty: qty, price: price }], p_subtotal: price * qty, p_pickup: false }, 20000);
        o.innerHTML = q ? ('<b>' + (q.charge > 0 ? '₹' + nf(q.charge) : 'फ़्री') + '</b> • ' + esc(q.reason === 'project' ? 'कम्प्लीट प्रोजेक्ट' : q.reason === 'above' ? 'फ़्री-लिमिट से ऊपर' : q.reason === 'rule' ? 'डिलीवरी नियम' : 'पुरानी सेटिंग') + (q.courier ? ' • ' + esc(q.courier) : '') + (q.mode === 'self' ? ' • खुद डिलीवरी' : '') + (q.eta_max ? ' • ' + q.eta_max + ' दिन तक' : '') + ' • वज़न ' + (+q.kg || 0) + ' kg') : '—';
      }
    } catch (e) { X.toast(e.message || String(e), true); }
  });
}
window.SPSHIP = {
  init: function (x) { X = x; },
  reset: function () { ST.rules = null; ST.err = ''; ST.loading = false; },
  html: html, bind: bind
};
})();
