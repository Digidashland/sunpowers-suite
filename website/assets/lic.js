/* =====================================================================
   lic.js — License lock (Website, Online Store, Admin, CRM)
   config.js me:  window.SP_LICENSE = { URL: '', KEY: '', ID: '' }
   URL ya ID khaali = koi check nahi (apni company ke liye).
   - Server "blocked / expired / galat domain" bole tabhi band hota hai.
   - Internet / server ki dikkat par band NAHI hota (30 din tak chhoot).
   ===================================================================== */
(function () {
  'use strict';
  var L = window.SP_LICENSE || {}, URL_ = String(L.URL || '').replace(/\/+$/, ''), KEY = String(L.KEY || ''), ID = String(L.ID || '').trim();
  var app = (document.currentScript && document.currentScript.getAttribute('data-app')) || 'website';
  var staff = app === 'admin' || app === 'crm';
  window.SPLicense = { app: app, state: 'off' };
  if (!URL_ || !ID || !KEY) return;
  var SK = 'sp_lic_' + app, GRACE = 30 * 864e5, BAD = { blocked: 1, expired: 1, invalid: 1, domain: 1, app: 1 };
  function get() { try { return JSON.parse(localStorage.getItem(SK) || '{}') || {}; } catch (e) { return {}; } }
  function put(o) { try { localStorage.setItem(SK, JSON.stringify(o)); } catch (e) {} }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
  function block(r) {
    window.SPLicense.state = r.status;
    var why = { expired: 'License ki avadhi khatam ho gayi hai', blocked: 'License band kar diya gaya hai', invalid: 'License sahi nahi hai', domain: 'Ye software is domain ke liye license nahi hai', app: 'Is app ka license nahi hai', offline: 'License check nahi ho paya (30 din se)' }[r.status] || 'License problem';
    var html = staff
      ? '<div style="font-size:44px">🔒</div><h1 style="font-size:22px;margin:10px 0 6px">' + esc(why) + '</h1><p style="color:#5b6b63;margin:0 0 6px">' + esc(r.msg || 'Kripya software developer se sampark karein.') + '</p>' + (r.until ? '<p style="color:#5b6b63;margin:0">Avadhi: ' + esc(r.until) + '</p>' : '') + '<p style="color:#9aa8a0;font-size:12px;margin-top:14px">Aapka data surakshit hai — license chalu hote hi sab wapas khul jayega.</p>'
      : '<div style="font-size:44px">🛠️</div><h1 style="font-size:22px;margin:10px 0 6px">Site abhi uplabdh nahi hai</h1><p style="color:#5b6b63;margin:0">' + esc(r.msg || 'Kripya thodi der baad dobara aayein.') + '</p>';
    function show() {
      var o = document.getElementById('spLicBlock');
      if (!o) { o = document.createElement('div'); o.id = 'spLicBlock'; o.setAttribute('role', 'alertdialog'); o.setAttribute('aria-modal', 'true'); o.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#f4f7f5;display:flex;align-items:center;justify-content:center;padding:24px;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;text-align:center;color:#0b2e1f'; document.documentElement.appendChild(o); }
      o.innerHTML = '<div style="max-width:420px">' + html + '</div>';
      document.documentElement.style.overflow = 'hidden';
    }
    if (document.body) show(); else document.addEventListener('DOMContentLoaded', show);
    clearInterval(window.SPLicense._keep); window.SPLicense._keep = setInterval(function () { if (document.body && !document.getElementById('spLicBlock')) show(); }, 700);
  }
  function unblock() { clearInterval(window.SPLicense._keep); var o = document.getElementById('spLicBlock'); if (o) { o.remove(); document.documentElement.style.overflow = ''; } }
  function warn(days) {
    if (!staff || days == null || days > 7) return;
    function show() { if (document.getElementById('spLicWarn')) return; var w = document.createElement('div'); w.id = 'spLicWarn'; w.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;z-index:2147483646;background:#fff7e6;border:1px solid #f0c36d;color:#7a4b00;border-radius:12px;padding:10px 40px 10px 14px;font:14px system-ui,sans-serif;box-shadow:0 6px 24px rgba(0,0,0,.12)'; w.innerHTML = '⏳ License ' + (days <= 0 ? 'aaj' : days + ' din me') + ' khatam ho raha hai — developer se renew karayein.<button aria-label="Band" style="position:absolute;right:8px;top:6px;border:0;background:none;font-size:20px;cursor:pointer">×</button>'; w.querySelector('button').onclick = function () { w.remove(); }; document.documentElement.appendChild(w); }
    if (document.body) show(); else document.addEventListener('DOMContentLoaded', show);
  }
  var c = get(), now = Date.now();
  if (c.status && BAD[c.status] && now - (c.at || 0) < 6 * 36e5) block(c);
  var ctl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctl) ctl.abort(); }, 8000);
  window.SPLicense.ready = fetch(URL_ + '/rest/v1/rpc/lic_check', {
    method: 'POST', signal: ctl ? ctl.signal : undefined,
    headers: KEY.indexOf('sb_') === 0 ? { 'Content-Type': 'application/json', apikey: KEY } : { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify({ p: { id: ID, app: app, host: location.hostname } })
  }).then(function (res) { if (!res.ok) throw new Error('http ' + res.status); return res.json(); }).then(function (r) {
    clearTimeout(tm); r = r || {};
    if (r.status === 'ok') { put({ status: 'ok', at: now, ok_at: now, until: r.until || null }); window.SPLicense.state = 'ok'; unblock(); warn(r.days_left); }
    else if (BAD[r.status]) { put({ status: r.status, at: now, ok_at: c.ok_at, until: r.until || null, msg: r.msg || '' }); block(r); }
    else throw new Error('bad reply');
  }).catch(function () {
    clearTimeout(tm);
    var first = c.fail_since || now; put({ status: c.status || 'unknown', at: c.at || 0, ok_at: c.ok_at, until: c.until, msg: c.msg, fail_since: first });
    var last = Math.max(c.ok_at || 0, first);
    if (c.status && BAD[c.status]) block(c);
    else if (now - last > GRACE) block({ status: 'offline' }); else window.SPLicense.state = 'grace';
  });
})();
