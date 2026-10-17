/* Customers — list + detail (quotations, bills, payments, ledger, reminders, documents, notes) */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;

  C.mod('customers', {
    title: 'Customers', nav: 'customers',
    allowed: function () { return C.canAny('customers.create', 'customers.view_all') || C.isPartner(); },
    render: async function (el, params, q) {
      var viewAll = C.can('customers.view_all'), uid = q.user || '', type = q.type || '';
      var all = await C.list('party', { limit: 3000, user_id: uid || null });
      var list = all.filter(function (p) { return !type || (p.data.type || 'customer') === type || p.data.type === 'both'; });
      var h = '<div class="ph"><div><h1>Customers</h1><p>' + all.length + ' customers' + (viewAll ? '' : ' — sirf aapke') + '. Ek mobile = ek customer (lock).</p></div><div class="row">' +
        (C.can('customers.export') ? C.reportBtns('Customers', function () { return { head: ['Naam', 'Mobile', 'Email', 'Shahar', 'Pata', 'GSTIN', 'Company', 'Prakar', 'Source', 'Kiske paas', 'Bana'], rows: list.map(function (p) { return [p.title, p.mobile || '', p.data.email || '', p.data.city || '', p.data.address || '', p.data.gstin || '', p.data.company || '', p.data.type || 'customer', p.data.source || '', p.owner_name || '', C.fd(p.created_at)]; }) }; }) : '') +
        (C.can('customers.create') ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Naya customer</button>' : '') + '</div></div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Naam / mobile / shahar khojein">' + C.chips([['', 'Sab'], ['customer', 'Customers'], ['supplier', 'Suppliers']], type, 'type') + (viewAll ? C.userFilter(uid, 'Sabhi users') : '') + '</div>';
      h += list.length ? '<div class="list" id="cl">' + list.map(function (p) {
        return '<div class="li click" data-href="#/customer/' + p.id + '"><span class="av">' + esc(C.initials(p.title)) + '</span><span class="grow"><span class="t">' + esc(p.title) + (p.data.type === 'supplier' ? C.pill('Supplier', 'b') : '') + '</span><span class="m"><span>' + C.ic('phone') + esc(p.mobile || '') + '</span>' + (p.data.city ? '<span>' + esc(p.data.city) + '</span>' : '') + (p.data.company ? '<span>' + esc(p.data.company) + '</span>' : '') + (viewAll ? '<span>' + C.ic('user') + esc(p.owner_name || '') + '</span>' : '') + '</span></span><span class="acts">' + C.callBtns(p.mobile) + '</span>' + C.ic('right') + '</div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('users', 'Koi customer nahi', C.can('customers.create') ? '"Naya customer" dabayein' : '') + '</div>';
      el.innerHTML = h;
      var cl = $('#cl', el); if (cl) C.filterList($('[data-q]', el), cl);
      el.addEventListener('click', function (e) { var c = e.target.closest('[data-type]'); if (c) C.go('#/customers' + C.qs({ type: c.getAttribute('data-type'), user: uid })); });
      var us = $('[data-user]', el); if (us) us.onchange = function () { C.go('#/customers' + C.qs({ type: type, user: this.value })); };
      C.bind(el, { add: function () { C.partyForm().then(function (r) { if (r) C.go('#/customer/' + r.id); }); } });
    }
  });

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
      var id = params[0], p = await C.get(id), tab = q.tab || 'overview';
      var res = await Promise.all([
        C.list('quote', { party_id: id }).catch(function () { return []; }), C.list('invoice', { party_id: id }).catch(function () { return []; }),
        C.list('payment', { party_id: id }).catch(function () { return []; }), C.list('reminder', { party_id: id }).catch(function () { return []; }),
        C.list('doc', { party_id: id }).catch(function () { return []; }), C.list('note', { party_id: id }).catch(function () { return []; }),
        C.list('plant', { party_id: id }).catch(function () { return []; })
      ]);
      var qs = res[0], inv = res[1], pay = res[2], rem = res[3], docs = res[4], notes = res[5], plants = res[6], d = p.data || {};
      var billed = C.sum(inv, 'amount'), paid = C.sum(pay, 'amount'), bal = num(d.opening) + billed - paid;
      var h = '<div class="crumb"><a href="#/customers">Customers</a>' + C.ic('right') + '<span>' + esc(p.title) + '</span></div>';
      h += '<div class="ph"><div><h1>' + esc(p.title) + '</h1><p>' + esc([p.mobile, d.city, d.company].filter(Boolean).join(' · ')) + (p.owner_name ? ' · ' + C.ic('user') + ' ' + esc(p.owner_name) : '') + '</p></div><div class="row">' + C.callBtns(p.mobile, 'Namaste ' + p.title + ' ji, ') +
        (C.can('customers.edit') ? '<button class="btn btn-o" data-act="edit">' + C.ic('edit') + ' Badlein</button>' : '') + (C.can('quotes.create') ? '<a class="btn btn-p" href="#/quote/new?party=' + p.id + '">' + C.ic('quote') + ' Quotation</a>' : '') + '</div></div>';
      h += '<div class="kpis">' + C.kpi('Quotation', qs.length, money(C.sum(qs, 'amount'))) + C.kpi('Kul bill', money(billed), inv.length + ' bill') + C.kpi('Mila', money(paid), pay.length + ' payment') + C.kpi('Baaki', money(bal), d.opening ? 'Opening ' + money(d.opening) + ' shamil' : '', bal > 0 ? 'warn' : '') + '</div>';
      if ((d.type || 'customer') !== 'supplier') h += '<div id="wfc"></div>';
      var tabs = [['overview', 'Details'], ['quotes', 'Quotation (' + qs.length + ')'], ['bills', 'Bill (' + inv.length + ')'], ['payments', 'Payment (' + pay.length + ')'], ['ledger', 'Ledger'], ['tasks', 'Kaam (' + rem.filter(function (r) { return r.status === 'open'; }).length + ')'], ['docs', 'Documents (' + docs.length + ')'], ['notes', 'Notes (' + notes.length + ')']];
      if (plants.length) tabs.splice(1, 0, ['plants', 'Plant (' + plants.length + ')']);
      h += '<div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + esc(t[1]) + '</button>'; }).join('') + '</div><div id="tb"></div>';
      el.innerHTML = h;
      if ($('#wfc', el) && C.wfCard) C.wfCard($('#wfc', el), { party_id: p.id, title: 'Customer ka process', onChange: function () { C.render(); } });
      var tb = $('#tb', el);
      function docRow(x, kind) { var lk = kind === 'quote' ? '#/quote/' : '#/invoice/'; return '<a class="li" href="' + lk + x.id + '"><span class="av ' + (kind === 'quote' ? 'b' : 'o') + '">' + C.ic(kind === 'quote' ? 'quote' : 'bill') + '</span><span class="grow"><span class="t">' + esc(x.ref) + ' ' + C.billPill(x) + '</span><span class="m"><span>' + esc(C.fd(x.data.date || x.created_at)) + '</span><span>' + esc(x.owner_name || '') + '</span></span></span><span class="amt">' + money(x.amount) + (kind === 'invoice' && num(x.data.balance) > 0 ? '<small>Baaki ' + money(x.data.balance) + '</small>' : '') + '</span></a>'; }
      function draw() {
        var t = '';
        if (tab === 'overview') {
          var f = function (l, v) { return v ? '<div><div class="xs mute">' + l + '</div><div class="b" style="white-space:pre-line">' + esc(v) + '</div></div>' : ''; };
          t = '<div class="grid g2"><div class="card"><div class="fg">' + f('Mobile', p.mobile) + f('Doosra mobile', d.mobile2) + f('Email', d.email) + f('Shahar', d.city) + f('Pincode', d.pincode) + f('Company', d.company) + f('GSTIN', d.gstin) + f('Prakar', (C.PARTY_TYPES.find(function (x) { return x[0] === (d.type || 'customer'); }) || [])[1]) + f('Source', d.source) + f('Bijli bill', d.bill ? '₹' + d.bill + '/mahina' : '') + f('Chahiye', d.kw ? d.kw + ' kW' : '') + f('Bana', C.fd(p.created_at)) + '</div>' + (d.address ? '<div style="margin-top:12px">' + f('Pata', d.address) + '</div>' : '') + (d.note ? '<div class="note" style="margin-top:12px">' + esc(d.note) + '</div>' : '') + '</div>' +
            '<div class="card"><div class="hd"><h3>Jaldi karein</h3></div><div class="stack">' + (C.can('quotes.create') ? '<a class="btn btn-o" href="#/quote/new?party=' + p.id + '">' + C.ic('quote') + ' Nayi quotation</a>' : '') + (C.can('payments.record') ? '<button class="btn btn-o" data-act="pay">' + C.ic('rupee') + ' Payment jodein</button>' : '') + '<button class="btn btn-o" data-act="rem">' + C.ic('clock') + ' Reminder lagayein</button><button class="btn btn-o" data-act="maint">' + C.ic('settings') + ' Maintenance &amp; Audit plan dein</button>' + (C.can('plants.create') ? '<button class="btn btn-o" data-act="plant">' + C.ic('plant') + ' Plant jodein</button>' : '') + '<button class="btn btn-o" data-act="up">' + C.ic('upload') + ' Document / photo jodein</button>' + (C.can('customers.assign') ? '<button class="btn btn-o" data-act="move">' + C.ic('send') + ' Doosre user ko dein</button>' : '') + (C.can('customers.delete') ? '<button class="btn btn-r" data-act="del">' + C.ic('trash') + ' Customer hatayein</button>' : '') + '</div></div></div>';
        } else if (tab === 'quotes') t = qs.length ? '<div class="list">' + qs.map(function (x) { return docRow(x, 'quote'); }).join('') + '</div>' : C.empty('quote', 'Koi quotation nahi');
        else if (tab === 'bills') t = inv.length ? '<div class="list">' + inv.map(function (x) { return docRow(x, 'invoice'); }).join('') + '</div>' : C.empty('bill', 'Koi bill nahi', 'Bill quotation se banta hai');
        else if (tab === 'payments') t = (C.can('payments.record') ? '<div class="bar"><span class="sp"></span><button class="btn btn-p btn-sm" data-act="pay">' + C.ic('plus') + ' Payment jodein</button></div>' : '') + (pay.length ? '<div class="list">' + pay.map(function (x) { return C.payRow(x); }).join('') + '</div>' : C.empty('rupee', 'Koi payment nahi'));
        else if (tab === 'ledger') { var rows = C.ledger(p, inv, pay); t = '<div class="bar"><span class="sp"></span><button class="btn btn-o btn-sm" data-act="lprint">' + C.ic('printer') + ' Print</button><button class="btn btn-wa btn-sm" data-act="lshare">' + C.ic('wa') + ' PDF bhejein</button></div>' + (rows.length ? '<div class="tw"><table class="t"><thead><tr><th>Date</th><th>Detail</th><th>Ref</th><th class="r">Debit</th><th class="r">Credit</th><th class="r">Balance</th></tr></thead><tbody>' + rows.map(function (r) { return '<tr><td>' + C.fd(r.date) + '</td><td>' + (r.k === 'invoice' ? '<a class="b" style="color:var(--leaf-d)" href="#/invoice/' + r.id + '">' + esc(r.t) + '</a>' : esc(r.t)) + '</td><td>' + esc(r.ref || '') + '</td><td class="r">' + (r.dr ? money(r.dr) : '') + '</td><td class="r">' + (r.cr ? money(r.cr) : '') + '</td><td class="r b">' + money(r.bal) + '</td></tr>'; }).join('') + '</tbody></table></div>' : C.empty('bill', 'Abhi koi len-den nahi')); }
        else if (tab === 'tasks') t = '<div class="bar"><span class="sp"></span><button class="btn btn-p btn-sm" data-act="rem">' + C.ic('plus') + ' Naya kaam</button></div>' + (rem.length ? '<div class="list">' + rem.map(function (r) { var rt = C.RTYPE[r.data.type] || C.RTYPE.other, od = r.status === 'open' && r.due_at < C.today(); return '<div class="li' + (od ? ' over' : '') + '"><span class="av ' + (r.status === 'done' ? '' : 'b') + '">' + C.ic(r.status === 'done' ? 'check' : rt[1]) + '</span><span class="grow"><span class="t">' + esc(r.title) + (r.status === 'done' ? C.pill('Ho gaya') : '') + '</span><span class="m"><span>' + esc(rt[0]) + '</span><span>' + esc(C.fd(r.due_at)) + '</span><span>' + esc(r.assigned_name || '') + '</span>' + (r.data.repeat ? '<span>' + C.ic('refresh') + esc(r.data.repeat) + '</span>' : '') + '</span></span><span class="acts">' + (r.status === 'open' ? '<button class="btn btn-p btn-sm" data-act="rdone" data-id="' + r.id + '">' + C.ic('check') + '</button>' : '') + '<button class="btn btn-g btn-icon btn-sm" data-act="redit" data-id="' + r.id + '">' + C.ic('edit') + '</button></span></div>'; }).join('') + '</div>' : C.empty('today', 'Koi kaam nahi', 'AMC / service ki tareekh bhi yahin se lagayein (Repeat: Har 3 mahine)'));
        else if (tab === 'docs') t = '<div class="bar"><span class="sp"></span><button class="btn btn-p btn-sm" data-act="up">' + C.ic('upload') + ' Upload</button></div>' + (docs.length ? '<div class="list">' + docs.map(function (x) { return '<div class="li"><span class="av o">' + C.ic(C.mimeIcon(x.data.mime)) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + C.fsize(x.data.size) + '</span><span>' + esc(C.fd(x.created_at)) + '</span><span>' + esc(x.owner_name || '') + '</span></span></span><span class="acts"><button class="btn btn-o btn-sm" data-act="dopen" data-id="' + x.id + '" style="display:inline-flex">' + C.ic('eye') + '</button><button class="btn btn-wa btn-sm" data-act="dshare" data-id="' + x.id + '">' + C.ic('share') + '</button>' + (x.owner_id === C.me.id || C.can('docs.delete') ? '<button class="btn btn-g btn-icon btn-sm" data-act="ddel" data-id="' + x.id + '">' + C.ic('trash') + '</button>' : '') + '</span></div>'; }).join('') + '</div>' : C.empty('folder', 'Koi document nahi', 'Aadhaar, bijli bill, site photo, agreement — yahan rakhein'));
        else if (tab === 'notes') t = '<div class="card" style="margin-bottom:12px;padding:12px"><div class="row"><input class="inp" id="nt" placeholder="Note likhein ya neeche se chunein…"><button class="btn btn-p" data-act="note">' + C.ic('send') + '</button></div>' + C.tplChips('note', '#nt') + '</div>' + (notes.length ? '<div class="list">' + notes.map(function (n) { return '<div class="li"><span class="grow"><span style="white-space:pre-line">' + esc(n.data.text) + '</span><span class="m"><span>' + esc(n.owner_name || '') + '</span><span>' + esc(C.fdt(n.created_at)) + '</span></span></span>' + (n.owner_id === C.me.id ? '<button class="btn btn-g btn-icon btn-sm" data-act="ndel" data-id="' + n.id + '">' + C.ic('trash') + '</button>' : '') + '</div>'; }).join('') + '</div>' : C.empty('edit', 'Koi note nahi'));
        else if (tab === 'plants') t = '<div class="list">' + plants.map(function (x) { return C.plantRow ? C.plantRow(x) : ''; }).join('') + '</div>';
        tb.innerHTML = t;
      }
      draw();
      el.addEventListener('click', function (e) { var b = e.target.closest('[data-tab]'); if (b) { tab = b.getAttribute('data-tab'); $$('[data-tab]', el).forEach(function (x) { x.classList.toggle('on', x === b); }); C.setQuery({ tab: tab === 'overview' ? '' : tab }); draw(); } });
      C.bind(el, {
        edit: function () { C.partyForm(p).then(function (r) { if (r) C.render(); }); },
        pay: function () { C.payForm && C.payForm({ party: p }).then(function (r) { if (r) C.render(); }); },
        maint: function () { C.maintAssign(p).then(function () { C.render(); }); },
        rem: function () { C.reminderForm(null, { party_id: p.id, party_name: p.title, mobile: p.mobile }).then(function (r) { if (r) C.render(); }); },
        plant: function () { C.plantForm(null, { party_id: p.id, name: p.title, mobile: p.mobile, address: p.data.address, city: p.data.city }).then(function (r) { if (r) C.render(); }); },
        up: function () { var i = document.createElement('input'); i.type = 'file'; i.multiple = true; i.accept = 'image/*,.pdf,.doc,.docx,.xls,.xlsx'; i.onchange = async function () { if (await C.uploadFiles(i.files, { party_id: p.id, attach_kind: 'party', attach_id: p.id })) { C.setQuery({ tab: 'docs' }); C.render(); } }; i.click(); },
        dopen: function (id) { C.openFile(id); }, dshare: function (id) { C.openFile(id, 'share'); },
        ddel: async function (id) { var x = docs.find(function (z) { return String(z.id) === id; }); if (await C.delWithReason(x, x.title)) C.render(); },
        move: async function () { var m = C.modal({ title: 'Customer kisko dein?', size: 'sm', body: '<select class="inp" id="mto">' + C.userOpts(p.owner_id, '— Company / Admin —') + '</select>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Dein</button>' }); $('[data-ok]', m.el).onclick = async function () { try { await C.run('crm_assign', { kind: 'party', ids: [p.id], user_id: $('#mto', m.el).value || null }, 'Customer de diya ✔'); m.close(); C.render(); } catch (e) {} }; },
        del: async function () { if (await C.delWithReason(p, p.title)) C.go('#/customers'); },
        rdone: async function (id) { await C.reminderDone({ id: id }); C.render(); },
        redit: async function (id) { var r = rem.find(function (x) { return String(x.id) === id; }); if (await C.reminderForm(r)) C.render(); },
        note: async function () { var t = $('#nt', el).value.trim(); if (!t) return; try { await C.save('note', null, { title: 'Note — ' + p.title, text: t }, { party_id: p.id }, 'Note jud gaya ✔'); C.render(); } catch (e) {} },
        ndel: async function (id) { var n = notes.find(function (x) { return String(x.id) === id; }); if (await C.delWithReason(n, 'Ye note')) C.render(); },
        lprint: function () { C.printHtml(C.ledgerHtml(p, C.ledger(p, inv, pay)), 'Ledger ' + p.title); },
        lshare: function () { var rows = C.ledger(p, inv, pay); C.sharePdf(C.ledgerHtml(p, rows), 'Ledger-' + p.title.replace(/\W+/g, '-') + '.pdf', 'Namaste ' + p.title + ' ji, aapka ledger statement. Baaki: ' + money(rows.length ? rows[rows.length - 1].bal : 0), p.mobile); }
      });
    }
  });
})();
