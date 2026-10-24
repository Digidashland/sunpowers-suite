/* Site Visit — solar site survey / installation visit booking.
   Storage: existing "reminder" record (data.type = 'sitevisit'). Naya SQL table nahi.
   - due_at = visit ki tareekh (mandatory), data.time / data.end_time = start + end (mandatory)
   - assigned_to = engineer / staff, data.mobile = customer (WhatsApp reminder ke liye)
   - party_id = customer record (CRM me agar customer chuna ho), tab customer ki history me bhi dikhega
   - record status: planned → 'open' (Today me dikhega), done/cancelled → 'done'

   FIELD CONTRACT (website / admin / CRM ek hi pattern):
   Har field ka source hota hai: 'customer' = sirf customer record (Conversation) se, form me box nahi (Round 38);
   'auto' = customer / plant / quotation se pehle se bhara, badla ja sakta hai,
   'manual' = hamesha user bharega. Website par auto ka source public form hoga (customer ka mobile/OTP),
   admin/CRM par customer picker. Field list: SVISIT.FIELDS. */
(function () {
  var C = window.CRM; if (!C || !C.mod) return;
  var esc = C.esc;
  var PURPOSE = [['survey', 'Site survey (roof / jagah dekhna)'], ['install', 'Installation'], ['check', 'Service / check-up'], ['repair', 'Repair / complaint']];
  var PTYPE = ['On-grid', 'Off-grid', 'Hybrid', 'Water pump', 'Street light', 'Other'];
  var STATUS = { planned: ['Planned', ''], done: ['Ho gayi', 'g'], cancelled: ['Cancel', 'r'] };
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var cur = { ym: null, sel: null };

  /* Field contract: key, label, source (auto|manual), required. Website / admin isi list se banega. */
  var FIELDS = [
    { key: 'party_name', label: 'Customer ka naam', source: 'customer', required: true },
    { key: 'mobile', label: 'Mobile (10 ank)', source: 'customer', required: true },
    { key: 'address', label: 'Address / jagah', source: 'customer', required: true },
    { key: 'city', label: 'Shahar', source: 'customer', required: false },
    { key: 'kw', label: 'Plant size (kW)', source: 'auto', required: false },
    { key: 'ptype', label: 'Plant prakar', source: 'auto', required: false },
    { key: 'purpose', label: 'Visit ka kaam', source: 'manual', required: true },
    { key: 'date', label: 'Tareekh', source: 'manual', required: true },
    { key: 'time', label: 'Start time', source: 'manual', required: true },
    { key: 'end_time', label: 'End time', source: 'manual', required: true },
    { key: 'assignee', label: 'Engineer / staff', source: 'manual', required: true },
    { key: 'note', label: 'Remarks / Note', source: 'manual', required: true }
  ];

  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function ymd(y, m, d) { return y + '-' + pad(m + 1) + '-' + pad(d); }
  function mins(t) { var p = String(t || '').split(':'); return p.length === 2 ? (+p[0]) * 60 + (+p[1]) : NaN; }
  function vis(a) { return (a || []).filter(function (x) { return x.data && x.data.type === 'sitevisit'; }); }
  function staffName(id) { var u = (C.cache.users || []).filter(function (x) { return String(x.id) === String(id); })[0]; return u ? u.name : ''; }
  function recStatus(vs) { return vs === 'planned' ? 'open' : 'done'; }
  function purposeLabel(p) { var x = PURPOSE.filter(function (q) { return q[0] === p; })[0]; return x ? x[1] : ''; }

  /* Validation (pure). Returns error text or ''. others = same-day visits from list. */
  function validate(o, others) {
    if (!o.date || !/^\d{4}-\d{2}-\d{2}$/.test(o.date)) return 'Tareekh chunein';
    if (!o.start || !o.end) return 'Start aur end time dono chunein (mandatory)';
    var s = mins(o.start), e = mins(o.end);
    if (isNaN(s) || isNaN(e)) return 'Time sahi bharein';
    if (e <= s) return 'End time start time se baad hona chahiye';
    var clash = (others || []).filter(function (x) {
      if (String(x.id) === String(o.id)) return false;
      if (x.data.visit_status === 'cancelled') return false;
      if (String(x.assigned_to) !== String(o.assignee)) return false;
      var xs = mins(x.data.time), xe = mins(x.data.end_time);
      return !isNaN(xs) && !isNaN(xe) && s < xe && xs < e;
    })[0];
    if (clash) return 'Is staff ka ' + clash.data.time + ' – ' + clash.data.end_time + ' pe pehle se visit hai (' + (clash.data.party_name || clash.title) + ')';
    return '';
  }

  /* Auto-fill ka data: customer record + uska latest plant (kW, prakar). Pure mapping, test ho sakta hai. */
  function prefillFrom(party, plants, quotes) {
    var qt = (quotes || []).filter(function (x) { return x.status !== 'rejected' && x.status !== 'expired' && x.data && parseFloat(x.data.kw) > 0; }).sort(function (a, b) { return (b.id || 0) - (a.id || 0); })[0];
    var pl = (plants || []).slice().sort(function (a, b) { return String(b.updated_at || '').localeCompare(String(a.updated_at || '')); })[0];
    return {
      party_id: party.id, party_name: party.title || '', mobile: party.mobile || '',
      address: (party.data && party.data.address) || '', city: (party.data && party.data.city) || '',
      kw: (pl && pl.data && pl.data.kw) || (qt && qt.data.kw) || (party.data && parseFloat(party.data.kw) > 0 ? party.data.kw : ''), ptype: pl ? (pl.data && pl.data.ptype) || '' : ''
    };
  }

  /* Round 37: customer chunte hi uski saari jaankari (plant + quotation + customer record) apne aap aati hai */
  async function loadPre(party) {
    var pl = await C.list('plant', { party_id: party.id, limit: 50 }).catch(function () { return []; }), qs = await C.list('quote', { party_id: party.id, limit: 50 }).catch(function () { return []; });
    return { fill: prefillFrom(party, pl, qs), plants: pl };
  }

  async function dayItems(date) {
    return vis(await C.list('reminder', { from: date, to: date, limit: 500 }));
  }

  async function monthItems(y, m) {
    var from = ymd(y, m, 1), to = ymd(y, m, new Date(y, m + 1, 0).getDate());
    return vis(await C.list('reminder', { from: from, to: to, limit: 3000 }));
  }

  /* Round 38: customer ki details (naam, mobile, pata, shahar) yahan DOBARA nahi bharti — Customer card dikhata hai (Conversation se).
     Visit ke liye sirf visit ka kaam bharna hai: kW / prakar (customer se pehle se bhare), tareekh, time, staff, remarks. */
  async function form(existing, done, party) {
    var d = existing ? existing.data : {};
    var canAssign = C.can('reminders.assign');
    var curAssignee = existing ? existing.assigned_to : C.me.id;
    var users = (C.cache.users || []).filter(function (u) { return u.status === 'active' && u.role !== 'consumer'; });
    var assignBox = canAssign
      ? C.f('Kis staff ko', C.sel('assignee', users.map(function (u) { return [u.id, u.name]; }), curAssignee))
      : '<input type="hidden" name="assignee" value="' + esc(curAssignee) + '">' + C.f('Kis staff ko', '<input class="inp" disabled value="' + esc(staffName(curAssignee) || 'Aap') + '">');
    if (!party && existing && existing.party_id) { try { party = await C.get(existing.party_id); } catch (e) { party = null; } }
    var pre = party ? (await loadPre(party)).fill : {};
    var v = function (k, fallback) { return d[k] != null && d[k] !== '' ? d[k] : (pre[k] != null && pre[k] !== '' ? pre[k] : (fallback || '')); };
    var body = '<form id="svF" class="form">' +
      '<div class="f full" style="margin-bottom:10px"><label>Customer</label><div id="svCust"></div></div>' +
      '<div class="grid2">' + C.f('Plant size (kW)', '<input class="inp" name="kw" inputmode="decimal" value="' + esc(v('kw')) + '">') +
      C.f('Plant prakar', C.sel('ptype', PTYPE, v('ptype', 'On-grid'))) + '</div>' +
      C.f('Visit ka kaam', C.sel('purpose', PURPOSE, d.purpose || 'survey')) +
      C.f('Tareekh', '<input class="inp" type="date" name="date" required value="' + esc(existing ? existing.due_at || '' : cur.sel || '') + '">') +
      C.f('Start time', '<input class="inp" type="time" name="start" required value="' + esc(d.time || '') + '">') +
      C.f('End time', '<input class="inp" type="time" name="end" required value="' + esc(d.end_time || '') + '">') +
      assignBox +
      C.f('Remarks / Note *', '<input class="inp" name="note" required value="' + esc(d.note || '') + '">') +
      '<div class="err" id="svE" role="alert"></div><div class="bar"><button class="btn btn-p" type="submit">Visit save karein</button></div></form>';
    var m = C.modal({ title: existing ? 'Visit badlein' : 'Naya site visit', body: body, size: 'wide' });
    var f = m.el.querySelector('#svF'), errBox = m.el.querySelector('#svE');
    var cc = C.custCardMount(m.el.querySelector('#svCust'), party, { pick: !existing, pickTitle: 'Customer chunein — visit ke liye', onChange: async function (p) {
      var fill = (await loadPre(p)).fill; if (fill.kw) f.elements.kw.value = fill.kw; if (fill.ptype) f.elements.ptype.value = fill.ptype; errBox.textContent = '';
    } });

    f.onsubmit = async function (e) {
      e.preventDefault();
      var fd = new FormData(f), p = cc.party;
      var o = { id: existing ? existing.id : null, date: fd.get('date'), start: fd.get('start'), end: fd.get('end'), assignee: Number(fd.get('assignee')) || C.me.id };
      if (!p) { errBox.textContent = 'Customer chunein (naya ho to list me "Naya" dabakar Conversation bharein)'; return; }
      var pd = p.data || {}, mob = String(p.mobile || '').replace(/\D/g, '').slice(-10);
      if (!String(pd.address || '').trim()) { errBox.textContent = 'Customer ka pata nahi bhara — card par "Badlein" dabakar ek baar bharein'; return; }
      if (!String(fd.get('note') || '').trim()) { errBox.textContent = 'Remarks / Note likhein (visit ka maksad ya baat)'; return; }
      var same = await dayItems(o.date).catch(function () { return []; });
      var err = validate(o, same);
      if (err) { errBox.textContent = err; return; }
      var vs = (existing && existing.data.visit_status) || 'planned';
      var data = Object.assign({}, d, {
        type: 'sitevisit', name: p.title, party_name: p.title, mobile: mob, address: C.addrText(pd) || pd.address || '', city: pd.city || '',
        kw: fd.get('kw') || '', ptype: fd.get('ptype') || '', purpose: fd.get('purpose'),
        time: o.start, end_time: o.end, note: fd.get('note') || '', visit_status: vs
      });
      var extra = { due_at: o.date, assigned_to: o.assignee, status: recStatus(vs), party_id: Number(p.id) };
      try {
        await C.save('reminder', o.id, data, extra, 'Visit save ho gayi ✔');
        m.close();
        if (done) done();
      } catch (ex) { errBox.textContent = ex.message; }
    };
  }

  async function setStatus(v, vs) {
    /* data me name + mobile dobara bhejna zaroori hai, warna crm_save unhe khali kar deta hai */
    var data = Object.assign({}, v.data, { visit_status: vs, name: v.data.name || v.data.party_name || v.title, mobile: v.mobile || v.data.mobile || '' });
    /* party_id key sirf tab bhejें jab link ho: crm_save me key maujood ho to null bhi link tod deta hai */
    var extra = { due_at: v.due_at, assigned_to: v.assigned_to, status: recStatus(vs) };
    if (v.party_id) extra.party_id = v.party_id;
    await C.save('reminder', v.id, data, extra, vs === 'done' ? 'Visit ho gayi ✔' : 'Visit cancel ho gayi');
  }

  function row(v) {
    var s = STATUS[v.data.visit_status || 'planned'] || STATUS.planned;
    var msg = 'Namaste ' + (v.data.party_name || '') + ', aapki solar site visit ' + C.fd(v.due_at) + ' ko ' + v.data.time + ' – ' + v.data.end_time + ' ke beech fix hai. Engineer: ' + staffName(v.assigned_to) + '. Sunpowers.';
    var vs = v.data.visit_status || 'planned';
    var extra = [purposeLabel(v.data.purpose), v.data.kw ? v.data.kw + ' kW' : '', v.data.city || '', staffName(v.assigned_to), v.data.address || ''].filter(Boolean).join(' · ');
    return '<div class="li"><span class="grow"><span class="t">' + esc(v.data.time + ' – ' + v.data.end_time) + ' · ' + esc(v.data.party_name || v.title) + '</span>' +
      '<span class="s">' + esc(extra) + '</span></span>' +
      C.pill(s[0], s[1]) +
      '<span class="acts">' +
      (v.mobile ? '<a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(v.mobile, msg)) + '">WhatsApp</a>' : '') +
      '<button class="btn btn-o btn-sm" data-sv="edit" data-id="' + v.id + '">Badlein</button>' +
      (vs === 'planned' ? '<button class="btn btn-p btn-sm" data-sv="done" data-id="' + v.id + '">Ho gayi</button>' : '') +
      (vs === 'planned' ? '<button class="btn btn-r btn-sm" data-sv="cancel" data-id="' + v.id + '">Cancel</button>' : '') +
      '</span></div>';
  }

  C.mod('sitevisit', {
    title: 'Site Visit',
    allowed: function () { return C.canAny('leads.create', 'leads.view_all'); },
    render: async function (el, params, q) {
      var now = new Date(), today = ymd(now.getFullYear(), now.getMonth(), now.getDate());
      if (!cur.ym) cur.ym = { y: now.getFullYear(), m: now.getMonth() };
      var list = [], err = '';
      await C.users().catch(function () {});
      try { list = await monthItems(cur.ym.y, cur.ym.m); } catch (e) { err = e.message; }

      var dayList = cur.sel ? list.filter(function (v) { return v.due_at === cur.sel; }) : null;
      var upcoming = list.filter(function (v) { return v.due_at >= today && v.data.visit_status !== 'cancelled'; })
        .sort(function (a, b) { return (a.due_at + a.data.time).localeCompare(b.due_at + b.data.time); });
      var shown = dayList || upcoming;

      var h = '<div class="ph"><div><h1>Site Visit</h1><p>Customer chunein — uski details (naam, mobile, pata) Conversation se apne aap aati hain, dobara nahi likhni. Visit ki tareekh aur start + end time mandatory hain. Same engineer ka time clash block hota hai.</p></div>' +
        '<div class="row"><button class="btn btn-p" id="svNew">' + C.ic('plus') + ' Naya visit</button></div></div>';
      if (err) h += '<div class="err">' + esc(err) + '</div>';

      h += '<div class="card"><div class="row" style="justify-content:space-between;align-items:center"><button class="btn btn-o btn-sm" id="svPrev" aria-label="Pichla mahina">‹</button><b>' + MON[cur.ym.m] + ' ' + cur.ym.y + '</b><button class="btn btn-o btn-sm" id="svNext" aria-label="Agla mahina">›</button></div>';
      var first = (new Date(cur.ym.y, cur.ym.m, 1).getDay() + 6) % 7, days = new Date(cur.ym.y, cur.ym.m + 1, 0).getDate();
      h += '<div class="cal-g">' + ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(function (x) { return '<div class="cal-h">' + x + '</div>'; }).join('');
      for (var i = 0; i < first; i++) h += '<div class="cal-c off"></div>';
      for (var d = 1; d <= days; d++) {
        var key = ymd(cur.ym.y, cur.ym.m, d);
        var a = list.filter(function (v) { return v.due_at === key && v.data.visit_status !== 'cancelled'; });
        var chips = a.slice(0, 2).map(function (v) { return '<span class="cal-e">' + esc(v.data.time || '') + ' ' + esc(String(v.data.party_name || v.title || '').split(' ')[0]) + '</span>'; }).join('');
        h += '<div class="cal-c' + (key === today ? ' today' : '') + (a.length ? ' has' : '') + '" data-day="' + key + '" tabindex="0"' + (key === cur.sel ? ' style="outline:2px solid #1b7f3b"' : '') + '><b>' + d + '</b>' + chips + (a.length > 2 ? '<span class="cal-more">+' + (a.length - 2) + '</span>' : '') + '</div>';
      }
      h += '</div></div>';

      h += '<div class="card"><h3>' + (cur.sel ? 'Din: ' + C.fd(cur.sel) + ' <button class="btn btn-g btn-sm" id="svAll">Sab dikhayein</button>' : 'Aane wali visits') + '</h3><div class="list">' +
        shown.map(row).join('') + '</div>' +
        (shown.length ? '' : C.empty('plant', 'Koi visit nahi', 'Naya visit book karein')) + '</div>';
      el.innerHTML = h;

      var ref = function () { return C.mods.sitevisit.render(el, params, q); };
      el.querySelector('#svNew').onclick = function () { form(null, ref); };
      /* #/sitevisit?party=ID  (customer page / workflow step "Site Visit") → form opens with that customer already filled in */
      if (!q.party) cur.opened = '';
      else if (cur.opened !== String(q.party)) {
        cur.opened = String(q.party);
        try { var pp = await C.get(q.party); await form(null, ref, pp); } catch (e) { C.toast('Customer nahi mila', true); }
      }
      el.querySelector('#svPrev').onclick = function () { cur.ym.m--; if (cur.ym.m < 0) { cur.ym.m = 11; cur.ym.y--; } cur.sel = null; ref(); };
      el.querySelector('#svNext').onclick = function () { cur.ym.m++; if (cur.ym.m > 11) { cur.ym.m = 0; cur.ym.y++; } cur.sel = null; ref(); };
      var all = el.querySelector('#svAll'); if (all) all.onclick = function () { cur.sel = null; ref(); };
      el.querySelectorAll('[data-day]').forEach(function (b) {
        b.onclick = function () { var k = b.getAttribute('data-day'); cur.sel = k === cur.sel ? null : k; ref(); };
        b.onkeydown = function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); b.click(); } };
      });
      el.querySelectorAll('[data-sv]').forEach(function (b) {
        b.onclick = async function () {
          var id = b.getAttribute('data-id'), v = list.filter(function (x) { return String(x.id) === id; })[0];
          if (!v) return;
          var act = b.getAttribute('data-sv');
          if (act === 'edit') return form(v, ref);
          try {
            if (act === 'done') await setStatus(v, 'done');
            else if (act === 'cancel') await setStatus(v, 'cancelled');
            ref();
          } catch (ex) { /* C.run ne toast dikha diya */ }
        };
      });
    }
  });

  window.SVISIT = { validate: validate, mins: mins, recStatus: recStatus, prefillFrom: prefillFrom, FIELDS: FIELDS };
})();
