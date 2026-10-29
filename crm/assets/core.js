/* Sunpowers CRM — core: data, session, permissions, layout, router, shared UI helpers.
   Every module lives in /modules/*.js and registers itself with CRM.mod(). */
(function () {
  'use strict';
  var CFG = window.CRM_CONFIG || {};
  var C = window.CRM = { cfg: CFG, mods: {}, routes: {}, me: null, cache: {} };

  /* ================================================================ small helpers */
  var $ = C.$ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = C.$$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var esc = C.esc = function (v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var num = C.num = function (v) { var n = parseFloat(String(v == null ? '' : v).replace(/[,₹\s]/g, '')); return isFinite(n) ? n : 0; };
  C.r2 = function (n) { return Math.round(num(n) * 100) / 100; };
  var money = C.money = function (n, dec) { n = C.r2(n); return '₹' + n.toLocaleString('en-IN', { minimumFractionDigits: dec ? 2 : (n % 1 ? 2 : 0), maximumFractionDigits: 2 }); };
  var pad = function (n) { return (n < 10 ? '0' : '') + n; };
  var iso = C.iso = function (d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); };
  var today = C.today = function () { return iso(new Date()); };
  C.addDays = function (s, n) { var d = C.pd(s) || new Date(); d.setDate(d.getDate() + n); return iso(d); };
  C.pd = function (s) { var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s || ''); return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null; };
  var fd = C.fd = function (s) { if (!s) return ''; var d = typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) ? C.pd(s) : new Date(s); return d && !isNaN(d) ? pad(d.getDate()) + '-' + pad(d.getMonth() + 1) + '-' + d.getFullYear() : ''; };
  C.fdt = function (s) { var d = new Date(s); if (isNaN(d)) return ''; var h = d.getHours(); return fd(d) + ' ' + ((h % 12) || 12) + ':' + pad(d.getMinutes()) + (h >= 12 ? ' PM' : ' AM'); };
  C.ago = function (s) { var d = (Date.now() - new Date(s).getTime()) / 1000; if (isNaN(d)) return ''; if (d < 60) return 'abhi'; if (d < 3600) return Math.floor(d / 60) + ' min pehle'; if (d < 86400) return Math.floor(d / 3600) + ' ghante pehle'; if (d < 172800) return 'kal'; return fd(s); };
  var mob = C.mob = function (v) { var d = String(v || '').replace(/\D/g, ''); if (d.length === 12 && d.indexOf('91') === 0) d = d.slice(2); if (d.length === 11 && d[0] === '0') d = d.slice(1); return d; };
  C.validMob = function (v) { return /^[6-9]\d{9}$/.test(mob(v)); };
  C.wa = function (m, text) { var d = mob(m); return 'https://wa.me/' + (d.length === 10 ? '91' + d : d) + (text ? '?text=' + encodeURIComponent(text) : ''); };
  C.tel = function (m) { return 'tel:+91' + mob(m); };
  C.initials = function (n) { return String(n || '?').trim().split(/\s+/).slice(0, 2).map(function (x) { return x[0]; }).join('').toUpperCase() || '?'; };
  C.debounce = function (fn, ms) { var t; return function () { var a = arguments, s = this; clearTimeout(t); t = setTimeout(function () { fn.apply(s, a); }, ms); }; };
  C.ls = function (k, v) { try { if (v === undefined) return JSON.parse(localStorage.getItem(k) || 'null'); if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, JSON.stringify(v)); } catch (e) { return null; } };
  C.lines = function (t) { return String(t || '').split('\n').map(function (x) { return x.trim(); }).filter(Boolean); };
  /* Round 63: item ki specification — ek hi jagah se padhna (Inventory, bill, online sab yahi use karte hain).
     specs = { 'Wattage (Wp)': '540', ..., _o: [label order, mukhya fields pehle], _n: mukhya fields ki ginti } */
  C.specPairs = function (sp) {
    if (!sp || typeof sp !== 'object') return [];
    var o = Array.isArray(sp._o) ? sp._o.filter(function (k) { return k in sp; }) : [], rest = Object.keys(sp).filter(function (k) { return k.charAt(0) !== '_' && o.indexOf(k) < 0; }).sort(), all = o.concat(rest), n = typeof sp._n === 'number' ? sp._n : 0;
    return all.map(function (k, i) { return [k, String(sp[k] == null ? '' : sp[k]).trim(), i < n]; }).filter(function (p) { return p[1] !== ''; });
  };
  C.specVal = function (k, v) {
    v = String(v == null ? '' : v).trim(); var m = /\(([^)]+)\)\s*$/.exec(k);
    if (m && /^[0-9.,\sx×*]+$/.test(v)) return m[1] === '%' ? v + '%' : v + ' ' + m[1];
    if (!m && /^[0-9.,]+$/.test(v)) return String(k).replace(/\s*\([^)]*\)\s*$/, '') + ': ' + v;
    return v;
  };
  C.warrantyText = function (w) { w = String(w == null ? '' : w).trim(); if (!w) return ''; if (/^[0-9.]+$/.test(w)) w += ' yrs'; return /warrant/i.test(w) ? w : w + ' warranty'; };
  /* bill ki chhoti line: Brand · Model · 2-3 mukhya specs · Warranty */
  C.specLine = function (d, max) {
    d = d || {}; var out = [], key = C.specPairs(d.specs).filter(function (p) { return p[2]; }).slice(0, max || 3);
    if (d.brand) out.push(String(d.brand).trim()); if (d.mpn) out.push(String(d.mpn).trim());
    key.forEach(function (p) { out.push(C.specVal(p[0], p[1])); });
    var w = C.warrantyText(d.warranty); if (w) out.push(w);
    return out.filter(Boolean).join(' · ');
  };
  C.clone = function (o) { return JSON.parse(JSON.stringify(o)); };

  /* ================================================================ icons */
  var P = {
    home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    today: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 15l2.5 2.5L16 13"/>',
    lead: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    quote: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h5"/>',
    bill: '<path d="M4 2v20l3-2 3 2 3-2 3 2 3-2 1 .7V2l-1 .7-3-2-3 2-3-2-3 2-3-2z"/><path d="M8 7h8M8 11h8M8 15h5"/>',
    box: '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.3 7 12 12l8.7-5M12 22V12"/>',
    plant: '<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M3 10h18M9 4v12M15 4v12M12 16v5M8 21h8"/>',
    rupee: '<path d="M6 3h12M6 8h12M6 13l8.5 8M6 13h3a5 5 0 0 0 0-10"/>',
    folder: '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>',
    cart: '<circle cx="9" cy="20" r="1.3"/><circle cx="18" cy="20" r="1.3"/><path d="M2 3h3l2.7 12.4a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.6L21 7H6"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    activity: '<path d="M12 8v4l3 3"/><path d="M3.05 11a9 9 0 1 1 .5 4M3 4v5h5"/>',
    search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    bell: '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0"/>',
    plus: '<path d="M12 5v14M5 12h14"/>', x: '<path d="M18 6 6 18M6 6l12 12"/>', menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    phone: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
    wa: '<path d="M21 11.5a8.4 8.4 0 0 1-12.4 7.4L3 21l2.1-5.4A8.4 8.4 0 1 1 21 11.5z"/><path d="M9 9.5c0 3 2.5 5.5 5.5 5.5"/>',
    mail: '<path d="M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"/><path d="m22 6-10 7L2 6"/>',
    check: '<path d="M20 6 9 17l-5-5"/>', trash: '<path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>',
    edit: '<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>', download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
    upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"/>', share: '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4"/>',
    eye: '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>', lock: '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
    right: '<path d="m9 18 6-6-6-6"/>', left: '<path d="m15 18-6-6 6-6"/>', star: '<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>',
    printer: '<path d="M6 9V2h12v7M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>', store: '<path d="M3 9l1-5h16l1 5M3 9h18v2a3 3 0 0 1-6 0 3 3 0 0 1-6 0 3 3 0 0 1-6 0zM5 13v8h14v-8"/>',
    globe: '<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15 15 0 0 1 0 20 15 15 0 0 1 0-20"/>', copy: '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
    clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>', alert: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.8 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
    dots: '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>', grid: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>',
    team: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M23 21v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/><path d="m16 11 2 2 4-4"/>',
    filter: '<path d="M22 3H2l8 9.46V19l4 2v-8.54z"/>', refresh: '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.9-3.4L23 10M1 14l4.6 4.4A9 9 0 0 0 20.5 15"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>', bolt: '<path d="M13 2 3 14h9l-1 8 10-12h-9z"/>',
    send: '<path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/>', key: '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/>',
    megaphone: '<path d="m3 11 18-5v12L3 14v-3zM11.6 16.8a3 3 0 1 1-5.8-1.6"/>'
  };
  C.ic = function (n, cls) { return '<svg class="ico' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" aria-hidden="true">' + (P[n] || P.dots) + '</svg>'; };
  C.LOGO = '<img src="assets/logo-mark-light.png" alt="" class="lg">';   /* for dark backgrounds */
  C.LOGO_D = '<img src="assets/logo-mark.png" alt="" class="lg">';        /* for light backgrounds */
  C.LOGO_FULL = function () { try { return new URL('assets/logo-full.png', location.href).href; } catch (e) { return 'assets/logo-full.png'; } };

  /* ================================================================ data access */
  function base() { return String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''); }
  function hdr(x) { var k = String(CFG.SUPABASE_KEY || '').trim(), h = { apikey: k, 'Content-Type': 'application/json' }; if (k.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + k; for (var i in x || {}) h[i] = x[i]; return h; }
  C.rpc = async function (fn, body) {
    var ctrl = new AbortController(), tm = setTimeout(function () { ctrl.abort(); }, 30000), res, txt;
    try { res = await fetch(base() + '/rest/v1/rpc/' + fn, { method: 'POST', headers: hdr(), body: JSON.stringify(body || {}), signal: ctrl.signal }); txt = await res.text(); }
    catch (e) { throw new Error('Internet / server se sampark nahi hua — dobara koshish karein'); }
    finally { clearTimeout(tm); }
    var j = null; try { j = txt ? JSON.parse(txt) : null; } catch (e) {}
    if (!res.ok) {
      var m = (j && (j.message || j.error)) || ('Server error ' + res.status);
      if (/Could not find the function|PGRST202/i.test(m)) m = 'Database setup baaki hai — crm-setup.sql Supabase me Run karein';
      if (/Login expired|active nahi/.test(m) && C.me && fn !== 'crm_login') { setTimeout(function () { C.logoutLocal(m); }, 10); }
      throw new Error(m);
    }
    return j;
  };
  C.call = function (fn, p) { var o = Object.assign({}, p || {}); o.token = C.token; return C.rpc(fn, { p: o }); };
  var busyN = 0;
  C.busy = function (on) { busyN = Math.max(0, busyN + (on ? 1 : -1)); document.documentElement.classList.toggle('busy', busyN > 0); };
  C.run = async function (fn, p, okMsg) { C.busy(true); try { var r = await C.call(fn, p); if (okMsg) C.toast(okMsg); return r; } catch (e) { C.toast(e.message, true); e.shown = true; throw e; } finally { C.busy(false); } };
  window.addEventListener('unhandledrejection', function (ev) { var r = ev.reason; ev.preventDefault(); if (r && r.message && !r.shown) C.toast(r.message, true); });
  C.list = function (kind, opt) { return C.call('crm_list', Object.assign({ kind: kind }, opt || {})); };
  C.get = function (id) { return C.call('crm_get', { id: id }); };
  C.save = function (kind, id, data, extra, msg) { return C.run('crm_save', Object.assign({ kind: kind, id: id || null, data: data }, extra || {}), msg === undefined ? 'Save ho gaya ✔' : msg); };
  C.setStatus = function (id, status, patch, msg) { return C.run('crm_status', { id: id, status: status, patch: patch || {} }, msg === undefined ? 'Update ho gaya ✔' : msg); };

  /* ================================================================ permissions + caches */
  C.can = function (k) { var p = (C.me && C.me.perms) || {}; return !!(p['*'] || p[k]); };
  C.isAdmin = function () { return C.can('*'); };
  C.canAny = function () { for (var i = 0; i < arguments.length; i++) if (C.can(arguments[i])) return true; return false; };
  C.isPartner = function () { return C.me && (C.me.role === 'dealer' || C.me.role === 'influencer'); };
  C.ROLE = { admin: 'Admin', manager: 'Manager', staff: 'Staff', dealer: 'Dealer', influencer: 'Influencer', consumer: 'Customer', marketing: 'Marketing', hr: 'HR' };
  C.settings = async function (force) { if (!C.cache.settings || force) C.cache.settings = await C.call('crm_settings_get', {}); return C.cache.settings; };
  C.company = function () { return ((C.cache.settings || {}).company) || {}; };
  C.users = async function (force) { if (!C.cache.users || force) { try { C.cache.users = await C.call('crm_users_list', {}); } catch (e) { C.cache.users = []; } } return C.cache.users; };
  C.userOpts = function (sel, blank, filter) { var us = (C.cache.users || []).filter(function (u) { return u.status === 'active' && u.role !== 'consumer' && (!filter || filter(u)); }); return (blank ? '<option value="">' + esc(blank) + '</option>' : '') + us.map(function (u) { return '<option value="' + u.id + '"' + (String(sel) === String(u.id) ? ' selected' : '') + '>' + esc(u.name) + ' — ' + esc(C.ROLE[u.role] || u.role) + '</option>'; }).join(''); };
  C.opts = function (list, sel, blank) { return (blank != null ? '<option value="">' + esc(blank) + '</option>' : '') + list.map(function (o) { var v = Array.isArray(o) ? o[0] : o, l = Array.isArray(o) ? o[1] : o; return '<option value="' + esc(v) + '"' + (String(sel) === String(v) ? ' selected' : '') + '>' + esc(l) + '</option>'; }).join(''); };

  /* ================================================================ UI: toast, modal, confirm, ask */
  C.toast = function (m, bad) { var w = $('#toasts'); if (!w) return; var t = document.createElement('div'); t.className = 'toast' + (bad ? ' bad' : ''); t.setAttribute('role', 'status'); t.textContent = m; w.appendChild(t); setTimeout(function () { t.remove(); }, bad ? 4500 : 2600); };
  C.modal = function (o) {
    var ov = document.createElement('div'); ov.className = 'ov'; ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-modal', 'true');
    ov.innerHTML = '<div class="md ' + (o.size || '') + '"><div class="mh"><h3>' + esc(o.title || '') + '</h3><button class="btn btn-g btn-icon" data-close aria-label="Band karein">' + C.ic('x') + '</button></div><div class="mb">' + (o.body || '') + '</div>' + (o.foot !== false ? '<div class="mf">' + (o.foot || '<button class="btn btn-o" data-close>Band karein</button>') + '</div>' : '') + '</div>';
    document.body.appendChild(ov); document.documentElement.style.overflow = 'hidden';
    var api = { el: ov, close: function () { ov.remove(); if (!$('.ov')) document.documentElement.style.overflow = ''; if (o.onClose) o.onClose(); } };
    ov.addEventListener('click', function (e) { if (e.target === ov || e.target.closest('[data-close]')) api.close(); });
    ov.addEventListener('keydown', function (e) { if (e.key === 'Escape') api.close(); });
    setTimeout(function () { var f = $('.mb input:not([type=hidden]):not([type=checkbox]):not([readonly]),.mb select,.mb textarea', ov); if (f && !o.noFocus && window.innerWidth > 900 && !ov.contains(document.activeElement)) try { f.focus(); } catch (e) {} }, 30);
    return api;
  };
  C.confirm = function (msg, okText, danger) {
    return new Promise(function (res) {
      var m = C.modal({ title: 'Pakka?', size: 'sm', body: '<p>' + esc(msg) + '</p>', foot: '<button class="btn btn-o" data-close>Nahi</button><button class="btn ' + (danger ? 'btn-r' : 'btn-p') + '" data-ok>' + esc(okText || 'Haan') + '</button>', onClose: function () { res(false); } });
      $('[data-ok]', m.el).onclick = function () { m.el.remove(); document.documentElement.style.overflow = ''; res(true); };
    });
  };
  C.ask = function (title, label, opt) {
    opt = opt || {};
    return new Promise(function (res) {
      var m = C.modal({ title: title, size: 'sm', body: '<div class="f"><label>' + esc(label) + '</label>' + (opt.area ? '<textarea class="inp" id="askv"></textarea>' : '<input class="inp" id="askv" value="' + esc(opt.value || '') + '">') + '</div>' + (opt.tpl && C.tplChips ? C.tplChips(opt.tpl, '#askv') : '') + (opt.hint ? '<p class="hint" style="margin-top:6px">' + esc(opt.hint) + '</p>' : ''), foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn ' + (opt.danger ? 'btn-r' : 'btn-p') + '" data-ok>' + esc(opt.ok || 'OK') + '</button>', onClose: function () { res(null); } });
      $('[data-ok]', m.el).onclick = function () { var v = $('#askv', m.el).value.trim(); if (opt.min && v.length < opt.min) { $('#askv', m.el).classList.add('bad'); return; } m.el.remove(); document.documentElement.style.overflow = ''; res(v); };
    });
  };
  C.delWithReason = async function (rec, label) {
    var needReason = ['party', 'quote', 'invoice', 'payment', 'plant', 'earning'].indexOf(rec.kind) >= 0, why = '';
    if (needReason) { why = await C.ask('Hatane ki wajah', (label || rec.title || '') + ' ko kyun hata rahe hain?', { min: 3, danger: true, ok: 'Hatao', tpl: 'delete', hint: 'Upar se chunein ya apni wajah likhein. Ye Activity record me rahegi.' }); if (why == null) return false; }
    else if (!(await C.confirm((label || rec.title || 'Ye record') + ' hatayein?', 'Hatao', true))) return false;
    try { await C.run('crm_delete', { id: rec.id, reason: why }, 'Hata diya'); return true; } catch (e) { return false; }
  };
  C.form = function (root) { var o = {}; $$('input,select,textarea', root).forEach(function (el) { if (!el.name) return; if (el.type === 'checkbox') o[el.name] = el.checked; else if (el.type === 'radio') { if (el.checked) o[el.name] = el.value; } else if (el.type !== 'file') o[el.name] = el.value.trim(); }); return o; };
  C.need = function (root, names) { var bad = null; names.forEach(function (n) { var el = $('[name="' + n + '"]', root); if (el && !String(el.value).trim()) { el.classList.add('bad'); bad = bad || el; } }); if (bad) { bad.focus(); C.toast('Laal wale khaane bharein', true); } return !bad; };
  C.f = function (label, html, cls) { return '<div class="f ' + (cls || '') + '"><label>' + label + '</label>' + html + '</div>'; };
  C.inp = function (name, val, attrs) { return '<input class="inp" name="' + name + '" value="' + esc(val == null ? '' : val) + '" ' + (attrs || '') + '>'; };
  C.ta = function (name, val, attrs) { return '<textarea class="inp" name="' + name + '" ' + (attrs || '') + '>' + esc(val || '') + '</textarea>'; };
  C.sel = function (name, list, val, blank, attrs) { return '<select class="inp" name="' + name + '" ' + (attrs || '') + '>' + C.opts(list, val, blank) + '</select>'; };
  C.empty = function (icon, title, sub, btn) { return '<div class="empty">' + C.ic(icon) + '<b>' + esc(title) + '</b>' + (sub ? '<p class="sm">' + esc(sub) + '</p>' : '') + (btn ? '<div style="margin-top:14px">' + btn + '</div>' : '') + '</div>'; };
  C.loading = function () { return '<div class="loading"><span class="spin"></span> Load ho raha hai…</div>'; };
  C.pill = function (t, cls) { return '<span class="pill ' + (cls || '') + '">' + esc(t) + '</span>'; };
  C.bind = function (root, map) { root.addEventListener('click', function (e) { var a = e.target.closest('[data-act]'); if (!a || !root.contains(a)) return; var f = map[a.getAttribute('data-act')]; if (f) { e.preventDefault(); f(a.getAttribute('data-id'), a, e); } }); };
  C.filterList = function (input, container, sel) { input.addEventListener('input', function () { var q = input.value.toLowerCase().trim(); $$(sel || '.li', container).forEach(function (li) { li.hidden = !!q && li.textContent.toLowerCase().indexOf(q) < 0; }); }); };

  /* ================================================================ files, share, print, pdf, excel */
  /* Photo chhoti karna: max = lambai side (px), q = quality, target = max bytes (optional — quality / size tab tak ghatate hain). Pehle se chhoti JPEG bada nahi karte. */
  C.compress = function (file, max, q, target) {
    return new Promise(function (res, rej) {
      if (!/^image\/(jpe?g|png|webp)/.test(file.type || '')) return res(file);
      var u = URL.createObjectURL(file), img = new Image();
      img.onerror = function () { URL.revokeObjectURL(u); rej(new Error('Photo padh nahi paye')); };
      img.onload = async function () {
        try {
          var w = img.naturalWidth, h = img.naturalHeight, s = Math.min(1, max / Math.max(w, h)), sc = 1, qq = q || 0.82, n = 0;
          var enc = function () { return new Promise(function (ok) { var c = document.createElement('canvas'); c.width = Math.max(1, Math.round(w * s * sc)); c.height = Math.max(1, Math.round(h * s * sc)); var x = c.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height); x.drawImage(img, 0, 0, c.width, c.height); c.toBlob(ok, 'image/jpeg', qq); }); };
          var b = await enc();
          while (target && b && b.size > target && n < 8 && Math.max(w, h) * s * sc > 480) { if (qq > 0.55) qq = Math.max(0.5, qq - 0.1); else sc *= 0.85; b = await enc(); n++; }
          URL.revokeObjectURL(u);
          if (!b) return rej(new Error('Photo process nahi hui'));
          if (s === 1 && sc === 1 && file.type === 'image/jpeg' && b.size >= file.size) return res(file);
          res(new File([b], (file.name || 'photo').replace(/\.\w+$/, '') + '.jpg', { type: 'image/jpeg' }));
        } catch (e) { URL.revokeObjectURL(u); rej(e); }
      };
      img.src = u;
    });
  };
  C.toB64 = function (blob) { return new Promise(function (res, rej) { var r = new FileReader(); r.onload = function () { res(String(r.result).split(',')[1] || ''); }; r.onerror = rej; r.readAsDataURL(blob); }); };
  C.toDataUrl = function (blob) { return new Promise(function (res, rej) { var r = new FileReader(); r.onload = function () { res(r.result); }; r.onerror = rej; r.readAsDataURL(blob); }); };
  C.fromB64 = function (b64, mime) { var s = atob(b64), u = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) u[i] = s.charCodeAt(i); return new Blob([u], { type: mime || 'application/octet-stream' }); };
  C.download = function (blob, name) { var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1500); };
  /* PDF ka public link: file Supabase storage me jati hai (CRM login se chhota token milta hai) */
  C.pdfLink = async function (blob, name) {
    var r = await C.call('crm_upload_token', {}), tk = (r && (r.token || r)) || '';
    if (!tk || typeof tk !== 'string') throw new Error('upload token nahi mila');
    var path = 'u/' + tk + '/' + Date.now() + '-' + String(name || 'doc.pdf').replace(/[^\w.\-]+/g, '-'), k = String(CFG.SUPABASE_KEY || '').trim(), h = { apikey: k, 'Content-Type': 'application/pdf', 'x-upsert': 'false' };
    if (k.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + k;
    var res = await fetch(base() + '/storage/v1/object/sp-images/' + path, { method: 'POST', headers: h, body: blob });
    if (!res.ok) throw new Error('upload ' + res.status);
    return base() + '/storage/v1/object/public/sp-images/' + path;
  };
  C.openWa = function (url) { var w = null; try { w = window.open(url, '_blank'); } catch (e) {} if (!w) location.href = url; };
  /* WhatsApp par seedha file na ja sake to: PDF download + link + poori details text me */
  C.share = async function (blob, name, text, phone) {
    var file = blob ? new File([blob], name, { type: blob.type || 'application/octet-stream' }) : null;
    try { if (file && navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], text: text || '' }); return 'shared'; } } catch (e) { if (e && e.name === 'AbortError') return 'cancel'; }
    var link = '';
    if (blob && /pdf/i.test(blob.type || name)) { try { link = await C.pdfLink(blob, name); } catch (e) { link = ''; } }
    if (blob) C.download(blob, name);
    var msg = (text || '') + (link ? '\n\n📄 PDF download karein:\n' + link : blob ? '\n\n(' + name + ' attach karein — file download ho gayi hai)' : '');
    C.openWa(C.wa(phone || '', msg));
    return link ? 'link' : 'fallback';
  };
  C.pdfSave = async function (html, name) {
    C.busy(true);
    try { var b = await C.pdfBlob(html, name); C.download(b, name); C.toast('PDF download ho gayi ✔'); return b; }
    catch (e) { C.toast('PDF nahi bani — Print → "Save as PDF" chunein', true); C.printHtml(html, name); return null; }
    finally { C.busy(false); }
  };
  C.printHtml = function (html, title) {
    var f = document.createElement('iframe'); f.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0'; document.body.appendChild(f);
    // "Powered by" patti har page ke neeche: tfoot har page par jagah chhodta hai, patti position:fixed se har page par chhapti hai
    if (html.indexOf('pstrip') >= 0) html = '<table style="width:100%;border-collapse:collapse"><tbody><tr><td style="padding:0">' + html + '</td></tr></tbody><tfoot><tr><td style="height:12mm;padding:0"></td></tr></tfoot></table>';
    var d = f.contentWindow.document; d.open(); d.write('<!doctype html><html><head><meta charset="utf-8"><title>' + esc(title || 'Print') + '</title><style>@page{size:A4;margin:10mm 8mm 8mm}</style></head><body style="margin:0">' + html + '</body></html>'); d.close();
    setTimeout(function () { try { f.contentWindow.focus(); f.contentWindow.print(); } catch (e) {} setTimeout(function () { f.remove(); }, 2000); }, 400);
  };
  C.loadScript = function (src) { return new Promise(function (res, rej) { if ($('script[src="' + src + '"]')) return res(); var s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = function () { s.remove(); rej(new Error('load')); }; document.head.appendChild(s); }); };
  C.pdfBlob = async function (html, name) {
    if (!window.html2pdf) { try { await C.loadScript('https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js'); } catch (e) { await C.loadScript('https://cdn.jsdelivr.net/npm/html2pdf.js@0.10.1/dist/html2pdf.bundle.min.js'); } }
    var box = document.createElement('div'); box.style.cssText = 'position:fixed;left:-10000px;top:0;width:794px;background:#fff'; box.innerHTML = html; document.body.appendChild(box);
    var pw = html.indexOf('pstrip') >= 0 ? C.powered() : null;
    try {
      var w = window.html2pdf().set({ margin: [8, 8, pw ? 16 : 10, 8], filename: name, image: { type: 'jpeg', quality: 0.95 }, html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff', windowWidth: 794, scrollX: 0, scrollY: 0 }, jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' }, pagebreak: { mode: ['css', 'legacy'] } }).from(box.querySelector('.bill') || box.querySelector('div') || box);
      if (pw && w.toPdf) w = w.toPdf().get('pdf').then(function (pdf) { C.pdfStrip(pdf, pw); });
      return await w.outputPdf('blob');
    }
    finally { box.remove(); }
  };
  /* har PDF page ke neeche hari patti + clickable "Powered by" link */
  C.powered = function () {
    var co = ((C.cache.settings || {}).company) || {}, t = co.powered == null ? 'Powered by: www.digidashland.in' : String(co.powered).trim();
    if (!t) return null;
    var m = /((https?:\/\/)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(\/\S*)?)/i.exec(t);
    return { text: t, url: m ? (/^https?:/i.test(m[1]) ? m[1] : 'https://' + m[1]) : 'https://www.digidashland.in' };
  };
  C.pdfStrip = function (pdf, pw) {
    try {
      var n = pdf.internal.getNumberOfPages(), W = pdf.internal.pageSize.getWidth(), H = pdf.internal.pageSize.getHeight();
      for (var i = 1; i <= n; i++) {
        pdf.setPage(i); pdf.setFillColor(30, 142, 62); pdf.rect(0, H - 9, W, 9, 'F');
        pdf.setTextColor(255, 255, 255); pdf.setFontSize(9); try { pdf.setFont('helvetica', 'bold'); } catch (e) {}
        var tw = pdf.getTextWidth(pw.text); pdf.textWithLink(pw.text, (W - tw) / 2, H - 3.4, { url: pw.url });
        if (n > 1) { pdf.setFontSize(8); try { pdf.setFont('helvetica', 'normal'); } catch (e) {} pdf.text(i + ' / ' + n, W - 8, H - 3.4, { align: 'right' }); }
      }
    } catch (e) { /* patti na bane to bhi PDF chale */ }
  };
  /* share a printable document as PDF (WhatsApp / any app); falls back to Print + WhatsApp text */
  C.sharePdf = async function (html, name, text, phone, meta) {
    /* Round 32: one "Send" sheet — 🔗 Send via Link (page with details + download) or 📎 Send from Local Storage (real PDF file) */
    if (window.SPSHARE) { SPSHARE.open(Object.assign({ html: html, name: name, text: text, phone: phone, title: name.replace(/\.pdf$/i, '') }, meta || {})); return 'sheet'; }
    C.busy(true); var blob = null;
    try { blob = await C.pdfBlob(html, name); } catch (e) { blob = null; } finally { C.busy(false); }
    if (blob) return C.share(blob, name, text, phone);
    C.toast('PDF ke liye Print → "Save as PDF" chunein', false); C.printHtml(html, name); C.openWa(C.wa(phone || '', text || '')); return 'print';
  };
  C.xl = async function (name, head, rows) { if (!window.XLSXLite) return C.toast('Excel tool load nahi hua', true); var fx = C.dlFilter ? await C.dlFilter(name, { head: head, rows: rows }) : { head: head, rows: rows }; if (!fx) return; head = fx.head; rows = fx.rows; C.download(window.XLSXLite.write([{ name: name, rows: [head].concat(rows), widths: head.map(function () { return 18; }) }]), name.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + today() + '.xlsx'); };
  C.readSheet = async function (file) {
    if (/\.csv$/i.test(file.name)) { var t = await file.text(); return C.csv(t); }
    var wb = await window.XLSXLite.read(await file.arrayBuffer()); return wb[Object.keys(wb)[0]] || [];
  };
  C.csv = function (t) { var rows = [], row = [], cur = '', q = false, i, c, first = t.split('\n')[0], sep = first.split(';').length > first.split(',').length ? ';' : ','; for (i = 0; i < t.length; i++) { c = t[i]; if (q) { if (c === '"' && t[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; } else if (c === '"') q = true; else if (c === sep) { row.push(cur); cur = ''; } else if (c === '\n' || c === '\r') { if (c === '\r' && t[i + 1] === '\n') i++; row.push(cur); rows.push(row); row = []; cur = ''; } else cur += c; } if (cur || row.length) { row.push(cur); rows.push(row); } return rows; };
  C.excelDate = function (v) { if (typeof v === 'number') return iso(new Date(Math.round((v - 25569) * 864e5) + new Date().getTimezoneOffset() * 6e4)); var s = String(v || '').trim(), m = /^(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{4})$/.exec(s); return m ? m[3] + '-' + pad(+m[2]) + '-' + pad(+m[1]) : /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : ''; };

  /* ================================================================ money in words (Indian) */
  var ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  var TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  function w2(n) { return n < 20 ? ONES[n] : TENS[Math.floor(n / 10)] + (n % 10 ? ' ' + ONES[n % 10] : ''); }
  function w3(n) { return n >= 100 ? ONES[Math.floor(n / 100)] + ' Hundred' + (n % 100 ? ' ' + w2(n % 100) : '') : w2(n); }
  C.words = function (amt) {
    amt = Math.round(num(amt) * 100) / 100; var r = Math.floor(amt), p = Math.round((amt - r) * 100), out = [];
    if (r === 0) out.push('Zero');
    var cr = Math.floor(r / 1e7); r %= 1e7; var la = Math.floor(r / 1e5); r %= 1e5; var th = Math.floor(r / 1e3); r %= 1e3;
    if (cr) out.push((cr > 999 ? C.words(cr).replace(/ Rupees.*$/, '') : w3(cr)) + ' Crore'); if (la) out.push(w2(la) + ' Lakh'); if (th) out.push(w2(th) + ' Thousand'); if (r) out.push(w3(r));
    return out.join(' ') + ' Rupees' + (p ? ' and ' + w2(p) + ' Paise' : '') + ' Only';
  };

  /* ================================================================ printable bill (quotation / invoice / purchase) */
  C.BILL_CSS = '.bill{font-family:Arial,Helvetica,sans-serif;color:#1c2a21;font-size:12.5px;padding:6px;background:#fff}.bill table{width:100%;border-collapse:collapse}.bill .hd td{vertical-align:top}.bill .hdw{border-bottom:3px solid #1e8e3e;padding-bottom:10px;margin-bottom:12px}.bill h1{margin:0 0 4px;font-size:21px;color:#0b2e1f}.bill .ttl{font-size:19px;font-weight:700;color:#1e8e3e;text-align:right;letter-spacing:.04em}.bill .sm{font-size:11.5px;color:#3d4b42;line-height:1.5}.bill .box{border:1px solid #d7e3d5;padding:8px 10px;border-radius:4px;vertical-align:top}.bill .box b.h{display:block;color:#1e8e3e;font-size:10.5px;text-transform:uppercase;letter-spacing:.06em;margin-bottom:3px}.bill .it th{background:#0b2e1f;color:#fff;padding:7px;font-size:11.5px;text-align:left}.bill .it td{border:1px solid #d7e3d5;padding:7px;vertical-align:top}.bill .r{text-align:right}.bill .tot td{padding:4px 8px}.bill .gt td{font-weight:700;font-size:15px;background:#e7f3e9;border-top:2px solid #1e8e3e}.bill .words{margin:10px 0;padding:8px 10px;background:#f4f9f3;border-left:4px solid #1e8e3e}.bill h4{margin:14px 0 5px;color:#0b2e1f;font-size:13px}.bill .ph th{background:#e7f3e9;padding:6px;font-size:11.5px;text-align:left;border:1px solid #d7e3d5}.bill .ph td{border:1px solid #d7e3d5;padding:6px}.bill .det{font-size:11px;color:#4d5b52;margin-top:3px;line-height:1.45}.bill .spt{width:auto;margin-top:4px}.bill .spt td{border:0;border-bottom:1px dotted #d7e3d5;padding:1px 10px 1px 0;font-size:10.5px;color:#4d5b52}.bill .spt td:first-child{color:#2c3a31;white-space:nowrap}.bill .ttl2{font-weight:700;color:#15702f;font-size:11px;margin-bottom:2px;text-transform:uppercase;letter-spacing:.03em}.bill .ft{margin-top:22px;text-align:center;font-size:10px;color:#8a978e}.bill .pg{page-break-inside:avoid}.pstrip{display:block;margin-top:22px;background:#1e8e3e;color:#fff!important;text-align:center;font:700 11px Arial,Helvetica,sans-serif;padding:7px 10px;text-decoration:none;border-radius:4px;-webkit-print-color-adjust:exact;print-color-adjust:exact}@media print{.pstrip{position:fixed;left:0;right:0;bottom:0;margin:0;border-radius:0}}';
  C.pstrip = function () { var p = C.powered(); return p ? '<a class="pstrip" data-html2canvas-ignore="true" href="' + esc(p.url) + '" target="_blank" rel="noopener">' + esc(p.text) + '</a>' : ''; };
  C.itemDetails = function (l, tech) {
    var h = '';
    if (l.spec != null || l.specs) {   /* Round 63: chhoti line; poori technical list sirf "Technical sheet" tick par */
      if (l.spec) h += '<div class="det">' + esc(l.spec) + '</div>';
      if (tech) {
        var d = C.lines(l.desc); if (d.length) h += '<div class="det">' + d.map(function (x, n) { return (n + 1) + '. ' + esc(x); }).join('<br>') + '</div>';
        var sp = (l.specs || []).filter(function (p) { return p && String(p[1] || '').trim(); }); if (sp.length) h += '<table class="spt">' + sp.map(function (p) { return '<tr><td>' + esc(p[0]) + '</td><td>' + esc(p[1]) + '</td></tr>'; }).join('') + '</table>';
      }
      return h;
    }
    var d2 = C.lines(l.desc), m = C.lines(l.more); if (d2.length) h += '<div class="det">' + d2.map(function (x, n) { return (n + 1) + '. ' + esc(x); }).join('<br>') + '</div>'; if (m.length) h += '<div class="det"><i>' + m.map(esc).join('<br>') + '</i></div>'; return h;
  };
  C.billHtml = function (rec, type) {
    var S = C.cache.settings || {}, co = S.company || {}, d = rec.data || {}, pt = d.party || {}, T = type === 'invoice' ? 'TAX INVOICE' : type === 'purchase' ? 'PURCHASE ORDER' : (type === 'quote' && d.order_id ? 'ORDER BILL — PAYMENT PENDING' : 'QUOTATION');
    var hideP = type === 'quote' && d.show_item_prices === false;
    var rows = (d.lines || []).map(function (l, n) {
      var body = (l.title ? '<div class="ttl2">' + esc(l.title) + '</div>' : '') + '<b>' + esc(l.name) + '</b>';
      if ((l.kind || 'product') === 'project') body += (l.kw ? '<div class="det"><b>System size: ' + esc(l.kw) + ' kW</b></div>' : '') + '<div class="det">' + (l.proj_items || []).map(function (x) { return '• ' + (x.title ? esc(x.title) + ' – ' : '') + esc(x.name) + ' × ' + esc(x.qty) + (l.show_prices && num(x.price) ? ' @ ' + money(x.price) : '') + (x.spec ? '<br><span style="padding-left:12px;display:inline-block;color:#4d5b52">' + esc(x.spec) + '</span>' : (C.lines(x.desc).length ? '<br><span style="padding-left:12px;display:inline-block">' + C.lines(x.desc).map(esc).join('<br>') + '</span>' : '')); }).join('<br>') + '</div>' + C.itemDetails(l, d.tech);
      else body += C.itemDetails(l, d.tech);
      var amt = num(l.qty) * num(l.price);
      return '<tr class="pg"><td>' + (n + 1) + '</td><td>' + body + '</td><td>' + esc(l.hsn || '') + '</td><td class="r">' + esc(l.qty) + (l.unit ? ' ' + esc(l.unit) : '') + '</td>' + (hideP ? '' : '<td class="r">' + money(l.price) + '</td><td class="r">' + esc(num(l.gst)) + '%</td><td class="r">' + money(amt * (1 + num(l.gst) / 100)) + '</td>') + '</tr>';
    }).join('');
    var h = '<div class="bill" data-noi18n><div class="hdw"><table class="hd"><tr><td style="width:62%">' + '<img src="' + esc(co.logo || C.LOGO_FULL()) + '" style="max-height:62px;max-width:150px;float:left;margin-right:10px">' + '<h1>' + esc(co.legal || co.name || '') + '</h1><div class="sm">' + esc(co.address || '') + (co.state ? '<br>' + esc(co.state) : '') + '<br>' + (co.phone ? 'Ph: ' + esc(co.phone) : '') + (co.email ? ' | ' + esc(co.email) : '') + (co.website ? '<br>' + esc(co.website) : '') + (co.gstin ? '<br><b>GSTIN:</b> ' + esc(co.gstin) : '') + (co.pan ? ' &nbsp; <b>PAN:</b> ' + esc(co.pan) : '') + '</div></td><td><div class="ttl">' + T + '</div><div class="sm r" style="margin-top:6px"><b>No:</b> ' + esc(rec.ref || '') + '<br><b>Date:</b> ' + esc(fd(d.date || rec.created_at)) + (d.valid_till && type === 'quote' ? '<br><b>Valid till:</b> ' + esc(fd(d.valid_till)) : '') + (d.quote_ref ? '<br><b>Ref:</b> ' + esc(d.quote_ref) : '') + (d.due_date && type === 'invoice' ? '<br><b>Due:</b> ' + esc(fd(d.due_date)) : '') + '</div></td></tr></table></div>';
    h += '<table style="margin-bottom:12px"><tr><td class="box" style="width:50%"><b class="h">' + (type === 'purchase' ? 'Supplier' : 'Bill To') + '</b><strong>' + esc(pt.name || rec.title || '') + '</strong><div class="sm">' + (C.addrText && (pt.state || pt.district || pt.pincode) ? esc(C.addrText(pt)).replace(/\n/g, '<br>') : esc(pt.address || '') + (pt.city ? (pt.address ? ', ' : '') + esc(pt.city) : '')) + (pt.mobile || rec.mobile ? '<br>Ph: ' + esc(pt.mobile || rec.mobile) : '') + (pt.email ? '<br>' + esc(pt.email) : '') + (pt.gstin ? '<br>GSTIN: ' + esc(pt.gstin) : '') + '</div></td>' + (d.ship ? '<td class="box"><b class="h">Ship To</b><div class="sm">' + esc(d.ship).replace(/\n/g, '<br>') + '</div></td>' : '<td></td>') + '</tr></table>';
    if (type === 'quote' && d.qtitle) h += '<div style="margin:0 0 10px;font-size:14px"><b>Subject:</b> ' + esc(d.qtitle) + '</div>';
    h += '<table class="it"><thead><tr><th style="width:26px">#</th><th>Item</th><th style="width:62px">HSN</th><th class="r" style="width:54px">Qty</th>' + (hideP ? '' : '<th class="r" style="width:86px">Rate</th><th class="r" style="width:48px">GST</th><th class="r" style="width:96px">Amount</th>') + '</tr></thead><tbody>' + rows + '</tbody></table>';
    h += '<table style="margin-top:8px"><tr><td style="width:52%"></td><td><table class="tot"><tr><td>Subtotal</td><td class="r">' + money(d.subtotal, 1) + '</td></tr><tr><td>GST</td><td class="r">' + money(d.gst_total, 1) + '</td></tr>' + (num(d.discount) > 0 ? '<tr><td>Discount</td><td class="r">−' + money(d.discount, 1) + '</td></tr>' : '') + '<tr class="gt"><td>Grand Total</td><td class="r">' + money(d.grand, 1) + '</td></tr>' + (type === 'invoice' ? '<tr><td>Paid</td><td class="r">' + money(d.paid || 0, 1) + '</td></tr><tr><td><b>Balance Due</b></td><td class="r"><b>' + money(d.balance != null ? d.balance : d.grand, 1) + '</b></td></tr>' : '') + '</table></td></tr></table>';
    h += '<div class="words"><b>Amount in words:</b> ' + C.words(d.grand) + '</div>';
    /* Round 61: sarkari subsidy — sirf jankari, bill ki rakam me se kam nahi hoti. Sirf Residential On-Grid / Hybrid project. */
    if ((type === 'quote' || type === 'invoice') && d.ctype === 'Residential' && d.subsidy && num(d.subsidy.total) > 0 && d.subsidy.sys !== 'off') {
      var sb = d.subsidy, net = Math.max(0, num(d.grand) - num(sb.total));
      h += '<div class="pg" style="margin:10px 0;padding:8px 10px;border:1px solid #bfe0c7;background:#f2faf4;border-radius:6px;font-size:12px"><b>Sarkari subsidy — sirf jankari</b> <span style="color:#555">(ye rakam upar ke bill / quotation me se kam nahi ki gayi; sarkar shartein poori hone par seedha aapke bank khate me deti hai)</span>' +
        '<table style="margin-top:6px;width:100%"><tr><td>Project rate (upar ka kul)</td><td class="r">' + money(d.grand, 1) + '</td></tr>' +
        '<tr><td>Central sarkar (PM Surya Ghar' + (sb.kw ? ', ' + esc(sb.kw) + ' kW' : '') + ')</td><td class="r">' + money(sb.central, 1) + '</td></tr>' +
        (num(sb.state) > 0 ? '<tr><td>Rajya sarkar' + (sb.state_name ? ' (' + esc(sb.state_name) + ')' : '') + '</td><td class="r">' + money(sb.state, 1) + '</td></tr>' : '') +
        '<tr><td><b>Kul anumanit subsidy</b></td><td class="r"><b>' + money(sb.total, 1) + '</b></td></tr>' +
        '<tr><td>Subsidy milne ke baad anumanit asli kharch</td><td class="r">' + money(net, 1) + '</td></tr></table>' +
        '<div style="margin-top:4px;color:#555;font-size:10.5px;line-height:1.35">Sharten: ghar (Residential), grid se juda On-Grid / Hybrid plant, DCR modules, DISCOM / sarkari portal ki manzoori' + (sb.hybrid_note ? ' (Hybrid: rajya ke bijli aayog ki manzoori par nirbhar)' : '') + '. Rakam anumanit hai aur sarkari niyam badalne par badal sakti hai. Sunpowers koi subsidy nahi deta.</div></div>';
    }
    /* Round 62: "Aapko kya milega" — save ke samay ka snapshot; purane / online order ke bill me snapshot na ho to abhi banta hai */
    if ((type === 'quote' || type === 'invoice') && !d.no_ben && window.SPBEN) {
      var bh = (S.hub || {}), br = d.benefits || SPBEN.build({ lines: d.lines || [], ctype: d.ctype, kw: d.kw, sys: d.sys, tariff: bh.tariff, gen: bh.gen, grand: d.grand, subsidy: (d.subsidy || {}).total, ov: bh.ben });
      h += SPBEN.html(br);
    }
    /* Round 54: pehli (Project) quotation anumanit hai; site visit ke baad wali "Antim" */
    if (type === 'quote' && !d.order_id && ['Residential', 'Commercial', 'Industrial', 'VFD'].indexOf(d.ctype) >= 0) {
      if (d.wf && d.wf['4']) h += '<div style="margin:8px 0;padding:7px 10px;border:1px solid #bfe0c7;background:#e3f3e7;border-radius:6px;font-size:12px"><b>Antim (Final) quotation</b> — site visit ke baad.</div>';
      else h += '<div style="margin:8px 0;padding:7px 10px;border:1px solid #f1d9a8;background:#fff4e0;border-radius:6px;font-size:12px"><b>Yah anumanit (estimate) quotation hai.</b> Aapki chhat, sthiti aur site visit ke baad keemat aur saamaan badal sakta hai. Antim quotation site visit ke baad milegi.</div>';
    }
    if (type === 'invoice') h += (d.cancelled ? '<div style="margin:8px 0;padding:6px 10px;border:2px solid #b3261e;color:#b3261e;font-weight:800;text-align:center">CANCELLED – NON REFUNDABLE</div>' : '') + '<div class="sm" style="margin-top:6px"><b>Note:</b> ' + (d.refund_ok ? 'Refund sirf Admin ki likhit ijazat se.' : 'Is bill ka bhugtan non-refundable hai — jama hua paisa wapas nahi hoga.') + '</div>';
    /* Round 58: sirf FINAL bill (poora payment aa gaya) par, sirf Project / Service — prakritik aapda ki chhoti line */
    if (type === 'invoice' && !d.cancelled && ['Items only', 'AMC only', 'Site visit only'].indexOf(d.ctype) < 0 && String(co.bill_calamity) !== '0' && num(d.balance != null ? d.balance : d.grand) <= 0 && num(d.grand) > 0)
      h += '<div style="margin-top:8px;font-size:10px;line-height:1.35;color:#555"><b>Prakritik aapda / Natural disaster:</b> ' + esc(co.calamity_text || 'Kaam poora hone ke baad aandhi-toofan, ole, bhookamp, baadh, aasmani bijli, tornado jaisi prakritik aapda se hue nuksan ki zimmedari Sunpowers ki nahi hogi; ye hamare installation ki apni khami par lagu nahi hota. / Damage from natural disasters (storm, hail, earthquake, flood, lightning, tornado) after handover is not covered; this does not apply to defects in our own installation work.') + '</div>';
    if (type === 'invoice' && (rec.payments || []).length) h += '<h4>Payment History</h4><table class="ph"><thead><tr><th>Date</th><th>Mode</th><th>Ref / UTR</th><th class="r">Amount</th></tr></thead><tbody>' + rec.payments.map(function (p) { return '<tr><td>' + esc(fd(p.due_at)) + '</td><td>' + esc(p.data.mode || '') + '</td><td>' + esc(p.data.utr || p.ref || '-') + '</td><td class="r">' + money(p.amount) + '</td></tr>'; }).join('') + '</tbody></table>';
    var bank = co.bank_name || co.bank_acc || co.upi;
    var qrImg = ''; /* Round 57: bakaya bill par UPI QR (rakam locked nahi) */
    if (type === 'invoice' && !d.cancelled && co.upi && /^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9.-]{2,32}$/.test(co.upi) && num(d.balance != null ? d.balance : d.grand) > 0 && window.SPQR) { try { qrImg = '<br><img src="' + window.SPQR.canvas('upi://pay?pa=' + encodeURIComponent(co.upi) + '&pn=' + encodeURIComponent(co.bank_holder || co.legal || co.name || '') + '&cu=INR&tn=' + encodeURIComponent(rec.ref || ''), 180).toDataURL('image/png') + '" style="width:92px;height:92px;margin-top:4px"><br>Scan &amp; pay'; } catch (e) { qrImg = ''; } }
    var terms = d.notes || (type === 'quote' ? co.terms_quote : '') || co.terms;
    if (bank || terms) { h += '<table style="margin-top:12px"><tr>'; if (bank && type !== 'purchase' && (type !== 'quote' || String(co.quote_show_bank) === '1')) h += '<td class="box" style="width:50%"><b class="h">Bank Details</b><div class="sm">' + (co.bank_holder ? 'A/c Name: ' + esc(co.bank_holder) + '<br>' : '') + (co.bank_name ? 'Bank: ' + esc(co.bank_name) + '<br>' : '') + (co.bank_acc ? 'A/c No: ' + esc(co.bank_acc) + '<br>' : '') + (co.bank_ifsc ? 'IFSC: ' + esc(co.bank_ifsc) + '<br>' : '') + (co.upi ? 'UPI: ' + esc(co.upi) : '') + qrImg + '</div></td>'; if (terms) h += '<td class="box"><b class="h">Terms &amp; Notes</b><div class="sm">' + esc(terms).replace(/\n/g, '<br>') + '</div></td>'; h += '</tr></table>'; }
    h += '<table style="margin-top:30px" class="pg"><tr><td class="sm" style="width:55%;vertical-align:bottom">' + (type === 'purchase' ? '' : 'Customer Signature') + '</td><td class="sm r">For <b>' + esc(co.legal || co.name || '') + '</b><br>' + (co.sign ? '<img src="' + esc(co.sign) + '" style="max-height:48px;max-width:160px;display:inline-block"><br>' : '<br><br><br>') + esc(co.sign_label || 'Authorised Signatory') + '</td></tr></table>' + C.pstrip() + '</div>';
    return '<style>' + C.BILL_CSS + '</style>' + h;
  };

  /* ================================================================ router + modules */
  C.mod = function (key, def) { C.mods[key] = def; (def.routes || [key]).forEach(function (r) { C.routes[r] = def; }); };
  C.go = function (h) { if (location.hash === h) C.render(); else location.hash = h; };
  C.parse = function () { var h = location.hash.replace(/^#\/?/, ''), qi = h.indexOf('?'), q = {}; if (qi >= 0) { h.slice(qi + 1).split('&').forEach(function (kv) { var a = kv.split('='); if (a[0]) q[decodeURIComponent(a[0])] = decodeURIComponent(a[1] || ''); }); h = h.slice(0, qi); } var parts = h.split('/').filter(Boolean); return { name: parts[0] || 'home', params: parts.slice(1), query: q }; };
  var renderSeq = 0;
  C.render = async function () {
    if (!C.me) return;
    var r = C.parse(), def = C.routes[r.name] || C.routes.home, view = $('#view'), seq = ++renderSeq;
    closeSearch(); $('#side').classList.remove('open'); var sc = $('#scrim'); if (sc) sc.remove();
    $$('.nav a, .mob-nav a').forEach(function (a) { a.classList.toggle('on', a.getAttribute('data-nav') === (C.secOf(r.name) || def.nav || r.name)); });
    if (def.allowed && !def.allowed()) { view.setAttribute('data-h', location.hash); view.innerHTML = C.empty('lock', 'Permission nahi hai', 'Ye hissa aapke liye band hai — Admin se baat karein.'); return; }
    view.innerHTML = C.loading();
    var fresh = document.createElement('div'); fresh.id = 'view'; fresh.className = 'view'; fresh.setAttribute('data-h', location.hash);
    try {
      await def.render(fresh, r.params, r.query, r.name);
      if (seq !== renderSeq) return;
      try { if (C.addHint) C.addHint(fresh, r.name); } catch (e) {}
      try { C.sectionBar(fresh, r); } catch (e) {}
      view.replaceWith(fresh); window.scrollTo(0, 0); C.fitPreviews();
      document.title = (def.title ? (typeof def.title === 'function' ? def.title(r) : def.title) + ' · ' : '') + (C.company().name || 'CRM');
    } catch (e) {
      if (seq !== renderSeq || C._bye) return;
      view.setAttribute('data-h', location.hash);
      if (/permission/i.test(e.message)) { view.innerHTML = C.empty('lock', 'Permission nahi hai', e.message + ' — Admin se baat karein.'); return; }
      if (/nahi mil/i.test(e.message)) { view.innerHTML = '<div class="card">' + C.empty('search', e.message, 'Ye record hata diya gaya hai ya aapko dikhane ki permission nahi hai.', '<a class="btn btn-o" href="#/home">' + C.ic('home') + ' Home</a>') + '</div>'; return; } console.error(e); view.innerHTML = '<div class="card">' + C.empty('alert', 'Kuch gadbad hui', e.message, '<button class="btn btn-o" onclick="CRM.render()">' + C.ic('refresh') + ' Dobara koshish</button>') + '</div>';
    }
  };
  C.refresh = function () { return C.render(); };
  /* printable bills keep A4 layout; on small screens they are zoomed to fit */
  C.fitPreviews = function () { $$('.preview').forEach(function (p) { var b = p.querySelector('.bill'); if (!b) return; b.style.zoom = ''; b.style.minWidth = ''; var w = p.clientWidth - 34; if (w < 700) { b.style.minWidth = '720px'; b.style.zoom = Math.max(0.3, w / 720); } }); };
  window.addEventListener('resize', C.debounce(function () { C.fitPreviews(); }, 200));

  /* navigation definition
     Round 45: sidebar chhota (25 -> 15). Jo pages ek dusre se jude hain wo ek entry ke andar tab-strip me hain (C.SECTIONS).
     Routes kahin nahi badle (#/sitevisit, #/commission, #/docs ...) — isliye customer flow patti aur purane links jaise the waise chalte hain. */
  var _any = function () { var a = arguments; return function () { return C.canAny.apply(C, a); }; };
  C.SECTIONS = {
    customers: { l: 'Customers', i: 'users', tabs: [
      ['customers', 'All Customers', '#/customers', function () { return C.canAny('customers.create', 'customers.view_all') || C.isPartner(); }],
      ['inquiries', 'Conversation', '#/inquiries', _any('customers.create', 'customers.view_all')]
    ] },
    projects: { l: 'Projects', i: 'plant', rib: 'Live tracking', tabs: [
      ['projects', 'Projects', '#/projects', _any('quotes.create', 'quotes.view_all', 'plants.create', 'plants.view_all')],
      ['sitevisit', 'Site Visit', '#/sitevisit', _any('leads.create', 'leads.view_all')],
      ['blueprint', 'Project blue print', '#/blueprint', _any('leads.create', 'leads.view_all')],
      ['maintenance', 'Maintenance & AMC', '#/maintenance', _any('items.view', 'reminders.view_all', 'customers.create', 'customers.view_all')]
    ] },
    accounts: { l: 'Accounts & Reports', i: 'rupee', tabs: [
      ['accounts', 'Accounts', '#/accounts', _any('accounts.manage', 'accounts.view')],
      ['reports', 'Reports', '#/reports', _any('reports.view')],
      ['analytics', 'Analytics', '#/analytics', _any('analytics.view')]
    ] },
    partners: { l: 'Partners', i: 'users', tabs: [
      ['partners', 'Dealer / Influencer', '#/partners', _any('users.manage')],
      ['commission', 'Commission', '#/commission', function () { return !C.isPartner() && C.canAny('earnings.view_all', 'earnings.manage'); }]
    ] },
    settings: { l: 'Settings', i: 'settings', tabs: [
      ['settings', 'Settings', '#/settings', _any('settings.manage')],
      ['team', 'Roles & Permission', '#/team', function () { return C.isAdmin(); }],
      ['connections', 'Connections', '#/connections', function () { return C.isAdmin(); }],
      ['activity', 'Activity Record', '#/activity', _any('activity.view')],
      ['hints', 'Help & Hints', '#/hints', function () { return C.isAdmin(); }]
    ] }
  };
  C.secTabs = function (k) { return (C.SECTIONS[k] ? C.SECTIONS[k].tabs : []).filter(function (t) { return t[3](); }); };
  C.secShow = function (k) { return function () { return C.secTabs(k).length > 0; }; };
  /* kis section ka page hai (sirf tab tab jab us section ki entry user ko dikh rahi ho) */
  C.secOf = function (route) {
    for (var k in C.SECTIONS) if (C.SECTIONS[k].tabs.some(function (t) { return t[0] === route; }) && C.secTabs(k).length) return k;
    return null;
  };
  C.sectionBar = function (root, r) {
    var k = C.secOf(r.name); if (!k) return;
    if ((r.query && (r.query.cf || r.query.cq)) || (r.params && r.params.length)) return; /* customer flow patti pehle se upar hai */
    var tabs = C.secTabs(k); if (tabs.length < 2) return;
    root.insertAdjacentHTML('afterbegin', '<div class="tabs sec" role="tablist">' + tabs.map(function (t) { return '<a href="' + t[2] + '" class="' + (t[0] === r.name ? 'on' : '') + '">' + esc(t[1]) + '</a>'; }).join('') + '</div>');
  };
  C.NAV = [
    { g: 'Main', items: [
      { k: 'home', l: 'Home', i: 'home' },
      { k: 'today', l: 'Aaj ke kaam', i: 'today', cnt: 'today' },
      { k: 'leads', l: 'Leads', i: 'lead', show: function () { return C.canAny('leads.create', 'leads.view_all'); } },
      { k: 'customers', l: 'Customers', i: 'users', show: C.secShow('customers') }
    ] },
    { g: 'Sales & Work', items: [
      { k: 'quotes', l: 'Quotations & Templates', i: 'quote', show: function () { return C.canAny('quotes.create', 'quotes.view_all'); } },
      { k: 'projects', l: 'Projects', i: 'plant', rib: 'Live tracking', show: C.secShow('projects') },
      { k: 'billing', l: 'Billing', i: 'bill', show: function () { return C.canAny('invoices.create', 'invoices.view_all', 'payments.record', 'purchase.manage') || C.isPartner(); } },
      { k: 'orders', l: 'Store Orders', i: 'cart', cnt: 'orders', show: function () { return C.can('orders.view'); } }
    ] },
    { g: 'Stock & Library', items: [
      { k: 'items', l: 'Inventory/Stock', i: 'box', show: function () { return C.can('items.view'); } },
      { k: 'docs', l: 'Documents & Gallery', i: 'folder', show: function () { return C.can('docs.view'); } }
    ] },
    { g: 'Money', items: [
      { k: 'accounts', l: 'Accounts & Reports', i: 'rupee', show: C.secShow('accounts') },
      { k: 'commission', l: 'Commission', i: 'rupee', show: function () { return C.isPartner(); } }
    ] },
    { g: 'People & Grow', items: [
      { k: 'staffs', l: 'All Staffs', i: 'team', show: function () { return C.canAny('staff.view', 'staff.manage', 'staff.hr', 'salary.manage', 'users.manage', 'team.stats'); } },
      { k: 'partners', l: 'Partners', i: 'users', show: function () { return C.canAny('users.manage', 'earnings.view_all', 'earnings.manage') && !C.isPartner(); } },
      { k: 'marketing', l: 'Marketing & Grow', i: 'megaphone', show: function () { return C.canAny('marketing.view', 'marketing.manage', 'marketing.leads'); } }
    ] },
    { g: 'Company', items: [
      { k: 'settings', l: 'Settings', i: 'settings', show: C.secShow('settings') }
    ] }
  ];
  function navHtml() {
    return C.NAV.map(function (g) { var it = g.items.filter(function (x) { return !x.show || x.show(); }); if (!it.length) return ''; return '<h6>' + esc(g.g) + '</h6>' + it.map(function (x) { return '<a href="#/' + x.k + '" data-nav="' + x.k + '">' + C.ic(x.i) + '<span>' + esc(x.l) + '</span>' + (x.rib ? '<span class="nrib">' + esc(x.rib) + '</span>' : '') + (x.cnt ? '<span class="cnt" data-cnt="' + x.cnt + '" hidden></span>' : '') + '</a>'; }).join(''); }).join('');
  }
  function mobNavHtml() {
    var list = [{ k: 'home', l: 'Home', i: 'home' }, { k: 'today', l: 'Aaj', i: 'today', cnt: 'today' }];
    if (C.canAny('leads.create', 'leads.view_all')) list.push({ k: 'leads', l: 'Leads', i: 'lead' });
    if (C.canAny('quotes.create', 'quotes.view_all')) list.push({ k: 'quotes', l: 'Quotations & Templates', i: 'quote' }); else list.push({ k: 'customers', l: 'All Customers', i: 'users' });
    list = list.slice(0, 4);
    return list.map(function (x) { return '<a href="#/' + x.k + '" data-nav="' + x.k + '">' + C.ic(x.i) + esc(x.l) + (x.cnt ? '<span class="cnt" data-cnt="' + x.cnt + '" hidden></span>' : '') + '</a>'; }).join('') + '<button type="button" id="mobMore">' + C.ic('grid') + 'Menu</button>';
  }

  /* Round 50: "App install karein" in the side menu (desktop sidebar + mobile Menu). Hidden once the app is installed. */
  function installNav() { try { if (window.SPInstall && SPInstall.available()) return '<h6>App</h6><a href="#" data-sp-install id="navInstall">' + C.ic('download') + 'App install karein</a>'; } catch (e) {} return ''; }

  /* ================================================================ shell */
  function shell() {
    var me = C.me, co = C.company();
    document.body.innerHTML = '<div class="shell"><aside class="side" id="side"><div class="brand">' + C.LOGO + '<span><b>' + esc(co.name || 'Sunpowers') + '</b><small>CRM</small></span></div><nav class="nav" aria-label="Menu">' + navHtml() + installNav() + '</nav>' +
      '<div class="me"><a href="#/profile" class="mechip" title="Meri Profile" style="display:flex;align-items:center;gap:10px;min-width:0;flex:1;color:inherit;text-decoration:none"><span class="li" style="padding:0;border:0;background:none"><span class="av o">' + esc(C.initials(me.name)) + '</span></span><div class="grow" style="min-width:0"><b class="ellip">' + esc(me.name) + '</b><span>' + esc(C.ROLE[me.role] || me.role) + (me.ref_code ? ' · ' + esc(me.ref_code) : '') + '</span></div></a><button class="btn btn-icon btn-sm" style="color:#fff" data-logout title="Logout" aria-label="Logout">' + C.ic('logout') + '</button></div></aside>' +
      '<div class="main"><header class="top"><button class="btn btn-g btn-icon mob-only" id="menuBtn" aria-label="Menu kholein">' + C.ic('menu') + '</button><a class="brand dark tbrand" href="#/home">' + C.LOGO_D + '</a>' +
      '<div class="search collapsed-m" id="search">' + C.ic('search') + '<input id="q" type="search" placeholder="Customer, mobile, quotation, document khojein…" autocomplete="off" aria-label="Khojein"><div class="sres" id="sres" hidden></div></div>' +
      '<div class="acts"><button class="btn btn-g btn-icon mob-only" id="searchBtn" aria-label="Khojein">' + C.ic('search') + '</button>' +
      (C.cfg.STORE_URL ? '<a class="btn btn-o btn-sm desk-only" href="' + esc(C.cfg.STORE_URL) + '" target="_blank" rel="noopener">' + C.ic('store') + ' Store</a>' : '') +
      (C.siteUrl && C.siteUrl() ? '<a class="btn btn-o btn-sm desk-only" id="lnkSite" href="' + esc(C.siteUrl()) + '" target="_blank" rel="noopener">' + C.ic('globe') + ' Website</a>' : '') +
      '<button type="button" class="btn btn-o btn-sm" data-sp-lang="short" id="langBtn" aria-label="Language"></button>' +
      '<div class="bell" style="position:relative"><button class="btn btn-g btn-icon" id="bellBtn" aria-label="Notifications">' + C.ic('bell') + '<span class="dot" id="bellDot" hidden></span></button></div></div></header>' +
      '<main id="view" class="view"></main></div></div><nav class="mob-nav" aria-label="Quick menu">' + mobNavHtml() + '</nav><div class="toasts" id="toasts"></div>';
    $('[data-logout]').onclick = C.logout;
    $('#menuBtn').onclick = openSide; $('#mobMore').onclick = openSide;
    initSearch(); initBell();
    if (window.innerWidth <= 900) $('#search').classList.add('collapsed');
    if (window.SPLOOK && SPLOOK.cur()) { try { SPLOOK.again(); } catch (e) {} }
  }
  function openSide() { $('#side').classList.add('open'); var s = document.createElement('div'); s.className = 'scrim'; s.id = 'scrim'; s.onclick = function () { $('#side').classList.remove('open'); s.remove(); }; document.body.appendChild(s); }

  /* ---------------- global search */
  var KIND = { party: ['Customer', 'users', 'customer/'], lead: ['Lead', 'lead', 'leads?open='], quote: ['Quotation', 'quote', 'quote/'], invoice: ['Bill', 'bill', 'invoice/'], item: ['Product', 'box', 'items?open='], doc: ['Document', 'folder', 'docs?doc='], folder: ['Folder', 'folder', 'docs/'], plant: ['Plant', 'plant', 'projects?tab=referral&open='], payment: ['Payment', 'rupee', 'billing?tab=payments&open='] };
  C.recLink = function (kind, id) { var k = KIND[kind]; return k ? '#/' + k[2] + id : '#/home'; };
  function closeSearch() { var r = $('#sres'); if (r) r.hidden = true; if (window.innerWidth <= 900 && $('#search')) $('#search').classList.add('collapsed'); }
  function initSearch() {
    var q = $('#q'), box = $('#sres'), hl = -1;
    $('#searchBtn').onclick = function () { $('#search').classList.remove('collapsed'); q.focus(); };
    var run = C.debounce(async function () {
      var v = q.value.trim(); if (v.length < 2) { box.hidden = true; return; }
      try {
        var res = await C.call('crm_search', { q: v }); if (q.value.trim() !== v) return;
        box.innerHTML = res.length ? res.map(function (x) { var k = KIND[x.kind] || ['', 'dots', 'home']; return '<a href="' + C.recLink(x.kind, x.id) + '"><span class="k">' + k[0] + '</span><span class="grow"><b class="ellip" style="display:block">' + esc(x.title) + '</b><span class="xs mute">' + esc([x.ref, x.mobile, x.status].filter(Boolean).join(' · ')) + '</span></span>' + (num(x.amount) ? '<span class="xs b">' + money(x.amount) + '</span>' : '') + '</a>'; }).join('') : '<div class="empty" style="padding:18px">Kuch nahi mila</div>';
        box.hidden = false; hl = -1;
      } catch (e) {}
    }, 250);
    q.addEventListener('input', run);
    q.addEventListener('keydown', function (e) { var a = $$('a', box); if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); hl = Math.max(0, Math.min(a.length - 1, hl + (e.key === 'ArrowDown' ? 1 : -1))); a.forEach(function (x, i) { x.classList.toggle('hl', i === hl); }); } else if (e.key === 'Enter' && a[hl >= 0 ? hl : 0]) { location.hash = a[hl >= 0 ? hl : 0].getAttribute('href'); q.value = ''; closeSearch(); } else if (e.key === 'Escape') { closeSearch(); q.blur(); } });
    box.addEventListener('click', function (e) { if (e.target.closest('a')) { q.value = ''; setTimeout(closeSearch, 10); } });
    document.addEventListener('click', function (e) { if (!e.target.closest('#search') && !e.target.closest('#searchBtn')) closeSearch(); });
  }

  /* ---------------- bell / notifications */
  var pulseItems = [], pulseTimer = null;
  function beep() { try { var A = window.AudioContext || window.webkitAudioContext; if (!A) return; var a = new A(), o = a.createOscillator(), g = a.createGain(); o.frequency.value = 880; o.connect(g); g.connect(a.destination); g.gain.setValueAtTime(0.08, a.currentTime); g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + 0.35); o.start(); o.stop(a.currentTime + 0.36); } catch (e) {} }
  var TYPEI = { order: ['cart', 'Order', 'orders?tab=orders'], enquiry: ['globe', 'Enquiry', 'orders?tab=enquiries'], lead: ['lead', 'Lead', 'leads?open='], reminder: ['today', 'Kaam', 'today'], plant: ['plant', 'Plant', 'projects?tab=referral&open='], user: ['user', 'ID', 'team'], svc: ['settings', 'Service', 'settings?tab=services'] };
  async function pulse(first) {
    if (!C.me || document.hidden) return;
    try {
      var seen = C.ls('crm_seen_' + C.me.id) || new Date(Date.now() - 3 * 864e5).toISOString();
      var res = await C.call('crm_pulse', { since: new Date(Date.now() - 7 * 864e5).toISOString() });
      var prevNew = pulseItems.filter(function (x) { return x.at > seen; }).length;
      pulseItems = (res.items || []).sort(function (a, b) { return a.at < b.at ? 1 : -1; });
      var fresh = pulseItems.filter(function (x) { return x.at > seen; });
      var dot = $('#bellDot'); if (dot) { dot.hidden = !fresh.length; dot.textContent = fresh.length > 9 ? '9+' : fresh.length; }
      document.title = document.title.replace(/^\(\d+\+?\) /, ''); if (fresh.length) document.title = '(' + fresh.length + ') ' + document.title;
      if (!first && fresh.length > prevNew) { beep(); C.toast('🔔 ' + fresh[0].title); }
      var oc = pulseItems.filter(function (x) { return x.type === 'order' && x.at > seen; }).length; $$('[data-cnt=orders]').forEach(function (e) { e.hidden = !oc; e.textContent = oc; });
    } catch (e) {}
  }
  C.updateTodayCount = function (n) { $$('[data-cnt=today]').forEach(function (e) { e.hidden = !n; e.textContent = n > 99 ? '99+' : n; }); };
  function initBell() {
    $('#bellBtn').onclick = function (e) {
      e.stopPropagation(); var ex = $('#bellPop'); if (ex) { ex.remove(); return; }
      var seen = C.ls('crm_seen_' + C.me.id) || '', p = document.createElement('div'); p.className = 'pop'; p.id = 'bellPop';
      p.innerHTML = '<h4>Notifications <button class="btn btn-g btn-sm" data-seen>' + C.ic('check') + ' Sab dekh liya</button></h4><div class="lst">' + (pulseItems.length ? pulseItems.slice(0, 40).map(function (x) { var t = TYPEI[x.type] || ['bell', '', 'home']; return '<a class="it' + (x.at > seen ? ' new' : '') + '" href="#/' + t[2] + (/=$/.test(t[2]) ? x.id : '') + '">' + C.ic(t[0]) + '<span class="grow"><b style="display:block;font-weight:600">' + esc(x.title) + '</b><span class="xs mute">' + esc(C.ago(x.at)) + (x.amount ? ' · ' + money(x.amount) : '') + '</span></span></a>'; }).join('') : '<div class="empty" style="padding:24px">Abhi kuch naya nahi</div>') + '</div>';
      $('.bell').appendChild(p);
      $('[data-seen]', p).onclick = function () { C.ls('crm_seen_' + C.me.id, new Date().toISOString()); p.remove(); pulse(true); };
      p.addEventListener('click', function (ev) { if (ev.target.closest('a')) { C.ls('crm_seen_' + C.me.id, new Date().toISOString()); setTimeout(function () { p.remove(); pulse(true); }, 10); } });
    };
    document.addEventListener('click', function (e) { var p = $('#bellPop'); if (p && !e.target.closest('.bell')) p.remove(); });
    pulse(true); clearInterval(pulseTimer); pulseTimer = setInterval(pulse, 60000);
    document.addEventListener('visibilitychange', function () { if (!document.hidden) pulse(); });
  }
  C.pulse = pulse;

  /* ================================================================ auth screens (Email OTP + PIN — assets/auth.js) */
  function authHtml() {
    var co = C.company();
    return '<button type="button" class="btn btn-o btn-sm auth-lang" data-sp-lang="long" aria-label="Language"></button><div class="auth"><section class="auth-art"><div class="brand">' + C.LOGO + '<span><b>' + esc(co.name || 'Sunpowers') + '</b><small>CRM</small></span></div><div><h1>Har lead, har quotation, har plant — <em>ek jagah.</em></h1><p>Billing, quotation, leads, reminders, documents aur team ka poora hisab — mobile aur computer dono par.</p><ul><li>' + C.ic('check') + 'Pehli baar Email OTP, phir sirf PIN</li><li>' + C.ic('check') + 'Quotation aur GST bill ek click me WhatsApp par</li><li>' + C.ic('check') + 'Har user ko sirf apna data dikhta hai</li></ul></div><p class="xs" style="color:var(--on-dark-mute)">© ' + new Date().getFullYear() + ' ' + esc(co.legal || co.name || 'Sunpowers') + '</p></section><section class="auth-form"><div class="auth-card" id="authBox"></div></section></div><div class="toasts" id="toasts"></div>';
  }
  function saveToken(r) {
    C.token = r.token;
    if (r.admin) { C.ss('crm_tok_s', r.token); C.ls('crm_tok', null); }   /* Admin: PIN every time the CRM is opened */
    else { C.ls('crm_tok', r.token); C.ss('crm_tok_s', null); }            /* others: stay logged in until Logout */
  }
  function showAuth() {
    document.body.onclick = null;
    document.body.innerHTML = authHtml();
    if (!window.SPAuth) { $('#authBox').innerHTML = '<p class="err">auth.js load nahi hua — page refresh karein</p>'; return; }
    window.SPAuth.mount($('#authBox'), { app: 'crm', lang: 'hn', title: 'Login', sub: 'Manager, Staff, Dealer aur Influencer — apni ID se login karein.',
      register: [['dealer', 'Dealer'], ['influencer', 'Influencer']], regSub: 'Dealer / Influencer ki ID — Admin verify karega.',
      rpc: function (fn, p) { return C.rpc(fn, { p: p }); },
      onDone: async function (r) { saveToken(r); await boot(); } });
  }
  C.ss = function (k, v) { try { if (v === undefined) return sessionStorage.getItem(k); if (v === null) sessionStorage.removeItem(k); else sessionStorage.setItem(k, v); } catch (e) { return null; } };
  /* Round 33: an Admin who came through the Admin panel goes BACK to the Admin page on logout (not to the CRM login screen). */
  function backToAdmin() {
    var u = null; try { u = window.SPSwitch && SPSwitch.urlFor('admin'); } catch (e) {}
    if (u) { location.href = u; return true; }
    try { window.close(); } catch (e) {}
    return false;
  }
  C.logoutLocal = function (msg) { var wasAdmin = false; try { wasAdmin = !!(C.me && C.isAdmin()); } catch (e) {} if (window.SPSwitch) SPSwitch.unmount(); C.me = null; C.token = null; C.cache = {}; C.ls('crm_tok', null); C.ss('crm_tok_s', null); clearInterval(pulseTimer); if (wasAdmin && backToAdmin()) return; showAuth(); if (msg) C.toast(msg, true); };
  C.logout = async function () { try { await C.call('crm_logout', {}); } catch (e) {} C.logoutLocal(); };

  /* Round 26: Admin enters the CRM only through the Admin panel (one-time ticket in the URL fragment, verified on the server). */
  async function takeHandoff() {
    var m = /[#&]h=([0-9a-f]{20,})/.exec(location.hash || ''); if (!m) return;
    try { history.replaceState(null, '', location.pathname + location.search); } catch (e) {}
    try { var r = await C.rpc('crm_auth_handoff', { p: { ticket: m[1], device: '' } }); if (r && r.token) saveToken(r); }
    catch (e) { C.ss('crm_tok_s', null); C.token = null; C._hoErr = e.message || 'Link expire ho gaya'; }
  }
  async function boot() {
    await takeHandoff();
    C.token = C.ss('crm_tok_s') || C.ls('crm_tok');
    if (window.SPAuth && window.SPAuth.resetToken()) { showAuth(); return; }
    if (!C.token) { showAuth(); if (C._hoErr) { C.toast(C._hoErr, true); C._hoErr = ''; } return; }
    try { C.me = await C.call('crm_me', {}); }
    catch (e) { C.ls('crm_tok', null); C.ss('crm_tok_s', null); C.token = null; showAuth(); if (!/Login expired/.test(e.message)) C.toast(e.message, true); return; }
    if (window.SPSwitch) SPSwitch.mount(C.me.role, 'crm');
    try { await C.settings(); } catch (e) { C.cache.settings = {}; }
    if (C.canAny('users.manage', 'leads.assign', 'reminders.assign', 'customers.assign', 'earnings.manage', 'team.stats', 'docs.folders')) C.users();
    shell();
    if (window.SPLOOK) { try { SPLOOK.boot('crm', { ctx: { userId: C.me.id, mount: function () { return document.querySelector('.main'); }, before: function () { return document.querySelector('.main > .top'); } } }); } catch (e) {} }
    if (!location.hash || location.hash === '#' || location.hash === '#/') location.hash = '#/home'; else C.render();
  }
  window.addEventListener('hashchange', function () { C.render(); });
  window.addEventListener('pagehide', function () { C._bye = true; });
  C.boot = boot;
  /* start now if the page is already loaded (some hosts insert the page after DOMContentLoaded) */
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { boot(); });
  else boot();
})();
