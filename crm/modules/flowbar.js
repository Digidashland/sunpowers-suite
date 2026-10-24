/* Round 33 — Customer flow bar ("patti").
   Shows ONLY when you open a customer's flow (customer page / project page → Quotation, Site Visit, Blueprint, Billing, Maintenance, Documents …).
   The page opens normally and the bar stays on top. Going straight from the side menu opens the page WITHOUT the bar.
   How: links clicked inside a customer's flow get ?cf=<customer id>&cq=<job (quotation) id> added; no cf/cq in the address = no bar.
   Steps that this job does not use are shown grey; tapping one explains and offers "Naya Kaam" (same customer, nothing re-typed). */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, F = C.FLOW; if (!C || !F) return;
  var WORK = { quote: 1, invoice: 1, sitevisit: 1, blueprint: 1, maintenance: 1, docs: 1, project: 1, billing: 1, plants: 1, plant: 1, commission: 1, payment: 1, payments: 1, quotes: 1, doc: 1 };

  var css = '#fbarTop{position:sticky;top:var(--top,56px);z-index:35;margin:0;border-radius:0;border-width:0 0 1px;box-shadow:0 2px 10px rgba(0,0,0,.06);padding:8px 16px;background:var(--bg,#f6f9f6)}' +
    '#fbarTop[hidden]{display:none!important}' +
    '.fbar{min-width:0;max-width:100%;box-sizing:border-box;width:100%;background:var(--card,#fff);border:1px solid var(--line,#dfe7e0);border-radius:14px;padding:8px 10px;margin:0 0 12px;box-shadow:0 4px 14px rgba(0,0,0,.06)}' +
    '.fb-top{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:6px}.fb-top .fb-cust{font-weight:800;color:inherit;text-decoration:none}.fb-top .grow{flex:1}' +
    '.fb-top select{max-width:min(46vw,300px);font-size:12px;padding:4px 6px}.fb-x{border:0;background:none;font-size:18px;line-height:1;cursor:pointer;color:var(--mut,#66756a);padding:2px 6px}' +
    '.fb-steps{min-width:0;max-width:100%;display:flex;flex-wrap:wrap;gap:4px;padding-bottom:3px}@media(max-width:760px){.fb-steps{flex-wrap:nowrap;overflow-x:auto;-webkit-overflow-scrolling:touch}}' +
    '.fbs{flex:0 0 auto;display:flex;align-items:center;gap:5px;border:1px solid var(--line,#dfe7e0);background:var(--bg,#f6f9f6);border-radius:999px;padding:4px 10px 4px 6px;font:600 11.5px system-ui,sans-serif;color:inherit;cursor:pointer;white-space:nowrap}' +
    '.fbs .d{width:20px;height:20px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;background:var(--c,#1e8e3e);color:#fff;font-size:11px}' +
    '.fbs.done{background:color-mix(in srgb,var(--c,#1e8e3e) 12%,transparent);border-color:color-mix(in srgb,var(--c,#1e8e3e) 40%,transparent)}' +
    '.fbs.now{border-color:var(--c,#1e8e3e);box-shadow:0 0 0 2px color-mix(in srgb,var(--c,#1e8e3e) 25%,transparent)}.fbs.on{outline:2px solid var(--c,#1e8e3e);outline-offset:1px}' +
    '.fbs.todo .d{background:transparent;color:var(--c,#1e8e3e);border:1.5px solid var(--c,#1e8e3e)}' +
    '.fbs.na{opacity:.45}.fbs.na .d{background:#9aa5a0}';
  css += '.fbs.locked{opacity:.5}.fbs-more{display:none;border:1px solid var(--line,#dfe7e0);background:var(--card,#fff);border-radius:999px;padding:4px 10px;font:600 11.5px system-ui,sans-serif;color:inherit;cursor:pointer;white-space:nowrap}' +
    '@media(max-width:760px){.fbs-more{display:inline-block}.fbs.fbs-hide:not(.on):not(.now){display:none}}';
  var st = document.createElement('style'); st.id = 'fbCss'; st.textContent = css; document.head.appendChild(st);

  function qget(name) { var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.hash || ''); return m ? decodeURIComponent(m[1]) : ''; }
  function setParam(hash, k, v) {
    var i = hash.indexOf('?'), base = i < 0 ? hash : hash.slice(0, i), parts = i < 0 ? [] : hash.slice(i + 1).split('&').filter(function (x) { return x && x.split('=')[0] !== k; });
    if (v !== '' && v != null) parts.push(k + '=' + encodeURIComponent(v)); return base + (parts.length ? '?' + parts.join('&') : '');
  }
  function routeOf(h) { return (h || '').replace(/^#\/?/, '').split('?')[0].split('/')[0]; }

  /* ---- 1) links opened from a customer's flow carry the flow along ---- */
  var ctxCf = '', ctxCq = '';
  /* Round 37: quotation page (#/quote/<id>) par bhi upar ki flow patti — neeche ka alag card hata diya */
  function quoteViewId() { var pr = (location.hash || '').replace(/^#\/?/, '').split('?')[0].split('/'); return pr[0] === 'quote' && pr.length === 2 && /^\d+$/.test(pr[1]) ? pr[1] : ''; }
  function currentCtx() {
    var h = location.hash || '', r = routeOf(h), parts = h.replace(/^#\/?/, '').split('?')[0].split('/');
    var cf = qget('cf'), cq = qget('cq');
    if (!cf && !cq && r === 'customer' && parts[1]) { cf = parts[1]; if (C._wfP && String(C._wfP) === String(parts[1]) && C._wfQ) cq = String(C._wfQ); }
    if (!cf && !cq && r === 'project' && parts[1]) cq = parts[1];
    if (!cf && !cq) cq = quoteViewId();
    return { cf: cf, cq: cq };
  }
  function carry(href) {
    var c = currentCtx(); if (!c.cf && !c.cq) return href;
    var r = routeOf(href); if (!WORK[r]) return href;
    if (/[?&]cf=|[?&]cq=/.test(href)) return href;
    if (c.cf) href = setParam(href, 'cf', c.cf);
    if (c.cq) href = setParam(href, 'cq', c.cq);
    return href;
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('#view a[href^="#/"], #view [data-href^="#/"], a[data-lk][href^="#/"]'); if (!a) return;
    if (a.closest('.fbar')) return;                          /* the bar builds its own links */
    var attr = a.hasAttribute('data-href') ? 'data-href' : 'href', h = a.getAttribute(attr), n = carry(h);
    if (n !== h) a.setAttribute(attr, n);
  }, true);

  /* pages that move on by themselves (e.g. after Save) keep the flow; side-menu clicks do not */
  var closing = false, fromMenu = false, lastCtx = { cf: '', cq: '' };
  document.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('.nav a, .mob-nav a, #side a, .brand a, .top a')) fromMenu = true; }, true);
  window.addEventListener('hashchange', function () {
    var h = location.hash || '', r = routeOf(h), had = lastCtx.cf || lastCtx.cq, now = currentCtx();
    if (closing) { closing = false; lastCtx = { cf: '', cq: '' }; return; }
    if (fromMenu) { fromMenu = false; lastCtx = { cf: '', cq: '' }; if (!qget('cf') && !qget('cq')) return; }
    if (had && !qget('cf') && !qget('cq') && WORK[r] && !/^#\/(customers|home|leads)/.test(h)) {
      var n = h; if (lastCtx.cf) n = setParam(n, 'cf', lastCtx.cf); if (lastCtx.cq) n = setParam(n, 'cq', lastCtx.cq);
      try { history.replaceState(null, '', location.pathname + location.search + n); } catch (e) {} lastCtx = { cf: lastCtx.cf, cq: lastCtx.cq }; setTimeout(function () { C.render(); }, 0); return;
    }
    lastCtx = qget('cf') || qget('cq') ? { cf: qget('cf'), cq: qget('cq') } : { cf: '', cq: '' };
  });
  lastCtx = { cf: qget('cf'), cq: qget('cq') };

  /* ---- 2) the bar ---- */
  var seq = 0;
  /* Round 39: patti ab header ke neeche ek hi jagah (permanent). Jo customer aakhri baar khula, wahi dikhta hai — page badalne par bhi. ✕ se band, naya customer khulne par wapas. */
  var LAST = 'sp_fbLast', OFF = 'sp_fbOff', expanded = false;
  /* Round 39: patti sirf customer se judi screens par */
  var SHOW = { customers: 1 };
  function store(k, get, v) { try { if (get) return sessionStorage.getItem(k); if (v == null) sessionStorage.removeItem(k); else sessionStorage.setItem(k, v); } catch (e) {} return null; }
  function lastGet() { try { return JSON.parse(store(LAST, true) || 'null'); } catch (e) { return null; } }
  function hostEl() {
    var h = document.getElementById('fbarTop'); if (h) return h;
    var top = document.querySelector('.main > .top'); if (!top) return null;
    h = document.createElement('div'); h.id = 'fbarTop'; h.className = 'fbar'; h.hidden = true; top.insertAdjacentElement('afterend', h); return h;
  }
  function pickHtml(list, sel) {
    return '<select class="inp" data-fbpick title="Customer chunein" style="max-width:min(60vw,320px)"><option value="">Customer chunein…</option>' + list.map(function (p) { return '<option value="' + p.id + '"' + (String(p.id) === String(sel) ? ' selected' : '') + '>' + esc((p.title || 'Customer') + (p.mobile ? ' · ' + p.mobile : '')) + '</option>'; }).join('') + '</select>';
  }
  function bindPick(host) { host.onchange = function (e) { var s = e.target.closest && e.target.closest('[data-fbpick]'); if (!s) return; store(LAST, false, JSON.stringify({ cf: s.value, cq: '' })); draw(); }; }
  /* Round 41: patti sirf All Customers list par, hamesha dikhti hai. Customer list se chuna jata hai. ✕ / "Sabhi steps" nahi. */
  async function draw() {
    var my = ++seq, host = hostEl(); if (!host) return;
    if (routeOf(location.hash) !== 'customers') { host.hidden = true; host.innerHTML = ''; placeBelow(host); return; }
    var prev = lastGet() || { cf: '', cq: '' }, cf = prev.cf || '', cq = prev.cq || '';
    var parties = await C.list('party', { limit: 3000 }).catch(function () { return []; });
    if (my !== seq || !host.isConnected) return;
    parties = parties.filter(function (p) { return (p.data && p.data.type) !== 'supplier'; }).sort(function (a, b) { return String(a.title || '').localeCompare(String(b.title || '')); });
    host.hidden = false;
    if (!cf) { host.innerHTML = '<div class="fb-top">' + pickHtml(parties, '') + '<span class="xs mute">Upar se customer chunein — uska flow yahan dikhega</span></div>'; bindPick(host); placeBelow(host); return; }
    host.innerHTML = '<div class="xs mute">Customer flow…</div>';
    var g, gp, party;
    try {
      g = await C.call('crm_wf_get', cq ? { id: +cq } : { party_id: +cf });
      var pid = g.party_id || +cf;
      gp = cq ? await C.call('crm_wf_get', { party_id: pid }).catch(function () { return { plants: [] }; }) : g;
      party = pid ? await C.get(pid).catch(function () { return null; }) : null;
      if (my !== seq || !host.isConnected) return;
      var q = g.quote_id || '', ctx = { party_id: pid, quote_id: q }, applicable = {}; g.steps.forEach(function (s) { applicable[s.n] = s; });
      var cur = (g.steps.filter(function (s) { return !s.done; })[0] || {}).n, here = routeOf(location.hash);
      var plants = (gp.plants || []);
      var h = '<div class="fb-top">' + pickHtml(parties, cf) + '<a class="fb-cust" href="#/customer/' + pid + '" title="Customer ka page">👤 ' + esc(party ? party.title : 'Customer') + (party && party.mobile ? ' · <span class="mute">' + esc(party.mobile) + '</span>' : '') + '</a>' + (g.kind ? C.kindPill(g.kind) : '') + (g.ctype ? C.pill(g.ctype, g.ctype === 'Items only' ? 'g' : 'v') : '') +
        (plants.length > 1 ? '<span class="xs mute">Kaam:</span><select class="inp" data-fbjob title="Kaam chunein">' + plants.map(function (p) { return '<option value="' + p.id + '"' + (p.id === q ? ' selected' : '') + '>' + esc((p.ref || '') + ' · ' + (p.ctype || '') + ' · ' + (p.title || '')) + '</option>'; }).join('') + '</select>' : (g.ref ? '<span class="mute xs">' + esc(g.ref) + '</span>' : '')) +
        '<span class="grow"></span></div><div class="fb-steps">';
      var curI = F.ALL.indexOf(cur);
      F.ALL.forEach(function (n, i) {
        var s = applicable[n], cls, mark;
        if (!s) { cls = 'na'; mark = '–'; } else if (s.done) { cls = 'done'; mark = s.skip ? '–' : '✓'; } else { cls = n === cur ? 'now' : 'todo'; mark = F.IC[n] || '•'; }
        var lk = s && F.link(n, ctx); if (lk && routeOf(lk.href) === here) cls += ' on';
        if (lk) { var dfn = lk.href && C.routes ? C.routes[routeOf(lk.href)] : null; if (dfn && dfn.allowed && !dfn.allowed()) cls += ' locked'; }
        if (s && !C.can(stepKey(n))) cls += ' locked';
        h += '<button type="button" class="fbs ' + cls + '" data-fbn="' + n + '" style="--c:' + (F.COL[n] || '#1e8e3e') + '" title="' + esc(F.NAMES[n] || '') + (s ? '' : ' — is kaam ke liye lagu nahi') + '"><span class="d">' + mark + '</span>' + esc(F.NAMES[n] || ('Step ' + n)) + '</button>';
      });
      host.innerHTML = h + '</div>'; bindPick(host);
      placeBelow(host);
      try { var nowEl = $('.fbs.now', host) || $('.fbs.on', host); if (nowEl && nowEl.scrollIntoView && innerWidth <= 760) { var bx = $('.fb-steps', host); bx.scrollLeft = Math.max(0, nowEl.offsetLeft - 40); } } catch (e) {}
      host.onclick = function (e) {
        if (e.target.closest('[data-fbx]')) { store(OFF, false, '1'); store(LAST, false, null); host.hidden = true; host.innerHTML = ''; return; }
        var b = e.target.closest('[data-fbn]'); if (!b) return; var n = +b.getAttribute('data-fbn'), s = applicable[n];
        if (!s) { C.toast((F.NAMES[n] || 'Ye step') + ' is kaam ke liye lagu nahi hai', true); return; }
        if (!C.can(stepKey(n)) || b.classList.contains('locked')) { C.toast('Permission not allowed — Admin se baat karein', true); return; }
        /* Round 39: step chhodne par rok nahi, sirf saaf chetavni (ek line) */
        var pend = F.ALL.filter(function (k) { if (k >= n) return false; var x = applicable[k]; return x && !x.done && !x.skip && k !== 19 && k !== 2; });
        if (pend.length) C.toast('Dhyan: pehle "' + (F.NAMES[pend[0]] || pend[0]) + '" step abhi poora nahi hua', true);
        if (n === 3 && !q) { location.hash = '#/quote/new?party=' + pid + '&ctype=' + encodeURIComponent(g.ctype || 'Residential') + '&cf=' + pid; return; }
        var lk = F.link(n, ctx);
        if (lk) { var hr = lk.href; hr = setParam(hr, 'cf', pid); if (q) hr = setParam(hr, 'cq', q); if (routeOf(hr) === 'quote' && /\/new/.test(hr) && q) hr = '#/quote/' + q + '?cf=' + pid + '&cq=' + q; location.hash = hr; return; }
        C.wfStep(g, s, function () { draw(); });
      };
      try { if (party && party.title) { var pre = party.title + ' — '; if (document.title.indexOf(pre) !== 0) document.title = pre + document.title; } } catch (e) {}
      var mb = $('[data-fbmore]', host); if (mb) mb.onclick = function () { expanded = !expanded; draw(); };
      var sel = $('[data-fbjob]', host); if (sel) sel.onchange = function () { location.hash = setParam(location.hash, 'cq', sel.value); };
    } catch (e) { if (host.isConnected) { host.hidden = true; host.innerHTML = ''; placeBelow(host); } }
  }
  /* Round 40: har step ki alag permission (Admin team me tick karta hai) */
  function stepKey(n) { return 'flow.step.' + n; }
  /* popups band ke NEECHE khulen, band dhakein nahi */
  function placeBelow(host) {
    var on = !host.hidden && host.isConnected, b = document.body;
    if (!on) { b.classList.remove('fb-on'); b.style.removeProperty('--fbar-end'); return; }
    b.classList.add('fb-on'); b.style.setProperty('--fbar-end', Math.ceil(host.getBoundingClientRect().bottom) + 'px');
  }
  window.addEventListener('resize', function () { var h = document.getElementById('fbarTop'); if (h) placeBelow(h); });
  if (!document.getElementById('fbStyle')) { var st = document.createElement('style'); st.id = 'fbStyle'; st.textContent = 'body.fb-on .ov{top:var(--fbar-end,0px);padding-top:12px}'; document.head.appendChild(st); }

  /* a step this job does not use */
  function naStep(n, g, party, pid) {
    var name = F.NAMES[n] || ('Step ' + n), proj = g.kind === 'project', nm = party ? party.title : 'Customer';
    var body = '<p><b>' + esc(name) + '</b> ' + (proj ? 'is type (' + esc(g.ctype || 'Project') + ') ke kaam me nahi aata.' : 'Project (plant) ka step hai — ye ' + (g.kind === 'service' ? 'Service' : 'Product') + ' kaam hai, isliye abhi grey hai.') + '</p>' +
      (proj ? '' : '<p class="xs mute">' + esc(nm) + ' ko plant lagwana ho to nayi details nahi bharni — ye hi customer rahega, bas ek <b>naya Project kaam</b> shuru hoga. Purana ' + (g.ref ? esc(g.ref) + ' ' : '') + 'kaam jaisa hai waisa hi rahega.</p>');
    var foot = '<button class="btn btn-o" data-close>Band</button>' + (proj ? '' : (g.quote_id ? '<a class="btn btn-o" data-go href="#/quote/' + g.quote_id + '?cf=' + pid + '&cq=' + g.quote_id + '">Is kaam ka type badlein</a>' : '') + (C.can('quotes.create') ? '<a class="btn btn-p" data-go href="#/quote/new?party=' + pid + '&ctype=Residential&cf=' + pid + '">➕ Naya Project kaam shuru karein</a>' : ''));
    var m = C.modal({ title: name + ' — lagu nahi', size: 'sm', body: body, foot: foot });
    $$('[data-go]', m.el).forEach(function (a) { a.onclick = function () { m.close(); }; });
  }

  /* hook into the page render (hints.js defines C.addHint after us in load order, so we wrap whatever is there at render time) */
  function install() {
    var prev = C.addHint;
    C.addHint = function (view, name) { try { if (prev) prev(view, name); } finally { try { draw(); } catch (e) {} } };
  }
  if (C.addHint) install(); else { var t = setInterval(function () { if (C.addHint) { clearInterval(t); install(); } }, 50); setTimeout(function () { clearInterval(t); if (!C.addHint) { C.addHint = function () { draw(); }; } }, 4000); }
  C.flowbar = { draw: draw, carry: carry };
})();
