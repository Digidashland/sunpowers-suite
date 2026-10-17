/* Sunpowers — lightweight visit / click tracker (Round 15).
   Used by the Website and the Online Store. Stores NO personal data: only a random visitor id, the page,
   the label of the button that was tapped, and where the visitor came from. Admin dashboards read it.
   <script src="sp-track.js" data-site="website|store"></script>                                            */
(function () {
  'use strict';
  var me = document.currentScript, SITE = (me && me.getAttribute('data-site')) || 'website';
  if (window.SPTRK) return;
  var CFG = window.SP_CONFIG || window.SITE || {};
  var URL_ = String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''), KEY = String(CFG.SUPABASE_KEY || '').trim();
  function ls(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) {} return null; }
  function ss(k, v) { try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) {} return null; }
  var off = false;
  try { off = !!ls('sp_notrack') || (!ls('sp_trk_force') && (navigator.webdriver || /bot|crawl|spider|headless|lighthouse/i.test(navigator.userAgent || ''))); } catch (e) {}
  var sid = ls('sp_sid'); if (!sid) { sid = 'v' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4); ls('sp_sid', sid); }
  var Q = [], timer = null;

  function srcOf() {
    var s = ss('sp_src_s'); if (s) return s;
    var q = new URLSearchParams(location.search), u = (q.get('utm_source') || q.get('src') || '').toLowerCase().replace(/[^a-z0-9_.-]/g, '').slice(0, 30);
    if (!u) {
      var r = ''; try { r = document.referrer ? new URL(document.referrer).hostname.toLowerCase() : ''; } catch (e) {}
      if (!r || r === location.hostname) u = '';
      else if (/google\./.test(r)) u = 'google'; else if (/facebook\.|fb\.com|l\.facebook/.test(r)) u = 'facebook'; else if (/instagram\./.test(r)) u = 'instagram';
      else if (/youtube\.|youtu\.be/.test(r)) u = 'youtube'; else if (/wa\.me|whatsapp/.test(r)) u = 'whatsapp'; else if (/sunpowers\.in$/.test(r) && SITE === 'store') u = 'website'; else u = 'other';
    }
    // the store remembers "came from the website" for 7 days so the order can be credited to the website
    if (SITE === 'store') {
      if (u === 'website' || u === 'shop') ls('sp_src_store', JSON.stringify({ v: u, t: Date.now() }));
      else if (!u) { try { var o = JSON.parse(ls('sp_src_store') || 'null'); if (o && Date.now() - o.t < 7 * 864e5) u = o.v || 'website'; } catch (e) {} }
    }
    ss('sp_src_s', u || 'direct'); return u || 'direct';
  }
  function dev() { return (window.innerWidth || 1024) < 760 ? 'mobile' : 'desktop'; }
  function flush(sync) {
    if (!Q.length || !URL_ || !KEY) { Q = []; return; }
    var evs = Q.splice(0, 25), body = JSON.stringify({ p: { events: evs } }), h = { 'Content-Type': 'application/json', apikey: KEY };
    if (KEY.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + KEY;
    try { fetch(URL_ + '/rest/v1/rpc/sp_track', { method: 'POST', headers: h, body: body, keepalive: true }).catch(function () {}); } catch (e) {}
    if (Q.length) setTimeout(flush, 300);
  }
  function ev(kind, label, val, page) {
    if (off) return;
    Q.push({ site: SITE, kind: kind, page: page || pageName(), label: String(label || '').replace(/\s+/g, ' ').trim().slice(0, 60), sid: sid, src: srcOf(), dev: dev(), val: val || 0 });
    clearTimeout(timer); timer = setTimeout(flush, Q.length >= 8 ? 50 : 2500);
  }
  function pageName() {
    if (SITE === 'store') { var q = new URLSearchParams(location.search); return q.get('p') ? 'product/' + q.get('p') : q.get('s') ? 'section/' + q.get('s') : q.get('page') ? 'page/' + q.get('page') : (q.get('view') || 'home'); }
    var f = location.pathname.split('/').pop() || 'index.html'; return f || 'index.html';
  }
  var lastView = '';
  function view(p) { var n = p || pageName(); if (n === lastView) return; lastView = n; ev('view', '', 0, n); }
  function orderSrc() { try { var o = JSON.parse(ls('sp_src_store') || 'null'); return o && Date.now() - o.t < 7 * 864e5 ? (o.v || 'website') : ''; } catch (e) { return ''; } }
  window.SPTRK = { orderSrc: orderSrc, ev: ev, view: view, sid: sid, src: srcOf, flush: flush, site: SITE, off: off };

  // every button / link tap (label = its visible text)
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a,button,[role=button],[data-trk]') : null; if (!a) return;
    var l = a.getAttribute('data-trk') || a.getAttribute('aria-label') || a.textContent || a.title || '';
    l = l.replace(/\s+/g, ' ').trim(); if (!l || l.length < 2) return;
    if (a.closest('#sp-lm,.spg-ov,.sp-adm')) return;
    ev('click', l);
  }, true);
  // site search box
  var st = null;
  document.addEventListener('input', function (e) { var t = e.target; if (t && t.matches && t.matches('input[type=search],#schQ,#wcSearch,[data-trk-search]')) { clearTimeout(st); st = setTimeout(function () { if ((t.value || '').trim().length >= 3) ev('search', t.value); }, 1200); } }, true);
  // website → store hand-off: credit the visit / order to the website (the store reads ?src=website)
  if (SITE === 'website') {
    var SH = String((window.SITE && window.SITE.SHOP_URL) || '').replace(/\/+$/, '');
    var tag = function (e) {
      var a = e.target && e.target.closest ? e.target.closest('a[href]') : null; if (!a || !SH) return;
      var h = a.getAttribute('href') || ''; if (h.indexOf(SH) !== 0 || /[?&]src=/.test(h)) return;
      a.setAttribute('href', h + (h.indexOf('?') < 0 ? (/^https?:\/\/[^/]+$/.test(h) ? '/?' : '?') : '&') + 'src=' + (/shop\.html/.test(location.pathname) ? 'shop' : 'website'));
    };
    document.addEventListener('mousedown', tag, true); document.addEventListener('touchstart', tag, true); document.addEventListener('click', tag, true); document.addEventListener('keydown', function (e) { if (e.key === 'Enter') tag(e); }, true);
  }
  window.addEventListener('pagehide', function () { flush(true); });
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') flush(true); });
  if (SITE === 'website') { if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { view(); }); else view(); }
})();
