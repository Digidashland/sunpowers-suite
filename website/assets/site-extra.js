/* Sunpowers website — video hero, header search, site-visit popup, live booking buttons, live store offers */
(function () {
  'use strict';
  var CFG = window.SITE || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function lang() { return window.SPI18N && SPI18N.lang === 'hi' ? 'hi' : 'en'; }
  function T(s) { return window.SPI18N ? SPI18N.t(s) : s; }
  var SHOP = String(CFG.SHOP_URL || '').replace(/\/+$/, '');
  function ss(k, v) { try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) {} return null; }

  /* ---------- hero video: pause for reduced motion / data saver ---------- */
  (function () {
    var v = $('.vhero-v'); if (!v) return;
    var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    var save = navigator.connection && navigator.connection.saveData;
    if (reduce || save) { v.removeAttribute('autoplay'); try { v.pause(); } catch (e) {} v.removeAttribute('src'); $$('source', v).forEach(function (x) { x.remove(); }); try { v.load(); } catch (e) {} return; }
    v.muted = true; var p = v.play && v.play(); if (p && p.catch) p.catch(function () {});
    v.addEventListener('error', function () { v.style.display = 'none'; }, true);
    document.addEventListener('visibilitychange', function () { if (document.hidden) v.pause(); else { var q = v.play(); if (q && q.catch) q.catch(function () {}); } });
  })();

  /* ---------- calculator kW → Blueprint ---------- */
  (function () {
    var b = $('#cBp'), box = $('#calc'); if (!b || !box) return;
    b.addEventListener('click', function () { ss('sp_calc_kw', String(box.dataset.kw || '')); });
  })();

  /* ---------- store data (shared by search + offers) ---------- */
  var storeP = null;
  function loadStore() {
    if (storeP) return storeP;
    var url = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), key = String(CFG.SUPABASE_KEY || '').trim();
    if (!url || !key) return (storeP = Promise.resolve(null));
    var h = { apikey: key, 'Content-Type': 'application/json' }; if (key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + key;
    var ctrl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctrl) ctrl.abort(); }, 12000);
    storeP = fetch(url + '/rest/v1/rpc/sp_get_store', { method: 'POST', headers: h, body: '{}', signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (d) { clearTimeout(tm); return d && Array.isArray(d.products) ? d : null; })
      .catch(function () { clearTimeout(tm); return null; });
    return storeP;
  }
  function num(v) { v = parseFloat(v); return isFinite(v) ? v : 0; }
  function price(p) { return num(p.offer) > 0 ? num(p.offer) : num(p.mrp); }
  function money(n) { return '₹' + Math.round(n).toLocaleString('en-IN'); }
  function isImg(u) { return typeof u === 'string' && (/^https?:\/\//i.test(u) || /^data:image\/(png|jpe?g|webp|gif);/i.test(u)); }
  function ttl(o) { return (lang() === 'en' ? (o.titleEn || o.title) : (o.title || o.titleEn)) || ''; }
  function productsOf(d, sid) {
    return d.products.filter(function (p) { return p && Array.isArray(p.sections) && p.sections.indexOf(sid) >= 0 && p.visible !== false; })
      .sort(function (a, b) { return num(a.sort) - num(b.sort); });
  }


  /* ---------- website media set from Store Admin -> Website media (no code) ---------- */
  function httpsUrl(u) { return typeof u === 'string' && /^(https:\/\/|http:\/\/(127\.0\.0\.1|localhost)[:\/])/i.test(u.trim()) ? u.trim() : ''; }
  function applyMedia(d) {
    var m = d && d.site; if (!m || typeof m !== 'object') return;
    var vid = $('.vhero-v'), v = httpsUrl(m.video), pst = httpsUrl(m.poster);
    if (vid && pst) vid.setAttribute('poster', pst);
    if (vid && v) { var s = $('source', vid); if (s && s.getAttribute('src') !== v) { s.setAttribute('src', v); try { vid.load(); var pp = vid.play(); if (pp && pp.catch) pp.catch(function () {}); } catch (e) {} } }
    var im = m.img && typeof m.img === 'object' ? m.img : {};
    $$('img[data-photo]').forEach(function (img) {
      var k = (img.getAttribute('src') || '').split('/').pop().replace(/\.[a-z]+$/i, ''), u = httpsUrl(im[k]);
      if (u && img.getAttribute('data-src0') == null) { img.setAttribute('data-src0', img.getAttribute('src')); img.removeAttribute('loading'); img.src = u; }
    });
  }
  loadStore().then(function (d) { if (d) applyMedia(d); });
  /* ---------- live offers ("For Best offer Visit our store") ---------- */
  var box = $('[data-offers]'), OFFERS = null;
  function pickSections(d) {
    var secs = (d.sections || []).filter(function (s) { return s && s.visible !== false && productsOf(d, s.id).length; });
    var order = {}; (d.layout || []).forEach(function (b, i) { if (b && b.type === 'section') order[b.ref] = i; });
    secs.sort(function (a, b) { return (order[a.id] == null ? 999 : order[a.id]) - (order[b.id] == null ? 999 : order[b.id]); });
    var pref = secs.filter(function (s) { return /offer|best|sell|deal/i.test((s.title || '') + ' ' + (s.titleEn || '')); });
    var out = pref.slice(0, 2);
    secs.forEach(function (s) { if (out.length < 2 && out.indexOf(s) < 0) out.push(s); });
    return out;
  }
  function pcard(p) {
    var pr = price(p), mrp = num(p.mrp), off = mrp > pr && pr > 0 ? Math.round((1 - pr / mrp) * 100) : 0, img = isImg(p.image) ? p.image : (Array.isArray(p.images) && isImg(p.images[0]) ? p.images[0] : '');
    var href = 'shop.html#q=' + encodeURIComponent(String(ttl(p) || '').slice(0, 60));
    return '<a class="pcd" href="' + esc(href) + '" rel="noopener"><div class="pcd-i" style="' + (/^#[0-9a-f]{3,8}$/i.test(p.bg || '') ? 'background:' + p.bg : '') + '"><span aria-hidden="true">' + esc(p.emoji || '☀️') + '</span>' + (img ? '<img src="' + esc(img) + '" alt="" loading="lazy" decoding="async" onerror="this.remove()">' : '') + (off ? '<span class="pcd-o">' + off + '% OFF</span>' : '') + '</div><div class="pcd-b"><b>' + esc(ttl(p)) + '</b><span class="pcd-p">' + (off ? '<s>' + money(mrp) + '</s>' : '') + (pr ? money(pr) : '') + '</span></div></a>';
  }
  function renderOffers() {
    if (!box || !OFFERS) return;
    var d = OFFERS, secs = pickSections(d);
    if (!secs.length) return; /* keep the built-in cards */
    box.innerHTML = secs.map(function (s, i) {
      var list = productsOf(d, s.id).slice(0, Math.max(6, Math.min(20, num(s.limit) || 10)));
      return '<div class="ofr"><div class="ofr-h"><h3>' + esc((s.icon ? s.icon + ' ' : '') + ttl(s)) + '</h3><a href="' + esc('shop.html#sec=' + encodeURIComponent(s.id)) + '" rel="noopener">' + esc(T('View all')) + ' →</a></div><div class="ofr-w"><button type="button" class="ofr-a l" aria-label="Previous" data-ofr="-1">‹</button><div class="ofr-t" data-ofr-t="' + i + '">' + list.map(pcard).join('') + '</div><button type="button" class="ofr-a r" aria-label="Next" data-ofr="1">›</button></div></div>';
    }).join('');
    $$('.ofr-w', box).forEach(function (w) { var t = $('.ofr-t', w); w.classList.toggle('ns', t.scrollWidth <= t.clientWidth + 4); });
  }
  window.addEventListener('resize', function () { if (box && OFFERS) $$('.ofr-w', box).forEach(function (w) { var t = $('.ofr-t', w); w.classList.toggle('ns', t.scrollWidth <= t.clientWidth + 4); }); });
  if (box) {
    box.addEventListener('click', function (e) {
      var b = e.target.closest('[data-ofr]'); if (!b) return;
      var t = $('.ofr-t', b.closest('.ofr-w')); if (t) t.scrollBy({ left: (+b.getAttribute('data-ofr')) * (t.clientWidth * .8), behavior: 'smooth' });
    });
    loadStore().then(function (d) { OFFERS = d; if (d) renderOffers(); });
    document.addEventListener('sp-lang', renderOffers);
  }


  /* ---------- booking slider: auto + manual ---------- */
  (function () {
    var rail = $('[data-bkrail]'); if (!rail) return;
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches, hold = false, vis = true, tm = null;
    function step() { var c = rail.querySelector('.bk'); return c ? c.getBoundingClientRect().width + 16 : 300; }
    function go(dir) {
      var max = rail.scrollWidth - rail.clientWidth;
      if (dir > 0 && rail.scrollLeft >= max - 4) rail.scrollTo({ left: 0, behavior: 'smooth' });
      else if (dir < 0 && rail.scrollLeft <= 4) rail.scrollTo({ left: max, behavior: 'smooth' });
      else rail.scrollBy({ left: dir * step(), behavior: 'smooth' });
    }
    $$('[data-bka]').forEach(function (b) { b.addEventListener('click', function () { go(+b.getAttribute('data-bka')); holdFor(6000); }); });
    function holdFor(ms) { hold = true; clearTimeout(tm); tm = setTimeout(function () { hold = false; }, ms); }
    ['pointerdown', 'touchstart', 'wheel', 'focusin'].forEach(function (ev) { rail.addEventListener(ev, function () { holdFor(7000); }, { passive: true }); });
    rail.addEventListener('mouseenter', function () { hold = true; clearTimeout(tm); });
    rail.addEventListener('mouseleave', function () { holdFor(1500); });
    if ('IntersectionObserver' in window) new IntersectionObserver(function (es) { vis = es[0].isIntersecting; }, { threshold: .2 }).observe(rail);
    if (!reduce) setInterval(function () { if (!hold && vis && !document.hidden) go(1); }, 3400);
  })();
  /* ---------- site visit popup (customer may fill or close it) ---------- */
  var pop = $('#visitPop');
  if (pop) {
    var form = $('form', pop), last = null;
    var PROF = { 'Site survey': ['survey', 'Book site survey', ['Residential (Ghar)', 'Commercial (Dukaan / Office)', 'Industrial (Factory)', 'VFD (Aata Chakki / Pump)']],
      'Installation / shifting': ['install', 'Book installation', ['Residential (Ghar)', 'Commercial (Dukaan / Office)', 'Industrial (Factory)', 'VFD (Aata Chakki / Pump)']],
      'Solar panel cleaning': ['clean', 'Book cleaning', null],
      'Solar quote': ['quote', 'Get my quote', ['Residential (Ghar)', 'Commercial (Dukaan / Office)', 'Industrial (Factory)', 'VFD (Aata Chakki / Pump)']] };
    var subBtn = $('[data-sub]', form), subHtml = subBtn ? subBtn.innerHTML : '';
    function profile(svc) {
      var P = PROF[svc], key = P ? P[0] : 'default';
      $$('.field[data-p]', form).forEach(function (f) {
        var on = f.getAttribute('data-p').split(' ').indexOf(key) >= 0; f.hidden = !on;
        if (!on) $$('input,select,textarea', f).forEach(function (el) { el.value = ''; el.classList.remove('bad'); });
      });
      var sel = $('select[name=type]', form);
      if (sel) {
        $$('option', sel).forEach(function (o) { var okk = !P || !P[2] || P[2].indexOf(o.value || o.textContent) >= 0; o.hidden = !okk; o.disabled = !okk; });
        if (P && !P[2]) sel.value = 'Service / Maintenance'; else if (sel.selectedOptions[0] && sel.selectedOptions[0].disabled) sel.selectedIndex = Array.prototype.findIndex.call(sel.options, function (o) { return !o.disabled; });
      }
      if (subBtn) { if (P) { subBtn.textContent = T(P[1]); } else subBtn.innerHTML = subHtml; }
    }
    function openPop(svc, auto) {
      if (!pop.hidden) return; last = document.activeElement; pop.hidden = false; document.documentElement.style.overflow = 'hidden';
      if (form.classList.contains('sent')) { form.reset(); form.classList.remove('sent'); }
      profile(svc);
      var pf = window.SPPREFILL; window.SPPREFILL = null;
      if (pf && svc === 'Solar quote') { var kk = $('[name=kw]', form), bb = $('[name=bill]', form), tt = $('[name=type]', form); if (kk && pf.kw) kk.value = pf.kw; if (bb && pf.bill) bb.value = pf.bill; if (tt && pf.type) tt.value = pf.type; }
      var old = $('.vpop-svc', pop); if (old) old.remove();
      var msg = $('input[name=message]', form); if (msg) msg.remove();
      if (svc) {
        var tag = document.createElement('span'); tag.className = 'vpop-svc'; tag.textContent = svc; $('#vpopS', pop).before(tag);
        var m = document.createElement('input'); m.type = 'hidden'; m.name = 'message'; m.value = 'Service booking: ' + svc; form.appendChild(m);
      }
      var n = $('[name=name]', form); if (n && !auto) setTimeout(function () { try { n.focus({ preventScroll: true }); } catch (e) {} }, 60);
    }
    function closePop() { if (pop.hidden) return; pop.hidden = true; document.documentElement.style.overflow = ''; ss('sp_vpop', '1'); if (last && last.focus) try { last.focus(); } catch (e) {} }
    pop.addEventListener('click', function (e) { if (e.target === pop || e.target.closest('[data-vpop-close]')) closePop(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closePop(); });
    document.addEventListener('click', function (e) { var b = e.target.closest('[data-book]'); if (b) { e.preventDefault(); openPop(b.getAttribute('data-book')); } });
    var seen = ss('sp_vpop');
    if (!seen && document.getElementById('vhero')) setTimeout(function () { if (!ss('sp_vpop') && !document.querySelector('.spd-ov,.spg-ov,.sch:not([hidden])')) { ss('sp_vpop', '1'); openPop('', true); } }, 9000);
    var obs = new MutationObserver(function () { if (form.classList.contains('sent')) setTimeout(closePop, 2600); });
    obs.observe(form, { attributes: true, attributeFilter: ['class'] });
  }

  /* ---------- header search ---------- */
  var PAGES = [
    ['🏠', 'Home', 'index.html', 'home sunpowers solar lucknow'],
    ['🧮', 'Solar savings calculator', 'calculator.html', 'calculator bill saving kw subsidy cost payback'],
    ['🧼', 'Solar panel cleaning', 'solar-panel-cleaning.html', 'cleaning wash dust panel safai book'],
    ['🔧', 'Installation & shifting', 'installation-shifting.html', 'installation shifting relocate install book'],
    ['🛠️', 'Maintenance & Audit', 'solar-maintenance-audit.html', 'maintenance audit amc service package performance'],
    ['⚡', 'On-Grid solar', 'on-grid-solar.html', 'on grid net metering'],['🔋', 'Off-Grid solar', 'off-grid-solar.html', 'off grid battery'],['🔌', 'Hybrid solar', 'hybrid-solar.html', 'hybrid battery backup'],
    ['📐', 'Project Blue Print', 'blueprint.html', 'blueprint blue print roof map layout panel design plan'],
    ['🔎', 'Solar Error Detector', 'error-detector.html', 'error detector inverter fault code problem photo check'],
    ['🛒', 'Online Store', '#shop', 'store shop buy order panel inverter battery price offer'],
    ['☀️', 'Products & Services', 'services.html', 'residential commercial industrial vfd on-grid off-grid hybrid pump'],
    ['💰', 'Subsidy guide (PM Surya Ghar)', 'subsidy.html', 'subsidy pm surya ghar yojana 1.08 lakh kusum'],
    ['🏦', 'Finance, loan & EMI', 'finance.html', 'finance loan emi bank roi payback'],
    ['❓', 'FAQ', 'faq.html', 'faq question sawal jawab net metering warranty'],
    ['👷', 'Experts Cabin', 'experts.html', 'expert salah advice cabin pustika'],
    ['ℹ️', 'About Us', 'about.html', 'about company team akash suraj 2016'],
    ['📞', 'Contact & site visit', 'contact.html', 'contact call whatsapp address site visit quote form'],
    ['📄', 'Privacy Policy', 'privacy.html', 'privacy policy data'],
    ['📄', 'Terms & Conditions', 'terms.html', 'terms conditions'],
    ['📄', 'Refund & Cancellation', 'refund-policy.html', 'refund cancel return'],
    ['📄', 'Shipping & Delivery', 'shipping-policy.html', 'shipping delivery']
  ];
  var sch = null, inp = null, res = null;
  function build() {
    if (sch) return;
    sch = document.createElement('div'); sch.className = 'sch'; sch.hidden = true; sch.setAttribute('role', 'dialog'); sch.setAttribute('aria-modal', 'true'); sch.setAttribute('aria-label', 'Search');
    sch.innerHTML = '<div class="sch-b"><div class="sch-f"><svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg><input type="search" id="schQ" autocomplete="off" enterkeyhint="search" maxlength="60" placeholder="' + esc(T('Search pages, tools and store products')) + '"><button type="button" class="sch-x" aria-label="Close">×</button></div><div class="sch-r" id="schR"></div></div>';
    document.body.appendChild(sch); inp = $('#schQ', sch); res = $('#schR', sch);
    sch.addEventListener('click', function (e) { if (e.target === sch || e.target.closest('.sch-x')) closeS(); });
    inp.addEventListener('input', paint);
    inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') { var a = $('a,button.sr-i', res); if (a) a.click(); } });
    res.addEventListener('click', function (e) {
      var a = e.target.closest('[data-act]'); if (!a) return; e.preventDefault(); closeS();
      if (a.getAttribute('data-act') === 'doctor') { var d = document.createElement('button'); d.setAttribute('data-doctor', ''); d.hidden = true; document.body.appendChild(d); d.click(); d.remove(); }
    });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeS(); });
  }
  function openS() { build(); sch.hidden = false; document.documentElement.style.overflow = 'hidden'; inp.value = ''; paint(); setTimeout(function () { inp.focus(); }, 30); loadStore().then(function (d) { OFFERS = OFFERS || d; paint(); }); }
  function closeS() { if (!sch || sch.hidden) return; sch.hidden = true; document.documentElement.style.overflow = ''; }
  function paint() {
    var q = inp.value.trim().toLowerCase(), words = q.split(/\s+/).filter(Boolean), out = '';
    function hit(txt) { txt = txt.toLowerCase(); return words.every(function (w) { return txt.indexOf(w) >= 0; }); }
    var pg = PAGES.filter(function (p) { return !words.length || hit(p[1] + ' ' + p[3]); }).slice(0, words.length ? 8 : 7);
    if (pg.length) out += '<div class="sch-h">' + esc(T('Pages & tools')) + '</div>' + pg.map(function (p) {
      var href = p[2];
      if (href === '#shop') href = 'shop.html'; 
      return '<a href="' + esc(href) + '"><span class="e">' + p[0] + '</span><span><b>' + esc(T(p[1])) + '</b></span></a>';
    }).join('');
    if (words.length && OFFERS) {
      var pr = OFFERS.products.filter(function (p) { return p && p.visible !== false && hit((p.title || '') + ' ' + (p.titleEn || '') + ' ' + (p.brand || '') + ' ' + (p.sku || '') + ' ' + (p.tagline || '')); }).slice(0, 8);
      if (pr.length) out += '<div class="sch-h">' + esc(T('Store products')) + '</div>' + pr.map(function (p) {
        return '<a href="' + esc('shop.html#q=' + encodeURIComponent(String(ttl(p) || '').slice(0, 60))) + '"><span class="e">' + esc(p.emoji || '☀️') + '</span><span><b>' + esc(ttl(p)) + '</b><small>' + (price(p) ? money(price(p)) : '') + '</small></span></a>';
      }).join('');
    }
    res.innerHTML = out || '<div class="sch-n">' + esc(T('No results. Try another word.')) + '</div>';
  }
  document.addEventListener('click', function (e) { var b = e.target.closest('[data-site-search]'); if (b) { e.preventDefault(); var dr = $('#drawer'); if (dr && dr.classList.contains('open')) dr.classList.remove('open'); document.documentElement.style.overflow = ''; openS(); } });
})();

