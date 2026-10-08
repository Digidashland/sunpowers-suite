/* Home dashboard — role based */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, esc = C.esc, money = C.money, num = C.num;

  C.mod('home', {
    title: 'Home',
    render: async function (el) {
      var me = C.me, partner = C.isPartner(), res = await Promise.all([C.call('crm_dashboard', {}), C.call('crm_today_list', {}).catch(function () { return { items: [] }; })]);
      var d = res[0], t = res[1].items || [], hr = new Date().getHours(), greet = hr < 12 ? 'Suprabhat' : hr < 17 ? 'Namaste' : 'Shubh sandhya';
      C.updateTodayCount(t.length);
      var over = t.filter(function (x) { return x.overdue; }).length;
      var h = '<div class="hero-card"><h2>' + greet + ', ' + esc(me.name.split(' ')[0]) + ' 👋</h2><p>' + (t.length ? 'Aaj ' + t.length + ' kaam hain' + (over ? ' — <b style="color:var(--sun)">' + over + ' overdue</b>' : '') : 'Aaj ka koi kaam baaki nahi — badhiya!') + '</p><div class="row wrap">' +
        '<a class="btn btn-s" href="#/today">' + C.ic('today') + ' Aaj ke kaam</a>' +
        (C.storeUrl() ? '<a class="btn btn-o" href="' + esc(partner ? C.refLink() : C.storeUrl()) + '" target="_blank" rel="noopener">' + C.ic('store') + ' Visit Store</a>' : '') +
        (C.siteUrl() ? '<a class="btn btn-o" href="' + esc(C.siteUrl()) + '" target="_blank" rel="noopener">' + C.ic('globe') + ' Visit Website</a>' : '') +
        (partner && me.ref_code ? '<button class="btn btn-o" data-act="ref">' + C.ic('share') + ' Mera store link</button>' : '') + '</div></div>';

      var k = [];
      if (partner) {
        k.push(C.kpi('Kul plants', d.plants, num(d.plants_kw) + ' kW lage' + (d.plants_pending ? ' · ' + d.plants_pending + ' verify baaki' : ''), 'gold', '#/plants', 'plant'));
        k.push(C.kpi('Commission baaki', money(d.earn_due), 'Mil chuka: ' + money(d.earn_paid), '', '#/commission', 'rupee'));
        k.push(C.kpi('Mere customers', d.customers, '', '', '#/customers', 'users'));
        k.push(C.kpi('Is mahine quotation', d.quotes_count, money(d.quotes_month), '', '#/quotes', 'quote'));
        k.push(C.kpi('Khuli leads', d.leads_open, d.leads_new + ' nayi', '', '#/leads', 'lead'));
      } else {
        if (C.canAny('invoices.view_all', 'invoices.create')) { k.push(C.kpi('Is mahine ki sale', money(d.sales_month), 'Collection: ' + money(d.collected_month), 'gold', '#/billing', 'bill')); k.push(C.kpi('Lena baaki (Receivable)', money(d.receivable), '', num(d.receivable) > 0 ? 'warn' : '', '#/billing?tab=due', 'rupee')); }
        if (C.canAny('quotes.view_all', 'quotes.create')) k.push(C.kpi('Is mahine quotation', d.quotes_count, money(d.quotes_month), '', '#/quotes', 'quote'));
        if (C.canAny('leads.view_all', 'leads.create')) k.push(C.kpi('Khuli leads', d.leads_open, d.leads_new + ' nayi', '', '#/leads', 'lead'));
        k.push(C.kpi('Customers', d.customers, '', '', '#/customers', 'users'));
        if (C.canAny('plants.view_all', 'plants.create')) k.push(C.kpi('Plants lage', d.plants, num(d.plants_kw) + ' kW' + (d.plants_pending ? ' · ' + d.plants_pending + ' verify baaki' : ''), d.plants_pending ? 'warn' : '', '#/plants' + (d.plants_pending ? '?status=pending' : ''), 'plant'));
        if (d.orders_new != null) k.push(C.kpi('Naye store order', d.orders_new, d.enquiries_new + ' nayi enquiry', d.orders_new || d.enquiries_new ? 'warn' : '', '#/orders', 'cart'));
        if (d.users_pending) k.push(C.kpi('ID verify karni hai', d.users_pending, 'Dealer / Influencer', 'warn', '#/team?tab=pending', 'user'));
        if (d.store_pending) k.push(C.kpi('Store review baaki', d.store_pending, 'Online Store Admin me', '', '#/items?store=pending', 'store'));
        if (C.canAny('earnings.view_all', 'earnings.manage')) k.push(C.kpi('Commission dena baaki', money(d.earn_due), 'Diya: ' + money(d.earn_paid), '', '#/commission', 'rupee'));
      }
      h += '<div class="kpis">' + k.join('') + '</div>';
      var tgt = num(d.target);
      if (tgt > 0) { var done = partner ? num(d.quotes_month) : num(d.sales_month), pc = Math.min(100, Math.round(done * 100 / tgt)); h += '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>Is mahine ka target</h3><span class="b">' + money(done) + ' / ' + money(tgt) + '</span></div><div style="height:10px;border-radius:6px;background:var(--mint);overflow:hidden"><div style="height:100%;width:' + pc + '%;background:linear-gradient(90deg,var(--leaf),var(--sun))"></div></div><p class="xs mute" style="margin-top:6px">' + pc + '% poora</p></div>'; }

      var qa = [];
      if (C.can('leads.create')) qa.push('<button class="btn btn-o" data-act="lead">' + C.ic('lead') + ' Nayi lead</button>');
      if (C.can('customers.create')) qa.push('<button class="btn btn-o" data-act="party">' + C.ic('users') + ' Naya customer</button>');
      if (C.can('quotes.create')) qa.push('<a class="btn btn-o" href="#/quote/new">' + C.ic('quote') + ' Nayi quotation</a>');
      if (C.can('plants.create')) qa.push('<button class="btn btn-o" data-act="plant">' + C.ic('plant') + ' Plant jodein</button>');
      qa.push('<button class="btn btn-o" data-act="rem">' + C.ic('clock') + ' Reminder</button>');
      h += '<div class="card" style="margin-bottom:16px"><div class="hd"><h3>Jaldi karein</h3></div><div class="row wrap">' + qa.join('') + '</div></div>';

      h += '<div class="grid g2"><div class="card"><div class="hd"><h3>Aaj ke kaam</h3><a class="btn btn-g btn-sm" href="#/today">Sab dekhein ' + C.ic('right') + '</a></div>' +
        (t.length ? '<div class="list" style="border:0">' + t.slice(0, 6).map(function (x) { var rt = C.RTYPE[x.kind] || C.RTYPE.other; return '<a class="li' + (x.overdue ? ' over' : '') + '" href="#/today"><span class="av' + (x.overdue ? ' r' : '') + '">' + C.ic(x.src === 'invoice' ? 'rupee' : x.src === 'quote' ? 'quote' : rt[1]) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(x.src === 'invoice' ? 'Payment lena' : x.src === 'quote' ? 'Quotation bhejna' : rt[0]) + '</span><span>' + esc(C.fd(x.due_at)) + '</span></span></span>' + (num(x.amount) ? '<span class="amt">' + money(x.amount) + '</span>' : '') + '</a>'; }).join('') + '</div>' : C.empty('check', 'Sab kaam ho gaye', 'Naya kaam jodne ke liye "Reminder" dabayein')) + '</div>';
      h += '<div class="card"><div class="hd"><h3>Notice board</h3>' + (C.can('settings.manage') ? '<a class="btn btn-g btn-sm" href="#/settings?tab=notices">' + C.ic('plus') + ' Notice</a>' : '') + '</div>' +
        ((d.notices || []).length ? '<div class="stack">' + d.notices.map(function (n) { return '<div class="note g"><b>' + esc(n.title) + '</b>' + (n.body ? '<div class="sm" style="margin-top:3px;white-space:pre-line">' + esc(n.body) + '</div>' : '') + '<div class="xs mute" style="margin-top:4px">' + esc(C.ago(n.at)) + '</div></div>'; }).join('') + '</div>' : C.empty('megaphone', 'Abhi koi notice nahi')) + '</div></div>';
      el.innerHTML = h;
      C.bind(el, {
        ref: function () { C.copy(C.refLink(), 'Aapka store link copy ho gaya — WhatsApp par bhejein'); },
        lead: function () { C.leadForm && C.leadForm().then(function (r) { if (r) C.go('#/leads?open=' + r.id); }); },
        party: function () { C.partyForm().then(function (r) { if (r) C.go('#/customer/' + r.id); }); },
        plant: function () { C.plantForm && C.plantForm().then(function (r) { if (r) C.go('#/plants'); }); },
        rem: function () { C.reminderForm().then(function (r) { if (r) C.render(); }); }
      });
    }
  });
})();
