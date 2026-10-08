/* Sunpowers website — interactions + enquiry form (no other data is loaded from outside) */
(function () {
  'use strict';
  var CFG = window.SITE || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var WA = String(CFG.WHATSAPP || '9621050636').replace(/\D/g, '').slice(-10);
  function waLink(text) { return 'https://wa.me/91' + WA + (text ? '?text=' + encodeURIComponent(text) : ''); }
  function money(n) { return '₹' + Math.round(n).toLocaleString('en-IN'); }
  function toast(msg) { var t = document.createElement('div'); t.className = 'toast'; t.setAttribute('role', 'status'); t.textContent = msg; document.body.appendChild(t); setTimeout(function () { t.remove(); }, 3200); }

  /* ---------- links from config ---------- */
  var SHOP = String(CFG.SHOP_URL || '').replace(/\/+$/, '');
  $$('[data-shop]').forEach(function (a) { if (SHOP) a.href = SHOP + (a.getAttribute('data-shop') || ''); });
  var LOGIN = String(CFG.LOGIN_URL || '').trim();
  $$('[data-login]').forEach(function (a) { if (LOGIN) { a.href = LOGIN; a.hidden = false; } else a.hidden = true; });
  var PW = String(CFG.POWERED_BY == null ? 'Powered by DigiDashLand' : CFG.POWERED_BY).trim(), PWU = String(CFG.POWERED_URL || '').trim();
  $$('[data-powered]').forEach(function (a) { if (!PW) { a.hidden = true; return; } a.textContent = PW; if (PWU) a.href = PWU; else a.removeAttribute('href'); a.hidden = false; });
  $$('[data-wa]').forEach(function (a) { a.href = waLink(a.getAttribute('data-wa')); a.target = '_blank'; a.rel = 'noopener'; });
  $$('[data-year]').forEach(function (e) { e.textContent = new Date().getFullYear(); });

  /* ---------- optional photos: show when the file exists, keep the drawn art when it doesn't ---------- */
  $$('img[data-photo]').forEach(function (img) {
    var host = img.closest('[data-photo-host]') || img.parentNode;
    function ok() { if (img.naturalWidth > 2) host.classList.add('has-photo'); else bad(); }
    function bad() { img.remove(); }
    if (img.complete) { if (img.naturalWidth > 2) host.classList.add('has-photo'); else if (img.naturalWidth === 0 && img.currentSrc) bad(); }
    img.addEventListener('load', ok); img.addEventListener('error', bad);
  });

  /* ---------- mobile drawer ---------- */
  var drawer = $('#drawer'), mbtn = $('#menuBtn');
  function setDrawer(open) {
    if (!drawer) return; drawer.classList.toggle('open', open); mbtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    drawer.setAttribute('aria-hidden', open ? 'false' : 'true'); document.documentElement.style.overflow = open ? 'hidden' : '';
    if (open) { var c = $('.close', drawer); if (c) c.focus(); } else if (mbtn) mbtn.focus();
  }
  if (mbtn) mbtn.addEventListener('click', function () { setDrawer(true); });
  if (drawer) drawer.addEventListener('click', function (e) { if (e.target.closest('.scrim,.close') || e.target.closest('a')) setDrawer(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && drawer && drawer.classList.contains('open')) setDrawer(false); });

  /* ---------- hero slider ---------- */
  (function () {
    var hero = $('#hero'); if (!hero) return;
    var slides = $$('.slide', hero), dots = $$('.dots button', hero), cur = 0, timer = null, DUR = 6500;
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    hero.style.setProperty('--dur', DUR + 'ms');
    function show(i) {
      i = (i + slides.length) % slides.length;
      slides.forEach(function (s, k) { s.classList.toggle('on', k === i); s.setAttribute('aria-hidden', k === i ? 'false' : 'true'); $$('a,button', s).forEach(function (el) { if (k === i) el.removeAttribute('tabindex'); else el.setAttribute('tabindex', '-1'); }); });
      dots.forEach(function (d, k) { d.classList.remove('on', 'done'); void d.offsetWidth; if (k < i) d.classList.add('done'); if (k === i) d.classList.add('on'); d.setAttribute('aria-current', k === i ? 'true' : 'false'); });
      cur = i; restart();
    }
    function restart() { clearTimeout(timer); if (reduce || hero.classList.contains('paused')) return; timer = setTimeout(function () { show(cur + 1); }, DUR); }
    function pause(p) { hero.classList.toggle('paused', p); if (p) clearTimeout(timer); else restart(); }
    dots.forEach(function (d, k) { d.addEventListener('click', function () { show(k); }); });
    $$('[data-go]', hero).forEach(function (b) { b.addEventListener('click', function () { show(cur + (+b.getAttribute('data-go'))); }); });
    var stage = $('.slides', hero);
    stage.addEventListener('mouseenter', function () { pause(true); }); stage.addEventListener('mouseleave', function () { pause(false); });
    hero.addEventListener('focusin', function (e) { if (e.target.closest('.qcard')) pause(true); });
    hero.addEventListener('focusout', function (e) { if (!hero.contains(e.relatedTarget)) pause(false); });
    document.addEventListener('visibilitychange', function () { pause(document.hidden); });
    var x0 = null;
    stage.addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; }, { passive: true });
    stage.addEventListener('touchend', function (e) { if (x0 === null) return; var dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 50 && !e.target.closest('.qcard')) show(cur + (dx < 0 ? 1 : -1)); x0 = null; });
    show(0);
  })();

  /* ---------- tabs ---------- */
  $$('[role=tablist]').forEach(function (tl) {
    var tabs = $$('[role=tab]', tl);
    function sel(t) { tabs.forEach(function (x) { var on = x === t; x.setAttribute('aria-selected', on ? 'true' : 'false'); x.tabIndex = on ? 0 : -1; var p = document.getElementById(x.getAttribute('aria-controls')); if (p) p.hidden = !on; }); }
    tabs.forEach(function (t, i) {
      t.addEventListener('click', function () { sel(t); });
      t.addEventListener('keydown', function (e) { var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0; if (d) { var n = tabs[(i + d + tabs.length) % tabs.length]; sel(n); n.focus(); } });
    });
  });

  /* ---------- reviews rail ---------- */
  $$('[data-rail]').forEach(function (nav) {
    var rail = document.getElementById(nav.getAttribute('data-rail'));
    $$('button', nav).forEach(function (b) { b.addEventListener('click', function () { var c = rail.firstElementChild; rail.scrollBy({ left: (+b.getAttribute('data-dir')) * ((c ? c.offsetWidth : 300) + 16), behavior: 'smooth' }); }); });
  });

  /* ---------- calculator ---------- */
  var CALC = { unitsPerKw: 135, rate: 8, sqftPerKw: 65, cost: { res: 58000, com: 52000, ind: 48000 } };
  function subsidy(kw, type) {
    if (type !== 'res' || kw < 1 || kw > 30) return 0;
    var central = kw <= 2 ? kw * 30000 : Math.min(78000, 60000 + (kw - 2) * 18000), state = Math.min(kw * 15000, 30000);
    return Math.min(108000, Math.round(central + state));
  }
  window.SPcalc = { subsidy: subsidy, CALC: CALC };
  (function () {
    var box = $('#calc'); if (!box) return;
    var bill = $('#cBill', box), rng = $('#cKw', box), out = $('#cKwV', box), LN = Math.log(2000);
    function kwFromR() { return Math.max(1, Math.round(Math.exp(+rng.value / 1000 * LN))); }
    function setKw(kw) { kw = Math.max(1, Math.min(2000, Math.round(kw))); rng.value = Math.round(Math.log(kw) / LN * 1000); return kw; }
    function type() { var r = $('input[name=ctype]:checked', box); return r ? r.value : 'res'; }
    function fmtKw(kw) { return kw >= 1000 ? (kw / 1000).toFixed(kw % 1000 ? 2 : 0) + ' MW' : kw + ' kW'; }
    function run(kw) {
      kw = kw || kwFromR(); var t = type(), units = kw * CALC.unitsPerKw, save = units * CALC.rate, year = save * 12, cost = kw * CALC.cost[t], sub = subsidy(kw, t), net = cost - sub, pay = year ? net / year : 0;
      out.textContent = fmtKw(kw); rng.setAttribute('aria-valuetext', fmtKw(kw));
      $('#oUnits').innerHTML = Math.round(units).toLocaleString('en-IN') + '<small>kWh</small>';
      $('#oSave').textContent = money(save); $('#oYear').textContent = money(year);
      $('#oPay').innerHTML = pay.toFixed(1) + '<small>saal</small>';
      $('#oArea').innerHTML = Math.round(kw * CALC.sqftPerKw).toLocaleString('en-IN') + '<small>sq ft</small>';
      $('#oCost').textContent = money(cost); $('#oSub').textContent = sub ? '− ' + money(sub) : '₹0'; $('#oNet').textContent = money(net);
      $('#oSubNote').textContent = t === 'res' ? (sub ? 'Subsidy (Kendra + UP Rajya) anumanit hai — asli rakam sarkari niyam ke hisab se.' : 'Subsidy sirf 1–30 kW Residential On-Grid / Hybrid par milti hai.') : 'Commercial / Industrial par sarkari subsidy nahi hai — tax me depreciation ka fayda (CA se confirm karein).';
      box.dataset.kw = kw; box.dataset.type = t;
    }
    bill.addEventListener('input', function () { var b = parseFloat(bill.value.replace(/[^\d.]/g, '')) || 0; if (b > 0) run(setKw(Math.ceil(b / CALC.rate / CALC.unitsPerKw))); });
    rng.addEventListener('input', function () { bill.value = ''; run(); });
    $$('input[name=ctype]', box).forEach(function (r) { r.addEventListener('change', function () { var dflt = { res: 5, com: 50, ind: 200 }[r.value]; if (!bill.value) run(setKw(dflt)); else run(); }); });
    var q = $('#cQuote'); if (q) q.addEventListener('click', function (e) {
      var f = $('#contact form[data-lead]'); if (!f) return; e.preventDefault();
      var kwEl = $('[name=kw]', f), billEl = $('[name=bill]', f), tyEl = $('[name=type]', f);
      if (kwEl) kwEl.value = box.dataset.kw; if (billEl && bill.value) billEl.value = bill.value.replace(/[^\d]/g, '');
      if (tyEl) tyEl.value = { res: 'Residential (Ghar)', com: 'Commercial (Dukaan / Office)', ind: 'Industrial (Factory)' }[box.dataset.type];
      document.getElementById('contact').scrollIntoView({ behavior: 'smooth' }); setTimeout(function () { var n = $('[name=name]', f); if (n) n.focus({ preventScroll: true }); }, 600);
    });
    var qw = $('#cWa'); if (qw) qw.addEventListener('click', function () { qw.href = waLink('Namaste, mujhe ' + out.textContent + ' solar ka quote chahiye' + (bill.value ? ' (bijli bill ₹' + bill.value + '/mahina)' : '')); });
    run(setKw(10));
  })();

  /* ---------- enquiry forms (saved in the same database as the Online Store → Admin → पूछताछ) ---------- */
  function digits(v) { var d = String(v || '').replace(/\D/g, ''); if (d.length === 12 && d.indexOf('91') === 0) d = d.slice(2); if (d.length === 11 && d[0] === '0') d = d.slice(1); return d; }
  async function submitEnquiry(data) {
    var url = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), key = String(CFG.SUPABASE_KEY || '').trim();
    if (!url || !key) throw new Error('config');
    var h = { apikey: key, 'Content-Type': 'application/json' }; if (key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + key;
    var ctrl = new AbortController(), tm = setTimeout(function () { ctrl.abort(); }, 15000);
    try {
      var r = await fetch(url + '/rest/v1/rpc/sp_submit_enquiry', { method: 'POST', headers: h, body: JSON.stringify({ p_data: data }), signal: ctrl.signal });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return true;
    } finally { clearTimeout(tm); }
  }
  $$('form[data-lead]').forEach(function (f) {
    var err = $('.ferr', f), btn = $('button[type=submit]', f), started = Date.now();
    $$('.inp', f).forEach(function (i) { i.addEventListener('input', function () { i.classList.remove('bad'); err.textContent = ''; }); });
    f.addEventListener('submit', async function (e) {
      e.preventDefault(); err.textContent = '';
      if ($('.hp input', f) && $('.hp input', f).value) return; // bots
      var o = {}; $$('input,select,textarea', f).forEach(function (el) { if (el.name && el.type !== 'checkbox' && !el.closest('.hp')) o[el.name] = el.value.trim(); });
      var bad = [];
      if (!o.name || o.name.length < 2) bad.push(['name', 'Apna naam likhein']);
      var ph = digits(o.phone); if (!/^[6-9]\d{9}$/.test(ph)) bad.push(['phone', 'Sahi 10 ank ka mobile number likhein']);
      var cons = $('input[name=consent]', f); if (cons && !cons.checked) bad.push(['consent', 'Call / WhatsApp ke liye sahmati par tick karein']);
      if (bad.length) { bad.forEach(function (b) { var el = $('[name=' + b[0] + ']', f); if (el) el.classList.add('bad'); }); err.textContent = bad[0][1]; var first = $('[name=' + bad[0][0] + ']', f); if (first) first.focus(); return; }
      if (Date.now() - started < 1500) { err.textContent = 'Ek second ruk kar dobara bhejein'; return; }
      var src = f.getAttribute('data-lead') || 'Website';
      var lines = [];
      if (o.bill) lines.push('Bijli bill: ₹' + o.bill.replace(/[^\d]/g, '') + '/mahina');
      if (o.kw) lines.push('Plant size: ' + o.kw + ' kW');
      if (o.message) lines.push(o.message);
      lines.push('Page: ' + (document.title.split('|')[0].trim() || location.pathname));
      var data = { name: o.name.slice(0, 80), phone: ph, city: (o.city || '').slice(0, 80), type: o.type || 'Solar enquiry', subject: '🌐 Website — ' + src, message: lines.join('\n').slice(0, 1500), source: 'website', bill: o.bill || '', kw: o.kw || '', page: location.pathname, lang: 'hinglish' };
      btn.disabled = true; var old = btn.innerHTML; btn.textContent = 'Bhej rahe hain…';
      var waText = 'Namaste Sunpowers, main ' + data.name + ' (' + ph + ')' + (data.city ? ', ' + data.city : '') + '. ' + data.type + '. ' + lines.slice(0, -1).join(', ');
      $$('.done [data-wa-done]', f).forEach(function (a) { a.href = waLink(waText); a.target = '_blank'; a.rel = 'noopener'; });
      try {
        await submitEnquiry(data);
        f.classList.add('sent'); var h = $('.done h3', f); if (h) h.textContent = 'Dhanyavaad ' + data.name.split(' ')[0] + ' ji!';
        try { if (window.gtag) window.gtag('event', 'generate_lead', { form: src }); if (window.fbq) window.fbq('track', 'Lead'); } catch (x) {}
      } catch (ex) {
        err.innerHTML = 'Form abhi nahi gaya (internet / server). <a href="' + waLink(waText) + '" target="_blank" rel="noopener">Yahan dabakar WhatsApp par bhejein</a> ya 0' + WA + ' par call karein.';
      }
      btn.disabled = false; btn.innerHTML = old;
    });
    var again = $('[data-again]', f); if (again) again.addEventListener('click', function () { f.reset(); f.classList.remove('sent'); started = Date.now(); });
  });
  window.SPsite = { digits: digits, toast: toast };
})();
