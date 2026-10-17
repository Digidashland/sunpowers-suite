/* Sunpowers website — Video guide sections.
   <div data-vguide="home|ongrid|offgrid|hybrid|vfd|subsidy|care|buy"> is filled here.
   Videos: the list the owner keeps in Store Admin -> Videos (sp_get_store.videos.items: {title,url}) is used when it has items;
   otherwise the dummy guides below are shown. Dummy / empty url = "Video coming soon" card (no external call).
   Playing: YouTube link -> privacy-friendly embed, .mp4/.webm/Cloudinary -> <video>, anything else -> opens the link. */
(function () {
  'use strict';
  var CFG = window.SITE || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function lang() { return window.SPI18N && (SPI18N.lang === 'hi' || SPI18N.lang === 'hg') ? 'hi' : 'en'; }
  function hg() { return !!(window.SPI18N && SPI18N.lang === 'hg' && SPI18N.xlit); }
  function X(v) { return hg() && /[\u0900-\u097F]/.test(v) ? SPI18N.xlit(v) : v; }
  // Sunpowers explainer videos (made for this site). Store Admin -> Videos replaces them when the owner adds his own links.
  var DUMMY = [
    { t: ['home'], en: 'Sunpowers: your complete solar partner', hi: 'सनपावर्स: आपका पूरा सोलर साथी', f: 'home' },
    { t: ['residential'], en: 'Solar for homes (3–30 kW)', hi: 'घर के लिए सोलर (3–30 kW)', f: 'residential' },
    { t: ['commercial'], en: 'Solar for shops, offices and schools', hi: 'दुकान, ऑफिस और स्कूल के लिए सोलर', f: 'commercial' },
    { t: ['industrial'], en: 'Solar for factories (100 kW – 2 MW)', hi: 'फैक्ट्री के लिए सोलर (100 kW – 2 MW)', f: 'industrial' },
    { t: ['ongrid'], en: 'How on-grid solar works', hi: 'ऑन-ग्रिड सोलर कैसे काम करता है', f: 'ongrid' },
    { t: ['offgrid'], en: 'Off-grid solar and batteries', hi: 'ऑफ-ग्रिड सोलर और बैटरी', f: 'offgrid' },
    { t: ['hybrid'], en: 'Hybrid solar: saving plus backup', hi: 'हाइब्रिड सोलर: बचत और बैकअप', f: 'hybrid' },
    { t: ['vfd'], en: 'Solar VFD for pumps and flour mills', hi: 'पंप और आटा चक्की के लिए सोलर VFD', f: 'vfd' },
    { t: ['subsidy'], en: 'PM Surya Ghar subsidy step by step', hi: 'पीएम सूर्य घर सब्सिडी स्टेप बाय स्टेप', f: 'subsidy' },
    { t: ['finance'], en: 'Loan, EMI and payback', hi: 'लोन, EMI और पैसा वापसी', f: 'finance' },
    { t: ['install'], en: 'Installation: survey to running plant', hi: 'इंस्टॉलेशन: सर्वे से चालू प्लांट तक', f: 'install' },
    { t: ['shifting'], en: 'Moving an existing solar plant', hi: 'पुराना सोलर प्लांट शिफ्ट करना', f: 'shifting' },
    { t: ['cleaning', 'care'], en: 'Panel cleaning and care', hi: 'पैनल की सफाई और देखभाल', f: 'cleaning' },
    { t: ['maintenance'], en: 'Solar maintenance and audit', hi: 'सोलर मेंटेनेंस और ऑडिट', f: 'maintenance' },
    { t: ['detector'], en: 'Understand your inverter error', hi: 'इन्वर्टर एरर का मतलब समझें', f: 'detector' },
    { t: ['blueprint'], en: 'Plan your roof with Blue Print', hi: 'ब्लू प्रिंट से अपनी छत का प्लान बनाएँ', f: 'blueprint' },
    { t: ['calculator'], en: 'How many kW of solar do you need?', hi: 'आपको कितने kW सोलर चाहिए?', f: 'calculator' },
    { t: ['buy'], en: 'How to order from our online store', hi: 'हमारे ऑनलाइन स्टोर से ऑर्डर कैसे करें', f: 'buy' },
    { t: ['support', 'experts'], en: 'Sunpowers hai to! Bharosa hai!', hi: 'सनपावर्स है तो! भरोसा है!', f: 'experts' },
    { t: ['myplant'], en: 'My Plant: see your plant with its Plant ID', hi: 'मेरा प्लांट: प्लांट आईडी से अपना प्लांट देखें', f: 'myplant' }
  ];
  function ytId(u) { var m = String(u || '').match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/))([\w-]{11})/); return m ? m[1] : ''; }
  function isFile(u) { return /\.(mp4|webm)(\?|#|$)/i.test(u) || /res\.cloudinary\.com\/.+\/video\//i.test(u); }
  function safe(u) { u = String(u || '').trim(); return /^https:\/\//i.test(u) ? u : ''; }
  var TXT = { soon: ['Video coming soon', 'वीडियो जल्द आ रहा है'], play: ['Play', 'चलाएँ'], title: ['Video guides', 'वीडियो गाइड'], sub: ['Short videos that explain solar in simple words.', 'छोटे वीडियो जो सोलर को आसान भाषा में समझाते हैं।'], close: ['Close', 'बंद करें'], wa: ['Ask us on WhatsApp', 'WhatsApp पर पूछें'] };
  function tt(k) { return X(TXT[k][lang() === 'hi' ? 1 : 0]); }
  var CSS = '.vg-one{width:100%;max-width:860px;margin:0 auto}.vg-play video{display:block;width:100%;aspect-ratio:16/9;border-radius:14px;background:#0b2e1f;box-shadow:0 8px 26px -14px rgba(0,0,0,.5)}.vg-sec{padding-block:18px}.vg-c{display:flex;flex-direction:column;gap:8px;min-width:0;background:none;border:0;padding:0;text-align:left;font:inherit;color:inherit;cursor:pointer}' +
    '.vg-f{position:relative;aspect-ratio:16/9;border-radius:14px;overflow:hidden;background:linear-gradient(135deg,#14231a,#1e8e3e);display:flex;align-items:center;justify-content:center;color:#fff}.vg-f img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}' +
    '.vg-p{position:relative;width:52px;height:52px;border-radius:50%;background:rgba(255,255,255,.92);color:#14231a;display:flex;align-items:center;justify-content:center;font-size:20px;box-shadow:0 4px 14px rgba(0,0,0,.3)}.vg-d{position:absolute;right:8px;bottom:8px;background:rgba(0,0,0,.65);color:#fff;font-size:12px;padding:2px 7px;border-radius:6px}' +
    '.vg-s{position:absolute;left:8px;top:8px;background:#f2a900;color:#14231a;font-size:11px;font-weight:700;padding:3px 8px;border-radius:999px}.vg-t{font-weight:700;font-size:14.5px;line-height:1.35;overflow-wrap:anywhere}' +
    '.vg-m{position:fixed;inset:0;z-index:95;background:rgba(0,0,0,.75);display:flex;align-items:center;justify-content:center;padding:16px}.vg-b{width:min(860px,100%);background:#000;border-radius:14px;overflow:hidden;position:relative}.vg-b iframe,.vg-b video{display:block;width:100%;aspect-ratio:16/9;border:0;background:#000}' +
    '.vg-x{position:absolute;top:6px;right:6px;z-index:2;background:rgba(255,255,255,.9);color:#14231a;border:0;border-radius:999px;width:34px;height:34px;font-size:18px;cursor:pointer}.vg-soon{aspect-ratio:16/9;display:flex;flex-direction:column;gap:10px;align-items:center;justify-content:center;color:#fff;text-align:center;padding:20px;background:linear-gradient(135deg,#14231a,#1e8e3e)}';
  (function () { var s = document.createElement('style'); s.textContent = CSS; document.head.appendChild(s); })();

  var STORE = null;
  function loadVideos() {
    var url = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), key = String(CFG.SUPABASE_KEY || '').trim();
    if (!url || !key) return Promise.resolve([]);
    try { var c = JSON.parse(sessionStorage.getItem('sp_wvid') || 'null'); if (c && Date.now() - c.at < 300000) return Promise.resolve(c.v); } catch (e) {}
    var h = { apikey: key, 'Content-Type': 'application/json' }; if (key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + key;
    var ctrl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctrl) ctrl.abort(); }, 10000);
    return fetch(url + '/rest/v1/rpc/sp_get_store', { method: 'POST', headers: h, body: '{}', signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) { if (!r.ok) throw new Error('x'); return r.json(); })
      .then(function (d) { clearTimeout(tm); var it = (d && d.videos && Array.isArray(d.videos.items) ? d.videos.items : []).filter(function (x) { return x && x.title; }).map(function (x) { return { title: String(x.title), url: safe(x.url) }; }).filter(function (x) { return x.url; }); try { sessionStorage.setItem('sp_wvid', JSON.stringify({ at: Date.now(), v: it })); } catch (e) {} return it; })
      .catch(function () { clearTimeout(tm); return []; });
  }
  function itemsFor(topic, real) {
    if (real.length) return real.map(function (x) { return { title: x.title, url: x.url, d: '' }; });
    var l = DUMMY.filter(function (v) { return v.t.indexOf(topic) >= 0; }); if (!l.length) l = DUMMY.slice(0, 4);
    return l.map(function (v) { return { title: X(lang() === 'hi' ? v.hi : v.en), url: v.url, d: v.d }; });
  }
  var SEQ = 0;
  function render(el, real) {
    var topic = el.getAttribute('data-vguide') || 'home', idx = parseInt(el.getAttribute('data-k'), 10) || 0, v;
    if (real.length) { var r = real[idx % real.length]; v = { title: r.title, url: r.url, d: '' }; }
    else { var l = DUMMY.filter(function (x) { return x.t.indexOf(topic) >= 0; }); if (!l.length) l = DUMMY; var d = l[idx % l.length]; v = { title: X(lang() === 'hi' ? d.hi : d.en), url: 'assets/video/' + d.f + '.mp4', poster: 'assets/video/' + d.f + '.jpg', d: '' }; }
    el._vg = [v];
    if (v.poster) { el.innerHTML = '<div class="vg-one vg-play"><video controls controlsList="nodownload noplaybackrate" disablePictureInPicture oncontextmenu="return false" playsinline preload="none" poster="' + esc(v.poster) + '" aria-label="' + esc(v.title) + '"><source src="' + esc(v.url) + '" type="video/mp4"></video></div>'; return; }
    var id = ytId(v.url), thumb = id ? 'https://i.ytimg.com/vi/' + id + '/hqdefault.jpg' : '';
    el.innerHTML = '<button type="button" class="vg-c vg-one" data-vg="0" aria-label="' + esc(v.title) + '"><span class="vg-f">' + (thumb ? '<img src="' + esc(thumb) + '" alt="" loading="lazy" onerror="this.remove()">' : '') + '<span class="vg-p" aria-hidden="true">▶</span></span></button>';
  }
  function open(v) {
    var m = document.createElement('div'); m.className = 'vg-m'; m.setAttribute('role', 'dialog'); m.setAttribute('aria-modal', 'true');
    var id = ytId(v.url), inner;
    if (id) inner = '<iframe src="https://www.youtube-nocookie.com/embed/' + id + '?autoplay=1&rel=0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen title="' + esc(v.title) + '"></iframe>';
    else if (v.url && isFile(v.url)) inner = '<video src="' + esc(v.url) + '" controls autoplay playsinline controlsList="nodownload" oncontextmenu="return false"></video>';
    else if (v.url) { window.open(v.url, '_blank', 'noopener'); return; }
    else { inner = '<div class="vg-soon"><div style="font-size:56px">▶</div></div>'; }
    m.innerHTML = '<div class="vg-b"><button type="button" class="vg-x" aria-label="' + esc(tt('close')) + '">✕</button>' + inner + '</div>';
    function close() { m.remove(); document.removeEventListener('keydown', key); }
    function key(e) { if (e.key === 'Escape') close(); }
    m.addEventListener('click', function (e) { if (e.target === m || e.target.className === 'vg-x') close(); }); document.addEventListener('keydown', key);
    document.body.appendChild(m);
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('[data-vg]') : null; if (!b) return;
    var host = b.closest('[data-vguide]'), v = host && host._vg && host._vg[parseInt(b.getAttribute('data-vg'), 10)]; if (v) open(v);
  });
  function boot() {
    var hosts = $$('[data-vguide]'); if (!hosts.length) return; hosts.forEach(function (h, i) { h.setAttribute('data-k', i); });
    hosts.forEach(function (h) { render(h, []); });
    loadVideos().then(function (real) { STORE = real; hosts.forEach(function (h) { render(h, real); }); });
    document.addEventListener('sp-lang', function () { setTimeout(function () { hosts.forEach(function (h) { render(h, STORE || []); }); }, 40); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
