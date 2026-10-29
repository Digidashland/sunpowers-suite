/* Customers — list + detail (quotations, bills, payments, ledger, reminders, documents, notes) */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;

  /* Round 35: ONE list screen, two modes. 'customers' = billed customers (+ suppliers); 'inquiries' = Pending Inquiries (customer added, no bill yet — removed only by manual delete) */
  C.mod('customers', {
    title: 'Customers', nav: 'customers',
    allowed: function () { return C.canAny('customers.create', 'customers.view_all') || C.isPartner(); },
    render: function (el, params, q) { return listView(el, q, 'customers'); }
  });
  C.mod('inquiries', {
    title: 'Pending Inquiries', nav: 'inquiries',
    allowed: function () { return C.canAny('customers.create', 'customers.view_all'); },
    render: function (el, params, q) { return listView(el, q, 'inquiries'); }
  });
  async function listView(el, q, mode) {
      var inq = mode === 'inquiries', R = '#/' + mode;
      var viewAll = C.can('customers.view_all'), uid = q.user || '', type = q.type || '';
      var all = (await C.list('party', { limit: 3000, user_id: uid || null })).filter(function (p) { var st = (p.data && p.data.stage) || ''; return inq ? st === 'inquiry' : st !== 'inquiry'; });
      var kindOf = function (p) { return p.data.cust_kind === 'product' ? 'product' : p.data.cust_kind === 'service' ? 'service' : 'project'; };
      /* Round 33: a customer never leaves this list. Each purchase is a separate job (quotation) — kinds and state come from ALL of them. */
      var byParty = {}; (await C.list('quote', { limit: 3000 }).catch(function () { return []; })).forEach(function (x) { if (x.party_id) (byParty[x.party_id] = byParty[x.party_id] || []).push(x); });
      var jstate = function (x) { var dd = x.data || {}; return dd.closed ? 'done' : x.status === 'rejected' ? 'lost' : (x.status === 'accepted' || x.status === 'converted') ? 'running' : 'quote'; };
      var kindsOf = function (p) { var ks = [kindOf(p)]; (byParty[p.id] || []).forEach(function (x) { var k = C.FLOW.kindOfCtype(x.data.ctype); if (k && ks.indexOf(k) < 0) ks.push(k); }); return ks; };
      var stateOf = function (p) { var js = (byParty[p.id] || []).map(jstate); return js.indexOf('running') >= 0 ? 'running' : js.indexOf('done') >= 0 ? 'done' : js.indexOf('quote') >= 0 ? 'quote' : ''; };
      var isOnline = function (p) { return !!(p.data.store_order_id || p.data.intake === 'store' || p.data.intake === 'online-order'); };
      var STL = { running: ['Kaam chal raha', 'o'], done: ['Kaam poora hua', 'g'], quote: ['Quotation', 'b'] };
      var list = all.filter(function (p) {
        var t = p.data.type || 'customer'; if (!type) return true;
        if (type === 'project' || type === 'product' || type === 'service') return t !== 'supplier' && kindsOf(p).indexOf(type) >= 0;
        if (type === 'running' || type === 'done') return t !== 'supplier' && stateOf(p) === type;
        if (type === 'b2b') return t !== 'supplier' && p.data.segment === 'b2b';
        if (type === 'online') return t !== 'supplier' && isOnline(p);
        if (type === 'adhuri') return C.detailsMissing(p).length > 0;
        if (type === 'old') return (Date.now() - new Date(p.created_at).getTime()) > 30 * 86400000;
        return t === type || t === 'both';
      });
      var cnt = function (f) { return all.filter(f).length; };
      var h = '<div class="ph"><div><h1>' + (inq ? 'Pending Inquiries' : 'Customers') + '</h1><p>' + (inq ? all.length + ' inquiry' + (viewAll ? '' : ' — sirf aapki') + '. Jinhone service / product maanga hai par abhi bill nahi bana — pehla bill bante hi ye customer All Customers me chale jayenge. Ye apne aap kabhi nahi hatti; sirf manual delete se. ' : all.length + ' customers' + (viewAll ? '' : ' — sirf aapke') + '. Kisi bhi platform (CRM, website, store, lead) se aaye — sab yahin. Ek mobile number = ek customer. Naya customer jodne se pehle path (kahan se aaya) chunna hota hai.') + '</p></div><div class="row">' +
        (C.can('customers.export') ? C.reportBtns('Customers', function () { return { head: ['Naam', 'Mobile', 'Email', 'Shahar', 'Pata', 'GSTIN', 'Company', 'Prakar', 'Project / Product', 'B2C / B2B', 'Source', 'Kiske paas', 'Bana'], rows: list.map(function (p) { return [p.title, p.mobile || '', p.data.email || '', p.data.city || '', p.data.address || '', p.data.gstin || '', p.data.company || '', p.data.type || 'customer', (p.data.type || 'customer') === 'supplier' ? '' : kindOf(p), p.data.segment || '', p.data.source || '', p.owner_name || '', C.fd(p.created_at)]; }) }; }) : '') +
        (C.can('customers.create') ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + (inq ? ' Nayi Inquiry' : ' Add New Customer') + '</button>' : '') + '</div></div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Naam / mobile / ID / shahar khojein">' + C.chips(inq ? [['', 'Sab', all.length], ['project', 'Project', cnt(function (p) { return kindsOf(p).indexOf('project') >= 0; })], ['product', 'Product', cnt(function (p) { return kindsOf(p).indexOf('product') >= 0; })], ['service', 'Service', cnt(function (p) { return kindsOf(p).indexOf('service') >= 0; })], ['old', 'Purani (30+ din)', cnt(function (p) { return (Date.now() - new Date(p.created_at).getTime()) > 30 * 86400000; })]] : [['', 'Sab', all.length], ['project', 'Project', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && kindsOf(p).indexOf('project') >= 0; })], ['product', 'Product', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && kindsOf(p).indexOf('product') >= 0; })], ['service', 'Service', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && kindsOf(p).indexOf('service') >= 0; })], ['running', 'Kaam chal raha', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && stateOf(p) === 'running'; })], ['done', 'Kaam poora hua', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && stateOf(p) === 'done'; })], ['b2b', 'Business (B2B)', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && p.data.segment === 'b2b'; })], ['online', 'Online order', cnt(function (p) { return (p.data.type || 'customer') !== 'supplier' && isOnline(p); })], ['adhuri', 'Details adhuri', cnt(function (p) { return C.detailsMissing(p).length > 0; })], ['supplier', 'Suppliers']], type, 'type') + (viewAll ? C.userFilter(uid, 'Sabhi users') : '') + '</div>';
      h += list.length ? '<div class="list" id="cl">' + list.map(function (p) {
        return '<div class="li click" data-href="#/customer/' + p.id + '"><span class="av">' + esc(C.initials(p.title)) + '</span><span class="grow"><span class="t">' + esc(p.title) + (p.data.cust_id ? ' <span class="mute xs" title="Customer ID">' + esc(p.data.cust_id) + '</span>' : '') + (p.data.type === 'supplier' ? C.pill('Supplier', 'b') : kindsOf(p).map(function (k) { return C.kindPill(k); }).join('') + (p.data.segment === 'b2b' ? C.pill('B2B', 'g') : '') + (isOnline(p) ? C.pill('Online order', 'b') : '') + (C.detailsMissing(p).length ? C.pill('Details adhuri', 'o') : '') + (STL[stateOf(p)] ? C.pill(STL[stateOf(p)][0], STL[stateOf(p)][1]) : '')) + '</span><span class="m"><span>' + C.ic(p.mobile ? 'phone' : 'mail') + esc(p.mobile || p.data.email || '') + '</span>' + (p.data.city ? '<span>' + esc(p.data.city) + '</span>' : '') + (p.data.company ? '<span>' + esc(p.data.company) + '</span>' : '') + (p.data.type !== 'supplier' ? '<span title="Path">' + C.ic('lead') + esc(p.data.source || 'Purana / Unknown') + '</span>' : '') + (viewAll ? '<span>' + C.ic('user') + esc(p.owner_name || '') + '</span>' : '') + '</span></span><span class="acts">' + (p.mobile ? C.callBtns(p.mobile) : '') + '</span>' + C.ic('right') + '</div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('users', inq ? 'Koi pending inquiry nahi' : 'Koi customer nahi', inq ? 'Naya customer / inquiry yahan aayegi, bill banne par All Customers me chali jayegi' : (C.can('customers.create') ? '"Add New Customer" dabayein' : '')) + '</div>';
      el.innerHTML = h;
      var cl = $('#cl', el); if (cl) C.filterList($('[data-q]', el), cl);
      el.addEventListener('click', function (e) { var c = e.target.closest('[data-type]'); if (c) C.go(R + C.qs({ type: c.getAttribute('data-type'), user: uid })); });
      var us = $('[data-user]', el); if (us) us.onchange = function () { C.go(R + C.qs({ type: type, user: this.value })); };
      /* Round 38: naya customer = Conversation form; Save ke baad seedha uske kaam ka agla step (Save & Next) */
      C.bind(el, { add: async function () { var r = await C.partyForm(null, { okLabel: 'Save & Next' }); if (!r || !r.id) return; var pt = r; try { pt = await C.get(r.id); } catch (e) {}
        if ((pt.data || {}).type !== 'supplier' && C.can('quotes.create') && C.startJob) { try { await C.startJob(pt.id, C.ctypeOfParty(pt)); return; } catch (e) {} } C.go('#/customer/' + r.id); } });
  }

  /* ledger rows: opening + bills (debit) + payments (credit) */
  C.ledger = function (party, invs, pays) {
    var rows = [], bal = num(party.data.opening);
    if (bal) rows.push({ date: party.created_at.slice(0, 10), t: 'Opening balance', ref: '', dr: bal, cr: 0 });
    invs.forEach(function (i) { rows.push({ date: i.data.date || i.created_at.slice(0, 10), t: 'Bill', ref: i.ref, dr: num(i.amount), cr: 0, id: i.id, k: 'invoice' }); });
    pays.forEach(function (p) { rows.push({ date: p.due_at, t: 'Payment (' + (p.data.mode || '') + ')', ref: p.ref + (p.data.utr ? ' / ' + p.data.utr : ''), dr: 0, cr: num(p.amount), id: p.id, k: 'payment' }); });
    rows.sort(function (a, b) { return a.date < b.date ? -1 : a.date > b.date ? 1 : a.dr ? -1 : 1; });
    var run = 0; rows.forEach(function (r) { run += r.dr - r.cr; r.bal = run; });
    return rows;
  };
  C.ledgerHtml = function (party, rows) {
    var co = C.company();
    return '<style>' + C.BILL_CSS + '</style><div class="bill" data-noi18n><div class="hdw"><table class="hd"><tr><td><h1>' + esc(co.legal || co.name || '') + '</h1><div class="sm">' + esc(co.address || '') + (co.phone ? '<br>Ph: ' + esc(co.phone) : '') + (co.gstin ? '<br>GSTIN: ' + esc(co.gstin) : '') + '</div></td><td><div class="ttl">LEDGER STATEMENT</div><div class="sm r">Date: ' + C.fd(C.today()) + '</div></td></tr></table></div>' +
      '<div class="box" style="margin-bottom:12px"><b class="h">Party</b><strong>' + esc(party.title) + '</strong><div class="sm">' + esc(party.mobile || '') + (party.data.address ? '<br>' + esc(party.data.address) : '') + (party.data.gstin ? '<br>GSTIN: ' + esc(party.data.gstin) : '') + '</div></div>' +
      '<table class="it"><thead><tr><th>Date</th><th>Detail</th><th>Ref</th><th class="r">Debit (Bill)</th><th class="r">Credit (Paid)</th><th class="r">Balance</th></tr></thead><tbody>' + rows.map(function (r) { return '<tr><td>' + C.fd(r.date) + '</td><td>' + esc(r.t) + '</td><td>' + esc(r.ref || '') + '</td><td class="r">' + (r.dr ? money(r.dr, 1) : '') + '</td><td class="r">' + (r.cr ? money(r.cr, 1) : '') + '</td><td class="r">' + money(r.bal, 1) + '</td></tr>'; }).join('') + '</tbody></table>' +
      '<div class="words"><b>Closing balance:</b> ' + money(rows.length ? rows[rows.length - 1].bal : 0, 1) + (rows.length && rows[rows.length - 1].bal > 0 ? ' (lena baaki)' : '') + '</div>' + C.pstrip() + '</div>';
  };

  C.mod('customer', {
    title: 'Customer', nav: 'customers',
    render: async function (el, params, q) {
      var id = params[0], p = await C.get(id), tab = q.tab === 'quotes' ? 'jobs' : (q.tab || 'overview');
      var res = await Promise.all([
        C.list('quote', { party_id: id }).catch(function () { return []; }), C.list('invoice', { party_id: id }).catch(function () { return []; }),
        C.list('payment', { party_id: id }).catch(function () { return []; }), C.list('reminder', { party_id: id }).catch(function () { return []; }),
        C.list('doc', { party_id: id }).catch(function () { return []; }), C.list('note', { party_id: id }).catch(function () { return []; }),
        C.list('plant', { party_id: id }).catch(function () { return []; })
      ]);
      var qs = res[0], inv = res[1], pay = res[2], rem = res[3], docs = res[4], notes = res[5], plants = res[6], d = p.data || {};
      var isSup = (d.type || 'customer') === 'supplier', kind = d.cust_kind === 'product' ? 'product' : d.cust_kind === 'service' ? 'service' : 'project', hasProject = kind === 'project' || plants.length || qs.some(function (x) { return C.FLOW.kindOfCtype(x.data.ctype) === 'project'; });
      var kinds = [kind]; qs.forEach(function (x) { var k = C.FLOW.kindOfCtype(x.data.ctype); if (k && kinds.indexOf(k) < 0) kinds.push(k); });
      var billed = C.sum(inv, 'amount'), paid = C.sum(pay, 'amount'), bal = num(d.opening) + billed - paid;
      var h = '<div class="crumb"><a href="#/customers">Customers</a>' + C.ic('right') + '<span>' + esc(p.title) + '</span></div>';
      h += '<div class="ph"><div><h1>' + esc(p.title) + '</h1>' + (!isSup && d.cust_id ? '<p style="margin:2px 0"><b title="Customer ID">' + esc(d.cust_id) + '</b> ' + (d.stage === 'inquiry' ? C.pill('Pending Inquiry', 'o') + ' <span class="xs mute">Pehla bill bante hi All Customers me aa jayega</span>' : C.pill('Customer', 'g')) + '</p>' : '') + '<p>' + (isSup ? '' : kinds.map(function (k) { return C.kindPill(k); }).join('') + (d.segment === 'b2b' ? C.pill('B2B', 'g') : '') + ' ') + esc([p.mobile, d.email, d.city, d.company].filter(Boolean).join(' · ')) + (p.owner_name ? ' · ' + C.ic('user') + ' ' + esc(p.owner_name) : '') + '</p></div><div class="row">' + (p.mobile ? C.callBtns(p.mobile, 'Namaste ' + p.title + ' ji, ') : '') +
        (C.can('customers.edit') ? '<button class="btn btn-o" data-act="edit">' + C.ic('edit') + ' Details badlein (Conversation)</button>' : '') + (C.can('quotes.create') && !isSup ? '<button class="btn btn-p" data-act="newjob">➕ Naya Kaam shuru karein</button>' : '') + (C.can('quotes.create') ? '<a class="btn btn-o" href="#/quote/new?party=' + p.id + '">' + C.ic('quote') + ' Quotation</a>' : '') + (C.isAdmin() ? '<button class="btn btn-g" data-act="gone" title="Sirf Admin">' + C.ic('trash') + ' Customer hatayein</button>' : '') + '</div></div>';
      h += '<div class="kpis">' + C.kpi('Quotation', qs.length, money(C.sum(qs, 'amount'))) + C.kpi('Kul bill', money(billed), inv.length + ' bill') + C.kpi('Mila', money(paid), pay.length + ' payment') + C.kpi('Baaki', money(bal), d.opening ? 'Opening ' + money(d.opening) + ' shamil' : '', bal > 0 ? 'warn' : '') + '</div>';
      var miss = C.detailsMissing(p); if (miss.length) h += '<div class="note o" style="margin-bottom:10px"><b>Details adhuri:</b> ' + esc(miss.join(', ')) + (d.store_order_id ? ' (online order se aaya)' : '') + ' — ' + (C.can('customers.edit') ? '<a href="#" data-act="edit" style="color:var(--leaf-d);font-weight:700">Conversation me bhar dein</a>' : 'Conversation me bharni hai') + '. Ek baar bharne par Site Visit, Quotation, Blueprint, Plant — har jagah apne aap aayengi.</div>';
      if (!isSup && Array.isArray(d.inquiries) && d.inquiries.length) h += '<div class="note o" style="margin-bottom:10px"><b>Dobara sampark (' + d.inquiries.length + ')</b> — is customer ne website / store / form se phir poocha:<br>' + d.inquiries.slice(-5).reverse().map(function (x) { return esc(C.fd(x.at)) + ' · ' + esc(x.source || '') + (x.note ? ' — ' + esc(String(x.note).trim()) : ''); }).join('<br>') + '<br><span class="xs">Naya lead nahi bana — isi customer ka kaam chalayein (Naya Kaam).</span></div>';
      var tabs = [['overview', 'Details'], ['jobs', 'Kaam / History (' + qs.length + ')'], ['bills', 'Bill (' + inv.length + ')'], ['payments', 'Payment (' + pay.length + ')'], ['ledger', 'Ledger'], ['tasks', 'Reminder (' + rem.filter(function (r) { return r.status === 'open'; }).length + ')'], ['docs', 'Documents (' + docs.length + ')'], ['notes', 'Notes (' + notes.length + ')']];
      if (plants.length) tabs.splice(1, 0, ['plants', 'Plant (' + plants.length + ')']);
      h += '<div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + esc(t[1]) + '</button>'; }).join('') + '</div><div id="tb"></div>';
      el.innerHTML = h;
      var tb = $('#tb', el);
      function docRow(x, kind) { var lk = kind === 'quote' ? '#/quote/' : '#/invoice/'; return '<a class="li" href="' + lk + x.id + '"><span class="av ' + (kind === 'quote' ? 'b' : 'o') + '">' + C.ic(kind === 'quote' ? 'quote' : 'bill') + '</span><span class="grow"><span class="t">' + esc(x.ref) + ' ' + C.billPill(x) + (x.data && x.data.superseded_by ? ' ' + C.pill('Band (dusri chuni gayi)', 'o') : '') + (x.data && x.data.locked ? C.ribbon((x.data.alt && x.data.alt.length ? 'Final: ' + (x.data.locked.label || '') : 'Final'), 'g') : '') + '</span><span class="m"><span>' + esc(C.fd(x.data.date || x.created_at)) + '</span><span>' + esc(x.owner_name || '') + '</span></span></span><span class="amt">' + money(x.amount) + (kind === 'invoice' && num(x.data.balance) > 0 ? '<small>Baaki ' + money(x.data.balance) + '</small>' : '') + '</span></a>'; }
      /* Round 33: every purchase / plant / service is its own "Kaam" (job) — own quotation, bill, flow. The customer record stays one. */
      function jobState(x) { var dd = x.data || {}; if (dd.closed) return ['Poora hua', 'g']; if (x.status === 'rejected') return ['Reject', 'r']; if (x.status === 'accepted' || x.status === 'converted') return ['Chal raha', 'o']; if (x.status === 'sent') return ['Bheji', 'b']; return ['Draft', '']; }
      function jobsHtml() {
        if (!qs.length) return '<div class="card">' + C.empty('quote', 'Abhi koi kaam nahi', 'Upar "Naya Kaam shuru karein" dabayein — customer ki details dobara nahi bharni padengi') + '</div>';
        var run = qs.filter(function (x) { return jobState(x)[0] === 'Chal raha'; }).length, fin = qs.filter(function (x) { return jobState(x)[0] === 'Poora hua'; }).length;
        var rows = qs.slice().sort(function (a, b) { return (b.id || 0) - (a.id || 0); }).map(function (x) {
          var dd = x.data || {}, stt = jobState(x), lines = (dd.lines || []).map(function (l) { return l.name || l.title || ''; }).filter(Boolean), kk = C.FLOW.kindOfCtype(dd.ctype) || kind;
          var q1 = '?cf=' + p.id + '&cq=' + x.id, inv1 = dd.invoice_id ? '<a class="btn btn-o btn-sm" href="#/invoice/' + dd.invoice_id + q1 + '">' + C.ic('bill') + ' Bill</a>' : '';
          return '<div class="li"><span class="av ' + (kk === 'project' ? 'b' : 'o') + '">' + C.ic(kk === 'project' ? 'plant' : 'box') + '</span><span class="grow"><span class="t">' + esc(x.ref || '') + ' ' + C.pill(dd.ctype || C.KINDS[kk], kk === 'project' ? 'v' : 'g') + ' ' + C.pill(stt[0], stt[1]) + '</span>' +
            '<span class="m"><span>' + esc(dd.qtitle || x.title || '') + '</span><span>' + esc(C.fd(dd.date || x.created_at)) + '</span><span>' + money(x.amount) + '</span></span>' +
            (lines.length ? '<span class="m"><span class="mute">' + esc(lines.slice(0, 3).join(' · ') + (lines.length > 3 ? ' +' + (lines.length - 3) + ' aur' : '')) + '</span></span>' : '') +
            '<span class="row wrap" style="gap:6px;margin-top:6px"><a class="btn btn-o btn-sm" href="#/quote/' + x.id + q1 + '">' + C.ic('quote') + ' Quotation</a>' + inv1 + '</span></span></div>';
        }).join('');
        return '<div class="note g" style="margin-bottom:10px">Kul <b>' + qs.length + '</b> kaam · <b>' + run + '</b> chal raha · <b>' + fin + '</b> poore. Har kaam ka apna quotation, bill aur flow hai — purana kaam kabhi nahi badalta.</div><div class="list">' + rows + '</div>';
      }
      function draw() {
        var t = '';
        if (tab === 'overview') {
          var f = function (l, v) { return v ? '<div><div class="xs mute">' + l + '</div><div class="b" style="white-space:pre-line">' + esc(v) + '</div></div>' : ''; };
          t = '<div class="grid g2"><div class="card"><div class="fg">' + f('Mobile', p.mobile) + f('Doosra mobile', d.mobile2) + f('Email', d.email) + f('Shahar', d.city) + f('Pincode', d.pincode) + f('Company', d.company) + f('Contact person', [d.contact_person, d.designation].filter(Boolean).join(' · ')) + f('GSTIN', d.gstin) + (isSup ? '' : f('Customer', C.KINDS[kind] + ' · ' + (C.SEGMENTS[d.segment] || C.SEGMENTS.b2c))) + f('Zaroorat', d.interest) + f('Prakar', (C.PARTY_TYPES.find(function (x) { return x[0] === (d.type || 'customer'); }) || [])[1]) + f('Source', d.source) + f('Bijli bill', d.bill ? '₹' + d.bill + '/mahina' : '') + f('Chahiye', d.kw ? d.kw + ' kW' : '') + f('Bana', C.fd(p.created_at)) + '</div>' + (d.address ? '<div style="margin-top:12px">' + f('Pata', d.address) + '</div>' : '') + (d.note ? '<div class="note" style="margin-top:12px">' + esc(d.note) + '</div>' : '') + '</div>' +
            '<div class="card"><div class="hd"><h3>Jaldi karein</h3></div><div class="stack">' + '<button class="btn btn-o" data-act="rem">' + C.ic('clock') + ' Reminder lagayein</button>' + (!isSup && (hasProject || kind === 'service') && C.canAny('leads.create', 'leads.view_all') ? '<a class="btn btn-o" href="#/sitevisit?party=' + p.id + '">' + C.ic('plant') + ' Site visit lagayein</a>' : '') + (!isSup && C.can('docs.view') ? '<a class="btn btn-o" href="#/docs">' + C.ic('send') + ' Demo / Files bhejein</a>' : '') + (!isSup && kind !== 'project' && C.can('customers.edit') ? '<button class="btn btn-o" data-act="kind">' + C.ic('plant') + ' Project customer banayein</button>' : '') + (hasProject ? '<button class="btn btn-o" data-act="maint">' + C.ic('settings') + ' Maintenance &amp; AMC plan dein</button>' : '') + (C.can('plants.create') && hasProject ? '<button class="btn btn-o" data-act="plant">' + C.ic('plant') + ' Plant jodein</button>' : '') + '<button class="btn btn-o" data-act="up">' + C.ic('upload') + ' Document / photo jodein</button>' + (C.can('customers.assign') ? '<button class="btn btn-o" data-act="move">' + C.ic('send') + ' Doosre user ko dein</button>' : '') + (C.can('customers.delete') ? '<button class="btn btn-r" data-act="del">' + C.ic('trash') + ' Customer hatayein</button>' : '') + '</div></div></div>';
        } else if (tab === 'jobs') t = jobsHtml();
        else if (tab === 'bills') t = inv.length ? '<div class="list">' + inv.map(function (x) { return docRow(x, 'invoice'); }).join('') + '</div>' : C.empty('bill', 'Koi bill nahi', 'Bill quotation se banta hai');
        else if (tab === 'payments') t = (C.can('payments.record') ? '<div class="bar"><span class="sp"></span><button class="btn btn-p btn-sm" data-act="pay">' + C.ic('plus') + ' Payment jodein</button></div>' : '') + (pay.length ? '<div class="list">' + pay.map(function (x) { return C.payRow(x); }).join('') + '</div>' : C.empty('rupee', 'Koi payment nahi'));
        else if (tab === 'ledger') { var rows = C.ledger(p, inv, pay); t = '<div class="bar"><span class="sp"></span>' + C.dlMenu([['wa', 'PDF WhatsApp par bhejein', 'data-act="lshare"'], ['printer', 'Print', 'data-act="lprint"']], { sm: true }) + '</div>' + (rows.length ? '<div class="tw"><table class="t"><thead><tr><th>Date</th><th>Detail</th><th>Ref</th><th class="r">Debit</th><th class="r">Credit</th><th class="r">Balance</th></tr></thead><tbody>' + rows.map(function (r) { return '<tr><td>' + C.fd(r.date) + '</td><td>' + (r.k === 'invoice' ? '<a class="b" style="color:var(--leaf-d)" href="#/invoice/' + r.id + '">' + esc(r.t) + '</a>' : esc(r.t)) + '</td><td>' + esc(r.ref || '') + '</td><td class="r">' + (r.dr ? money(r.dr) : '') + '</td><td class="r">' + (r.cr ? money(r.cr) : '') + '</td><td class="r b">' + money(r.bal) + '</td></tr>'; }).join('') + '</tbody></table></div>' : C.empty('bill', 'Abhi koi len-den nahi')); }
        else if (tab === 'tasks') t = '<div class="bar"><span class="sp"></span><button class="btn btn-p btn-sm" data-act="rem">' + C.ic('plus') + ' Naya kaam</button></div>' + (rem.length ? '<div class="list">' + rem.map(function (r) { var rt = C.RTYPE[r.data.type] || C.RTYPE.other, od = r.status === 'open' && r.due_at < C.today(); return '<div class="li' + (od ? ' over' : '') + '"><span class="av ' + (r.status === 'done' ? '' : 'b') + '">' + C.ic(r.status === 'done' ? 'check' : rt[1]) + '</span><span class="grow"><span class="t">' + esc(r.title) + (r.status === 'done' ? C.pill('Ho gaya') : '') + '</span><span class="m"><span>' + esc(rt[0]) + '</span><span>' + esc(C.fd(r.due_at)) + '</span><span>' + esc(r.assigned_name || '') + '</span>' + (r.data.repeat ? '<span>' + C.ic('refresh') + esc(r.data.repeat) + '</span>' : '') + '</span></span><span class="acts">' + (r.status === 'open' ? '<button class="btn btn-p btn-sm" data-act="rdone" data-id="' + r.id + '">' + C.ic('check') + '</button>' : '') + '<button class="btn btn-g btn-icon btn-sm" data-act="redit" data-id="' + r.id + '">' + C.ic('edit') + '</button></span></div>'; }).join('') + '</div>' : C.empty('today', 'Koi kaam nahi', 'AMC / service ki tareekh bhi yahin se lagayein (Repeat: Har 3 mahine)'));
        else if (tab === 'docs') t = '<div class="bar"><span class="sp"></span><button class="btn btn-p btn-sm" data-act="up">' + C.ic('upload') + ' Upload</button></div>' + (docs.length ? '<div class="list">' + docs.map(function (x) { return '<div class="li"><span class="av o">' + C.ic(C.mimeIcon(x.data.mime)) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + C.fsize(x.data.size) + '</span><span>' + esc(C.fd(x.created_at)) + '</span><span>' + esc(x.owner_name || '') + '</span></span></span><span class="acts"><button class="btn btn-o btn-sm" data-act="dopen" data-id="' + x.id + '" style="display:inline-flex">' + C.ic('eye') + '</button><button class="btn btn-wa btn-sm" data-act="dshare" data-id="' + x.id + '">' + C.ic('share') + '</button>' + (x.owner_id === C.me.id || C.can('docs.delete') ? '<button class="btn btn-g btn-icon btn-sm" data-act="ddel" data-id="' + x.id + '">' + C.ic('trash') + '</button>' : '') + '</span></div>'; }).join('') + '</div>' : C.empty('folder', 'Koi document nahi', 'Aadhaar, bijli bill, site photo, agreement — yahan rakhein'));
        else if (tab === 'notes') t = '<div class="card" style="margin-bottom:12px;padding:12px"><div class="row"><input class="inp" id="nt" placeholder="Note likhein ya neeche se chunein…"><button class="btn btn-p" data-act="note">' + C.ic('send') + '</button></div>' + C.tplChips('note', '#nt') + '</div>' + (notes.length ? '<div class="list">' + notes.map(function (n) { return '<div class="li"><span class="grow"><span style="white-space:pre-line">' + esc(n.data.text) + '</span><span class="m"><span>' + esc(n.owner_name || '') + '</span><span>' + esc(C.fdt(n.created_at)) + '</span></span></span>' + (n.owner_id === C.me.id ? '<button class="btn btn-g btn-icon btn-sm" data-act="ndel" data-id="' + n.id + '">' + C.ic('trash') + '</button>' : '') + '</div>'; }).join('') + '</div>' : C.empty('edit', 'Koi note nahi'));
        else if (tab === 'plants') t = '<div class="list">' + plants.map(function (x) { return C.plantRow ? C.plantRow(x) : ''; }).join('') + '</div>';
        tb.innerHTML = t;
      }
      draw();
      el.addEventListener('click', function (e) { var b = e.target.closest('[data-tab]'); if (b) { tab = b.getAttribute('data-tab'); $$('[data-tab]', el).forEach(function (x) { x.classList.toggle('on', x === b); }); C.setQuery({ tab: tab === 'overview' ? '' : tab }); draw(); } });
      C.bind(el, {
        gone: function () { C.custGone(p); },
        newjob: function () {
          var m = C.modal({ title: 'Naya Kaam — ' + p.title, size: 'sm', body: '<div class="note g">Customer ki details wahi rahengi — dobara kuch nahi bharna. Naya kaam alag quotation / bill / flow ke saath shuru hoga; purane kaam waise hi rahenge.</div>' +
            '<div class="stack" style="margin-top:10px"><label class="li click" style="cursor:pointer"><input type="radio" name="nj" value="Residential" checked style="margin-right:8px"><span class="grow"><b>Project (plant)</b><span class="m"><span>Solar plant — site visit, blueprint, installation, net meter…</span></span></span></label>' +
            '<div id="njsub" style="margin:0 0 6px 26px"><select class="inp" id="njt"><option value="Residential">Residential</option><option value="Commercial">Commercial</option><option value="Industrial">Industrial</option><option value="VFD">VFD</option></select></div>' +
            '<label class="li click" style="cursor:pointer"><input type="radio" name="nj" value="Items only" style="margin-right:8px"><span class="grow"><b>Product (sirf saaman)</b><span class="m"><span>Panel, inverter, battery… — chhota flow</span></span></span></label>' +
            '<label class="li click" style="cursor:pointer"><input type="radio" name="nj" value="Service" style="margin-right:8px"><span class="grow"><b>Service</b><span class="m"><span>Cleaning, AMC, repair, shifting, audit</span></span></span></label>' +
            '<label class="li click" style="cursor:pointer"><input type="radio" name="nj" value="AMC only" style="margin-right:8px"><span class="grow"><b>Sirf AMC / Maintenance</b><span class="m"><span>Lead, Customer, Conversation pehle se bhare — seedha AMC plan</span></span></span></label>' +
            '<label class="li click" style="cursor:pointer"><input type="radio" name="nj" value="Site visit only" style="margin-right:8px"><span class="grow"><b>Sirf Site Visit</b><span class="m"><span>Lead, Customer, Conversation pehle se bhare — seedha Site Visit</span></span></span></label></div>',
            foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Aage badhein</button>' });
          $('[data-ok]', m.el).onclick = function () { var v = ($('input[name=nj]:checked', m.el) || {}).value || 'Residential'; if (v === 'Residential') v = $('#njt', m.el).value; m.close();
            C.startJob(p.id, v).catch(function () {}); };
        },
        edit: function () { C.partyForm(p).then(function (r) { if (r) C.render(); }); },
        kind: async function () { try { await C.save('party', p.id, Object.assign({}, p.data, { cust_kind: 'project' }), {}, 'Customer prakar badal gaya ✔'); C.render(); } catch (e) {} },
        pay: function () { C.payForm && C.payForm({ party: p }).then(function (r) { if (r) C.render(); }); },
        maint: function () { C.maintAssign(p).then(function () { C.render(); }); },
        rem: function () { C.reminderForm(null, { party_id: p.id, party_name: p.title, mobile: p.mobile }).then(function (r) { if (r) C.render(); }); },
        plant: function () { C.plantForm(null, { party_id: p.id }).then(function (r) { if (r) C.render(); }); },
        up: function () { var i = document.createElement('input'); i.type = 'file'; i.multiple = true; i.accept = 'image/*,.pdf,.doc,.docx,.xls,.xlsx'; i.onchange = async function () { if (await C.uploadFiles(i.files, { party_id: p.id, attach_kind: 'party', attach_id: p.id })) { C.setQuery({ tab: 'docs' }); C.render(); } }; i.click(); },
        dopen: function (id) { C.openFile(id); }, dshare: function (id) { C.openFile(id, 'share'); },
        ddel: async function (id) { var x = docs.find(function (z) { return String(z.id) === id; }); if (await C.delWithReason(x, x.title)) C.render(); },
        move: async function () { var m = C.modal({ title: 'Customer kisko dein?', size: 'sm', body: '<select class="inp" id="mto">' + C.userOpts(p.owner_id, '— Company / Admin —') + '</select>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Dein</button>' }); $('[data-ok]', m.el).onclick = async function () { try { await C.run('crm_assign', { kind: 'party', ids: [p.id], user_id: $('#mto', m.el).value || null }, 'Customer de diya ✔'); m.close(); C.render(); } catch (e) {} }; },
        del: async function () { if (await C.delWithReason(p, p.title)) C.go(p.data.stage === 'inquiry' ? '#/inquiries' : '#/customers'); },
        rdone: async function (id) { await C.reminderDone({ id: id }); C.render(); },
        redit: async function (id) { var r = rem.find(function (x) { return String(x.id) === id; }); if (await C.reminderForm(r)) C.render(); },
        note: async function () { var t = $('#nt', el).value.trim(); if (!t) return; try { await C.save('note', null, { title: 'Note — ' + p.title, text: t }, { party_id: p.id }, 'Note jud gaya ✔'); C.render(); } catch (e) {} },
        ndel: async function (id) { var n = notes.find(function (x) { return String(x.id) === id; }); if (await C.delWithReason(n, 'Ye note')) C.render(); },
        lprint: function () { C.printHtml(C.ledgerHtml(p, C.ledger(p, inv, pay)), 'Ledger ' + p.title); },
        lshare: function () { var rows = C.ledger(p, inv, pay), bal = rows.length ? rows[rows.length - 1].bal : 0; C.sharePdf(C.ledgerHtml(p, rows), 'Ledger-' + p.title.replace(/\W+/g, '-') + '.pdf', 'Namaste ' + p.title + ' ji, aapka ledger statement. Baaki: ' + money(bal), p.mobile,
          { kind: 'ledger', title: 'Ledger Statement — ' + p.title, subtitle: 'Closing balance (baaki)', amount: bal, customer: p.title, date: C.today(), ref: 'rec:' + p.id, details: [['Party', p.title], ['Statement date', C.fd(C.today())], ['Entries', String(rows.length)], ['Closing balance', money(bal)]] }); }
      });
    }
  });
})();
