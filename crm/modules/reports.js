/* Reports — one place for every business report. Pick a report -> filters (date, user, status, category, search) -> table -> download.
   Numbers come from the server (crm_report); what a user can open depends on their permission points. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = function (v) { return parseFloat(v) || 0; };
  var MONEY_H = /amount|total|taxable|^gst$|baaki|paid|diya|mila|value|rate$|discount|balance|^din$/i;
  var NOSUM_H = /rate$|^din$|^gst %$|stock$|kharid rate|bikri rate/i;
  var EXP_CATS = ['Rent', 'Salary', 'Fuel / Travel', 'Electricity', 'Phone / Internet', 'Marketing / Ads', 'Office', 'Repair / Maintenance', 'Transport / Freight', 'CA / Professional fees', 'Insurance', 'Bank charges', 'Tax / Govt fees', 'Other'];
  var ST = {
    invoice: [['', 'Sab'], ['due', 'Baaki (due)'], ['partial', 'Aadha mila'], ['paid', 'Poora mila']],
    quote: [['', 'Sab'], ['draft', 'Draft'], ['sent', 'Bheji'], ['accepted', 'Accepted'], ['converted', 'Bill ban gaya'], ['rejected', 'Rejected'], ['expired', 'Expired']],
    lead: [['', 'Sab'], ['new', 'Nayi'], ['contacted', 'Contacted'], ['visit', 'Visit'], ['quoted', 'Quoted'], ['won', 'Won'], ['lost', 'Lost']],
    purchase: [['', 'Sab'], ['open', 'Open'], ['received', 'Maal aa gaya'], ['cancelled', 'Cancelled']],
    plant: [['', 'Sab'], ['pending', 'Verify baaki'], ['verified', 'Verified'], ['rejected', 'Rejected']],
    earning: [['', 'Sab'], ['due', 'Dena baaki'], ['paid', 'Diya']],
    mode: [['', 'Sab'], ['cash', 'Cash'], ['bank', 'Bank / UPI'], ['card', 'Card'], ['credit', 'Udhaar'], ['UPI', 'UPI'], ['Cash', 'Cash (receipt)']]
  };
  var REPORTS = [
    { g: 'Paisa & Accounts', k: 'sales', t: 'Sales register', d: 'Har bill: taxable, GST, mila, baaki', i: 'bill', st: 'invoice', money: true },
    { g: 'Paisa & Accounts', k: 'gst_sale', t: 'GST sale (rate-wise)', d: 'Bill ke hisab se 5% / 12% / 18% taxable aur GST', i: 'rupee', money: true },
    { g: 'Paisa & Accounts', k: 'collections', t: 'Collection', d: 'Kitna paisa mila, kis mode se, kisne liya', i: 'rupee', st: 'mode', stl: 'Mode', money: true },
    { g: 'Paisa & Accounts', k: 'receivable', t: 'Lena baaki (aging)', d: 'Customer-wise baaki aur kitne din se', i: 'clock', money: true },
    { g: 'Paisa & Accounts', k: 'purchase', t: 'Purchase register', d: 'Supplier se kharid, GST input, diya / baaki', i: 'cart', st: 'purchase', money: true },
    { g: 'Paisa & Accounts', k: 'payable', t: 'Dena baaki (suppliers)', d: 'Kis supplier ko kitna dena hai', i: 'clock', money: true },
    { g: 'Paisa & Accounts', k: 'expenses', t: 'Kharcha', d: 'Category-wise kharcha aur GST', i: 'rupee', cat: 'Category', catList: EXP_CATS, st: 'mode', stl: 'Mode', money: true },
    { g: 'Sales & Customers', k: 'quotes', t: 'Quotation register', d: 'Kisne kis customer ko kitne ki quotation di', i: 'quote', st: 'quote', user: true },
    { g: 'Sales & Customers', k: 'leads', t: 'Leads report', d: 'Source, status aur owner ke hisab se leads', i: 'lead', st: 'lead', cat: 'Source', user: true },
    { g: 'Field', k: 'plants', t: 'Plants report', d: 'Lage hue plants, kW, city, status', i: 'plant', st: 'plant', user: true },
    { g: 'Field', k: 'commission', t: 'Commission report', d: 'Dealer / influencer / staff ka commission', i: 'rupee', st: 'earning', user: true, need: function () { return C.canAny('earnings.view_all', 'earnings.manage'); } },
    { g: 'Stock', k: 'stock_value', t: 'Stock valuation', d: 'Item-wise stock aur uski keemat', i: 'box', cat: 'Category', money: true, need: function () { return C.canAny('items.view', 'accounts.view', 'accounts.manage'); } }
  ];
  function moneyOk() { return C.canAny('accounts.view', 'accounts.manage', 'invoices.view_all'); }
  function avail() { return REPORTS.filter(function (r) { if (r.need) return r.need(); if (r.money) return moneyOk(); return true; }); }
  function fyStart() { var t = C.today(), y = +t.slice(0, 4), m = +t.slice(5, 7); return (m >= 4 ? y : y - 1) + '-04-01'; }
  function presets() {
    var t = C.today(), m0 = t.slice(0, 8) + '01', pm = new Date(+t.slice(0, 4), +t.slice(5, 7) - 2, 1), pe = new Date(+t.slice(0, 4), +t.slice(5, 7) - 1, 0);
    var f = function (d) { return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); };
    return [['m', 'Is mahine', m0, t], ['pm', 'Pichhla mahina', f(pm), f(pe)], ['q', 'Pichhle 90 din', C.addDays(t, -90), t], ['fy', 'Is saal (FY)', fyStart(), t], ['y', 'Pichhle 12 mahine', C.addDays(t, -365), t]];
  }
  function cell(h, v) {
    if (v == null || v === '') return '';
    if (/^\d{4}-\d{2}-\d{2}/.test(String(v))) return esc(C.fd(String(v).slice(0, 10)));
    if (typeof v === 'number' && MONEY_H.test(h) && !/^din$|gst %/i.test(h)) return money(v);
    return esc(String(v));
  }
  function plain(rows) { return rows.map(function (r) { return r.map(function (v) { return /^\d{4}-\d{2}-\d{2}/.test(String(v == null ? '' : v)) ? C.fd(String(v).slice(0, 10)) : v == null ? '' : v; }); }); }
  function users() { return (C.cache.users || []).filter(function (u) { return u.role !== 'consumer' && u.status === 'active'; }); }

  C.mod('reports', {
    title: 'Reports',
    allowed: function () { return C.can('reports.view'); },
    render: async function (el, params, q) {
      var list = avail(), cur = q.r ? list.filter(function (x) { return x.k === q.r; })[0] : null;
      if (!cur) {
        var groups = {}; list.forEach(function (r) { (groups[r.g] = groups[r.g] || []).push(r); });
        el.innerHTML = '<div class="ph"><div><h1>Reports</h1><p>Report chunein, filter lagayein (tareekh, user, status, category) aur Excel me download karein.</p></div></div>' +
          Object.keys(groups).map(function (g) { return '<h4 style="margin:6px 0 10px">' + esc(g) + '</h4><div class="ch-tiles">' + groups[g].map(function (r) { return C.chart.tile({ l: r.t, v: ' ', sub: r.d, icon: r.i, c: r.money ? '#f2a900' : '#1e8e3e', href: '#/reports?r=' + r.k }).replace('<b class="ch-tv"> </b>', ''); }).join('') + '</div>'; }).join('');
        return;
      }
      var P = presets(), from = q.from || P[2][2], to = q.to || P[2][3], st = q.st || '', cat = q.c || '', uid = q.u || '', text = q.q || '';
      if (!q.from && !q.to) { from = P[3][2]; to = P[3][3]; }
      var sel = ST[cur.st] || null, canUser = cur.user && (C.can('analytics.all') || C.isAdmin());
      var bar = '<div class="card" style="margin-bottom:12px"><div style="margin-bottom:8px">' + C.chips(P.map(function (p) { return [p[0], p[1]]; }), (P.filter(function (p) { return from === p[2] && to === p[3]; })[0] || [''])[0], 'pre') + '</div>' +
        '<div class="row wrap"><span class="sm b">Se</span><input class="inp" type="date" data-f="from" value="' + esc(from) + '" style="width:auto"><span class="sm b">Tak</span><input class="inp" type="date" data-f="to" value="' + esc(to) + '" style="width:auto">' +
        (sel ? '<select class="inp" data-f="st" style="width:auto" title="' + esc(cur.stl || 'Status') + '">' + C.opts(sel, st) + '</select>' : '') +
        (canUser ? '<select class="inp" data-f="u" style="width:auto"><option value="">Sab users</option>' + users().map(function (u) { return '<option value="' + u.id + '"' + (String(u.id) === String(uid) ? ' selected' : '') + '>' + esc(u.name) + '</option>'; }).join('') + '</select>' : '') +
        (cur.cat ? '<input class="inp" data-f="c" list="rcats" value="' + esc(cat) + '" placeholder="' + esc(cur.cat) + '" style="width:auto;max-width:180px">' + (cur.catList ? '<datalist id="rcats">' + cur.catList.map(function (x) { return '<option value="' + esc(x) + '">'; }).join('') + '</datalist>' : '') : '') +
        '<input class="inp grow" type="search" data-f="q" value="' + esc(text) + '" placeholder="Naam / bill no khojein" style="min-width:140px"><button class="btn btn-p" data-go>Dikhayein</button></div></div>';
      el.innerHTML = '<div class="ph"><div><h1>' + esc(cur.t) + '</h1><p>' + esc(cur.d) + '</p></div><div class="row"><a class="btn btn-o" href="#/reports">' + C.ic('right') + ' Sab reports</a></div></div>' + bar + '<div id="rbody"><div class="card"><div class="spin"></div></div></div>';
      function go(extra) { var o = { r: cur.k, from: $('[data-f=from]', el).value, to: $('[data-f=to]', el).value, st: ($('[data-f=st]', el) || {}).value || '', c: ($('[data-f=c]', el) || {}).value || '', u: ($('[data-f=u]', el) || {}).value || '', q: $('[data-f=q]', el).value || '' }; C.go('#/reports' + C.qs(Object.assign(o, extra || {}))); }
      $('[data-go]', el).onclick = function () { go(); };
      $$('[data-f]', el).forEach(function (i) { i.addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); }); if (i.tagName === 'SELECT') i.onchange = function () { go(); }; });
      $$('[data-pre]', el).forEach(function (b) { b.onclick = function () { var p = P.filter(function (x) { return x[0] === b.getAttribute('data-pre'); })[0]; go({ from: p[2], to: p[3] }); }; });
      var R; try { R = await C.call('crm_report', { report: cur.k, from: from, to: to, status: st, category: cat, user_id: uid || null, q: text }); } catch (e) { $('#rbody', el).innerHTML = '<div class="card"><div class="note r">' + esc(e.message) + '</div></div>'; return; }
      var tot = R.head.map(function (h, i) { return !NOSUM_H.test(h) && MONEY_H.test(h) && R.rows.some(function (r) { return typeof r[i] === 'number'; }) ? R.rows.reduce(function (a, r) { return a + num(r[i]); }, 0) : null; });
      var shown = R.rows.slice(0, 500);
      $('#rbody', el).innerHTML = '<div class="card"><div class="hd"><h3>' + esc(R.title) + ' <span class="xs mute">' + esc(C.fd(R.from)) + ' – ' + esc(C.fd(R.to)) + ' · ' + R.rows.length + ' line</span></h3>' +
        (C.can('reports.download') ? C.reportBtns(R.title, function () { return { head: R.head, rows: plain(R.rows), text: R.title + ' ' + C.fd(R.from) + ' – ' + C.fd(R.to) }; }) : '<span class="xs mute">Download ki permission nahi</span>') + '</div>' +
        (R.rows.length ? '<div class="tw"><table class="t"><thead><tr>' + R.head.map(function (h, i) { return '<th' + (tot[i] != null || /^din$|gst %|kW|stock/i.test(h) ? ' class="r"' : '') + '>' + esc(h) + '</th>'; }).join('') + '</tr></thead><tbody>' +
          shown.map(function (r) { return '<tr>' + r.map(function (v, i) { return '<td' + (tot[i] != null || typeof v === 'number' ? ' class="r"' : '') + '>' + cell(R.head[i], v) + '</td>'; }).join('') + '</tr>'; }).join('') +
          (tot.some(function (x) { return x != null; }) ? '<tr style="font-weight:800;background:var(--paper,#f4f9f3)">' + R.head.map(function (h, i) { return '<td' + (tot[i] != null ? ' class="r"' : '') + '>' + (i === 0 ? 'Kul' : tot[i] != null ? money(tot[i]) : '') + '</td>'; }).join('') + '</tr>' : '') + '</tbody></table></div>' +
          (R.rows.length > shown.length ? '<p class="hint">Pehli 500 line dikh rahi hain — poori list ke liye Download karein.</p>' : '') : C.empty('quote', 'Is filter me koi line nahi', 'Tareekh ya status badal kar dekhein')) + '</div>';
    }
  });
})();
