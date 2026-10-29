/* Shop page = Store app look (Round 31).
   Draws the Store-style pieces on the website Shop page: header details, footer, bottom bar, and the blocks
   (services, Blueprint card, Error-detector card, how-to-order, customer feedback, videos) that the Web Shop Page Builder places as rows.
   cart.js owns the data and calls these helpers; nothing here talks to the server. */
(function (root) {
  'use strict';
  var X = root.SHOPX = {};
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function safeUrl(u) { u = String(u || '').trim(); return /^(https?:\/\/|mailto:|tel:|\/|\.\/|[a-z0-9_-]+\.html)/i.test(u) ? u : (u && !/^[a-z]+:/i.test(u) ? 'https://' + u : ''); }
  function digits(s) { return String(s || '').replace(/\D/g, ''); }
  function ytId(u) { var m = String(u || '').match(/(?:youtu\.be\/|v=|embed\/|shorts\/)([\w-]{11})/); return m ? m[1] : ''; }
  function num(v) { v = Number(v); return isFinite(v) ? v : 0; }

  /* ---------- wishlist (this phone only) ---------- */
  X.wish = {
    get: function () { try { var a = JSON.parse(localStorage.getItem('sp_wwish') || '[]'); return Array.isArray(a) ? a : []; } catch (e) { return []; } },
    set: function (a) { try { localStorage.setItem('sp_wwish', JSON.stringify(a.slice(0, 200))); } catch (e) {} },
    has: function (id) { return X.wish.get().indexOf(id) >= 0; },
    toggle: function (id) { var a = X.wish.get(), i = a.indexOf(id); if (i >= 0) a.splice(i, 1); else a.unshift(id); X.wish.set(a); return i < 0; }
  };

  /* ---------- blocks placed by the builder ---------- */
  function flash(t) { return '<span class="sx-flash"><i></i>' + esc(t('live')) + '</span>'; }
  X.legacy = function (kind, S, t) {
    var st = (S && S.settings) || {};
    if (kind === 'services') {
      var v = S.services || {}, items = v.items || []; if (!items.length) return '';
      return (v.title ? '<div class="bh"><h2>' + esc(v.title) + '</h2></div>' : '') + '<div class="sx-svc">' + items.map(function (it) {
        return '<button type="button" class="sx-svc-c" style="--b:' + esc(/^#[0-9a-f]{3,8}$/i.test(it.bg || '') ? it.bg : '#e8f5e9') + '" data-sx-lt="' + esc(it.linkType || 'none') + '" data-sx-l="' + esc(it.link || '') + '" data-subj="' + esc(it.title) + '">' +
          '<span class="i">' + esc(it.icon || '⭐') + '</span><b>' + esc(it.title) + '</b><small>' + esc(it.sub) + '</small>' + (it.price ? '<em>' + esc(it.price) + '</em>' : '') + '</button>';
      }).join('') + '</div>';
    }
    if (kind === 'bp_card') return '<a class="sx-fcard fc-bp" href="blueprint.html">' + flash(t) + '<span class="fc-i">📐</span><span class="fc-t"><b>' + esc(t('bpT')) + '</b><small>' + esc(t('bpS')) + '</small></span><span class="fc-go">' + esc(t('open')) + ' ›</span></a>';
    if (kind === 'dt_card') return '<button type="button" class="sx-fcard fc-dt" data-doctor="">' + flash(t) + '<span class="fc-i">🔎</span><span class="fc-t"><b>' + esc(t('docT')) + '</b><small>' + esc(t('docS')) + '</small></span><span class="fc-go">' + esc(t('open')) + ' ›</span></button>';
    if (kind === 'howto') {
      var h = S.howto || {}, p = st.payments || {}, pl = p.upi && p.upi.enabled ? ['<div>📱 <b>' + esc(p.upi.label || 'UPI') + '</b><br><small>UPI ID: <b>' + esc(p.upi.upiId) + '</b></small></div>'] : [];
      if (!(h.steps || []).length) return '';
      return '<div class="card acc"><button type="button" class="acc-h" data-sx-acc aria-expanded="false"><span>🛍️ ' + esc(h.title) + '</span><span class="ar">⌄</span></button>' +
        '<div class="acc-b"><ol class="steps">' + (h.steps || []).map(function (s) { return '<li><span>' + esc(s) + '</span></li>'; }).join('') + '</ol>' +
        (pl.length ? '<div class="paybox"><b>' + esc(t('payModes')) + '</b>' + pl.map(function (x, i) { return '<div>' + (i + 1) + '. ' + x.replace(/^<div>|<\/div>$/g, '') + '</div>'; }).join('') + '</div>' : '') + '</div></div>';
    }
    if (kind === 'feedback') {
      var f = S.feedback || {}, its = (f.items || []).filter(function (x) { return x && x.text; }), gl = (st.social && st.social.gmb) || st.mapsLink, rl = st.reviewLink, sum = '';
      if (gl || rl || st.googleRating) {
        var r = num(st.googleRating), n = Math.round(num(st.googleReviews));
        sum = '<div class="revsum">' + (r ? '<span class="big">' + r.toFixed(1) + '</span><span class="st">' + '★★★★★'.slice(0, Math.round(r)) + '</span>' : '') + '<span class="grow">' + (n ? n + ' ' : '') + 'Google reviews</span>' +
          (gl ? '<a class="sx-btn out" style="padding:8px 12px" target="_blank" rel="noopener" href="' + esc(safeUrl(gl)) + '">' + esc(t('gAll')) + '</a>' : '') + (rl ? '<a class="sx-btn" style="padding:8px 12px" target="_blank" rel="noopener" href="' + esc(safeUrl(rl)) + '">⭐ ' + esc(t('gWrite')) + '</a>' : '') + '</div>';
      }
      if (!its.length) return sum ? '<div class="bh"><h2>💬 ' + esc(f.title) + '</h2></div>' + sum : '';
      var one = its.map(function (x) {
        var r2 = Math.max(1, Math.min(5, Math.round(num(x.rating) || 5)));
        return '<div class="fbc"><div class="st">' + '★★★★★'.slice(0, r2) + '<span style="color:#ddd">' + '★★★★★'.slice(r2) + '</span>' + (x.source === 'google' ? '<span class="gbadge">Google</span>' : '') + '</div><p>“' + esc(x.text) + '”</p><small>— ' + esc(x.name) + (x.city ? ', ' + esc(x.city) : '') + '</small></div>';
      }).join('');
      return '<div class="bh"><h2>💬 ' + esc(f.title) + '</h2></div>' + sum + '<div class="fbm"><div class="fbt" style="--d:' + Math.max(20, its.length * 8) + 's">' + one + one + '</div></div>';
    }
    if (kind === 'videos') {
      var vv = S.videos || {}, vi = vv.items || []; if (!vi.length) return '';
      var yt = st.social && st.social.youtube;
      return '<div class="bh"><h2>▶️ ' + esc(vv.title) + '</h2>' + (yt ? '<a class="va" href="' + esc(safeUrl(yt)) + '" target="_blank" rel="noopener">YouTube ↗</a>' : '') + '</div><div class="vids">' + vi.map(function (it) {
        var id = ytId(it.url);
        return '<div class="vd">' + (id ? '<div class="vd-f" data-sx-yt="' + id + '"><img src="https://i.ytimg.com/vi/' + id + '/hqdefault.jpg" alt="" loading="lazy" onerror="this.remove()"><span class="play">▶</span></div>' : '<div class="vd-f vd-ph">' + esc(t('soon')) + '</div>') + '<b>' + esc(it.title) + '</b></div>';
      }).join('') + '</div>';
    }
    return '';
  };

  /* ---------- categories page (bottom bar → Categories) ---------- */
  X.cats = function (S, cats, count, tt, title) {
    return '<div class="top"><button type="button" class="sx-back" data-sx-home aria-label="Back">←</button><h1>🗂️ ' + esc(title) + '</h1></div><div class="cats">' + cats.map(function (s) {
      return '<a class="cat" href="#" data-wc-sec="' + esc(s.id) + '"><span class="i">' + esc(s.icon || (s.kind === 'update' ? '🔥' : '📦')) + '</span><span><b>' + esc(tt(s)) + '</b><small>' + count(s) + '</small></span></a>';
    }).join('') + '</div>';
  };

  /* ---------- footer (same blocks as the Store footer) ---------- */
  var SOC = {
    Facebook: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M14 8V6.5c0-.8.2-1.3 1.4-1.3H17V2.2C16.7 2.1 15.7 2 14.6 2 12.2 2 10.6 3.4 10.6 6.1V8H8v3.2h2.6V22H14V11.2h2.6L17 8z"/></svg>',
    Instagram: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1" fill="currentColor"/></svg>',
    YouTube: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M21.6 7.2a2.6 2.6 0 0 0-1.8-1.8C18.2 5 12 5 12 5s-6.2 0-7.8.4A2.6 2.6 0 0 0 2.4 7.2 27 27 0 0 0 2 12a27 27 0 0 0 .4 4.8 2.6 2.6 0 0 0 1.8 1.8C5.8 19 12 19 12 19s6.2 0 7.8-.4a2.6 2.6 0 0 0 1.8-1.8A27 27 0 0 0 22 12a27 27 0 0 0-.4-4.8zM10 15V9l5.2 3z"/></svg>',
    Google: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/></svg>'
  };
  X.storeUrl = '';
  X.footer = function (S, t, tt, lang) {
    var st = (S && S.settings) || {}, so = st.social || {}, links = [['Facebook', so.facebook], ['Instagram', so.instagram], ['YouTube', so.youtube], ['Google', so.gmb]].filter(function (x) { return x[1]; });
    var cats = (S.sections || []).filter(function (s) { return s.visible !== false && s.kind !== 'update'; }).slice(0, 5), ph = digits(st.phone || st.whatsapp || ''), name = st.storeName || 'Sunpowers';
    var logo = /^(https?:\/\/|data:image\/|assets\/|\/)/i.test(st.logoImg || '') ? st.logoImg : 'assets/logo-mark.png';
    return '<div class="sx-wrap"><div class="pf-cta"><div><b>☀️ ' + esc(t('fCtaT')) + '</b><small>' + esc(t('fCtaS')) + '</small></div><div class="bt">' +
      (ph ? '<a class="pf-btn" href="tel:' + esc(ph) + '">📞 ' + esc(t('fCall')) + (st.phone ? ' · ' + esc(st.phone) : '') + '</a>' : '') + '</div></div>' +
      '<div class="pf-grid"><div><div class="pf-brand"><span><img src="' + esc(logo) + '" alt=""></span>' + esc(name) + '</div>' + (st.footerText ? '<p class="pf-about">' + esc(st.footerText) + '</p>' : '') +
      (links.length ? '<div class="pf-soc">' + links.map(function (l) { return '<a target="_blank" rel="noopener" aria-label="' + l[0] + '" href="' + esc(safeUrl(l[1])) + '">' + SOC[l[0]] + '</a>'; }).join('') + '</div>' : '') + '</div>' +
      '<div><h4>' + esc(t('fShop')) + '</h4><div class="pf-links">' + cats.map(function (c) { return '<a href="#" data-wc-sec="' + esc(c.id) + '">' + esc(tt(c)) + '</a>'; }).join('') + '</div></div>' +
      '<div><h4>' + esc(t('fHelp')) + '</h4><div class="pf-links"><a href="blueprint.html">' + esc(t('bpT')) + '</a><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="refund-policy.html">Refund</a><a href="shipping-policy.html">Shipping</a><a href="index.html">' + esc(t('mainSite')) + ' ↗</a>' + (X.storeUrl ? '<a href="' + esc(X.storeUrl) + '/?install=1" target="_blank" rel="noopener">📲 ' + esc(t('appInst').replace('📲 ', '')) + '</a>' : '') + '</div></div>' +
      '<div><h4>' + esc(t('fContact')) + '</h4><div class="pf-links">' + (st.email ? '<a href="mailto:' + esc(st.email) + '">✉️ ' + esc(st.email) + '</a>' : '') +
      (st.address ? '<span>📍 ' + esc(st.address) + '</span>' : '') + (st.hours ? '<span>🕘 ' + esc(lang === 'en' ? (st.hoursEn || st.hours) : st.hours) + '</span>' : '') + '</div></div></div></div>' +
      '<div class="pf-bot"><div class="sx-wrap"><span>© ' + new Date().getFullYear() + ' ' + esc(st.legalName || name) + (st.gstin ? ' • GSTIN: ' + esc(st.gstin) : '') + '</span></div></div>';
  };

  /* ---------- header / bottom bar details ---------- */
  X.chrome = function (o) {
    var S = o.S, t = o.t, st = (S && S.settings) || {}, $ = function (s) { return document.querySelector(s); };
    var nm = $('#sxName'); if (nm && st.storeName) nm.textContent = st.storeName;
    var lg = $('#sxLogo img'); if (lg && /^(https?:\/\/|data:image\/)/i.test(st.logoImg || '') && lg.getAttribute('data-set') !== st.logoImg) { lg.setAttribute('data-set', st.logoImg); lg.src = st.logoImg; }
    var loc = $('#sxLoc'); if (loc) loc.textContent = o.pinMsg;
    var q = $('#sxQ'); if (q) q.placeholder = t('search');
    var fab = $('#sxFab'); if (fab) { var w = digits(st.whatsapp || ''); if (w) { fab.href = 'https://wa.me/' + w + '?text=' + encodeURIComponent((o.lang === 'en' ? 'Hello ' : 'नमस्ते ') + (st.storeName || 'Sunpowers')); fab.classList.remove('hide'); } }
    [['home', 'nHome'], ['cats', 'nCats'], ['doc', 'nDoc'], ['wish', 'nWish'], ['cart', 'nCart'], ['help', 'nHelp']].forEach(function (p) { var e = document.querySelector('[data-sxt="' + p[0] + '"]'); if (e) e.textContent = t(p[1]); });
    document.querySelectorAll('[data-sx-tab]').forEach(function (a) { a.classList.toggle('on', a.getAttribute('data-sx-tab') === (o.tab || 'home')); });
    var ft = $('#sxFoot'); if (ft) { var sig = o.lang + '|' + JSON.stringify([st.storeName, st.phone, st.whatsapp, st.email, st.address, st.hours, st.social, (S.sections || []).length]); if (ft.getAttribute('data-sig') !== sig) { ft.setAttribute('data-sig', sig); ft.setAttribute('data-noi18n', ''); ft.innerHTML = X.footer(S, t, o.tt, o.lang); } }
    X.badges(o.cartN);
  };
  X.badges = function (n) {
    [['#sxBadge', n], ['#sxBadge2', n], ['#sxWishBadge', X.wish.get().length]].forEach(function (p) { var e = document.querySelector(p[0]); if (!e) return; e.textContent = p[1] > 99 ? '99+' : p[1]; e.classList.toggle('hide', !p[1]); });
  };
  X.openYt = function (box) {
    var id = box.getAttribute('data-sx-yt'); if (!id || box.querySelector('iframe')) return;
    box.innerHTML = '<iframe src="https://www.youtube-nocookie.com/embed/' + id + '?autoplay=1&rel=0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen title="video"></iframe>';
  };
})(window);
