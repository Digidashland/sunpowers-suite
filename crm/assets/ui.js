/* Sunpowers CRM — shared pickers & forms used by many modules */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, num = C.num, money = C.money;

  C.RTYPE = { call: ['Call karna', 'phone'], visit: ['Site visit', 'home'], meeting: ['Meeting', 'users'], quote_send: ['Quotation bhejna', 'quote'], followup: ['Lead follow-up', 'lead'],
    amc: ['AMC / Service', 'settings'], complaint: ['Complaint', 'alert'], payment_in: ['Payment lena', 'rupee'], payment_out: ['Payment dena', 'send'], other: ['Doosra kaam', 'today'] };
  C.rtypeOpts = function (sel) { return Object.keys(C.RTYPE).filter(function (k) { return k !== 'followup'; }).map(function (k) { return '<option value="' + k + '"' + (sel === k ? ' selected' : '') + '>' + C.RTYPE[k][0] + '</option>'; }).join(''); };
  C.STAGE = { new: ['Nayi', 'b'], contacted: ['Baat hui', 'v'], visit: ['Visit', 'o'], quote: ['Quotation', 'o'], won: ['Jeeti ✔', ''], lost: ['Haari', 'g'] };
  C.stagePill = function (s) { var x = C.STAGE[s] || [s, 'g']; return C.pill(x[0], x[1]); };
  C.PARTY_TYPES = [['customer', 'Customer'], ['supplier', 'Supplier / Vendor'], ['both', 'Dono']];
  C.SOURCES = ['Walk-in', 'Reference', 'Website', 'Online Store', 'Facebook', 'Instagram', 'Google', 'JustDial', 'IndiaMART', 'TradeIndia', 'Sulekha', 'Meta Ads', 'Google Ads', 'YouTube', 'WhatsApp', 'Camp / Event', 'Dealer', 'Influencer', 'Other'];

  /* links to company store / website (with partner referral code) */
  C.storeUrl = function () { var co = C.company(), u = String(co.store_url || '').trim(), site = String(co.website || '').replace(/^https?:\/\//, '').replace(/\/+$/, '').toLowerCase(), h = u.replace(/^https?:\/\//, '').replace(/\/+$/, '').toLowerCase();
    if (!u || h === site || /^((www\.)?sunpowers\.in|shop\.sunpowers\.in)$/.test(h)) u = C.cfg.STORE_URL || u; return u || ''; }; // store link kabhi main website na khole
  C.siteUrl = function () { var co = C.company(); return co.website ? (/^https?:/.test(co.website) ? co.website : 'https://' + co.website) : (C.cfg.SITE_URL || ''); };
  C.refLink = function () { var u = C.storeUrl(); if (!u || !C.me || !C.me.ref_code) return u; return u + (u.indexOf('?') >= 0 ? '&' : '?') + 'ref=' + encodeURIComponent(C.me.ref_code); };
  C.copy = async function (t, msg) { try { await navigator.clipboard.writeText(t); C.toast(msg || 'Copy ho gaya ✔'); } catch (e) { C.ask('Copy karein', 'Neeche wala text copy karein', { value: t }); } };

  /* ------------------------------------------------ customer (party) form */
  C.SERVICE_TYPES = ['Panel cleaning', 'Maintenance / AMC', 'Repair / Error fix', 'Shifting / Re-installation', 'Audit / Inspection', 'Other service'];
  C.PROJECT_TYPES = ['Residential', 'Commercial', 'Industrial', 'VFD'];
  /* STEP 0 of "Add New Customer": where did he come from? (the lead path) — nothing else opens before this is chosen */
  C.pathPick = function (cur) {
    return new Promise(function (res) {
      var list = (C.sourceList ? C.sourceList() : C.SOURCES), done = false;
      var body = '<div class="note g" style="margin-bottom:10px">Pehle batayein customer <b>kahan se aaya</b>. Yahi uska Leads wala <b>path</b> banega — isse pata chalta hai lead asli (organic) hai ya nahi.</div>' +
        '<div class="pathgrid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:8px">' + list.map(function (x) { return '<button type="button" class="btn ' + (x === cur ? 'btn-p' : 'btn-o') + '" data-path="' + esc(x) + '">' + esc(x) + '</button>'; }).join('') + '</div>';
      var m = C.modal({ title: 'Customer kahan se aaya?', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button>', onClose: function () { if (!done) res(null); } });
      m.el.addEventListener('click', function (e) { var b = e.target.closest('[data-path]'); if (!b) return; done = true; var v = b.getAttribute('data-path'); m.el.remove(); document.documentElement.style.overflow = ''; res(v); });
    });
  };
  /* customer is created ONLY with everything the flow needs (mirrors the server rule in crm_rules_trg) */
  C.partyForm = async function (rec, opt) {
    opt = opt || {}; rec = rec || { data: {} };
    var isNew = !rec.id, pre = Object.assign({}, opt.prefill || {});
    if (isNew && !opt.onSubmit && !pre.source) { var pth = await C.pathPick(); if (!pth) return null; pre.source = pth; opt = Object.assign({}, opt, { prefill: pre }); }
    return partyFormBody(rec, opt);
  };
  function partyFormBody(rec, opt) {
    var d = Object.assign({}, rec.data || {}), isNew = !rec.id;
    if (opt.prefill) Object.assign(d, opt.prefill);
    return new Promise(function (res) {
      var assign = C.can('customers.assign') && (C.cache.users || []).length, kind = d.cust_kind || (isNew ? '' : 'project'), seg = d.segment || (d.gstin || d.company ? 'b2b' : (isNew ? '' : 'b2c'));
      function opts(map, cur, blank) { return (blank ? '<option value="">' + blank + '</option>' : '') + Object.keys(map).map(function (k) { return '<option value="' + k + '"' + (k === cur ? ' selected' : '') + '>' + esc(map[k]) + '</option>'; }).join(''); }
      var req = isNew ? ' *' : '', srcs = (C.sourceList ? C.sourceList() : C.SOURCES).slice(); if (d.source && srcs.indexOf(d.source) < 0) srcs.push(d.source);
      var body = '<form class="stack" id="pf">' +
        (isNew ? '<div class="note g" style="margin-bottom:8px"><b>Mobile number zaroori hai</b> (email optional). Aage ka poora flow chalane ke liye <b>*</b> wali jaankari yahin bharein.</div>' : '') +
        '<div class="fg">' + C.f('Naam *', C.inp('name', d.name || rec.title, 'maxlength="120" required')) + C.f('Mobile *', C.inp('mobile', d.mobile || rec.mobile, 'inputmode="tel" maxlength="16"')) +
        C.f('Email <span class="o">(optional)</span>', C.inp('email', d.email, 'type="email" maxlength="160"')) + C.f('Doosra mobile / WhatsApp', C.inp('mobile2', d.mobile2, 'inputmode="tel" maxlength="16"')) + '</div>' +
        '<div class="sec-t">Customer kaisa hai?</div><div class="fg">' + C.f('Prakar', C.sel('type', C.PARTY_TYPES, d.type || 'customer')) +
        '<div data-show="cust">' + C.f('Path — kahan se aaya' + req, C.sel('source', srcs, d.source, '— chunein —')) + '</div>' +
        '<div data-show="cust"><div class="fld"><label class="l">Kya kharidega' + req + '</label><select class="inp" name="cust_kind">' + opts({ project: 'Project (solar plant lagwana)', product: 'Product (sirf item / saaman)', service: 'Service (cleaning / AMC / repair)' }, kind, isNew ? '— chunein —' : '') + '</select></div></div>' +
        '<div data-show="cust"><div class="fld"><label class="l">Customer' + req + '</label><select class="inp" name="segment">' + opts(C.SEGMENTS, seg, isNew ? '— chunein —' : '') + '</select></div></div></div>' +
        '<div data-show="b2b"><div class="sec-t">Business ki jaankari</div><div class="fg">' + C.f('Company / Firm' + req, C.inp('company', d.company)) + C.f('GSTIN <span class="o">(optional)</span>', C.inp('gstin', d.gstin, 'maxlength="15" style="text-transform:uppercase"')) +
        C.f('Contact person', C.inp('contact_person', d.contact_person)) + C.f('Designation', C.inp('designation', d.designation)) + '</div></div>' +
        '<div data-show="project"><div class="sec-t">Project ki zaroorat</div><div class="fg">' + C.f('Project type' + req, C.sel('project_type', C.PROJECT_TYPES, d.project_type, '— chunein —')) + C.f('Chahiye (kW)' + req, C.inp('kw', d.kw, 'inputmode="decimal"')) + C.f('Bijli ka bill (₹/mahina)', C.inp('bill', d.bill, 'inputmode="numeric"')) + '</div></div>' +
        '<div data-show="product"><div class="sec-t">Product ki zaroorat</div><div class="fg">' + C.f('Kaunsa product / kitna' + req, C.inp('interest', d.interest, 'maxlength="200" placeholder="Jaise: 10 panel 540W, 1 inverter"'), 'full') + '</div></div>' +
        '<div data-show="service"><div class="sec-t">Service ki zaroorat</div><div class="fg">' + C.f('Kaunsi service' + req, C.sel('service_type', C.SERVICE_TYPES, d.service_type, '— chunein —')) + C.f('Kya dikkat / kaam', C.inp('service_note', d.service_note, 'maxlength="200"')) + '</div></div>' +
        '<div class="sec-t" data-show="cust">Pata' + (isNew ? ' (Blueprint, Site Visit, Quotation ke liye zaroori)' : '') + '</div>' + C.addrFields('', d, { defState: (C.company().state || 'Uttar Pradesh') }) +
        '<div class="fg">' + (assign ? C.f('Kiske paas rahe', '<select class="inp" name="assigned_to">' + C.userOpts(rec.assigned_to, '— Main / Owner —') + '</select>') : '') + C.f('Opening balance (₹ lena hai)', C.inp('opening', d.opening, 'inputmode="decimal"')) +
        C.f('Note', C.ta('note', d.note, 'rows="2"'), 'full') + '</div></form>';
      var m = C.modal({ title: opt.title || (isNew ? 'Conversation — naya customer' + (d.source ? ' (' + d.source + ')' : '') : 'Conversation — customer ki details'), body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' ' + (opt.okLabel || 'Save') + '</button>', onClose: function () { res(null); } });
      C.addrBind(m.el);
      var pf = $('#pf', m.el);
      function sync() {
        var t = pf.type.value, isC = t !== 'supplier', k = pf.cust_kind.value, sg = pf.segment.value;
        $$('[data-show]', pf).forEach(function (b) { var w = b.getAttribute('data-show'); b.hidden = !(w === 'cust' ? isC : w === 'b2b' ? (!isC || sg === 'b2b') : (isC && k === w)); });
      }
      ['type', 'cust_kind', 'segment'].forEach(function (n) { pf[n].addEventListener('change', sync); }); sync();
      $('[data-ok]', m.el).onclick = async function () {
        var f = pf, o = C.form(f); if (!C.need(f, ['name'])) return;
        Object.assign(o, C.addrRead(o, ''));
        var mob = String(o.mobile || '').trim(), em = String(o.email || '').trim(), sup = o.type === 'supplier';
        if (!mob || !C.validMob(mob)) { f.mobile.classList.add('bad'); f.mobile.focus(); return C.toast('Sahi 10 ank ka mobile number likhna zaroori hai', true); }
        if (em && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) { f.email.classList.add('bad'); return C.toast('Sahi email likhein ya khali chhodein', true); }
        if (isNew && !sup) {
          var must = ['source', 'cust_kind', 'segment', 'city', 'address'];
          if (o.cust_kind === 'project') must.push('project_type', 'kw'); else if (o.cust_kind === 'product') must.push('interest'); else if (o.cust_kind === 'service') must.push('service_type');
          if (o.segment === 'b2b') must.push('company');
          if (!C.need(f, must.filter(function (n) { return f[n]; }))) return;
          if (!/^[0-9]{6}$/.test(String(o.pincode || '').replace(/\D/g, ''))) { f.pincode.classList.add('bad'); f.pincode.focus(); return C.toast('Pincode 6 ank ka likhein', true); }
          if (o.cust_kind === 'project' && !(parseFloat(o.kw) > 0)) { f.kw.classList.add('bad'); return C.toast('kW likhein (jaise 3)', true); }
        }
        if (isNew && !sup && !opt.onSubmit) { /* Round 37: same mobile = same customer, kabhi dusra record nahi */
          var d10 = mob.replace(/\D/g, '').slice(-10), dup = null;
          try { dup = (await C.list('party', { limit: 3000 })).filter(function (x) { return String(x.mobile || '').replace(/\D/g, '').slice(-10) === d10; })[0]; } catch (e) {}
          if (dup) { if (await C.confirm('Ye mobile pehle se hai: ' + dup.title + '. Usi customer ko chunein? (naya nahi banega)', 'Haan, wahi chunein')) { m.el.remove(); document.documentElement.style.overflow = ''; return res(dup); } return; }
        }
        var extra = {}; if (assign) { extra.assigned_to = o.assigned_to || null; delete o.assigned_to; }
        o.gstin = String(o.gstin || '').toUpperCase();
        if (sup) { delete o.cust_kind; delete o.segment; }
        else { if (o.cust_kind !== 'project') { delete o.project_type; if (o.cust_kind !== 'product' && o.cust_kind !== 'service') delete o.interest; } if (o.cust_kind !== 'service') delete o.service_type; }
        try {
          if (opt.onSubmit) { var rr = await opt.onSubmit(Object.assign({}, rec.data || {}, o), extra); if (rr === false) return; m.el.remove(); document.documentElement.style.overflow = ''; return res(rr || true); }
          var r = await C.save('party', rec.id, Object.assign({}, rec.data || {}, o), extra); m.el.remove(); document.documentElement.style.overflow = ''; res(r);
        } catch (e) {}
      };
    });
  }

  /* ------------------------------------------------ Round 38: customer ki details SIRF Conversation (customer form) me bharti hain.
     Baaki har form me ye card dikhta hai — wahi details, padhne ke liye; "Badlein" usi ek form ko kholta hai. Koi doosra box nahi. */
  C.detailsMissing = function (p) {
    var d = (p && p.data) || {}, m = []; if (!p || (d.type || 'customer') === 'supplier') return m;
    if (!String(d.address || '').trim()) m.push('Pata'); if (!String(d.city || '').trim()) m.push('Shahar'); if (!/^[0-9]{6}$/.test(String(d.pincode || ''))) m.push('Pincode');
    if (d.cust_kind === 'project' && !(parseFloat(d.kw) > 0)) m.push('kW');
    return m;
  };
  C.custCardHtml = function (p, opt) {
    opt = opt || {}; var d = p.data || {}, miss = C.detailsMissing(p), adr = C.addrText(d) || d.city || '';
    var need = [d.cust_kind === 'project' ? (d.project_type || 'Project') + (parseFloat(d.kw) > 0 ? ' · ' + d.kw + ' kW' : '') : d.cust_kind === 'product' ? 'Product' + (d.interest ? ' · ' + d.interest : '') : d.cust_kind === 'service' ? 'Service' + (d.service_type ? ' · ' + d.service_type : '') : ''].filter(Boolean)[0] || '';
    return '<div class="ccard" data-ccard="' + p.id + '" style="border:1px solid var(--line,#dde3ea);border-radius:12px;padding:10px 12px;background:var(--soft,#f6f8fa)">' +
      '<div style="min-width:0"><b style="font-size:15px">' + esc(p.title) + '</b>' + (d.cust_id ? ' <span class="xs mute" style="white-space:nowrap">' + esc(d.cust_id) + '</span>' : '') + '</div>' +
      '<div class="sm" style="display:flex;flex-wrap:wrap;gap:4px 14px;margin-top:4px;align-items:center"><span style="white-space:nowrap">' + C.ic('phone') + ' ' + esc(p.mobile || '—') + '</span>' + (need ? '<span>' + esc(need) + '</span>' : '') + '</div>' +
      (adr ? '<div class="sm" style="white-space:pre-line;margin-top:4px">' + C.ic('home') + ' ' + esc(adr) + '</div>' : '') +
      ((opt.noEdit || !C.can('customers.edit')) && !opt.pick ? '' : '<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:8px">' + (opt.noEdit || !C.can('customers.edit') ? '' : '<button type="button" class="btn btn-o btn-sm" data-cc-edit>' + C.ic('edit') + ' Badlein</button>') + (opt.pick ? '<button type="button" class="btn btn-g btn-sm" data-cc-pick>' + C.ic('users') + ' Doosra customer</button>' : '') + '</div>') +
      (miss.length ? '<div class="note o" style="margin:8px 0 0">Details adhuri: <b>' + esc(miss.join(', ')) + '</b> — "Badlein" se bharein (sirf ek jagah, har form me apne aap aa jayegi).</div>' : '') + '</div>';
  };
  /* box me card (ya "Customer chunein"); onChange(party) har badlav par */
  C.custCardMount = function (box, party, opt) {
    opt = opt || {}; var ctl = { party: party || null };
    function draw() {
      box.innerHTML = ctl.party ? C.custCardHtml(ctl.party, opt) : '<button type="button" class="btn btn-o" data-cc-pick style="justify-content:flex-start;width:100%">' + C.ic('users') + ' Customer chunein *</button><div class="xs mute" style="margin-top:4px">Naya customer ho to list me "Naya" dabayein — details ek hi baar bharengi.</div>';
    }
    box.addEventListener('click', async function (e) {
      if (e.target.closest('[data-cc-edit]')) { var r = await C.partyForm(ctl.party); if (r && r.id) { try { ctl.party = await C.get(r.id); } catch (x) { ctl.party = r; } draw(); opt.onChange && opt.onChange(ctl.party); } return; }
      if (e.target.closest('[data-cc-pick]')) { var p = await C.partyPick({ title: opt.pickTitle || 'Customer chunein' }); if (p) { ctl.party = p; draw(); opt.onChange && opt.onChange(p); } }
    });
    draw(); return ctl;
  };

  /* ------------------------------------------------ pick a customer (search + quick add) */
  C.partyPick = function (opt) {
    opt = opt || {};
    return new Promise(async function (res) {
      var m = C.modal({ title: opt.title || 'Customer chunein', body: '<div class="row" style="margin-bottom:10px"><input class="inp" id="pq" placeholder="Naam / mobile / shahar khojein" type="search">' + (C.can('customers.create') ? '<button class="btn btn-p" data-new>' + C.ic('plus') + ' Naya</button>' : '') + '</div><div id="pl" class="list" style="max-height:55vh;overflow:auto">' + C.loading() + '</div>', foot: false, onClose: function () { res(null); } });
      var all = [];
      function draw() {
        var q = $('#pq', m.el).value.toLowerCase().trim(), list = all.filter(function (p) { return (!opt.type || (p.data.type || 'customer') === opt.type || p.data.type === 'both') && (!q || (p.title + ' ' + (p.mobile || '') + ' ' + (p.data.city || '') + ' ' + (p.data.company || '')).toLowerCase().indexOf(q) >= 0); }).slice(0, 200);
        $('#pl', m.el).innerHTML = list.length ? list.map(function (p) { return '<button type="button" class="li click" style="width:100%;text-align:left" data-id="' + p.id + '"><span class="av">' + esc(C.initials(p.title)) + '</span><span class="grow"><span class="t">' + esc(p.title) + '</span><span class="m"><span>' + esc(p.mobile || '') + '</span>' + (p.data.city ? '<span>' + esc(p.data.city) + '</span>' : '') + '</span></span>' + C.ic('right') + '</button>'; }).join('') : C.empty('users', 'Koi customer nahi mila', C.can('customers.create') ? '"Naya" dabakar jodein' : '');
      }
      try { all = await C.list('party', { limit: 3000 }); } catch (e) { C.toast(e.message, true); }
      draw(); $('#pq', m.el).addEventListener('input', draw);
      $('#pl', m.el).addEventListener('click', function (e) { var b = e.target.closest('[data-id]'); if (!b) return; var p = all.find(function (x) { return String(x.id) === b.getAttribute('data-id'); }); m.el.remove(); document.documentElement.style.overflow = ''; res(p); });
      var nb = $('[data-new]', m.el); if (nb) nb.onclick = async function () { var q = $('#pq', m.el).value.trim(), pre = /^[\d\s+]{6,}$/.test(q) ? { mobile: q } : { name: q }; var p = await C.partyForm(null, { prefill: Object.assign(pre, opt.prefill || {}) }); if (p) { m.el.remove(); document.documentElement.style.overflow = ''; res(p); } };
    });
  };

  /* ------------------------------------------------ reminder (task) form */
  C.reminderForm = function (rec, pre) {
    rec = rec || { data: {} }; pre = pre || {}; var d = Object.assign({ type: 'call' }, pre, rec.data || {}), isNew = !rec.id;
    return new Promise(function (res) {
      var assign = C.can('reminders.assign') && (C.cache.users || []).length;
      var body = '<form class="stack" id="rf"><div class="fg">' + C.f('Kaam ka prakar', '<select class="inp" name="type">' + C.rtypeOpts(d.type) + '</select>') + C.f('Kya karna hai *', C.inp('title', rec.title || d.title || '', 'maxlength="160" placeholder="Jaise: Sharma ji ko call — quotation follow-up"')) +
        C.f('Tareekh *', C.inp('due_at', rec.due_at || d.due_at || C.today(), 'type="date"')) + C.f('Samay', C.inp('time', d.time, 'type="time"')) +
        C.f('Mobile (call / WhatsApp ke liye)', C.inp('mobile', d.mobile || rec.mobile, 'inputmode="tel"')) + C.f('Amount (agar payment ho)', C.inp('amount', d.amount, 'inputmode="decimal"')) +
        (assign ? C.f('Kisko dena hai', '<select class="inp" name="assigned_to">' + C.userOpts(rec.assigned_to || pre.assigned_to || (C.me.id || ''), C.me.id === 0 ? 'Admin (khud)' : null) + '</select>', 'full') : '') +
        C.f('Repeat', C.sel('repeat', [['', 'Ek baar'], ['weekly', 'Har hafte'], ['monthly', 'Har mahine'], ['quarterly', 'Har 3 mahine'], ['yearly', 'Har saal']], d.repeat)) + C.f('Customer', '<input type="hidden" name="party_id" value="' + esc(rec.party_id || pre.party_id || '') + '"><button type="button" class="btn btn-o" data-pp style="justify-content:flex-start">' + C.ic('users') + '<span class="ellip">' + esc(rec.party_name || pre.party_name || 'Customer jodein (optional)') + '</span></button>') +
        C.f('Note', C.ta('note', d.note, 'rows="2"'), 'full') + '</div></form>';
      var m = C.modal({ title: isNew ? 'Naya kaam / reminder' : 'Kaam badlein', body: body, foot: (isNew ? '' : '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + '</button>') + '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      var f = $('#rf', m.el);
      $('[data-pp]', m.el).onclick = async function () { var p = await C.partyPick(); if (!p) return; f.party_id.value = p.id; $('[data-pp] span', m.el).textContent = p.title; if (!f.mobile.value) f.mobile.value = p.mobile || ''; if (!f.title.value) f.title.value = (C.RTYPE[f.type.value] || [''])[0] + ' — ' + p.title; };
      var del = $('[data-del]', m.el); if (del) del.onclick = async function () { if (await C.delWithReason(rec, 'Ye kaam')) { m.el.remove(); document.documentElement.style.overflow = ''; res({ deleted: true }); } };
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (!C.need(f, ['title', 'due_at'])) return;
        var extra = { due_at: o.due_at, party_id: o.party_id || null }; if (assign) extra.assigned_to = o.assigned_to || null; else if (isNew) extra.assigned_to = C.me.id;
        var data = Object.assign({}, rec.data || {}, { type: o.type, title: o.title, time: o.time, mobile: o.mobile, amount: o.amount, repeat: o.repeat, note: o.note });
        try { var r = await C.save('reminder', rec.id, data, extra); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  };
  /* mark reminder done (and create the next one when it repeats) */
  C.reminderDone = async function (r) { C.busy(true); try { return await reminderDone(r); } finally { C.busy(false); } };
  async function reminderDone(r) {
    var rec = r.data ? r : await C.get(r.id);
    try { await C.setStatus(rec.id, 'done', {}, 'Ho gaya ✔'); } catch (e) { return; }
    var rp = (rec.data || {}).repeat; if (!rp) return;
    var d = C.pd(rec.due_at) || new Date(), t0 = C.today(), step = function () { if (rp === 'weekly') d.setDate(d.getDate() + 7); else if (rp === 'monthly') d.setMonth(d.getMonth() + 1); else if (rp === 'quarterly') d.setMonth(d.getMonth() + 3); else d.setFullYear(d.getFullYear() + 1); };
    step(); var g = 0; while (C.iso(d) <= t0 && g++ < 600) step();
    var data = Object.assign({}, rec.data); delete data.done_at;
    try { await C.call('crm_save', { kind: 'reminder', data: data, due_at: C.iso(d), assigned_to: rec.assigned_to, party_id: rec.party_id }); C.toast('Agla reminder ' + C.fd(C.iso(d)) + ' ko lag gaya'); } catch (e) { C.toast(e.message, true); }
  }
  C.snooze = function (id, days) { return C.run('crm_get', { id: id }).then(function (r) { return C.call('crm_save', { kind: r.kind, id: r.id, data: r.kind === 'lead' ? Object.assign({}, r.data, { followup: C.addDays(C.today(), days) }) : r.data, due_at: C.addDays(C.today(), days), party_id: r.party_id, assigned_to: r.assigned_to }); }).then(function () { C.toast('Aage badha diya → ' + C.fd(C.addDays(C.today(), days))); }); };

  /* ------------------------------------------------ report buttons: Download + Download & Share to Accountant */
  C.accountants = function () { var s = C.cache.settings || {}; return (s.accountants || []).filter(function (a) { return a && (a.mobile || a.email); }); };
  /* Round 47: ek hi "Download & Share" dropdown — har jagah same. items: [[icon, label, 'data-act="x" data-id="1"'], ...]; click handlers wahi purane (data-act / data-rep) rehte hain. */
  C.dlMenu = function (items, o) {
    o = o || {};
    return '<span class="dlm' + (o.up ? ' up' : '') + '"><button type="button" class="btn ' + (o.cls || 'btn-o') + (o.sm ? ' btn-sm' : '') + '" data-dlm aria-haspopup="true" aria-expanded="false">' + C.ic(o.icon || 'download') + '<span class="dlm-t"> ' + esc(o.label || 'Download & Share') + '</span> ▾</button><span class="dlm-pop" hidden role="menu">' +
      items.map(function (i) { return '<button type="button" role="menuitem" class="dlm-i" ' + (i[2] || '') + '>' + C.ic(i[0]) + ' ' + esc(i[1]) + '</button>'; }).join('') + '</span></span>';
  };
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-dlm]'), pops = document.querySelectorAll('.dlm-pop:not([hidden])');
    for (var i = 0; i < pops.length; i++) if (!b || pops[i] !== b.nextElementSibling) pops[i].hidden = true;
    if (b) { var p = b.nextElementSibling; p.hidden = !p.hidden; b.setAttribute('aria-expanded', String(!p.hidden)); if (!p.hidden) { p.style.left = ''; p.style.right = '0'; var r = p.getBoundingClientRect(); if (r.left < 8) { p.style.left = '0'; p.style.right = 'auto'; } } }
    else if (e.target.closest('.dlm-i')) { for (var j = 0; j < pops.length; j++) pops[j].hidden = true; }
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') document.querySelectorAll('.dlm-pop:not([hidden])').forEach(function (p) { p.hidden = true; }); });
  C.reportBtns = function (name, build) {
    var id = 'rb' + Math.random().toString(36).slice(2, 8);
    setTimeout(function () {
      var el = document.getElementById(id); if (!el) return;
      el.addEventListener('click', async function (e) {
        var b = e.target.closest('[data-rep]'); if (!b) return;
        var x = await build(); if (!x || !x.rows) return;
        if (!window.XLSXLite) return C.toast('Excel tool load nahi hua', true);
        var fx = await C.dlFilter(name, x, b.getAttribute('data-rep')); if (!fx) return; x = Object.assign({}, x, fx);
        var blob = window.XLSXLite.write([{ name: name.slice(0, 30), rows: [x.head].concat(x.rows), widths: x.head.map(function () { return 18; }) }]), fname = name.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + C.today() + '.xlsx';
        if (b.getAttribute('data-rep') === 'dl') return C.download(blob, fname);
        C.shareAccountant(blob, fname, (x.text || name) + ' — ' + (C.company().name || ''));
      });
    }, 0);
    return '<span class="row wrap" id="' + id + '">' + C.dlMenu([['download', 'Excel Download', 'data-rep="dl"'], ['share', 'Accountant ko Share', 'data-rep="acc"']], { sm: true }) + '</span>';
  };
  C.shareAccountant = function (blob, fname, text) {
    var acc = C.accountants();
    if (!acc.length) { C.download(blob, fname); return C.toast(C.can('settings.manage') ? 'Settings → Accountant me CA / accountant ka number jodein' : 'Accountant ka number Settings me nahi hai — Admin se jodwayein', true); }
    var m = C.modal({ title: 'Accountant ko bhejein', size: 'sm', body: '<p class="mute sm" style="margin-bottom:10px">File download hogi aur WhatsApp / Email khulega — file attach karke bhej dein.</p><div class="list">' + acc.map(function (a, i) {
      return '<div class="li"><span class="av">' + esc(C.initials(a.name)) + '</span><span class="grow"><span class="t">' + esc(a.name || 'Accountant') + '</span><span class="m">' + esc([a.mobile, a.email].filter(Boolean).join(' · ')) + '</span></span><span class="acts">' + (a.mobile ? '<button class="btn btn-wa btn-sm" data-wa="' + i + '">' + C.ic('wa') + '</button>' : '') + (a.email ? '<button class="btn btn-o btn-sm" data-em="' + i + '" style="display:inline-flex">' + C.ic('mail') + '</button>' : '') + '</span></div>';
    }).join('') + '</div>' });
    m.el.addEventListener('click', function (e) {
      var w = e.target.closest('[data-wa]'), em = e.target.closest('[data-em]');
      if (w) { var a = acc[+w.getAttribute('data-wa')]; m.close(); C.share(blob, fname, text, a.mobile); }
      if (em) { var b = acc[+em.getAttribute('data-em')]; m.close(); C.download(blob, fname); location.href = 'mailto:' + encodeURIComponent(b.email) + '?subject=' + encodeURIComponent(text) + '&body=' + encodeURIComponent('Namaste,\n\n' + text + ' attach hai (' + fname + ').\n\nDhanyavaad'); }
    });
  };

  /* ------------------------------------------------ small widgets */
  C.callBtns = function (mobile, text) { if (!mobile || /\*/.test(mobile)) return ''; return '<a class="btn btn-o btn-icon btn-sm" href="' + C.tel(mobile) + '" title="Call" aria-label="Call">' + C.ic('phone') + '</a><a class="btn btn-wa btn-icon btn-sm" href="' + C.wa(mobile, text || '') + '" target="_blank" rel="noopener" title="WhatsApp" aria-label="WhatsApp">' + C.ic('wa') + '</a>'; };
  C.chips = function (list, sel, attr) { return '<div class="chips">' + list.map(function (x) { return '<button type="button" data-' + attr + '="' + esc(x[0]) + '" class="' + (String(sel) === String(x[0]) ? 'on' : '') + '">' + esc(x[1]) + (x[2] != null ? '<span class="n">' + x[2] + '</span>' : '') + '</button>'; }).join('') + '</div>'; };
  C.userFilter = function (sel, label) { if (!(C.cache.users || []).length) return ''; return '<select class="inp" data-user style="width:auto;max-width:220px">' + C.userOpts(sel, label || 'Sabhi users') + '<option value="0"' + (String(sel) === '0' ? ' selected' : '') + '>Company / Admin</option></select>'; };
  C.qs = function (o) { var a = []; for (var k in o) if (o[k] != null && o[k] !== '') a.push(encodeURIComponent(k) + '=' + encodeURIComponent(o[k])); return a.length ? '?' + a.join('&') : ''; };
  C.setQuery = function (patch) { var r = C.parse(), q = Object.assign({}, r.query, patch); history.replaceState(null, '', '#/' + [r.name].concat(r.params).join('/') + C.qs(q)); };
  C.openFile = async function (docId, mode) {
    var f = await C.run('crm_file_get', { id: docId }), blob = C.fromB64(f.b64, f.mime);
    if (mode === 'share') return window.SPSHARE ? SPSHARE.open({ blob: blob, name: f.name, title: f.name, subtitle: (f.mime || 'File') + (blob.size ? ' · ' + Math.max(1, Math.round(blob.size / 1024)) + ' KB' : ''), kind: 'doc', ref: 'doc:' + docId }) : C.share(blob, f.name, f.name);
    if (mode === 'download') return C.download(blob, f.name);
    var u = URL.createObjectURL(blob), w = window.open(u, '_blank'); if (!w) C.download(blob, f.name); setTimeout(function () { URL.revokeObjectURL(u); }, 60000);
  };
  /* opts: {max, q, target} — photo ka size target (default: document photo 1600px / ~450 KB). Blueprint / plan jaisi photo ke liye bada max do. */
  C.uploadFiles = async function (files, extra, opts) {
    opts = opts || {};
    var ok = 0;
    for (var i = 0; i < files.length; i++) {
      var f = files[i];
      try {
        C.busy(true); if (/^image\//.test(f.type)) f = await C.compress(f, opts.max || 1600, opts.q || 0.8, opts.target || 450 * 1024);
        if (f.size > 3 * 1024 * 1024) { C.toast(files[i].name + ': 3 MB se badi file — chhoti karke dalein', true); continue; }
        await C.call('crm_file_put', Object.assign({ name: files[i].name.replace(/\.(png|webp|jpeg)$/i, '.jpg').replace(/\.jpg\.jpg$/, '.jpg'), mime: f.type || 'application/octet-stream', b64: await C.toB64(f) }, extra || {})); ok++;
      } catch (e) { C.toast(files[i].name + ': ' + e.message, true); } finally { C.busy(false); }
    }
    if (ok) C.toast(ok + ' file upload ho gayi ✔'); return ok;
  };
  C.fsize = function (n) { n = num(n); return n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB'; };
  C.mimeIcon = function (m) { return /image/.test(m || '') ? 'image' : /pdf/.test(m || '') ? 'quote' : /sheet|excel|csv/.test(m || '') ? 'grid' : 'folder'; };
  C.kpi = function (label, val, sub, cls, href, icon) { return '<' + (href ? 'a href="' + href + '"' : 'div') + ' class="kpi ' + (cls || '') + '"><span>' + (icon ? C.ic(icon) : '') + esc(label) + '</span><b>' + val + '</b>' + (sub ? '<small>' + sub + '</small>' : '') + '</' + (href ? 'a' : 'div') + '>'; };
  document.addEventListener('click', function (e) { var r = e.target.closest('[data-href]'); if (!r || e.target.closest('a,button,input,select,textarea,label')) return; location.hash = r.getAttribute('data-href'); });
  C.sum = function (list, f) { return list.reduce(function (a, x) { return a + num(typeof f === 'function' ? f(x) : x[f]); }, 0); };

  /* ------------------------------------------------ address: Country → State → District (+ Other / khud likhein) */
  var OTHER = '__other';
  function geo() { return window.SP_GEO || { countries: ['India', 'Other'], IN: {} }; }
  function stateList() { return Object.keys(geo().IN || {}); }
  C.addrFields = function (pfx, d, opt) {
    d = d || {}; opt = opt || {}; pfx = pfx || '';
    var G = geo(), country = d[pfx + 'country'] || d.country_ || 'India', inIndia = country === 'India', st = d[pfx + 'state'] || (inIndia && !d[pfx + 'state'] && opt.defState ? opt.defState : ''), stKnown = inIndia && stateList().indexOf(st) >= 0;
    var dist = d[pfx + 'district'] || '', dists = stKnown ? (G.IN[st] || []) : [], dKnown = dists.indexOf(dist) >= 0;
    var cOpts = G.countries.indexOf(country) >= 0 ? G.countries : G.countries.concat([country]);
    return '<div class="fg addr" data-addr="' + pfx + '">' +
      C.f('Country', '<select class="inp" name="' + pfx + 'country" data-ac="country">' + C.opts(cOpts, country) + '</select>') +
      C.f('State', '<select class="inp" name="' + pfx + 'state" data-ac="state"' + (inIndia ? '' : ' hidden') + '>' + C.opts(stateList().map(function (x) { return [x, x]; }).concat([[OTHER, 'Other (khud likhein)']]), stKnown ? st : (st ? OTHER : ''), '— State chunein —') + '</select><input class="inp" name="' + pfx + 'state_x" data-ac="state_x" placeholder="State likhein" value="' + esc(stKnown ? '' : st) + '"' + (inIndia && (stKnown || !st) ? ' hidden' : '') + '>') +
      C.f('District', '<select class="inp" name="' + pfx + 'district" data-ac="district"' + (stKnown ? '' : ' hidden') + '>' + C.opts(dists.map(function (x) { return [x, x]; }).concat([[OTHER, 'Other (khud likhein)']]), dKnown ? dist : (dist ? OTHER : ''), '— District chunein —') + '</select><input class="inp" name="' + pfx + 'district_x" data-ac="district_x" placeholder="District likhein" value="' + esc(dKnown ? '' : dist) + '"' + (stKnown && (dKnown || !dist) ? ' hidden' : '') + '>') +
      C.f('Shahar / Gaon', C.inp(pfx + 'city', d[pfx + 'city'])) + C.f('Pincode', C.inp(pfx + 'pincode', d[pfx + 'pincode'], 'inputmode="numeric" maxlength="6"')) +
      C.f('Poora pata <span class="o">(makaan / gali / mohalla)</span>', C.ta(pfx + 'address', d[pfx + 'address'], 'rows="2"'), 'full') + '</div>';
  };
  C.addrBind = function (root) {
    root.addEventListener('change', function (e) {
      var t = e.target, k = t.getAttribute && t.getAttribute('data-ac'); if (!k) return;
      var box = t.closest('[data-addr]'), q = function (n) { return box.querySelector('[data-ac="' + n + '"]'); };
      if (k === 'country') {
        var ind = t.value === 'India'; q('state').hidden = !ind; q('state_x').hidden = ind; if (!ind) { q('state').value = ''; q('district').hidden = true; q('district').value = ''; q('district_x').hidden = false; } else { q('state_x').hidden = true; q('district_x').hidden = true; }
      } else if (k === 'state') {
        var st = t.value, list = (geo().IN || {})[st] || [], ds = q('district');
        q('state_x').hidden = st !== OTHER; if (st === OTHER) setTimeout(function () { q('state_x').focus(); }, 0);
        ds.innerHTML = C.opts(list.map(function (x) { return [x, x]; }).concat([[OTHER, 'Other (khud likhein)']]), '', '— District chunein —');
        ds.hidden = !list.length; q('district_x').hidden = !!list.length; q('district_x').value = '';
      } else if (k === 'district') { q('district_x').hidden = t.value !== OTHER; if (t.value === OTHER) setTimeout(function () { q('district_x').focus(); }, 0); }
    });
  };
  /* form values (C.form) → clean address object */
  C.addrRead = function (o, pfx) {
    pfx = pfx || ''; var country = o[pfx + 'country'] || 'India', st = o[pfx + 'state'], ds = o[pfx + 'district'];
    if (country !== 'India' || st === OTHER || !st) st = o[pfx + 'state_x'] || (st === OTHER ? '' : st || '');
    if (ds === OTHER || !ds || country !== 'India') ds = o[pfx + 'district_x'] || (ds === OTHER ? '' : ds || '');
    var a = { address: o[pfx + 'address'] || '', city: o[pfx + 'city'] || '', district: (ds || '').trim(), state: (st || '').trim(), country: country, pincode: o[pfx + 'pincode'] || '' };
    ['country', 'state', 'state_x', 'district', 'district_x', 'city', 'pincode', 'address'].forEach(function (k) { delete o[pfx + k]; });
    return a;
  };
  C.addrText = function (a) {
    if (!a) return ''; var l2 = [a.city, a.district && a.district !== a.city ? a.district : ''].filter(Boolean).join(', ');
    var l3 = [a.state, a.pincode].filter(Boolean).join(' - ');
    return [a.address, l2, l3, a.country && a.country !== 'India' ? a.country : ''].filter(function (x) { return String(x || '').trim(); }).join('\n');
  };

  /* ------------------------------------------------ templates (Admin Settings → Templates me badle ja sakte hain) */
  C.TPL_DEF = {
    delete: ['Not interested', 'Postpone solar plan', 'Next month', 'Next week', 'Duplicate entry', 'Galat entry', 'Budget nahi hai', 'Doosri company se lagwa liya'],
    note: ['Call kiya — phone nahi uthaya', 'Baat hui — quotation bhejni hai', 'Site visit fix hua', 'Next week call karna hai', 'Next month solar plan', 'Bijli bill ki photo maangi', 'Loan / finance ki jaankari chahiye', 'Subsidy ki jaankari di'],
    reject: ['Documents poore nahi', 'Galat jaankari', 'Duplicate entry', 'Customer ne mana kiya'],
    lost: ['Not interested', 'Budget nahi hai', 'Postpone solar plan', 'Doosri company se lagwa liya', 'Chhat / jagah nahi hai']
  };
  C.TPL_NAMES = { delete: 'Hatane (delete) ki wajah', note: 'Baat-cheet / follow-up note', reject: 'Reject ki wajah', lost: 'Lead haarne ki wajah' };
  C.tpl = function (k) { var t = ((C.cache.settings || {}).templates || {})[k]; return Array.isArray(t) && t.length ? t : (C.TPL_DEF[k] || []); };
  C.tplChips = function (k, target) { var list = C.tpl(k); if (!list.length) return ''; return '<div class="tplc" data-tplfor="' + esc(target) + '">' + list.map(function (x) { return '<button type="button" data-tpl="' + esc(x) + '">' + esc(x) + '</button>'; }).join('') + '</div>'; };
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('[data-tpl]'); if (!b) return;
    var box = b.closest('[data-tplfor]'), sel = box.getAttribute('data-tplfor'), root = box.closest('.md,.card,form,.mb') || document, inp = root.querySelector(sel) || document.querySelector(sel); if (!inp) return;
    var v = b.getAttribute('data-tpl'), cur = inp.value.trim();
    inp.value = !cur || cur === v ? v : (inp.tagName === 'TEXTAREA' ? cur + '\n' + v : cur + ' — ' + v);
    inp.dispatchEvent(new Event('input', { bubbles: true })); inp.classList.remove('bad'); try { inp.focus(); } catch (x) {}
  });

  /* ------------------------------------------------ inline customer list (1 click select) */
  C.partyInline = function (box, opt, onPick) {
    opt = opt || {}; var all = null;
    box.innerHTML = '<div class="row" style="margin-bottom:8px"><input class="inp" data-piq type="search" placeholder="Naam / mobile / shahar khojein">' + (C.can('customers.create') ? '<button type="button" class="btn btn-o" data-pinew>' + C.ic('plus') + ' Naya</button>' : '') + '</div><div class="list pil" style="max-height:300px;overflow:auto">' + C.loading() + '</div>';
    var q = box.querySelector('[data-piq]'), lst = box.querySelector('.pil');
    function draw() {
      var s = q.value.toLowerCase().trim(), list = (all || []).filter(function (p) { return (!opt.type || (p.data.type || 'customer') === opt.type || p.data.type === 'both') && (!s || (p.title + ' ' + (p.mobile || '') + ' ' + (p.data.city || '') + ' ' + (p.data.company || '')).toLowerCase().indexOf(s) >= 0); });
      lst.innerHTML = list.length ? list.slice(0, 300).map(function (p) { return '<button type="button" class="li click" style="width:100%;text-align:left" data-pi="' + p.id + '"><span class="av">' + esc(C.initials(p.title)) + '</span><span class="grow"><span class="t">' + esc(p.title) + '</span><span class="m"><span>' + esc(p.mobile || '') + '</span>' + (p.data.city ? '<span>' + esc(p.data.city) + '</span>' : '') + (p.owner_name ? '<span>' + esc(p.owner_name) + '</span>' : '') + '</span></span><span class="btn btn-p btn-sm">Chunein</span></button>'; }).join('') + (list.length > 300 ? '<p class="xs mute" style="padding:8px">Aur bhi hain — upar khojein</p>' : '') : C.empty('users', 'Koi customer nahi mila', C.can('customers.create') ? '"Naya" dabakar jodein' : '');
    }
    C.list('party', { limit: 3000 }).then(function (r) { all = r; draw(); }, function (e) { all = []; draw(); C.toast(e.message, true); });
    q.addEventListener('input', draw);
    box.addEventListener('click', async function (e) {
      var b = e.target.closest('[data-pi]'); if (b) { var p = all.find(function (x) { return String(x.id) === b.getAttribute('data-pi'); }); if (p) onPick(p); return; }
      if (e.target.closest('[data-pinew]')) { var v = q.value.trim(), pre = /^[\d\s+]{6,}$/.test(v) ? { mobile: v } : { name: v }; var np = await C.partyForm(null, { prefill: Object.assign(pre, opt.prefill || {}) }); if (np) onPick(np); }
    });
  };
})();
