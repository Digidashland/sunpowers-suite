/* Sunpowers — "Look" engine (Round 15): colour theme per panel + greeting banner.
   Shared by Website, Online Store, Admin and CRM.  Settings live in ONE public row (sp_get_cfg) that only the Admin can change.
   <script src="sp-look.js" data-app="website|store|admin|crm"></script>
   API:  SPLOOK.boot(app, {ctx})   SPLOOK.apply(app, cfg)   SPLOOK.greet(app, cfg, ctx)   SPLOOK.PRESETS   SPLOOK.derive(preset)      */
(function () {
  'use strict';
  if (window.SPLOOK) return;
  var me = document.currentScript, APP = (me && me.getAttribute('data-app')) || '';
  var KEY = 'sp_look_v1';

  /* ---------- colour maths ---------- */
  function hsl2hex(h, s, l) { h = ((h % 360) + 360) % 360; s = Math.max(0, Math.min(100, s)) / 100; l = Math.max(0, Math.min(100, l)) / 100; var a = s * Math.min(l, 1 - l);
    function f(n) { var k = (n + h / 30) % 12, c = l - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1))); var x = Math.round(255 * c).toString(16); return x.length < 2 ? '0' + x : x; } return '#' + f(0) + f(8) + f(4); }
  function hex2hsl(hex) { var m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '')); if (!m) return null; var n = parseInt(m[1], 16), r = (n >> 16 & 255) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255, mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, h = 0, s = 0, d = mx - mn;
    if (d) { s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn); h = mx === r ? ((g - b) / d + (g < b ? 6 : 0)) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h *= 60; } return { h: h, s: s * 100, l: l * 100 }; }

  /* id, [English, Hindi], hue, saturation, accent (buttons / highlights) */
  var PRESETS = [
    { id: 'green',  n: ['Solar Green', 'सोलर ग्रीन'],     h: 137, s: 65, a: '#f4b740', base: true },
    { id: 'ocean',  n: ['Ocean Blue', 'ओशन ब्लू'],        h: 212, s: 68, a: '#ffb347' },
    { id: 'violet', n: ['Royal Violet', 'रॉयल वायलेट'],    h: 262, s: 50, a: '#ffc857' },
    { id: 'sunset', n: ['Sunset Orange', 'सनसेट ऑरेंज'],   h: 19,  s: 76, a: '#ffd166' },
    { id: 'ruby',   n: ['Ruby Red', 'रूबी रेड'],          h: 350, s: 62, a: '#ffcf5c' },
    { id: 'teal',   n: ['Lagoon Teal', 'लैगून टील'],      h: 176, s: 62, a: '#ffb84d' },
    { id: 'rose',   n: ['Rose Pink', 'रोज़ पिंक'],         h: 328, s: 58, a: '#ffd166' },
    { id: 'coffee', n: ['Coffee Brown', 'कॉफ़ी ब्राउन'],   h: 27,  s: 42, a: '#e9b44c' },
    { id: 'slate',  n: ['Slate Grey', 'स्लेट ग्रे'],       h: 215, s: 24, a: '#f2b134' }
  ];
  function presetOf(t) {
    t = t || {}; if (t.preset === 'custom') { var p = hex2hsl(t.primary) || { h: 137, s: 65 }, a = hex2hsl(t.accent); var al = a ? Math.max(52, Math.min(74, a.l)) : 60;
      return { id: 'custom', h: p.h, s: Math.max(22, Math.min(78, p.s)), a: a ? hsl2hex(a.h, Math.max(55, a.s), al) : '#f4b740' }; }
    for (var i = 0; i < PRESETS.length; i++) if (PRESETS[i].id === t.preset) return PRESETS[i]; return PRESETS[0];
  }
  /* every token comes from ONE hue, so backgrounds, text and borders always match as a combo */
  function derive(p) {
    var h = p.h, s = p.s, a = hex2hsl(p.a) || { h: 41, s: 90, l: 61 }, T = {};
    T.forestD = hsl2hex(h, s * .7, 8); T.forest = hsl2hex(h, s * .62, 11); T.forest2 = hsl2hex(h, s * .55, 16); T.forest3 = hsl2hex(h, s * .5, 22);
    T.leafB = hsl2hex(h, s, 42); T.leaf = hsl2hex(h, s, 34); T.leafD = hsl2hex(h, s, 26);
    T.mint = hsl2hex(h, s * .45, 93); T.mint2 = hsl2hex(h, s * .4, 86); T.paper = hsl2hex(h, 22, 96); T.line = hsl2hex(h, 20, 88); T.line2 = hsl2hex(h, 16, 82);
    T.ink = hsl2hex(h, 35, 11); T.ink2 = hsl2hex(h, 22, 19); T.mute = hsl2hex(h, 10, 38); T.onDark = hsl2hex(h, 35, 94); T.onDarkMute = hsl2hex(h, 22, 72);
    T.sun = p.a; T.sunD = hsl2hex(a.h, a.s, Math.max(24, a.l - 24)); T.sunL = hsl2hex(a.h, Math.min(100, a.s + 5), 93);
    return T;
  }
  function css(app, t) {
    var p = presetOf(t); if (p.base) return ''; var T = derive(p), v;
    if (app === 'store' || app === 'admin') {
      v = '--g:' + T.leaf + ';--g-d:' + T.leafD + ';--g-l:' + T.mint + ';--g-m:' + T.mint2 + ';--bg:' + T.paper + ';--txt:' + T.ink + ';--mut:' + T.mute + ';--line:' + T.line + ';--gold:' + T.sun;
    } else {
      v = '--forest-d:' + T.forestD + ';--forest:' + T.forest + ';--forest-2:' + T.forest2 + ';--forest-3:' + T.forest3 + ';--leaf-b:' + T.leafB + ';--leaf:' + T.leaf + ';--leaf-d:' + T.leafD + ';--mint:' + T.mint + ';--mint-2:' + T.mint2 +
        ';--paper:' + T.paper + ';--line:' + T.line + ';--line-2:' + T.line2 + ';--ink:' + T.ink + ';--ink-2:' + T.ink2 + ';--mute:' + T.mute + ';--on-dark:' + T.onDark + ';--on-dark-mute:' + T.onDarkMute + ';--sun:' + T.sun + ';--sun-d:' + T.sunD + ';--sun-l:' + T.sunL;
    }
    return ':root:root{' + v + '}';
  }
  function apply(app, cfg) {
    var t = cfg && cfg.theme && cfg.theme[app], el = document.getElementById('sp-look-css');
    var txt = css(app, t);
    if (!txt) { if (el) el.remove(); return; }
    if (!el) { el = document.createElement('style'); el.id = 'sp-look-css'; (document.head || document.documentElement).appendChild(el); }
    if (el.textContent !== txt) el.textContent = txt;
    try { var m = document.querySelector('meta[name=theme-color]'); if (m) m.setAttribute('content', derive(presetOf(t)).forest); } catch (e) {}
  }

  /* ---------- greeting banner ---------- */
  var GCSS = '.sp-greet{position:relative;z-index:70;display:flex;align-items:center;justify-content:center;gap:10px;padding:8px 44px 8px 14px;min-height:38px;font:700 14px/1.25 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans Devanagari",sans-serif;text-align:center;overflow:hidden}' +
    '.sp-greet .sp-gt{min-width:0;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}.sp-greet.marq .sp-gt{text-overflow:clip}.sp-greet.marq .sp-gtm{display:inline-block;padding-left:100%;animation:spgm 16s linear infinite}@keyframes spgm{to{transform:translateX(-100%)}}' +
    '.sp-greet .sp-gx{position:absolute;right:6px;top:50%;transform:translateY(-50%);width:30px;height:30px;border-radius:50%;border:0;background:rgba(255,255,255,.22);color:inherit;font:700 18px/1 system-ui;cursor:pointer}.sp-greet .sp-gx:hover{background:rgba(255,255,255,.4)}' +
    '.sp-gi{display:inline-block;font-size:20px;line-height:1;flex:none}' +
    '.sp-a-bounce{animation:spab 1s ease-in-out infinite}@keyframes spab{50%{transform:translateY(-5px)}}.sp-a-pulse{animation:spap 1.2s ease-in-out infinite}@keyframes spap{50%{transform:scale(1.3)}}' +
    '.sp-a-spin{animation:spas 3s linear infinite}@keyframes spas{to{transform:rotate(360deg)}}.sp-a-wave{transform-origin:70% 70%;animation:spaw 1.4s ease-in-out infinite}@keyframes spaw{0%,60%,100%{transform:rotate(0)}10%,30%{transform:rotate(16deg)}20%,40%{transform:rotate(-10deg)}}' +
    '.sp-a-float{animation:spaf 2.4s ease-in-out infinite}@keyframes spaf{50%{transform:translateY(-4px) rotate(-6deg)}}.sp-a-flicker{animation:spaq 1.1s steps(1) infinite}@keyframes spaq{0%{transform:scale(1)}30%{transform:scale(1.14) rotate(-4deg)}60%{transform:scale(.94) rotate(3deg)}}' +
    '.sp-a-sparkle{animation:spak 1.6s ease-in-out infinite}@keyframes spak{0%,100%{transform:scale(1) rotate(0);filter:brightness(1)}50%{transform:scale(1.25) rotate(18deg);filter:brightness(1.35)}}' +
    '.sp-g-festive{background:linear-gradient(90deg,#ff8f1f,#ffbf2e 50%,#ff8f1f);color:#3b1d00}.sp-g-theme{background:linear-gradient(90deg,var(--forest,#0b2e1f),var(--leaf,#1e8e3e));color:#fff}.sp-g-theme.g2{background:linear-gradient(90deg,var(--g-d,#14692c),var(--g,#1e8e3e))}' +
    '.sp-g-royal{background:linear-gradient(90deg,#3b1d7a,#6b46c1);color:#fff}.sp-g-rose{background:linear-gradient(90deg,#c2185b,#ec407a);color:#fff}.sp-g-night{background:#101820;color:#ffd166}.sp-g-light{background:var(--mint,#e8f5e9);color:var(--forest,#14231a);border-bottom:1px solid var(--line,#dce5da)}' +
    '@media(max-width:560px){.sp-greet{font-size:13px;gap:7px;padding-left:10px}.sp-gi{font-size:18px}}@media print{.sp-greet{display:none}}';
  var ICONS = ['🪔', '🎆', '🎇', '✨', '🎉', '🎊', '🌸', '🌈', '☀️', '🙏', '🕉️', '🌙', '⭐', '🎁', '🛍️', '🔥', '💥', '🎄', '🥳', '🪁', '🌻', '🍬', '🚩', '🇮🇳', '⚡', '🔆'];
  var ANIMS = [['bounce', 'Bounce', 'उछलना'], ['pulse', 'Pulse', 'धड़कना'], ['spin', 'Spin', 'घूमना'], ['wave', 'Wave', 'हिलाना'], ['float', 'Float', 'तैरना'], ['flicker', 'Flicker (diya)', 'झिलमिल'], ['sparkle', 'Sparkle', 'चमकना'], ['none', 'None', 'स्थिर']];
  var STYLES = [['festive', 'Festive Saffron', 'फेस्टिव केसरिया'], ['theme', 'Panel colour', 'पैनल का रंग'], ['royal', 'Royal Violet', 'रॉयल वायलेट'], ['rose', 'Rose', 'रोज़'], ['night', 'Night Gold', 'नाइट गोल्ड'], ['light', 'Soft Light', 'सॉफ़्ट लाइट']];
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function today() { try { return new Date(Date.now() + 19800000).toISOString().slice(0, 10); } catch (e) { return ''; } }
  function shouldShow(app, g, ctx) {
    if (!g || !g.on || !String(g.text || '').trim()) return false;
    var d = today(); if (g.from && d < g.from) return false; if (g.to && d > g.to) return false;
    var t = g.t || {}; ctx = ctx || {};
    if (app === 'website') return ctx.page === 'shop' ? !!t.shop : (ctx.page === 'home' ? !!t.home : !!t.inner);
    if (app === 'store') return !!t.store;
    if (app === 'admin') return !!t.admin;
    if (app === 'crm') { var c = t.crm || {}; return !!c.all || !!(ctx.userId != null && c.users && c.users[String(ctx.userId)]); }
    return false;
  }
  function bannerHtml(g, app) {
    var ic = g.icon ? '<span class="sp-gi sp-a-' + esc(g.anim || 'bounce') + '" aria-hidden="true">' + esc(g.icon) + '</span>' : '';
    return ic + '<span class="sp-gt"><span class="sp-gtm">' + esc(g.text) + '</span></span>' + ic + (g.close === false ? '' : '<button type="button" class="sp-gx" aria-label="Close">×</button>');
  }
  function styleOnce() { if (document.getElementById('sp-greet-css')) return; var s = document.createElement('style'); s.id = 'sp-greet-css'; s.textContent = GCSS; (document.head || document.documentElement).appendChild(s); }
  function ssGet(k) { try { return sessionStorage.getItem(k); } catch (e) { return null; } }
  function ssSet(k, v) { try { sessionStorage.setItem(k, v); } catch (e) {} }
  function greet(app, cfg, ctx) {
    var old = document.getElementById('sp-greet'); var g = cfg && cfg.greet;
    if (!shouldShow(app, g, ctx) || ssGet('sp_gx_' + (g.id || '0'))) { if (old) old.remove(); return null; }
    styleOnce();
    var el = old || document.createElement('div'); el.id = 'sp-greet'; el.setAttribute('role', 'status'); el.setAttribute('data-noi18n', '');
    var st = g.style || 'festive'; el.className = 'sp-greet sp-g-' + st + (app === 'store' || app === 'admin' ? ' g2' : '');
    var html = bannerHtml(g, app); if (el.getAttribute('data-sig') !== html) { el.innerHTML = html; el.setAttribute('data-sig', html); }
    el.querySelector('.sp-gx') && (el.querySelector('.sp-gx').onclick = function () { ssSet('sp_gx_' + (g.id || '0'), '1'); el.remove(); });
    var rz = function (v) { return typeof v === 'function' ? v() : v; }, mount = (ctx && rz(ctx.mount)) || document.body, bf = ctx && rz(ctx.before);
    if (el.parentNode && el.parentNode !== mount) el.remove();
    if (!el.parentNode) mount.insertBefore(el, bf && bf.parentNode === mount ? bf : mount.firstChild);
    var gt = el.querySelector('.sp-gt'); el.classList.remove('marq'); if (gt && gt.scrollWidth > gt.clientWidth + 2) el.classList.add('marq');
    return el;
  }

  /* ---------- load + cache ---------- */
  function cacheGet() { try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { return null; } }
  function cacheSet(c) { try { localStorage.setItem(KEY, JSON.stringify(c)); } catch (e) {} }
  function fetchCfg() {
    var C = window.SP_CONFIG || window.SITE || window.CRM_CONFIG || {}, u = String(C.SUPABASE_URL || '').replace(/\/+$/, ''), k = String(C.SUPABASE_KEY || '').trim();
    if (!u || !k) return Promise.resolve(null);
    var h = { 'Content-Type': 'application/json', apikey: k }; if (k.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + k;
    return fetch(u + '/rest/v1/rpc/sp_get_cfg', { method: 'POST', headers: h, body: '{}' }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
  }
  var CUR = null, CTX = {}, BOOTED = '';
  function pageCtx() { var f = (location.pathname.split('/').pop() || 'index.html'); return { page: /^shop\.html$/.test(f) ? 'shop' : (/^(index\.html)?$/.test(f) ? 'home' : 'inner') }; }
  function boot(app, o) {
    app = app || APP; o = o || {}; BOOTED = app; CTX = Object.assign(app === 'website' ? pageCtx() : {}, o.ctx || {});
    var c = cacheGet(); if (c) { CUR = c; apply(app, c); }
    var run = function () { if (CUR) greet(app, CUR, CTX); };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
    return new Promise(function (res) {
      var go = function () { fetchCfg().then(function (cfg) { if (cfg && typeof cfg === 'object') { CUR = cfg; cacheSet(cfg); apply(app, cfg); run(); } res(CUR); }); };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', go); else go();
    });
  }
  /* CRM / Admin re-draw their whole body — call again after each redraw (cheap, uses cache) */
  function again(ctx) { if (ctx) Object.assign(CTX, ctx); if (BOOTED && CUR) { apply(BOOTED, CUR); greet(BOOTED, CUR, CTX); } }
  function setCur(cfg) { CUR = cfg; cacheSet(cfg); again(); }
  window.SPLOOK = { boot: boot, again: again, apply: apply, greet: greet, derive: derive, presetOf: presetOf, css: css, PRESETS: PRESETS, ICONS: ICONS, ANIMS: ANIMS, STYLES: STYLES, hsl2hex: hsl2hex, hex2hsl: hex2hsl, shouldShow: shouldShow, bannerHtml: bannerHtml, styleOnce: styleOnce, fetch: fetchCfg, cur: function () { return CUR; }, setCur: setCur, esc: esc };
  if (APP) { var cc = cacheGet(); if (cc) { CUR = cc; apply(APP, cc); } if (APP === 'website' || APP === 'store' || APP === 'admin') boot(APP); }
})();
