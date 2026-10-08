/* Aaj ke kaam — reminders, follow-ups, payments due, quotations to send */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, esc = C.esc, money = C.money, num = C.num;
  var LBL = { lead: 'Lead follow-up', invoice: 'Payment lena', quote: 'Quotation bhejna', earning: 'Commission dena' };

  C.mod('today', {
    title: 'Aaj ke kaam',
    render: async function (el, params, q) {
      var viewAll = C.canAny('reminders.view_all', 'team.stats'), uid = q.user != null && q.user !== '' ? q.user : '', all = q.all === '1', dt = q.date || C.today();
      var p = { date: dt }; if (viewAll && all) p.all = true; else if (viewAll && uid !== '') p.user_id = uid;
      var res = await Promise.all([C.call('crm_today_list', p), C.list('reminder', { mine: !(viewAll && (all || uid !== '')), user_id: viewAll && uid !== '' ? uid : null, from: C.addDays(dt, 1), to: C.addDays(dt, 7), status: 'open' })]);
      var items = res[0].items || [], next = res[1], over = items.filter(function (x) { return x.overdue; }), tod = items.filter(function (x) { return !x.overdue; });
      if (!all && uid === '') C.updateTodayCount(items.length);
      function row(x) {
        var rt = C.RTYPE[x.kind] || C.RTYPE.other, lbl = x.src === 'reminder' ? rt[0] : LBL[x.src], ic = x.src === 'reminder' ? rt[1] : x.src === 'invoice' ? 'rupee' : x.src === 'quote' ? 'quote' : x.src === 'earning' ? 'send' : 'lead';
        var acts = '';
        if (x.src === 'reminder') acts = '<button class="btn btn-p btn-sm" data-act="done" data-id="' + x.id + '">' + C.ic('check') + ' Ho gaya</button><button class="btn btn-o btn-sm" data-act="snooze" data-id="' + x.id + '">Kal</button><button class="btn btn-g btn-icon btn-sm" data-act="edit" data-id="' + x.id + '" aria-label="Badlein">' + C.ic('edit') + '</button>';
        else if (x.src === 'lead') acts = '<a class="btn btn-p btn-sm" href="#/leads?open=' + x.id + '">Kholein</a><button class="btn btn-o btn-sm" data-act="snooze" data-id="' + x.id + '">Kal</button>';
        else if (x.src === 'invoice') acts = '<a class="btn btn-p btn-sm" href="#/invoice/' + x.id + '">Bill</a>';
        else if (x.src === 'quote') acts = '<a class="btn btn-p btn-sm" href="#/quote/' + x.id + '">Bhejein</a>';
        else if (x.src === 'earning') acts = '<a class="btn btn-p btn-sm" href="#/commission?open=' + x.id + '">Dekhein</a>';
        return '<div class="li' + (x.overdue ? ' over' : '') + '"><span class="av' + (x.overdue ? ' r' : x.src === 'invoice' ? ' o' : '') + '">' + C.ic(ic) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(lbl) + '</span><span>' + C.ic('clock') + esc(C.fd(x.due_at)) + (x.time ? ' ' + esc(x.time) : '') + '</span>' + ((all || uid !== '') && x.user ? '<span>' + C.ic('user') + esc(x.user) + '</span>' : '') + (num(x.amount) ? '<span class="b">' + money(x.amount) + '</span>' : '') + (x.note ? '<span>' + esc(x.note) + '</span>' : '') + '</span></span><span class="acts">' + C.callBtns(x.mobile) + acts + '</span></div>';
      }
      var h = '<div class="ph"><div><h1>Aaj ke kaam</h1><p>' + esc(C.fd(dt)) + ' tak ke saare kaam — time par poore karein.</p></div><div class="row"><button class="btn btn-o" data-act="wa">' + C.ic('wa') + ' WhatsApp list</button><button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Naya kaam</button></div></div>';
      h += '<div class="bar"><input class="inp" type="date" data-date value="' + esc(dt) + '" style="width:auto">' + (viewAll ? '<select class="inp" data-who style="width:auto;max-width:240px"><option value="">Mere kaam</option><option value="all"' + (all ? ' selected' : '') + '>Sabke kaam (poori team)</option>' + C.userOpts(all ? '' : uid) + '</select>' : '') + '<span class="sp"></span><span class="pill r">' + over.length + ' overdue</span><span class="pill">' + tod.length + ' aaj</span></div>';
      h += over.length ? '<div class="sec-t" style="color:var(--red)">Overdue — pehle ye karein</div><div class="list">' + over.map(row).join('') + '</div>' : '';
      h += '<div class="sec-t">Aaj</div>' + (tod.length ? '<div class="list">' + tod.map(row).join('') + '</div>' : '<div class="card">' + C.empty('check', 'Aaj ka koi kaam baaki nahi', '') + '</div>');
      h += '<div class="sec-t">Agle 7 din</div>' + (next.length ? '<div class="list">' + next.sort(function (a, b) { return a.due_at < b.due_at ? -1 : 1; }).map(function (r) { var rt = C.RTYPE[r.data.type] || C.RTYPE.other; return '<div class="li"><span class="av b">' + C.ic(rt[1]) + '</span><span class="grow"><span class="t">' + esc(r.title) + '</span><span class="m"><span>' + esc(rt[0]) + '</span><span>' + esc(C.fd(r.due_at)) + (r.data.time ? ' ' + esc(r.data.time) : '') + '</span>' + (r.assigned_name ? '<span>' + C.ic('user') + esc(r.assigned_name) + '</span>' : '') + (r.party_name ? '<span>' + esc(r.party_name) + '</span>' : '') + '</span></span><span class="acts"><button class="btn btn-g btn-icon btn-sm" data-act="edit" data-id="' + r.id + '" aria-label="Badlein">' + C.ic('edit') + '</button></span></div>'; }).join('') + '</div>' : '<p class="mute sm">Agle 7 din me koi reminder nahi.</p>');
      el.innerHTML = h;
      function nav(patch) { var o = { date: dt !== C.today() ? dt : '', user: uid, all: all ? '1' : '' }; Object.assign(o, patch); C.go('#/today' + C.qs(o)); }
      $('[data-date]', el).onchange = function () { nav({ date: this.value }); };
      var w = $('[data-who]', el); if (w) w.onchange = function () { nav(this.value === 'all' ? { all: '1', user: '' } : { all: '', user: this.value }); };
      C.bind(el, {
        add: function () { C.reminderForm().then(function (r) { if (r) C.render(); }); },
        done: async function (id) { await C.reminderDone({ id: id }); C.render(); },
        snooze: async function (id) { try { await C.snooze(id, 1); C.render(); } catch (e) { C.toast(e.message, true); } },
        edit: async function (id) { var r = await C.run('crm_get', { id: id }); var x = await C.reminderForm(r); if (x) C.render(); },
        wa: function () { var t = '*Aaj ke kaam — ' + C.fd(dt) + '*\n' + items.map(function (x, i) { return (i + 1) + '. ' + (x.overdue ? '⚠️ ' : '') + x.title + (x.time ? ' (' + x.time + ')' : '') + (num(x.amount) ? ' — ' + money(x.amount) : ''); }).join('\n'); window.open(C.wa('', t), '_blank'); }
      });
    }
  });
})();
