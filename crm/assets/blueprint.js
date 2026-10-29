/* =====================================================================
   Sunpowers Project Blueprint — loader (same file in Website, Store and CRM)
   The Solar Designer lives in designer.html (own page, own 3D engine).
   This file only: shows it inside the page, gives it the customer, the map
   token and the language, and passes "Send / Save" to the app's own server
   call (onSubmit for Website + Store, onSave for CRM).
   Use: SPBlueprint.mount(el, { mode:'public'|'crm', customer, initial, recordId,
        noDraft, targetKw, whatsapp, links:{store,storeLabel,site,siteLabel}, onSubmit, onSave })
   ===================================================================== */
(function () {
  'use strict';
  if (window.SPBlueprint) return;
  /* Mapbox PUBLIC token (pk.…). Safe to be seen in a browser: lock it to your websites in your Mapbox account.
     Change it in one place: set  MAPBOX_TOKEN  in config.js (SITE / SP_CONFIG / CRM_CONFIG). */
  var DEFAULT_TOKEN = 'pk.eyJ1Ijoic3VucG93ZXJzIiwiYSI6ImNtdmhsYjUxdjBkOGsyd3F1YzEyZHRlMHcifQ.gbhT7v8k9l37EsRSsIBqbg';
  var VER = '9';
  var CS = document.currentScript, BASE = CS && CS.src ? CS.src.replace(/[^\/]*$/, '') : '';   /* sp-share.js sits next to this file */

  function token(o) {
    var t = o.mapboxToken || (window.SITE && SITE.MAPBOX_TOKEN) || (window.SP_CONFIG && SP_CONFIG.MAPBOX_TOKEN) || (window.CRM_CONFIG && CRM_CONFIG.MAPBOX_TOKEN) || DEFAULT_TOKEN;
    return /^pk\./.test(String(t || '').trim()) ? String(t).trim() : '';
  }
  function curLang() { try { return window.SPI18N && SPI18N.lang ? SPI18N.lang : ''; } catch (e) { return ''; } }
  function say(k) { try { return window.SPI18N && SPI18N.t ? SPI18N.t(k) : k; } catch (e) { return k; } }


  /* ===================== PAID MODEL (public users) =====================
     Host gives  o.pay = { rpc(fn, params) -> Promise, settings() -> Promise<store settings> }.
     Free start; popup at ~50%; ONE design per payment; design data stays on the user's device (only the payment record goes to the server). */
  var PK = 'sp_dpay_v1';
  function lsGet() { try { return JSON.parse(localStorage.getItem(PK) || 'null') || {}; } catch (e) { return {}; } }
  function lsSet(v) { try { if (v) localStorage.setItem(PK, JSON.stringify(v)); else localStorage.removeItem(PK); } catch (e) {} }
  function hi() { return curLang() === 'hi' || curLang() === 'hg'; }
  function T(en, h) { return hi() ? h : en; }
  function esc(x) { return String(x == null ? '' : x).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function norm(st) { return st === 'verified' ? 'verified' : st === 'submitted' ? 'submitted' : 'none'; }

  function makePay(o, sendState) {
    var pay = o.pay, cur = lsGet(), busy = null, cfg = null;
    function save(r) { cur = { id: r.id, order_no: r.order_no, status: r.status, used: !!r.used, amount: r.amount }; lsSet(cur); return cur; }
    function settings() { if (cfg) return Promise.resolve(cfg); return Promise.resolve(pay.settings ? pay.settings() : null).then(function (s) { cfg = s || {}; return cfg; }, function () { cfg = {}; return cfg; }); }
    function refresh() {
      if (!cur.id) return Promise.resolve(cur);
      return pay.rpc('sp_design_status', { id: cur.id }).then(function (r) { if (r && r.status && r.status !== 'none') save(r); else { cur = {}; lsSet(null); } return cur; }, function () { return cur; });
    }
    function view() { return { on: true, status: norm(cur.status), used: !!cur.used, order_no: cur.order_no || '' }; }
    function css() {
      if (document.getElementById('spbp-paycss')) return;
      var st = document.createElement('style'); st.id = 'spbp-paycss';
      st.textContent = '.spbp-pay{position:fixed;inset:0;z-index:100000;background:rgba(6,18,12,.72);display:flex;align-items:flex-end;justify-content:center;padding:0}@media(min-width:640px){.spbp-pay{align-items:center;padding:16px}}' +
        '.spbp-pay .bx{background:#fff;color:#14231a;width:100%;max-width:460px;max-height:94vh;overflow:auto;border-radius:18px 18px 0 0;padding:18px 18px 22px;font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}@media(min-width:640px){.spbp-pay .bx{border-radius:18px}}' +
        '.spbp-pay h3{margin:0 0 4px;font-size:19px}.spbp-pay .sub{color:#4b5d51;margin:0 0 10px}.spbp-pay .amt{display:flex;align-items:baseline;gap:8px;background:#f1f7f2;border-radius:12px;padding:10px 12px;margin:8px 0}.spbp-pay .amt b{font-size:28px;color:#0b6b2f}' +
        '.spbp-pay ul{margin:6px 0 10px;padding-left:18px}.spbp-pay .bt{display:block;width:100%;box-sizing:border-box;text-align:center;font:inherit;font-weight:700;padding:11px 12px;border-radius:12px;border:1.5px solid #1e8e3e;background:#fff;color:#0b6b2f;cursor:pointer;margin-top:8px;text-decoration:none}.spbp-pay .bt.p{background:#1e8e3e;color:#fff}.spbp-pay .bt[disabled]{opacity:.55}' +
        '.spbp-pay input{font:inherit;width:100%;box-sizing:border-box;padding:10px;border:1px solid #c9d6cc;border-radius:10px;margin-top:6px}.spbp-pay .nt{background:#fff8e1;border:1px solid #f0d58a;border-radius:10px;padding:8px 10px;font-size:12.5px;margin-top:10px}.spbp-pay .er{color:#b3261e;font-weight:600;margin-top:8px}.spbp-pay .ok{color:#0b6b2f;font-weight:700;margin-top:8px}.spbp-pay .x{float:right;border:0;background:none;font-size:22px;line-height:1;cursor:pointer;color:#4b5d51}';
      document.head.appendChild(st);
    }
    function ask(reason, loc, summary, fp) {
      if (busy) return busy;
      busy = new Promise(function (resolve) {
        css(); var done = false, poll = null, ov = document.createElement('div'); ov.className = 'spbp-pay'; document.body.appendChild(ov);
        function close(ok) { if (done) return; done = true; clearInterval(poll); ov.remove(); busy = null; sendState(); resolve({ ok: !!ok, status: norm(cur.status), used: !!cur.used }); }
        function consume() {
          return pay.rpc('sp_design_consume', { id: cur.id, fp: fp }).then(function (r) { save(r); close(true); }, function (e) {
            var msg = String((e && e.message) || '');
            if (/NEW_DESIGN_NEEDS_PAYMENT/.test(msg)) { cur = {}; lsSet(null); step1('new'); }
            else shell('<p class="er">' + esc(msg.replace(/^[A-Z_]+:\s*/, '')) + '</p><button class="bt" data-c>' + esc(T('Close', 'बंद करें')) + '</button>');
          });
        }
        function shell(h) { ov.innerHTML = '<div class="bx"><button class="x" data-c aria-label="Close">×</button>' + h + '</div>'; var c = ov.querySelectorAll('[data-c]'); for (var i = 0; i < c.length; i++) c[i].onclick = function () { close(false); }; try { window.SPI18N && SPI18N.walk && SPI18N.walk(ov); } catch (e) {} }
        function step1(why) {
          shell('<p class="sub">…</p>');
          Promise.all([settings(), pay.rpc('sp_design_start', { location: loc, summary: summary })]).then(function (x) {
            var s = x[0] || {}, r = x[1]; save(r);
            if (r.status === 'verified') { if (reason === 'download') return consume(); return close(true); }
            if (r.status === 'submitted') return waiting(r, s);
            show(r, s, why);
          }, function (e) { shell('<p class="er">' + esc((e && e.message) || T('Could not start payment. Please login again and retry.', 'पेमेंट शुरू नहीं हुआ। फिर से लॉगिन करके कोशिश करें।')) + '</p><button class="bt" data-c>' + esc(T('Close', 'बंद करें')) + '</button>'); });
        }
        function links(r, s) {
          var p = (s && s.payments) || {}, u = p.upi || {}, L = p.links || {}, out = '';
          if (u.upiId && u.enabled !== false) out += '<a class="bt p" href="upi://pay?pa=' + encodeURIComponent(u.upiId) + '&pn=' + encodeURIComponent(u.payeeName || 'Sunpowers') + '&am=' + Number(r.amount).toFixed(2) + '&cu=INR&tn=' + encodeURIComponent(r.order_no) + '">📱 ' + esc(T('Pay ', 'पे करें ')) + '₹' + Math.round(r.amount) + esc(T(' by UPI app', ' UPI ऐप से')) + '</a><div class="sub" style="margin:6px 0 0">UPI ID: <b>' + esc(u.upiId) + '</b></div>';
          [['gpay', 'Google Pay'], ['phonepe', 'PhonePe'], ['paytm', 'Paytm']].forEach(function (k) { var v = L[k[0]]; if (v && v.enabled !== false && /^https:\/\//i.test(v.url || '')) out += '<a class="bt" target="_blank" rel="noopener" href="' + esc(v.url) + '">💳 ' + k[1] + ' — ₹' + Math.round(r.amount) + '</a>'; });
          return out || '<p class="sub">' + esc(T('Payment details will be shared by our team on call/WhatsApp.', 'पेमेंट की जानकारी हमारी टीम कॉल/WhatsApp पर देगी।')) + '</p>';
        }
        function show(r, s, why) {
          var head = reason === 'download' ? T('Pay ₹' + Math.round(r.amount) + ' to download', '₹' + Math.round(r.amount) + ' देकर डाउनलोड करें') : T('Your design is 50% ready — unlock to continue', 'आपका डिज़ाइन 50% तैयार है — आगे बढ़ने के लिए अनलॉक करें');
          shell('<h3>' + esc(head) + '</h3><p class="sub">' + esc(why === 'new' ? T('A new design needs a new payment (one payment = one design).', 'नए डिज़ाइन के लिए नया पेमेंट चाहिए (एक पेमेंट = एक डिज़ाइन)।') : T('Sunpowers Solar Designer — 1 design', 'Sunpowers Solar Designer — 1 डिज़ाइन')) + '</p>' +
            '<div class="amt"><b>₹' + Math.round(r.amount) + '</b><span>' + esc(T('incl. ', 'GST ')) + esc(r.gst_pct) + '% GST ' + esc(hi() ? 'सहित' : '') + ' · ' + esc(r.order_no) + '</span></div>' +
            '<ul><li>' + esc(T('Clean HD download — plan, 3D view, drawing sheet & quotation PDF', 'क्लीन HD डाउनलोड — प्लान, 3D व्यू, ड्रॉइंग शीट और कोटेशन PDF')) + '</li><li>' + esc(T('GST invoice in your Orders details', 'आपके Orders details में GST Invoice')) + '</li><li>' + esc(T('Your design stays on your phone — we do not store it', 'आपका डिज़ाइन आपके फ़ोन में ही रहता है — हम सेव नहीं करते')) + '</li></ul>' +
            links(r, s) +
            '<div style="margin-top:12px"><b>' + esc(T('Paid? Tap below', 'पेमेंट कर दिया? नीचे दबाएँ')) + '</b><input id="spbp-utr" maxlength="30" placeholder="' + esc(T('UTR / Transaction ID (optional)', 'UTR / ट्रांज़ैक्शन ID (ज़रूरी नहीं)')) + '"><button class="bt p" data-paid>✅ ' + esc(T('I have paid', 'मैंने पेमेंट कर दिया')) + '</button></div>' +
            '<div id="spbp-msg"></div><div class="nt">ℹ️ ' + esc(T('After verification of payment & Location, Invoice will appear on your Orders details — you can download it from there. UTR / slip is not compulsory — our team may call you.', 'पेमेंट और लोकेशन वेरिफ़ाई होने के बाद Invoice आपकी Orders details में दिखेगा — वहीं से डाउनलोड कर सकते हैं। UTR / स्लिप ज़रूरी नहीं — हमारी टीम कॉल कर सकती है।')) + '</div>' +
            '<button class="bt" data-c>' + esc(T('Not now', 'अभी नहीं')) + '</button>');
          var b = ov.querySelector('[data-paid]'); b.onclick = function () {
            b.disabled = true; var m = ov.querySelector('#spbp-msg'); m.innerHTML = '';
            pay.rpc('sp_design_submit', { id: r.id, utr: (ov.querySelector('#spbp-utr').value || '').trim(), location: loc, summary: summary }).then(function (x) { save(x); sendState(); if (reason === 'download') waiting(x, s); else okHalf(); },
              function (e) { b.disabled = false; m.innerHTML = '<div class="er">' + esc(String((e && e.message) || 'Error')) + '</div>'; });
          };
        }
        function okHalf() {
          shell('<h3>✅ ' + esc(T('Payment noted', 'पेमेंट दर्ज हुआ')) + '</h3><p class="sub">' + esc(T('You can continue designing now. The clean download opens as soon as our team verifies your payment & location (they may call you).', 'अब आप डिज़ाइन आगे बना सकते हैं। हमारी टीम पेमेंट और लोकेशन वेरिफ़ाई करते ही क्लीन डाउनलोड खुल जाएगा (वे कॉल कर सकते हैं)।')) + '</p><button class="bt p" data-go>' + esc(T('Continue designing', 'डिज़ाइन जारी रखें')) + '</button>');
          ov.querySelector('[data-go]').onclick = function () { close(true); };
        }
        function waiting(r, s) {
          shell('<h3>⏳ ' + esc(T('Waiting for verification', 'वेरिफ़िकेशन का इंतज़ार')) + '</h3><p class="sub">' + esc(T('Order ', 'ऑर्डर ')) + esc(r.order_no) + ' — ' + esc(T('our team is checking your payment & location. Download opens automatically once verified. You can keep this open or come back later.', 'हमारी टीम पेमेंट और लोकेशन जाँच रही है। वेरिफ़ाई होते ही डाउनलोड अपने-आप खुल जाएगा। इसे खुला रखें या बाद में लौटें।')) + '</p><div class="nt">ℹ️ ' + esc(T('After verification of payment & Location, Invoice will appear on your Orders details.', 'पेमेंट और लोकेशन वेरिफ़ाई होने के बाद Invoice आपकी Orders details में दिखेगा।')) + '</div><div id="spbp-msg"></div><button class="bt" data-c>' + esc(T('Close', 'बंद करें')) + '</button>');
          clearInterval(poll);
          poll = setInterval(function () { pay.rpc('sp_design_status', { id: r.id }).then(function (x) { if (x && x.status === 'verified') { save(x); clearInterval(poll); consume(); } else if (x && x.status === 'rejected') { clearInterval(poll); cur = {}; lsSet(null); step1('new'); } }, function () {}); }, 6000);
        }
        step1();
      });
      return busy;
    }
    return { view: view, refresh: refresh, ask: ask, reset: function () { cur = {}; lsSet(null); sendState(); } };
  }

  function mount(el, o) {
    o = o || {};
    if (!el) return;
    el.innerHTML = '';
    var wrap = document.createElement('div'); wrap.className = 'spbp-wrap'; wrap.style.cssText = 'position:relative;width:100%';
    var bar = document.createElement('div'); bar.style.cssText = 'display:flex;justify-content:flex-end;padding:0 0 6px';
    var fs = document.createElement('button'); fs.type = 'button'; fs.textContent = '⛶ Full screen';
    fs.style.cssText = 'font:inherit;font-size:13px;font-weight:700;padding:6px 12px;border-radius:999px;border:1px solid rgba(0,0,0,.18);background:#fff;color:#14231a;cursor:pointer';
    bar.appendChild(fs);
    var f = document.createElement('iframe');
    f.src = 'designer.html?v=' + VER; f.title = 'Sunpowers Designer'; f.setAttribute('allow', 'geolocation; fullscreen'); f.setAttribute('loading', 'eager');
    f.style.cssText = 'width:100%;border:0;border-radius:12px;background:#0f172a;display:block';
    wrap.appendChild(bar); wrap.appendChild(f); el.appendChild(wrap);
    var full = false;
    function size() {
      if (full) { f.style.height = '100%'; return; }
      var top = f.getBoundingClientRect().top, vh = window.innerHeight || 700;
      f.style.height = Math.max(620, Math.round(vh - Math.max(0, top) - 12)) + 'px';
    }
    function setFull(on) {
      full = !!on;
      if (full) { wrap.style.cssText = 'position:fixed;inset:0;z-index:99999;background:#0f172a;padding:0;width:auto'; bar.style.cssText = 'position:absolute;top:6px;right:8px;z-index:2;padding:0'; fs.textContent = '✕ Close'; f.style.borderRadius = '0'; document.documentElement.style.overflow = 'hidden'; }
      else { wrap.style.cssText = 'position:relative;width:100%'; bar.style.cssText = 'display:flex;justify-content:flex-end;padding:0 0 6px'; fs.textContent = '⛶ Full screen'; f.style.borderRadius = '12px'; document.documentElement.style.overflow = ''; }
      size();
      try { window.SPI18N && SPI18N.walk && SPI18N.walk(wrap); } catch (e) {}
    }
    fs.onclick = function () { setFull(!full); };
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && full) setFull(false); });
    window.addEventListener('resize', size); setTimeout(size, 50); setTimeout(size, 600);

    var PAY = (o.mode !== 'crm' && o.pay) ? makePay(o, function () { try { f.contentWindow.postMessage({ sp: 'host', type: 'pay-state', status: PAY.view().status, used: PAY.view().used }, location.origin); } catch (e) {} }) : null;
    function initMsg() {
      return {
        sp: 'host', type: 'init',
        opts: {
          mode: o.mode === 'crm' ? 'crm' : 'public', customer: o.customer || {}, targetKw: o.targetKw || '', whatsapp: o.whatsapp || '', links: o.links || {},
          project: (o.initial && o.initial.designer) ? o.initial.designer : null, legacy: (o.initial && !o.initial.designer) ? o.initial : null,
          recordId: o.recordId || null, noDraft: !!o.noDraft, token: token(o), lang: curLang(), pay: PAY ? PAY.view() : null
        }
      };
    }
    function send(id, ok, extra) { var m = { sp: 'host', type: 'result', id: id, ok: ok }; for (var k in (extra || {})) m[k] = extra[k]; try { f.contentWindow.postMessage(m, location.origin); } catch (e) {} }

    function onMsg(e) {
      if (e.source !== f.contentWindow || e.origin !== location.origin) return;
      var m = e.data; if (!m || m.sp !== 'designer') return;
      if (m.type === 'ready') {
        var sent = false, go = function () { if (sent) return; sent = true; try { f.contentWindow.postMessage(initMsg(), location.origin); } catch (x) {} };
        if (PAY) { PAY.refresh().then(go, go); setTimeout(go, 3500); } else go();
        return;
      }
      if (m.type === 'pay-need' && PAY) {
        PAY.ask(m.reason, m.loc || {}, m.summary || {}, m.fp || '').then(function (r) { send(m.id, true, { ok: r.ok, status: r.status, used: r.used }); });
        return;
      }
      if (m.type === 'pay-reset' && PAY) { PAY.reset(); return; }
      if (m.type === 'dirty') { try { if (o.onDirty) o.onDirty(true); } catch (x) {} return; }
      if (m.type === 'share') {   /* Round 32: the designer asks this page to open the Send sheet (link page / real file); the sheet uses this app's own database login */
        var spec = {}; for (var k in m) if (k !== 'sp' && k !== 'type') spec[k] = m[k];
        var go = function () { try { SPSHARE.open(spec); } catch (x) {} };
        if (window.SPSHARE) go(); else { var sc = document.createElement('script'); sc.src = BASE + 'sp-share.js?v=3'; sc.onload = go; document.head.appendChild(sc); }
        return;
      }
      if (m.type === 'submit') {
        var d = m.data || {}, kind = m.kind;
        var fn = kind === 'save' ? o.onSave : o.onSubmit;
        if (!fn) { send(m.id, false, { error: 'Not connected' }); return; }
        var payload = kind === 'save'
          ? { id: d.id || o.recordId || null, name: d.name, mobile: d.mobile, city: d.city, make_lead: !!d.make_lead, blueprint: d.blueprint }
          : { name: d.name, mobile: d.mobile, city: d.city, note: d.note, blueprint: d.blueprint };
        Promise.resolve().then(function () { return fn(payload); }).then(function (res) {
          res = res || {};
          if (res.id) o.recordId = res.id;
          send(m.id, true, { id2: res.id || null, msg: kind === 'save' ? say('Blueprint saved ✔') : say('Thank you! Our engineer will check your design and call you soon.') });
        }).catch(function (err) { send(m.id, false, { error: (err && err.message) || 'Could not send. Please try again.' }); });
      }
    }
    window.addEventListener('message', onMsg);
    window.addEventListener('storage', function (e) { if (e.key === 'sp_lang' && window.SPI18N && e.newValue && SPI18N.lang !== e.newValue) { try { SPI18N.set(e.newValue); } catch (x) {} } });
    document.addEventListener('sp-lang', function () { try { f.contentWindow.postMessage({ sp: 'host', type: 'lang', lang: curLang() }, location.origin); } catch (e) {} });
  }
  window.SPBlueprint = { mount: mount, VERSION: 'designer-2-paid' };
})();
