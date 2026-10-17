/* Accounts — Kharcha (expenses), Profit & Loss, GST (output / input / net) and ITR summary.
   A report for your CA — it is NOT GST / ITR filing. Numbers come from the server (crm_acct_report). */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = function (v) { return parseFloat(v) || 0; };
  var CATS = ['Rent', 'Salary', 'Fuel / Travel', 'Electricity', 'Phone / Internet', 'Marketing / Ads', 'Office', 'Repair / Maintenance', 'Transport / Freight', 'CA / Professional fees', 'Insurance', 'Bank charges', 'Tax / Govt fees', 'Other'];
  var MODES = [['cash', 'Cash'], ['bank', 'Bank / UPI'], ['card', 'Card'], ['credit', 'Udhaar (baad me)']];
  var MN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  function fyStart(d) { var y = +d.slice(0, 4), m = +d.slice(5, 7); return m >= 4 ? y : y - 1; }
  function fyOf(y) { return [y + '-04-01', (y + 1) + '-03-31']; }
  function fyLabel(y) { return 'FY ' + y + '-' + String(y + 1).slice(2); }
  function monLabel(k) { return MN[+k.slice(5, 7) - 1] + ' ' + k.slice(0, 4); }
  function range(q) {
    var cur = fyStart(C.today()), fy = q.fy || String(cur), from, to;
    if (fy === 'custom' && q.from && q.to) { from = q.from; to = q.to; }
    else { var r = fyOf(+fy || cur); from = r[0]; to = r[1]; fy = String(+fy || cur); }
    return { fy: fy, from: from, to: to };
  }
  function fySelect(cur, sel) {
    var o = []; for (var i = 0; i < 4; i++) o.push([String(cur - i), fyLabel(cur - i)]); o.push(['custom', 'Apni tareekh']);
    return '<select class="inp" data-fy style="width:auto">' + C.opts(o, sel) + '</select>';
  }
  function row(cells) { return '<tr>' + cells.map(function (c, i) { return '<td' + (i ? ' class="r"' : '') + '>' + c + '</td>'; }).join('') + '</tr>'; }
  function table(head, rows, foot) {
    return '<div class="tw"><table class="t"><thead><tr>' + head.map(function (h, i) { return '<th' + (i ? ' class="r"' : '') + '>' + esc(h) + '</th>'; }).join('') + '</tr></thead><tbody>' + (rows.length ? rows.join('') : '<tr><td colspan="' + head.length + '" class="mute">Is period me koi entry nahi</td></tr>') + (foot || '') + '</tbody></table></div>';
  }

  /* ---------------- Round 13: Overview / Ledger / Lena baaki / Dena baaki / Payments ---------------- */
  var ch = function () { return C.chart; };
  function dlb(name, head, rows) { return C.can('reports.download') ? C.reportBtns(name, function () { return { head: head, rows: rows }; }) : ''; }
  function tb(head, rows, right) { right = right || []; return '<div class="tw"><table class="t"><thead><tr>' + head.map(function (h, i) { return '<th' + (right.indexOf(i) >= 0 ? ' class="r"' : '') + '>' + esc(h) + '</th>'; }).join('') + '</tr></thead><tbody>' + (rows.length ? rows.map(function (r) { return '<tr>' + r.map(function (v, i) { return '<td' + (right.indexOf(i) >= 0 ? ' class="r"' : '') + '>' + v + '</td>'; }).join('') + '</tr>'; }).join('') : '<tr><td colspan="' + head.length + '" class="mute">Koi entry nahi</td></tr>') + '</tbody></table></div>'; }
  async function newTab(el, tab, R, q) {
    var box = $('#nbody', el), h = '';
    try {
      if (tab === 'home') {
        var r = await Promise.all([C.call('crm_acct_report', { from: R.from, to: R.to }), C.call('crm_receivable', { side: 'receivable' }), C.call('crm_receivable', { side: 'payable' }).catch(function () { return { rows: [], total: 0 }; }), C.call('crm_ledger', { from: R.from, to: R.to })]);
        var D = r[0], RC = r[1], PB = r[2], LG = r[3], t = LG.tot;
        h += '<div class="ch-tiles">' +
          ch().tile({ l: 'Sale (GST ke bina)', v: money(D.revenue), sub: D.invoices + ' bill · GST ' + money(D.gst_output), icon: 'bill', c: '#f2a900', href: '#/accounts?tab=report' }) +
          ch().tile({ l: 'Paisa mila (cash in)', v: money(t.cash_in), sub: 'Collection', icon: 'rupee', c: '#1e8e3e', href: '#/accounts?tab=payments' }) +
          ch().tile({ l: 'Paisa gaya (cash out)', v: money(t.cash_out), sub: 'Supplier + kharcha', icon: 'cart', c: '#d64545', href: '#/accounts?tab=payments' }) +
          ch().tile({ l: 'Lena baaki', v: money(RC.total), sub: RC.rows.length + ' customer', icon: 'clock', c: num(RC.total) > 0 ? '#e0742c' : '#6b7a70', href: '#/accounts?tab=receivable' }) +
          ch().tile({ l: 'Dena baaki', v: money(PB.total), sub: PB.rows.length + ' supplier', icon: 'clock', c: '#7b4fd1', href: '#/accounts?tab=payable' }) +
          ch().tile({ l: 'Kharcha', v: money(D.expense), sub: 'GST ke bina', icon: 'rupee', c: '#2f6fdb', href: '#/accounts?tab=expenses' }) +
          ch().tile({ l: 'Net profit', v: money(D.net_profit), sub: 'Sale − Purchase − Kharcha', icon: 'activity', c: num(D.net_profit) < 0 ? '#d64545' : '#1e8e3e' }) +
          ch().tile({ l: 'Net GST', v: money(Math.abs(D.gst_net)), sub: num(D.gst_net) >= 0 ? 'dena hai' : 'aage ke liye (credit)', icon: 'shield', c: '#12a5a5', href: '#/accounts?tab=report' }) + '</div><div class="ch-grid2">';
        h += '<div class="card"><div class="hd"><h3>Mahine ke hisab se</h3></div>' + ch().bars((D.months || []).map(function (m) { return { l: monLabel(m.month), vs: [num(m.sales), num(m.purchase), num(m.expense)] }; }), { series: [{ n: 'Sale', c: '#f2a900' }, { n: 'Purchase', c: '#2f6fdb' }, { n: 'Kharcha', c: '#d64545' }], label: 'Sale purchase expense' }) + '</div>';
        h += '<div class="card"><div class="hd"><h3>Kharcha category ke hisab se</h3></div>' + ch().donut((D.expense_by_category || []).map(function (x) { return { l: x.category, v: x.amount }; }), { label: 'Expense by category' }) + '</div>';
        h += '<div class="card"><div class="hd"><h3>Lena baaki — sabse zyada</h3><a class="btn btn-g btn-sm" href="#/accounts?tab=receivable">Sab ' + C.ic('right') + '</a></div>' + ch().hbars(RC.rows.slice(0, 6).map(function (x) { return { l: x.name, v: x.total, sub: money(x.total) }; })) + '</div>';
        h += '<div class="card"><div class="hd"><h3>Dena baaki — sabse zyada</h3><a class="btn btn-g btn-sm" href="#/accounts?tab=payable">Sab ' + C.ic('right') + '</a></div>' + ch().hbars(PB.rows.slice(0, 6).map(function (x) { return { l: x.name, v: x.total, c: '#7b4fd1', sub: money(x.total) }; })) + '</div></div>';
      } else if (tab === 'ledger') {
        var pid = q.party || '', LG2 = await C.call('crm_ledger', { party_id: pid || null, from: R.from, to: R.to });
        var closing = LG2.lines.length ? num(LG2.lines[LG2.lines.length - 1].bal) : num(LG2.opening);
        h += '<div class="card" style="margin-bottom:12px"><div class="row wrap"><button class="btn btn-o" data-lp>' + C.ic('users') + ' ' + (pid ? 'Party badlein' : 'Party chunein (party ledger)') + '</button>' + (pid ? '<button class="btn btn-g" data-lc>Day book par wapas</button><b>' + esc(LG2.party || '') + '</b>' : '<span class="xs mute">Party na chunein to Day book (sab entry) dikhega</span>') + '</div></div>';
        var heads = pid ? ['Date', 'Kya', 'Ref', 'Detail', 'Bill / Dena', 'Mila / Diya', 'Baaki'] : ['Date', 'Kya', 'Ref', 'Party', 'Detail', 'Mila', 'Gaya'];
        var rows = LG2.lines.map(function (l) { return pid ? [esc(C.fd(l.d)), esc(l.typ), esc(l.ref || ''), esc(l.note || ''), num(l.debit) ? money(l.debit) : '', num(l.credit) ? money(l.credit) : '', money(l.bal)] : [esc(C.fd(l.d)), esc(l.typ), esc(l.ref || ''), esc(l.party || ''), esc(l.note || ''), num(l.cash_in) ? money(l.cash_in) : '', num(l.cash_out) ? money(l.cash_out) : '']; });
        h += '<div class="card"><div class="hd"><h3>' + (pid ? 'Party ledger' : 'Day book') + ' <span class="xs mute">' + esc(C.fd(R.from)) + ' – ' + esc(C.fd(R.to)) + '</span></h3>' + dlb(pid ? 'Ledger ' + (LG2.party || '') : 'Day book', heads, LG2.lines.map(function (l) { return pid ? [C.fd(l.d), l.typ, l.ref || '', l.note || '', num(l.debit), num(l.credit), num(l.bal)] : [C.fd(l.d), l.typ, l.ref || '', l.party || '', l.note || '', num(l.cash_in), num(l.cash_out)]; })) + '</div>' +
          (pid ? '<div class="note g" style="margin-bottom:10px">Shuru ka baaki: <b>' + money(LG2.opening) + '</b> · Aakhri baaki: <b>' + money(closing) + '</b> <span class="xs">(+ = party se lena, − = party ko dena)</span></div>' : '<div class="note g" style="margin-bottom:10px">Paisa mila: <b>' + money(LG2.tot.cash_in) + '</b> · Paisa gaya: <b>' + money(LG2.tot.cash_out) + '</b></div>') +
          tb(heads, rows, pid ? [4, 5, 6] : [5, 6]) + '</div>';
      } else if (tab === 'receivable' || tab === 'payable') {
        var side = tab, RR = await C.call('crm_receivable', { side: side }), pay = side === 'payable';
        h += '<div class="ch-tiles">' + ch().tile({ l: pay ? 'Kul dena baaki' : 'Kul lena baaki', v: money(RR.total), sub: RR.rows.length + (pay ? ' supplier' : ' customer'), icon: 'clock', c: pay ? '#7b4fd1' : '#e0742c' }) +
          ch().tile({ l: '90+ din purana', v: money(RR.rows.reduce(function (a, x) { return a + num(x.b90); }, 0)), icon: 'alert', c: '#d64545' }) + '</div>';
        h += '<div class="card"><div class="hd"><h3>' + (pay ? 'Suppliers ko dena' : 'Customers se lena') + '</h3>' + dlb(pay ? 'Dena baaki' : 'Lena baaki', ['Party', 'Mobile', 'Bills', 'Kul baaki', '0-30', '31-60', '61-90', '90+', 'Sabse purana'], RR.rows.map(function (x) { return [x.name, x.mobile || '', x.n, num(x.total), num(x.b0), num(x.b30), num(x.b60), num(x.b90), x.oldest ? C.fd(x.oldest) : '']; })) + '</div></div>' +
          (RR.rows.length ? RR.rows.map(function (x) {
            return '<details class="card" style="margin-bottom:8px;padding:10px 12px"><summary style="cursor:pointer;display:flex;gap:10px;align-items:center;flex-wrap:wrap"><b class="grow">' + esc(x.name) + '</b><span class="xs mute">' + x.n + ' ' + (pay ? 'PO' : 'bill') + ' · sabse purana ' + esc(x.oldest ? C.fd(x.oldest) : '') + '</span><b>' + money(x.total) + '</b></summary>' +
              '<div class="xs mute" style="margin:8px 0">0-30: ' + money(x.b0 || 0) + ' · 31-60: ' + money(x.b30 || 0) + ' · 61-90: ' + money(x.b60 || 0) + ' · 90+: <b style="color:#d64545">' + money(x.b90 || 0) + '</b></div>' +
              '<div class="list">' + x.docs.map(function (d) { return '<div class="li"><span class="grow"><span class="t">' + esc(d.ref || '') + '</span><span class="m"><span>' + esc(C.fd(d.date)) + '</span><span>Total ' + money(d.amount) + '</span><span>Diya/Mila ' + money(d.paid) + '</span></span></span><b>' + money(d.balance) + '</b>' + (pay ? (C.can('purchase.manage') ? '<button class="btn btn-p btn-sm" data-pp="' + d.id + '" data-bal="' + d.balance + '" data-ref="' + esc(d.ref || '') + '">Payment diya</button>' : '') : '<a class="btn btn-o btn-sm" href="#/invoice/' + d.id + '">Bill</a>') + '</div>'; }).join('') + '</div>' +
              '<div class="row wrap" style="margin-top:8px">' + (!pay && x.mobile ? '<a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(x.mobile, 'Namaste ' + x.name + ' ji, ' + (C.company().name || '') + ' ki taraf se yaad dila rahe hain — aapka ' + money(x.total) + ' baaki hai. Kripya payment kar dein. Dhanyavaad.')) + '">' + C.ic('wa') + ' WhatsApp yaad dilayein</a>' : '') + (x.party_id ? '<a class="btn btn-g btn-sm" href="#/accounts?tab=ledger&party=' + x.party_id + '">Ledger dekhein</a>' : '') + '</div></details>';
          }).join('') : '<div class="card">' + C.empty('check', pay ? 'Kisi supplier ko kuch dena baaki nahi' : 'Koi baaki nahi — sab paisa aa chuka hai') + '</div>');
      } else if (tab === 'payments') {
        var r2 = await Promise.all([C.call('crm_report', { report: 'collections', from: R.from, to: R.to }), C.call('crm_ledger', { from: R.from, to: R.to })]);
        var CO = r2[0], outs = r2[1].lines.filter(function (l) { return l.typ === 'Supplier ko payment' || l.typ === 'Kharcha'; });
        var tin = CO.rows.reduce(function (a, x) { return a + num(x[5]); }, 0), tout = outs.reduce(function (a, x) { return a + num(x.cash_out); }, 0);
        h += '<div class="ch-tiles">' + ch().tile({ l: 'Paisa mila', v: money(tin), sub: CO.rows.length + ' payment', icon: 'rupee', c: '#1e8e3e' }) + ch().tile({ l: 'Paisa gaya', v: money(tout), sub: outs.length + ' entry', icon: 'cart', c: '#d64545' }) + ch().tile({ l: 'Bacha (net)', v: money(tin - tout), icon: 'activity', c: tin - tout < 0 ? '#d64545' : '#1e8e3e' }) + '</div><div class="ch-grid2">';
        h += '<div class="card"><div class="hd"><h3>Mile (customers se)</h3>' + dlb('Payments received', CO.head, CO.rows.map(function (x) { return [C.fd(x[0]), x[1], x[2], x[3], x[4], num(x[5]), x[6]]; })) + '</div>' + tb(['Date', 'Receipt', 'Customer', 'Bill', 'Mode', 'Amount'], CO.rows.slice(0, 200).map(function (x) { return [esc(C.fd(x[0])), esc(x[1] || ''), esc(x[2] || ''), esc(x[3] || ''), esc(x[4] || ''), money(x[5])]; }), [5]) + '</div>';
        h += '<div class="card"><div class="hd"><h3>Diye (supplier + kharcha)</h3>' + dlb('Payments made', ['Date', 'Kya', 'Ref', 'Party', 'Mode', 'Amount'], outs.map(function (x) { return [C.fd(x.d), x.typ, x.ref || '', x.party || '', x.note || '', num(x.cash_out)]; })) + '</div>' + tb(['Date', 'Kya', 'Ref', 'Party', 'Mode', 'Amount'], outs.slice(0, 200).map(function (x) { return [esc(C.fd(x.d)), esc(x.typ), esc(x.ref || ''), esc(x.party || ''), esc(x.note || ''), money(num(x.cash_out))]; }), [5]) + '<p class="hint">Supplier ko payment "Dena baaki" tab se darj hoti hai. Kharcha "Kharcha" tab se. Udhaar wala kharcha tab judta hai jab paisa diya jaye.</p></div></div>';
      }
    } catch (e) { box.innerHTML = '<div class="card"><div class="note r">' + esc(e.message) + '</div></div>'; return; }
    box.innerHTML = h;
    var lp = $('[data-lp]', box); if (lp) lp.onclick = async function () { var p = await C.partyPick({ title: 'Party chunein' }); if (p) C.go('#/accounts' + C.qs({ tab: 'ledger', party: p.id, fy: R.fy, from: R.from, to: R.to })); };
    var lc = $('[data-lc]', box); if (lc) lc.onclick = function () { C.go('#/accounts' + C.qs({ tab: 'ledger', fy: R.fy, from: R.from, to: R.to })); };
    $$('[data-pp]', box).forEach(function (b) {
      b.onclick = function () {
        var bal = num(b.getAttribute('data-bal')), m = C.modal({ title: 'Supplier ko payment — ' + b.getAttribute('data-ref'), size: 'sm',
          body: C.f('Amount * (baaki ' + money(bal) + ')', '<input class="inp" type="number" min="0" step="0.01" inputmode="decimal" data-k="amount" value="' + bal + '">') + C.f('Tareekh', '<input class="inp" type="date" data-k="date" value="' + C.today() + '">') +
            C.f('Kaise diya', '<select class="inp" data-k="mode">' + C.opts(MODES.slice(0, 3), 'bank') + '</select>') + C.f('Note / UTR', '<input class="inp" data-k="note" maxlength="200">'), foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>' });
        $('[data-ok]', m.el).onclick = async function () {
          var p = { id: +b.getAttribute('data-pp') }; $$('[data-k]', m.el).forEach(function (i) { p[i.getAttribute('data-k')] = i.value; });
          if (num(p.amount) <= 0) return C.toast('Amount likhein', true);
          try { C.busy(true); await C.call('crm_purchase_pay', p); m.close(); C.toast('Payment darj ho gayi ✔'); C.render(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
        };
      };
    });
  }

  C.mod('accounts', {
    title: 'Accounts',
    allowed: function () { return C.canAny('accounts.manage', 'accounts.view'); },
    render: async function (el, params, q) {
      var tab = q.tab || 'home', R = range(q), cur = fyStart(C.today()), canEdit = C.can('accounts.manage');
      var h = '<div class="ph"><div><h1>Accounts</h1><p>Ledger, lena-dena, payments, kharcha aur GST — sab ek jagah. Reports ke liye alag <a href="#/reports">Reports</a> menu hai.</p></div></div>';
      h += '<div class="note g" style="margin-bottom:14px">' + C.ic('shield') + ' Ye <b>report</b> hai — GST return / ITR file karna CA ka kaam hai. Sale aur purchase Billing se, kharcha yahan se aata hai.</div>';
      h += '<div class="tabs">' + [['home', 'Overview'], ['ledger', 'Ledger'], ['receivable', 'Lena baaki'], ['payable', 'Dena baaki'], ['payments', 'Payments'], ['expenses', 'Kharcha'], ['report', 'Profit & GST']].map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + t[1] + '</button>'; }).join('') + '</div>';
      h += '<div class="bar">' + fySelect(cur, R.fy) + '<span class="xs mute">Se</span><input class="inp" type="date" data-from value="' + esc(R.from) + '" style="width:auto"><span class="xs mute">Tak</span><input class="inp" type="date" data-to value="' + esc(R.to) + '" style="width:auto"><span class="sp"></span>' +
        (tab === 'expenses' && canEdit ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Kharcha jodein</button>' : '') + '</div>';
      var body = '';
      if (tab === 'expenses') {
        var L = await C.call('crm_exp_list', { from: R.from, to: R.to });
        var tot = C.sum(L, 'amount'), gst = C.sum(L, 'gst_amount');
        body = '<div class="kpis">' + C.kpi('Kul kharcha', money(tot), L.length + ' entry', 'gold') + C.kpi('Isme GST', money(gst), 'input credit') + C.kpi('GST ke bina', money(tot - gst)) + '</div>' +
          '<div class="card"><div class="hd"><h3>Kharcha list</h3>' + C.reportBtns('Expenses', function () { return { head: ['Date', 'Category', 'Vendor', 'Amount', 'GST', 'Mode', 'Note'], rows: L.map(function (e) { return [e.spent_on, e.category, e.vendor, num(e.amount), num(e.gst_amount), e.mode, e.note]; }), text: 'Expenses ' + R.from + ' to ' + R.to }; }) + '</div>' +
          (L.length ? '<div class="list">' + L.map(function (e) { return '<div class="li" data-id="' + e.id + '"><span class="grow"><b>' + esc(e.category) + '</b>' + (e.vendor ? ' · ' + esc(e.vendor) : '') + '<span class="xs mute" style="display:block">' + esc(C.fd(e.spent_on)) + ' · ' + esc(e.mode) + (e.note ? ' · ' + esc(e.note) : '') + '</span></span><b>' + money(e.amount) + '</b>' + (num(e.gst_amount) ? '<span class="xs mute">GST ' + money(e.gst_amount) + '</span>' : '') + (C.can('accounts.manage') ? '<button class="btn btn-g btn-sm" data-edit="' + e.id + '" aria-label="Badlein">' + C.ic('edit') + '</button><button class="btn btn-g btn-sm" data-del="' + e.id + '" aria-label="Hatayein">' + C.ic('trash') + '</button>' : '') + '</div>'; }).join('') + '</div>' : C.empty('rupee', 'Abhi koi kharcha nahi', 'Rent, salary, petrol jaise kharche yahan likhein — P&L me apne aap judenge.')) + '</div>';
        el.innerHTML = h + body;
        el._L = L;
      } else if (tab !== 'report') {
        el.innerHTML = h + '<div id="nbody"><div class="card"><div class="spin"></div></div></div>';
        await newTab(el, tab, R, q);
      } else {
        var D = await C.call('crm_acct_report', { from: R.from, to: R.to });
        var k = '<div class="kpis">' + C.kpi('Sale (GST ke bina)', money(D.revenue), D.invoices + ' bill', 'gold') + C.kpi('Purchase', money(D.purchase), D.purchases + ' purchase') + C.kpi('Kharcha', money(D.expense)) +
          C.kpi('Gross profit', money(D.gross_profit), 'Sale − Purchase') + C.kpi('Net profit', money(D.net_profit), 'Gross − Kharcha', num(D.net_profit) < 0 ? 'red' : '') + C.kpi('Payment mila', money(D.collected)) + C.kpi('Baaki lena (abhi tak)', money(D.receivable)) + C.kpi('Baaki dena (open purchase)', money(D.payable)) + '</div>';
        var gst = '<div class="card"><div class="hd"><h3>GST — output, input, net</h3>' + C.reportBtns('GST net', function () { return { head: ['Detail', 'Amount'], rows: [['GST output (sale par)', num(D.gst_output)], ['GST input (purchase + kharcha)', num(D.gst_input)], ['Net GST (output − input)', num(D.gst_net)], ['B2B sale (GSTIN wale)', num(D.b2b)], ['B2C sale', num(D.b2c)]], text: 'GST ' + R.from + ' to ' + R.to }; }) + '</div>' +
          table(['Detail', 'Amount'], [row(['GST output (sale par)', money(D.gst_output)]), row(['GST input (purchase + kharcha)', money(D.gst_input)]), row(['<b>Net GST ' + (num(D.gst_net) >= 0 ? 'dena hai' : 'wapas / aage ke liye') + '</b>', '<b>' + money(Math.abs(D.gst_net)) + '</b>']), row(['B2B sale (customer ka GSTIN hai)', money(D.b2b)]), row(['B2C sale', money(D.b2c)])]) +
          '<p class="hint" style="margin:10px 0 0">Input me sirf "Maal aa gaya" wale purchase aur GST wala kharcha judta hai.</p></div>';
        var rates = '<div class="card"><div class="hd"><h3>GST rate ke hisab se (sale)</h3>' + C.reportBtns('GST rate wise', function () { return { head: ['GST %', 'Taxable', 'GST'], rows: D.rates.map(function (x) { return [num(x.rate), C.r2(x.taxable), C.r2(x.gst)]; }), text: 'GST rate wise' }; }) + '</div>' +
          table(['GST %', 'Taxable', 'GST'], D.rates.map(function (x) { return row([num(x.rate) + '%', money(x.taxable), money(x.gst)]); })) + '</div>';
        var mon = '<div class="card"><div class="hd"><h3>Mahine ke hisab se</h3>' + C.reportBtns('Month wise P&L', function () { return { head: ['Mahina', 'Sale', 'GST out', 'Purchase', 'GST in', 'Kharcha', 'Profit'], rows: D.months.map(function (m) { return [m.month, C.r2(m.sales), C.r2(m.gst_out), C.r2(m.purchase), C.r2(m.gst_in), C.r2(m.expense), C.r2(m.profit)]; }), text: 'Month wise ' + R.from + ' to ' + R.to }; }) + '</div>' +
          table(['Mahina', 'Sale', 'GST out', 'Purchase', 'GST in', 'Kharcha', 'Profit'], D.months.map(function (m) { return row([esc(monLabel(m.month)), money(m.sales), money(m.gst_out), money(m.purchase), money(m.gst_in), money(m.expense), money(m.profit)]); })) + '</div>';
        var cats = '<div class="card"><div class="hd"><h3>Kharcha category ke hisab se</h3>' + C.reportBtns('Expense by category', function () { return { head: ['Category', 'Amount', 'GST'], rows: D.expense_by_category.map(function (x) { return [x.category, num(x.amount), num(x.gst)]; }), text: 'Expense by category' }; }) + '</div>' +
          table(['Category', 'Amount', 'GST'], D.expense_by_category.map(function (x) { return row([esc(x.category), money(x.amount), money(x.gst)]); })) + '</div>';
        var itr = '<div class="card"><div class="hd"><h3>ITR ke liye summary</h3>' + C.reportBtns('ITR summary', function () { return { head: ['Detail', 'Amount'], rows: [['Turnover (sale, GST ke bina)', num(D.itr.turnover)], ['Books ka profit (Sale − Purchase − Kharcha)', num(D.itr.books_profit)], ['Presumptive profit @ 6% (digital sale)', num(D.itr.presumptive_6)], ['Presumptive profit @ 8%', num(D.itr.presumptive_8)]], text: 'ITR summary ' + R.from + ' to ' + R.to }; }) + '</div>' +
          table(['Detail', 'Amount'], [row(['Turnover (sale, GST ke bina)', money(D.itr.turnover)]), row(['Books ka profit (Sale − Purchase − Kharcha)', money(D.itr.books_profit)]), row(['Presumptive profit @ 6% (digital sale)', money(D.itr.presumptive_6)]), row(['Presumptive profit @ 8% (baaki)', money(D.itr.presumptive_8)])]) +
          '<p class="hint" style="margin:10px 0 0">6% / 8% sirf andaaza hai (Section 44AD, limit aur eligibility CA tay karega). Ye ITR filing nahi hai.</p></div>';
        el.innerHTML = h + '<div class="stack">' + k + '<div class="grid g2">' + gst + itr + '</div>' + mon + '<div class="grid g2">' + rates + cats + '</div></div>';
      }
      function nav(p) { C.go('#/accounts' + C.qs(Object.assign({ tab: tab, fy: R.fy, from: R.from, to: R.to }, p))); }
      $$('[data-tab]', el).forEach(function (b) { b.onclick = function () { nav({ tab: b.getAttribute('data-tab') }); }; });
      $('[data-fy]', el).onchange = function () { nav(this.value === 'custom' ? { fy: 'custom' } : { fy: this.value, from: '', to: '' }); };
      $('[data-from]', el).onchange = function () { nav({ fy: 'custom', from: this.value }); };
      $('[data-to]', el).onchange = function () { nav({ fy: 'custom', to: this.value }); };
      if (tab === 'expenses') {
        var L2 = el._L || [];
        var add = $('[data-act=add]', el); if (add) add.onclick = function () { form(null); };
        $$('[data-edit]', el).forEach(function (b) { b.onclick = function () { form(L2.filter(function (e) { return String(e.id) === b.getAttribute('data-edit'); })[0]); }; });
        $$('[data-del]', el).forEach(function (b) {
          b.onclick = async function () {
            var why = await C.ask('Kharcha hatayein', 'Kyun hata rahe hain?', { min: 3, danger: true, ok: 'Hatao' }); if (why == null) return;
            try { C.busy(true); await C.call('crm_exp_del', { id: +b.getAttribute('data-del'), why: why }); C.toast('Kharcha hata diya'); C.render(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
          };
        });
      }
      function form(e) {
        e = e || {};
        var m = C.modal({
          title: e.id ? 'Kharcha badlein' : 'Naya kharcha', size: 'sm',
          body: C.f('Tareekh *', '<input class="inp" type="date" data-k="spent_on" value="' + esc(e.spent_on || C.today()) + '">') +
            C.f('Category *', '<input class="inp" list="expcats" data-k="category" value="' + esc(e.category || '') + '" placeholder="Rent, Salary, Petrol…"><datalist id="expcats">' + CATS.map(function (c) { return '<option value="' + esc(c) + '">'; }).join('') + '</datalist>') +
            C.f('Kisko diya (vendor)', '<input class="inp" data-k="vendor" value="' + esc(e.vendor || '') + '" maxlength="120">') +
            '<div class="grid g2">' + C.f('Kul amount (GST sahit) *', '<input class="inp" type="number" min="0" step="0.01" inputmode="decimal" data-k="amount" value="' + esc(e.amount || '') + '">') + C.f('Isme GST kitna', '<input class="inp" type="number" min="0" step="0.01" inputmode="decimal" data-k="gst_amount" value="' + esc(e.gst_amount || '') + '">') + '</div>' +
            C.f('Kaise diya', '<select class="inp" data-k="mode">' + C.opts(MODES, e.mode || 'cash') + '</select>') + C.f('Note', '<input class="inp" data-k="note" value="' + esc(e.note || '') + '" maxlength="300">') +
            '<p class="hint">GST tabhi likhein jab GST bill mila ho — wahi input credit me judega.</p>',
          foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>'
        });
        $('[data-ok]', m.el).onclick = async function () {
          var p = { id: e.id || null }; $$('[data-k]', m.el).forEach(function (i) { p[i.getAttribute('data-k')] = i.value; });
          if (!p.category.trim() || num(p.amount) <= 0) { C.toast('Category aur amount zaroori hai', true); return; }
          try { C.busy(true); await C.call('crm_exp_save', p); m.close(); C.toast('Kharcha save ho gaya ✔'); C.render(); } catch (er) { C.toast(er.message, true); } finally { C.busy(false); }
        };
      }
    }
  });
})();
