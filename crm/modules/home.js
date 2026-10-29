/* Home dashboard — role based */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;


  /* ---- growth graphs (business / marketing / store / leads / maintenance) ---- */
  var MN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var DEFS = [
    { k: 'business', t: 'Pura business', money: true, lines: [['sales', 'Sale (bill)', '#2e7d32'], ['collected', 'Collection', '#f59e0b'], ['quotes', 'Quotation', '#1d4a9b']] },
    { k: 'marketing', t: 'Marketing', lines: [['leads', 'Leads', '#7c3aed'], ['won', 'Won', '#2e7d32']] },
    { k: 'store', t: 'Online Store', lines: [['orders', 'Orders', '#2e7d32'], ['enquiries', 'Enquiry', '#1d4a9b']] },
    { k: 'store', id: 'storeamt', t: 'Store ki bikri', money: true, lines: [['amount', 'Order amount', '#f59e0b']] },
    { k: 'leads', t: 'Leads', lines: [['new', 'Nayi leads', '#1d4a9b'], ['won', 'Won', '#2e7d32']] },
    { k: 'maintenance', t: 'Maintenance & AMC', lines: [['planned', 'Planned', '#1d4a9b'], ['done', 'Ho gayi', '#2e7d32']] }
  ];
  function compact(v, m) { v = Math.round(v); if (!m) return String(v); return v >= 1e7 ? (v / 1e7).toFixed(1).replace(/\.0$/, '') + 'Cr' : v >= 1e5 ? (v / 1e5).toFixed(1).replace(/\.0$/, '') + 'L' : v >= 1e3 ? (v / 1e3).toFixed(1).replace(/\.0$/, '') + 'K' : String(v); }
  C.lineChart = function (months, rows, lines, isMoney) {
    var W = 640, H = 230, L = 46, R = 12, T = 12, B = 26, n = months.length, mx = 1;
    lines.forEach(function (ln) { rows.forEach(function (r) { mx = Math.max(mx, +r[ln[0]] || 0); }); });
    var step = Math.pow(10, Math.floor(Math.log10(mx))), nice = Math.ceil(mx / step) * step; if (nice / step < 2) nice = step * 2; mx = nice;
    var x = function (i) { return n < 2 ? L : L + (W - L - R) * i / (n - 1); }, y = function (v) { return T + (H - T - B) * (1 - (+v || 0) / mx); };
    var s = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" style="width:100%;height:auto;max-width:100%">';
    for (var g = 0; g <= 4; g++) { var gv = mx * g / 4, gy = y(gv); s += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + gy + '" y2="' + gy + '" stroke="currentColor" stroke-opacity=".12"/><text x="' + (L - 6) + '" y="' + (gy + 4) + '" text-anchor="end" font-size="11" fill="currentColor" fill-opacity=".6">' + compact(gv, isMoney) + '</text>'; }
    months.forEach(function (mo, i) { if (n > 8 && i % 2 === 1 && i !== n - 1) return; s += '<text x="' + x(i) + '" y="' + (H - 6) + '" text-anchor="middle" font-size="11" fill="currentColor" fill-opacity=".6">' + MN[+mo.slice(5, 7) - 1] + '</text>'; });
    lines.forEach(function (ln) {
      var pts = rows.map(function (r, i) { return x(i) + ',' + y(r[ln[0]]); });
      s += '<polyline fill="none" stroke="' + ln[2] + '" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" points="' + pts.join(' ') + '"/>';
      rows.forEach(function (r, i) { s += '<circle cx="' + x(i) + '" cy="' + y(r[ln[0]]) + '" r="3.2" fill="' + ln[2] + '"><title>' + MN[+months[i].slice(5, 7) - 1] + ' ' + months[i].slice(0, 4) + ' · ' + ln[1] + ': ' + (isMoney ? money(r[ln[0]]) : (r[ln[0]] || 0)) + '</title></circle>'; });
    });
    return s + '</svg>';
  };
  async function growthCard(box, partner) {
    if (!box) return;
    var S; try { S = await C.call('crm_series', { months: 12 }); } catch (e) { return; }
    var defs = DEFS.filter(function (d) { return S[d.k] && S[d.k].length && (!d.money || C.can('dashboard.money')); });
    if (!defs.length) return;
    var cur = 0, span = 12;
    function draw() {
      var d = defs[cur], rows = S[d.k], months = S.months.slice(), r = rows;
      if (span < 12) { months = months.slice(-span); r = rows.slice(-span); }
      var sums = d.lines.map(function (ln) { var a = r.reduce(function (m, x) { return m + (+x[ln[0]] || 0); }, 0), last = +r[r.length - 1][ln[0]] || 0, prev = r.length > 1 ? (+r[r.length - 2][ln[0]] || 0) : 0, pc = prev ? Math.round((last - prev) * 100 / prev) : null;
        return '<div class="gk"><span class="gd" style="background:' + ln[2] + '"></span><div><div class="xs mute">' + esc(ln[1]) + '</div><b>' + (d.money ? money(a) : a) + '</b><div class="xs mute">Is mahine ' + (d.money ? money(last) : last) + (pc == null ? '' : ' · <span style="color:' + (pc >= 0 ? '#2e7d32' : '#c0392b') + ';font-weight:700">' + (pc >= 0 ? '▲ ' : '▼ ') + Math.abs(pc) + '%</span>') + '</div></div></div>'; }).join('');
      box.innerHTML = '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>' + C.ic('activity') + ' Growth</h3><div class="row wrap"><select class="inp" data-gs style="width:auto"><option value="6"' + (span === 6 ? ' selected' : '') + '>6 mahine</option><option value="12"' + (span === 12 ? ' selected' : '') + '>12 mahine</option></select></div></div>' +
        '<div class="tabs" style="margin-bottom:10px">' + defs.map(function (x, i) { return '<button data-g="' + i + '" class="' + (i === cur ? 'on' : '') + '">' + esc(x.t) + '</button>'; }).join('') + '</div>' +
        '<div class="gks">' + sums + '</div><div style="color:var(--ink,#222);margin-top:6px">' + C.lineChart(months, r, d.lines, d.money) + '</div></div>';
      $$('[data-g]', box).forEach(function (b) { b.onclick = function () { cur = +b.getAttribute('data-g'); draw(); }; });
      var sel = $('[data-gs]', box); sel.onchange = function () { span = +sel.value; draw(); };
    }
    draw();
  }
  async function maintCard(box, partner) {
    if (!box || partner || !C.canAny('items.view', 'reminders.view_all')) return;
    var V; try { V = (await C.list('reminder', { limit: 3000 })).filter(function (x) { return x.data && x.data.maint && x.status !== 'done'; }); } catch (e) { return; }
    var t0 = C.today(), t7 = C.addDays(t0, 7), due = V.filter(function (x) { return x.due_at && x.due_at <= t7; }).sort(function (a, b) { return String(a.due_at).localeCompare(String(b.due_at)); });
    if (!due.length) return;
    box.innerHTML = '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>' + C.ic('settings') + ' Maintenance & AMC — agli 7 din</h3><a class="btn btn-g btn-sm" href="#/maintenance">Sab dekhein ' + C.ic('right') + '</a></div><div class="list" style="border:0">' + due.slice(0, 6).map(function (x) {
      var nm = x.data.party_name || x.title, late = x.due_at < t0;
      return '<div class="li' + (late ? ' over' : '') + '"><span class="grow"><span class="t">' + esc(nm) + (late ? ' ' + C.pill('Overdue', 'r') : '') + '</span><span class="m"><span>' + esc(x.data.plan_name || '') + '</span><span>' + C.fd(x.due_at) + '</span></span></span>' +
        (x.mobile ? '<a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(x.mobile, 'Namaste ' + nm + ' ji, aapke solar plant ki ' + (x.data.plan_name || 'maintenance') + ' service ' + C.fd(x.due_at) + ' ko due hai. Kya hum aa sakte hain?')) + '">WhatsApp</a>' : '') + '</div>';
    }).join('') + '</div></div>';
  }

  /* ---- Round 13: role-wise cards (pipeline, this-month table, daily bars, stair, sources, aging, team) ---- */
  var MET = [['leads_new', 'Nayi leads', false], ['leads_won', 'Leads won', false], ['quotes_n', 'Quotation', false], ['quotes_amt', 'Quotation ki value', true], ['bills_n', 'Bills', false], ['sales', 'Sale (bill)', true], ['collected', 'Collection', true], ['customers_new', 'Naye customers', false], ['plants_n', 'Plants', false], ['kw', 'kW lage', false]];
  function dashCards(box, D, partner) {
    if (!box || !D) return;
    var ch = C.chart, cur = D.cur || {}, prev = D.prev || {}, h = '', day = D.daily || [];
    var rows = MET.filter(function (m) { return cur[m[0]] != null; }).filter(function (m) { return !(partner && m[2]); }).map(function (m) {
      var a = +cur[m[0]] || 0, b = +prev[m[0]] || 0, ch_ = b ? Math.round((a - b) * 100 / b) : (a ? 100 : 0), up = a >= b;
      return '<tr><td>' + esc(m[1]) + '</td><td class="r"><b>' + (m[2] ? money(a) : a) + '</b></td><td class="r mute">' + (m[2] ? money(b) : b) + '</td><td class="r" style="color:' + (up ? '#1e8e3e' : '#d64545') + '">' + (up ? '▲ ' : '▼ ') + Math.abs(ch_) + '%</td></tr>';
    }).join('');
    h += '<div class="ch-grid2"><div class="card"><div class="hd"><h3>' + C.ic('activity') + ' Is mahine ka hisab</h3><span class="xs mute">pichhle mahine se tulna</span></div><div class="tw"><table class="t"><thead><tr><th></th><th class="r">Is mahine</th><th class="r">Pichhle</th><th class="r">Badlav</th></tr></thead><tbody>' + rows + '</tbody></table></div></div>';
    h += '<div class="card"><div class="hd"><h3>Leads ki pipeline</h3><a class="btn btn-g btn-sm" href="#/leads">Leads ' + C.ic('right') + '</a></div>' + ch.donut((D.leads_by_status || []).map(function (x) { return { l: x.s, v: x.n }; }), { label: 'Lead pipeline' }) + '</div>';
    var bars = day.map(function (x) { return { l: x.d.slice(8), vs: D.money ? [x.leads, x.quotes, +x.sales || 0] : [x.leads, x.quotes] }; });
    if (D.money) {
      var cum = 0; h += '<div class="card"><div class="hd"><h3>Sale — pichhle 14 din</h3></div>' + ch.stair(day.map(function (x) { cum += +x.sales || 0; return { l: x.d.slice(8), v: cum }; }), { color: '#f2a900', label: 'Cumulative sale' }) + '</div>';
    } else {
      var c2 = 0; h += '<div class="card"><div class="hd"><h3>Leads — pichhle 14 din</h3></div>' + ch.stair(day.map(function (x) { c2 += +x.leads || 0; return { l: x.d.slice(8), v: c2 }; }), { color: '#7b4fd1', label: 'Cumulative leads' }) + '</div>';
    }
    h += '<div class="card"><div class="hd"><h3>Roz ka kaam — 14 din</h3></div>' + ch.bars(day.map(function (x) { return { l: x.d.slice(8), vs: [x.leads, x.quotes] }; }), { series: [{ n: 'Leads', c: '#7b4fd1' }, { n: 'Quotation', c: '#2f6fdb' }], label: 'Daily leads and quotes' }) + '</div>';
    h += '<div class="card"><div class="hd"><h3>Quotation ki halat</h3><a class="btn btn-g btn-sm" href="#/quotes">Quotation ' + C.ic('right') + '</a></div>' + ch.donut((D.quotes_by_status || []).map(function (x) { return { l: x.s, v: x.n }; }), { label: 'Quotes by status' }) + '</div>';
    if ((D.sources || []).length) h += '<div class="card"><div class="hd"><h3>Lead kahan se (90 din)</h3></div>' + ch.hbars(D.sources.map(function (x) { return { l: x.s, v: x.n, sub: x.n + (x.won ? ' · won ' + x.won : '') }; })) + '</div>';
    if (D.aging) h += '<div class="card"><div class="hd"><h3>Baaki lena — kitne din purana</h3><a class="btn btn-g btn-sm" href="#/accounts?tab=receivable">Customer-wise ' + C.ic('right') + '</a></div>' + ch.bars([{ l: '0-30', v: +D.aging.b0 }, { l: '31-60', v: +D.aging.b30 }, { l: '61-90', v: +D.aging.b60 }, { l: '90+', v: +D.aging.b90 }], { color: '#d64545', label: 'Receivable aging' }) + '</div>';
    if ((D.top_customers || []).length) h += '<div class="card"><div class="hd"><h3>Sabse bade customers</h3></div>' + ch.hbars(D.top_customers.map(function (x) { return { l: x.name, v: x.amt, sub: money(x.amt) }; })) + '</div>';
    h += '</div>';
    if (D.team && D.team.length) {
      h += '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>' + C.ic('team') + ' Team — is mahine</h3><a class="btn btn-g btn-sm" href="#/staffs?tab=perf">Poori performance ' + C.ic('right') + '</a></div><div class="tw"><table class="t"><thead><tr><th>Naam</th><th class="r">Khuli leads</th><th class="r">Overdue</th><th class="r">Quotation</th>' + (D.money ? '<th class="r">Sale</th><th>Target</th>' : '') + '</tr></thead><tbody>' +
        D.team.map(function (u) { var pc = u.target && +u.target > 0 && u.sales_m != null ? Math.min(100, Math.round(100 * u.sales_m / u.target)) : null; return '<tr><td><b>' + esc(u.name) + '</b><div class="xs mute">' + esc(C.ROLE[u.role] || u.role) + '</div></td><td class="r">' + u.leads_open + '</td><td class="r' + (u.overdue ? ' bad' : '') + '">' + u.overdue + '</td><td class="r">' + u.quotes_m + '</td>' + (D.money ? '<td class="r">' + money(u.sales_m || 0) + '</td><td style="min-width:90px">' + (pc == null ? '<span class="xs mute">—</span>' : ch.progress(pc) + ' <span class="xs">' + pc + '%</span>') + '</td>' : '') + '</tr>'; }).join('') + '</tbody></table></div></div>';
    }
    box.innerHTML = h;
  }
  async function stockCard(box, tiles, partner) {
    if (!box || partner || !C.can('stock.view')) return;
    var S; try { S = await C.call('crm_stock_report', {}); } catch (e) { return; }
    var low = (S.rows || []).filter(function (x) { return x.level === 'low' || x.level === 'out'; });
    if (tiles) tiles.insertAdjacentHTML('beforeend', C.chart.tile({ l: 'Stock alert', v: low.length, sub: low.length ? 'Kam / khatam items' : 'Sab theek', icon: 'box', c: low.length ? '#d64545' : '#1e8e3e', href: '#/items?tab=stock' }));
    if (!low.length) return;
    box.innerHTML = '<div class="card" style="margin-bottom:16px;border-color:#f0b7b7"><div class="hd"><h3>' + C.ic('alert') + ' Stock kam hai — ' + low.length + ' item</h3><a class="btn btn-g btn-sm" href="#/items?tab=stock">Stock dashboard ' + C.ic('right') + '</a></div><div class="list">' + low.slice(0, 6).map(function (x) {
      return '<div class="li"><span class="grow"><span class="t">' + esc(x.name) + '</span><span class="m"><span>' + esc(x.sku || '') + '</span><span>Stock ' + x.on_hand + ' ' + esc(x.unit || '') + '</span><span>Online ke liye bacha ' + x.online_left_pct + '%</span></span></span>' + C.pill(x.level === 'out' ? 'Khatam' : 'Kam', x.level === 'out' ? 'r' : 'o') + '</div>'; }).join('') + '</div></div>';
  }

  C.mod('home', {
    title: 'Home',
    render: async function (el) {
      var me = C.me, partner = C.isPartner(), res = await Promise.all([C.call('crm_dashboard', {}), C.call('crm_today_list', {}).catch(function () { return { items: [] }; }), C.call('crm_dash2', {}).catch(function () { return null; })]);
      var d = res[0], t = res[1].items || [], d2 = res[2], hr = new Date().getHours(), greet = hr < 12 ? 'Suprabhat' : hr < 17 ? 'Namaste' : 'Shubh sandhya';
      C.updateTodayCount(t.length);
      var over = t.filter(function (x) { return x.overdue; }).length;
      var h = '<div class="hero-card"><h2>' + greet + ', ' + esc(me.name.split(' ')[0]) + ' 👋</h2><p>' + (t.length ? 'Aaj ' + t.length + ' kaam hain' + (over ? ' — <b style="color:var(--sun)">' + over + ' overdue</b>' : '') : 'Aaj ka koi kaam baaki nahi — badhiya!') + '</p><div class="row wrap">' +
        '<a class="btn btn-s" href="#/today">' + C.ic('today') + ' Aaj ke kaam</a>' +
        ((C.canAny('customers.create', 'customers.view_all') || C.isPartner()) ? '<a class="btn btn-o" href="#/customers">' + C.ic('users') + ' All Customers</a>' : '') +
        (C.storeUrl() ? '<a class="btn btn-o" href="' + esc(partner ? C.refLink() : C.storeUrl()) + '" target="_blank" rel="noopener">' + C.ic('store') + ' Visit Store</a>' : '') +
        (C.siteUrl() ? '<a class="btn btn-o" href="' + esc(C.siteUrl()) + '" target="_blank" rel="noopener">' + C.ic('globe') + ' Visit Website</a>' : '') +
        (partner && me.ref_code ? '<button class="btn btn-o" data-act="ref">' + C.ic('share') + ' Mera store link</button>' : '') + '</div></div>';

      var k = [], DAY = d2 && d2.daily ? d2.daily : [], kt = function (label, val, sub, cls, href, icon, c, key) { return C.chart.tile({ l: label, v: String(val).replace(/<[^>]+>/g, ''), sub: String(sub || '').replace(/<[^>]+>/g, ''), icon: icon, href: href, c: c || (cls === 'warn' ? '#e0742c' : cls === 'gold' ? '#f2a900' : cls === 'red' ? '#d64545' : '#1e8e3e'), spark: key && DAY.length ? C.chart.spark(DAY.map(function (x) { return +x[key] || 0; }), c) : '' }); };
      if (partner) {
        k.push(kt('Kul plants', d.plants, num(d.plants_kw) + ' kW lage' + (d.plants_pending ? ' · ' + d.plants_pending + ' verify baaki' : ''), 'gold', '#/plants', 'plant'));
        k.push(kt('Commission baaki', money(d.earn_due), 'Mil chuka: ' + money(d.earn_paid), '', '#/commission', 'rupee'));
        k.push(kt('Mere customers', d.customers, '', '', '#/customers', 'users'));
        k.push(kt('Is mahine quotation', d.quotes_count, money(d.quotes_month), '', '#/quotes', 'quote', '#2f6fdb', 'quotes'));
        k.push(kt('Khuli leads', d.leads_open, d.leads_new + ' nayi', '', '#/leads', 'lead', '#7b4fd1', 'leads'));
      } else {
        if (C.canAny('invoices.view_all', 'invoices.create') && C.can('dashboard.money')) { k.push(kt('Is mahine ki sale', money(d.sales_month), 'Collection: ' + money(d.collected_month), 'gold', '#/billing', 'bill', '#f2a900', 'sales')); k.push(kt('Lena baaki (Receivable)', money(d.receivable), '', num(d.receivable) > 0 ? 'warn' : '', '#/billing?tab=due', 'rupee')); }
        if (C.canAny('quotes.view_all', 'quotes.create')) k.push(kt('Is mahine quotation', d.quotes_count, money(d.quotes_month), '', '#/quotes', 'quote', '#2f6fdb', 'quotes'));
        if (C.canAny('leads.view_all', 'leads.create')) k.push(kt('Khuli leads', d.leads_open, d.leads_new + ' nayi', '', '#/leads', 'lead', '#7b4fd1', 'leads'));
        k.push(kt('Customers', d.customers, '', '', '#/customers', 'users'));
        if (C.canAny('plants.view_all', 'plants.create')) k.push(kt('Plants lage', d.plants, num(d.plants_kw) + ' kW' + (d.plants_pending ? ' · ' + d.plants_pending + ' verify baaki' : ''), d.plants_pending ? 'warn' : '', '#/plants' + (d.plants_pending ? '?status=pending' : ''), 'plant'));
        if (d.orders_new != null) k.push(kt('Naye store order', d.orders_new, d.enquiries_new + ' nayi enquiry', d.orders_new || d.enquiries_new ? 'warn' : '', '#/orders', 'cart'));
        if (d.users_pending) k.push(kt('ID verify karni hai', d.users_pending, 'Dealer / Influencer', 'warn', '#/partners?tab=pending', 'user'));
        if (d.store_pending) k.push(kt('Store review baaki', d.store_pending, 'Online Store Admin me', '', '#/items?store=pending', 'store'));
        if (C.canAny('earnings.view_all', 'earnings.manage')) k.push(kt('Commission dena baaki', money(d.earn_due), 'Diya: ' + money(d.earn_paid), '', '#/commission', 'rupee'));
      }
      h += '<div class="ch-tiles" id="tiles">' + k.join('') + '</div>';
      var tgt = num(d.target);
      if (tgt > 0) { var done = partner ? num(d.quotes_month) : num(d.sales_month), pc = Math.min(100, Math.round(done * 100 / tgt)); h += '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>Is mahine ka target</h3><span class="b">' + money(done) + ' / ' + money(tgt) + '</span></div><div style="height:10px;border-radius:6px;background:var(--mint);overflow:hidden"><div style="height:100%;width:' + pc + '%;background:linear-gradient(90deg,var(--leaf),var(--sun))"></div></div><p class="xs mute" style="margin-top:6px">' + pc + '% poora</p></div>'; }

      h += '<div id="dbox"></div><div id="sbox"></div><div id="gbox"></div><div id="mbox"></div>';
      if (C.can('marketing.leads') && !partner) {
        try { var MS = await C.call('crm_mkt_stats', {}); if ((MS.sources || []).length) h += '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>' + C.ic('megaphone') + ' Lead kahan se aayi</h3><a class="btn btn-g btn-sm" href="#/marketing">Poori report ' + C.ic('right') + '</a></div>' + C.sourceReport(MS, (C.cache.settings || {}).marketing || {}, true) + '</div>'; } catch (e) {}
      }
      h += '<div class="grid g2"><div class="card"><div class="hd"><h3>Aaj ke kaam</h3><a class="btn btn-g btn-sm" href="#/today">Sab dekhein ' + C.ic('right') + '</a></div>' +
        (t.length ? '<div class="list" style="border:0">' + t.slice(0, 6).map(function (x) { var rt = C.RTYPE[x.kind] || C.RTYPE.other; return '<a class="li' + (x.overdue ? ' over' : '') + '" href="#/today"><span class="av' + (x.overdue ? ' r' : '') + '">' + C.ic(x.src === 'invoice' ? 'rupee' : x.src === 'quote' ? 'quote' : rt[1]) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(x.src === 'invoice' ? 'Payment lena' : x.src === 'quote' ? 'Quotation bhejna' : rt[0]) + '</span><span>' + esc(C.fd(x.due_at)) + '</span></span></span>' + (num(x.amount) ? '<span class="amt">' + money(x.amount) + '</span>' : '') + '</a>'; }).join('') + '</div>' : C.empty('check', 'Sab kaam ho gaye', 'Naya kaam jodne ke liye "Reminder" dabayein')) + '</div>';
      h += '<div class="card"><div class="hd"><h3>Notice board</h3>' + (C.can('settings.manage') ? '<a class="btn btn-g btn-sm" href="#/settings?tab=notices">' + C.ic('plus') + ' Notice</a>' : '') + '</div>' +
        ((d.notices || []).length ? '<div class="stack">' + d.notices.map(function (n) { return '<div class="note g"><b>' + esc(n.title) + '</b>' + (n.body ? '<div class="sm" style="margin-top:3px;white-space:pre-line">' + esc(n.body) + '</div>' : '') + '<div class="xs mute" style="margin-top:4px">' + esc(C.ago(n.at)) + '</div></div>'; }).join('') + '</div>' : C.empty('megaphone', 'Abhi koi notice nahi')) + '</div></div>';
      el.innerHTML = h;
      dashCards($('#dbox', el), d2, partner); stockCard($('#sbox', el), $('#tiles', el), partner);
      if (C.canAny('analytics.view', 'dashboard.money')) growthCard($('#gbox', el), partner); maintCard($('#mbox', el), partner);
      C.bind(el, {
        ref: function () { C.copy(C.refLink(), 'Aapka store link copy ho gaya — WhatsApp par bhejein'); },
      });
    }
  });
})();
