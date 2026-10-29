/* Round 47: Hazri (attendance) + Leave.
   - Meri Profile: aaj ka Check-in / Check-out, leave maangna, apni leave list.
   - All Staffs > "Hazri & Leave": mahine ka grid, Admin / HR / Manager hazri lagayein, leave approve / reject.
   - Salary & Pay me hazri ka saar + deduction ka suggestion (payModal, staffhr.js).
   Saara data server me (crm_att_*, crm_leave_*). Sunday = weekly off. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, num = C.num;
  var ST = { present: ['P', 'Present'], absent: ['A', 'Absent'], half: ['H', 'Half day'], leave: ['L', 'Leave (paid)'], unpaid: ['U', 'Unpaid leave'], holiday: ['O', 'Holiday'] };
  var KINDS = [['Casual', 'Casual'], ['Sick', 'Sick'], ['Paid', 'Paid / Earned'], ['Unpaid', 'Unpaid (bina tankhwah)']];
  function mname(m) { var a = String(m || '').split('-'); try { return new Date(+a[0], +a[1] - 1, 1).toLocaleString('en-IN', { month: 'long', year: 'numeric' }); } catch (e) { return m; } }
  function pillOf(s) { return s === 'approved' ? C.pill('Approved', '') : s === 'rejected' ? C.pill('Reject', 'r') : s === 'cancelled' ? C.pill('Cancel', 'g') : C.pill('Pending', 'o'); }
  function range(l) { return C.fd(l.from) + (l.to !== l.from ? ' – ' + C.fd(l.to) : '') + ' · ' + l.days + ' din'; }

  /* ------------------------------------------------ Meri Profile card */
  function leaveModal(after) {
    var t = C.today(), body = '<form id="lf" class="fg">' + C.f('Kab se *', C.inp('from', t, 'type="date"')) + C.f('Kab tak', C.inp('to', t, 'type="date"')) + C.f('Prakar', C.sel('kind', KINDS, 'Casual')) +
      '<label class="f" style="justify-content:flex-end"><span class="xs mute">Sirf ek din ho to</span><span><input type="checkbox" name="half"> Aadha din</span></label>' +
      C.f('Wajah *', C.ta('reason', '', 'rows="2" maxlength="300" placeholder="Jaise: Ghar me shaadi hai"'), 'full') + '</form><p class="hint">Sunday weekly off hai — leave me nahi ginta. Admin / HR approve karenge.</p>';
    var m = C.modal({ title: 'Leave maangein', size: 'sm', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Leave maangein</button>' });
    $('[data-ok]', m.el).onclick = async function () {
      var f = $('#lf', m.el), v = C.form(f); if (!C.need(f, ['from', 'reason'])) return;
      try { await C.run('crm_leave_apply', { from: v.from, to: v.to || v.from, kind: v.kind, reason: v.reason, half: !!v.half }, 'Leave maangi gayi ✔'); m.close(); after && after(); } catch (e) {}
    };
  }
  C.attMe = async function (box) {
    if (!box) return;
    var me = await C.call('crm_att_me', {}).catch(function () { return null; });
    if (!me || !me.staff) { box.innerHTML = ''; return; }
    var ls = await C.call('crm_leave_list', { mine: true }).catch(function () { return []; });
    function draw(me) {
      var t = me.today, sm = me.sum || {};
      var h = '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:8px">' + C.ic('clock') + ' Meri Hazri</h3><div class="att-today">';
      if (!t) h += '<span class="pill g">Aaj abhi check-in nahi hua</span><button class="btn btn-p" data-act="att_in">' + C.ic('check') + ' Check-in</button>';
      else if (t.status === 'present' || t.status === 'half') h += '<span class="pill">' + (ST[t.status] || [])[1] + ' · ' + esc(t.in_time || '') + (t.out_time ? ' → ' + esc(t.out_time) : '') + '</span>' + (t.out_time ? '<span class="xs mute">Aaj ka din poora ✔</span>' : '<button class="btn btn-o" data-act="att_out">Check-out</button>');
      else h += '<span class="pill b">Aaj: ' + esc((ST[t.status] || [])[1] || t.status) + '</span>';
      h += '</div><div class="xs mute" style="margin-top:10px">' + esc(mname(me.month)) + ' — Present <b>' + (sm.present || 0) + '</b> · Half <b>' + (sm.half || 0) + '</b> · Absent <b>' + (sm.absent || 0) + '</b> · Leave <b>' + (sm.leave || 0) + '</b> · Unpaid <b>' + (sm.unpaid || 0) + '</b></div>' +
        '<div class="row" style="margin-top:10px"><button class="btn btn-o" data-act="att_leave">' + C.ic('plus') + ' Leave maangein</button></div>';
      if (ls.length) h += '<div class="sec-t" style="margin-top:12px">Meri leave</div><div class="list">' + ls.slice(0, 8).map(function (l) {
        return '<div class="li"><span class="grow"><span class="t">' + esc(range(l)) + ' ' + pillOf(l.status) + '</span><span class="m"><span>' + esc(l.kind) + '</span><span>' + esc(l.reason) + '</span>' + (l.note ? '<span>' + esc(l.decided_by || '') + ': ' + esc(l.note) + '</span>' : '') + '</span></span>' +
          (l.status === 'pending' ? '<button class="btn btn-o btn-sm" data-act="att_cancel" data-id="' + l.id + '">Cancel</button>' : '') + '</div>'; }).join('') + '</div>';
      box.innerHTML = h + '</div>';
    }
    draw(me);
    async function reload() { me = await C.call('crm_att_me', {}); ls = await C.call('crm_leave_list', { mine: true }).catch(function () { return []; }); draw(me); }
    if (!box._bound) { box._bound = true;
      C.bind(box, {
        att_in: async function () { try { await C.run('crm_att_mark', { action: 'in' }, 'Check-in ho gaya ✔'); reload(); } catch (e) {} },
        att_out: async function () { try { await C.run('crm_att_mark', { action: 'out' }, 'Check-out ho gaya ✔'); reload(); } catch (e) {} },
        att_leave: function () { leaveModal(reload); },
        att_cancel: async function (id) { if (!(await C.confirm('Ye leave request cancel karein?', 'Haan, cancel'))) return; try { await C.run('crm_leave_decide', { id: +id, action: 'cancel' }, 'Cancel ho gayi'); reload(); } catch (e) {} }
      }); }
  };

  /* ------------------------------------------------ All Staffs > Hazri & Leave */
  C.attTab = async function (tb, q) {
    var month = /^\d{4}-\d{2}$/.test(q.month || '') ? q.month : C.today().slice(0, 7);
    var res = await Promise.all([C.call('crm_att_month', { month: month }), C.call('crm_leave_list', {})]), d = res[0], ls = res[1], today = C.today();
    var pend = ls.filter(function (l) { return l.status === 'pending'; }), done = ls.filter(function (l) { return l.status !== 'pending'; }).slice(0, 8);
    var dim = d.days, cols = []; for (var i = 1; i <= dim; i++) cols.push(i);
    function dkey(i) { return month + '-' + (i < 10 ? '0' + i : i); }
    function isSun(i) { return new Date(+month.slice(0, 4), +month.slice(5) - 1, i).getDay() === 0; }
    var h = '<div class="bar"><span class="sm b">Mahina:</span><input class="inp" type="month" data-month value="' + esc(month) + '" style="width:auto"><span class="sp"></span></div>';
    h += '<div class="sec-t">Leave requests (' + pend.length + ' pending)</div>';
    h += pend.length ? '<div class="list">' + pend.map(function (l) {
      return '<div class="li"><span class="grow"><span class="t">' + esc(l.name) + ' — ' + esc(range(l)) + ' ' + C.pill(l.kind, 'b') + '</span><span class="m"><span>' + esc(l.reason) + '</span></span></span><button class="btn btn-p btn-sm" data-act="ok" data-id="' + l.id + '">Approve</button> <button class="btn btn-o btn-sm" data-act="no" data-id="' + l.id + '">Reject</button></div>'; }).join('') + '</div>' : '<div class="note g">Koi leave request pending nahi.</div>';
    if (done.length) h += '<div class="xs mute" style="margin:8px 0 0">Haal ki: ' + done.map(function (l) { return esc(l.name) + ' ' + esc(C.fd(l.from)) + ' (' + esc(l.status === 'approved' ? 'approved' : l.status === 'rejected' ? 'reject' : 'cancel') + ')'; }).join(' · ') + '</div>';
    h += '<div class="sec-t" style="margin-top:14px">' + esc(mname(month)) + ' ki hazri <span class="o">(kisi din par click karke hazri lagayein / badlein)</span></div>';
    h += '<div class="att-leg">' + Object.keys(ST).map(function (k) { return '<span><span class="att-c ' + ST[k][0] + '">' + ST[k][0] + '</span> ' + ST[k][1] + '</span>'; }).join('') + '<span>Dhusar = Sunday (weekly off) · Is mahine ke kaam ke din: <b>' + d.work + '</b></span></div>';
    h += d.rows.length ? '<div class="tw"><table class="att-grid"><thead><tr><th>Staff</th>' + cols.map(function (i) { return '<th>' + i + '</th>'; }).join('') + '<th>P</th><th>H</th><th>A</th><th>L</th><th>U</th></tr></thead><tbody>' + d.rows.map(function (r) {
      var c = { present: 0, half: 0, absent: 0, leave: 0, unpaid: 0 };
      var tds = cols.map(function (i) {
        var k = dkey(i), a = r.att[k], future = k > today, sun = isSun(i); if (a && c[a.s] != null) c[a.s]++;
        return '<td class="' + (sun ? 'sun ' : '') + (future ? '' : 'cl') + '"' + (future ? '' : ' data-act="cell" data-u="' + r.id + '" data-d="' + k + '"') + (a && (a.in || a.n) ? ' title="' + esc((a.in ? a.in + (a.out ? '–' + a.out : '') + ' ' : '') + (a.n || '')) + '"' : '') + '>' + (a ? '<span class="att-c ' + ST[a.s][0] + '">' + ST[a.s][0] + '</span>' : sun ? '·' : '') + '</td>';
      }).join('');
      return '<tr><td><b>' + esc(r.name) + '</b><div class="xs mute">' + esc(C.ROLE[r.role] || r.role) + '</div></td>' + tds + '<td><b>' + c.present + '</b></td><td>' + c.half + '</td><td class="' + (c.absent ? 'bad' : '') + '">' + c.absent + '</td><td>' + c.leave + '</td><td>' + c.unpaid + '</td></tr>';
    }).join('') + '</tbody></table></div>' : '<div class="card">' + C.empty('users', 'Koi staff nahi', '') + '</div>';
    tb.innerHTML = h;
    $('[data-month]', tb).onchange = function () { if (this.value) C.go('#/staffs' + C.qs({ tab: 'att', month: this.value })); };
    function reload() { C.attTab(tb, q); }
    if (tb._att) tb.removeEventListener('click', tb._att);
    var map = {
      ok: async function (id) { try { await C.run('crm_leave_decide', { id: +id, action: 'approve' }, 'Leave approve ✔ — hazri me chadh gayi'); reload(); } catch (e) {} },
      no: async function (id) { var why = await C.ask('Reject ki wajah', 'Kyun reject kar rahe hain?', { min: 3, ok: 'Reject', danger: true }); if (why == null) return; try { await C.run('crm_leave_decide', { id: +id, action: 'reject', note: why }, 'Leave reject ki'); reload(); } catch (e) {} },
      cell: function (id, a) {
        var u = a.getAttribute('data-u'), day = a.getAttribute('data-d'), r = d.rows.filter(function (x) { return String(x.id) === u; })[0], cur = r.att[day] || {};
        var opts = Object.keys(ST).map(function (k) { return [k, ST[k][1]]; }).concat([['clear', '— Hazri hatayein —']]);
        var m = C.modal({ title: r.name + ' — ' + C.fd(day), size: 'sm', body: '<div class="fg" id="cf">' + C.f('Status', C.sel('status', opts, cur.s || 'present'), 'full') + C.f('Aaya', C.inp('in_time', cur.in || '', 'type="time"')) + C.f('Gaya', C.inp('out_time', cur.out || '', 'type="time"')) + C.f('Note', C.inp('note', cur.n || '', 'maxlength="200"'), 'full') + '</div>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>' });
        $('[data-ok]', m.el).onclick = async function () { var v = C.form($('#cf', m.el)); try { await C.run('crm_att_mark', { user_id: +u, day: day, status: v.status, in_time: v.in_time, out_time: v.out_time, note: v.note }, 'Hazri save ✔'); m.close(); reload(); } catch (e) {} };
      }
    };
    tb._att = function (e) { var a = e.target.closest('[data-act]'); if (!a || !tb.contains(a)) return; var f = map[a.getAttribute('data-act')]; if (f) { e.preventDefault(); f(a.getAttribute('data-id'), a); } };
    tb.addEventListener('click', tb._att);
  };

  /* Salary pay ke time: hazri ka saar + suggested deduction (khud tay karein) */
  C.attSuggest = function (row, work, basic, allw) {
    var a = row.att || {}, wd = num(work) || 26, per = (basic + allw) / wd, cut = per * (num(a.absent) + num(a.unpaid) + 0.5 * num(a.half));
    return { text: 'Hazri: Present ' + (a.present || 0) + ' · Half ' + (a.half || 0) + ' · Absent ' + (a.absent || 0) + ' · Leave ' + (a.leave || 0) + ' · Unpaid ' + (a.unpaid || 0) + ' (kaam ke din ' + wd + ')', cut: Math.round(cut), any: (num(a.absent) + num(a.unpaid) + num(a.half)) > 0 };
  };
})();
