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
  function X(v) { return hg() && /[\u0900-\u097F]/.test(v) ? SPI18N.xlit(v) : v; }
  function pick(o) { if (!o) return ''; if (typeof o === 'string') return X(o); return X(o[lang()] || o.en || o.hi || ''); }
  var SHOP = String(CFG.SHOP_URL || '').replace(/\/+$/, '');
  var T = {
    add: ['Add to cart', 'कार्ट में जोड़ें'], buy: ['Buy now', 'अभी ख़रीदें'], view: ['View', 'देखें'], added: ['Added ✓', 'जुड़ गया ✓'], out: ['Out of stock', 'स्टॉक में नहीं'],
    na: ['Not available at this pin code', 'इस पिन कोड पर उपलब्ध नहीं'], chg: ['Change pin code', 'पिन कोड बदलें'],
    pin: ['Delivery pin code', 'डिलीवरी पिन कोड'], pinSet: ['Enter pin code', 'पिन कोड डालें'], pinOk: ['Check', 'जाँचें'], pinBad: ['Enter a 6-digit pin code', '6 अंकों का पिन कोड डालें'],
    none: ['No products in this section yet. See all products in the shop.', 'इस सेक्शन में अभी प्रोडक्ट नहीं हैं। शॉप में सभी प्रोडक्ट देखें।'],
    fail: ['Could not load products. Please try again or WhatsApp us.', 'प्रोडक्ट लोड नहीं हुए। फिर कोशिश करें या WhatsApp करें।'],
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
    var out = { sections: [], products: [], settings: d && d.settings || {}, builder: d && d.builder || null };
    (d && d.sections || []).forEach(function (s) { if (s && s.id) out.sections.push(s); });
    (d && d.products || []).forEach(function (p) {
      if (!p || !p.id || p.visible === false || p.web === false) return;
      p.sections = Array.isArray(p.sections) ? p.sections : []; p.images = Array.isArray(p.images) ? p.images : []; p.stock = p.stock === 'out' ? 'out' : 'in';
      out.products.push(p);
    });
    out.products.sort(function (a, b) { return num(a.sort) - num(b.sort); });
    return out;
  }
  function loadStore() {
    if (S) return Promise.resolve(S);
    if (LOADING) return LOADING;
    try { var c = JSON.parse(sessionStorage.getItem('sp_wstore') || 'null'); if (c && Date.now() - c.at < 300000) { S = normStore(c.d); return Promise.resolve(S); } } catch (e) {}
    LOADING = rpc('sp_get_store', {}, 12000).then(function (d) {
      if (!d || typeof d !== 'object' || !Array.isArray(d.products)) throw new Error('bad store');
      try { sessionStorage.setItem('sp_wstore', JSON.stringify({ at: Date.now(), d: { sections: d.sections, products: d.products, builder: d.builder || null, settings: d.settings || {} } })); } catch (e) {}
      S = normStore(d); FAILED = false; return S;
    }).catch(function () { FAILED = true; S = null; return null; }).then(function (r) { LOADING = null; return r; });
    return LOADING;
  }
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
  function pcard(p, cfg, opt) {
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
    if (h3 && cfg.title) { h3.textContent = cfg.title; h3.setAttribute('data-noi18n', ''); }
    if (!list) return;
    if (!S) { list.innerHTML = '<p class="wc-note">' + esc(FAILED ? t('fail') : t('load')) + '</p>'; return; }
    var ps = pickProducts(cfg);
    var more = cfg.more ? linkFor(cfg.more, '') : (SHOP ? 'shop.html' : '');
    list.innerHTML = ps.length ? rail(ps.map(function (p) { return pcard(p, cfg); }).join('')) + (more ? '<p class="wc-more"><a class="link" href="' + esc(more) + '">' + esc(t('shop')) + ' →</a></p>' : '')
      : '<p class="wc-note">' + esc(t('none')) + (more ? ' <a class="link" href="' + esc(more) + '">' + esc(t('shop')) + ' →</a>' : '') + '</p>';
  }
  var SHOPST = { sec: '', q: '' };
  function readHash() { try { var h = location.hash || '', hm = h.match(/sec=([^&]+)/), hq = h.match(/q=([^&]+)/); if (hm) { SHOPST.sec = decodeURIComponent(hm[1]); SHOPST.q = ''; } else if (hq) { SHOPST.q = decodeURIComponent(hq[1]); SHOPST.sec = ''; } } catch (e) {} }
  readHash(); window.addEventListener('hashchange', function () { readHash(); if (typeof renderShop === 'function') renderShop(); });
  function renderCats() {
    $$('[data-wc-cats]').forEach(function (el) {
      if (!S) { el.innerHTML = '<p class="wc-note">' + esc(FAILED ? t('fail') : t('load')) + '</p>'; return; }
      var cats = S.sections.filter(function (s) { return s.visible !== false && s.kind !== 'update' && !s.parent; }).map(function (s) { return { s: s, n: S.products.filter(function (p) { return p.sections.indexOf(s.id) >= 0; }).length }; }).filter(function (x) { return x.n > 0; });
      var lim = Math.max(1, parseInt(el.getAttribute('data-limit'), 10) || 12); cats = cats.slice(0, lim);
      el.innerHTML = cats.length ? '<div class="wc-cats">' + cats.map(function (x) { var s = x.s; return '<a class="wc-cat" href="shop.html#sec=' + encodeURIComponent(s.id) + '"><span class="wc-ce">' + esc(s.emoji || s.icon || '☀️') + '</span><b data-noi18n>' + esc(X(lang() === 'en' ? (s.titleEn || s.title || '') : (s.title || s.titleEn || ''))) + '</b><small>' + x.n + ' ' + esc(t('items')) + '</small></a>'; }).join('') + '</div>' : '';
    });
  }
  function bctx() {
    var wa = String((S && S.settings && S.settings.whatsapp) || CFG.WHATSAPP || '').replace(/\D/g, '');
    return { S: S, lang: lang, t: t, card: function (p, o) { return pcard(p, null, o); }, timer: null,
      pinChip: function () { return '<button type="button" class="btn btn-line btn-sm" data-wc-pin data-noi18n>' + esc(PIN.pin ? '📍 ' + PIN.pin : '📍 ' + t('pinSet')) + ' ▾</button>'; },
      search: function (q) { SHOPST.q = q; SHOPST.sec = ''; renderShop(); var a = $('#wcAll'); if (a && a.scrollIntoView) a.scrollIntoView({ behavior: 'smooth', block: 'start' }); },
      link: function (lt, l, subj) {
        if (lt === 'section') { SHOPST.sec = l; SHOPST.q = ''; renderShop(); var a = $('#wcAll'); if (a && a.scrollIntoView) a.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
        else if (lt === 'product') { var pp = S && S.products ? S.products.filter(function (x) { return x && x.id === l; })[0] : null; SHOPST.sec = ''; SHOPST.q = pp ? String(pp.titleEn || pp.title || '') : ''; renderShop(); var b2 = $('#wcAll'); if (b2 && b2.scrollIntoView) b2.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
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
    var pinMsg = PIN.pin ? '📍 ' + PIN.pin + (PIN.district ? ' · ' + PIN.district : '') : '📍 ' + t('pinSet');
    var keepQ = document.activeElement && document.activeElement.id === 'wcSearch';
    var bc = window.SPBLD && S.builder ? SPBLD.norm(S.builder) : null, useB = !!(bc && SPBLD.isOn(bc, 'shop')), hasSB = useB && SPBLD.list(bc, 'shop').some(function (c) { return c.type === 'search_bar'; });
    var bar = '<div class="wc-bar"><input id="wcSearch" type="search" class="wc-in" data-noi18n placeholder="' + esc(t('search')) + '" value="' + esc(SHOPST.q) + '"><button type="button" class="btn btn-line btn-sm" data-wc-pin id="wcPinBtn" data-noi18n>' + esc(pinMsg) + ' ▾</button></div>';
    var rest = '<div class="wc-chips"><button type="button" class="wc-chip' + (SHOPST.sec ? '' : ' on') + '" data-wc-sec="">' + esc(t('all')) + '</button>' + cats.map(function (s) { return '<button type="button" class="wc-chip' + (SHOPST.sec === s.id ? ' on' : '') + '" data-wc-sec="' + esc(s.id) + '" data-noi18n>' + esc(X(lang() === 'en' ? (s.titleEn || s.title) : (s.title || s.titleEn))) + '</button>'; }).join('') + '</div>' +
      (list.length ? rail(list.map(function (p) { return pcard(p, null); }).join(''), 'wc-gs' + (list.length > 6 ? ' wc-g2' : '')) : '<p class="wc-note">' + esc(t('none')) + '</p>');
    if (!useB) host.innerHTML = bar + rest;
    else {
      if (!$('#wcBld', host)) host.innerHTML = '<div id="wcBld" data-noi18n></div><div id="wcAll"></div>';
      var bh = $('#wcBld', host), sig = lang() + '|' + PIN.pin + '|' + (PIN.on ? 1 : 0) + '|' + S.products.length + '|' + JSON.stringify(S.builder).length;
      if (bh.getAttribute('data-sig') !== sig) { bh.setAttribute('data-sig', sig); SPBLD.stop(bh); bh.innerHTML = SPBLD.render(bc, 'shop', bctx()); SPBLD.mount(bh, bctx()); }
      $('#wcAll', host).innerHTML = (hasSB ? '' : bar) + rest;
    }
    if (keepQ) { var i = $('#wcSearch'); if (i) { i.focus(); try { i.setSelectionRange(i.value.length, i.value.length); } catch (e) {} } }
  }
  function cartLines() { return CART.map(function (c) { return { p: prod(c.id), qty: c.qty }; }).filter(function (x) { return x.p && x.p.stock !== 'out' && !unavail(x.p.id); }); }
  function coHref() {
    var ls = S ? cartLines() : [], add = ls.map(function (x) { return encodeURIComponent(x.p.id) + ':' + x.qty; }).join(',');
    return 'checkout.html' + (PIN.pin ? '?pin=' + PIN.pin : '');
  }
  function renderBar() {
    var bar = $('#wcBar');
    if ($('#coPage')) { if (bar) bar.remove(); return; }
    var ls = S ? cartLines() : [], n = ls.reduce(function (a, x) { return a + x.qty; }, 0), tot = ls.reduce(function (a, x) { return a + x.qty * price(x.p); }, 0);
    if (!n) { if (bar) bar.remove(); return; }
    if (!bar) { bar = document.createElement('div'); bar.id = 'wcBar'; bar.className = 'wc-fbar'; document.body.appendChild(bar); }
    var href = coHref();
    bar.innerHTML = '<span>🛒 <b>' + n + '</b> ' + esc(t('items')) + ' · ' + esc(t('sub')) + ' <b>' + money(tot) + '</b></span><span class="wc-fa"><button type="button" class="btn btn-line btn-sm" data-wc-clear data-noi18n>' + esc(t('clear')) + '</button><a class="btn btn-sun btn-sm" id="wcGo" href="' + esc(href) + '" data-noi18n>' + esc(t('go')) + ' →</a></span>';
  }
  function renderAll() {
    $$('.wcart[data-cart]').forEach(renderBox); renderCats(); renderShop(); renderTabs(); renderBar(); setTimeout(railAll, 60); setTimeout(railAll, 600);
  }
  function renderTabs() {
    $$('[data-wc-tabs]').forEach(function (tb) {
      var boxes = $$('.wcart[data-tab]', tb.parentNode);
      var vis = boxes.filter(function (b) { return !boxCfg(b).off; }); if (!vis.length) { tb.hidden = true; return; } tb.hidden = false;
      var cur = tb.getAttribute('data-cur'); if (!cur || !vis.some(function (b) { return b.getAttribute('data-cart') === cur; })) cur = vis[0].getAttribute('data-cart');
      tb.setAttribute('data-cur', cur);
      tb.innerHTML = vis.map(function (b) { var c = boxCfg(b), k = b.getAttribute('data-cart'), nm = c.title || b.getAttribute('data-tab'); return '<button type="button" role="tab" class="wc-chip' + (k === cur ? ' on' : '') + '" data-wc-tab="' + esc(k) + '" aria-selected="' + (k === cur) + '" data-noi18n>' + esc(nm) + '</button>'; }).join('');
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
      saveCart(); renderBar(); var old = tg.textContent; tg.textContent = t('added'); setTimeout(function () { tg.textContent = old; }, 1200); return;
    }
    if (tg.hasAttribute('data-wc-pin')) { e.preventDefault(); pinDialog(); return; }
    if (tg.hasAttribute('data-wc-sec')) { SHOPST.sec = tg.getAttribute('data-wc-sec'); renderShop(); return; }
    if (tg.hasAttribute('data-wc-tab')) { var tb = tg.closest('[data-wc-tabs]'); tb.setAttribute('data-cur', tg.getAttribute('data-wc-tab')); renderTabs(); return; }
    if (tg.hasAttribute('data-wc-clear')) { CART = []; saveCart(); renderBar(); }
  });
  document.addEventListener('input', function (e) { if (e.target && e.target.id === 'wcSearch') { SHOPST.q = e.target.value; clearTimeout(renderShop._t); renderShop._t = setTimeout(renderShop, 200); } });
  document.addEventListener('sp-cms', function () { renderAll(); });
  document.addEventListener('sp-lang', function () { setTimeout(renderAll, 40); });

  function boot() {
    if (!$('.wcart[data-cart]') && !$('#shopPage') && !$('[data-wc-cats]')) return;
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
