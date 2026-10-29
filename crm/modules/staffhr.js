/* Staff HR — Round 45: staff profile (job / personal / bank & ID), salary set, advance, mahine ki salary pay (-> Accounts > Kharcha me "Salary"), payslip.
   Dikhna: sab ko directory (naam, role, mobile, designation) — HR details sirf staff.hr, salary sirf salary.manage (server par bhi check). */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var EMP = [['', '—'], ['Full-time', 'Full-time'], ['Part-time', 'Part-time'], ['Contract', 'Contract'], ['Intern', 'Intern']];
  var MODES = [['bank', 'Bank transfer'], ['upi', 'UPI'], ['cash', 'Cash'], ['cheque', 'Cheque']];
  function mname(m) { var a = String(m || '').split('-'); try { return new Date(+a[0], +a[1] - 1, 1).toLocaleString('en-IN', { month: 'long', year: 'numeric' }); } catch (e) { return m; } }
  function fdate(d) { return d ? C.fd ? C.fd(d) : d : ''; }

  /* ---------------- payslip ---------------- */
  C.payslipHtml = function (pay, who) {
    var co = C.company(), earn = num(pay.basic) + num(pay.allowance) + num(pay.bonus) + num(pay.commission), ded = num(pay.deduction) + num(pay.adv_cut);
    var row = function (a, b) { return '<tr><td>' + esc(a) + '</td><td style="text-align:right">' + money(b, 1) + '</td></tr>'; };
    return '<div class="bill" data-noi18n style="font-family:Arial,Helvetica,sans-serif;color:#1c2a21;font-size:13px;padding:14px;background:#fff"><div style="border-bottom:3px solid #1e8e3e;padding-bottom:8px;margin-bottom:12px"><div style="font-size:19px;font-weight:800;color:#0b2e1f">' + esc(co.legal || co.name || '') + '</div><div style="font-size:11.5px">' + esc(co.address || '') + '</div></div>' +
      '<div style="font-size:16px;font-weight:800;margin-bottom:8px">Payslip — ' + esc(mname(pay.month)) + '</div>' +
      '<table style="width:100%;border-collapse:collapse;margin-bottom:10px"><tr><td><b>' + esc(who.name || '') + '</b><br><span style="font-size:11.5px">' + esc([who.designation, C.ROLE[who.role] || who.role].filter(Boolean).join(' · ')) + '</span></td><td style="text-align:right;font-size:11.5px">Paid on: ' + esc(fdate(pay.paid_on)) + '<br>Mode: ' + esc(pay.mode || '') + '</td></tr></table>' +
      '<table style="width:100%;border-collapse:collapse" border="1" cellpadding="6"><tr><th align="left" style="background:#eef6f0">Earnings</th><th align="right" style="background:#eef6f0">₹</th></tr>' + row('Basic salary', pay.basic) + (num(pay.allowance) ? row('Allowance', pay.allowance) : '') + (num(pay.bonus) ? row('Bonus / Incentive', pay.bonus) : '') + (num(pay.commission) ? row('Commission', pay.commission) : '') +
      '<tr><th align="left" style="background:#fdf3f2">Deductions</th><th align="right" style="background:#fdf3f2">₹</th></tr>' + (num(pay.deduction) ? row('Deductions', pay.deduction) : '') + (num(pay.adv_cut) ? row('Advance recovery', pay.adv_cut) : '') + (ded ? '' : row('—', 0)) +
      '<tr><td><b>Net pay</b></td><td style="text-align:right"><b>' + money(pay.net, 1) + '</b></td></tr></table><div style="font-size:11.5px;margin-top:6px"><b>In words:</b> ' + esc(C.words(pay.net)) + '</div>' +
      '<table style="width:100%;margin-top:34px"><tr><td style="font-size:11.5px">Employee signature</td><td style="text-align:right;font-size:11.5px">For <b>' + esc(co.legal || co.name || '') + '</b></td></tr></table></div>';
  };
  C.sharePayslip = function (pay, who) {
    var fname = 'Payslip-' + String(who.name || 'staff').replace(/[^A-Za-z0-9]+/g, '-') + '-' + pay.month + '.pdf';
    return C.sharePdf(C.payslipHtml(pay, who), fname, 'Namaste ' + (who.name || '') + ' ji, ' + mname(pay.month) + ' ki payslip.', who.mobile || '', { kind: 'doc', title: 'Payslip ' + mname(pay.month) });
  };

  /* ---------------- advance ---------------- */
  function advanceModal(u) {
    return new Promise(function (res) {
      var m = C.modal({ title: 'Advance — ' + u.name, size: 'sm', body: '<form id="af" class="stack">' + C.f('Advance amount (₹) *', C.inp('amount', '', 'inputmode="decimal"')) + C.f('Tareekh', C.inp('given_on', C.today(), 'type="date"')) + C.f('Kaise diya', C.sel('mode', [['cash', 'Cash'], ['bank', 'Bank transfer'], ['upi', 'UPI']], 'cash')) + C.f('Note', C.inp('note', '')) + '<p class="hint">Ye Accounts &gt; Kharcha me "Staff advance" ke naam se jaayega. Agli salary me se kat sakta hai.</p></form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Advance dein</button>', onClose: function () { res(null); } });
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form($('#af', m.el)); if (num(o.amount) <= 0) return C.toast('Amount likhein', true);
        try { var r = await C.run('crm_staff_advance', { user_id: u.id, amount: num(o.amount), given_on: o.given_on, mode: o.mode, note: o.note }, 'Advance de diya ✔'); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  }

  /* ---------------- pay one month ---------------- */
  function payModal(row, month) {
    var s = row.sal || {}, basic = num(s.monthly), allw = num(s.allowance), ded = num(s.deduction), out = num(row.adv_out), cm = row.comm || {}, cmSum = num(cm.sum);
    return new Promise(function (res) {
      var m = C.modal({ title: 'Salary — ' + row.name + ' (' + mname(month) + ')', size: 'sm', body: '<form id="pf" class="stack"><div class="note g" style="margin:0">Basic <b>' + money(basic) + '</b> + Allowance <b>' + money(allw) + '</b> − Fixed deduction <b>' + money(ded) + '</b></div>' +
        (cmSum > 0 ? '<label class="note" style="display:block;margin:0"><input type="checkbox" name="incl" checked> Commission <b>' + money(cmSum) + '</b> bhi salary me jodein<div class="xs">' + (cm.items || []).map(function (x) { return esc(x.title) + ' — ' + money(x.amount); }).join('<br>') + '</div></label>' : '') +
        (function () { var sg = C.attSuggest ? C.attSuggest(row, row._work, basic, allw) : null; return sg ? '<div class="note' + (sg.any ? '' : ' g') + '" style="margin:0">' + esc(sg.text) + (sg.any && sg.cut > 0 ? '<div style="margin-top:6px"><button type="button" class="btn btn-o btn-sm" data-sg="' + sg.cut + '">Absent / unpaid ka ' + money(sg.cut) + ' deduction me daalein</button></div>' : '') + '<div class="xs">Sirf suggestion — jin din hazri nahi lagi unka kuch nahi katta.</div></div>' : ''; })() +
        C.f('Bonus / Incentive (₹)', C.inp('bonus', '', 'inputmode="decimal" placeholder="0"')) + C.f('Aur deduction (₹)', C.inp('deduction', '', 'inputmode="decimal" placeholder="0"')) +
        (out > 0 ? C.f('Advance katna (₹) <span class="o">(baaki ' + money(out) + ')</span>', C.inp('adv_cut', '', 'inputmode="decimal" placeholder="0"')) : '') +
        C.f('Kab diya', C.inp('paid_on', C.today(), 'type="date"')) + C.f('Kaise diya', C.sel('mode', MODES, 'bank')) + C.f('Note', C.inp('note', '')) +
        '<div class="totals" style="width:100%"><div class="gt"><span>Net salary</span><span id="pnet">' + money(basic + allw - ded + cmSum, 1) + '</span></div></div><p class="hint">Pay karte hi Accounts &gt; Kharcha me "Salary" entry ban jaati hai.</p></form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Salary pay karein</button>', onClose: function () { res(null); } });
      var f = $('#pf', m.el);
      function net() { var o = C.form(f); return basic + allw - ded + (cmSum > 0 && o.incl ? cmSum : 0) + num(o.bonus) - num(o.deduction) - num(o.adv_cut); }
      f.addEventListener('input', function () { $('#pnet', m.el).textContent = money(net(), 1); });
      var sgb = $('[data-sg]', m.el); if (sgb) sgb.onclick = function () { f.deduction.value = sgb.getAttribute('data-sg'); $('#pnet', m.el).textContent = money(net(), 1); };
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (num(o.adv_cut) > out) return C.toast('Advance sirf ' + money(out) + ' baaki hai', true); if (net() <= 0) return C.toast('Net salary zero se zyada ho', true);
        if (!(await C.confirm(row.name + ' ko ' + money(net()) + ' salary (' + mname(month) + ') pay karein?', 'Pay karein'))) return;
        try { var r = await C.run('crm_salary_pay', { user_id: row.id, month: month, bonus: num(o.bonus), include_comm: cmSum > 0 ? !!o.incl : false, deduction: num(o.deduction), adv_cut: num(o.adv_cut), paid_on: o.paid_on, mode: o.mode, note: o.note }, 'Salary pay ho gayi ✔ (Kharcha me jud gayi)'); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  }

  /* ---------------- All Staffs > Salary & Pay tab ---------------- */
  C.payrollTab = async function (tb, q, staff) {
    var month = /^\d{4}-\d{2}$/.test(q.month || '') ? q.month : C.today().slice(0, 7);
    var res = await C.call('crm_payroll_list', { month: month }), rows = res.rows || []; rows.forEach(function (r) { r._work = res.work; });
    function gross(r) { var s = r.sal || {}; return num(s.monthly) + num(s.allowance) - num(s.deduction) + num((r.comm || {}).sum); }
    var due = 0, paid = 0, unset = 0, pend = 0;
    rows.forEach(function (r) { if (r.pay) paid += num(r.pay.net); else if (num((r.sal || {}).monthly) > 0) { due += gross(r); pend++; } else unset++; });
    var h = '<div class="bar"><span class="sm b">Mahina:</span><input class="inp" type="month" data-month value="' + esc(month) + '" style="width:auto"><span class="sp"></span>' + C.reportBtns('Salary ' + month, function () { return { head: ['Naam', 'Role', 'Basic', 'Allowance', 'Commission', 'Deduction', 'Advance baaki', 'Net', 'Status', 'Paid on'], rows: rows.map(function (r) { var s = r.sal || {}; return [r.name, C.ROLE[r.role] || r.role, num(s.monthly), num(s.allowance), r.pay ? num(r.pay.commission) : num((r.comm || {}).sum), num(s.deduction), num(r.adv_out), r.pay ? num(r.pay.net) : gross(r), r.pay ? 'Paid' : 'Baaki', r.pay ? r.pay.paid_on : '']; }) }; }) + '</div>';
    h += '<div class="kpis">' + C.kpi('Pay ho gayi', money(paid), mname(month), 'gold') + C.kpi('Pay karni baaki', money(due), pend + ' staff') + C.kpi('Salary set nahi', String(unset), 'staff profile me set karein') + '</div>';
    h += rows.length ? '<div class="tw"><table class="t"><thead><tr><th>Staff</th><th class="r">Salary</th><th class="r">Allowance</th><th class="r">Commission</th><th class="r">Deduction</th><th class="r">Advance baaki</th><th class="r">Net</th><th>Status</th><th></th></tr></thead><tbody>' + rows.map(function (r) {
      var s = r.sal || {}, p = r.pay, setOk = num(s.monthly) > 0;
      return '<tr><td><a href="javascript:void(0)" data-act="prof" data-id="' + r.id + '"><b>' + esc(r.name) + '</b></a><div class="xs mute">' + esc([r.designation, C.ROLE[r.role]].filter(Boolean).join(' · ')) + '</div></td><td class="r">' + (setOk ? money(s.monthly) : '—') + '</td><td class="r">' + money(s.allowance) + '</td><td class="r">' + (p ? (num(p.commission) ? money(p.commission) : '—') : num((r.comm || {}).sum) ? money(r.comm.sum) : '—') + '</td><td class="r">' + money(p ? p.deduction : s.deduction) + '</td><td class="r' + (num(r.adv_out) > 0 ? ' bad' : '') + '">' + money(r.adv_out) + '</td><td class="r"><b>' + (p ? money(p.net) : setOk ? money(gross(r)) : '—') + '</b></td><td>' + (p ? C.pill('Paid ' + fdate(p.paid_on), '') : setOk ? C.pill('Baaki', 'o') : C.pill('Salary set nahi', 'g')) + '</td><td class="r" style="white-space:nowrap">' +
        (p ? '<button class="btn btn-o btn-sm" data-act="slip" data-id="' + r.id + '">Payslip</button> <button class="btn btn-g btn-icon btn-sm" data-act="undo" data-id="' + r.id + '" aria-label="Wapas">' + C.ic('trash') + '</button>' : setOk ? '<button class="btn btn-p btn-sm" data-act="pay" data-id="' + r.id + '">Pay karein</button>' : '<button class="btn btn-o btn-sm" data-act="prof" data-id="' + r.id + '">Salary set</button>') + '</td></tr>';
    }).join('') + '</tbody></table></div>' : '<div class="card">' + C.empty('users', 'Koi staff nahi', 'Pehle All Staffs me staff jodein') + '</div>';
    tb.innerHTML = h;
    $('[data-month]', tb).onchange = function () { if (this.value) C.go('#/staffs' + C.qs({ tab: 'pay', month: this.value })); };
    function R(id) { return rows.find(function (r) { return String(r.id) === String(id); }); }
    C.bind(tb, {
      prof: function (id) { var u = (C.cache.users || []).find(function (x) { return String(x.id) === String(id); }) || { id: +id, name: R(id).name, role: R(id).role }; C.staffProfile(u, {}).then(function () { C.render(); }); },
      pay: async function (id) { var r = await payModal(R(id), month); if (r) C.render(); },
      slip: function (id) { var r = R(id); C.sharePayslip(r.pay, { name: r.name, role: r.role, designation: r.designation, mobile: r.mobile }); },
      undo: async function (id) { var r = R(id), why = await C.ask('Salary entry hatayein', r.name + ' (' + mname(month) + ') ki salary entry hata dein? Accounts ki Kharcha entry bhi hat jaayegi.', { min: 3, danger: true, ok: 'Hatao', hint: 'Wajah likhein — Activity Record me rahegi.' }); if (why == null) return; try { await C.run('crm_salary_undo', { id: r.pay.id, reason: why }, 'Salary entry hata di'); C.render(); } catch (e) {} }
    });
  };

  /* ---------------- staff profile (modal) ---------------- */
  C.staffProfile = async function (u, roleDefs) {
    var d = await C.call('crm_staff_get', { id: u.id }), hr = d.hr || {}, sal = d.sal || {}, canHr = !!d.can_hr, canSal = !!d.can_sal;
    var users = ((await C.users()) || []).filter(function (x) { return ['admin', 'manager', 'staff', 'hr', 'marketing'].indexOf(x.role) >= 0 && x.id !== d.id; });
    var canLogin = C.can('users.manage') || (C.can('staff.manage') && ['manager', 'staff', 'marketing'].indexOf(d.role) >= 0);
    var rep = users.map(function (x) { return [String(x.id), x.name + ' — ' + (C.ROLE[x.role] || x.role)]; });
    function H(k, label, attrs, cls) { return C.f(label, C.inp('h_' + k, hr[k], attrs || ''), cls); }
    var body = '<form id="sf" class="stack"><div class="li" style="padding:0;border:0"><span class="av">' + esc(C.initials(d.name)) + '</span><span class="grow"><span class="t">' + esc(d.name) + ' ' + C.pill(C.ROLE[d.role] || d.role, 'g') + (d.status !== 'active' ? C.pill(d.status, 'o') : '') + '</span><span class="m">' + (d.mobile ? '<span>' + C.ic('phone') + ' ' + esc(d.mobile) + '</span>' : '') + (d.email ? '<span>' + esc(d.email) + '</span>' : '') + '</span></span>' +
      (d.mobile ? '<a class="btn btn-o btn-sm" href="tel:' + esc(d.mobile) + '">' + C.ic('phone') + '</a> <a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(d.mobile, '')) + '">' + C.ic('wa') + '</a>' : '') + '</div>';
    if (canHr) {
      body += '<div class="sec-t">Job</div><div class="fg g3">' + H('designation', 'Designation', 'placeholder="Jaise: Sales Executive"') + H('department', 'Department') + C.f('Kiske neeche (Reporting)', C.sel('h_reports_to', rep, hr.reports_to || '', '—')) + H('joining', 'Joining date', 'type="date"') + C.f('Type', C.sel('h_emp_type', EMP, hr.emp_type || '')) + H('location', 'Kaam ki jagah') + H('exit_date', 'Chhodne ki date <span class="o">(agar chhod diya)</span>', 'type="date"') + '</div>' +
        '<div class="sec-t">Personal</div><div class="fg g3">' + H('qualification', 'Qualification') + H('experience', 'Pichhla experience') + H('dob', 'Janm tithi', 'type="date"') + C.f('Gender', C.sel('h_gender', [['', '—'], ['Male', 'Male'], ['Female', 'Female'], ['Other', 'Other']], hr.gender || '')) + H('blood', 'Blood group') + H('emergency_name', 'Emergency contact naam') + H('emergency_mobile', 'Emergency mobile', 'inputmode="tel"') + C.f('Ghar ka pata', '<textarea class="inp" rows="2" name="h_address">' + esc(hr.address || '') + '</textarea>', 'full') + '</div>' +
        '<div class="sec-t">Bank &amp; ID <span class="o">(sirf HR / Admin ko dikhta hai)</span></div><div class="fg g3">' + H('bank_holder', 'Account holder') + H('bank_name', 'Bank') + H('bank_acc', 'Account number', 'inputmode="numeric"') + H('ifsc', 'IFSC') + H('upi', 'UPI ID') + H('id_proof', 'ID proof (type + number)') + '</div>' +
        C.f('Note', '<textarea class="inp" rows="2" name="h_notes">' + esc(hr.notes || '') + '</textarea>', 'full');
    } else {
      body += '<div class="sec-t">Job</div><div class="fg g3"><div><div class="xs mute">Designation</div><b>' + esc(hr.designation || '—') + '</b></div><div><div class="xs mute">Kiske neeche</div><b>' + esc((function () { var x = users.find(function (z) { return String(z.id) === String(hr.reports_to); }); return x ? x.name : '—'; })()) + '</b></div><div><div class="xs mute">Joining</div><b>' + esc(fdate(hr.joining) || '—') + '</b></div></div>';
    }
    if (canSal) {
      body += '<div class="sec-t">Salary <span class="o">(sirf Admin / HR ko dikhti hai)</span></div><div class="fg g3">' + C.f('Monthly salary (₹)', C.inp('s_monthly', sal.monthly, 'inputmode="decimal"')) + C.f('Allowance (₹)', C.inp('s_allowance', sal.allowance, 'inputmode="decimal"')) + C.f('Fixed deduction (₹) <span class="o">(PF / ESI aadi)</span>', C.inp('s_deduction', sal.deduction, 'inputmode="decimal"')) + C.f('Salary ka din (1-31)', C.inp('s_pay_day', sal.pay_day, 'inputmode="numeric"')) + C.f('Note', C.inp('s_note', sal.note), 'full') + '</div>' +
        '<div class="row wrap" style="gap:10px;align-items:center"><span class="pill ' + (num(d.adv_out) > 0 ? 'o' : 'g') + '">Advance baaki: ' + money(d.adv_out) + '</span><button type="button" class="btn btn-o btn-sm" data-adv>' + C.ic('plus') + ' Advance dein</button></div>';
      if ((d.pays || []).length) body += '<div class="sec-t">Salary di (pichhle mahine)</div><div class="list">' + d.pays.map(function (p) { return '<div class="li"><span class="grow"><span class="t">' + esc(mname(p.month)) + '</span><span class="m"><span>' + money(p.net) + '</span><span>' + esc(fdate(p.paid_on)) + ' · ' + esc(p.mode) + '</span></span></span><button type="button" class="btn btn-o btn-sm" data-slip="' + p.id + '">Payslip</button></div>'; }).join('') + '</div>';
      if ((d.advs || []).length) body += '<div class="sec-t">Advance diye</div><div class="list">' + d.advs.map(function (a) { return '<div class="li"><span class="grow"><span class="t">' + money(a.amount) + '</span><span class="m"><span>' + esc(fdate(a.given_on)) + '</span><span>' + esc(a.mode) + '</span>' + (a.note ? '<span>' + esc(a.note) + '</span>' : '') + '</span></span></div>'; }).join('') + '</div>';
    }
    body += '</form>';
    return new Promise(function (res) {
      var changed = false;
      var m = C.modal({ title: 'Staff profile', size: 'wide', body: body, foot: (canLogin ? '<button class="btn btn-o" data-login style="margin-right:auto">' + C.ic('key') + ' Login / Role' + (C.can('users.manage') ? ' / Permission' : '') + '</button>' : '') + '<button class="btn btn-o" data-close>' + (canHr || canSal ? 'Cancel' : 'Band') + '</button>' + (canHr || canSal ? '<button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>' : ''), onClose: function () { res(changed); } });
      var f = $('#sf', m.el);
      var lg = $('[data-login]', m.el); if (lg) lg.onclick = function () { var uu = (C.cache.users || []).find(function (x) { return x.id === d.id; }); if (!uu) return C.toast('User list taza karke dobara kholein', true); C.userForm(C.clone(uu), roleDefs || {}, { kind: 'staff' }).then(function (r) { if (r) { changed = true; m.close(); } }); };
      var av = $('[data-adv]', m.el); if (av) av.onclick = async function () { var r = await advanceModal(d); if (r) { changed = true; m.close(); } };
      $$('[data-slip]', m.el).forEach(function (b) { b.onclick = function () { var p = d.pays.find(function (z) { return String(z.id) === b.getAttribute('data-slip'); }); C.sharePayslip(p, { name: d.name, role: d.role, designation: hr.designation, mobile: d.mobile }); }; });
      var ok = $('[data-ok]', m.el); if (ok) ok.onclick = async function () {
        var o = C.form(f), body2 = { id: d.id };
        if (canHr) { var h2 = {}; Object.keys(o).forEach(function (k) { if (k.indexOf('h_') === 0) h2[k.slice(2)] = o[k]; }); if (h2.emergency_mobile && !C.validMob(h2.emergency_mobile)) return C.toast('Emergency mobile sahi likhein', true); body2.hr = h2; }
        if (canSal) { var s2 = {}; Object.keys(o).forEach(function (k) { if (k.indexOf('s_') === 0) s2[k.slice(2)] = k === 's_note' ? o[k] : num(o[k]); }); body2.sal = s2; }
        try { await C.run('crm_staff_save', body2, 'Save ho gaya ✔'); changed = true; m.close(); } catch (e) {}
      };
    });
  };
})();
