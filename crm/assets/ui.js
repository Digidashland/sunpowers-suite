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
  C.SOURCES = ['Walk-in', 'Reference', 'Website', 'Online Store', 'Facebook', 'Instagram', 'Google', 'WhatsApp', 'Camp / Event', 'Dealer', 'Influencer', 'Other'];

  /* links to company store / website (with partner referral code) */
  C.storeUrl = function () { var co = C.company(); return co.store_url || C.cfg.STORE_URL || ''; };
  C.siteUrl = function () { var co = C.company(); return co.website ? (/^https?:/.test(co.website) ? co.website : 'https://' + co.website) : (C.cfg.SITE_URL || ''); };
  C.refLink = function () { var u = C.storeUrl(); if (!u || !C.me || !C.me.ref_code) return u; return u + (u.indexOf('?') >= 0 ? '&' : '?') + 'ref=' + encodeURIComponent(C.me.ref_code); };
  C.copy = async function (t, msg) { try { await navigator.clipboard.writeText(t); C.toast(msg || 'Copy ho gaya ✔'); } catch (e) { C.ask('Copy karein', 'Neeche wala text copy karein', { value: t }); } };

  /* ------------------------------------------------ customer (party) form */
  C.partyForm = function (rec, opt) {
    opt = opt || {}; rec = rec || { data: {} }; var d = Object.assign({}, rec.data || {}), isNew = !rec.id;
    if (opt.prefill) Object.assign(d, opt.prefill);
    return new Promise(function (res) {
      var assign = C.can('customers.assign') && (C.cache.users || []).length;
      var body = '<form class="stack" id="pf"><div class="fg">' + C.f('Naam *', C.inp('name', d.name || rec.title, 'maxlength="120" required')) + C.f('Mobile *', C.inp('mobile', d.mobile || rec.mobile, 'inputmode="tel" maxlength="16"')) +
        C.f('Doosra mobile', C.inp('mobile2', d.mobile2, 'inputmode="tel" maxlength="16"')) + C.f('Email', C.inp('email', d.email, 'type="email"')) +
        C.f('Shahar / Gaon', C.inp('city', d.city)) + C.f('Pincode', C.inp('pincode', d.pincode, 'inputmode="numeric" maxlength="6"')) +
        C.f('Poora pata', C.ta('address', d.address, 'rows="2"'), 'full') + C.f('Company / Firm', C.inp('company', d.company)) + C.f('GSTIN', C.inp('gstin', d.gstin, 'maxlength="15" style="text-transform:uppercase"')) +
        C.f('Prakar', C.sel('type', C.PARTY_TYPES, d.type || 'customer')) + C.f('Kahan se aaya', C.sel('source', C.SOURCES, d.source, '— chunein —')) +
        C.f('Bijli ka bill (₹/mahina)', C.inp('bill', d.bill, 'inputmode="numeric"')) + C.f('Chahiye (kW)', C.inp('kw', d.kw, 'inputmode="decimal"')) +
        C.f('Opening balance (₹ lena hai)', C.inp('opening', d.opening, 'inputmode="decimal"')) + (assign ? C.f('Kiske paas rahe', '<select class="inp" name="assigned_to">' + C.userOpts(rec.assigned_to, '— Main / Owner —') + '</select>') : '') +
        C.f('Note', C.ta('note', d.note, 'rows="2"'), 'full') + '</div></form>';
      var m = C.modal({ title: isNew ? 'Naya customer' : 'Customer badlein', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      $('[data-ok]', m.el).onclick = async function () {
        var f = $('#pf', m.el), o = C.form(f); if (!C.need(f, ['name', 'mobile'])) return;
        if (!C.validMob(o.mobile)) { f.mobile.classList.add('bad'); return C.toast('Sahi 10 ank ka mobile likhein', true); }
        var extra = {}; if (assign) { extra.assigned_to = o.assigned_to || null; delete o.assigned_to; }
        o.gstin = o.gstin.toUpperCase();
        try { var r = await C.save('party', rec.id, Object.assign({}, rec.data || {}, o), extra); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
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
  C.reportBtns = function (name, build) {
    var id = 'rb' + Math.random().toString(36).slice(2, 8);
    setTimeout(function () {
      var el = document.getElementById(id); if (!el) return;
      el.addEventListener('click', async function (e) {
        var b = e.target.closest('[data-rep]'); if (!b) return;
        var x = await build(); if (!x || !x.rows) return;
        if (!window.XLSXLite) return C.toast('Excel tool load nahi hua', true);
        var blob = window.XLSXLite.write([{ name: name.slice(0, 30), rows: [x.head].concat(x.rows), widths: x.head.map(function () { return 18; }) }]), fname = name.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + C.today() + '.xlsx';
        if (b.getAttribute('data-rep') === 'dl') return C.download(blob, fname);
        C.shareAccountant(blob, fname, (x.text || name) + ' — ' + (C.company().name || ''));
      });
    }, 0);
    return '<span class="row wrap" id="' + id + '"><button class="btn btn-o btn-sm" data-rep="dl">' + C.ic('download') + ' Download</button><button class="btn btn-o btn-sm" data-rep="acc">' + C.ic('share') + ' Download &amp; Share to Accountant</button></span>';
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
    if (mode === 'share') return C.share(blob, f.name, f.name);
    if (mode === 'download') return C.download(blob, f.name);
    var u = URL.createObjectURL(blob), w = window.open(u, '_blank'); if (!w) C.download(blob, f.name); setTimeout(function () { URL.revokeObjectURL(u); }, 60000);
  };
  C.uploadFiles = async function (files, extra) {
    var ok = 0;
    for (var i = 0; i < files.length; i++) {
      var f = files[i];
      try {
        C.busy(true); if (/^image\//.test(f.type)) f = await C.compress(f, 1800, 0.82);
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
})();
