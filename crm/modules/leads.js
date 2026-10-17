/* Leads — own leads + company-assigned leads, stages, follow-up, import / export, assign */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, num = C.num;
  var STAGES = ['new', 'contacted', 'visit', 'quote', 'won', 'lost'];

  C.leadForm = function (rec, pre) {
    rec = rec || { data: {} }; var d = Object.assign({}, pre || {}, rec.data || {}), isNew = !rec.id;
    return new Promise(function (res) {
      var assign = C.can('leads.assign') && (C.cache.users || []).length;
      var body = '<form id="lf" class="fg">' + C.f('Naam', C.inp('name', d.name || (isNew ? '' : rec.title), 'maxlength="120"')) + C.f('Mobile *', C.inp('mobile', d.mobile || rec.mobile, 'inputmode="tel" maxlength="16"')) +
        C.f('Shahar / Gaon', C.inp('city', d.city)) + C.f('Kahan se aayi', C.sel('source', (C.sourceList ? C.sourceList() : C.SOURCES), d.source, '— chunein —')) +
        C.f('Bijli ka bill (₹/mahina)', C.inp('bill', d.bill, 'inputmode="numeric"')) + C.f('Chahiye (kW)', C.inp('kw', d.kw, 'inputmode="decimal"')) +
        C.f('Agla follow-up', C.inp('followup', d.followup || (isNew ? C.addDays(C.today(), 1) : ''), 'type="date"')) + (isNew ? C.f('Stage', C.sel('stage', STAGES.map(function (s) { return [s, C.STAGE[s][0]]; }), 'new')) : '') +
        (assign ? C.f('Kisko dena hai', '<select class="inp" name="assigned_to">' + C.userOpts(rec.assigned_to, '— Khud ke paas —') + '</select>', 'full') : '') +
        C.f('Pata', C.ta('address', d.address, 'rows="2"'), 'full') + C.f('Note', C.ta('note', d.note, 'rows="2"'), 'full') + '</form>';
      var m = C.modal({ title: isNew ? 'Nayi lead' : 'Lead badlein', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      $('[data-ok]', m.el).onclick = async function () {
        var f = $('#lf', m.el), o = C.form(f); if (!C.validMob(o.mobile)) { f.mobile.classList.add('bad'); return C.toast('Sahi 10 ank ka mobile likhein', true); }
        if (isNew) o.intake = d.intake || 'manual'; var extra = {}; if (assign) { extra.assigned_to = o.assigned_to || null; } if (isNew && !assign) extra.assigned_to = C.me.id || null; if (isNew) extra.status = o.stage;
        delete o.assigned_to; delete o.stage;
        try { var r = await C.save('lead', rec.id, Object.assign({}, rec.data || {}, o), extra); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  };

  async function leadView(id, onChange) {
    var r = await C.run('crm_get', { id: id }), d = r.data || {}, log = d.log || [];
    var body = '<div class="row" style="margin-bottom:12px;flex-wrap:wrap">' + C.stagePill(r.status) + (d.company ? C.pill('Company lead', 'v') : '') + (d.source ? C.pill(d.source, 'g') : '') + '<span class="grow"></span>' + C.callBtns(r.mobile, 'Namaste ' + (d.name || '') + ', ' + (C.company().name || '') + ' se baat kar rahe hain.') + '</div>' +
      '<div class="fg" style="margin-bottom:12px"><div><div class="xs mute">Mobile</div><b>' + esc(r.mobile || '') + '</b></div><div><div class="xs mute">Shahar</div><b>' + esc(d.city || '—') + '</b></div><div><div class="xs mute">Bijli bill / kW</div><b>' + (d.bill ? '₹' + esc(d.bill) : '—') + ' / ' + esc(d.kw || '—') + '</b></div><div><div class="xs mute">Follow-up</div><b>' + esc(C.fd(r.due_at) || '—') + '</b></div><div><div class="xs mute">Kiske paas</div><b>' + esc(r.assigned_name || r.owner_name || '') + '</b></div><div><div class="xs mute">Aayi</div><b>' + esc(C.fd(r.created_at)) + '</b></div>' + (d.address ? '<div class="full"><div class="xs mute">Pata</div>' + esc(d.address) + '</div>' : '') + (d.note ? '<div class="full"><div class="xs mute">Note</div>' + esc(d.note) + '</div>' : '') + '</div>' +
      '<div class="sec-t">Stage badlein</div>' + C.chips(STAGES.map(function (s) { return [s, C.STAGE[s][0]]; }), r.status, 'st') +
      '<div class="sec-t">Baat-cheet likhein</div><div class="row"><input class="inp" id="lg" placeholder="Kya baat hui? (jaise: Sunday ko visit bulaya)"><input class="inp" type="date" id="lfd" value="' + esc(r.due_at || '') + '" style="width:auto" title="Agla follow-up"><button class="btn btn-p" data-log>' + C.ic('send') + '</button></div>' + C.tplChips('note', '#lg') +
      (log.length ? '<div class="list" style="margin-top:10px">' + log.slice().reverse().map(function (x) { return '<div class="li"><span class="grow"><span class="sm">' + esc(x.t) + '</span><span class="m"><span>' + esc(x.by || '') + '</span><span>' + esc(C.fdt(x.at)) + '</span></span></span></div>'; }).join('') + '</div>' : '');
    var canXfer = C.isAdmin() || r.owner_id === C.me.id || r.assigned_to === C.me.id;
    var foot = (C.can('leads.delete') || (r.owner_id === C.me.id && r.owner_id !== 0) ? '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + '</button>' : '') + '<button class="btn btn-o" data-edit>' + C.ic('edit') + ' Badlein</button>' + (!d.party_id && canXfer ? '<button class="btn btn-o" data-cust>' + C.ic('users') + ' Customer list me bhejein</button>' : d.party_id ? '<a class="btn btn-o" href="#/customer/' + d.party_id + '">' + C.ic('users') + ' Customer</a>' : '') + (C.can('quotes.create') ? '<button class="btn btn-p" data-quote>' + C.ic('quote') + ' Quotation</button>' : '');
    var m = C.modal({ title: r.title, body: body, foot: foot, size: 'wide', onClose: onChange });
    async function patch(st, p, msg) { try { await C.call('crm_save', { kind: 'lead', id: r.id, status: st || r.status, data: Object.assign({}, r.data, p || {}), party_id: r.party_id, assigned_to: r.assigned_to }); C.toast(msg || 'Update ho gaya ✔'); m.close(); leadView(id, onChange); } catch (e) { C.toast(e.message, true); } }
    m.el.addEventListener('click', async function (e) {
      var s = e.target.closest('[data-st]'); if (s) { var st = s.getAttribute('data-st'), why = ''; if (st === 'lost' && r.status !== 'lost') { why = await C.ask('Lead kyun haari?', 'Wajah chunein ya likhein', { tpl: 'lost', ok: 'Save' }); if (why == null) return; } var lg = log.concat([{ at: new Date().toISOString(), by: C.me.name, t: 'Stage → ' + C.STAGE[st][0] + (why ? ' — ' + why : '') }]); patch(st, st === 'lost' && why ? { log: lg, lost_reason: why } : { log: lg }); }
    });
    $('[data-log]', m.el).onclick = function () { var t = $('#lg', m.el).value.trim(), fu = $('#lfd', m.el).value; if (!t && fu === (r.due_at || '')) return C.toast('Kuch likhein', true); var lg = log.concat(t ? [{ at: new Date().toISOString(), by: C.me.name, t: t }] : []); patch(r.status === 'new' ? 'contacted' : r.status, { log: lg, followup: fu }, 'Likh liya ✔'); };
    $('[data-edit]', m.el).onclick = async function () { m.el.remove(); document.documentElement.style.overflow = ''; var x = await C.leadForm(r); leadView(id, onChange); };
    var del = $('[data-del]', m.el); if (del) del.onclick = async function () { if (await C.delWithReason(r, 'Lead "' + r.title + '"')) m.close(); };
    /* Lead → Customer list: only after a conversation remark; name, mobile, address and city are mandatory */
    async function transfer() {
      if (!(r.data.log || []).length) { C.toast('Pehle customer se baat karke "Baat-cheet" me remark likhein', true); return null; }
      return new Promise(function (res) {
        var body = '<form id="xf" class="fg"><div class="note g full">Baat-cheet ke remark lead me save hain. Neeche customer ki zaroori details bharein.</div>' + C.f('Naam *', C.inp('name', d.name && !/^Lead \d/.test(d.name) ? d.name : (/^Lead \d/.test(r.title) ? '' : r.title))) + C.f('Mobile *', C.inp('mobile', r.mobile, 'inputmode="tel" maxlength="16"')) +
          C.f('Pata *', C.ta('address', d.address, 'rows="2"'), 'full') + C.f('Shahar / Gaon *', C.inp('city', d.city)) + C.f('Pincode', C.inp('pincode', d.pincode, 'inputmode="numeric" maxlength="6"')) + C.f('Email', C.inp('email', d.email)) + C.f('Kahan se aaya', C.sel('source', (C.sourceList ? C.sourceList() : C.SOURCES), d.source, '— chunein —')) + '</form>';
        var x = C.modal({ title: 'Customer list me bhejein', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Customer banayein</button>', onClose: function () { res(null); } });
        $('[data-ok]', x.el).onclick = async function () {
          var f = $('#xf', x.el), o = C.form(f); if (!C.need(f, ['name', 'mobile', 'address', 'city'])) return; if (!C.validMob(o.mobile)) { f.mobile.classList.add('bad'); return C.toast('Sahi 10 ank ka mobile likhein', true); }
          try { var out = await C.run('crm_lead_transfer', { id: r.id, party: o }, 'Customer list me aa gaya ✔'); res(out.party_id); x.el.remove(); document.documentElement.style.overflow = ''; } catch (e) {}
        };
      });
    }
    var cu = $('[data-cust]', m.el); if (cu) cu.onclick = async function () { var pid = await transfer(); if (pid) { m.el.remove(); document.documentElement.style.overflow = ''; if (onChange) onChange(); C.go('#/customer/' + pid); } };
    var qb = $('[data-quote]', m.el); if (qb) qb.onclick = async function () {
      var pid = d.party_id;
      if (!pid) { var ex = await C.list('party', { q: r.mobile, limit: 5 }).catch(function () { return []; }); var hit = ex.find(function (x) { return x.mobile === r.mobile; }); if (hit) pid = hit.id; }
      if (!pid) { if (!canXfer) return C.toast('Pehle lead ka user ya Admin ise Customer list me bheje', true); pid = await transfer(); if (!pid) return; }
      if (r.status !== 'won') { try { await C.call('crm_save', { kind: 'lead', id: r.id, status: 'quote', data: Object.assign({}, r.data, { party_id: pid }), party_id: r.party_id, assigned_to: r.assigned_to }); } catch (e) {} }
      m.el.remove(); document.documentElement.style.overflow = ''; C.go('#/quote/new?party=' + pid);
    };
  }
  C.leadView = leadView;
  C.leadImport = function (preSrc) { return new Promise(function (res) { importDlg(function () { res(true); }, preSrc); }); };

  /* import from Excel / CSV / pasted text / phone contacts */
  function importDlg(done, preSrc) {
    var assign = C.can('leads.assign') && (C.cache.users || []).length;
    var body = '<div class="note g" style="margin-bottom:12px">Excel / CSV me columns: <b>Name, Mobile, City, Source, Note, Followup</b> (pehli line heading). Ya neeche seedha naam + number paste karein (har line me ek).</div>' +
      '<div class="stack"><input type="file" class="inp" id="lfile" accept=".xlsx,.csv,.txt">' + ('contacts' in navigator && 'ContactsManager' in window ? '<button class="btn btn-o" data-ct>' + C.ic('phone') + ' Phone ke contacts se chunein</button>' : '') +
      C.f('Ya paste karein', '<textarea class="inp" id="lpaste" rows="5" placeholder="Ramesh Kumar 9876543210&#10;9123456780, Suresh, Lucknow"></textarea>') +
      C.f('Source', C.sel('src', (C.sourceList ? C.sourceList() : C.SOURCES), preSrc || (assign ? '' : 'Import'), '— jo file me hai —', 'id="lsrc"')) +
      (assign ? C.f('Kiski list me jaye? (Company leads)', '<select class="inp" id="lto">' + C.userOpts('', '— Meri khud ki list —') + '</select><span class="hint">Kisi user ko chunne par leads sirf usi ID ko dikhengi (Company leads).</span>') : '') + '<p id="lprev" class="sm b"></p></div>';
    var m = C.modal({ title: 'Leads import', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('upload') + ' Import</button>' }), rows = [];
    function parseText(t) {
      return t.split(/\n/).map(function (line) { var mm = line.match(/(\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}/); if (!mm) return null; var mob = C.mob(mm[0]), rest = line.replace(mm[0], '').split(/[,\t;]/).map(function (x) { return x.trim(); }).filter(Boolean); return { mobile: mob, name: rest[0] || '', city: rest[1] || '' }; }).filter(Boolean);
    }
    function prev() { var p = parseText($('#lpaste', m.el).value); $('#lprev', m.el).textContent = (rows.length + p.length) + ' leads milin'; }
    $('#lpaste', m.el).addEventListener('input', prev);
    $('#lfile', m.el).onchange = async function () {
      var f = this.files[0]; if (!f) return;
      try {
        var data = /\.txt$/i.test(f.name) ? (await f.text()).split('\n').map(function (l) { return [l]; }) : await C.readSheet(f), head = (data[0] || []).map(function (x) { return String(x || '').toLowerCase().trim(); });
        var ix = function (re) { return head.findIndex(function (h) { return re.test(h); }); }, im = ix(/mob|phone|number|contact/), iname = ix(/name|naam/), ic = ix(/city|shahar|place|address/), is = ix(/source/), inote = ix(/note|remark/), ifu = ix(/follow/);
        if (im < 0) { rows = parseText(data.map(function (r) { return r.join(', '); }).join('\n')); }
        else rows = data.slice(1).map(function (r) { return { mobile: C.mob(r[im]), name: iname >= 0 ? String(r[iname] || '') : '', city: ic >= 0 ? String(r[ic] || '') : '', source: is >= 0 ? String(r[is] || '') : '', note: inote >= 0 ? String(r[inote] || '') : '', followup: ifu >= 0 ? C.excelDate(r[ifu]) : '' }; }).filter(function (x) { return x.mobile; });
        prev();
      } catch (e) { C.toast('File padh nahi paye — .xlsx ya .csv dalein', true); }
    };
    var ct = $('[data-ct]', m.el); if (ct) ct.onclick = async function () { try { var cs = await navigator.contacts.select(['name', 'tel'], { multiple: true }); cs.forEach(function (c) { (c.tel || []).slice(0, 1).forEach(function (t) { rows.push({ mobile: C.mob(t), name: (c.name || [])[0] || '' }); }); }); prev(); } catch (e) {} };
    $('[data-ok]', m.el).onclick = async function () {
      var all = rows.concat(parseText($('#lpaste', m.el).value)), src = $('#lsrc', m.el).value; if (!all.length) return C.toast('Koi lead nahi mili', true);
      if (src) all.forEach(function (x) { x.source = src; });
      var to = $('#lto', m.el) ? $('#lto', m.el).value : '';
      try { var r = await C.run('crm_lead_import', { rows: all.slice(0, 3000), assign_to: to || null }); m.close(); C.toast(r.added + ' leads jud gayin' + (r.skipped ? ', ' + r.skipped + ' chhodi (galat number / pehle se)' : '')); done(); } catch (e) {}
    };
  }

  C.mod('leads', {
    title: 'Leads',
    allowed: function () { return C.canAny('leads.create', 'leads.view_all'); },
    render: async function (el, params, q) {
      var st = q.st || 'open', scope = q.scope || '', uid = q.user || '', viewAll = C.can('leads.view_all');
      var opt = { limit: 3000 }; if (scope === 'mine' || !viewAll) opt.mine = true; if (uid) opt.user_id = uid;
      var all = await C.list('lead', opt);
      if (scope === 'company') all = all.filter(function (x) { return x.data.company; });
      var cnt = {}; all.forEach(function (x) { cnt[x.status] = (cnt[x.status] || 0) + 1; });
      var openN = all.filter(function (x) { return x.status !== 'won' && x.status !== 'lost'; }).length;
      var list = all.filter(function (x) { return st === 'all' ? true : st === 'open' ? x.status !== 'won' && x.status !== 'lost' : st === 'due' ? x.due_at && x.due_at <= C.today() && x.status !== 'won' && x.status !== 'lost' : x.status === st; });
      var dueN = all.filter(function (x) { return x.due_at && x.due_at <= C.today() && x.status !== 'won' && x.status !== 'lost'; }).length;
      var sel = {};
      var h = '<div class="ph"><div><h1>Leads</h1><p>Har lead ka follow-up time par — jeeti hui lead ko customer banayein.</p></div><div class="row">' +
        (C.can('leads.export') ? '<button class="btn btn-o" data-act="export">' + C.ic('download') + ' Excel</button>' : '') + (C.can('leads.import') ? '<button class="btn btn-o" data-act="import">' + C.ic('upload') + ' Import</button>' : '') +
        (C.can('leads.create') ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Nayi lead</button>' : '') + '</div></div>';
      h += '<div class="bar">' + C.chips([['open', 'Khuli', openN], ['due', 'Follow-up aaj', dueN]].concat(STAGES.map(function (s) { return [s, C.STAGE[s][0], cnt[s] || 0]; })).concat([['all', 'Sab', all.length]]), st, 'st') + '</div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Naam / mobile / shahar khojein">' +
        '<select class="inp" data-scope style="width:auto"><option value="">' + (viewAll ? 'Sabki leads' : 'Meri leads') + '</option><option value="mine"' + (scope === 'mine' ? ' selected' : '') + '>Sirf meri</option><option value="company"' + (scope === 'company' ? ' selected' : '') + '>Company se mili</option></select>' +
        (viewAll ? C.userFilter(uid, 'Sabhi users') : '') + '<span class="sp"></span>' +
        (C.can('leads.assign') ? '<button class="btn btn-o btn-sm" data-act="assign" disabled id="asgBtn">' + C.ic('send') + ' Chuni hui leads kisi ko dein</button>' : '') + '</div>';
      h += list.length ? '<div class="list" id="ll">' + list.map(function (r) {
        var od = r.due_at && r.due_at < C.today() && r.status !== 'won' && r.status !== 'lost';
        return '<div class="li click' + (od ? ' over' : '') + '" data-act="open" data-id="' + r.id + '">' + (C.can('leads.assign') ? '<input type="checkbox" data-sel="' + r.id + '" aria-label="Chunein">' : '') + '<span class="av ' + (C.STAGE[r.status] || ['', 'g'])[1] + '">' + esc(C.initials(r.title)) + '</span><span class="grow"><span class="t">' + esc(r.title) + ' ' + C.stagePill(r.status) + (r.data.company ? C.pill('Company', 'v') : '') + '</span><span class="m"><span>' + C.ic('phone') + esc(r.mobile || '') + '</span>' + (r.data.city ? '<span>' + esc(r.data.city) + '</span>' : '') + (r.due_at ? '<span>' + C.ic('clock') + esc(C.fd(r.due_at)) + '</span>' : '') + (viewAll ? '<span>' + C.ic('user') + esc(r.assigned_name || r.owner_name || '') + '</span>' : '') + (r.data.source ? '<span>' + esc(r.data.source) + '</span>' : '') + '</span></span><span class="acts">' + C.callBtns(r.mobile) + '</span></div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('lead', 'Koi lead nahi', C.can('leads.create') ? '"Nayi lead" ya "Import" se jodein' : '') + '</div>';
      el.innerHTML = h;
      var nav = function (p) { C.go('#/leads' + C.qs(Object.assign({ st: st !== 'open' ? st : '', scope: scope, user: uid }, p))); };
      el.addEventListener('click', function (e) { var c = e.target.closest('[data-st]'); if (c) nav({ st: c.getAttribute('data-st') === 'open' ? '' : c.getAttribute('data-st') }); });
      $('[data-scope]', el).onchange = function () { nav({ scope: this.value }); };
      var us = $('[data-user]', el); if (us) us.onchange = function () { nav({ user: this.value }); };
      var ll = $('#ll', el); if (ll) { C.filterList($('[data-q]', el), ll); ll.addEventListener('click', function (e) { if (e.target.closest('a,input')) e.stopPropagation(); }, true); ll.addEventListener('change', function (e) { var c = e.target.closest('[data-sel]'); if (!c) return; if (c.checked) sel[c.getAttribute('data-sel')] = 1; else delete sel[c.getAttribute('data-sel')]; var b = $('#asgBtn', el); if (b) { b.disabled = !Object.keys(sel).length; b.innerHTML = C.ic('send') + ' ' + Object.keys(sel).length + ' leads kisi ko dein'; } }); }
      if (q.open) setTimeout(function () { leadView(q.open, function () { C.setQuery({ open: '' }); C.render(); }); }, 30);
      C.bind(el, {
        open: function (id, a, e) { if (e.target.closest('a,input,button')) return; leadView(id, function () { C.render(); }); },
        add: function () { C.leadForm().then(function (r) { if (r) C.render(); }); },
        import: function () { importDlg(function () { C.render(); }); },
        export: function () { C.xl('Leads', ['Naam', 'Mobile', 'Shahar', 'Stage', 'Source', 'Follow-up', 'Bill', 'kW', 'Kiske paas', 'Company lead', 'Note', 'Bani'], list.map(function (r) { return [r.title, r.mobile, r.data.city || '', C.STAGE[r.status] ? C.STAGE[r.status][0] : r.status, r.data.source || '', C.fd(r.due_at), r.data.bill || '', r.data.kw || '', r.assigned_name || r.owner_name || '', r.data.company ? 'Haan' : '', r.data.note || '', C.fd(r.created_at)]; })); },
        assign: async function () {
          var ids = Object.keys(sel); if (!ids.length) return;
          var m = C.modal({ title: ids.length + ' leads kisko dein?', size: 'sm', body: '<select class="inp" id="ato">' + C.userOpts('', '— Company (kisi ko nahi) —') + '</select><p class="hint" style="margin-top:8px">Ye leads us user ki list me "Company lead" ban kar dikhengi.</p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Dein</button>' });
          $('[data-ok]', m.el).onclick = async function () { try { var r = await C.run('crm_assign', { kind: 'lead', ids: ids, user_id: $('#ato', m.el).value || null }); m.close(); C.toast(r.count + ' leads de di ✔'); C.render(); } catch (e) {} };
        }
      });
    }
  });
})();
