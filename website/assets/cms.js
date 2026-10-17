/* Sunpowers website — changes made in Admin → Website Admin (no code).
   Reads one public row from the database (sp_get_web) and applies: text, photos, store links, hero slides,
   menu, home sections, rating, social links and extra pages. If anything fails the normal page stays as it is. */
(function () {
  'use strict';
  var CFG = window.SITE || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function lang() { return window.SPI18N && (SPI18N.lang === 'hi' || SPI18N.lang === 'hg') ? 'hi' : 'en'; }
  function pick(o) { if (!o) return ''; if (typeof o === 'string') return o; var l = lang(), v = (o[l] || o.en || o.hi || ''); if (l === 'hi' && window.SPI18N && SPI18N.lang === 'hg' && SPI18N.xlit && /[\u0900-\u097F]/.test(v)) v = SPI18N.xlit(v); return v; }
  function https(u) { u = String(u || '').trim(); return /^(https:\/\/|http:\/\/(127\.0\.0\.1|localhost)[:\/])/i.test(u) ? u : ''; }
  var SHOP = String(CFG.SHOP_URL || '').replace(/\/+$/, ''), PHONE = String(CFG.WHATSAPP || '9621050636').replace(/\D/g, '').slice(-10);
  var KEY = 'sp_web_cache_v1', W = null;
  function safeHref(u) { u = String(u || '').trim(); if (!u) return ''; if (/^(https?:|tel:|mailto:)/i.test(u)) return u; if (/^[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w\-]*)?$/i.test(u) || /^page\.html\?s=[a-z0-9\-]+$/i.test(u)) return u; return ''; }
  function shopPath(u) { var m = /[?&]s=([^&#]+)/.exec(String(u || '')); return m ? 'shop.html#sec=' + m[1] : 'shop.html'; }
  function storeHref(u) { u = String(u || '').trim(); if (!u) return ''; if (/^https?:\/\//i.test(u)) return u; if (u.charAt(0) === '/') return shopPath(u); return ''; }

  /* ---------- text + photos ---------- */
  function applyText() {
    var t = W.text || {}; if (!Object.keys(t).length) return;
    $$('[data-cms]').forEach(function (el) {
      var o = t[el.getAttribute('data-cms')]; if (!o) return;
      var v = pick(o); if (!v) return;
      el.setAttribute('data-noi18n', ''); if (el.textContent !== v) el.textContent = v;
    });
  }
  function applyImgs() {
    var m = W.img || {};
    $$('img[data-cms-img]').forEach(function (img) {
      var u = https(m[img.getAttribute('data-cms-img')]); if (!u) return;
      if (img.getAttribute('src') !== u) { img.removeAttribute('srcset'); img.removeAttribute('loading'); img.style.display = ''; img.src = u; }
    });
  }
  function applyLogo() {
    var u = https((W.img || {}).logo); if (!u) return;
    $$('.brand img, .ftr .brand img, .drawer .brand img, #drawer .brand img').forEach(function (i) { if (i.getAttribute('src') !== u) { i.removeAttribute('srcset'); i.src = u; i.style.display = ''; } });
  }
  /* ---------- store links per page ---------- */
  function applyLinks() {
    var L = W.links || {};
    $$('a[data-slug]').forEach(function (a) {
      var u = storeHref(L[a.getAttribute('data-slug')] || L['*']); if (!u) return;
      a.removeAttribute('data-shop'); a.href = u;
    });
  }
  /* ---------- hero slides ---------- */
  function applyHero() {
    var hs = $('[data-hslider]'), S = W.slides; if (!hs || !Array.isArray(S) || !S.length) return;
    var tr = $('.hs-track', hs), dots = $('.hs-dots', hs); if (!tr || !dots) return;
    var arrow = '<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>';
    var html = '', n = 0;
    S.forEach(function (s) {
      if (s.hide) return; var title = pick(s.title), txt = pick(s.text), lab = pick(s.label) || 'Know more'; if (!title) return;
      var kind = s.kind || 'a', tg = String(s.target || '').trim(), btn = '';
      if (kind === 'book') btn = '<button type="button" class="btn btn-sun" data-book="' + esc(tg || 'Site survey') + '">' + esc(lab) + ' ' + arrow + '</button>';
      else if (kind === 'shop') { var su = storeHref(tg) || 'shop.html'; btn = '<a class="btn btn-sun" href="' + esc(su) + '">' + esc(lab) + ' ' + arrow + '</a>'; }
      else if (kind === 'wa') btn = '<a class="btn btn-wa" target="_blank" rel="noopener" href="https://wa.me/91' + PHONE + '?text=' + encodeURIComponent(tg || 'Namaste Sunpowers') + '">' + esc(lab) + '</a>';
      else { var h = safeHref(tg) || 'index.html'; btn = '<a class="btn btn-sun" href="' + esc(h) + '">' + esc(lab) + ' ' + arrow + '</a>'; }
      html += '<div class="hs" role="group" aria-roledescription="slide"><' + (n ? 'h2' : 'h1') + ' class="h1" data-noi18n>' + esc(title) + '</' + (n ? 'h2' : 'h1') + '><p class="lead" data-noi18n>' + esc(txt) + '</p><div class="btns">' + btn + '</div></div>';
      n++;
    });
    if (!n) return;
    tr.innerHTML = html; dots.innerHTML = new Array(n + 1).join('<button type="button"></button>');
    $$('.hs', tr).forEach(function (el, i) { el.setAttribute('aria-label', (i + 1) + ' / ' + n); });
    $$('.hs-dots button', hs).forEach(function (b, i) { b.setAttribute('aria-label', 'Slide ' + (i + 1)); });
    if (window.SPHeroInit) window.SPHeroInit();
  }
  /* ---------- menu ---------- */
  function applyMenu() {
    var M = W.menu || {}, hide = M.hide || [], add = M.add || [], names = M.names || {};
    $$('[data-cms-add]').forEach(function (e) { e.remove(); });
    function setLabel(a, v) { var tn = null; for (var i = 0; i < a.childNodes.length; i++) { var n = a.childNodes[i]; if (n.nodeType === 3 && n.nodeValue.trim()) { tn = n; break; } } if (tn) tn.nodeValue = v; else a.insertBefore(document.createTextNode(v), a.firstChild); }
    $$('.nav a, #drawer a.nl, .dsub a, .ddm a, .ftr a').forEach(function (a) {
      var h = a.getAttribute('href'), n = names[h], inFt = !!a.closest('.ftr');
      if (n && (n.en || n.hi) && !inFt && !a.hasAttribute('data-cms-add')) { var lab = pick(n); if (lab) { a.setAttribute('data-noi18n', ''); setLabel(a, lab); } }
      if (hide.indexOf(h) >= 0 && !inFt) { var host = a.closest('.dd') || a; host.style.display = 'none'; host.setAttribute('data-cms-hide', ''); }
    });
    var nav = $('.nav'), dr = $('#drawer .dnav, #drawer nav') || $('#drawer');
    add.forEach(function (it) {
      var h = safeHref(it.href), l = pick(it.label); if (!h || !l) return;
      if (nav) { var a = document.createElement('a'); a.href = h; a.textContent = l; a.setAttribute('data-cms-add', ''); a.setAttribute('data-noi18n', ''); nav.appendChild(a); }
      if (dr) { var d = document.createElement('a'); d.className = 'nl'; d.href = h; d.textContent = l; d.setAttribute('data-cms-add', ''); d.setAttribute('data-noi18n', ''); var last = $('a.nl:last-of-type', dr); if (last && last.parentNode) last.parentNode.insertBefore(d, last.nextSibling); else dr.appendChild(d); }
    });
  }
  /* ---------- blocks (used for extra pages and extra home sections) ---------- */
  function ytId(u) { u = String(u || '').trim(); var m = /(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)([\w-]{11})/.exec(u); return m ? m[1] : (/^[\w-]{11}$/.test(u) ? u : ''); }
  function fillMedia(root) {
    $$('.cms-xm', root || document).forEach(function (el) {
      if (el.firstChild) return; var urls = String(el.getAttribute('data-xu') || '').split('|').filter(Boolean);
      var n = mediaNode({ kind: el.getAttribute('data-xm') === 'video' ? 'video' : 'images', urls: urls }, ''); if (n) el.appendChild(n);
    });
  }
  function blocksHtml(blocks) {
    return (blocks || []).map(function (b) {
      var t = b.t;
      if (t === 'h') return '<h2 class="cms-h" data-noi18n>' + esc(pick(b)) + '</h2>';
      if (t === 'p') return '<p class="lead-p" data-noi18n>' + esc(pick(b)).replace(/\n/g, '<br>') + '</p>';
      if (t === 'list') return '<ul class="ticks">' + pick(b).split('\n').filter(Boolean).map(function (x) { return '<li><span data-noi18n>' + esc(x) + '</span></li>'; }).join('') + '</ul>';
      if (t === 'img') { var u = https(b.src); return u ? '<figure class="cms-img"><img src="' + esc(u) + '" alt="' + esc(pick(b.alt) || '') + '" loading="lazy"></figure>' : ''; }
      if (t === 'slides') { var us = (b.urls || []).map(https).filter(Boolean).slice(0, 8); return us.length ? '<div class="cms-bn-m cms-xm" data-xm="images" data-xu="' + esc(us.join('|')) + '"></div>' : ''; }
      if (t === 'video') { var vu = https((b.urls || [])[0] || b.url); return vu ? '<div class="cms-bn-m cms-xm" data-xm="video" data-xu="' + esc(vu) + '"></div>' : ''; }
      if (t === 'yt') { var yi = ytId(b.url); return yi ? '<div class="cms-bn-m cms-yt"><iframe src="https://www.youtube-nocookie.com/embed/' + yi + '" title="YouTube video" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></div>' : ''; }
      if (t === 'cards') return '<div class="why">' + (b.items || []).map(function (c) { var u = https(c.img); return '<div class="wcard">' + (u ? '<img src="' + esc(u) + '" alt="" loading="lazy" style="width:100%;border-radius:12px;margin-bottom:10px">' : '') + '<h3 data-noi18n>' + esc(pick(c.title)) + '</h3><p data-noi18n>' + esc(pick(c.text)) + '</p></div>'; }).join('') + '</div>';
      if (t === 'btn') {
        var lab = esc(pick(b.label) || 'Open'), k = b.kind || 'link', tg = String(b.target || '').trim();
        if (k === 'form') return '<p><button type="button" class="btn btn-leaf" data-book="' + esc(tg || 'Site survey') + '" data-noi18n>' + lab + '</button></p>';
        if (k === 'wa') return '<p><a class="btn btn-wa" target="_blank" rel="noopener" data-noi18n href="https://wa.me/91' + PHONE + '?text=' + encodeURIComponent(tg || 'Namaste Sunpowers') + '">' + lab + '</a></p>';
        if (k === 'store') { var su = storeHref(tg) || 'shop.html'; return '<p><a class="btn btn-sun" data-noi18n href="' + esc(su) + '">' + lab + '</a></p>'; }
        var h = safeHref(tg); return h ? '<p><a class="btn btn-sun" data-noi18n href="' + esc(h) + '">' + lab + '</a></p>' : '';
      }
      return '';
    }).join('');
  }
  /* ---------- extra page: page.html?s=slug ---------- */
  function applyPage() {
    var body = $('#cmsBody'); if (!body) return;
    var slug = ''; try { slug = new URLSearchParams(location.search).get('s') || ''; } catch (e) {}
    var pg = (W.pages || []).filter(function (p) { return p.slug === slug && !p.hide; })[0];
    if (!pg) { $('#cmsT').textContent = 'Page not found'; if ($('#cmsS')) $('#cmsS').textContent = ''; body.innerHTML = '<p><a class="btn btn-sun" href="index.html">Home</a></p>'; document.title = 'Page not found | Sunpowers'; return; }
    var t = pick(pg.title); document.title = t + ' | Sunpowers';
    var d = $('meta[name=description]'); if (d && pick(pg.desc)) d.setAttribute('content', pick(pg.desc));
    $('#cmsT').textContent = t; $('#cmsT').setAttribute('data-noi18n', ''); if ($('#cmsS')) { $('#cmsS').textContent = pick(pg.sub); $('#cmsS').setAttribute('data-noi18n', ''); } if ($('#cmsCrumb')) { $('#cmsCrumb').textContent = t; $('#cmsCrumb').setAttribute('data-noi18n', ''); };
    body.innerHTML = blocksHtml(pg.blocks) || ''; fillMedia(body);
  }
  /* ---------- home sections: hide / order / extra ---------- */
  function applyHome() {
    return; var H = W.home; if (!H || !$('#vhero')) return;
    var main = $('main') || document.body, secs = $$('main > section[id]').filter(function (s) { return s.id !== 'vhero'; });
    (H.hide || []).forEach(function (id) { var s = document.getElementById(id); if (s) s.style.display = 'none'; });
    (H.show || []).forEach(function (id) { var s = document.getElementById(id); if (s) s.style.display = ''; });
    if (Array.isArray(H.order) && H.order.length) {
      var ids = secs.map(function (s) { return s.id; }), want = H.order.filter(function (i) { return ids.indexOf(i) >= 0; });
      ids.forEach(function (i) { if (want.indexOf(i) < 0) want.push(i); });
      var marks = secs.map(function (s) { var c = document.createComment('s'); s.parentNode.insertBefore(c, s); return c; });
      secs.forEach(function (s) { s.parentNode.removeChild(s); });
      want.forEach(function (id, i) { var s = document.getElementById(id) || secs.filter(function (x) { return x.id === id; })[0]; marks[i].parentNode.insertBefore(s, marks[i]); });
      marks.forEach(function (c) { c.remove(); });
    }
    $$('[data-cms-extra]').forEach(function (e) { e.remove(); });
    (H.extra || []).forEach(function (x) {
      if (x.hide) return; var html = blocksHtml(x.blocks); if (!html) return;
      var s = document.createElement('section'); s.className = 'sec' + (x.dark ? ' dark' : ''); s.setAttribute('data-cms-extra', ''); s.innerHTML = '<div class="wrap">' + html + '</div>';
      var after = x.after && document.getElementById(x.after);
      if (after && after.parentNode) after.parentNode.insertBefore(s, after.nextSibling); else (main.querySelector('section:last-of-type') || main).insertAdjacentElement(main.querySelector('section') ? 'afterend' : 'beforeend', s);
    });
  }

  /* ---------- every page: sections (hide / order / delete / extra) + buttons (text / link / hide) ---------- */
  function pgFile() { return (location.pathname.split('/').pop() || 'index.html'); }
  function pgData(f) { if (f === 'index.html') return W.home || null; return (W.pg && W.pg[f.replace(/\.html$/, '')]) || null; }
  function secList(main) { return $$('section[data-sid]', main).filter(function (s) { return s.parentNode === main; }); }
  function applySecs() {
    var f = pgFile(), P = pgData(f), main = $('main'); if (!P || !main) return;
    $$('[data-cms-extra],[data-cms-dup]', main).forEach(function (e) { if (e.parentNode === main) e.parentNode.removeChild(e); });
    var secs = secList(main), by = {}; secs.forEach(function (s) { by[s.getAttribute('data-sid')] = s; });
    var anchor = {};
    /* copies of built-in sections (Duplicate in Website Builder): same look, own text / photos / buttons (keys get "<id>~" in front) */
    (P.dup || []).forEach(function (d) {
      var src = d && by[d.src]; if (!src || !d.id || by[d.id]) return;
      var c = src.cloneNode(true); c.setAttribute('data-sid', d.id); c.setAttribute('data-cms-dup', ''); c.removeAttribute('id'); c.style.display = '';
      $$('[id]', c).forEach(function (e) { e.removeAttribute('id'); });
      ['data-cms', 'data-cms-img', 'data-bid'].forEach(function (a) { $$('[' + a + ']', c).forEach(function (e) { e.setAttribute(a, d.id + '~' + e.getAttribute(a)); }); });
      $$('[data-banner]', c).forEach(function (e) { e.removeAttribute('data-banner'); });
      src.parentNode.insertBefore(c, src.nextSibling); by[d.id] = c; anchor[d.id] = d.src;
    });
    /* new sections (blocks) */
    (P.extra || []).forEach(function (x, i) {
      var html = blocksHtml(x.blocks); if (!html) return; var id = x.id || ('x' + (i + 1));
      var s = document.createElement('section'); s.className = 'sec' + (x.dark ? ' dark' : ''); s.setAttribute('data-cms-extra', ''); s.setAttribute('data-sid', id); s.innerHTML = '<div class="wrap">' + html + '</div>';
      fillMedia(s);
      var after = x.after && by[x.after];
      if (after && after.parentNode) after.parentNode.insertBefore(s, after.nextSibling); else main.appendChild(s);
      by[id] = s; if (x.after) anchor[id] = x.after;
    });
    secs = secList(main);
    var hide = (P.hide || []).concat(P.del || []);
    hide.forEach(function (id) { var s = by[id]; if (s) s.style.display = 'none'; });
    (P.extra || []).forEach(function (x, i) { if (x.hide) { var s = by[x.id || ('x' + (i + 1))]; if (s) s.style.display = 'none'; } });
    (P.show || []).forEach(function (id) { var s = by[id]; if (s && (P.del || []).indexOf(id) < 0) s.style.display = ''; });
    if (Array.isArray(P.order) && P.order.length && secs.length) {
      var ids = secs.map(function (s) { return s.getAttribute('data-sid'); }), want = P.order.filter(function (i) { return ids.indexOf(i) >= 0; });
      ids.forEach(function (i) { if (want.indexOf(i) >= 0) return; var p = anchor[i] ? want.indexOf(anchor[i]) : -1; if (p >= 0) want.splice(p + 1, 0, i); else want.push(i); });
      var marks = secs.map(function (s) { var c = document.createComment('s'); s.parentNode.insertBefore(c, s); return c; });
      secs.forEach(function (s) { s.parentNode.removeChild(s); });
      want.forEach(function (id, i) { marks[i].parentNode.insertBefore(by[id], marks[i]); });
      marks.forEach(function (c) { c.remove(); });
    }
    var B = P.btn || {};
    $$('[data-bid]', main).forEach(function (a) {
      var o = B[a.getAttribute('data-bid')]; if (!o) return;
      if (o.hide) { a.style.display = 'none'; return; }
      var tx = pick(o.text); if (tx) { var done = false; Array.prototype.slice.call(a.childNodes).forEach(function (n) { if (n.nodeType === 3 && n.nodeValue.trim()) { if (!done) { n.nodeValue = tx; done = true; } else n.nodeValue = ''; } }); if (!done) { var sp = a.querySelector('span:not([class*=ico])'); if (sp) sp.textContent = tx; else a.appendChild(document.createTextNode(tx)); } a.setAttribute('data-noi18n', ''); }
      var hr = String(o.href || '').trim(); if (hr && (/^(https?:\/\/|tel:|mailto:|#)/i.test(hr) || /^[a-z0-9\-_\/.]+\.html(\?[\w=&%\-.]*)?(#[\w-]+)?$/i.test(hr))) { a.setAttribute('href', hr); if (/^https?:/i.test(hr) && hr.indexOf(location.host) < 0) { a.setAttribute('target', '_blank'); a.setAttribute('rel', 'noopener'); } }
    });
  }
  /* ---------- rating, store info, social ---------- */
  function applySite() {
    var S = W.site || {}, r = S.rating || {};
    if (r.value) $$('[data-rating]').forEach(function (e) { e.textContent = r.value; });
    if (r.count) $$('[data-rcount]').forEach(function (e) { e.textContent = r.count; });
    if (https(r.url)) $$('a.gbadge').forEach(function (a) { a.href = r.url; });
    var si = pick(S.storeInfo);

    /* App button: 'Coming soon' until an app link is saved in Admin; then Android / iPhone get their own store, other devices get whichever exists */
    var ap = S.app || {}, au = https(ap.android), iu = https(ap.ios), ua = String(navigator.userAgent || ''), isIos = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1), alink = isIos ? (iu || au) : (au || iu);
    $$('a[data-app]').forEach(function (a) {
      var t = a.querySelector('[data-app-t]') || a, foot = !!a.closest('.ftr');
      if (alink) { a.href = alink; a.target = '_blank'; a.rel = 'noopener'; a.removeAttribute('aria-disabled'); a.removeAttribute('title'); a.classList.remove('is-soon'); t.textContent = pick({ en: foot ? 'Download App' : '📲 Download App', hi: foot ? 'ऐप डाउनलोड करें' : '📲 ऐप डाउनलोड करें' }); }
      else { a.removeAttribute('href'); a.removeAttribute('target'); a.setAttribute('aria-disabled', 'true'); a.setAttribute('title', pick({ en: 'Our app is coming soon', hi: 'हमारा ऐप जल्द आ रहा है' })); a.classList.add('is-soon'); t.textContent = pick({ en: foot ? 'Download App · Coming soon' : '📲 App · Coming soon', hi: foot ? 'ऐप डाउनलोड · जल्द आ रहा है' : '📲 ऐप · जल्द आ रहा है' }); }
      a.setAttribute('data-noi18n', ''); if (t !== a) t.setAttribute('data-noi18n', '');
    });
    $$('[data-storeinfo]').forEach(function (e) { if (si) { e.innerHTML = si.split('\n').filter(Boolean).map(function (x) { return '<p data-noi18n>' + esc(x) + '</p>'; }).join(''); e.hidden = false; } });
    var so = S.social || {}, map = { youtube: 'a[href*="youtube.com"],a[href*="youtu.be"]', instagram: 'a[href*="instagram.com"]', facebook: 'a[href*="facebook.com"]', gmb: 'a[href*="maps.app.goo.gl"],a[href*="google.com/maps"],a[href*="g.page"]' };
    Object.keys(map).forEach(function (k) { var u = https(so[k]); if (u) $$(map[k]).forEach(function (a) { if (!a.classList.contains('gbadge')) a.href = u; }); });
  }

  /* ---------- Round 8: card links / card media / page banners ---------- */
  function isVideo(u) { return /\.(mp4|webm)(\?|#|$)/i.test(u) || /res\.cloudinary\.com\/.+\/video\//i.test(u); }
  function slideshow(urls, alt) {
    var wrap = document.createElement('div'); wrap.className = 'cms-show';
    wrap.innerHTML = urls.map(function (u, i) { return '<img src="' + esc(u) + '" alt="' + esc(alt || '') + '" loading="' + (i ? 'lazy' : 'eager') + '"' + (i ? '' : ' class="on"') + '>'; }).join('') +
      (urls.length > 1 ? '<div class="cms-dots">' + urls.map(function (u, i) { return '<button type="button" aria-label="' + (i + 1) + '"' + (i ? '' : ' class="on"') + '></button>'; }).join('') + '</div>' : '');
    if (urls.length > 1) {
      var imgs = $$('img', wrap), dots = $$('.cms-dots button', wrap), cur = 0, t = null;
      var go = function (n) { cur = (n + imgs.length) % imgs.length; imgs.forEach(function (im, i) { im.classList.toggle('on', i === cur); }); dots.forEach(function (d, i) { d.classList.toggle('on', i === cur); }); };
      var run = function () { clearInterval(t); if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return; t = setInterval(function () { go(cur + 1); }, 4500); };
      dots.forEach(function (d, i) { d.onclick = function () { go(i); run(); }; });
      var x0 = null; wrap.addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; }, { passive: true });
      wrap.addEventListener('touchend', function (e) { if (x0 == null) return; var dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 40) { go(cur + (dx < 0 ? 1 : -1)); run(); } x0 = null; });
      run();
    }
    return wrap;
  }
  function mediaNode(m, alt) {
    if (!m) return null;
    var urls = (m.urls || []).map(https).filter(Boolean).slice(0, 5); if (!urls.length) return null;
    if (m.kind === 'video' || (urls.length === 1 && isVideo(urls[0]))) {
      var v = document.createElement('video'); v.src = urls[0]; v.muted = true; v.defaultMuted = true; v.loop = true; v.autoplay = true; v.playsInline = true; v.setAttribute('playsinline', ''); v.setAttribute('muted', ''); v.setAttribute('preload', 'metadata'); v.setAttribute('aria-label', alt || ''); v.className = 'cms-vid';
      v.addEventListener('click', function () { if (v.paused) v.play(); else v.pause(); });
      return v;
    }
    return slideshow(urls, alt);
  }
  function actionBtn(b, cls) {
    var lab = pick(b.label); if (!lab) return null;
    var k = b.kind || 'page', tg = String(b.target || '').trim(), el;
    if (k === 'form') { el = document.createElement('button'); el.type = 'button'; el.setAttribute('data-book', tg || 'Site survey'); }
    else {
      el = document.createElement('a');
      if (k === 'wa') { el.href = 'https://wa.me/91' + PHONE + '?text=' + encodeURIComponent(tg || 'Namaste Sunpowers'); el.target = '_blank'; el.rel = 'noopener'; }
      else if (k === 'call') { var num = tg.replace(/[^\d+]/g, ''); if (!num) return null; el.href = 'tel:' + num; }
      else if (k === 'store') { var su = storeHref(tg) || 'shop.html'; el.href = su; }
      else { var h = safeHref(tg); if (!h) return null; el.href = h; }
    }
    el.className = 'btn ' + (cls || 'btn-sun'); el.setAttribute('data-noi18n', ''); el.textContent = lab; return el;
  }
  function applyCards() {
    var C = W.cards; if (!C || typeof C !== 'object') return;
    $$('[data-card]').forEach(function (art) {
      var c = C[art.getAttribute('data-card')]; if (!c || typeof c !== 'object') return;
      var L = c.links || {};
      $$('a[data-cl]', art).forEach(function (a) {
        var raw = String(L[a.getAttribute('data-cl')] || '').trim();
        if (raw === '-') { a.hidden = true; return; }
        var u = safeHref(raw) || (/^\//.test(raw) ? storeHref(raw) : '');
        if (!u) return; a.href = u; a.removeAttribute('data-wa'); a.hidden = false;
        if (/^https?:/i.test(u) && u.indexOf(location.host) < 0) { a.target = '_blank'; a.rel = 'noopener'; } else { a.removeAttribute('target'); }
      });
      if (c.media && (art.classList.contains('pc2') || art.classList.contains('sys'))) {
        var n = mediaNode(c.media, $('h3', art) ? $('h3', art).textContent : ''); if (!n) return;
        if (art.classList.contains('sys')) {
          var sl = $('[data-sys-m]', art); if (sl) { sl.innerHTML = ''; sl.classList.remove('cms-m-def'); sl.removeAttribute('aria-hidden'); sl.appendChild(n); }
        } else {
          var old = $('.cms-m', art); if (old) old.remove();
          var box = document.createElement('div'); box.className = 'cms-m'; box.appendChild(n);
          var ib = $('.ib', art); if (ib) ib.hidden = true; var p = $('p', art); if (p) p.hidden = true;
          art.insertBefore(box, art.firstChild);
        }
      }
    });
  }
  function applyBanners() {
    var B = W.banners; $$('[data-banner]').forEach(function (sec) {
      var b = B && B[sec.getAttribute('data-banner')]; if (!b || typeof b !== 'object') return;
      if (b.hide) { sec.hidden = true; return; }
      var m = $('[data-bn-m]', sec), bt = $('[data-bn-b]', sec);
      var n = m ? mediaNode(b.media, document.title) : null; if (n) { m.innerHTML = ''; m.appendChild(n); }
      var made = []; (b.btns || []).slice(0, 2).forEach(function (x, i) { var e = actionBtn(x, i ? 'btn-line' : 'btn-sun'); if (e) made.push(e); });
      if (made.length && bt) { bt.innerHTML = ''; made.forEach(function (e) { bt.appendChild(e); }); }
      sec.hidden = false;
    });
  }
  function applyAll() {
    if (!W || typeof W !== 'object') return;
    try { applyHero(); applyMenu(); applyHome(); applySecs(); applyPage(); applyText(); applyImgs(); applyLogo(); applyLinks(); applyCards(); applyBanners(); applySite(); } catch (e) { if (window.console) console.warn('cms', e); }
    document.documentElement.setAttribute('data-cms', '1');
    try { document.dispatchEvent(new Event('sp-cms')); } catch (e) {}
  }
  function fetchWeb() {
    var url = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), key = String(CFG.SUPABASE_KEY || '').trim();
    if (!url || !key) return Promise.resolve(null);
    var h = { apikey: key, 'Content-Type': 'application/json' }; if (key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + key;
    var ctrl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctrl) ctrl.abort(); }, 12000);
    return fetch(url + '/rest/v1/rpc/sp_get_web', { method: 'POST', headers: h, body: '{}', signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) { clearTimeout(tm); if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (d) { return d && typeof d === 'object' && !Array.isArray(d) ? d : null; }).catch(function () { clearTimeout(tm); return null; });
  }
  /* Website Builder live preview: Admin opens this page inside an iframe with ?spprev=1 and sends the unsaved draft (postMessage).
     The draft is kept in this frame's own sessionStorage and the page reloads once so every section starts from the original HTML. Nothing is saved or sent anywhere. */
  var PV = false; try { PV = /[?&]spprev=1(&|$)/.test(location.search) && window.parent !== window; } catch (e) {}
  function bootPreview() {
    var cur = null; try { cur = JSON.parse(sessionStorage.getItem('sp_pv') || 'null'); } catch (e) {}
    if (cur && typeof cur === 'object') { W = cur; setTimeout(applyAll, 30); }
    window.addEventListener('message', function (e) {
      var d = e.data; if (e.source !== window.parent || !d || d.sp !== 'pv-data' || !d.data || typeof d.data !== 'object') return;
      var rev = String(d.rev || ''), had = ''; try { had = sessionStorage.getItem('sp_pv_rev') || ''; } catch (x) {}
      if (rev && rev === had) return;
      try { sessionStorage.setItem('sp_pv', JSON.stringify(d.data)); sessionStorage.setItem('sp_pv_rev', rev); } catch (x) { return; }
      location.reload();
    });
    document.addEventListener('sp-lang', function () { setTimeout(applyAll, 30); });
    try { window.parent.postMessage({ sp: 'pv-ready', h: document.documentElement.scrollHeight }, '*'); } catch (e) {}
  }
  function boot() {
    if (PV) return bootPreview();
    try { var c = JSON.parse(localStorage.getItem(KEY) || 'null'); if (c && typeof c === 'object') { W = c; setTimeout(applyAll, 30); } } catch (e) {}
    fetchWeb().then(function (d) {
      if (!d) { if (!W && $('#cmsBody')) { W = {}; applyAll(); } return; }
      W = d; try { localStorage.setItem(KEY, JSON.stringify(d)); } catch (e) {} applyAll();
    });
    document.addEventListener('sp-lang', function () { setTimeout(applyAll, 30); });
  }
  window.SPCMS = { apply: applyAll, data: function () { return W; } };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
