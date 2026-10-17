/* Analytics — how the business is growing: funnel, months, sources, categories, top items / customers, team, receivable aging.
   Server (crm_analytics) already limits everything to what the user may see; "Poori company" needs the analytics.all point. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = function (v) { return parseFloat(v) || 0; }, ch = function () { return C.chart; };
  var MN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  function mlabel(m) { return MN[+m.slice(5, 7) - 1] + ' ' + m.slice(2, 4); }
  function presets() {
    var t = C.today(), y = +t.slice(0, 4), mo = +t.slice(5, 7);
    return [['m', 'Is mahine', t.slice(0, 8) + '01', t], ['3', 'Pichhle 3 mahine', C.addDays(t, -90), t], ['fy', 'Is saal (FY)', (mo >= 4 ? y : y - 1) + '-04-01', t], ['12', 'Pichhle 12 mahine', C.addDays(t, -365), t]];
  }
  function card(title, inner, extra) { return '<div class="card"><div class="hd"><h3>' + title + '</h3>' + (extra || '') + '</div>' + inner + '</div>'; }
  function dl(name, head, rows) { return C.can('reports.download') ? C.reportBtns(name, function () { return { head: head, rows: rows }; }) : ''; }
  function tbl(head, rows) { return '<div class="tw"><table class="t"><thead><tr>' + head.map(function (h, i) { return '<th' + (i ? ' class="r"' : '') + '>' + esc(h) + '</th>'; }).join('') + '</tr></thead><tbody>' + (rows.length ? rows.map(function (r) { return '<tr>' + r.map(function (v, i) { return '<td' + (i ? ' class="r"' : '') + '>' + v + '</td>'; }).join('') + '</tr>'; }).join('') : '<tr><td colspan="' + head.length + '" class="mute">Koi data nahi</td></tr>') + '</tbody></table></div>'; }

  C.mod('analytics', {
    title: 'Analytics',
    allowed: function () { return C.can('analytics.view'); },
    render: async function (el, params, q) {
      var P = presets(), pre = q.p || '12', cur = P.filter(function (x) { return x[0] === pre; })[0] || P[3], from = q.from || cur[2], to = q.to || cur[3], uid = q.u || '';
      if (q.from || q.to) pre = 'x';
      var canAll = C.can('analytics.all'), us = (C.cache.users || []).filter(function (u) { return u.role !== 'consumer' && u.status === 'active'; });
      el.innerHTML = '<div class="ph"><div><h1>Analytics</h1><p>' + (canAll ? 'Poori company ka haal — kya badh raha hai, kahan se kaam aa raha hai.' : 'Aapke apne kaam ka haal.') + '</p></div></div>' +
        '<div class="card" style="margin-bottom:12px"><div style="margin-bottom:8px">' + C.chips(P.map(function (p) { return [p[0], p[1]]; }), pre, 'pre') + '</div><div class="row wrap"><span class="sm b">Se</span><input class="inp" type="date" data-f="from" value="' + esc(from) + '" style="width:auto"><span class="sm b">Tak</span><input class="inp" type="date" data-f="to" value="' + esc(to) + '" style="width:auto">' +
        (canAll ? '<select class="inp" data-f="u" style="width:auto"><option value="">Poori company</option>' + us.map(function (u) { return '<option value="' + u.id + '"' + (String(u.id) === String(uid) ? ' selected' : '') + '>' + esc(u.name) + '</option>'; }).join('') + '</select>' : '') + '<button class="btn btn-p" data-go>Dikhayein</button></div></div><div id="abody"><div class="card"><div class="spin"></div></div></div>';
      function go(extra) { C.go('#/analytics' + C.qs(Object.assign({ from: $('[data-f=from]', el).value, to: $('[data-f=to]', el).value, u: ($('[data-f=u]', el) || {}).value || '' }, extra || {}))); }
      $('[data-go]', el).onclick = function () { go(); };
      $$('[data-pre]', el).forEach(function (b) { b.onclick = function () { C.go('#/analytics' + C.qs({ p: b.getAttribute('data-pre'), u: ($('[data-f=u]', el) || {}).value || '' })); }; });
      var A; try { A = await C.call('crm_analytics', { from: from, to: to, user_id: uid || null }); } catch (e) { $('#abody', el).innerHTML = '<div class="card"><div class="note r">' + esc(e.message) + '</div></div>'; return; }
      var f = A.funnel, mon = A.months, m = A.money, h = '';
      var pct = function (a, b) { return b ? Math.round(100 * a / b) + '%' : '—'; }, sum = function (k) { return mon.reduce(function (a, x) { return a + num(x[k]); }, 0); };
      var tiles = [ch().tile({ l: 'Leads', v: f.leads, sub: 'Won: ' + f.leads_won + ' (' + pct(f.leads_won, f.leads) + ')', icon: 'lead', c: '#7b4fd1' }),
        ch().tile({ l: 'Quotation', v: f.quotes, sub: 'Accepted: ' + f.quotes_accepted + ' (' + pct(f.quotes_accepted, f.quotes) + ')', icon: 'quote', c: '#2f6fdb' }),
        ch().tile({ l: 'Bills', v: f.bills, sub: 'Poore mile: ' + f.bills_paid, icon: 'bill', c: '#1e8e3e' }),
        ch().tile({ l: 'Plants (kW)', v: ch().fmt(sum('kw')), sub: 'Lage hue', icon: 'plant', c: '#12a5a5' })];
      if (m) tiles.push(ch().tile({ l: 'Sale', v: money(A.totals.sales), sub: 'Collection: ' + money(A.totals.collected), icon: 'rupee', c: '#f2a900', spark: ch().spark(mon.map(function (x) { return num(x.sales); }), '#f2a900') }), ch().tile({ l: 'Baaki lena', v: money(A.aging.total), sub: '90+ din: ' + money(A.aging.b90), icon: 'clock', c: A.aging.b90 > 0 ? '#d64545' : '#6b7a70' }));
      h += '<div class="ch-tiles">' + tiles.join('') + '</div><div class="ch-grid2">';
      if (m) h += card('Mahine ke hisab se — Sale &amp; Collection', ch().bars(mon.map(function (x) { return { l: mlabel(x.m), vs: [num(x.sales), num(x.collected)] }; }), { series: [{ n: 'Sale', c: '#f2a900' }, { n: 'Collection', c: '#1e8e3e' }], label: 'Sale and collection' }), dl('Analytics monthly', ['Mahina', 'Sale', 'Collection', 'Leads', 'Won', 'Quotation', 'Bills', 'kW'], mon.map(function (x) { return [mlabel(x.m), num(x.sales), num(x.collected), x.leads, x.won, x.quotes, x.bills, num(x.kw)]; })));
      h += card('Leads aur Won', ch().bars(mon.map(function (x) { return { l: mlabel(x.m), vs: [x.leads, x.won] }; }), { series: [{ n: 'Leads', c: '#7b4fd1' }, { n: 'Won', c: '#1e8e3e' }], label: 'Leads and won' }));
      h += card('Kaam ka funnel', ch().hbars([{ l: 'Leads', v: f.leads, c: '#7b4fd1', sub: '' }, { l: 'Quotation', v: f.quotes, c: '#2f6fdb' }, { l: 'Quotation accepted', v: f.quotes_accepted, c: '#12a5a5' }, { l: 'Bills', v: f.bills, c: '#f2a900' }, { l: 'Poore mile', v: f.bills_paid, c: '#1e8e3e' }]) +
        '<p class="hint" style="margin-top:8px">Lead→Won: <b>' + pct(f.leads_won, f.leads) + '</b> · Quotation→Accepted: <b>' + pct(f.quotes_accepted, f.quotes) + '</b> · Bill→Poore mile: <b>' + pct(f.bills_paid, f.bills) + '</b></p>');
      h += card('Lead kahan se aayi', ch().donut(A.sources.map(function (x) { return { l: x.s, v: x.leads }; }), { center: f.leads, label: 'Lead sources' }) + tbl(['Source', 'Leads', 'Won', 'Conversion'], A.sources.map(function (x) { return [esc(x.s), x.leads, x.won, x.rate + '%']; })), dl('Lead sources', ['Source', 'Leads', 'Won', 'Conversion %'], A.sources.map(function (x) { return [x.s, x.leads, x.won, x.rate]; })));
      h += card('Quotation ki halat', ch().donut(A.quote_status.map(function (x) { return { l: x.s, v: x.n }; }), { center: f.quotes, label: 'Quotation status' }));
      h += card('Plants (kW) mahine ke hisab se', ch().line(mon.map(function (x) { return { l: mlabel(x.m), v: num(x.kw) }; }), { label: 'kW installed' }));
      if (m) {
        h += card('Category ke hisab se sale', ch().donut(A.by_category.map(function (x) { return { l: x.c, v: x.amt }; }), { label: 'Sale by category' }), dl('Sale by category', ['Category', 'Amount', 'Qty'], A.by_category.map(function (x) { return [x.c, num(x.amt), num(x.qty)]; })));
        h += card('Sabse zyada bikne wale items', ch().hbars(A.by_item.map(function (x) { return { l: x.name, v: x.amt, sub: money(x.amt) }; }), { max: 10 }), dl('Top items', ['Item', 'Amount', 'Qty'], A.by_item.map(function (x) { return [x.name, num(x.amt), num(x.qty)]; })));
        h += card('Sabse bade customers', ch().hbars(A.top_customers.map(function (x) { return { l: x.name, v: x.amt, sub: money(x.amt) }; }), { max: 10 }), dl('Top customers', ['Customer', 'Amount', 'Bills'], A.top_customers.map(function (x) { return [x.name, num(x.amt), x.bills]; })));
        h += card('Baaki lena — kitne din purana', ch().bars([{ l: '0-30', v: num(A.aging.b0) }, { l: '31-60', v: num(A.aging.b30) }, { l: '61-90', v: num(A.aging.b60) }, { l: '90+', v: num(A.aging.b90) }], { color: '#d64545', label: 'Receivable aging' }) + '<p class="hint" style="margin-top:6px">Kul baaki: <b>' + money(A.aging.total) + '</b> · <a href="#/accounts?tab=receivable">Customer-wise dekhein</a></p>');
      }
      h += '</div>';
      if (A.by_user.length > 1 || (canAll && !uid)) h += card('Team ke hisab se', tbl(['Naam', 'Leads', 'Won', 'Quotation', 'Bills', 'kW'].concat(m ? ['Sale'] : []), A.by_user.map(function (x) { return [esc(x.name), x.leads, x.won, x.quotes, x.bills, ch().fmt(x.kw)].concat(m ? [money(x.sales)] : []); })),
        dl('Team analytics', ['Naam', 'Leads', 'Won', 'Quotation', 'Bills', 'kW'].concat(m ? ['Sale'] : []), A.by_user.map(function (x) { return [x.name, x.leads, x.won, x.quotes, x.bills, num(x.kw)].concat(m ? [num(x.sales)] : []); })));
      $('#abody', el).innerHTML = h;
    }
  });
})();
