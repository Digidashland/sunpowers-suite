/* Sunpowers website — full checkout (cart → address → payment → order → UTR) on www, no hop to the store domain.
   Uses the same server functions as the Online Store: sp_get_store, sp_pin_check, sp_place_order, sp_order_no, sp_submit_utr, and the same customer login (SPGate).
   Cart = localStorage "sp_wcart" (shared with the Shop page, cart.js). */
(function () {
  'use strict';
  var root = document.getElementById('coPage'); if (!root) return;
  var TX = {
    cart: ['Your cart', 'आपका कार्ट'], empty: ['Your cart is empty.', 'आपका कार्ट खाली है।'], shop: ['Go to Shop', 'शॉप पर जाएँ'], remove: ['Remove', 'हटाएँ'],
    deliver: ['Delivery details', 'डिलीवरी की जानकारी'], name: ['Full name', 'पूरा नाम'], phone: ['Mobile number', 'मोबाइल नंबर'], addr: ['Full address', 'पूरा पता'], city: ['City', 'शहर'], pin: ['Pin code', 'पिन कोड'], note: ['Note (optional)', 'नोट (वैकल्पिक)'],
    pay: ['Payment', 'पेमेंट'], noPay: ['Online payment is not set up yet. Please send the order on WhatsApp.', 'ऑनलाइन पेमेंट अभी चालू नहीं है। कृपया WhatsApp पर ऑर्डर भेजें।'],
    sub: ['Subtotal', 'कुल'], pickupL: ['🏬 I will pick it up from the store (delivery free)', '🏬 मैं स्टोर से खुद ले जाऊँगा (डिलीवरी फ़्री)'], viaL: ['via', 'कूरियर'], daysL: ['days', 'दिन'], projFree: ['Complete project — delivery free', 'कम्प्लीट प्रोजेक्ट — डिलीवरी फ़्री'], shipChg: ['The delivery charge changed — please check the new charge and place the order again.', 'डिलीवरी चार्ज बदल गया है — कृपया नया चार्ज देखकर दोबारा ऑर्डर करें।'], ship: ['Delivery', 'डिलीवरी'], free: ['Free', 'फ़्री'], pinFirst: ['Enter pin code', 'पिन कोड डालें'], adv: ['Pay your bill amount now', 'अभी बिल की रकम दें'], due: ['Pay on delivery', 'डिलीवरी पर'], grand: ['Order total', 'ऑर्डर कुल'], total: ['Pay now', 'अभी देना है'],
    place: ['Place order', 'ऑर्डर करें'], placing: ['Placing…', 'ऑर्डर हो रहा है…'], wa: ['Send order on WhatsApp', 'WhatsApp पर ऑर्डर भेजें'],
    consent: ['I agree to the', 'मैं सहमत हूँ'], cons2: ['Refund', 'रिफ़ंड'], cons3: ['Shipping', 'शिपिंग'], cons4: ['Terms', 'शर्तों'],
    reqName: ['Enter your name', 'नाम लिखें'], reqPhone: ['Enter a 10-digit mobile number', '10 अंकों का मोबाइल नंबर डालें'], reqAddr: ['Enter your full address', 'पूरा पता लिखें'], reqPin: ['Enter a 6-digit pin code', '6 अंकों का पिन कोड डालें'], reqPay: ['Choose a payment option', 'पेमेंट का तरीका चुनें'], reqOk: ['Please accept the policies', 'कृपया नीतियाँ स्वीकार करें'],
    na: ['Not available at this pin code', 'इस पिन कोड पर उपलब्ध नहीं'], naMsg: ['Remove the unavailable items to continue.', 'आगे बढ़ने के लिए अनुपलब्ध आइटम हटाएँ।'], out: ['Out of stock', 'स्टॉक में नहीं'],
    fail: ['Could not place the order. Please try again or send it on WhatsApp.', 'ऑर्डर नहीं हो सका। फिर कोशिश करें या WhatsApp पर भेजें।'], loadFail: ['Could not load the store. Please refresh.', 'स्टोर लोड नहीं हुआ। पेज रीफ़्रेश करें।'],
    done: ['Order placed!', 'ऑर्डर हो गया!'], ono: ['Order number', 'ऑर्डर नंबर'], advNote: ['Pay your bill amount to confirm your order. The rest is paid on delivery.', 'ऑर्डर पक्का करने के लिए अपने बिल की रकम दें। बाकी डिलीवरी पर।'], fullNote: ['Pay the full amount to confirm your order.', 'ऑर्डर पक्का करने के लिए पूरा पेमेंट करें।'],
    upi: ['UPI ID', 'UPI आईडी'], copy: ['Copy', 'कॉपी'], copied: ['Copied', 'कॉपी हुआ'], payNow: ['Pay with UPI app', 'UPI ऐप से पेमेंट करें'], utrQ: ['Paid? Enter the UTR / transaction ID', 'पेमेंट हो गया? UTR / ट्रांज़ैक्शन आईडी डालें'], utrGo: ['Submit', 'जमा करें'], more: ['Continue shopping', 'और खरीदारी करें'],
    gst: ['Prices include GST where applicable.', 'क़ीमत में लागू GST शामिल है।'], secure: ['Secure checkout · Login with email OTP', 'सुरक्षित चेकआउट · ईमेल OTP से लॉगिन']
  };
  var CSSX = '.co{display:grid;gap:18px;grid-template-columns:minmax(0,1fr);align-items:start}@media(min-width:960px){.co{grid-template-columns:minmax(0,1.15fr) minmax(0,.85fr)}}' +
    '.co-card{background:#fff;border:1px solid var(--line,#dce5da);border-radius:16px;padding:16px}.co-card h2{font-size:18px;margin:0 0 12px}' +
    '.co-i{display:grid;grid-template-columns:64px minmax(0,1fr);gap:12px;padding:10px 0;border-bottom:1px solid var(--line,#e6ece4)}.co-i:last-child{border:0}.co-img{width:64px;height:64px;border-radius:12px;background:#e7f3e9;display:grid;place-items:center;font-size:28px;overflow:hidden;position:relative}.co-img img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}' +
    '.co-i b{display:block;overflow-wrap:anywhere}.co-r{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:6px;flex-wrap:wrap}.co-q{display:inline-flex;align-items:center;border:1px solid var(--line,#cfd8cf);border-radius:10px;overflow:hidden}.co-q button{border:0;background:#f3f7f2;width:34px;height:34px;font-size:18px;cursor:pointer}.co-q span{min-width:34px;text-align:center;font-weight:700}' +
    '.co-rm{border:0;background:none;color:#c8372d;cursor:pointer;font:inherit;font-size:13px}.co-na{color:#c8372d;font-size:13px;margin-top:4px}' +
    '.co-g{display:grid;gap:10px;grid-template-columns:minmax(0,1fr)}@media(min-width:560px){.co-g.two{grid-template-columns:repeat(2,minmax(0,1fr))}}.co-f label{display:block;font-weight:600;font-size:13.5px;margin-bottom:4px}.co-f input,.co-f textarea{width:100%;box-sizing:border-box;padding:11px 12px;border:1px solid var(--line,#cfd8cf);border-radius:12px;font:inherit;background:#fff;color:inherit}.co-f textarea{min-height:64px}' +
    '.co-e{color:#c8372d;font-size:12.5px;margin-top:3px}.co-pm{display:grid;gap:8px;margin-top:6px}.co-po{display:flex;gap:10px;align-items:flex-start;border:1.5px solid var(--line,#cfd8cf);border-radius:12px;padding:10px 12px;cursor:pointer}.co-po.on{border-color:var(--leaf,#1e8e3e);background:#f1f9f2}.co-po small{display:block;color:var(--mute,#5a6b5f)}' +
    '.co-t{display:grid;gap:6px;margin-top:14px;background:#f1f7f2;border-radius:12px;padding:12px}.co-t div{display:flex;justify-content:space-between;gap:8px}.co-t .g{font-weight:800;font-size:17px;border-top:1px dashed #b9cbbb;padding-top:8px}' +
    '.co-cons{display:flex;gap:8px;align-items:flex-start;font-size:13.5px;margin-top:12px}.co-fail{background:#fdecea;border-radius:12px;padding:10px 12px;margin-top:12px;color:#8a1f17}.co-ok{text-align:center;padding:24px 16px}.co-ok .tick{font-size:44px}' +
    '.co-upi{display:flex;gap:8px;align-items:center;justify-content:space-between;background:#f1f7f2;border-radius:12px;padding:10px 12px;margin:10px 0;flex-wrap:wrap}.co-act{display:grid;gap:8px;margin-top:12px}.co-sec{font-size:12.5px;color:var(--mute,#5a6b5f);margin:8px 0 0;text-align:center}';
  var st = document.createElement('style'); st.textContent = CSSX; document.head.appendChild(st);

  var C = window.SPCART, ST = null, placing = false, form = {}, mode = '';
  function lg() { return C && C.lang ? C.lang() : 'en'; }
  function t(k) { return TX[k] ? TX[k][lg() === 'hi' ? 1 : 0] : k; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function num(x) { x = Number(x); return isFinite(x) ? x : 0; }
  function digits(v) { return String(v || '').replace(/\D/g, ''); }
  function money(n) { return '₹' + Math.round(num(n)).toLocaleString('en-IN'); }
  function lsGet(k, d) { try { var v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }
  function lsSet(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  function cleanPhone(v) { var d = digits(v); if (d.length === 12 && d.indexOf('91') === 0) d = d.slice(2); if (d.length === 11 && d[0] === '0') d = d.slice(1); return d; }
  function S() { return (ST && ST.settings) || {}; }
  function trk(kind, val) { try { if (window.SPTRK) SPTRK.ev(kind, '', val || 0, 'checkout.html'); } catch (e) {} }
  function waNum() { var w = digits(S().whatsapp || (window.SITE && SITE.WHATSAPP) || '9621050636'); return w.length === 10 ? '91' + w : w; }
  function waLink(text) { return 'https://wa.me/' + waNum() + '?text=' + encodeURIComponent(text); }

  function payModes() {
    var p = S().payments || {}, m = [];
    /* sab products PREPAID — Cash on Delivery band hai */
    if (p.upi && p.upi.enabled) m.push({ k: 'upi', label: p.upi.label || 'UPI', desc: (lg() === 'hi' ? 'पूरा पेमेंट UPI से' : 'Pay in full by UPI') + (p.upi.upiId ? ' • ' + p.upi.upiId : '') });
    return m;
  }
  function calc(total, m) {
    var pct = num(((S().payments || {}).cod || {}).advancePct);
    return { adv: total, due: 0 };
  }
  /* Round 48: delivery charge ka asli hisaab server deta hai (sp_ship_quote); cache na ho to purani setting se andaza */
  var SQ = {};
  function qItems() { return lines().filter(function (l) { return !l.out; }).map(function (l) { return { id: l.p.id, qty: l.qty, price: C.price(l.p) }; }); }
  function qKey(pin, sub, pick) { return digits(pin) + '|' + (pick ? 'P' : '') + '|' + Math.round(sub) + '|' + qItems().map(function (i) { return i.id + 'x' + i.qty; }).join(','); }
  function shipFetch(pin, sub, pick) {
    var k = qKey(pin, sub, pick); if (SQ[k]) return Promise.resolve(SQ[k]);
    if (digits(pin).length !== 6 && !pick) return Promise.resolve(null);
    return C.rpc('sp_ship_quote', { p_pin: digits(pin), p_items: qItems(), p_subtotal: sub, p_pickup: !!pick }, 12000).then(function (q) { if (q) SQ[k] = q; return q || null; }, function () { return null; });
  }
  function shipFor(sub, pin, pick) {
    var q = SQ[qKey(pin, sub, pick)];
    if (q) return { charge: num(q.charge), known: q.known !== false, server: true, reason: q.reason, courier: q.courier || '', etaMin: q.eta_min || 0, etaMax: q.eta_max || 0 };
    if (pick) return { charge: 0, known: true };
    var sh = S().shipping || {};
    if (sh.enabled === false) return { charge: 0, known: true };
    if (num(sh.freeAbove) > 0 && sub >= num(sh.freeAbove)) return { charge: 0, known: true };
    pin = digits(pin);
    var local = String(sh.localPins || '').split(/[,\s]+/).filter(Boolean).some(function (p) { return pin.indexOf(p) === 0; });
    if (pin.length !== 6) return { charge: num(sh.otherCharge), known: false };
    return { charge: local ? num(sh.localCharge) : num(sh.otherCharge), known: true };
  }
  function shipInfo(sh) {
    if (!sh || !sh.server) return '';
    var bits = []; if (sh.reason === 'project') bits.push(t('projFree')); if (sh.courier) bits.push('🚚 ' + t('viaL') + ' ' + esc(sh.courier)); if (sh.etaMax && !(C.sellEtaOn && C.sellEtaOn(lines().map(function (l) { return l.p.id; })))) bits.push((sh.etaMin && sh.etaMin !== sh.etaMax ? sh.etaMin + '–' : '') + sh.etaMax + ' ' + t('daysL'));
    return bits.length ? '<div><span></span><small>' + bits.join(' • ') + '</small></div>' : '';
  }
  function lines() {
    return C.getCart().map(function (c) { var p = C.prod(c.id); return p ? { p: p, qty: Math.max(1, Math.min(999, c.qty)), out: p.stock === 'out' } : null; }).filter(Boolean);
  }
  function subtotal() { return lines().reduce(function (a, l) { return l.out ? a : a + C.price(l.p) * l.qty; }, 0); }
  function img(p) { var u = p.image || (p.images && p.images[0]) || ''; return /^https?:\/\//i.test(u) ? u : ''; }

  function readForm() {
    var g = function (id) { var e = document.getElementById(id); return e ? e.value : ''; };
    if (!document.getElementById('co-name')) return;
    form = { name: g('co-name'), phone: g('co-phone'), addr: g('co-addr'), city: g('co-city'), pin: g('co-pin'), note: g('co-note'), pickup: !!(document.getElementById('co-pickup') || {}).checked, inst: instPicked() };
    var pm = root.querySelector('input[name=pm]:checked'); if (pm) mode = pm.value; var ck0 = document.getElementById('co-ok'); if (ck0) form.ok = ck0.checked;
    lsSet('sp_wcust', { name: form.name, phone: form.phone, addr: form.addr, city: form.city, pin: form.pin, pay: mode });
  }
  function instBlock() {
    var a = lines().filter(function (l) { return !l.out && l.p.installOk; }); if (!a.length) return '';
    var hi = lg() === 'hi';
    return '<div class="co-card" style="margin-top:10px;padding:10px 12px;background:#eef6ef"><b>🔧 ' + (hi ? 'इंस्टालेशन (वैकल्पिक)' : 'Installation (optional)') + '</b>' +
      a.map(function (l) { var p = l.p; return '<label class="co-cons" style="margin-top:6px"><input type="checkbox" class="co-inst" value="' + esc(p.id) + '"' + (form.inst && form.inst.indexOf(p.id) >= 0 ? ' checked' : '') + '><span>' + esc(lg() === 'en' && p.titleEn ? p.titleEn : p.title) + (num(p.installPrice) > 0 ? ' — +' + money(num(p.installPrice)) : '') + '</span></label>'; }).join('') +
      '<div style="font-size:12.5px;margin-top:6px;opacity:.75">' + (hi ? 'इंस्टालेशन का चार्ज order total में नहीं जुड़ता — हमारी टीम आपसे बात करके अलग से बिल बनाएगी।' : 'Installation is not added to the order total — our team will contact you and bill it separately.') + '</div></div>';
  }
  function instPicked() { return Array.prototype.map.call(document.querySelectorAll('.co-inst:checked'), function (e) { return e.value; }); }
  function fld(id, label, val, type, extra) { return '<div class="co-f"><label for="' + id + '">' + esc(label) + '</label><input id="' + id + '"' + (type ? ' type="' + type + '"' : '') + ' ' + (extra || '') + ' value="' + esc(val || '') + '"><div class="co-e" hidden></div></div>'; }
  function ferr(id, msg) { var el = document.getElementById(id); if (!el) return; var e = el.parentNode.querySelector('.co-e'); if (!e) return; e.textContent = msg || ''; e.hidden = !msg; }

  function render() {
    var ae = document.activeElement, aid = ae && ae.id && root.contains(ae) ? ae.id : '', as = null; try { as = ae && ae.selectionStart != null ? [ae.selectionStart, ae.selectionEnd] : null; } catch (e) {}
    var L = lines();
    if (!L.length) { root.innerHTML = '<div class="co-card" style="text-align:center;padding:36px 16px"><div style="font-size:42px">🛒</div><p>' + esc(t('empty')) + '</p><a class="btn btn-sun" href="shop.html">' + esc(t('shop')) + '</a></div>'; return; }
    var modes = payModes(), pol = S().policyConsent !== false;
    if (!mode || !modes.some(function (m) { return m.k === mode; })) mode = (modes[0] || {}).k || '';
    var anyBad = L.some(function (l) { return l.out || C.unavail(l.p.id); });
    root.innerHTML = '<div class="co"><div><div class="co-card"><h2>🛒 ' + esc(t('cart')) + ' (' + L.length + ')</h2>' + L.map(function (l) {
      var p = l.p, bad = C.unavail(p.id), u = img(p);
      return '<div class="co-i"><div class="co-img"><span>' + esc(p.emoji || '☀️') + '</span>' + (u ? '<img src="' + esc(u) + '" alt="" loading="lazy" onerror="this.remove()">' : '') + '</div><div><b data-noi18n>' + esc(C.ptitle(p)) + '</b>' +
        '<div><strong>' + money(C.price(p)) + '</strong>' + (num(p.mrp) > C.price(p) ? ' <s style="color:#7a8a7e;font-size:12.5px">' + money(p.mrp) + '</s>' : '') + (p.unit ? '<small> /' + esc(p.unit) + '</small>' : '') + '</div>' +
        (l.out ? '<div class="co-na">' + esc(t('out')) + '</div>' : (bad ? '<div class="co-na">⚠️ ' + esc(C.naText ? C.naText() : t('na')) + '</div>' : '')) +
        '<div class="co-r"><div class="co-q"><button type="button" data-q="-1" data-id="' + esc(p.id) + '" aria-label="-">−</button><span>' + l.qty + '</span><button type="button" data-q="1" data-id="' + esc(p.id) + '" aria-label="+">+</button></div><button type="button" class="co-rm" data-rm="' + esc(p.id) + '">' + esc(t('remove')) + '</button></div></div></div>';
    }).join('') + '</div></div>' +
      '<form class="co-card" id="coForm" novalidate><h2>📦 ' + esc(t('deliver')) + '</h2><div class="co-g two">' + fld('co-name', t('name') + ' *', form.name, '', 'autocomplete="name" maxlength="80"') + fld('co-phone', t('phone') + ' *', form.phone, 'tel', 'inputmode="numeric" autocomplete="tel" maxlength="18"') + '</div>' +
      '<div class="co-g" style="margin-top:10px">' + fld('co-addr', t('addr') + ' *', form.addr, '', 'autocomplete="street-address" maxlength="250"') + '</div>' +
      '<div class="co-g two" style="margin-top:10px">' + fld('co-city', t('city'), form.city, '', 'maxlength="60"') + fld('co-pin', t('pin') + ' *', form.pin, 'tel', 'inputmode="numeric" maxlength="6" autocomplete="postal-code"') + '</div>' + '<div class="co-note" id="co-sell" style="margin-top:8px;font-size:13px;line-height:1.6"></div><div id="co-sub" style="margin-top:8px;font-size:13px;line-height:1.6;background:#f2faf4;border:1px solid #bfe0c7;border-radius:8px;padding:8px 10px" hidden></div>' + (S().pickup === false ? '' : '<label class="co-cons" style="margin-top:8px"><input type="checkbox" id="co-pickup"' + (form.pickup ? ' checked' : '') + '><span>' + esc(t('pickupL')) + '</span></label>') +
      instBlock() +
      '<div class="co-f" style="margin-top:10px"><label for="co-note">' + esc(t('note')) + '</label><textarea id="co-note" maxlength="500">' + esc(form.note || '') + '</textarea></div>' +
      '<h2 style="margin-top:16px">💳 ' + esc(t('pay')) + '</h2>' + (modes.length ? '<div class="co-pm">' + modes.map(function (m) { return '<label class="co-po' + (m.k === mode ? ' on' : '') + '"><input type="radio" name="pm" value="' + m.k + '"' + (m.k === mode ? ' checked' : '') + '><span><b>' + esc(m.label) + '</b><small>' + esc(m.desc) + '</small></span></label>'; }).join('') + '</div><div class="co-e" id="co-pme" hidden></div>' : '<p>' + esc(t('noPay')) + '</p>') +
      '<div class="co-t" id="coTot"></div><p class="co-sec">✔ ' + esc(S().gstNote || t('gst')) + (S().delivery ? ' • 🚚 ' + esc(S().delivery) : '') + '</p>' +
      '<div id="coTerms"></div>' +
      (pol ? '<label class="co-cons"><input type="checkbox" id="co-ok"' + (form.ok ? ' checked' : '') + '><span>' + esc(t('consent')) + ' <a href="refund-policy.html" target="_blank" rel="noopener">' + esc(t('cons2')) + '</a>, <a href="shipping-policy.html" target="_blank" rel="noopener">' + esc(t('cons3')) + '</a> & <a href="terms.html" target="_blank" rel="noopener">' + esc(t('cons4')) + '</a></span></label><div class="co-e" id="co-oke" hidden></div>' : '') +
      '<div class="co-fail" id="coFail" hidden></div><div class="co-act">' + (modes.length ? '<button type="submit" class="btn btn-sun" id="coPlace"' + (anyBad ? ' disabled' : '') + '>✅ ' + esc(t('place')) + '</button>' : '') + '<button type="button" class="btn btn-wa" id="coWa">💬 ' + esc(t('wa')) + '</button></div>' +
      (anyBad ? '<p class="co-na" style="text-align:center">' + esc(t('naMsg')) + '</p>' : '') + '<p class="co-sec">🔒 ' + esc(t('secure')) + '</p></form></div>';
    totals(); bind(); termsLoad(); sellPaint();
    if (aid) { var fe = document.getElementById(aid); if (fe && fe.focus) { fe.focus(); try { if (as) fe.setSelectionRange(as[0], as[1]); } catch (e) {} } }
  }
  function totals() {
    var el = document.getElementById('coTot'); if (!el) return;
    readForm(); var sub = subtotal(), sh = shipFor(sub, form.pin, form.pickup), grand = sub + (sh.known ? sh.charge : 0), r = calc(grand, mode);
    if (!sh.server && (digits(form.pin).length === 6 || form.pickup)) shipFetch(form.pin, sub, form.pickup).then(function (q) { if (q && document.getElementById('coTot')) totals(); });
    el.innerHTML = '<div><span>' + esc(t('sub')) + '</span><b>' + money(sub) + '</b></div><div><span>' + esc(t('ship')) + '</span><b>' + (sh.known ? (sh.charge ? money(sh.charge) : esc(t('free'))) : '<small>' + esc(t('pinFirst')) + '</small>') + '</b></div>' + shipInfo(sh) +
      (mode === 'cod' ? '<div><span>' + esc(t('grand')) + '</span><b>' + money(grand) + '</b></div><div><span>' + esc(t('adv')) + '</span><b>' + money(r.adv) + '</b></div><div><span>' + esc(t('due')) + '</span><b>' + money(r.due) + '</b></div>' : '') +
      '<div class="g"><span>' + esc(mode === 'cod' ? t('adv') : t('total')) + '</span><span>' + money(r.adv) + '</span></div>';
    Array.prototype.forEach.call(root.querySelectorAll('.co-po'), function (l) { var i = l.querySelector('input'); l.classList.toggle('on', i && i.checked); });    if (TERMS && termKinds().join(',') !== TKEYK) termsLoad();
  }
  function badSig() { var b = C.pinBad(); return Object.keys(b).sort().join(',') + '|' + (C.pinOn() ? 1 : 0); }
  var pinT = null;
  var sellPin = '';
  function subPaint() {
    var b = document.getElementById('co-sub'); if (!b || !C.subLine) return;
    var ls = lines().filter(function (l) { return !l.out; }), tot = ls.reduce(function (a, l) { return a + C.price(l.p) * l.qty; }, 0), h = C.subLine(ls.map(function (l) { return { id: l.p.id, qty: l.qty }; }), tot);
    b.innerHTML = h; b.hidden = !h;
  }
  function sellPaint() {
    var el = document.getElementById('co-sell'); if (!el || !C.sellLine) return;
    var pin = digits(form.pin || ''), h = C.sellLine(lines().map(function (l) { return l.p.id; })); el.innerHTML = h;
    subPaint();
    if (!h && pin.length === 6 && pin !== sellPin) { sellPin = pin; C.pinSync(pin).then(function () { var e2 = document.getElementById('co-sell'); if (e2) e2.innerHTML = C.sellLine(lines().map(function (l) { return l.p.id; })); subPaint(); }); }
  }
  function pinCheck() {
    var pin = digits(form.pin); if (pin.length !== 6) return Promise.resolve([]);
    var ids = lines().map(function (l) { return l.p.id; });
    return C.rpc('sp_pin_check', { p_pin: pin, p_ids: ids }, 12000).then(function (r) { return (r && r.enabled && r.bad) || []; }, function () { return []; });
  }
  function bind() {
    var cf = root.querySelector('#coForm'); if (cf) cf.addEventListener('submit', function (e) { e.preventDefault(); place(); });
    var wa = document.getElementById('coWa'); if (wa) wa.onclick = function () { readForm(); window.open(waLink(orderText(null, null)), '_blank', 'noopener'); };
    Array.prototype.forEach.call(root.querySelectorAll('input[name=pm]'), function (r) { r.addEventListener('change', totals); });
    Array.prototype.forEach.call(root.querySelectorAll('.co-inst'), function (c) { c.addEventListener('change', termsLoad); });
    var pkb = document.getElementById('co-pickup'); if (pkb) pkb.addEventListener('change', function () { totals(); });
    var pn = document.getElementById('co-pin'); if (pn) pn.addEventListener('input', function () { totals(); clearTimeout(pinT); pinT = setTimeout(function () { readForm(); if (digits(form.pin).length === 6) { var sg0 = badSig(); C.pinSync(digits(form.pin)).then(function () { if (document.getElementById('coForm') && !placing && badSig() !== sg0) { readForm(); render(); } sellPaint(); }); } }, 500); });
  }
  function onClick(e) {
    var q = e.target.closest && e.target.closest('[data-q],[data-rm]'); if (!q) return;
    readForm(); var c = C.getCart(), id = q.getAttribute('data-id') || q.getAttribute('data-rm'), it = c.filter(function (x) { return x.id === id; })[0]; if (!it) return;
    if (q.hasAttribute('data-rm')) c = c.filter(function (x) { return x.id !== id; }); else it.qty = Math.max(1, Math.min(99, it.qty + (+q.getAttribute('data-q'))));
    C.setCart(c); render();
  }
  function orderText(id, ono) {
    var sub = subtotal(), sh = shipFor(sub, form.pin), total = sub + (sh.known ? sh.charge : 0), r = calc(total, mode);
    var pm = mode === 'cod' ? 'Cash on Delivery (' + Math.round(num(((S().payments || {}).cod || {}).advancePct)) + '% advance)' : mode === 'upi' ? 'UPI' : '-';
    return '🛒 *' + (id ? 'Order ' + (ono || '#' + id) : 'New Order') + '* — ' + (S().storeName || 'Sunpowers') + '\n\n' + lines().filter(function (l) { return !l.out; }).map(function (l, i) { return (i + 1) + '. ' + C.ptitle(l.p) + ' × ' + l.qty + ' = ' + money(C.price(l.p) * l.qty); }).join('\n') +
      '\n\n*Subtotal:* ' + money(sub) + '\n*Delivery:* ' + (sh.known ? (sh.charge ? money(sh.charge) : 'Free') : 'as per pincode') + '\n*Total:* ' + money(total) + '\n*Payment:* ' + pm + (mode === 'cod' ? '\n*Pay now:* ' + money(r.adv) + '\n*On delivery:* ' + money(r.due) : '') +
      '\n\n*Name:* ' + (form.name || '') + '\n*Mobile:* ' + (form.phone || '') + '\n*Address:* ' + (form.addr || '') + (form.city ? ', ' + form.city : '') + (form.pin ? ' - ' + form.pin : '') + (form.note ? '\n*Note:* ' + form.note : '');
  }

  /* ---- Round 58: order se pehle Disclaimer (text DB se: sp_terms) — tick ke bina order nahi ---- */
  var TERMS = null, TKEYK = '', TOK = false, TLOAD = 0;
  function termKinds() { var k = ['product']; try { var sh = shipFor(subtotal(), form.pin, !!form.pickup); if (instPicked().length || (sh && sh.reason === 'project')) k.push('install'); } catch (e) {} return k; }
  function termsPaint() {
    var box = document.getElementById('coTerms'); if (!box) return;
    if (!TERMS) { box.innerHTML = '<p class="co-na">' + esc(lg() === 'en' ? 'Loading important terms…' : 'ज़रूरी शर्तें लोड हो रही हैं…') + '</p>'; return; }
    box.innerHTML = '<label class="co-cons" style="margin-top:12px;font-weight:600"><input type="checkbox" id="co-terms"' + (TOK ? ' checked' : '') + '><span>' + esc(lg() === 'en' ? 'I agree to the ' : 'मैं ') + '<a href="#" id="co-tv">' + esc(lg() === 'en' ? 'Disclaimer & Terms' : 'डिस्क्लेमर / शर्तों') + '</a>' + esc(lg() === 'en' ? '.' : ' से सहमत हूँ।') + '</span></label>' +
      '<div id="co-tb" hidden style="max-height:36vh;overflow:auto;font-size:11.5px;line-height:1.45;color:#5d6f62;border:1px solid #dfe8e0;border-radius:10px;padding:8px 10px 8px 4px;margin-top:6px;background:#fff">' + TERMS.items.map(function (it) {
        return '<b style="margin-left:6px;color:#1c2b20">' + esc(it.title.h) + '</b><ol style="padding-left:22px;margin:4px 0 8px">' + it.points.map(function (p) { return '<li style="margin:4px 0">' + esc(p.h) + (p.e && p.e !== p.h ? '<br>' + esc(p.e) : '') + '</li>'; }).join('') + '</ol>'; }).join('') + '</div><div class="co-e" id="co-termse" hidden></div>';
    var tv = document.getElementById('co-tv'); if (tv) tv.addEventListener('click', function (e) { e.preventDefault(); var b = document.getElementById('co-tb'); b.hidden = !b.hidden; });
    var c = document.getElementById('co-terms'); if (c) c.addEventListener('change', function () { TOK = c.checked; var e = document.getElementById('co-termse'); if (e) e.hidden = true; });
  }
  function termsLoad() {
    var kinds = termKinds(), key = kinds.join(',');
    if (TERMS && key === TKEYK) { termsPaint(); return; }
    var my = ++TLOAD; termsPaint();
    C.rpc('sp_terms', { p_kinds: kinds }, 12000).then(function (r) { if (my !== TLOAD) return; if (r && r.items) { if (TERMS && TERMS.ver !== r.ver) TOK = false; TERMS = r; TKEYK = key; } termsPaint(); }, function () { if (my === TLOAD) termsPaint(); });
  }
  function validate() {
    readForm(); var ok = true, d = { name: form.name.trim(), phone: cleanPhone(form.phone), addr: form.addr.trim(), pin: digits(form.pin) };
    ferr('co-name', d.name.length >= 2 ? '' : (ok = false, t('reqName'))); ferr('co-phone', /^[6-9]\d{9}$/.test(d.phone) ? '' : (ok = false, t('reqPhone')));
    ferr('co-addr', d.addr.length >= 5 ? '' : (ok = false, t('reqAddr'))); ferr('co-pin', /^\d{6}$/.test(d.pin) ? '' : (ok = false, t('reqPin')));
    var pe = document.getElementById('co-pme'); if (pe) { pe.textContent = mode ? '' : t('reqPay'); pe.hidden = !!mode; if (!mode) ok = false; }
    var tk = document.getElementById('co-terms'), te = document.getElementById('co-termse'); if (!TERMS || !tk || !tk.checked) { ok = false; if (te) { te.textContent = !TERMS ? (lg() === 'en' ? 'Terms are loading — please wait a moment and try again' : 'शर्तें लोड हो रही हैं — थोड़ी देर बाद फिर कोशिश करें') : (lg() === 'en' ? 'Please tick to agree to the disclaimer' : 'डिस्क्लेमर से सहमत होने के लिए टिक करें'); te.hidden = false; } }
    var ck = document.getElementById('co-ok'), ce = document.getElementById('co-oke'); if (ck && ce) { ce.textContent = ck.checked ? '' : t('reqOk'); ce.hidden = ck.checked; if (!ck.checked) ok = false; }
    if (!ok) { var f = root.querySelector('.co-e:not([hidden])'); if (f && f.scrollIntoView) f.parentNode.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
    return ok;
  }
  function failBox(msg, extra) { var f = document.getElementById('coFail'); if (!f) return; f.innerHTML = '⚠️ ' + esc(msg) + (extra ? '<br><small>' + esc(extra) + '</small>' : '') + '<a class="btn btn-wa" style="margin-top:8px;display:flex" target="_blank" rel="noopener" href="' + esc(waLink(orderText(null, null))) + '">💬 ' + esc(t('wa')) + '</a>'; f.hidden = false; f.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
  async function place() {
    if (placing || !validate()) return;
    var bad = await pinCheck(); if (bad.length) { C.pinSync(digits(form.pin)).then(render); return; }
    if (!window.SPGate || !SPGate.active()) return failBox(t('fail'), 'login unavailable');
    trk('checkout', subtotal());
    SPGate.require('order', async function () {
      if (placing) return; placing = true; var btn = document.getElementById('coPlace'); if (btn) { btn.disabled = true; btn.textContent = t('placing'); }
      var sub = subtotal(), pk = !!form.pickup; try { await shipFetch(form.pin, sub, pk); } catch (e) {} var sh = shipFor(sub, form.pin, pk), total = sub + sh.charge, r = calc(total, mode), ls = lines().filter(function (l) { return !l.out; }).map(function (l) { var pr = C.price(l.p); return { id: l.p.id, title: l.p.title, titleEn: l.p.titleEn, sku: l.p.sku, gst: l.p.gst, qty: l.qty, price: pr, amount: pr * l.qty }; });
      var ck = document.getElementById('co-ok');
      var order = { name: form.name.trim(), phone: cleanPhone(form.phone), address: form.addr.trim(), city: form.city.trim(), pincode: digits(form.pin), note: form.note.trim(), payment: mode, items: ls, subtotal: sub, shipping: sh.charge, pickup: pk, install: (form.inst || []), total: total, advance: r.adv, due: r.due,
        terms_ok: !!(TERMS && TOK), terms_ver: TERMS ? TERMS.ver : '', terms_kinds: TERMS ? TERMS.items.map(function (i) { return i.k; }) : [], policyAccepted: !!(ck && ck.checked), lang: lg(), page: location.origin + location.pathname, src: 'shop', token: SPGate.token() };
      var id = null, err = null, ono = null;
      try { id = await C.rpc('sp_place_order', { p_order: order }, 20000); } catch (e) { err = e; }
      if (id) { try { ono = await C.rpc('sp_order_no', { p_id: id, p_token: SPGate.token() }, 12000); } catch (e) { ono = null; } }
      placing = false;
      if (!id) { if (btn) { btn.disabled = false; btn.textContent = '✅ ' + t('place'); } return failBox(t('fail'), err && /OUT_OF_STOCK/.test(err.message || '') ? ((lg() === 'en' ? 'Sorry, someone just booked this — not enough stock: ' : 'माफ़ कीजिए, अभी इतना स्टॉक नहीं बचा (किसी और का ऑर्डर आ चुका है): ') + String(err.message).replace(/^OUT_OF_STOCK:\s*/, '')) : err && /DELIVERY_CHANGED/.test(err.message || '') ? (t('shipChg') + ' ' + String(err.message).replace(/^DELIVERY_CHANGED:\s*/, '')) : err && /PRICE_CHANGED/.test(err.message || '') ? ((lg() === 'en' ? 'The price was updated just now — please refresh this page (Ctrl+F5) and check the new price: ' : 'अभी कीमत अपडेट हुई है — पेज रिफ़्रेश (Ctrl+F5) करके नई कीमत देखें: ') + String(err.message).replace(/^PRICE_CHANGED:\s*/, '')) : (err && err.message)); }
      var my = lsGet('sp_worders', []); if (!Array.isArray(my)) my = []; my.unshift({ id: id, no: ono || '', at: Date.now(), total: total, adv: r.adv, pay: mode }); lsSet('sp_worders', my.slice(0, 30));
      var text = orderText(id, ono); C.setCart([]); trk('order', total); success(id, ono, r, text);
    });
  }
  function payLinks(amount) {
    var L = (S().payments && S().payments.links) || {}, out = [];
    [['gpay', 'Google Pay'], ['phonepe', 'PhonePe'], ['paytm', 'Paytm']].forEach(function (x) { var v = L[x[0]]; if (v && v.enabled !== false && /^https:\/\//i.test(v.url || '')) out.push('<a class="btn btn-line" target="_blank" rel="noopener" href="' + esc(v.url) + '">💳 ' + x[1] + ' — ' + money(amount) + '</a>'); });
    var o = L.other; if (o && o.enabled !== false && o.label && /^https:\/\//i.test(o.url || '')) out.push('<a class="btn btn-line" target="_blank" rel="noopener" href="' + esc(o.url) + '">💳 ' + esc(o.label) + '</a>');
    return out.join('');
  }
  function success(id, ono, r, text) {
    var u = (S().payments || {}).upi || {}, link = u.upiId ? 'upi://pay?pa=' + encodeURIComponent(u.upiId) + '&pn=' + encodeURIComponent(u.payeeName || S().storeName || 'Sunpowers') + '&am=' + encodeURIComponent(Number(r.adv).toFixed(2)) + '&cu=INR&tn=' + encodeURIComponent('Order ' + id) : '';
    history.replaceState({}, '', 'checkout.html?done=1');
    root.innerHTML = '<div class="co-card co-ok"><div class="tick">✅</div><h2>' + esc(t('done')) + '</h2><p>' + esc(t('ono')) + ': <b id="coOrderNo">' + esc(ono || ('#' + id)) + '</b></p>' +
      '<div class="co-upi" style="text-align:left"><span>' + esc(mode === 'cod' ? t('advNote') : t('fullNote')) + '<br><b>' + esc(mode === 'cod' ? t('adv') : t('total')) + ': ' + money(r.adv) + '</b>' + (mode === 'cod' ? ' · ' + esc(t('due')) + ': ' + money(r.due) : '') + '</span></div>' +
      (u.upiId ? '<div class="co-upi"><span>' + esc(t('upi')) + ': <b id="coUpi">' + esc(u.upiId) + '</b></span><button type="button" class="btn btn-line btn-sm" id="coCopy">' + esc(t('copy')) + '</button></div><div class="co-act"><a class="btn btn-sun" href="' + esc(link) + '">📱 ' + esc(t('payNow')) + ' — ' + money(r.adv) + '</a></div>' : '') +
      '<div class="co-act">' + payLinks(r.adv) + '</div>' +
      '<div class="co-upi" style="text-align:left;display:block"><b>' + esc(t('utrQ')) + '</b><div style="display:flex;gap:8px;margin-top:8px"><input id="coUtr" maxlength="30" placeholder="UTR" style="flex:1;min-width:0;padding:10px;border:1px solid #cfd8cf;border-radius:10px"><button type="button" class="btn btn-sun btn-sm" id="coUtrGo">' + esc(t('utrGo')) + '</button></div><div id="coUtrMsg" style="margin-top:8px" hidden></div></div>' +
      '<div class="co-upi" style="text-align:left;display:block;background:#fff8e1;border-color:#f0d58a">ℹ️ ' + esc(lg() === 'hi' ? 'पेमेंट और लोकेशन वेरिफ़ाई होने के बाद Invoice आपकी Orders details में दिखेगा — वहीं से डाउनलोड कर सकते हैं।' : 'After verification of payment & Location, Invoice will appear on your Orders details — you can download it from there.') + '<br><small>' + esc(lg() === 'hi' ? 'UTR / स्लिप डालना ज़रूरी नहीं — हमारी टीम आपको कॉल करेगी। सभी ऑर्डर प्रीपेड हैं।' : 'UTR / slip is optional — our team will call you. All orders are prepaid.') + '</small></div>' +
      '<div class="co-act"><a class="btn btn-wa" target="_blank" rel="noopener" href="' + esc(waLink(text)) + '">💬 ' + esc(t('wa')) + '</a><a class="btn btn-line" href="shop.html">' + esc(t('more')) + '</a><a class="btn btn-line" href="orders.html">🧾 ' + esc(lg() === 'hi' ? 'मेरे ऑर्डर / Invoice' : 'My Orders / Invoice') + '</a></div></div>';
    var cp = document.getElementById('coCopy'); if (cp) cp.onclick = function () { try { navigator.clipboard.writeText(u.upiId); } catch (e) {} cp.textContent = t('copied'); };
    document.getElementById('coUtrGo').onclick = async function () {
      var b = this, m = document.getElementById('coUtrMsg'); b.disabled = true;
      try { var res = await C.rpc('sp_submit_utr', { p: { token: SPGate.token(), id: String(id), utr: document.getElementById('coUtr').value } }, 15000); m.hidden = false; m.innerHTML = '✅ ' + esc((res && res.message) || ''); b.textContent = '✔'; document.getElementById('coUtr').disabled = true; }
      catch (e) { m.hidden = false; m.innerHTML = '⚠️ ' + esc((e && e.message) || 'Error'); b.disabled = false; }
    };
    window.scrollTo(0, 0);
  }

  function prefill() {
    var sv = lsGet('sp_wcust', {}) || {}; form = { name: sv.name || '', phone: sv.phone || '', addr: sv.addr || '', city: sv.city || '', pin: sv.pin || '', note: '' }; mode = sv.pay || '';
    var qp = (location.search.match(/[?&]pin=(\d{6})/) || [])[1]; if (qp && !form.pin) form.pin = qp; if (!form.pin) form.pin = C.pinGet() || '';
    if (window.SPGate && SPGate.active() && SPGate.token()) return SPGate.me().then(function (r) { var me = r && r.me; if (me) { var m = me.meta || {}; form.name = form.name || me.name || ''; form.phone = form.phone || me.mobile || ''; form.addr = form.addr || m.address || ''; form.city = form.city || m.city || ''; form.pin = form.pin || m.pincode || ''; } }, function () {});
    return Promise.resolve();
  }
  function boot() {
    if (!window.SPCART) { root.innerHTML = '<p>' + esc(t('loadFail')) + '</p>'; return; }
    root.innerHTML = '<p style="color:var(--mute,#5a6b5f)">…</p>';
    if (/[?&]done=1/.test(location.search)) { history.replaceState({}, '', 'checkout.html'); }
    C.load().then(function (s) {
      if (!s) { root.innerHTML = '<p>' + esc(t('loadFail')) + '</p>'; return; }
      ST = s;
      return prefill().then(function () { return digits(form.pin).length === 6 ? C.pinSync(digits(form.pin)) : null; }).then(render);
    });
  }
  root.addEventListener('click', onClick);
  document.addEventListener('sp-lang', function () { if (ST && document.getElementById('coForm')) { readForm(); render(); } });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
