/* Sunpowers website — real store products with Add to cart (same list as the Online Store).
   Boxes:   .wcart[data-cart]      small product list inside solar sections (On-Grid / Off-Grid / Hybrid / VFD)
   Page:    #shopPage              full Shop page (shop.html)
   Source:  sp_get_store (public).  Pin rules: sp_pin_check (public).  Cart is kept here; "Go to store cart" hands it to the store
   (?add=id:qty&pin=NNNNNN) where login, payment and the order are done.  Settings come from Website Admin -> W.shop[key]. */
(function () {
  'use strict';
  var CFG = window.SITE || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function lang() { return window.SPI18N && (SPI18N.lang === 'hi' || SPI18N.lang === 'hg') ? 'hi' : 'en'; }
  function hg() { return !!(window.SPI18N && SPI18N.lang === 'hg' && SPI18N.xlit); }
  /* Round 27: one language only — whatever the owner typed (English / Hindi / Hinglish) is shown in the visitor's own language (dictionary first, then cached machine translation) */
  function X(v) { var I = window.SPI18N; if (!v) return v; if (I && !I.off && I.tr) { var t = I.tr(v, I.lang); if (t) return t; } return hg() && /[\u0900-\u097F]/.test(v) ? I.xlit(v) : v; }
  function pick(o) { if (!o) return ''; if (typeof o === 'string') return X(o); return X(o[lang()] || o.en || o.hi || ''); }
  var SHOP = String(CFG.SHOP_URL || '').replace(/\/+$/, '');
  var T = {
    add: ['Add to cart', 'कार्ट में जोड़ें'], buy: ['Buy now', 'अभी ख़रीदें'], view: ['View', 'देखें'], added: ['Added ✓', 'जुड़ गया ✓'], out: ['Out of stock', 'स्टॉक में नहीं'],
    na: ['Not available at this pin code', 'इस पिन कोड पर उपलब्ध नहीं'], chg: ['Change pin code', 'पिन कोड बदलें'],
    pin: ['Delivery pin code', 'डिलीवरी पिन कोड'], pinSet: ['Enter pin code', 'पिन कोड डालें'], pinOk: ['Check', 'जाँचें'], pinBad: ['Enter a 6-digit pin code', '6 अंकों का पिन कोड डालें'],
    none: ['No products in this section yet. See all products in the shop.', 'इस सेक्शन में अभी प्रोडक्ट नहीं हैं। शॉप में सभी प्रोडक्ट देखें।'],
    fail: ['Could not load products. Please try again or WhatsApp us.', 'प्रोडक्ट लोड नहीं हुए। फिर कोशिश करें या WhatsApp करें।'],
    appSoonT: ['Sunpowers App', 'Sunpowers ऐप'], appSoonB: ['Coming soon', 'जल्द आ रहा है'], appSoonD: ['Order, track and get offers in our app. Play Store and App Store links will be added soon.', 'ऐप में ऑर्डर, ट्रैकिंग और ऑफ़र मिलेंगे। Play Store और App Store की लिंक जल्द जुड़ेंगी।'], appGet: ['Download the app', 'ऐप डाउनलोड करें'], appInst: ['📲 Install App', '📲 ऐप इंस्टॉल करें'], appInstD: ['Install our app on your phone in one tap — no Play Store needed. Android and iPhone.', 'हमारा ऐप फ़ोन में एक टैप में इंस्टॉल करें — Play Store की ज़रूरत नहीं। Android और iPhone।'], appLiveD: ['Order, track and get offers in our app — download it free.', 'ऐप में ऑर्डर, ट्रैकिंग और ऑफ़र पाएँ — मुफ़्त डाउनलोड करें।'],
    appT: ['Sunpowers Store App', 'Sunpowers Store ऐप'], appD: ['This offer / product is in our Store App. Download the app to order — it takes a minute.', 'ये ऑफ़र / प्रोडक्ट हमारे Store ऐप में है। ऑर्डर करने के लिए ऐप डाउनलोड करें — सिर्फ़ एक मिनट।'], appGo: ['⬇️ Download the app', '⬇️ ऐप डाउनलोड करें'], appWeb: ['Open the online store', 'ऑनलाइन स्टोर खोलें'], appLater: ['Not now', 'अभी नहीं'],
    nHome: ['Home', 'होम'], nCats: ['Categories', 'कैटेगरी'], nDoc: ['Error check', 'एरर जाँच'], nWish: ['Wishlist', 'पसंद'], nCart: ['Cart', 'कार्ट'], nHelp: ['Help', 'मदद'],
    bpT: ['Project Blueprint', 'प्रोजेक्ट ब्लूप्रिंट'], bpS: ['Free solar site survey — mark your roof, get a blueprint PDF and a quotation', 'मुफ़्त सोलर साइट सर्वे — छत मार्क करें, ब्लूप्रिंट PDF पाएँ, कोटेशन मँगाएँ'],
    docT: ['Solar Problem Detector', 'सोलर समस्या जाँच'], docS: ['Type the inverter error code or add a photo — meaning and safe fix in 1 minute. Photo is never saved.', 'इन्वर्टर एरर कोड या फ़ोटो डालें — 1 मिनट में मतलब और सही उपाय। फ़ोटो सेव नहीं होती।'],
    open: ['Open', 'खोलें'], live: ['Live', 'लाइव'], fCtaT: ['Need help with solar?', 'सोलर में मदद चाहिए?'], fCtaS: ['Free advice from our engineer — call or WhatsApp', 'हमारे इंजीनियर से मुफ़्त सलाह — कॉल या WhatsApp करें'],
    fCall: ['Call us', 'कॉल करें'], fDoc: ['Check a solar problem', 'सोलर समस्या जाँचें'], fShop: ['Shop', 'शॉप'], fAll: ['All categories', 'सभी कैटेगरी'], fHelp: ['Help & policies', 'मदद व पॉलिसी'], fContact: ['Contact', 'संपर्क'],
    mainSite: ['Main website', 'मुख्य वेबसाइट'], payModes: ['Payment options', 'पेमेंट के तरीके'], gAll: ['See all reviews on Google', 'Google पर सभी रिव्यू देखें'], gWrite: ['Write a review', 'रिव्यू लिखें'], soon: ['Coming soon', 'जल्द आ रहा है'],
    allCats: ['All categories', 'सभी कैटेगरी'], wishT: ['Wishlist', 'पसंद की लिस्ट'], emptyWish: ['Nothing saved yet — tap ♡ on a product.', 'अभी कुछ सेव नहीं — प्रोडक्ट पर ♡ दबाएँ।'], resFor: ['Results for', 'नतीजे:'],
    pinShort: ['Pincode', 'पिनकोड'],
    all: ['All', 'सभी'], search: ['Search products', 'प्रोडक्ट खोजें'], items: ['items', 'आइटम'], go: ['Checkout', 'चेकआउट'],
    shop: ['View all in shop', 'शॉप में सब देखें'], off: ['% off', '% छूट'], clear: ['Clear', 'खाली करें'], sub: ['Subtotal', 'कुल'], load: ['Loading…', 'लोड हो रहा है…'], save: ['Save', 'सेव']
  };
  function reg() { return !!(window.SPI18N && !SPI18N.off && !/^(en|hi|hg)$/.test(SPI18N.lang)); }
  try { if (window.SPI18N && SPI18N.add) SPI18N.add(Object.keys(T).map(function (k) { return [T[k][0], T[k][1]]; })); } catch (e) {}
  function t(k) { return reg() ? (SPI18N.t(T[k][0]) || T[k][0]) : X(T[k][lang() === 'hi' ? 1 : 0]); }
  function money(n) { n = Number(n) || 0; return '₹' + Math.round(n).toLocaleString('en-IN'); }
  function num(x) { x = Number(x); return isFinite(x) ? x : 0; }
  function price(p) { var o = num(p.offer); return o > 0 ? o : num(p.mrp); }
  function disc(p) { var m = num(p.mrp), o = num(p.offer); return m > 0 && o > 0 && o < m ? Math.round((1 - o / m) * 100) : 0; }
  function isImg(u) { return typeof u === 'string' && /^(https:\/\/|data:image\/|\/?[\w\-./]+\.(png|jpe?g|webp|gif|svg))/i.test(u); }
  function ptitle(p) { return X(lang() === 'en' ? (p.titleEn || p.title || '') : (p.title || p.titleEn || '')); }
  function lsGet(k, d) { try { var v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }
  function lsSet(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  function webCfg() { var c = window.SPCMS && SPCMS.data && SPCMS.data(); return (c && c.shop) || {}; }


  var CSS_TXT = '.wc-h{margin-bottom:10px}.wc-h h3{font-size:20px;color:var(--forest,#14231a);margin:2px 0 0}' +
  '.wcart{margin:14px 0;padding:14px;border:1px solid var(--line,#dce5da);border-radius:16px;background:var(--white,#fff)}.sys .wcart{padding:10px;margin:10px 0;background:var(--paper,#f6f8f3)}' +
  '.wc-rail{position:relative}.wc-g{display:flex;gap:12px;overflow-x:auto;overflow-y:hidden;scroll-snap-type:x proximity;-webkit-overflow-scrolling:touch;scrollbar-width:thin;padding:2px 2px 10px;overscroll-behavior-x:contain}.wc-g>.wc-p{flex:0 0 clamp(168px,62vw,214px);scroll-snap-align:start}.sys .wc-g>.wc-p{flex-basis:clamp(160px,58vw,196px)}' +
  '.wc-gs.wc-g2{display:grid;grid-auto-flow:column;grid-template-rows:repeat(2,auto);grid-auto-columns:clamp(168px,62vw,214px)}.wc-gs.wc-g2>.wc-p{flex:none}' +
  '.wc-ar{position:absolute;top:38%;z-index:3;width:38px;height:38px;border-radius:50%;border:1px solid var(--line,#dce5da);background:#fff;color:var(--forest,#14231a);font-size:22px;line-height:1;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.16);display:none;align-items:center;justify-content:center;padding:0 0 3px}.wc-ar.l{left:-8px}.wc-ar.r{right:-8px}.wc-rail.can-l .wc-ar.l,.wc-rail.can-r .wc-ar.r{display:flex}@media(hover:none),(max-width:700px){.wc-ar{display:none!important}}' +
  '.wc-hint{display:flex;justify-content:space-between;align-items:center;font-size:12px;color:var(--mute,#5a6b5f);margin:0 0 6px}' +
  '.wc-p{display:flex;flex-direction:column;gap:6px;padding:10px;border:1px solid var(--line,#dce5da);border-radius:14px;background:#fff;min-width:0}.wc-x{opacity:.72}' +
  '.wc-i{position:relative;aspect-ratio:4/3;border-radius:10px;overflow:hidden;display:flex;align-items:center;justify-content:center;font-size:44px}.wc-i img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}' +
  '.wc-i em{position:absolute;top:6px;left:6px;background:#c8372d;color:#fff;font-size:11px;font-weight:700;line-height:1;font-family:inherit;font-style:normal;padding:4px 7px;border-radius:999px}' +
  '.wc-t{font-weight:700;font-size:14.5px;line-height:1.3;overflow-wrap:anywhere}.wc-br{color:var(--mute,#5a6b5f)}.wc-pr{display:flex;gap:6px;align-items:baseline;flex-wrap:wrap}.wc-pr b{font-size:17px;color:var(--leaf-d,#15702f)}.wc-pr s{color:var(--mute,#5a6b5f);font-size:13px}' +
  '.wc-na{font-size:12.5px;color:#c8372d}.wc-a{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:auto}.wc-b{flex:1;justify-content:center}' +
  '.wc-q{display:inline-flex;align-items:center;border:1px solid var(--line,#dce5da);border-radius:999px}.wc-q b{min-width:26px;text-align:center}.wc-s{width:32px;height:34px;border:0;background:none;font-size:18px;cursor:pointer;color:inherit}' +
  '.wc-pbs{display:flex;gap:6px;margin-top:2px}.wc-pb{flex:1 1 0;min-width:0;justify-content:center;padding-inline:6px;font-size:12.5px;white-space:nowrap}.wc-pw{flex:0 0 36px}.bld-rl .wc-p{min-width:0}' +
  '.wc-note{color:var(--mute,#5a6b5f);margin:6px 0}.wc-more{margin:10px 0 0}.wc-bar{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:12px}.wc-in{flex:1;min-width:160px;padding:10px 12px;border:1px solid var(--line,#dce5da);border-radius:12px;font:inherit;background:#fff;color:inherit}' +
  '.wc-chips,.wc-tabs{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 14px}.wc-chip{border:1px solid var(--line,#dce5da);background:#fff;border-radius:999px;padding:7px 14px;font-size:14px;font-weight:600;font-family:inherit;cursor:pointer;color:inherit}.wc-chip.on{background:var(--leaf,#1e8e3e);color:#fff;border-color:var(--leaf,#1e8e3e)}' +
  '.wc-fbar{position:fixed;left:0;right:0;bottom:0;z-index:70;display:flex;gap:10px;justify-content:space-between;align-items:center;flex-wrap:wrap;padding:10px max(16px,env(safe-area-inset-right,0px)) calc(10px + env(safe-area-inset-bottom,0px)) max(16px,env(safe-area-inset-left,0px));background:var(--forest,#0f3d24);color:#fff;box-shadow:0 -6px 24px rgba(0,0,0,.18)}.wc-fa{display:flex;gap:8px}' +
  '.wc-dlg{position:fixed;inset:0;z-index:90;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;padding:16px}.wc-dc{background:#fff;color:#14231a;border-radius:16px;padding:18px;width:min(360px,100%)}.wc-dc h3{margin:0 0 10px}' +
  '.wc-cats{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px}.wc-cat{display:flex;flex-direction:column;gap:4px;align-items:flex-start;padding:14px;border:1px solid var(--line,#dce5da);border-radius:14px;background:#fff;text-decoration:none;color:inherit;min-width:0}.wc-cat:hover{border-color:var(--leaf,#1e8e3e);box-shadow:0 4px 14px rgba(0,0,0,.07)}.wc-ce{font-size:30px;line-height:1}.wc-cat b{font-size:14.5px;line-height:1.3;overflow-wrap:anywhere}.wc-cat small{color:var(--mute,#5a6b5f)}' +
  '.wc-bplace .bld-b{margin:0}.wc-bplace[data-app-teaser] a,.wc-bplace[data-app-teaser] button:not(.bld-arr):not(.wc-ar){cursor:pointer}' +
  '.wc-appcard{display:flex;align-items:center;gap:14px;flex-wrap:wrap;padding:16px 18px;border-radius:18px;background:linear-gradient(135deg,#0b3a1b,#14622e);color:#fff}.wc-ai{font-size:30px;width:54px;height:54px;border-radius:16px;background:#fff;display:grid;place-items:center;flex:none}.wc-at{flex:1;min-width:200px}.wc-at b{display:block;font-size:18px}.wc-at small{display:block;opacity:.85;font-size:13.5px;margin-top:2px}.wc-soon{background:#f9a825;color:#1c2b20;font-weight:800;border-radius:999px;padding:6px 14px;font-size:13px;white-space:nowrap}' +
  '[hidden]{display:none!important}';
  (function () { var st = document.createElement('style'); st.textContent = CSS_TXT; document.head.appendChild(st); })();

  /* ---------- state ---------- */
  var S = null, PIN = { pin: '', on: false, bad: {}, state: '', district: '' }, CART = lsGet('sp_wcart', []), LOADING = null, FAILED = false;
  if (!Array.isArray(CART)) CART = [];
  function saveCart() { lsSet('sp_wcart', CART.slice(0, 60)); }

  function pinGet() {
    var v = lsGet('sp_pin', ''); v = typeof v === 'string' ? v : '';
    if (!/^\d{6}$/.test(v)) { var m = (document.cookie || '').match(/(?:^|;\s*)sp_pin=(\d{6})/); v = m ? m[1] : ''; }
    return v;
  }
  function pinPut(v) {
    lsSet('sp_pin', v);
    try { var d = /(^|\.)sunpowers\.in$/.test(location.hostname) ? '; Domain=.sunpowers.in' : ''; document.cookie = 'sp_pin=' + v + d + '; Path=/; Max-Age=31536000; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : ''); } catch (e) {}
  }
  function rpc(fn, args, ms) {
    var url = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), key = String(CFG.SUPABASE_KEY || '').trim();
    if (!url || !key) return Promise.reject(new Error('no db'));
    var h = { apikey: key, 'Content-Type': 'application/json' }; if (key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + key;
    var ctrl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctrl) ctrl.abort(); }, ms || 12000);
    return fetch(url + '/rest/v1/rpc/' + fn, { method: 'POST', headers: h, body: JSON.stringify(args || {}), signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) { clearTimeout(tm); if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); }, function (e) { clearTimeout(tm); throw e; });
  }
  function normStore(d) {
    var out = { sections: [], products: [], settings: d && d.settings || {}, builder: d && d.builder || null, services: d && d.services || null, howto: d && d.howto || null, feedback: d && d.feedback || null, videos: d && d.videos || null };
    (d && d.sections || []).forEach(function (s) { if (s && s.id) out.sections.push(s); });
    (d && d.products || []).forEach(function (p) {
      if (!p || !p.id || p.visible === false || p.web === false) return;
      p.sections = Array.isArray(p.sections) ? p.sections : []; p.images = Array.isArray(p.images) ? p.images : []; p.stock = p.stock === 'out' ? 'out' : 'in';
      out.products.push(p);
    });
    out.products.sort(function (a, b) { return num(a.sort) - num(b.sort); });
    return out;
  }
  /* Store data (products, builder sections): shown at once from this phone's copy, then checked in the background —
     one tiny "changed?" question (sp_store_ver); the full data is downloaded only when something really changed, and the page redraws by itself. */
  var SKEY = 'sp_wstore2', REFRESHING = false, NOVER = false, LASTREF = 0;
  function slimStore(d) { return { sections: d.sections, products: d.products, builder: d.builder || null, settings: d.settings || {}, services: d.services || null, howto: d.howto || null, feedback: d.feedback || null, videos: d.videos || null }; }
  function readCache() { try { var c = JSON.parse(localStorage.getItem(SKEY) || 'null'); return c && c.d && Date.now() - c.at < 7 * 864e5 ? c : null; } catch (e) { return null; } }
  function storeVer() { if (NOVER) return Promise.resolve(null); return rpc('sp_store_ver', {}, 6000).then(function (v) { return v && v.main ? v : null; }, function (e) { if (/HTTP 404/.test(String(e && e.message))) NOVER = true; return null; }); }
  function fetchStore() {
    var ver = null;
    return storeVer().then(function (v) { ver = v; return rpc('sp_get_store', {}, 12000); }).then(function (d) {   /* version is read first, so the data is never older than the version we remember */
      if (!d || typeof d !== 'object' || !Array.isArray(d.products)) throw new Error('bad store');
      var sl = slimStore(d); try { localStorage.setItem(SKEY, JSON.stringify({ at: Date.now(), ver: ver, d: sl })); } catch (e) {}
      return sl;
    });
  }
  function loadStore() {
    if (S) return Promise.resolve(S);
    if (LOADING) return LOADING;
    var c = readCache();
    if (c) { S = normStore(c.d); FAILED = false; setTimeout(function () { refreshStore(true); }, 0); return Promise.resolve(S); }
    LOADING = fetchStore().then(function (sl) { S = normStore(sl); FAILED = false; return S; }).catch(function () { FAILED = true; S = null; return null; }).then(function (r) { LOADING = null; return r; });
    return LOADING;
  }
  function rerender() {
    if (!$('.wcart[data-cart]') && !$('#shopPage') && !$('[data-wc-cats]')) { if (window.SPBLD && $('main') && webFile() !== 'shop.html' && webFile() !== 'checkout.html') placeBuilder(); return; }
    renderAll();
  }
  function refreshStore(force) {
    if (REFRESHING || !S || (!force && Date.now() - LASTREF < 25000)) return Promise.resolve(false);
    REFRESHING = true; LASTREF = Date.now();
    var c = readCache();
    return storeVer().then(function (v) {
      if (v && c && c.ver && c.ver.main === v.main && Date.now() - c.at < 6 * 3600e3) return false;
      return fetchStore().then(function (sl) { var same = c && JSON.stringify(c.d) === JSON.stringify(sl); if (same) return false; S = normStore(sl); return true; });
    }).catch(function () { return false; }).then(function (ch) {
      REFRESHING = false; if (!ch) return false;
      return (S ? pinSync() : Promise.resolve()).then(function () { rerender(); return true; });
    });
  }
  document.addEventListener('visibilitychange', function () { if (!document.hidden) refreshStore(false); });
  window.addEventListener('online', function () { refreshStore(true); });
  setInterval(function () { if (!document.hidden) refreshStore(false); }, 90000);
  function prod(id) { if (!S) return null; for (var i = 0; i < S.products.length; i++) if (S.products[i].id === id) return S.products[i]; return null; }
  function secOf(id) { if (!S) return null; for (var i = 0; i < S.sections.length; i++) if (S.sections[i].id === id) return S.sections[i]; return null; }
  function unavail(id) { return !!(PIN.on && PIN.bad[id]); }
  var pinAt = 0, pinSig = '';
  function pinSync() {
    if (!S) return Promise.resolve();
    var ids = S.products.map(function (p) { return p.id; }).slice(0, 1500), sig = PIN.pin + '|' + ids.length;
    if (sig === pinSig && Date.now() - pinAt < 60000) return Promise.resolve();
    return rpc('sp_pin_check', { p_pin: PIN.pin, p_ids: ids }, 12000).then(function (r) {
      PIN.on = !!(r && r.enabled); PIN.bad = {}; ((r && r.bad) || []).forEach(function (id) { PIN.bad[id] = 1; });
      PIN.state = (r && r.state) || ''; PIN.district = (r && r.district) || '';
    }, function () { PIN.on = false; PIN.bad = {}; }).then(function () { pinSig = sig; pinAt = Date.now(); });
  }

  /* ---------- picking products for a box ---------- */
  function boxCfg(el) {
    var key = el.getAttribute('data-cart'), c = webCfg()[key]; c = c && typeof c === 'object' ? c : {};
    var kw = String(c.keywords != null && c.keywords !== '' ? c.keywords : (el.getAttribute('data-kw') || '')).toLowerCase().split('|').map(function (x) { return x.trim(); }).filter(Boolean);
    return { key: key, off: !!c.off, title: pick(c.title), section: String(c.section || ''), kw: kw, limit: Math.max(1, Math.min(24, parseInt(c.limit, 10) || (el.getAttribute('data-compact') ? 3 : 4))), all: el.getAttribute('data-all') === '1', link: String(c.link || '').trim(), btn: pick(c.btn), more: String(c.more || '').trim() };
  }
  function hay(p) { return [p.title, p.titleEn, p.tagline, p.brand, p.sku].concat(p.sections.map(function (id) { var s = secOf(id); return s ? (s.title || '') + ' ' + (s.titleEn || '') : ''; })).join(' ').toLowerCase(); }
  function pickProducts(cfg) {
    var list = S.products.filter(function (p) {
      if (cfg.section) return p.sections.indexOf(cfg.section) >= 0;
      if (cfg.all && !cfg.kw.length) return true;
      var h = hay(p); return cfg.kw.some(function (k) { return h.indexOf(k) >= 0; });
    });
    var ok = list.filter(function (p) { return p.stock !== 'out'; }), no = list.filter(function (p) { return p.stock === 'out'; });
    return ok.concat(no).slice(0, cfg.limit);
  }
  function linkFor(raw, id) {
    raw = String(raw || '').trim(); if (!raw) return '';
    raw = raw.replace(/\{id\}/g, encodeURIComponent(id || ''));
    if (/^https?:\/\//i.test(raw)) return raw;
    if (raw.charAt(0) === '/') { var ms = /[?&]s=([^&#]+)/.exec(raw); return ms ? 'shop.html#sec=' + ms[1] : 'shop.html'; }
    if (/^[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w\-]*)?$/i.test(raw)) return raw;
    return '';
  }

  /* ---------- rendering ---------- */
  function qtyOf(id) { for (var i = 0; i < CART.length; i++) if (CART[i].id === id) return CART[i].qty; return 0; }

  /* Round 30: product card + grid identical to the Store app (same size, same layout, same 2 / 3 / 4 / 5 columns) */
  var PCCSS = '.pc{--g:#1e8e3e;--g-d:#14692c;--mut:#66756a;--red:#d93025;--card:#fff;--r:16px;--sh:0 1px 2px rgba(16,40,20,.06),0 4px 14px rgba(16,40,20,.06);background:var(--card);border-radius:var(--r);padding:8px;position:relative;box-shadow:var(--sh);display:flex;flex-direction:column;min-width:0;color:#1c2b20;text-align:left}' +
    '.pc .pc-img{position:relative;display:grid;place-items:center;aspect-ratio:1/.86;border-radius:12px;overflow:hidden;background:#e8f5e9}.pc .pc-img .emo{font-size:clamp(46px,13vw,64px)}.pc .pc-img img,.pc .pc-img video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}' +
    '.pc .pc-off{position:absolute;left:6px;top:6px;background:var(--red);color:#fff;font-size:11px;font-weight:700;border-radius:6px;padding:1px 6px;z-index:1}.pc .pc-bdg{position:absolute;left:6px;bottom:6px;background:rgba(255,255,255,.92);color:var(--g-d);font-size:11px;font-weight:700;border-radius:6px;padding:1px 6px;z-index:1}' +
    '.pc .pc-t{font-weight:700;font-size:14px;line-height:1.25;margin:8px 2px 2px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;min-height:35px}.pc .pc-tag{font-size:12px;color:var(--mut);margin:0 2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pc .pc-tag i{font-style:normal;color:var(--g)}' +
    '.pc .pc-row{display:flex;align-items:flex-end;justify-content:space-between;gap:4px;margin:6px 2px 0;margin-top:auto;padding-top:6px}.pc .pr b{font-size:17px;font-weight:800}.pc .pr s{font-size:12px;color:var(--mut);display:block;line-height:1}' +
    '.pc .add{width:34px;height:34px;border-radius:50%;background:var(--g);color:#fff;font-size:22px;font-weight:600;display:grid;place-items:center;flex:none;box-shadow:0 2px 6px rgba(0,0,0,.18);border:0;cursor:pointer;font-family:inherit;line-height:1}.pc .add:active{transform:scale(.92)}.pc .add[disabled]{background:#c9d1cb;box-shadow:none;cursor:default}.pc .oos{font-size:11px;color:var(--red);font-weight:700}' +
    '.pc .pc-btns{display:flex;gap:6px;margin-top:8px}.pc .pcb{flex:1;display:grid;place-items:center;min-height:34px;padding:0 8px;border:1px solid var(--g);border-radius:10px;background:#fff;color:var(--g-d);font:inherit;font-size:12.5px;font-weight:700;cursor:pointer;text-decoration:none}.pc .pcb-buy{background:var(--g);color:#fff}.pc .pcb-wa{flex:0 0 38px;border-color:#25d366;color:#128c4a}.pc .pcb[disabled]{opacity:.5;cursor:default}' +
    '#shopPage .wc-chips{flex-wrap:nowrap;overflow-x:auto;scrollbar-width:none;padding:2px 0 4px}#shopPage .wc-chips::-webkit-scrollbar{display:none}#shopPage .wc-chip{flex:none;white-space:nowrap}#shopPage .wc-chip.on{background:#1e8e3e;border-color:#1e8e3e;color:#fff}' +
    '.pcg{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}@media(min-width:560px){.pcg{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(min-width:820px){.pcg{grid-template-columns:repeat(4,minmax(0,1fr))}}@media(min-width:1060px){.pcg{grid-template-columns:repeat(5,minmax(0,1fr))}}';
  (function () { if (document.getElementById('wcPcCss')) return; var st = document.createElement('style'); st.id = 'wcPcCss'; st.textContent = PCCSS; (document.head || document.documentElement).appendChild(st); })();
  function scard(p, opt) {
    var d = disc(p), out = p.stock === 'out', na = !out && unavail(p.id), blocked = out || na, url = 'shop.html#q=' + encodeURIComponent(String(p.titleEn || p.title || '').slice(0, 60));
    var img = isImg(p.image) ? p.image : (isImg(p.images[0]) ? p.images[0] : '');
    var mm = null; (p.media || []).forEach(function (m) { if (!mm && m && m.main) mm = m; }); if (!mm && p.media && p.media[0]) mm = p.media[0];
    var vid = mm && mm.type === 'video' && /^https?:\/\//i.test(mm.url || '') ? mm.url : '';
    return '<div class="pc' + (na ? ' na' : '') + '"><div class="pc-img" style="background:' + esc(/^#[0-9a-f]{3,8}$/i.test(p.bg || '') ? p.bg : '#e8f5e9') + '"><span class="emo">' + esc(p.emoji || '☀️') + '</span>' +
      (vid ? '<video src="' + esc(vid) + '#t=0.1" muted playsinline preload="metadata" onerror="this.remove()"></video>' : (img ? '<img src="' + esc(img) + '" alt="" loading="lazy" onerror="this.remove()">' : '')) +
      (d ? '<span class="pc-off">' + d + t('off') + '</span>' : '') + (p.badge ? '<span class="pc-bdg" data-noi18n>' + esc(p.badge) + '</span>' : '') + '</div>' +
      (window.SHOPX ? '<button type="button" class="heart' + (SHOPX.wish.has(p.id) ? ' on' : '') + '" data-wc-wish="' + esc(p.id) + '" aria-label="Wishlist" data-noi18n>' + (SHOPX.wish.has(p.id) ? '♥' : '♡') + '</button>' : '') +
      '<div class="pc-t" data-noi18n>' + esc(ptitle(p)) + '</div>' + (p.tagline ? '<div class="pc-tag" data-noi18n>' + esc(p.tagline) + ' <i>✔</i></div>' : (p.brand ? '<div class="pc-tag" data-noi18n>' + esc(p.brand) + ' <i>✔</i></div>' : '')) +
      '<div class="pc-row"><div class="pr">' + (d ? '<s>' + money(p.mrp) + '</s>' : '') + '<b>' + money(price(p)) + '</b>' + (p.unit ? '<small style="color:var(--mut)"> /' + esc(p.unit) + '</small>' : '') +
      (out ? '<div class="oos">' + esc(t('out')) + '</div>' : (na ? '<div class="oos">⚠️ ' + esc(t('na')) + ' · <a href="#" data-wc-pin>' + esc(t('chg')) + '</a></div>' : '')) + '</div>' +
      '<button type="button" class="add" data-wc-add="' + esc(p.id) + '"' + (blocked ? ' disabled' : '') + ' aria-label="' + esc(t('add')) + '" data-noi18n>+</button></div>' +
      (function () { var h = pbtns(p, opt, blocked); return h ? h.replace('class="wc-pbs"', 'class="pc-btns"').replace(/class="btn btn-line btn-sm wc-pb wc-pw"/g, 'class="pcb pcb-wa"').replace(/class="btn btn-line btn-sm wc-pb"( data-wc-buy)/g, 'class="pcb pcb-buy"$1').replace(/class="btn btn-line btn-sm wc-pb"/g, 'class="pcb"') : ''; })() + '</div>';
  }
  function pcard(p, cfg, opt) {
    if (opt && opt.sc) return scard(p, opt);
    var d = disc(p), out = p.stock === 'out', na = !out && unavail(p.id), blocked = out || na;
    var img = isImg(p.image) ? p.image : (isImg(p.images[0]) ? p.images[0] : '');
    var mm = null; (p.media || []).forEach(function (m) { if (!mm && m && m.main) mm = m; }); if (!mm && p.media && p.media[0]) mm = p.media[0];
    var vid = mm && mm.type === 'video' && /^https?:\/\//i.test(mm.url || '') ? mm.url : '';
    var lk = cfg && cfg.link ? linkFor(cfg.link, p.id) : '';
    var label = (cfg && cfg.btn) || t('add');
    var act;
    if (blocked) act = '<button class="btn btn-sm wc-b" disabled>' + esc(out ? t('out') : t('na')) + '</button>';
    else if (lk) act = '<a class="btn btn-sun btn-sm wc-b" href="' + esc(lk) + '"' + (/^https?:/i.test(lk) && lk.indexOf(location.host) < 0 ? ' target="_blank" rel="noopener"' : '') + ' data-noi18n>' + esc(label) + '</a>';
    else act = '<div class="wc-q"><button type="button" class="wc-s" data-wc-q="-1" data-id="' + esc(p.id) + '" aria-label="-">−</button><b data-wc-n="' + esc(p.id) + '">' + (qtyOf(p.id) || 1) + '</b><button type="button" class="wc-s" data-wc-q="1" data-id="' + esc(p.id) + '" aria-label="+">+</button></div><button type="button" class="btn btn-sun btn-sm wc-b" data-wc-add="' + esc(p.id) + '" data-noi18n>' + esc(label) + '</button>';
    return '<div class="wc-p' + (blocked ? ' wc-x' : '') + '"><div class="wc-i" style="background:' + esc(/^#[0-9a-f]{3,8}$/i.test(p.bg || '') ? p.bg : '#e7f3e9') + '"><span>' + esc(p.emoji || '☀️') + '</span>' + (vid ? '<video src="' + esc(vid) + '#t=0.1" muted playsinline preload="metadata" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;background:#000" onerror="this.remove()"></video>' : (img ? '<img src="' + esc(img) + '" alt="" loading="lazy" onerror="this.remove()">' : '')) + (d ? '<em>' + d + t('off') + '</em>' : '') + '</div>' +
      '<div class="wc-t" data-noi18n>' + esc(ptitle(p)) + '</div>' + (p.brand ? '<small class="wc-br" data-noi18n>' + esc(p.brand) + '</small>' : '') +
      '<div class="wc-pr">' + (d ? '<s>' + money(p.mrp) + '</s>' : '') + '<b>' + money(price(p)) + '</b>' + (p.unit ? '<small> /' + esc(p.unit) + '</small>' : '') + '</div>' +
      (na ? '<div class="wc-na">⚠️ ' + esc(t('na')) + ' · <a href="#" data-wc-pin>' + esc(t('chg')) + '</a></div>' : '') + '<div class="wc-a">' + act + '</div>' + pbtns(p, opt, blocked) + '</div>';
  }
  function pbtns(p, opt, blocked) {
    var b = opt && opt.btns; if (!b || !b.length) return '';
    var wa = String((S && S.settings && S.settings.whatsapp) || CFG.WHATSAPP || '').replace(/\D/g, ''), h = '';
    if (b.indexOf('buy') >= 0) h += '<button type="button" class="btn btn-line btn-sm wc-pb" data-wc-buy="' + esc(p.id) + '"' + (blocked ? ' disabled' : '') + ' data-noi18n>' + esc(t('buy')) + '</button>';
    if (b.indexOf('view') >= 0) h += '<a class="btn btn-line btn-sm wc-pb" href="shop.html#q=' + encodeURIComponent(String(p.titleEn || p.title || '').slice(0, 60)) + '" data-noi18n>' + esc(t('view')) + '</a>';
    if (b.indexOf('wa') >= 0 && wa) h += '<a class="btn btn-line btn-sm wc-pb wc-pw" target="_blank" rel="noopener" href="https://wa.me/' + (wa.length === 10 ? '91' + wa : wa) + '?text=' + encodeURIComponent('Namaste, mujhe ye product chahiye: ' + ptitle(p)) + '" aria-label="WhatsApp" data-noi18n>💬</a>';
    return h ? '<div class="wc-pbs">' + h + '</div>' : '';
  }
  function rail(inner, cls) { return '<div class="wc-rail"><button type="button" class="wc-ar l" data-wc-sc="-1" aria-label="Left">‹</button><div class="wc-g' + (cls ? ' ' + cls : '') + '" data-wc-scroller>' + inner + '</div><button type="button" class="wc-ar r" data-wc-sc="1" aria-label="Right">›</button></div>'; }
  function railState(r) { var g = r.querySelector('[data-wc-scroller]'); if (!g) return; r.classList.toggle('can-l', g.scrollLeft > 8); r.classList.toggle('can-r', g.scrollLeft + g.clientWidth < g.scrollWidth - 8); }
  function railAll() { $$('.wc-rail').forEach(railState); }
  document.addEventListener('scroll', function (e) { var g = e.target; if (g && g.hasAttribute && g.hasAttribute('data-wc-scroller')) railState(g.parentNode); }, true);
  window.addEventListener('resize', function () { clearTimeout(railAll._t); railAll._t = setTimeout(railAll, 120); });
  function renderBox(el) {
    var cfg = boxCfg(el), list = $('[data-wc-list]', el), h3 = $('[data-wc-title]', el);
    if (cfg.off) { el.hidden = true; return; } el.hidden = false;
    if (h3 && cfg.title) { h3.textContent = X(cfg.title); h3.setAttribute('data-noi18n', ''); }
    if (!list) return;
    if (!S) { list.innerHTML = '<p class="wc-note">' + esc(FAILED ? t('fail') : t('load')) + '</p>'; return; }
    var ps = pickProducts(cfg);
    var more = cfg.more ? linkFor(cfg.more, '') : (SHOP ? 'shop.html' : '');
    list.innerHTML = ps.length ? rail(ps.map(function (p) { return pcard(p, cfg); }).join('')) + (more ? '<p class="wc-more"><a class="link" href="' + esc(more) + '">' + esc(t('shop')) + ' →</a></p>' : '')
      : '<p class="wc-note">' + esc(t('none')) + (more ? ' <a class="link" href="' + esc(more) + '">' + esc(t('shop')) + ' →</a>' : '') + '</p>';
  }
  var SHOPST = { sec: '', q: '', view: '' };
  if (window.SHOPX) SHOPX.storeUrl = SHOP;
  function readHash() { try { var h = location.hash || '', hm = h.match(/sec=([^&]+)/), hq = h.match(/q=([^&]+)/); if (hm) { SHOPST.sec = decodeURIComponent(hm[1]); SHOPST.q = ''; } else if (hq) { SHOPST.q = decodeURIComponent(hq[1]); SHOPST.sec = ''; } } catch (e) {} }
  readHash(); window.addEventListener('hashchange', function () { readHash(); if (typeof renderShop === 'function') renderShop(); });
  function renderCats() {
    $$('[data-wc-cats]').forEach(function (el) {
      if (!S) { el.innerHTML = '<p class="wc-note">' + esc(FAILED ? t('fail') : t('load')) + '</p>'; return; }
      var cats = S.sections.filter(function (s) { return s.visible !== false && s.kind !== 'update' && !s.parent; }).map(function (s) { return { s: s, n: S.products.filter(function (p) { return p.sections.indexOf(s.id) >= 0; }).length }; }).filter(function (x) { return x.n > 0; });
      var lim = Math.max(1, parseInt(el.getAttribute('data-limit'), 10) || 12); cats = cats.slice(0, lim);
      el.innerHTML = cats.length ? '<div class="wc-cats">' + cats.map(function (x) { var s = x.s; return '<a class="wc-cat" href="shop.html#sec=' + encodeURIComponent(s.id) + '"><span class="wc-ce">' + (isImg(s.image) ? '<img src="' + esc(s.image) + '" alt="" loading="lazy" onerror="this.style.display=\'none\'" style="width:56px;height:56px;border-radius:12px;object-fit:cover;display:block">' : esc(s.emoji || s.icon || '☀️')) + '</span><b data-noi18n>' + esc(X(lang() === 'en' ? (s.titleEn || s.title || '') : (s.title || s.titleEn || ''))) + '</b><small>' + x.n + ' ' + esc(t('items')) + '</small></a>'; }).join('') + '</div>' : '';
    });
  }
  function bctx() {
    var wa = String((S && S.settings && S.settings.whatsapp) || CFG.WHATSAPP || '').replace(/\D/g, '');
    return { S: S, lang: lang, t: t, card: function (p, o) { return pcard(p, null, Object.assign({ sc: 1 }, o || {})); }, timer: null,
      pinChip: function () { return '<button type="button" class="btn btn-line btn-sm" data-wc-pin data-noi18n>' + esc(PIN.pin ? '📍 ' + PIN.pin : '📍 ' + t('pinSet')) + ' ▾</button>'; },
      search: function (q) { SHOPST.q = q; SHOPST.sec = ''; renderShop(); goTop(); },
      link: function (lt, l, subj) {
        if (lt === 'section') { SHOPST.sec = l; SHOPST.q = ''; renderShop(); goTop(); }
        else if (lt === 'product') { var pp = S && S.products ? S.products.filter(function (x) { return x && x.id === l; })[0] : null; SHOPST.sec = ''; SHOPST.q = pp ? String(pp.titleEn || pp.title || '') : ''; renderShop(); goTop(); }
        else if (lt === 'form') location.href = 'contact.html';
        else if (lt === 'whatsapp' && wa) window.open('https://wa.me/' + (wa.length === 10 ? '91' + wa : wa) + '?text=' + encodeURIComponent(l || subj || 'Hello'), '_blank', 'noopener');
        else if (lt === 'call' && wa) location.href = 'tel:+' + (wa.length === 10 ? '91' + wa : wa);
      } };
  }
  function renderShop() {
    var host = $('#shopPage'); if (!host) return;
    if (!S) { host.innerHTML = '<p class="wc-note">' + esc(FAILED ? t('fail') : t('load')) + '</p>'; return; }
    var curSec = secOf(SHOPST.sec), topId = curSec ? (curSec.parent || curSec.id) : '', cats = S.sections.filter(function (s) { return s.visible !== false && s.kind !== 'update' && (!s.parent || (topId && s.parent === topId)) && S.products.some(function (p) { return p.sections.indexOf(s.id) >= 0; }); });
    var list = S.products.filter(function (p) {
      if (SHOPST.sec && p.sections.indexOf(SHOPST.sec) < 0) return false;
      if (SHOPST.q && hay(p).indexOf(SHOPST.q.toLowerCase()) < 0) return false; return true;
    });
    var pinMsg = PIN.pin ? '📍 ' + PIN.pin : '📍 ' + t('pinShort');
    var bc = window.SPBLD && S.builder ? SPBLD.norm(S.builder) : null, useB = !!(bc && SPBLD.isOn(bc, 'shop')), hasSB = useB && SPBLD.list(bc, 'shop').some(function (c) { return c.type === 'search_bar'; });
    var tt = function (s) { return X(lang() === 'en' ? (s.titleEn || s.title) : (s.title || s.titleEn)); };
    var mode = SHOPST.view || (SHOPST.sec || SHOPST.q ? 'flt' : '');
    var chipsH = '<div class="sx-chips"><button type="button" class="sx-chip' + (SHOPST.sec ? '' : ' on') + '" data-wc-sec="">' + esc(t('all')) + '</button>' + cats.map(function (s) { return '<button type="button" class="sx-chip' + (SHOPST.sec === s.id ? ' on' : '') + '" data-wc-sec="' + esc(s.id) + '" data-noi18n>' + (s.icon ? esc(s.icon) + ' ' : '') + esc(X(lang() === 'en' ? (s.titleEn || s.title) : (s.title || s.titleEn))) + '</button>'; }).join('') + '</div>',
      gridH = (list.length ? '<div class="pcg">' + list.map(function (p) { return pcard(p, null, { sc: 1 }); }).join('') + '</div>' : '<p class="wc-note">' + esc(t('none')) + '</p>'), rest = chipsH + gridH;
    function topBar(h) { return '<div class="top"><button type="button" class="sx-back" data-sx-home aria-label="Back">←</button><h1>' + h + '</h1></div>'; }
    var fltTitle = SHOPST.q ? esc(t('resFor')) + ' “' + esc(SHOPST.q) + '”' : (curSec ? esc(tt(curSec)) : '');
    function legacy(k) {
      if (k === 'shop_bar') return ''; if (k === 'shop_chips') return chipsH; if (k === 'shop_grid') return gridH;
      var m = { shop_services: 'services', shop_howto: 'howto', shop_feedback: 'feedback', shop_videos: 'videos', shop_bp: 'bp_card', shop_dt: 'dt_card' }[k];
      return m && window.SHOPX ? SHOPX.legacy(m, S, t) : '';
    }
    var oldB = $('#wcBld', host); if (oldB && (mode || !useB)) { try { SPBLD.stop(oldB); } catch (e) {} }
    if (mode === 'cats') {
      host.innerHTML = window.SHOPX ? SHOPX.cats(S, S.sections.filter(function (s) { return s.visible !== false; }), function (s) { return S.products.filter(function (p) { return p.sections.indexOf(s.id) >= 0; }).length + ' ' + t('items'); }, tt, t('allCats')) : '';
    } else if (mode === 'wish') {
      var wl = window.SHOPX ? SHOPX.wish.get().map(prod).filter(Boolean) : [];
      host.innerHTML = topBar('❤️ ' + esc(t('wishT'))) + (wl.length ? '<div class="pcg">' + wl.map(function (p) { return pcard(p, null, { sc: 1 }); }).join('') + '</div>' : '<div class="empty"><div class="i">🤍</div>' + esc(t('emptyWish')) + '</div>');
    } else if (!useB || (bc.ssv && mode === 'flt')) {
      host.innerHTML = (mode === 'flt' ? topBar(fltTitle) : '') + rest;
    }
    else if (bc.ssv) {   /* Round 30/31: the Page Builder draws the whole Shop page (every Store-style block is one of its rows) */
      if (!$('#wcBld', host) || $('#wcAll', host)) host.innerHTML = '<div id="wcBld"></div>';
      var bh2 = $('#wcBld', host), sig2 = lang() + '|' + PIN.pin + '|' + (PIN.on ? 1 : 0) + '|' + S.products.length + '|' + JSON.stringify(S.builder).length + '|' + JSON.stringify([S.services, S.howto, S.feedback, S.videos]).length + '|' + (window.SHOPX ? SHOPX.wish.get().join(',') : ''), cx2 = bctx();
      cx2.legacy = legacy;
      if (bh2.getAttribute('data-sig') !== sig2) { bh2.setAttribute('data-sig', sig2); SPBLD.stop(bh2); bh2.innerHTML = SPBLD.render(bc, 'shop', cx2); SPBLD.mount(bh2, cx2); }
    }
    else {
      if (!$('#wcBld', host) || !$('#wcAll', host)) host.innerHTML = '<div id="wcBld"></div><div id="wcAll"></div>';
      var bh = $('#wcBld', host), sig = lang() + '|' + PIN.pin + '|' + (PIN.on ? 1 : 0) + '|' + S.products.length + '|' + JSON.stringify(S.builder).length;
      if (bh.getAttribute('data-sig') !== sig) { bh.setAttribute('data-sig', sig); SPBLD.stop(bh); bh.innerHTML = SPBLD.render(bc, 'shop', bctx()); SPBLD.mount(bh, bctx()); }
      $('#wcAll', host).innerHTML = rest;
    }
    var vgs = $('.vg-sec'); if (vgs) vgs.hidden = !!(useB && bc.ssv && mode !== 'cats' && mode !== 'wish');
    if (window.SHOPX) {
      SHOPX.chrome({ S: S, t: t, tt: tt, lang: lang(), pinMsg: pinMsg, cartN: CART.reduce(function (a, c) { return a + c.qty; }, 0), tab: mode === 'cats' ? 'cats' : mode === 'wish' ? 'wish' : 'home' });
      var qi = $('#sxQ'); if (qi && document.activeElement !== qi && qi.value !== SHOPST.q) qi.value = SHOPST.q; var qx = $('#sxQx'); if (qx) qx.classList.toggle('hide', !SHOPST.q);
    }
  }
  function goTop() { var h = $('#shopPage'); if (h && h.getBoundingClientRect().top < 0) window.scrollTo({ top: Math.max(0, h.getBoundingClientRect().top + window.pageYOffset - 130), behavior: 'smooth' }); }
  function cartLines() { return CART.map(function (c) { return { p: prod(c.id), qty: c.qty }; }).filter(function (x) { return x.p && x.p.stock !== 'out' && !unavail(x.p.id); }); }
  function coHref() {
    var ls = S ? cartLines() : [], add = ls.map(function (x) { return encodeURIComponent(x.p.id) + ':' + x.qty; }).join(',');
    return 'checkout.html' + (PIN.pin ? '?pin=' + PIN.pin : '');
  }
  function renderBar() {
    var bar = $('#wcBar');
    if ($('#coPage')) { if (bar) bar.remove(); return; }
    var ls = S ? cartLines() : [], n = ls.reduce(function (a, x) { return a + x.qty; }, 0), tot = ls.reduce(function (a, x) { return a + x.qty * price(x.p); }, 0);
    if (window.SHOPX) SHOPX.badges(n);
    if (!n) { if (bar) bar.remove(); return; }
    if (!bar) { bar = document.createElement('div'); bar.id = 'wcBar'; bar.className = 'wc-fbar'; document.body.appendChild(bar); }
    var href = coHref();
    bar.innerHTML = '<span>🛒 <b>' + n + '</b> ' + esc(t('items')) + ' · ' + esc(t('sub')) + ' <b>' + money(tot) + '</b></span><span class="wc-fa"><button type="button" class="btn btn-line btn-sm" data-wc-clear data-noi18n>' + esc(t('clear')) + '</button><a class="btn btn-sun btn-sm" id="wcGo" href="' + esc(href) + '" data-noi18n>' + esc(t('go')) + ' →</a></span>';
  }

  /* ---------- Round 22: sections from the Page Builder placed on ordinary website pages ----------
     Web Shop Page Builder sections work like on the Shop page (website cart / checkout).
     Store App sections are only a "teaser": any tap opens "Download the app" -> Play Store / App Store (the store app has its own login). */
  var PLSIG = '';
  function webFile() { var f = location.pathname.split('/').pop() || 'index.html'; return /\.html$/i.test(f) ? f : f + '.html'; }
  function appLink() {
    var a = ((webCfgAll().site || {}).app) || {}, ok = function (u) { return typeof u === 'string' && /^https:\/\//i.test(u.trim()) ? u.trim() : ''; }, au = ok(a.android), iu = ok(a.ios), ua = String(navigator.userAgent || '');
    var ios = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    return ios ? (iu || au) : (au || iu);
  }
  function pageCms(f) { var W = webCfgAll(); return f === 'index.html' ? (W.home || {}) : ((W.pg || {})[f.replace(/\.html$/, '')] || {}); }
  function webCfgAll() { var c = window.SPCMS && SPCMS.data && SPCMS.data(); return c || {}; }
  function appDialog() {
    var old = $('#wcAppDlg'); if (old) old.remove();
    var link = appLink(), d = document.createElement('div'); d.id = 'wcAppDlg'; d.className = 'wc-dlg';
    d.innerHTML = '<div class="wc-dc" role="dialog" aria-modal="true"><h3 data-noi18n>📱 ' + esc(link ? t('appT') : t('appSoonT') + ' · ' + t('appSoonB')) + '</h3><p class="wc-note" data-noi18n style="margin:6px 0 12px">' + esc(link ? t('appD') : t('appSoonD')) + '</p>' +
      (link ? '<a class="btn btn-sun" id="wcAppGo" href="' + esc(link) + '" target="_blank" rel="noopener" data-noi18n>' + esc(t('appGo')) + '</a>' : '') +
      (SHOP ? ' <a class="btn btn-line btn-sm" href="' + esc(SHOP) + '" target="_blank" rel="noopener" data-noi18n>' + esc(t('appWeb')) + '</a>' : '') +
      ' <button type="button" class="btn btn-line btn-sm" id="wcAppX" data-noi18n>' + esc(t('appLater')) + '</button></div>';
    document.body.appendChild(d);
    function close() { d.remove(); }
    $('#wcAppX').onclick = close; d.addEventListener('click', function (e) { if (e.target === d) close(); });
    var go = $('#wcAppGo'); if (go) go.addEventListener('click', function () { setTimeout(close, 300); });
  }
  /* Store App sections on ordinary website pages: no products, no clicks into the app (different domain / login) — one "Sunpowers App · Coming soon" card.
     When Android / iOS links are saved in Website Builder (site.app) the same card gets a Download button. */
  function appCard() {
    var link = appLink();
    return '<div class="wc-appcard" data-noi18n><span class="wc-ai">📲</span><span class="wc-at"><b>' + esc(t('appSoonT')) + '</b><small>' + esc(link ? t('appLiveD') : (SHOP ? t('appInstD') : t('appSoonD'))) + '</small></span>' +
      (link ? '<a class="btn btn-sun btn-sm" href="' + esc(link) + '" target="_blank" rel="noopener">' + esc(t('appGet')) + '</a>' : (SHOP ? '<a class="btn btn-sun btn-sm" href="' + esc(SHOP) + '/?install=1" target="_blank" rel="noopener">' + esc(t('appInst')) + '</a>' : '<span class="wc-soon">' + esc(t('appSoonB')) + '</span>')) + '</div>';
  }
  function placeBuilder() {
    var main = $('main'), f = webFile();
    if (!main || f === 'shop.html' || !window.SPBLD || !S || !S.builder) return;
    var bc = SPBLD.norm(S.builder), list = SPBLD.webList(bc, f), PG = pageCms(f), ORD = Array.isArray(PG.order) ? PG.order : [], HID = Array.isArray(PG.hide) ? PG.hide : [];
    list = list.map(function (x, i) { x.__i = i; return x; }).sort(function (a, b) { var ia = ORD.indexOf('bp_' + a.id), ib = ORD.indexOf('bp_' + b.id); if (ia < 0 && ib < 0) return a.__i - b.__i; if (ia < 0) return -1; if (ib < 0) return 1; return ia - ib; });
    var sig = lang() + '|' + PIN.pin + '|' + (PIN.on ? 1 : 0) + '|' + S.products.length + '|' + JSON.stringify(list.map(function (x) { return [x.id, x.ref, x.pos, x.comp.cfg, x.comp.name, x.comp.nameEn]; })) + '|' + ORD.join(',') + '|' + HID.join(',');
    if (sig === PLSIG && $('[data-bplace]', main)) return;
    if (sig === PLSIG && !list.length) return;
    PLSIG = sig;
    $$('[data-bplace]', main).forEach(function (e) { SPBLD.stop(e); e.remove(); });
    if (!list.length) return;
    SPBLD.css();
    var TEASER_DONE = false;
    list.forEach(function (x) {
      var c = x.comp, teaser = !!(c.pages.store && !c.pages.shop), cx = bctx(); cx.page = teaser ? 'store' : 'shop';
      var baseLink = cx.link; cx.search = function (q) { location.href = 'shop.html#q=' + encodeURIComponent(q); };
      cx.link = function (lt, l, subj) { if (lt === 'section') location.href = 'shop.html#sec=' + encodeURIComponent(l); else if (lt === 'product') { var pp = prod(l); location.href = 'shop.html#q=' + encodeURIComponent(pp ? String(pp.titleEn || pp.title || '').slice(0, 60) : ''); } else baseLink(lt, l, subj); };
      var html = ''; try { html = teaser ? appCard() : SPBLD.renderOne(c, cx.page, cx); } catch (e) {}
      if (teaser) { if (TEASER_DONE) return; TEASER_DONE = true; }
      if (!html) return;
      var sec = document.createElement('section'); sec.className = 'sec wc-bplace'; sec.setAttribute('data-bplace', c.id); if (teaser) sec.setAttribute('data-app-teaser', '');
      sec.innerHTML = '<div class="wrap"><div class="bld-b bld-' + esc(c.type) + '" data-bid="' + esc(c.id) + '">' + html + '</div></div>';
      var ref = x.ref ? $('section[data-sid="' + (window.CSS && CSS.escape ? CSS.escape(x.ref) : x.ref) + '"]', main) : null;
      var bid = 'bp_' + c.id, oi = ORD.indexOf(bid), placed = false;
      if (oi >= 0) {   /* the user reordered this page in Website Builder: sit right after the nearest earlier section of that order */
        for (var k = oi - 1; k >= 0 && !placed; k--) {
          var pe = $('section[data-sid="' + (window.CSS && CSS.escape ? CSS.escape(ORD[k]) : ORD[k]) + '"]', main) || (ORD[k].indexOf('bp_') === 0 ? $('[data-bplace="' + ORD[k].slice(3) + '"]', main) : null);
          if (pe && pe.parentNode === main) { main.insertBefore(sec, pe.nextSibling); placed = true; }
        }
        if (!placed) { main.insertBefore(sec, main.firstElementChild); placed = true; }
      }
      if (!placed) {
        if (x.pos === 'top') main.insertBefore(sec, main.firstElementChild);
        else if (ref && ref.parentNode === main) main.insertBefore(sec, x.pos === 'above' ? ref : ref.nextSibling);
        else main.appendChild(sec);
      }
      if (HID.indexOf(bid) >= 0) sec.style.display = 'none';
      SPBLD.mount(sec, cx);
    });
    setTimeout(railAll, 60);
  }
  function renderAll() {
    $$('.wcart[data-cart]').forEach(renderBox); renderCats(); renderShop(); placeBuilder(); renderTabs(); renderBar(); setTimeout(railAll, 60); setTimeout(railAll, 600);
  }
  function renderTabs() {
    $$('[data-wc-tabs]').forEach(function (tb) {
      var boxes = $$('.wcart[data-tab]', tb.parentNode);
      var vis = boxes.filter(function (b) { return !boxCfg(b).off; }); if (!vis.length) { tb.hidden = true; return; } tb.hidden = false;
      var cur = tb.getAttribute('data-cur'); if (!cur || !vis.some(function (b) { return b.getAttribute('data-cart') === cur; })) cur = vis[0].getAttribute('data-cart');
      tb.setAttribute('data-cur', cur);
      tb.innerHTML = vis.map(function (b) { var c = boxCfg(b), k = b.getAttribute('data-cart'), nm = c.title || b.getAttribute('data-tab'); return '<button type="button" role="tab" class="wc-chip' + (k === cur ? ' on' : '') + '" data-wc-tab="' + esc(k) + '" aria-selected="' + (k === cur) + '" data-noi18n>' + esc(X(nm)) + '</button>'; }).join('');
      boxes.forEach(function (b) { b.hidden = boxCfg(b).off || b.getAttribute('data-cart') !== cur; });
    });
  }

  /* ---------- pin dialog ---------- */
  function pinDialog() {
    var old = $('#wcPinDlg'); if (old) old.remove();
    var d = document.createElement('div'); d.id = 'wcPinDlg'; d.className = 'wc-dlg';
    d.innerHTML = '<div class="wc-dc" role="dialog" aria-modal="true"><h3 data-noi18n>' + esc(t('pin')) + '</h3><input id="wcPinIn" class="wc-in" inputmode="numeric" maxlength="6" placeholder="226001" value="' + esc(PIN.pin) + '"><p id="wcPinMsg" class="wc-note" style="margin:6px 0" aria-live="polite"></p><div style="display:flex;gap:8px"><button type="button" class="btn btn-sun btn-sm" id="wcPinOk" data-noi18n>' + esc(t('pinOk')) + '</button><button type="button" class="btn btn-line btn-sm" id="wcPinX" data-noi18n>✕</button></div></div>';
    document.body.appendChild(d); var inp = $('#wcPinIn'); inp.focus();
    function close() { d.remove(); }
    $('#wcPinX').onclick = close; d.addEventListener('click', function (e) { if (e.target === d) close(); });
    function go() {
      var v = (inp.value || '').replace(/\D/g, '');
      if (!/^[1-9]\d{5}$/.test(v)) { $('#wcPinMsg').textContent = t('pinBad'); return; }
      PIN.pin = v; pinPut(v); pinSig = ''; close();
      loadStore().then(pinSync).then(renderAll);
    }
    $('#wcPinOk').onclick = go; inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); });
  }

  /* ---------- events ---------- */
  document.addEventListener('click', function (e) {
    var tg = e.target.closest ? e.target.closest('[data-wc-add],[data-wc-buy],[data-wc-sc],[data-wc-q],[data-wc-pin],[data-wc-sec],[data-wc-tab],[data-wc-clear]') : null; if (!tg) return;
    if (tg.hasAttribute('data-wc-sc')) { var gg = tg.parentNode.querySelector('[data-wc-scroller]'); if (gg) gg.scrollBy({ left: parseInt(tg.getAttribute('data-wc-sc'), 10) * Math.max(200, gg.clientWidth * 0.8), behavior: 'smooth' }); return; }
    if (tg.hasAttribute('data-wc-q')) {
      var id = tg.getAttribute('data-id'), n = $('[data-wc-n="' + (window.CSS && CSS.escape ? CSS.escape(id) : id) + '"]', tg.parentNode);
      var v = Math.max(1, Math.min(99, (parseInt(n && n.textContent, 10) || 1) + parseInt(tg.getAttribute('data-wc-q'), 10))); if (n) n.textContent = v; return;
    }
    if (tg.hasAttribute('data-wc-buy')) {
      var bid = tg.getAttribute('data-wc-buy'), bp = prod(bid); if (!bp || bp.stock === 'out' || unavail(bid)) return;
      var bi = CART.filter(function (c) { return c.id === bid; })[0]; if (!bi) CART.push({ id: bid, qty: 1 });
      saveCart(); renderBar(); location.href = coHref(); return;
    }
    if (tg.hasAttribute('data-wc-add')) {
      var pid = tg.getAttribute('data-wc-add'), p = prod(pid); if (!p || p.stock === 'out' || unavail(pid)) return;
      var box = tg.closest('.wc-p'), nn = box && $('.wc-q b', box), q = Math.max(1, Math.min(99, parseInt(nn && nn.textContent, 10) || 1));
      var it = CART.filter(function (c) { return c.id === pid; })[0]; if (it) it.qty = Math.min(999, it.qty + q); else CART.push({ id: pid, qty: q });
      saveCart(); renderBar(); var old = tg.textContent; tg.textContent = tg.classList.contains('add') ? '✓' : t('added'); setTimeout(function () { tg.textContent = old; }, 1200); return;
    }
    if (tg.hasAttribute('data-wc-pin')) { e.preventDefault(); pinDialog(); return; }
    if (tg.hasAttribute('data-wc-sec')) { e.preventDefault(); SHOPST.sec = tg.getAttribute('data-wc-sec'); SHOPST.q = ''; SHOPST.view = ''; renderShop(); goTop(); return; }
    if (tg.hasAttribute('data-wc-tab')) { var tb = tg.closest('[data-wc-tabs]'); tb.setAttribute('data-cur', tg.getAttribute('data-wc-tab')); renderTabs(); return; }
    if (tg.hasAttribute('data-wc-clear')) { CART = []; saveCart(); renderBar(); }
  });
  document.addEventListener('input', function (e) { if (e.target && e.target.id === 'wcSearch') { SHOPST.q = e.target.value; clearTimeout(renderShop._t); renderShop._t = setTimeout(renderShop, 200); } });
  document.addEventListener('click', function (e) {   /* Store-style page parts: wishlist, service cards, accordion, video, bottom bar */
    var g = e.target.closest ? e.target.closest('[data-wc-wish],[data-sx-lt],[data-sx-acc],[data-sx-yt],[data-sx-tab],[data-sx-home],[data-sx-cats],#sxQx') : null; if (!g || !window.SHOPX) return;
    function home() { SHOPST.sec = ''; SHOPST.q = ''; SHOPST.view = ''; var qi = $('#sxQ'); if (qi) qi.value = ''; renderShop(); window.scrollTo({ top: 0, behavior: 'smooth' }); }
    if (g.hasAttribute('data-wc-wish')) { e.preventDefault(); var id = g.getAttribute('data-wc-wish'), on = SHOPX.wish.toggle(id); $$('[data-wc-wish]').forEach(function (h) { if (h.getAttribute('data-wc-wish') === id) { h.classList.toggle('on', on); h.textContent = on ? '♥' : '♡'; } }); SHOPX.badges(CART.reduce(function (a, c) { return a + c.qty; }, 0)); if (SHOPST.view === 'wish') renderShop(); return; }
    if (g.hasAttribute('data-sx-lt')) { e.preventDefault(); bctx().link(g.getAttribute('data-sx-lt'), g.getAttribute('data-sx-l'), g.getAttribute('data-subj')); return; }
    if (g.hasAttribute('data-sx-acc')) { var ac = g.closest('.acc'); if (ac) { ac.classList.toggle('open'); g.setAttribute('aria-expanded', ac.classList.contains('open') ? 'true' : 'false'); } return; }
    if (g.hasAttribute('data-sx-yt')) { SHOPX.openYt(g); return; }
    if (g.id === 'sxQx') { SHOPST.q = ''; var q2 = $('#sxQ'); if (q2) { q2.value = ''; q2.focus(); } renderShop(); return; }
    if (g.hasAttribute('data-sx-home')) { e.preventDefault(); home(); return; }
    if (g.hasAttribute('data-sx-cats')) { e.preventDefault(); SHOPST.view = 'cats'; SHOPST.sec = ''; SHOPST.q = ''; renderShop(); window.scrollTo({ top: 0, behavior: 'smooth' }); return; }
    if (g.hasAttribute('data-sx-tab')) {
      var tb = g.getAttribute('data-sx-tab'); if (tb === 'home') { e.preventDefault(); home(); } else if (tb === 'cats') { e.preventDefault(); SHOPST.view = 'cats'; SHOPST.sec = ''; SHOPST.q = ''; renderShop(); window.scrollTo({ top: 0, behavior: 'smooth' }); }
      else if (tb === 'wish') { e.preventDefault(); SHOPST.view = 'wish'; SHOPST.sec = ''; SHOPST.q = ''; renderShop(); window.scrollTo({ top: 0, behavior: 'smooth' }); }
    }
  });
  document.addEventListener('input', function (e) { if (e.target && e.target.id === 'sxQ') { SHOPST.q = e.target.value.trim(); SHOPST.sec = ''; SHOPST.view = ''; clearTimeout(renderShop._t); renderShop._t = setTimeout(renderShop, 220); } });
  document.addEventListener('sp-cms', function () { renderAll(); });
  document.addEventListener('sp-lang', function () { setTimeout(renderAll, 40); });

  function boot() {
    if (!$('.wcart[data-cart]') && !$('#shopPage') && !$('[data-wc-cats]')) {
      /* ordinary page: only needed when the Page Builder placed a section on it */
      if (!window.SPBLD || !$('main') || webFile() === 'shop.html' || webFile() === 'checkout.html') return;
      PIN.pin = pinGet(); loadStore().then(function () { return S ? pinSync() : null; }).then(function () { if (S) placeBuilder(); }); return;
    }
    PIN.pin = pinGet(); renderAll();
    loadStore().then(function () { return S ? pinSync() : null; }).then(renderAll);
  }
  window.SPCART = { render: renderAll, state: function () { return { cart: CART, pin: PIN, store: S }; },
    load: function () { PIN.pin = PIN.pin || pinGet(); return loadStore(); }, rpc: rpc, prod: prod, price: price, money: money, esc: esc, lang: lang, ptitle: ptitle, unavail: unavail,
    pinSync: function (v) { if (/^\d{6}$/.test(v || '')) { PIN.pin = v; pinPut(v); } return pinSync(); }, pinGet: pinGet,
    getCart: function () { return CART.map(function (c) { return { id: c.id, qty: c.qty }; }); }, setCart: function (c) { CART = (c || []).slice(0, 60); saveCart(); },
    pinOn: function () { return PIN.on; }, pinBad: function () { return PIN.bad; } };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
