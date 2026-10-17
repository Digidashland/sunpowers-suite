/* Sunpowers Admin — shared dark header (Round 16): ☰ menu · title · 🔍 search · filter · 🔔 alerts · language · logout.
   Icons only. The left menu is a full-height drawer. Alerts live in the bell with a "New" badge.
   SPHDR.config({ items:[{id,ic,l,kw,fn,group}], links:[...], alerts:fn()->Promise<[{c,t}]>, logout:fn }) once;
   SPHDR.bar({ title, back:true, filter:true }) returns header HTML; SPHDR.bind({ back:fn, onFilter:fn }) wires it.        */
(function () {
  'use strict';
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var CFG = { items: [], alerts: null, logout: null, counts: null }, ALERTS = [], SEEN = '';
  function ls(k, v) { try { if (v === undefined) return localStorage.getItem(k) || ''; localStorage.setItem(k, v); } catch (e) {} return ''; }
  var IC = {"menu": "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M4 6h16M4 12h16M4 18h16\"/></svg>", "back": "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M15 5l-7 7 7 7\"/></svg>", "search": "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><circle cx=\"11\" cy=\"11\" r=\"7\"/><path d=\"M20 20l-4-4\"/></svg>", "filter": "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 5h18l-7 8v6l-4-2v-4z\"/></svg>", "bell": "<svg viewBox=\"0 0 24 24\" width=\"22\" height=\"22\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M6 17V11a6 6 0 1112 0v6l1.5 2h-15z\"/><path d=\"M10 21a2 2 0 004 0\"/></svg>"};
  var CSS = '.hd{position:sticky;top:0;z-index:60;background:#14301f;color:#fff;padding-top:env(safe-area-inset-top,0px)}.hd-in{max-width:1100px;margin:0 auto;display:flex;align-items:center;gap:4px;padding:6px 8px;min-height:52px}' +
    '.hd-b{position:relative;width:42px;height:42px;border-radius:12px;display:inline-grid;place-items:center;font-size:20px;color:#fff;background:transparent;flex:none;text-decoration:none}.hd-b:active,.hd-b:hover{background:rgba(255,255,255,.14)}' +
    '.hd-t{flex:1;min-width:0;font-size:16px;font-weight:800;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;gap:8px;padding:0 4px}.hd-t img{height:28px;width:28px;border-radius:7px;flex:none}' +
    '.hd-t{font-size:15.5px}@media(max-width:480px){.hd-t img{display:none}.hd-b{width:38px}}.hd-dot{position:absolute;top:3px;right:1px;background:#e53935;color:#fff;border-radius:999px;font-size:10px;font-weight:800;padding:1px 6px;line-height:1.3;border:2px solid #14301f}.hd-dot.n{top:2px;right:-4px}' +
    '.hd-lang button,.hd-lang a{color:#fff!important;background:transparent!important;border:0!important;font-size:13px!important;padding:6px!important}' +
    '.hd-ov{position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:90;opacity:0;transition:opacity .2s}.hd-ov.on{opacity:1}' +
    '.hd-dr{position:fixed;top:0;left:0;bottom:0;width:min(84vw,320px);background:#fff;color:#1c2b20;z-index:91;transform:translateX(-102%);transition:transform .22s;display:flex;flex-direction:column;box-shadow:4px 0 24px rgba(0,0,0,.25);padding-top:env(safe-area-inset-top,0px)}.hd-dr.on{transform:none}' +
    '.hd-dh{background:#14301f;color:#fff;padding:14px;display:flex;align-items:center;gap:10px;font-weight:800}.hd-dh img{width:36px;height:36px;border-radius:9px}.hd-dh span{flex:1}.hd-dh button{color:#fff;font-size:22px;width:36px;height:36px}' +
    '.hd-dl{flex:1;overflow-y:auto;padding:8px 8px 24px}.hd-g{font-size:11.5px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:#66756a;padding:12px 10px 4px}' +
    '.hd-i{display:flex;align-items:center;gap:12px;width:100%;text-align:left;padding:11px 10px;border-radius:12px;font-size:15px;font-weight:600;text-decoration:none;color:#1c2b20}.hd-i:hover,.hd-i.on{background:#e8f5e9}.hd-i i{font-style:normal;width:26px;text-align:center;font-size:19px}.hd-i em{margin-left:auto;font-style:normal;background:#e53935;color:#fff;border-radius:999px;font-size:11px;padding:1px 7px;font-weight:800}' +
    '.hd-pop{position:fixed;z-index:92;background:#fff;color:#1c2b20;border-radius:14px;box-shadow:0 8px 30px rgba(0,0,0,.28);min-width:210px;max-width:92vw;padding:6px;top:calc(56px + env(safe-area-inset-top,0px));right:8px}.hd-pop .hd-i{padding:10px}.hd-pop.al{width:min(92vw,360px);max-height:70vh;overflow:auto}' +
    '.hd-a{display:flex;gap:8px;border-radius:10px;padding:9px 10px;font-size:13.5px;margin:4px;border:1px solid}.hd-a.r{background:#fdecea;border-color:#f5c2bd;color:#8a1f17}.hd-a.y{background:#fff8e6;border-color:#ffe08a;color:#7a5a00}.hd-a.g{background:#e8f5e9;border-color:#b9d6c3;color:#14622e}' +
    '.hd-sr{position:fixed;inset:0;z-index:93;background:#fff;display:flex;flex-direction:column;padding-top:env(safe-area-inset-top,0px)}.hd-sr .hd-sh{display:flex;gap:6px;align-items:center;background:#14301f;padding:8px}.hd-sr input{flex:1;border:0;border-radius:12px;padding:12px;font-size:16px;outline:0}.hd-sr .hd-sh button{color:#fff;font-size:22px;width:40px;height:40px}.hd-sr .hd-dl{padding:8px}';
  function cssOnce() { if (document.getElementById('hd-css')) return; var s = document.createElement('style'); s.id = 'hd-css'; s.textContent = CSS; document.head.appendChild(s); }
  function bar(o) {
    cssOnce(); o = o || {};
    return '<div class="hd"><div class="hd-in">' + (o.back ? '<button type="button" class="hd-b" data-hd="back" aria-label="Back">' + IC.back + '</button>' : '') + '<button type="button" class="hd-b" data-hd="menu" aria-label="Menu">' + IC.menu + '</button>' +
      '<div class="hd-t"><img src="logo-mark.png" alt=""><span style="overflow:hidden;text-overflow:ellipsis">' + esc(o.title || 'Sunpowers Admin') + '</span></div>' +
      '<button type="button" class="hd-b" data-hd="search" aria-label="Search">' + IC.search + '</button>' + (o.filter ? '<button type="button" class="hd-b" data-hd="filter" aria-label="Filter">' + IC.filter + '</button>' : '') +
      '<button type="button" class="hd-b" data-hd="bell" aria-label="Alerts">' + IC.bell + '<span class="hd-dot n hide" data-hd-new>New</span></button>' +
      '<span class="hd-lang"><button type="button" data-sp-lang="short"></button></span></div></div>';
  }
  function closeAll() { ['.hd-ov', '.hd-dr', '.hd-pop', '.hd-sr'].forEach(function (s) { var e = document.querySelector(s); if (e) e.remove(); }); }
  function go(it) { closeAll(); if (it && it.fn) it.fn(); }
  function itemHtml(it, i) { return '<button type="button" class="hd-i' + (it.on ? ' on' : '') + '" data-i="' + i + '"><i>' + it.ic + '</i>' + esc(it.l) + (it.cnt ? '<em>' + esc(it.cnt) + '</em>' : '') + '</button>'; }
  function items() { var r = typeof CFG.items === 'function' ? CFG.items() : CFG.items; return r || []; }
  function drawer() {
    closeAll(); var its = items(), h = '', g = '';
    its.forEach(function (it, i) { if (it.group && it.group !== g) { g = it.group; h += '<div class="hd-g">' + esc(g) + '</div>'; } h += itemHtml(it, i); });
    (CFG.links || []).forEach(function (l) { h += '<a class="hd-i" href="' + esc(l.href) + '" target="_blank" rel="noopener"><i>' + l.ic + '</i>' + esc(l.l) + '</a>'; });
    h += '<button type="button" class="hd-i" data-lo><i>🚪</i>Logout</button>';
    var ov = document.createElement('div'); ov.className = 'hd-ov'; var dr = document.createElement('div'); dr.className = 'hd-dr';
    dr.innerHTML = '<div class="hd-dh"><img src="logo-mark.png" alt=""><span>' + esc(typeof CFG.title === 'function' ? CFG.title() : 'Sunpowers Admin') + '</span><button type="button" data-x aria-label="Close">✕</button></div><div class="hd-dl">' + h + '</div>';
    document.body.appendChild(ov); document.body.appendChild(dr); requestAnimationFrame(function () { ov.classList.add('on'); dr.classList.add('on'); });
    ov.onclick = closeAll; dr.querySelector('[data-x]').onclick = closeAll;
    dr.onclick = function (e) { var b = e.target.closest('[data-i]'); if (b) return go(its[+b.getAttribute('data-i')]); if (e.target.closest('[data-lo]')) { closeAll(); if (CFG.logout) CFG.logout(); } };
  }
  function search() {
    closeAll(); var its = items(), s = document.createElement('div'); s.className = 'hd-sr';
    s.innerHTML = '<div class="hd-sh"><button type="button" data-x>←</button><input type="search" placeholder="Search…" autocomplete="off"></div><div class="hd-dl"></div>';
    document.body.appendChild(s); var inp = s.querySelector('input'), list = s.querySelector('.hd-dl');
    function draw() { var q = inp.value.trim().toLowerCase(), r = its.map(function (it, i) { return [it, i]; }).filter(function (x) { return !q || (x[0].l + ' ' + (x[0].kw || '') + ' ' + (x[0].group || '')).toLowerCase().indexOf(q) >= 0; }); list.innerHTML = r.length ? r.map(function (x) { return itemHtml(x[0], x[1]); }).join('') : '<div class="hd-g">No result</div>'; }
    draw(); inp.oninput = draw; setTimeout(function () { inp.focus(); }, 60);
    s.querySelector('[data-x]').onclick = closeAll; list.onclick = function (e) { var b = e.target.closest('[data-i]'); if (b) go(its[+b.getAttribute('data-i')]); };
  }
  function sig(a) { return a.map(function (x) { return x.t; }).join('|'); }
  function paintBadge() { var bad = ALERTS.filter(function (x) { return x.c !== 'g'; }); document.querySelectorAll('[data-hd-new]').forEach(function (e) { e.classList.toggle('hide', !(bad.length && sig(bad) !== SEEN)); }); }
  function refreshAlerts() { if (!CFG.alerts) return Promise.resolve(); return Promise.resolve().then(CFG.alerts).then(function (a) { ALERTS = a || []; SEEN = ls('sp_hd_seen'); paintBadge(); }).catch(function () {}); }
  function bell() {
    closeAll(); var a = ALERTS.length ? ALERTS : [{ c: 'g', t: '✅ No alerts' }];
    var p = document.createElement('div'); p.className = 'hd-pop al'; p.innerHTML = a.map(function (x) { return '<div class="hd-a ' + x.c + '">' + x.t + '</div>'; }).join('');
    var ov = document.createElement('div'); ov.className = 'hd-ov on'; ov.style.background = 'transparent'; ov.onclick = closeAll; document.body.appendChild(ov); document.body.appendChild(p);
    SEEN = sig(ALERTS.filter(function (x) { return x.c !== 'g'; })); ls('sp_hd_seen', SEEN); paintBadge();
  }
  function filterPop(o) {
    closeAll(); var p = document.createElement('div'); p.className = 'hd-pop';
    p.innerHTML = o.ranges.map(function (r) { return '<button type="button" class="hd-i' + (r[2] ? ' on' : '') + '" data-r="' + r[0] + '"><i>' + (r[2] ? '✔' : '📅') + '</i>' + esc(r[1]) + '</button>'; }).join('');
    var ov = document.createElement('div'); ov.className = 'hd-ov on'; ov.style.background = 'transparent'; ov.onclick = closeAll; document.body.appendChild(ov); document.body.appendChild(p);
    p.onclick = function (e) { var b = e.target.closest('[data-r]'); if (b) { closeAll(); o.pick(b.getAttribute('data-r')); } };
  }
  var SPHDR = window.SPHDR = {
    bar: bar, close: closeAll, refresh: refreshAlerts, setAlerts: function (a) { ALERTS = a || []; SEEN = ls('sp_hd_seen'); paintBadge(); },
    config: function (c) { CFG = Object.assign(CFG, c); },
    bind: function (o) {
      o = o || {}; closeAll();
      document.querySelectorAll('.hd [data-hd]').forEach(function (b) {
        var k = b.getAttribute('data-hd');
        b.onclick = function () { if (k === 'back') { if (o.back) o.back(); } else if (k === 'menu') drawer(); else if (k === 'search') search(); else if (k === 'bell') bell(); else if (k === 'filter' && o.filter) filterPop(o.filter()); };
      });
      paintBadge(); if (window.SPI18N && SPI18N.refresh) try { SPI18N.refresh(); } catch (e) {}
    }
  };
})();
