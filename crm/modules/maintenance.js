/* Maintenance & AMC Packages
   - Plans and checklist items live in the INVENTORY (Items): edit / delete / add from here or from Products & Projects → "Maintenance & AMC".
   - A contract = one customer + one plan. Every visit is a reminder (shows in "Aaj ke kaam"). When a visit is marked done the
     materials used are taken out of stock and the next visit date moves forward from the real service date. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = function (v) { return parseFloat(v) || 0; };
  var PER = { one: ['Ek baar (one-time)', 0, 1], monthly: ['Har mahine', 1, 12], quarterly: ['Quarterly (har 3 mahine)', 3, 4], half: ['Half-yearly (har 6 mahine)', 6, 2], yearly: ['Yearly (saal me 1 baar)', 12, 1] };
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var ST = { overdue: ['Overdue', 'r'], soon: ['Jaldi due', 'o'], upcoming: ['Aane wali', 'b'], complete: ['Poori ho gayi', ''] };

  function allItems() { return C.list('item', { limit: 3000 }); }
  var ORDER = ['random', 'recommended', 'valuable', 'tension', 'best'];
  function plansOf(a) { return a.filter(function (x) { return (x.data.type || '') === 'maintenance' && x.status !== 'inactive'; }).sort(function (a, b) { var i = ORDER.indexOf(a.data.plan_code), j = ORDER.indexOf(b.data.plan_code); return (i < 0 ? 99 : i) - (j < 0 ? 99 : j) || a.id - b.id; }); }
  function checksOf(a) { return a.filter(function (x) { return (x.data.type || '') === 'mcheck' && x.status !== 'inactive'; }); }
  function visits() { return C.list('reminder', { limit: 3000 }).then(function (a) { return a.filter(function (x) { return x.data && x.data.maint; }); }); }
  function perOf(d) { var p = PER[d.period]; return p || (d.visits >= 12 ? PER.monthly : d.visits >= 4 ? PER.quarterly : d.visits >= 2 ? PER.half : PER.yearly); }
  function visitsTotal(d) { if (d.period === 'one') return 1; var p = perOf(d); return Math.max(1, Math.ceil(p[2] * Math.max(1, num(d.years) || 1))); }

  function groups(V) {
    var g = {}, t0 = C.today(), t7 = C.addDays(t0, 7);
    V.forEach(function (v) {
      var d = v.data, k = d.contract_id || ('L' + v.party_id + '-' + (d.plan_name || ''));
      (g[k] = g[k] || { key: k, party_id: v.party_id, party: d.party_name || v.title, mobile: v.mobile || d.mobile || '', plan: d.plan_name || 'Maintenance', free: !!d.free, visits: [] }).visits.push(v);
    });
    return Object.keys(g).map(function (k) {
      var c = g[k];
      c.visits.sort(function (a, b) { return (num(a.data.visit_no) - num(b.data.visit_no)) || String(a.due_at).localeCompare(String(b.due_at)); });
      var open = c.visits.filter(function (x) { return x.status !== 'done'; }), done = c.visits.filter(function (x) { return x.status === 'done'; });
      c.open = open; c.done = done; c.next = open[0] || null; c.total = c.visits.length;
      c.last = done.reduce(function (m, x) { var s = x.data.done_on || x.due_at || ''; return s > m ? s : m; }, '');
      c.status = !c.next ? 'complete' : c.next.due_at < t0 ? 'overdue' : c.next.due_at <= t7 ? 'soon' : 'upcoming';
      c.cost = done.reduce(function (m, x) { return m + num(x.data.done_cost); }, 0);
      return c;
    }).sort(function (a, b) { return String(a.next ? a.next.due_at : '9999').localeCompare(String(b.next ? b.next.due_at : '9999')); });
  }

  function waText(c, v) { return 'Namaste ' + c.party + ' ji 🙏\n' + (C.company().name || 'Sunpowers') + ' se — aapke solar plant ki *' + c.plan + '* service ' + C.fd(v.due_at) + ' ko due hai. Kya hum aa sakte hain? Aapko jo samay theek lage bata dein.'; }

  C.mod('maintenance', {
    title: 'Maintenance & AMC Packages',
    allowed: function () { return C.canAny('items.view', 'reminders.view_all', 'customers.create', 'customers.view_all'); },
    render: async function (el, params, q) {
      var tab = ['cal', 'plans', 'checks'].indexOf(q && q.tab) >= 0 ? q.tab : 'dash', canEdit = C.can('items.create');
      var sub = { dash: 'Kis customer ne kaunsa package liya, last service kab hui aur agli kab due hai.', cal: 'Mahine aur saal ke hisab se aane wali maintenance aur audit ki tareekhein.', plans: 'Packages (plans) — kya-kya shamil hai, kitne periods me aur kitne ka. Ye Inventory ka hissa hai.', checks: 'Checklist items — har kaam ka apna cost aur (agar lage) stock ka maal. Ye Inventory ka hissa hai.' }[tab];
      var h = '<div class="ph"><div><h1>Maintenance &amp; AMC Packages</h1><p>' + esc(sub) + '</p></div><div class="acts">' +
        (tab === 'plans' ? '<span class="pill">🔒 5 Fixed plans — sirf Admin keemat / kaam ki list badal sakta hai</span>' :
          tab === 'checks' ? (canEdit ? '<button class="btn btn-p" data-act="newcheck">' + C.ic('plus') + ' Naya checklist item</button>' : '') :
            '<button class="btn btn-p" data-act="newcontract">' + C.ic('plus') + ' Customer ko plan dein</button>') + '</div></div>' +
        '<div class="tabs"><button data-tab="dash" class="' + (tab === 'dash' ? 'on' : '') + '">Dashboard</button><button data-tab="cal" class="' + (tab === 'cal' ? 'on' : '') + '">Calendar</button><button data-tab="plans" class="' + (tab === 'plans' ? 'on' : '') + '">Plans (Inventory)</button><button data-tab="checks" class="' + (tab === 'checks' ? 'on' : '') + '">Checklist items (Inventory)</button></div>';
      var ALL = [], V = [];
      try { ALL = await allItems(); if (tab === 'dash' || tab === 'cal') V = await visits(); } catch (e) { return void (el.innerHTML = h + '<div class="card">' + esc(e.message) + '</div>'); }
      var G = groups(V), P = plansOf(ALL), K = checksOf(ALL);

      if (tab === 'dash') h += dashHtml(G, q);
      else if (tab === 'cal') h += calHtml(V, G, q);
      else if (tab === 'plans') h += plansHtml(P, K);
      else h += checksHtml(K, ALL);

      el.innerHTML = h;
      if (q.party && C._mOpened !== String(q.party)) { C._mOpened = String(q.party); C.get(q.party).then(function (pp) { contractForm(pp, P, K); }).catch(function () {}); } else if (!q.party) C._mOpened = '';
      $$('[data-tab]', el).forEach(function (b) { b.onclick = function () { C.go('#/maintenance' + C.qs({ tab: b.getAttribute('data-tab') === 'dash' ? '' : b.getAttribute('data-tab') })); }; });
      var cs = $('[data-q]', el), lst = $('#mlist', el); if (cs && lst) C.filterList(cs, lst);
      $$('[data-st]', el).forEach(function (b) { b.onclick = function () { C.go('#/maintenance' + C.qs({ st: b.getAttribute('data-st') })); }; });
      var ms = $('#cmon', el), ys = $('#cyear', el); if (ms && ys) { var go = function () { C.go('#/maintenance' + C.qs({ tab: 'cal', ym: ys.value + '-' + ms.value })); }; ms.onchange = go; ys.onchange = go; }
      C.bind(el, {
        newplan: function () { planForm(null, K); },
        editplan: function (id) { planForm(P.find(function (x) { return String(x.id) === id; }), K); },
        newcheck: function () { checkForm(null); },
        editcheck: function (id) { checkForm(K.find(function (x) { return String(x.id) === id; })); },
        newcontract: function () { contractForm(null, P, K); },
        open: function (id, a, e) { if (e.target.closest('a,button.btn')) return; var c = G.find(function (x) { return x.key === id; }); if (c) contractView(c, P, K); },
        done: function (id) { var c = G.find(function (x) { return x.key === id; }); if (c && c.next) doneForm(c, c.next, K); },
        day: function (d) { dayView(d, V, G, K); },
        cur: function () { C.go('#/maintenance?tab=cal'); }
      });
    }
  });

  /* ------------------------------------------------------------ dashboard */
  function dashHtml(G, q) {
    var st = (q && q.st) || '', t0 = C.today(), mo = t0.slice(0, 7);
    var cnt = { overdue: 0, soon: 0, upcoming: 0, complete: 0 }; G.forEach(function (c) { cnt[c.status]++; });
    var doneM = 0, costM = 0; G.forEach(function (c) { c.done.forEach(function (x) { if ((x.data.done_on || '').slice(0, 7) === mo) { doneM++; costM += num(x.data.done_cost); } }); });
    var h = '<div class="kpis">' + C.kpi('Active packages', G.length - cnt.complete, G.length + ' total customers', 'gold', '', 'settings') + C.kpi('Overdue', cnt.overdue, 'Tareekh nikal gayi', cnt.overdue ? 'warn' : '', '', 'clock') +
      C.kpi('7 din me due', cnt.soon, 'Reminder bhejein', cnt.soon ? 'warn' : '', '', 'today') + C.kpi('Is mahine ho gayi', doneM, 'Service cost ' + money(costM), '', '', 'check') + '</div>';
    var list = G.filter(function (c) { return !st || c.status === st; });
    h += '<div class="bar">' + C.chips([['', 'Sab', G.length], ['overdue', 'Overdue', cnt.overdue], ['soon', '7 din me', cnt.soon], ['upcoming', 'Aane wali', cnt.upcoming], ['complete', 'Poori', cnt.complete]], st, 'st') + '<input class="inp" type="search" data-q placeholder="Customer / plan khojein"></div>';
    h += list.length ? '<div class="list" id="mlist">' + list.map(function (c) {
      var s = ST[c.status], nx = c.next;
      return '<div class="li click" data-act="open" data-id="' + esc(c.key) + '"><span class="av ' + (c.status === 'overdue' ? 'r' : '') + '">' + C.ic('settings') + '</span><span class="grow"><span class="t">' + esc(c.party) + ' ' + C.pill(s[0], s[1]) + '</span>' +
        '<span class="m"><span>' + esc(c.plan) + (c.free ? ' · ' + C.pill('FREE', '') : '') + '</span><span>Last service: ' + (c.last ? C.fd(c.last) : '—') + '</span><span><b>Next due: ' + (nx ? C.fd(nx.due_at) : '—') + '</b></span><span>' + c.done.length + '/' + c.total + ' visits</span>' + (c.status === 'complete' ? '<span class="xs mute">Plan poora — dobara plan lene ke liye kholein</span>' : '') + '</span></span>' +
        '<span class="acts">' + (nx && c.mobile ? '<a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(c.mobile, waText(c, nx))) + '">WhatsApp</a>' : '') + (nx ? '<button class="btn btn-p btn-sm" data-act="done" data-id="' + esc(c.key) + '">Visit ho gayi</button>' : '') + '</span></div>';
    }).join('') + '</div>' : '<div class="card">' + C.empty('settings', G.length ? 'Is filter me koi nahi' : 'Abhi kisi customer ne package nahi liya', G.length ? '' : '"Customer ko plan dein" dabayein — naye aur purane dono customers ko plan de sakte hain.') + '</div>';
    return h;
  }

  /* ------------------------------------------------------------ calendar */
  function calHtml(V, G, q) {
    var t0 = C.today(), ym = /^\d{4}-\d{2}$/.test((q && q.ym) || '') ? q.ym : t0.slice(0, 7), y = +ym.slice(0, 4), m = +ym.slice(5, 7);
    var by = {}; V.forEach(function (v) { if (v.due_at) (by[v.due_at] = by[v.due_at] || []).push(v); });
    var first = new Date(y, m - 1, 1), lead = (first.getDay() + 6) % 7, days = new Date(y, m, 0).getDate(), cells = [];
    for (var i = 0; i < lead; i++) cells.push('<div class="cal-c off"></div>');
    for (var d = 1; d <= days; d++) {
      var ds = y + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0'), a = by[ds] || [];
      var chips = a.slice(0, 2).map(function (v) { var late = v.status !== 'done' && v.due_at < t0; return '<span class="cal-e ' + (v.status === 'done' ? 'ok' : late ? 'late' : '') + '">' + esc(String(v.data.party_name || v.title).split(' ')[0]) + '</span>'; }).join('');
      cells.push('<div class="cal-c' + (ds === t0 ? ' today' : '') + (a.length ? ' has' : '') + '"' + (a.length ? ' data-act="day" data-id="' + ds + '"' : '') + '><b>' + d + '</b>' + chips + (a.length > 2 ? '<span class="cal-more">+' + (a.length - 2) + '</span>' : '') + '</div>');
    }
    var yrs = []; for (var yy = y - 2; yy <= y + 8; yy++) yrs.push(yy);
    var h = '<div class="card"><div class="row wrap" style="margin-bottom:12px;gap:8px"><a class="btn btn-o btn-sm" href="#/maintenance?tab=cal&ym=' + shift(y, m, -1) + '">‹</a>' +
      '<select class="inp" id="cmon" style="width:auto">' + MON.map(function (n, i) { return '<option value="' + String(i + 1).padStart(2, '0') + '"' + (i + 1 === m ? ' selected' : '') + '>' + n + '</option>'; }).join('') + '</select>' +
      '<select class="inp" id="cyear" style="width:auto">' + yrs.map(function (n) { return '<option' + (n === y ? ' selected' : '') + '>' + n + '</option>'; }).join('') + '</select>' +
      '<a class="btn btn-o btn-sm" href="#/maintenance?tab=cal&ym=' + shift(y, m, 1) + '">›</a><button class="btn btn-g btn-sm" data-act="cur">Aaj</button>' +
      '<span class="hint" style="margin-left:auto"><span class="cal-e">Aane wali</span> <span class="cal-e late">Overdue</span> <span class="cal-e ok">Ho gayi</span></span></div>' +
      '<div class="cal-g"><div class="cal-h">Mon</div><div class="cal-h">Tue</div><div class="cal-h">Wed</div><div class="cal-h">Thu</div><div class="cal-h">Fri</div><div class="cal-h">Sat</div><div class="cal-h">Sun</div>' + cells.join('') + '</div></div>';
    // next 12 months overview
    var ov = [], cur = new Date(); for (var k = 0; k < 12; k++) {
      var dt = new Date(cur.getFullYear(), cur.getMonth() + k, 1), key = dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0'), n = V.filter(function (v) { return v.status !== 'done' && (v.due_at || '').slice(0, 7) === key; }).length;
      ov.push('<a class="li" href="#/maintenance?tab=cal&ym=' + key + '"><span class="grow"><span class="t">' + MON[dt.getMonth()] + ' ' + dt.getFullYear() + '</span></span><span class="amt">' + n + ' visit' + (n === 1 ? '' : 's') + '</span></a>');
    }
    h += '<div class="sec-t" style="margin-top:16px">Agle 12 mahine</div><div class="list">' + ov.join('') + '</div>';
    return h;
  }
  function shift(y, m, n) { var d = new Date(y, m - 1 + n, 1); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0'); }

  function dayView(ds, V, G, K) {
    var a = V.filter(function (v) { return v.due_at === ds; });
    var body = '<div class="list">' + a.map(function (v) {
      var c = G.find(function (x) { return x.visits.indexOf(v) >= 0; }) || { party: v.data.party_name || v.title, plan: v.data.plan_name, mobile: v.mobile, key: '' };
      return '<div class="li"><span class="grow"><span class="t">' + esc(c.party) + ' ' + (v.status === 'done' ? C.pill('Ho gayi', '') : '') + '</span><span class="m"><span>' + esc(c.plan || '') + '</span><span>Visit ' + esc(v.data.visit_no || '') + '/' + esc(v.data.visits_total || '') + '</span></span></span>' +
        '<span class="acts">' + (c.mobile && v.status !== 'done' ? '<a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(c.mobile, waText(c, v))) + '">WhatsApp</a>' : '') + (v.status !== 'done' ? '<button class="btn btn-p btn-sm" data-do="' + v.id + '">Visit ho gayi</button>' : '') + '</span></div>';
    }).join('') + '</div>';
    var m = C.modal({ title: C.fd(ds) + ' — ' + a.length + ' visit', body: body, size: 'wide' });
    m.el.addEventListener('click', function (e) { var b = e.target.closest('[data-do]'); if (!b) return; var v = a.find(function (x) { return String(x.id) === b.getAttribute('data-do'); }), c = G.find(function (x) { return x.visits.indexOf(v) >= 0; }); if (v && c) { m.close(); doneForm(c, v, K); } });
  }

  /* ------------------------------------------------------------ plans (Inventory) */
  function plansHtml(P, K) {
    var kc = {}; K.forEach(function (k) { kc[k.id] = k; });
    return P.length ? '<div class="list">' + P.map(function (x) {
      var d = x.data, ck = (d.checklist || []).map(function (i) { return kc[i]; }).filter(Boolean), vc = ck.reduce(function (m, k) { return m + num(k.data.cost); }, 0), p = perOf(d);
      return '<div class="li click" data-act="editplan" data-id="' + x.id + '"><span class="av">' + C.ic('settings') + '</span><span class="grow"><span class="t">' + esc(x.title) + (d.fixed ? ' <span class="pill" title="Cycle aur duration lock hai">🔒 Fixed</span>' : '') + (d.free || num(d.price) === 0 ? ' ' + C.pill('FREE', '') : '') + '</span>' +
        '<span class="m"><span>' + esc(p[0]) + '</span><span>' + visitsTotal(d) + ' visits / ' + (num(d.years) || 1) + ' saal</span><span>' + ck.length + ' kaam · ek visit ka cost ' + money(vc) + '</span></span>' +
        (ck.length ? '<span class="m"><span class="xs mute">' + esc(ck.map(function (k) { return k.title; }).join(' • ')) + '</span></span>' : '') + '</span><span class="amt">' + (num(d.price) === 0 ? 'Free' : money(d.price) + '<small>+ GST ' + esc(d.gst || 0) + '%</small>') + '</span></div>';
    }).join('') + '</div>' : '<div class="card">' + C.empty('settings', 'Abhi koi plan nahi', 'Plan banayein — jaise "Silver AMC" ya "Free Basic Check".') + '</div>';
  }
  function checksHtml(K, ALL) {
    var by = {}; ALL.forEach(function (x) { by[x.id] = x; });
    return K.length ? '<div class="list">' + K.map(function (x) {
      var d = x.data, mat = d.material_item_id ? by[d.material_item_id] : null;
      return '<div class="li click" data-act="editcheck" data-id="' + x.id + '"><span class="av v">' + C.ic('check') + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(d.desc || '') + '</span>' +
        (mat ? '<span>Maal: ' + esc(mat.title) + ' × ' + esc(d.material_qty || 1) + (mat.data.stock != null ? ' (stock ' + esc(mat.data.stock) + ')' : '') + '</span>' : '') + '</span></span><span class="amt">' + money(d.cost) + '</span></div>';
    }).join('') + '</div>' : '<div class="card">' + C.empty('check', 'Koi checklist item nahi', '"Naya checklist item" dabayein — jaise Panel cleaning, Earthing test.') + '</div>';
  }

  function planForm(rec, K) {
    if (rec && rec.data.fixed && !C.isAdmin()) return C.toast('Ye Fixed plan hai — sirf Admin keemat ya kaam ki list badal sakta hai. Koi recommendation/badlav nahi.', true);
    var d = Object.assign({ gst: 18, period: 'half', years: 1, price: '', free: false, checklist: [] }, rec ? rec.data : {}), isNew = !rec, chosen = {};
    (d.checklist || []).forEach(function (i) { chosen[i] = 1; });
    var fx = !!(rec && rec.data.fixed), lk = fx ? ' disabled' : '';
    var m = C.modal({ title: isNew ? 'Naya Maintenance & AMC plan' : (fx ? '🔒 Fixed plan — ' + rec.title : 'Plan badlein'), size: 'wide', body: '<form id="mpf" class="fg">' + (fx ? '<div class="note full">Is plan ka naam, cycle aur duration lock hai. Sirf <b>keemat</b> aur <b>kaun-kaun se kaam shamil hain</b> badal sakte hain — naye customers par lagu hoga; jisko plan mil chuka hai uska plan nahi badlega.</div>' : '') +
      C.f('Plan ka naam *', C.inp('name', rec ? rec.title : '', 'maxlength="160" placeholder="Jaise: Silver AMC (3 kW tak)"' + lk), 'full') +
      C.f('Kitne periods me', C.sel('period', Object.keys(PER).map(function (k) { return [k, PER[k][0]]; }), d.period, null, lk)) + C.f('Kitne saal ka', C.inp('years', d.years, 'inputmode="numeric"' + lk)) +
      '<div class="f full"><label class="ck"><input type="checkbox" name="free"' + (d.free || (rec && num(d.price) === 0) ? ' checked' : '') + '> <b>Free plan</b> (Rs 0 — customer se paisa nahi)</label></div>' +
      C.f('Package ki keemat (₹, bina GST)', C.inp('price', d.price, 'inputmode="decimal"') + '<span class="hint" id="psug"></span>') + C.f('GST %', C.sel('gst', [['0', '0%'], ['5', '5%'], ['12', '12%'], ['18', '18%'], ['28', '28%']], String(d.gst))) +
      '<div class="f full"><label>Isme kaun-kaun se kaam shamil hain (Inventory ke Checklist items)</label><div class="list" id="mck" style="max-height:34vh;overflow:auto">' + (K.length ? K.map(function (k) {
        return '<label class="li" style="cursor:pointer"><input type="checkbox" data-ck="' + k.id + '"' + (chosen[k.id] ? ' checked' : '') + '><span class="grow"><span class="t">' + esc(k.title) + '</span><span class="m"><span>' + esc(k.data.desc || '') + '</span></span></span><span class="amt">' + money(k.data.cost) + '</span></label>';
      }).join('') : '<div class="note">Pehle "Checklist items" tab me kaam jodein.</div>') + '</div></div>' +
      '<div class="full xs mute" id="msum"></div></form>',
      foot: (isNew || !C.can('items.delete') ? '' : '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + '</button>') + '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>' });
    var f = $('#mpf', m.el);
    function calc() {
      var ids = $$('[data-ck]:checked', m.el).map(function (x) { return +x.getAttribute('data-ck'); }), vc = 0;
      K.forEach(function (k) { if (ids.indexOf(k.id) >= 0) vc += num(k.data.cost); });
      var per = PER[f.period.value] || PER.half, tv = Math.max(1, Math.ceil(per[2] * Math.max(1, num(f.years.value) || 1))), sug = Math.round(vc * tv);
      f.price.disabled = f.free.checked; if (f.free.checked) f.price.value = 0;
      $('#psug', m.el).textContent = ' Suggested (kaam ka cost × visits): ' + money(sug);
      $('#msum', m.el).textContent = tv + ' visits · ek visit ka cost ' + money(vc) + ' · poore package ka asli kharcha ' + money(vc * tv) + (f.free.checked ? ' (Free — ye aapka kharcha hoga)' : '');
      return { ids: ids, sug: sug };
    }
    m.el.addEventListener('change', function () { calc(); }); m.el.addEventListener('input', function (e) { if (e.target.name === 'years') calc(); }); var c0 = calc();
    if (isNew && !f.price.value && !f.free.checked) f.price.value = '';
    var del = $('[data-del]', m.el); if (del) del.onclick = async function () { if (await C.delWithReason(rec, rec.title)) { m.close(); C.cache.items = null; C.render(); } };
    $('[data-ok]', m.el).onclick = async function () {
      var o = C.form(f); if (fx) { o.name = rec.title; o.period = rec.data.period; o.years = rec.data.years; } if (!C.need(f, ['name'])) return; var cc = calc(), free = !!f.free.checked, price = free ? 0 : C.r2(o.price);
      if (!free && !(price > 0)) return C.toast('Keemat likhein, ya "Free plan" chunein', true);
      if (!cc.ids.length) return C.toast('Kam se kam 1 kaam chunein', true);
      var per = PER[o.period] || PER.half, names = K.filter(function (k) { return cc.ids.indexOf(k.id) >= 0; }).map(function (k) { return k.title; });
      try {
        await C.save('item', rec ? rec.id : null, Object.assign({}, rec ? rec.data : {}, { type: 'maintenance', name: o.name, title: '', category: 'Maintenance', price: price, gst: num(o.gst), unit: 'Plan', period: o.period, years: Math.max(1, Math.round(num(o.years)) || 1), visits: per[2], free: free, checklist: cc.ids, desc: names.join('\n') }), { status: 'active' });
        C.cache.items = null; m.close(); C.render();
      } catch (e) {}
    };
  }

  function checkForm(rec) {
    var d = Object.assign({ cost: '', material_item_id: '', material_qty: 1, desc: '' }, rec ? rec.data : {}), isNew = !rec, mat = { id: d.material_item_id || '', name: '' };
    var m = C.modal({ title: isNew ? 'Naya checklist item' : 'Checklist item badlein', size: 'wide', body: '<form id="mcf2" class="fg">' +
      C.f('Kaam ka naam *', C.inp('name', rec ? rec.title : '', 'maxlength="160" placeholder="Jaise: Earthing resistance test"'), 'full') +
      C.f('Is kaam ka cost (₹) *', C.inp('cost', d.cost, 'inputmode="decimal"')) + C.f('Detail (customer ko dikhane ke liye)', C.inp('desc', d.desc, 'maxlength="200"')) +
      '<div class="f full"><label>Isme lagne wala maal (Inventory se) <span class="o">(zaroori nahi)</span></label><div class="row wrap"><button type="button" class="btn btn-o" data-mat>' + C.ic('box') + ' <span id="matn">' + (mat.id ? 'Maal badlein' : 'Maal chunein') + '</span></button><button type="button" class="btn btn-g btn-sm" data-matx' + (mat.id ? '' : ' hidden') + '>Hatao</button></div></div>' +
      C.f('Ek visit me kitna maal lagega (qty)', C.inp('material_qty', d.material_qty, 'inputmode="decimal"')) + '</form>',
      foot: (isNew || !C.can('items.delete') ? '' : '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + '</button>') + '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>' });
    var f = $('#mcf2', m.el);
    if (mat.id) C.get(mat.id).then(function (r) { $('#matn', m.el).textContent = r.title; }).catch(function () {});
    $('[data-mat]', m.el).onclick = async function () { var it = await C.itemPick('product', false); if (it) { mat = { id: it.id, name: it.title }; $('#matn', m.el).textContent = it.title; $('[data-matx]', m.el).hidden = false; } };
    $('[data-matx]', m.el).onclick = function () { mat = { id: '', name: '' }; $('#matn', m.el).textContent = 'Maal chunein'; this.hidden = true; };
    var del = $('[data-del]', m.el); if (del) del.onclick = async function () { if (await C.delWithReason(rec, rec.title)) { m.close(); C.cache.items = null; C.render(); } };
    $('[data-ok]', m.el).onclick = async function () {
      var o = C.form(f); if (!C.need(f, ['name', 'cost'])) return;
      try {
        await C.save('item', rec ? rec.id : null, Object.assign({}, rec ? rec.data : {}, { type: 'mcheck', name: o.name, title: '', category: 'Maintenance & Audit', price: C.r2(o.cost), cost: C.r2(o.cost), unit: 'Visit', gst: 18, desc: o.desc, material_item_id: mat.id ? String(mat.id) : '', material_qty: mat.id ? (num(o.material_qty) || 1) : 0 }), { status: 'active' });
        C.cache.items = null; m.close(); C.render();
      } catch (e) {}
    };
  }

  /* ------------------------------------------------------------ give a plan to a customer (new or existing) */
  C.maintAssign = async function (party) { var A = []; try { A = await allItems(); } catch (e) { return C.toast(e.message, true); } return contractForm(party, plansOf(A), checksOf(A)); };

  async function contractForm(party0, P, K, plan0) {
    var party = party0 || null, kc = {}; K.forEach(function (k) { kc[k.id] = k; });
    if (!P.length) return C.toast('Pehle Maintenance & AMC → Plans me koi plan banayein', true);
    var m = C.modal({ title: 'Customer ko Maintenance & AMC plan dein', size: 'wide', body: '<form id="mcf" class="fg">' +
      C.f('Customer * (naya ya purana)', '<button type="button" class="btn btn-o" data-pp style="justify-content:flex-start">' + C.ic('users') + '<span class="ellip">' + (party ? esc(party.title + ' · ' + (party.mobile || '')) : 'Customer chunein') + '</span></button>', 'full') +
      C.f('Plan *', C.sel('plan', P.map(function (p) { return [String(p.id), p.title + (num(p.data.price) === 0 ? ' (FREE)' : ' — ' + money(p.data.price))]; }), String(plan0 || P[0].id)), 'full') +
      C.f('Pehli visit ki tareekh *', C.inp('start', C.addDays(C.today(), 30), 'type="date"')) +
      C.f('Visit ka time', C.inp('time', '10:00', 'type="time"')) +
      '<div class="full" id="mcn"></div></form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Visits schedule karein</button>' });
    var f = $('#mcf', m.el);
    function info() {
      var p = P.find(function (x) { return String(x.id) === f.plan.value; }); if (!p) return; var d = p.data, cyc = d.period || 'half', tv = visitsTotal(d), ck = (d.checklist || []).map(function (i) { return kc[i]; }).filter(Boolean), vc = ck.reduce(function (s, k) { return s + num(k.data.cost); }, 0);
      $('#mcn', m.el).innerHTML = '<div class="note g"><b>' + esc(p.title) + '</b> ' + (num(d.price) === 0 ? C.pill('FREE', '') : '') + '<br>' + esc((PER[cyc] || PER.half)[0]) + ' · ' + tv + ' visit' + (tv > 1 ? 's' : '') + (cyc === 'one' ? ' · agli due date nahi' : ' · ' + (num(d.years) || 1) + ' saal') + '<br>' +
        '<ul style="margin:6px 0 0 18px">' + ck.map(function (k) { return '<li>' + esc(k.title) + ' — ' + money(k.data.cost) + (k.data.material_item_id ? ' (maal stock se kategi)' : '') + '</li>'; }).join('') + '</ul>' +
        '<div class="sm" style="margin-top:6px">Ek visit ka cost ' + money(vc) + ' · Customer se: ' + (num(d.price) === 0 ? 'Rs 0 (Free)' : money(d.price) + ' + GST ' + esc(d.gst || 0) + '%') + '</div></div>';
    }
    f.plan.onchange = info; info();
    $('[data-pp]', m.el).onclick = async function () { var p = await C.partyPick(); if (!p) return; party = p; $('[data-pp] span', m.el).textContent = p.title + ' · ' + (p.mobile || ''); };
    $('[data-ok]', m.el).onclick = async function () {
      if (!party) return C.toast('Customer chunein', true);
      var o = C.form(f); if (!C.need(f, ['start'])) return;
      try {
        var r = await C.run('crm_maint_contract', { party_id: party.id, plan_id: +o.plan, start: o.start, time: o.time || '', assigned_to: C.me.id }, null);
        C.toast(r.visits + ' visits schedule ho gayi ✔'); m.close(); C.go('#/maintenance'); C.render();
      } catch (e) {}
    };
  }

  /* ------------------------------------------------------------ contract details + visit done */
  function contractView(c, P, K) {
    var plan = P.find(function (p) { return c.visits[0] && String(p.id) === String(c.visits[0].data.plan_id); });
    var ck = (c.visits[0] && c.visits[0].data.checks) || [];
    var body = '<div class="fg" style="margin-bottom:12px"><div><div class="xs mute">Customer</div><b>' + esc(c.party) + '</b></div><div><div class="xs mute">Plan</div><b>' + esc(c.plan) + '</b> ' + (c.free ? C.pill('FREE', '') : '') + '</div>' +
      '<div><div class="xs mute">Last service</div><b>' + (c.last ? C.fd(c.last) : '—') + '</b></div><div><div class="xs mute">Next due</div><b>' + (c.next ? C.fd(c.next.due_at) : '—') + '</b></div>' +
      '<div><div class="xs mute">Period</div><b>' + esc((plan ? perOf(plan.data)[0] : (c.visits[0] && c.visits[0].data.months ? 'Har ' + c.visits[0].data.months + ' mahine' : ''))) + '</b></div><div><div class="xs mute">Ab tak ka service cost</div><b>' + money(c.cost) + '</b></div></div>' +
      (ck.length ? '<div class="sec-t">Isme kya-kya shamil hai</div><ul style="margin:0 0 12px 18px">' + ck.map(function (k) { return '<li>' + esc(k.name) + ' — ' + money(k.cost) + '</li>'; }).join('') + '</ul>' : '') +
      '<div class="sec-t">Saari visits</div><div class="list">' + c.visits.map(function (v) {
        var late = v.status !== 'done' && v.due_at < C.today();
        return '<div class="li"><span class="grow"><span class="t">Visit ' + esc(v.data.visit_no || '') + ' — ' + C.fd(v.due_at) + ' ' + (v.status === 'done' ? C.pill('Ho gayi ' + C.fd(v.data.done_on || v.due_at), '') : late ? C.pill('Overdue', 'r') : '') + '</span>' + (v.data.done_note ? '<span class="m"><span>' + esc(v.data.done_note) + '</span></span>' : '') + '</span>' +
          '<span class="acts">' + (v.status === 'done' ? '<button class="btn btn-o btn-sm" data-rep="' + v.id + '">Report</button>' : '<button class="btn btn-o btn-sm" data-mv="' + v.id + '">Tareekh badlein</button><button class="btn btn-p btn-sm" data-dn="' + v.id + '">Visit ho gayi</button>') + '</span></div>';
      }).join('') + '</div>';
    var others = P.filter(function (x) { return !plan || x.id !== plan.id; });
    body += '<div class="sec-t" style="margin-top:14px">' + (c.next ? 'Plan badlein / Upgrade' : 'Plan poora hua — dobara plan lein') + '</div><div class="list">' + others.map(function (x) {
      var pp = perOf(x.data);
      return '<div class="li"><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(pp[0]) + '</span><span>' + visitsTotal(x.data) + ' visit' + (visitsTotal(x.data) > 1 ? 's' : '') + (x.data.period === 'one' ? '' : ' / ' + (num(x.data.years) || 1) + ' saal') + '</span></span></span><span class="amt">' + (num(x.data.price) === 0 ? 'Free' : money(x.data.price)) + '</span>' +
        '<span class="acts"><button class="btn btn-o btn-sm" data-chg="' + x.id + '">' + (c.next ? 'Plan badlein' : 'Ye plan lein') + '</button></span></div>';
    }).join('') + '</div>';
    var m = C.modal({ title: c.party + ' — ' + c.plan, size: 'wide', body: body });
    m.el.addEventListener('click', async function (e) {
      var cb = e.target.closest('[data-chg]');
      if (cb) {
        var np = P.find(function (x) { return String(x.id) === cb.getAttribute('data-chg'); }); if (!np) return;
        if (!c.next) { m.close(); return contractForm({ id: c.party_id, title: c.party, mobile: c.mobile }, P, K, np.id); }
        if (!(await C.confirm('Plan "' + c.plan + '" se badal kar "' + np.title + '" karein? Baaki bachi visits naye plan ke hisaab se dobara set hongi (ho chuki visits ka record rahega).', 'Haan, badlein'))) return;
        try { var r = await C.run('crm_maint_change', { contract_id: c.key, plan_id: np.id }, null); m.close(); C.toast('Plan badal gaya ✔ · ' + r.visits + ' visit' + (r.visits > 1 ? 's' : '') + ' set'); C.render(); } catch (er) {}
        return;
      }
      var b = e.target.closest('[data-dn],[data-mv],[data-rep]'); if (!b) return;
      var id = b.getAttribute('data-dn') || b.getAttribute('data-mv') || b.getAttribute('data-rep'), v = c.visits.find(function (x) { return String(x.id) === id; });
      if (b.hasAttribute('data-dn')) { m.close(); doneForm(c, v, K); }
      else if (b.hasAttribute('data-mv')) { if (await C.reminderForm(v)) { m.close(); C.render(); } }
      else report(c, v);
    });
  }

  function doneForm(c, v, K) {
    var ck = v.data.checks || [];
    var m = C.modal({ title: 'Visit ho gayi — ' + c.party, size: 'wide', body: '<form id="mdf" class="fg">' +
      C.f('Service ki tareekh', C.inp('done_on', C.today(), 'type="date"')) + '<div class="f"><label>Plan</label><b>' + esc(c.plan) + ' · visit ' + esc(v.data.visit_no || '') + '/' + esc(v.data.visits_total || c.total) + '</b></div>' +
      '<div class="f full"><label>Kaun-kaun se kaam hue (tick karein)</label><div class="list" id="mdk">' + (ck.length ? ck.map(function (k) {
        return '<label class="li" style="cursor:pointer"><input type="checkbox" data-t="' + k.id + '" checked><span class="grow"><span class="t">' + esc(k.name) + '</span>' + (k.mat_id ? '<span class="m"><span>Stock se maal kategi</span></span>' : '') + '</span><span class="amt">' + money(k.cost) + '</span></label>';
      }).join('') : '<div class="note">Is visit ke saath koi checklist nahi judi.</div>') + '</div></div>' +
      C.f('Note (zaroori nahi)', C.ta('note', '', 'rows="2" maxlength="500"'), 'full') + '</form>',
      foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Visit ho gayi — Save</button>' });
    $('[data-ok]', m.el).onclick = async function () {
      var f = $('#mdf', m.el), o = C.form(f), t = $$('[data-t]:checked', m.el).map(function (x) { return +x.getAttribute('data-t'); });
      try {
        var r = await C.run('crm_maint_done', { id: v.id, done_on: o.done_on, ticked: t, note: o.note }, null);
        m.close(); C.toast('Visit ho gayi ✔' + (r.next_due ? ' · Agli visit ' + C.fd(r.next_due) : ' · Package poora'));
        var rv = Object.assign({}, v, { status: 'done', data: Object.assign({}, v.data, { done_on: o.done_on, done_ticked: t, done_cost: r.cost, done_note: o.note }) });
        if (await C.confirm('Customer ke liye Service Report banayein / WhatsApp karein?', 'Haan, report')) report(c, rv, r.next_due);
        C.render();
      } catch (e) {}
    };
  }

  function report(c, v, nextDue) {
    var co = C.company(), d = v.data, tk = d.done_ticked || [], ck = d.checks || [];
    var rows = ck.map(function (k) { var ok = !tk.length || tk.indexOf(k.id) >= 0 || tk.indexOf(String(k.id)) >= 0; return '<tr><td style="padding:6px 8px;border:1px solid #ddd">' + esc(k.name) + '</td><td style="padding:6px 8px;border:1px solid #ddd;text-align:center">' + (ok ? '✔ Done' : '— Not done') + '</td></tr>'; }).join('');
    var nx = nextDue || (c.next && c.next.id !== v.id ? c.next.due_at : '');
    var html = '<div style="font-family:Arial,sans-serif;padding:24px;color:#111"><h2 style="margin:0">' + esc(co.name || 'Sunpowers') + '</h2><div style="color:#555;font-size:13px">' + esc([co.address, co.phone].filter(Boolean).join(' · ')) + '</div>' +
      '<h3 style="margin:18px 0 6px">Service / Audit Report</h3><table style="font-size:14px;margin-bottom:12px"><tr><td style="padding:2px 14px 2px 0;color:#555">Customer</td><td><b>' + esc(c.party) + '</b></td></tr><tr><td style="padding:2px 14px 2px 0;color:#555">Plan</td><td>' + esc(c.plan) + '</td></tr><tr><td style="padding:2px 14px 2px 0;color:#555">Service date</td><td>' + C.fd(d.done_on || v.due_at) + '</td></tr>' +
      '<tr><td style="padding:2px 14px 2px 0;color:#555">Visit</td><td>' + esc(d.visit_no || '') + ' / ' + esc(d.visits_total || c.total) + '</td></tr>' + (nx ? '<tr><td style="padding:2px 14px 2px 0;color:#555">Next service</td><td><b>' + C.fd(nx) + '</b></td></tr>' : '') + '</table>' +
      '<table style="border-collapse:collapse;width:100%;font-size:14px"><thead><tr><th style="padding:6px 8px;border:1px solid #ddd;text-align:left;background:#f4f4f4">Kaam</th><th style="padding:6px 8px;border:1px solid #ddd;background:#f4f4f4">Status</th></tr></thead><tbody>' + rows + '</tbody></table>' +
      (d.done_note ? '<p style="margin-top:12px"><b>Note:</b> ' + esc(d.done_note) + '</p>' : '') + '<p style="margin-top:28px;font-size:12px;color:#777">Ye report computer se banai gayi hai.</p></div>';
    var fn = 'Service-Report-' + String(c.party || 'customer').replace(/[^\w\-]+/g, '-') + '.pdf';
    C.sharePdf(html, fn, 'Namaste ' + c.party + ' ji, aapke solar plant ki ' + c.plan + ' service ' + C.fd(d.done_on || v.due_at) + ' ko ho gayi hai.' + (nx ? ' Agli service: ' + C.fd(nx) + '.' : '') + ' — ' + (co.name || 'Sunpowers'), c.mobile,
      { kind: 'service', title: 'Service Report — ' + c.party, subtitle: c.plan + ' · visit ' + (d.visit_no || '') + '/' + (d.visits_total || c.total), customer: c.party, date: d.done_on || v.due_at, ref: 'svc:' + v.id,
        details: [['Customer', c.party], ['Plan', c.plan], ['Service date', C.fd(d.done_on || v.due_at)], ['Visit', (d.visit_no || '') + ' / ' + (d.visits_total || c.total)], ['Next service', nx ? C.fd(nx) : ''], ['Kaam hue', ck.filter(function (k) { return !tk.length || tk.indexOf(k.id) >= 0 || tk.indexOf(String(k.id)) >= 0; }).map(function (k) { return k.name; }).join(', ')], ['Note', d.done_note || '']].filter(function (x) { return x[1]; }) });
  }
})();
