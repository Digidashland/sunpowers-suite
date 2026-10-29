/* Sunpowers website: shared customer login (header Login/Logout + the tools gate).
   Once logged in the customer stays logged in until they press Logout (server session ~365 days, renewed on every visit). */
(function () {
  'use strict';
  var C = window.SITE || {};
  if (!window.SPGate) return;
  var KEY = 'sp_ctok', $$ = function (s) { return Array.prototype.slice.call(document.querySelectorAll(s)); };
  function rpc(fn, p) {
    var base = String(C.SUPABASE_URL || '').replace(/\/+$/, '');
    return fetch(base + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { apikey: C.SUPABASE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p: p }) })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok) throw new Error((j && j.message) || 'Request failed'); return j; }); });
  }
  function get() {
    var t = null; try { t = localStorage.getItem(KEY) || null; } catch (e) {}
    if (!t) { t = SPGate.cookie.get(); if (t) { try { localStorage.setItem(KEY, t); } catch (e) {} } }
    return t;
  }
  function set(t) { try { if (t) localStorage.setItem(KEY, t); else localStorage.removeItem(KEY); } catch (e) {} SPGate.cookie.set(t); paint(null); }
  var shop = String(C.SHOP_URL || '').replace(/\/+$/, ''), who = null;
  SPGate.init({ getToken: get, setToken: set, rpc: rpc, authUrl: 'assets/auth.js',
    lang: function () { return window.SPI18N && SPI18N.lang === 'hi' ? 'hi' : 'en'; },
    links: shop ? { store: shop, storeLabel: 'Go to store' } : {} });

  function paint(me) {
    who = me && me.name ? me : (get() ? who : null);
    var on = !!(who && get());
    $$('[data-hlogin]').forEach(function (b) {
      b.classList.toggle('on', on);
      var t = b.querySelector('[data-hl-t]'); if (t) t.textContent = on ? String(who.name || 'Account').split(' ')[0] : 'Login';
      b.setAttribute('aria-label', on ? 'Account' : 'Login');
    });
  }
  var menu = null;
  function closeMenu() { if (menu) { menu.remove(); menu = null; } }
  function openMenu(btn) {
    closeMenu(); var r = btn.getBoundingClientRect(); menu = document.createElement('div'); menu.className = 'hl-menu'; menu.setAttribute('data-noi18n', '');
    menu.innerHTML = '<b></b><small>Logged in</small><button type="button">Logout</button>'; menu.querySelector('b').textContent = who && who.name || 'Account';
    menu.style.top = (r.bottom + 6) + 'px'; menu.style.left = Math.max(8, Math.min(innerWidth - 226, r.right - 210)) + 'px'; document.body.appendChild(menu);
    menu.querySelector('button').onclick = function () { closeMenu(); SPGate.logout(); };
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-hlogin]');
    if (!b) { if (menu && !e.target.closest('.hl-menu')) closeMenu(); return; }
    e.preventDefault(); var dr = document.getElementById('drawer'); if (dr) dr.classList.remove('open'); document.documentElement.style.overflow = '';
    if (get() && who) { if (window.SPCART && SPCART.account) { SPCART.account(); return; } openMenu(b); return; }
    SPGate.require('login', function (me) { paint(me); });
  });
  document.addEventListener('sp-auth', function (e) { var m = e.detail && e.detail.me; if (m) { who = m; paint(m); SPGate.me().then(function (r) { if (r.me) paint(r.me); }); } else { who = null; paint(null); } });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeMenu(); });
  // on every page load: quietly confirm the saved login (extends the session) and show the name
  if (get()) SPGate.me().then(function (r) { if (r.me) paint(r.me); else if (!r.offline) paint(null); });
})();
/* My Plant section (customer Plant IDs) — right under the header */
document.addEventListener('DOMContentLoaded', function () {
  /* Round 50: Profile card sirf Shop page par (header ke logo-wali row ke neeche, search bar se pehle) */
  if (!window.SPPlant || !document.querySelector('header.sx-hdr .search')) return;
  var C = window.SITE || {};
  SPPlant.init({ getToken: function () { try { return localStorage.getItem('sp_ctok') || (window.SPGate && SPGate.cookie.get()) || null; } catch (e) { return null; } },
    rpc: function (fn, p) {
      var base = String(C.SUPABASE_URL || '').replace(/\/+$/, '');
      return fetch(base + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { apikey: C.SUPABASE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p: p }) })
        .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok) throw new Error((j && j.message) || 'Request failed'); return j; }); });
    },
    manual: true });
  if (window.SPCART && SPCART.plantSync) SPCART.plantSync();
});
