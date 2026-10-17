/* Plants (installations) + Commission / incentive */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, esc = C.esc, money = C.money, num = C.num;
  var PST = { pending: ['Verify baaki', 'o'], verified: ['Verified ✔', ''], rejected: ['Reject', 'r'] };

  C.plantRow = function (x) {
    var d = x.data || {}, s = PST[x.status] || [x.status, 'g'];
    return '<div class="li click" data-act="popen" data-id="' + x.id + '"><span class="av ' + (x.status === 'verified' ? '' : x.status === 'rejected' ? 'r' : 'o') + '">' + C.ic('plant') + '</span><span class="grow"><span class="t">' + esc(x.title) + ' ' + C.pill(s[0], s[1]) + '</span><span class="m"><span class="b">' + esc(d.kw || 0) + ' kW</span><span>' + esc(x.ref || '') + '</span>' + (d.city ? '<span>' + esc(d.city) + '</span>' : '') + (x.due_at ? '<span>' + C.ic('clock') + esc(C.fd(x.due_at)) + '</span>' : '') + '<span>' + C.ic('user') + esc(x.owner_name || '') + (d.ref ? ' · ' + esc(d.ref) : '') + '</span></span></span>' + (num(x.amount) && C.canAny('plants.view_all', 'plants.verify') ? '<span class="amt">' + money(x.amount) + '</span>' : '') + '</div>';
  };

  C.plantForm = function (rec, pre) {
    rec = rec || { data: {} }; var d = Object.assign({}, pre || {}, rec.data || {}), isNew = !rec.id, ver = C.can('plants.verify');
    return new Promise(function (res) {
      var body = '<form id="plf" class="fg">' + C.f('Customer ka naam *', C.inp('name', d.name || (isNew ? '' : rec.title))) + C.f('Mobile *', C.inp('mobile', d.mobile || rec.mobile, 'inputmode="tel"')) +
        C.f('Plant size (kW) *', C.inp('kw', d.kw, 'inputmode="decimal"')) + C.f('Prakar', C.sel('ptype', ['On-grid', 'Off-grid', 'Hybrid', 'Water pump', 'Street light', 'Other'], d.ptype || 'On-grid')) +
        C.f('Lagne ki tareekh', C.inp('install', d.install || C.today(), 'type="date"')) + C.f('Deal value (₹)', C.inp('deal_value', d.deal_value, 'inputmode="decimal"')) +
        C.f('Panel (brand / watt)', C.inp('panel', d.panel)) + C.f('Inverter', C.inp('inverter', d.inverter)) +
        C.f('Shahar / Gaon', C.inp('city', d.city)) + C.f('Discom / Consumer no.', C.inp('consumer_no', d.consumer_no)) +
        C.f('Subsidy status', C.sel('subsidy', ['Nahi', 'Apply kiya', 'Mil gayi', 'Lagu nahi'], d.subsidy || 'Nahi')) + C.f('Referral code <span class="o">(Dealer / Influencer)</span>', C.inp('ref', d.ref || (isNew && C.me.ref_code ? C.me.ref_code : ''), 'style="text-transform:uppercase"' + (C.isPartner() ? ' readonly' : ''))) +
        C.f('Pata', C.ta('address', d.address, 'rows="2"'), 'full') + C.f('Note', C.ta('note', d.note, 'rows="2"'), 'full') +
        (ver ? C.f('Status', C.sel('status', [['pending', 'Verify baaki'], ['verified', 'Verified'], ['rejected', 'Reject']], rec.status || 'verified'), 'full') : '<div class="note full">Plant Admin ke verify karne ke baad hi commission banega.</div>') + '</form>';
      var m = C.modal({ title: isNew ? 'Plant jodein' : 'Plant badlein', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      $('[data-ok]', m.el).onclick = async function () {
        var f = $('#plf', m.el), o = C.form(f); if (!C.need(f, ['name', 'mobile', 'kw'])) return;
        if (!C.validMob(o.mobile)) return C.toast('Sahi mobile likhein', true);
        var st = o.status; delete o.status; o.ref = (o.ref || '').toUpperCase();
        try { var r = await C.run('crm_save', { kind: 'plant', id: rec.id || null, status: st || '', party_id: rec.party_id || d.party_id || null, data: Object.assign({}, rec.data || {}, o) }, 'Plant save ho gaya ✔'); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  };

  async function plantView(id, done) {
    var r = await C.run('crm_get', { id: id }), d = r.data || {}, s = PST[r.status] || [r.status, 'g'], ver = C.can('plants.verify');
    var f = function (l, v) { return v ? '<div><div class="xs mute">' + l + '</div><b>' + esc(v) + '</b></div>' : ''; };
    var foot = (C.can('plants.delete') || (r.owner_id === C.me.id && r.status === 'pending') ? '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + '</button>' : '') + (ver || r.status === 'pending' ? '<button class="btn btn-o" data-edit>' + C.ic('edit') + ' Badlein</button>' : '') + (ver && r.status !== 'verified' ? '<button class="btn btn-p" data-ver>' + C.ic('check') + ' Verify karein</button>' : '') + (ver && r.status === 'pending' ? '<button class="btn btn-r" data-rej>Reject</button>' : '');
    var m = C.modal({ title: r.title, body: '<div class="row" style="margin-bottom:12px">' + C.pill(s[0], s[1]) + '<span class="mute">' + esc(r.ref || '') + '</span><span class="grow"></span>' + C.callBtns(r.mobile) + '</div><div class="fg">' + f('Size', (d.kw || 0) + ' kW') + f('Prakar', d.ptype) + f('Lagne ki tareekh', C.fd(d.install)) + f('Deal value', num(d.deal_value) ? money(d.deal_value) : '') + f('Panel', d.panel) + f('Inverter', d.inverter) + f('Shahar', d.city) + f('Consumer no.', d.consumer_no) + f('Subsidy', d.subsidy) + f('Jodne wala', r.owner_name) + f('Referral', d.ref) + f('Mobile', r.mobile) + '</div>' + (d.address ? '<p style="margin-top:10px">' + esc(d.address) + '</p>' : '') + (d.note ? '<div class="note" style="margin-top:10px">' + esc(d.note) + '</div>' : '') + (r.party_id ? '<a class="btn btn-o btn-sm" style="margin-top:12px" href="#/customer/' + r.party_id + '">' + C.ic('users') + ' Customer dekhein</a>' : ''), foot: foot, onClose: done });
    var b;
    if ((b = $('[data-edit]', m.el))) b.onclick = async function () { m.el.remove(); document.documentElement.style.overflow = ''; await C.plantForm(r); done && done(); };
    if ((b = $('[data-ver]', m.el))) b.onclick = async function () { try { await C.setStatus(r.id, 'verified', {}, 'Verified ✔ — commission apne aap ban gaya'); m.close(); } catch (e) {} };
    if ((b = $('[data-rej]', m.el))) b.onclick = async function () { var why = await C.ask('Reject ki wajah', 'Kyun reject kar rahe hain?', { min: 3, danger: true, ok: 'Reject', tpl: 'reject' }); if (why == null) return; try { await C.setStatus(r.id, 'rejected', { reject_reason: why }, 'Reject kar diya'); m.close(); } catch (e) {} };
    if ((b = $('[data-del]', m.el))) b.onclick = async function () { if (await C.delWithReason(r, r.title)) m.close(); };
  }

  C.plantsRender = async function (el, params, q, route, extra) {
      extra = extra || {};
      var st = q.status || '', uid = q.user || '', all = await C.list('plant', { limit: 3000, user_id: uid || null }), cnt = {};
      all.forEach(function (x) { cnt[x.status] = (cnt[x.status] || 0) + 1; });
      var list = all.filter(function (x) { return !st || x.status === st; }), ver = all.filter(function (x) { return x.status === 'verified'; });
      var h = '<div class="ph"><div><h1>Referral plants</h1><p>Dealer / influencer / staff ke laye hue plant — verify hone par commission apne aap banta hai.</p></div><div class="row">' + C.reportBtns('Plants', function () { return { head: ['No', 'Customer', 'Mobile', 'kW', 'Prakar', 'Tareekh', 'Shahar', 'Deal value', 'Status', 'Jodne wala', 'Referral', 'Subsidy'], rows: list.map(function (x) { var d = x.data; return [x.ref, x.title, x.mobile || '', num(d.kw), d.ptype || '', C.fd(d.install), d.city || '', num(d.deal_value), (PST[x.status] || [x.status])[0], x.owner_name || '', d.ref || '', d.subsidy || '']; }) }; }) + (C.can('plants.create') ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Plant jodein</button>' : '') + '</div></div>';
      h += '<div class="kpis">' + C.kpi('Verified plants', ver.length, '', 'gold') + C.kpi('Kul kW', C.r2(C.sum(ver, function (x) { return x.data.kw; })) + ' kW') + C.kpi('Verify baaki', cnt.pending || 0, '', cnt.pending ? 'warn' : '', route + C.qs(Object.assign({}, extra, { status: 'pending' }))) + '</div>';
      h += '<div class="bar">' + C.chips([['', 'Sab', all.length], ['pending', 'Verify baaki', cnt.pending || 0], ['verified', 'Verified', cnt.verified || 0], ['rejected', 'Reject', cnt.rejected || 0]], st, 'st') + '<input class="inp" type="search" data-q placeholder="Khojein">' + (C.can('plants.view_all') ? C.userFilter(uid) : '') + '</div>';
      h += list.length ? '<div class="list" id="pll">' + list.map(C.plantRow).join('') + '</div>' : '<div class="card">' + C.empty('plant', 'Koi plant nahi', C.can('plants.create') ? 'Lage hue plant jodein — verify hone par commission milega' : '') + '</div>';
      el.innerHTML = h;
      var pl = $('#pll', el); if (pl) C.filterList($('[data-q]', el), pl);
      el.addEventListener('click', function (e) { var c = e.target.closest('[data-st]'); if (c) C.go(route + C.qs(Object.assign({}, extra, { status: c.getAttribute('data-st'), user: uid }))); });
      var us = $('[data-user]', el); if (us) us.onchange = function () { C.go(route + C.qs(Object.assign({}, extra, { status: st, user: this.value }))); };
      C.bind(el, { add: function () { C.plantForm().then(function (r) { if (r) C.render(); }); }, popen: function (id, a, e) { if (e.target.closest('a')) return; plantView(id, function () { C.render(); }); } });
      if (q.open) { C.setQuery({ open: '' }); plantView(q.open, function () { C.render(); }); }
  };
  C.mod('plants', { title: 'Projects', nav: 'projects', allowed: function () { return C.canAny('plants.create', 'plants.view_all'); }, render: async function (el, params, q) { return C.go('#/projects' + C.qs({ tab: 'referral', status: q.status || '', user: q.user || '', open: q.open || '' })); } });
  /* customer page uses plantRow too */
  document.addEventListener('click', function (e) { var r = e.target.closest('[data-act=popen]'); if (!r || C.parse().name === 'projects' || e.target.closest('a')) return; plantView(r.getAttribute('data-id'), function () { C.render(); }); });

  /* ================================================================ commission */
  C.mod('commission', {
    title: 'Commission',
    allowed: function () { return C.canAny('earnings.view_all', 'earnings.manage') || C.isPartner(); },
    render: async function (el, params, q) {
      var st = q.st || '', uid = q.user || '', mg = C.can('earnings.manage'), all = await C.list('earning', { limit: 3000, user_id: uid || null });
      var list = all.filter(function (x) { return !st || x.status === st; }), due = all.filter(function (x) { return x.status === 'due'; }), paid = all.filter(function (x) { return x.status === 'paid'; });
      var me = C.me.meta || {}, rule = me.commission || {};
      var h = '<div class="ph"><div><h1>Commission</h1><p>' + (C.isPartner() ? 'Aapka incentive — har verified plant par apne aap judta hai.' + (rule.mode ? ' Aapka rate: <b>' + (rule.mode === 'per_kw' ? money(rule.value) + ' / kW' : rule.mode === 'fixed' ? money(rule.value) + ' / plant' : rule.value + '% deal value') + '</b>' : '') : 'Dealer / Influencer / Staff ka commission — rate Team me har user par set karein.') + '</p></div><div class="row">' + C.reportBtns('Commission', function () { return { head: ['Tareekh', 'User', 'Detail', 'kW', 'Amount', 'Status', 'Paid on', 'UTR'], rows: list.map(function (x) { return [C.fd(x.data.date || x.created_at), x.owner_name || '', x.title, x.data.kw || '', num(x.amount), x.status === 'paid' ? 'Paid' : 'Baaki', C.fd(x.data.paid_on), x.data.utr || '']; }) }; }) + (mg ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Commission / bonus jodein</button>' : '') + '</div></div>';
      h += '<div class="kpis">' + C.kpi('Baaki', money(C.sum(due, 'amount')), due.length + ' entry', 'gold') + C.kpi('Mil chuka', money(C.sum(paid, 'amount')), paid.length + ' entry') + C.kpi('Kul', money(C.sum(all, 'amount'))) + '</div>';
      h += '<div class="bar">' + C.chips([['', 'Sab'], ['due', 'Baaki'], ['paid', 'Paid']], st, 'st') + (C.can('earnings.view_all') ? C.userFilter(uid) : '') + '</div>';
      h += list.length ? '<div class="list">' + list.map(function (x) { return '<div class="li"><span class="av ' + (x.status === 'paid' ? '' : 'o') + '">' + C.ic('rupee') + '</span><span class="grow"><span class="t">' + esc(x.title) + ' ' + (x.status === 'paid' ? C.pill('Paid') : C.pill('Baaki', 'o')) + (x.data.auto ? C.pill('Auto', 'g') : '') + '</span><span class="m"><span>' + C.ic('user') + esc(x.owner_name || '') + '</span><span>' + esc(C.fd(x.data.date || x.created_at)) + '</span>' + (x.data.kw ? '<span>' + esc(x.data.kw) + ' kW</span>' : '') + (x.data.paid_on ? '<span>Paid ' + esc(C.fd(x.data.paid_on)) + (x.data.utr ? ' · ' + esc(x.data.utr) : '') + '</span>' : '') + (x.data.note ? '<span>' + esc(x.data.note) + '</span>' : '') + '</span></span><span class="amt">' + money(x.amount) + '</span>' + (mg ? '<span class="acts">' + (x.status === 'due' ? '<button class="btn btn-p btn-sm" data-act="paid" data-id="' + x.id + '">Paid</button>' : '') + '<button class="btn btn-g btn-icon btn-sm" data-act="del" data-id="' + x.id + '">' + C.ic('trash') + '</button></span>' : '') + '</div>'; }).join('') + '</div>' : '<div class="card">' + C.empty('rupee', 'Abhi koi commission nahi', C.isPartner() ? 'Plant jodein — Admin verify karega to commission yahan dikhega' : '') + '</div>';
      el.innerHTML = h;
      el.addEventListener('click', function (e) { var c = e.target.closest('[data-st]'); if (c) C.go('#/commission' + C.qs({ st: c.getAttribute('data-st'), user: uid })); });
      var us = $('[data-user]', el); if (us) us.onchange = function () { C.go('#/commission' + C.qs({ st: st, user: this.value })); };
      C.bind(el, {
        add: function () {
          var m = C.modal({ title: 'Commission / bonus jodein', body: '<form id="ef" class="fg">' + C.f('Kisko *', '<select class="inp" name="owner_id">' + C.userOpts('', '— chunein —') + '</select>') + C.f('Amount (₹) *', C.inp('amount', '', 'inputmode="decimal"')) + C.f('Detail', C.inp('title', 'Bonus')) + C.f('Kab dena hai', C.inp('pay_on', C.addDays(C.today(), 7), 'type="date"')) + C.f('Note', C.inp('note', ''), 'full') + '</form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>' });
          $('[data-ok]', m.el).onclick = async function () { var o = C.form($('#ef', m.el)); if (!o.owner_id) return C.toast('User chunein', true); try { await C.run('crm_save', { kind: 'earning', owner_id: o.owner_id, data: { title: o.title, amount: o.amount, pay_on: o.pay_on, note: o.note, date: C.today() } }, 'Jud gaya ✔'); m.close(); C.render(); } catch (e) {} };
        },
        paid: async function (id) { var utr = await C.ask('Commission paid', 'UTR / payment detail (optional)', { ok: 'Paid karein' }); if (utr == null) return; var x = all.find(function (z) { return String(z.id) === id; }); try { await C.setStatus(id, 'paid', { utr: utr }, 'Paid ✔'); C.render(); if (x && await C.confirm('User ko WhatsApp par bata dein?', 'Haan')) window.open(C.wa('', 'Namaste ' + (x.owner_name || '') + ' ji, aapka commission ' + money(x.amount) + ' bhej diya gaya hai.' + (utr ? ' UTR: ' + utr : '') + ' — ' + (C.company().name || '')), '_blank'); } catch (e) {} },
        del: async function (id) { var x = all.find(function (z) { return String(z.id) === id; }); if (await C.delWithReason(x, x.title)) C.render(); }
      });
      if (q.open) C.setQuery({ open: '' });
    }
  });
})();