/* ---------- Round 7: hero slider, back button, dropdown ---------- */
(function () {
  var $ = function (s, r) { return (r || document).querySelector(s); }, $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var hs = $('[data-hslider]');
  if (hs) {
    var cur = 0, hold = false, tm = null, vis = true, x0 = null;
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var sd = navigator.connection && navigator.connection.saveData;
    var SL = function () { return $$('.hs', hs); }, DT = function () { return $$('.hs-dots button', hs); };
    var show = function (i) {
      var slides = SL(), dots = DT(); if (!slides.length) return;
      cur = (i + slides.length) % slides.length;
      slides.forEach(function (s, k) { var on = k === cur; s.classList.toggle('on', on); s.setAttribute('aria-hidden', on ? 'false' : 'true'); $$('a,button', s).forEach(function (x) { x.tabIndex = on ? 0 : -1; }); });
      dots.forEach(function (d, k) { if (k === cur) d.setAttribute('aria-current', 'true'); else d.removeAttribute('aria-current'); });
    };
    var holdFor = function (ms) { hold = true; clearTimeout(tm); tm = setTimeout(function () { hold = false; }, ms); };
    hs.addEventListener('click', function (e) {
      var a = e.target.closest('[data-hs]'); if (a) { show(cur + (+a.getAttribute('data-hs'))); holdFor(9000); return; }
      var d = e.target.closest('.hs-dots button'); if (d) { show(DT().indexOf(d)); holdFor(9000); }
    });
    hs.addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; hold = true; }, { passive: true });
    hs.addEventListener('touchend', function (e) { if (x0 !== null) { var dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 40) show(cur + (dx < 0 ? 1 : -1)); } x0 = null; holdFor(9000); }, { passive: true });
    hs.addEventListener('mouseenter', function () { hold = true; clearTimeout(tm); });
    hs.addEventListener('mouseleave', function () { holdFor(1200); });
    hs.addEventListener('focusin', function () { holdFor(9000); });
    if ('IntersectionObserver' in window) new IntersectionObserver(function (es) { vis = es[0].isIntersecting; }, { threshold: .2 }).observe(hs);
    window.SPHeroInit = function () { show(0); };
    show(0);
    if (!reduce && !sd) setInterval(function () { if (!hold && vis && !document.hidden) show(cur + 1); }, 5500);
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-back]'); if (!b) return;
    var same = false; try { same = document.referrer && new URL(document.referrer).origin === location.origin && history.length > 1; } catch (x) {}
    if (same) { e.preventDefault(); history.back(); }
  });
  $$('.dd').forEach(function (d) {
    var t = $('.dd-t', d); if (!t) return;
    t.addEventListener('click', function (e) {
      if (window.matchMedia && window.matchMedia('(hover: none)').matches && !d.classList.contains('open')) { e.preventDefault(); d.classList.add('open'); }
    });
    d.addEventListener('keydown', function (e) { if (e.key === 'Escape') d.classList.remove('open'); });
  });
  document.addEventListener('click', function (e) { $$('.dd.open').forEach(function (d) { if (!d.contains(e.target)) d.classList.remove('open'); }); });
  /* about page: rating + store info from the store settings (manual in admin) */
  window.SPCMS = window.SPCMS || {};

  /* ---------- header: collapse the utility line on scroll, centre the current quick-link ---------- */
  (function () {
    var h = $('.hdr'); if (!h) return;
    var on = false; function f() { var y = window.pageYOffset || document.documentElement.scrollTop || 0; if (!on && y > 40) { on = true; h.classList.add('sc'); } else if (on && y < 8) { on = false; h.classList.remove('sc'); } }
    window.addEventListener('scroll', f, { passive: true }); f();
    var cur = $('.hdr-strip a[aria-current=page]'), st = $('.hdr-strip');
    if (cur && st) { try { st.scrollLeft = Math.max(0, cur.offsetLeft - (st.clientWidth - cur.offsetWidth) / 2); } catch (e) {} }
  })();
})();
