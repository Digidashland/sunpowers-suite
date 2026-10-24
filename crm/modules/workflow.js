/* Customer workflow (19 steps, flow differs per customer type) + Projects (live tracking).
   Rules live in MASTER-UPDATE.sql (Round 21); names / icons / menu links / step details live in flow.js — this file only draws and calls. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, F = C.FLOW;
  var IC = F.IC, COL = F.COL, LBL = F.NAMES;
  C.CTYPES = ['Residential', 'Commercial', 'Industrial', 'VFD', 'Items only', 'Service', 'AMC only', 'Site visit only'];

  C.dt = function (s) { if (!s) return ''; var d = new Date(s); return isNaN(d) ? '' : C.fdt(d); };
  C.ribbon = function (t, cls) { return '<span class="rib ' + (cls || '') + '">' + esc(t) + '</span>'; };
  function nm(s) { return s.name || LBL[s.n] || ('Step ' + s.n); }

  function fieldHtml(f, v) {
    var k = f[0], req = f[2], t = f[3] === 'date' ? 'date' : 'text';
    return '<div class="fld"><label class="l" for="wfi_' + k + '">' + esc(f[1]) + (req ? ' *' : '') + '</label><input class="inp" id="wfi_' + k + '" data-wfi="' + k + '" type="' + t + '" maxlength="200" value="' + esc(v || '') + '"></div>';
  }
  function stepModal(g, s, done) {
    var fields = F.FIELDS[s.n] || [], info = s.info || {}, lk = F.link(s.n, { party_id: g.party_id, quote_id: g.quote_id });
    var body = '<div class="row" style="margin-bottom:10px"><span class="wfc big" style="--c:' + (COL[s.n] || '#1e8e3e') + '">' + (IC[s.n] || '•') + '</span><div class="grow"><b>' + esc(nm(s)) + '</b><div class="xs mute">' + (s.done ? (s.skip ? 'Is customer ke liye lagu nahi' : 'Poora hua: ' + esc(C.dt(s.at))) : 'Abhi baaki') + '</div></div></div>';
    if (F.HELP[s.n]) body += '<div class="xs mute" style="margin-bottom:8px">' + esc(F.HELP[s.n]) + '</div>';
    var editable = !s.locked && s.can_edit && !s.done && g.quote_id;
    if (s.locked) body += '<div class="note">🔒 Is step ki details dekhne ki permission nahi hai — Admin se allow karwayein. Tareekh aur samay sabko dikhta hai.</div>';
    else {
      if (s.done && !s.skip) {
        body += '<div class="fg"><div><div class="xs mute">Kisne</div><b>' + esc(s.by || (s.auto ? 'Apne aap (system)' : '—')) + '</b></div></div>';
        var shown = fields.filter(function (f) { return info[f[0]]; });
        if (shown.length) body += '<div class="fg" style="margin-top:8px">' + shown.map(function (f) { return '<div><div class="xs mute">' + esc(f[1]) + '</div><b>' + esc(info[f[0]]) + '</b></div>'; }).join('') + '</div>';
        if (s.note) body += '<div class="note g" style="margin-top:8px;white-space:pre-line">' + esc(s.note) + '</div>';
      }
      if (editable) {
        body += '<div class="xs mute" style="margin-bottom:6px">Jaankari bharein, phir neeche "Ye step poora hua" dabayein — tabhi ✓ lagega.</div>';
        if (fields.length) body += '<div class="fg" style="margin-top:8px">' + fields.map(function (f) { return fieldHtml(f, info[f[0]]); }).join('') + '</div>';
        body += '<div class="fld" style="margin-top:10px"><label class="l" for="wfnote">Note (optional)</label><textarea class="inp" id="wfnote" rows="2" maxlength="500" placeholder="Koi aur baat…"></textarea></div>';
      } else if (!s.done && s.auto !== true && !g.quote_id && s.n !== 19 && s.n !== 1 && s.n !== 2) body += '<div class="note">Ye step quotation banne ke baad yahan tick hoga. Pehle quotation banayein.</div>';
      else if (!s.done && !s.can_edit && s.n !== 19) body += '<div class="note g">Ye step apne aap poora hota hai (' + esc(F.HELP[s.n] || '') + ')</div>';
    }
    var foot = '<button class="btn btn-o" data-close>Band</button>' + (lk ? '<a class="btn btn-o" data-lk href="' + esc(lk.href) + '">' + C.ic(lk.icon) + ' ' + esc(lk.label) + '</a>' : '') +
      (editable && s.can_skip ? '<button class="btn btn-o" data-skip>Lagu nahi</button>' : '') +
      (editable ? '<button class="btn btn-p" data-ok>' + C.ic('check') + ' Ye step poora hua</button>' : '') +
      (s.done && C.isAdmin() && !s.auto ? '<button class="btn btn-r" data-undo>Wapas karein</button>' : '');
    var m = C.modal({ title: nm(s), body: body, foot: foot, size: 'sm' });
    function collect() { var o = {}; $$('[data-wfi]', m.el).forEach(function (i) { if (i.value.trim()) o[i.getAttribute('data-wfi')] = i.value.trim(); }); return o; }
    var lkEl = $('[data-lk]', m.el); if (lkEl) lkEl.onclick = function () { m.close(); };
    var ok = $('[data-ok]', m.el); if (ok) ok.onclick = async function () {
      var miss = fields.filter(function (f) { return f[2] && !($('#wfi_' + f[0], m.el) || {}).value; }).map(function (f) { return f[1]; });
      if (miss.length) return C.toast('Ye bharna zaroori hai: ' + miss.join(', '), true);
      try { await C.run('crm_wf_set', { id: g.quote_id, step: s.n, done: true, note: ($('#wfnote', m.el) || {}).value || '', info: collect() }, nm(s) + ' ✔'); m.close(); done && done(); } catch (e) {}
    };
    var sk = $('[data-skip]', m.el); if (sk) sk.onclick = async function () { try { await C.run('crm_wf_set', { id: g.quote_id, step: s.n, skip: true }, nm(s) + ': lagu nahi'); m.close(); done && done(); } catch (e) {} };
    var un = $('[data-undo]', m.el); if (un) un.onclick = async function () { try { await C.run('crm_wf_set', { id: g.quote_id, step: s.n, done: false }, 'Step wapas kiya'); m.close(); done && done(); } catch (e) {} };
  }
  C.wfStep = stepModal;
  /* Round 38: ek hi flow — upar ki sticky patti (flowbar.js). Alag card nahi. */


  /* ---------- Documents & Gallery → customer's plant (stamped with customer name + Plant ID) ---------- */
  function loadPdfLib() { return new Promise(function (res, rej) { if (window.PDFLib) return res(); var sc = document.createElement('script'); sc.src = 'assets/pdf-lib.min.js'; sc.onload = res; sc.onerror = function () { rej(new Error('PDF tool load nahi hua')); }; document.head.appendChild(sc); }); }
  function stampImage(blob, text) {
    return new Promise(function (res, rej) {
      var img = new Image(), u = URL.createObjectURL(blob);
      img.onload = function () {
        var w = img.naturalWidth, h = img.naturalHeight, c = document.createElement('canvas'); c.width = w; c.height = h; var g = c.getContext('2d'); g.drawImage(img, 0, 0);
        var bh = Math.max(30, Math.round(w * 0.045)); g.fillStyle = 'rgba(10,30,18,.62)'; g.fillRect(0, h - bh, w, bh);
        g.fillStyle = '#fff'; g.font = '600 ' + Math.round(bh * 0.52) + 'px system-ui,sans-serif'; g.textBaseline = 'middle'; g.fillText(text, Math.round(bh * 0.4), h - bh / 2, w - bh);
        g.save(); g.globalAlpha = 0.16; g.fillStyle = '#fff'; g.translate(w / 2, h / 2); g.rotate(-Math.PI / 6); g.font = '800 ' + Math.round(w * 0.07) + 'px system-ui,sans-serif'; g.textAlign = 'center'; g.fillText(text.split('  •')[0], 0, 0, w * 0.9); g.restore();
        URL.revokeObjectURL(u); c.toBlob(function (b) { b ? res(b) : rej(new Error('Photo par naam nahi lag paya')); }, 'image/jpeg', 0.86);
      };
      img.onerror = function () { URL.revokeObjectURL(u); rej(new Error('Photo padh nahi paye')); }; img.src = u;
    });
  }
  async function stampPdf(blob, text) {
    await loadPdfLib(); var P = window.PDFLib, doc = await P.PDFDocument.load(await blob.arrayBuffer(), { ignoreEncryption: true }), F = await doc.embedFont(P.StandardFonts.HelveticaBold), ascii = text.replace(/[^\x20-\x7E]/g, '');
    doc.getPages().forEach(function (pg) { var sz = pg.getSize(); pg.drawText(ascii, { x: 24, y: 14, size: 9, font: F, color: P.rgb(0.1, 0.4, 0.2) }); pg.drawText(ascii.split('  |')[0], { x: sz.width * 0.12, y: sz.height * 0.42, size: Math.max(22, sz.width * 0.06), font: F, color: P.rgb(0.2, 0.5, 0.3), opacity: 0.1, rotate: P.degrees(30) }); });
    return new Blob([await doc.save()], { type: 'application/pdf' });
  }
  C.stampFile = async function (blob, mime, text) {
    if (/^image\/(jpeg|png|webp)/.test(mime)) return { blob: await stampImage(blob, text), mime: 'image/jpeg', stamped: true, ext: 'jpg' };
    if (mime === 'application/pdf') return { blob: await stampPdf(blob, text), mime: mime, stamped: true };
    return { blob: blob, mime: mime, stamped: false };
  };
  /* docs: [crm doc records]; preset: { party, quote_id } */
  C.shareToCustomer = async function (docs, preset) {
    preset = preset || {}; docs = (docs || []).filter(Boolean); if (!docs.length) return;
    var party = preset.party || await C.partyPick({ title: 'Kis customer ko bhejna hai?' }); if (!party) return;
    var qs = (await C.list('quote', { party_id: party.id, limit: 50 }).catch(function () { return []; })).filter(function (x) { return x.status !== 'rejected'; });
    if (!qs.length) return C.toast('Is customer ki quotation nahi hai — Plant ID quotation number hi hota hai', true);
    var def = qs.filter(function (x) { return x.id === preset.quote_id; })[0] || qs[0];
    var body = '<div class="fg"><div class="full"><div class="xs mute">Customer</div><b>' + esc(party.title) + '</b> · ' + esc(party.mobile || '') + '</div>' +
      C.f('Kis plant / quotation par (Plant ID)', '<select class="inp" name="qid">' + qs.map(function (x) { return '<option value="' + x.id + '"' + (x.id === def.id ? ' selected' : '') + '>' + esc((x.ref || '') + ' · ' + (x.data.ctype || '') + ' · ' + (x.data.qtitle || x.title)) + '</option>'; }).join('') + '</select>', 'full') +
      C.f('Note (optional)', C.inp('note', '', 'maxlength="300" placeholder="Jaise: Aapke plant ki installation photos"'), 'full') + '</div>' +
      '<div class="sec-t">Files (' + docs.length + ')</div><div class="list">' + docs.map(function (x) { return '<div class="li"><span class="av o">' + C.ic(C.mimeIcon(x.data.mime)) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + (/^image\//.test(x.data.mime) || x.data.mime === 'application/pdf' ? 'Naam + Plant ID is par likh jayega' : 'Naam file ke title me jodega (video par nahi likha ja sakta)') + '</span></span></span></div>'; }).join('') + '</div>';
    var m = C.modal({ title: 'Customer ko bhejein', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('send') + ' Bhejein</button>' });
    $('[data-ok]', m.el).onclick = async function () {
      var o = C.form($('.fg', m.el)), q = qs.filter(function (x) { return String(x.id) === String(o.qid); })[0], text = party.title + '  •  Plant ID ' + q.ref + '  •  Sunpowers', sent = 0;
      C.busy(true);
      try {
        for (var i = 0; i < docs.length; i++) {
          var f = await C.call('crm_file_get', { id: docs[i].id }), st = await C.stampFile(C.fromB64(f.b64, f.mime), f.mime, text), nm = String(party.title).replace(/[^\w]+/g, '-').replace(/^-|-$/g, '') + '_' + String(q.ref).replace(/[^\w]+/g, '-') + '_' + String(f.name).replace(/\.[^.]+$/, '') + (st.ext ? '.' + st.ext : (/\.[^.]+$/.exec(f.name) || [''])[0]);
          await C.call('crm_doc_share', { quote_id: q.id, name: nm, mime: st.mime, b64: await C.toB64(st.blob), stamped: st.stamped, note: o.note || '' }); sent++;
        }
      } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
      if (!sent) return; m.close(); C.toast(sent + ' file customer ke plant me jud gayi ✔');
      var msg = 'Namaste ' + party.title + ' ji, aapke plant (Plant ID ' + q.ref + ') ki ' + sent + ' file Sunpowers par aa gayi hai. Website / Store par login karke "My Plant → Downloads" me dekhein.';
      var w = C.modal({ title: 'Customer ko batayein', size: 'sm', body: '<p>' + esc(msg) + '</p>', foot: '<button class="btn btn-o" data-close>Band</button><a class="btn btn-wa" target="_blank" rel="noopener" href="' + esc(C.wa(party.mobile, msg)) + '">' + C.ic('wa') + ' WhatsApp</a>' });
    };
  };

  /* ---------- Projects page ---------- */
  function cur(p) { var s = (p.steps || []).filter(function (x) { return !x.done; })[0]; return s ? LBL[s.n] : 'Poora ho gaya'; }
  /* Round 40: Net Metering sirf is customer ki project list me, alag permission (projects.netmetering) se */
  function nmRow(p) {
    var st = (p.steps || []).filter(function (x) { return x.n === 11; })[0];
    if (!st || !C.can('projects.netmetering')) return '';
    return '<div class="row" style="padding:0 12px 10px 68px"><button class="btn btn-o btn-sm" data-nm="' + p.id + '">' + C.ic('plug') + ' Net Metering' + (st.done ? ' ✔' : '') + '</button></div>';
  }
  function projRow(p) {
    var pct = Math.round(p.done / Math.max(1, p.total) * 100);
    return '<div class="proj-wrap">' + projRowA(p, pct) + nmRow(p) + '</div>';
  }
  function projRowA(p, pct) {
    return '<a class="li proj-li" href="#/project/' + p.id + '"><span class="av b">' + C.ic('plant') + '</span><span class="grow"><span class="t">' + esc(p.customer) + ' ' + C.pill(p.ctype || '', 'v') + (p.old ? C.pill('Purana', 'g') : '') + (p.bill_state === 'pending' ? C.ribbon('Pending bill', 'o') : '') + (p.closed ? C.ribbon('Bill clear', 'g') : '') + '</span>' +
      '<span class="m"><span>' + esc(p.ref || '') + '</span>' + (p.kw ? '<span>' + esc(p.kw) + ' kW</span>' : '') + '<span>' + C.ic('user') + ' ' + esc(p.owner || '—') + '</span><span>Abhi: <b>' + esc(cur(p)) + '</b></span></span><span class="prog" style="margin-top:6px"><i style="width:' + pct + '%"></i></span></span>' +
      '<span class="amt">' + p.done + '/' + p.total + '<small class="mute">' + esc(C.dt(p.last) ? C.fd(p.last) : '') + '</small></span></a>';
  }
  async function accessTab(host) {
    var r = await C.run('crm_wf_perm', {}), users = (C.cache.users || []).filter(function (u) { return u.status === 'active' && u.role !== 'consumer' && u.role !== 'admin'; });
    var h = '<div class="note g">Tareekh aur samay sabko dikhta hai. Step ki <b>details</b> aur <b>badalne</b> ki permission default me sirf Admin + Manager ko hai — yahan se aur users ko allow karein.</div>' +
      '<label class="chk" style="margin:8px 0"><input type="checkbox" id="wfold"' + (r.allow_old ? ' checked' : '') + '> Purane final projects (jo Projects me nahi hain) Projects me jodne ki permission sabko dein</label>';
    if (!users.length) h += C.empty('team', 'Koi aur user nahi', 'Team me user banane ke baad yahan access de sakte hain');
    else h += '<div class="tw"><table class="t"><thead><tr><th>Step</th>' + users.map(function (u) { return '<th class="r">' + esc(u.name) + '</th>'; }).join('') + '</tr></thead><tbody>' + (r.flow || r.names.map(function (x, i) { return i + 1; })).map(function (num) {
      var n = String(num), nm = r.names[num - 1], pm = (r.perm || {})[n] || {}; return '<tr><td>' + (IC[n] || '•') + ' ' + esc(nm) + '</td>' + users.map(function (u) {
        var v = (pm.view || []).map(String).indexOf(String(u.id)) >= 0, e = (pm.edit || []).map(String).indexOf(String(u.id)) >= 0;
        return '<td class="r"><label class="xs"><input type="checkbox" data-pv="' + n + ':' + u.id + '"' + (v ? ' checked' : '') + '> Dekhe</label><br><label class="xs"><input type="checkbox" data-pe="' + n + ':' + u.id + '"' + (e ? ' checked' : '') + '> Badle</label></td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div>';
    h += '<div class="bar" style="margin-top:12px"><button class="btn btn-p" data-save>' + C.ic('check') + ' Save</button></div>';
    host.innerHTML = h;
    $('[data-save]', host).onclick = async function () {
      var perm = {}; $$('[data-pv],[data-pe]', host).forEach(function (c) { if (!c.checked) return; var k = c.hasAttribute('data-pv') ? 'view' : 'edit', a = c.getAttribute('data-p' + (k === 'view' ? 'v' : 'e')).split(':'); perm[a[0]] = perm[a[0]] || { view: [], edit: [] }; perm[a[0]][k].push(+a[1]); });
      try { await C.run('crm_wf_perm', { perm: perm, allow_old: $('#wfold', host).checked }, 'Access save ho gaya ✔'); } catch (e) {}
    };
  }
  async function importOld() {
    var all = await C.list('quote', { limit: 3000 }), list = all.filter(function (x) { return ['Residential', 'Commercial', 'Industrial', 'VFD'].indexOf(x.data.ctype) >= 0 && !(x.data.wf && x.data.wf['7']) && !x.data.old_project; });
    var m = C.modal({ title: 'Purana project jodein', size: 'wide', body: '<div class="note g">Sirf wahi quotation dikhengi jinme <b>Customer type</b> (Residential / Commercial / Industrial / VFD) chuna hai. Purani quotation me type pehle chunein.</div>' +
      (list.length ? '<input class="inp" type="search" id="oq" placeholder="Khojein"><div class="list" id="ol" style="margin-top:8px">' + list.map(function (x) { return '<label class="li click" style="cursor:pointer"><input type="checkbox" value="' + x.id + '" style="margin-right:6px"><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(x.ref) + '</span><span>' + esc(x.data.ctype) + '</span></span></span></label>'; }).join('') + '</div>' : C.empty('quote', 'Koi quotation nahi mili')),
      foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Projects me jodein</button>' });
    var ol = $('#ol', m.el); if (ol) C.filterList($('#oq', m.el), ol);
    $('[data-ok]', m.el).onclick = async function () { var ids = $$('#ol input:checked', m.el).map(function (c) { return +c.value; }); if (!ids.length) return C.toast('Kam se kam ek chunein', true); try { for (var i = 0; i < ids.length; i++) await C.call('crm_project_import', { id: ids[i] }); C.toast(ids.length + ' project jud gaye ✔'); m.close(); C.render(); } catch (e) { C.toast(e.message, true); } };
  }
  C.mod('projects', {
    title: 'Projects', nav: 'projects',
    allowed: function () { return C.canAny('quotes.create', 'quotes.view_all', 'plants.create', 'plants.view_all'); },
    render: async function (el, params, q) {
      var tab = q.tab || 'live', canRef = C.canAny('plants.create', 'plants.view_all'), canQ = C.canAny('quotes.create', 'quotes.view_all');
      if (tab === 'live' && !canQ) tab = 'referral';
      var tabs = []; if (canQ) tabs.push(['live', 'Live tracking']); if (canRef) tabs.push(['referral', 'Referral plants']); if (C.isAdmin()) tabs.push(['access', 'Step access']);
      var head = '<div class="tabs">' + tabs.map(function (t) { return '<button data-goto="#/projects' + (t[0] === 'live' ? '' : '?tab=' + t[0]) + '" class="' + (tab === t[0] ? 'on' : '') + '">' + esc(t[1]) + '</button>'; }).join('') + '</div>';
      el.addEventListener('click', function (e) { var gt = e.target.closest('[data-goto]'); if (gt) C.go(gt.getAttribute('data-goto')); });
      if (tab === 'referral') { var box = document.createElement('div'); el.innerHTML = head; el.appendChild(box); return C.plantsRender(box, params, q, '#/projects', { tab: 'referral' }); }
      if (tab === 'access') { el.innerHTML = '<div class="ph"><div><h1>Projects ' + C.ribbon('Live tracking', 'g') + '</h1><p>Kaun kis step ki details dekhe / badle.</p></div></div>' + head + '<div id="ac"></div>'; return accessTab($('#ac', el)); }
      var list = await C.call('crm_projects', {}), st = q.st || '', f = list.filter(function (p) { return !st || (st === 'pending' ? p.bill_state === 'pending' : st === 'closed' ? p.closed : st === 'running' ? !p.closed : true); });
      var allowOld = C.isAdmin(); try { if (!allowOld) { allowOld = false; } } catch (e) {}
      var h = '<div class="ph"><div><h1>Projects ' + C.ribbon('Live tracking', 'g') + '</h1><p>Apply Process confirm hote hi customer yahan aa jata hai. Sirf plant / project wale customers.</p></div><div class="row">' +
        C.reportBtns('Projects', function () { return { head: ['No', 'Customer', 'Mobile', 'Type', 'kW', 'Abhi', 'Steps', 'Baaki bill'], rows: f.map(function (p) { return [p.ref, p.customer, p.mobile || '', p.ctype, p.kw || '', cur(p), p.done + '/' + p.total, p.balance != null ? p.balance : '']; }), text: 'Projects' }; }) +
        (C.isAdmin() ? '<button class="btn btn-o" data-act="old">' + C.ic('plus') + ' Purana project jodein</button>' : '') + '</div></div>' + head;
      var pend = list.filter(function (p) { return p.bill_state === 'pending'; }).length;
      h += '<div class="kpis">' + C.kpi('Chalu projects', list.filter(function (p) { return !p.closed; }).length) + C.kpi('Pending bill', pend, '', pend ? 'warn' : '') + C.kpi('Bill clear', list.filter(function (p) { return p.closed; }).length, '', 'gold') + '</div>';
      h += '<div class="bar">' + C.chips([['', 'Sab', list.length], ['running', 'Chalu'], ['pending', 'Pending bill', pend], ['closed', 'Bill clear']], st, 'st') + '<input class="inp" type="search" data-q placeholder="Customer / quotation no. khojein"></div>';
      h += f.length ? '<div class="list" id="pl">' + f.map(projRow).join('') + '</div>' : '<div class="card">' + C.empty('plant', 'Abhi koi project nahi', 'Quotation ka "Apply Process" step poora hone par customer yahan apne aap aa jata hai') + '</div>';
      el.innerHTML = h; var pl = $('#pl', el); if (pl) C.filterList($('[data-q]', el), pl);
      el.addEventListener('click', function (e) { var c = e.target.closest('[data-st]'); if (c) C.go('#/projects' + C.qs({ st: c.getAttribute('data-st') })); });
      el.addEventListener('click', function (e) {
        var b = e.target.closest('[data-nm]'); if (!b) return; e.preventDefault();
        if (!C.can('projects.netmetering')) return C.toast('Permission not allowed — Admin se baat karein', true);
        C.call('crm_wf_get', { id: +b.getAttribute('data-nm') }).then(function (g) {
          var st = (g.steps || []).filter(function (x) { return x.n === 11; })[0];
          if (!st) return C.toast('Net Metering is project me lagu nahi hai', true);
          C.wfStep(g, st, function () { C.render(); });
        }).catch(function (err) { C.toast(err.message, true); });
      });
      C.bind(el, { old: importOld });
    }
  });
  C.mod('project', {
    title: 'Project', nav: 'projects', routes: ['project'],
    render: async function (el, params) {
      var q = await C.get(params[0]), d = q.data || {};
      var inv = d.invoice_id ? await C.get(d.invoice_id).catch(function () { return null; }) : null;
      var h = '<div class="crumb"><a href="#/projects">Projects</a>' + C.ic('right') + '<span>' + esc(q.title) + '</span></div><div class="ph"><div><h1>' + esc(q.title) + ' ' + (d.bill_state === 'pending' ? C.ribbon('Pending bill', 'o') : '') + '</h1><p>' + esc([q.ref, d.ctype, d.qtitle].filter(Boolean).join(' · ')) + '</p></div><div class="row">' + C.callBtns(q.mobile, 'Namaste ' + q.title + ' ji, ') +
        '<a class="btn btn-o" href="#/quote/' + q.id + '">' + C.ic('quote') + ' Quotation</a>' + (inv ? '<a class="btn btn-o" href="#/invoice/' + inv.id + '">' + C.ic('bill') + ' Bill</a>' : '') + (q.party_id ? '<a class="btn btn-o" href="#/customer/' + q.party_id + '">' + C.ic('user') + ' Customer</a>' : '') + (C.can('docs.view') ? '<button class="btn btn-p" data-act="sendf">' + C.ic('send') + ' Documents / Photos bhejein</button>' : '') + '</div></div>';
      if (inv) h += '<div class="kpis">' + C.kpi('Bill', money(inv.amount), inv.ref) + C.kpi('Mila', money(inv.data.paid || 0)) + C.kpi('Baaki', money(inv.data.balance != null ? inv.data.balance : inv.amount), '', (inv.data.balance || 0) > 0 ? 'warn' : '') + '</div>';
      el.innerHTML = h;

      C.bind(el, { sendf: async function () { var ds = await C.list('doc', { limit: 500 }).catch(function () { return []; }); ds = ds.filter(function (x) { return !x.data.attach_kind; }); if (!ds.length) return C.toast('Documents & Gallery me abhi koi file nahi', true); var m = C.modal({ title: 'Kaun si file bhejni hai?', size: 'wide', body: '<input class="inp" type="search" id="fq" placeholder="Khojein"><div class="list" id="fl" style="margin-top:8px">' + ds.map(function (x) { return '<label class="li click" style="cursor:pointer"><input type="checkbox" value="' + x.id + '" style="margin-right:6px"><span class="av o">' + C.ic(C.mimeIcon(x.data.mime)) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span></span></label>'; }).join('') + '</div>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Aage</button>' }); C.filterList($('#fq', m.el), $('#fl', m.el)); $('[data-ok]', m.el).onclick = function () { var ids = $$('#fl input:checked', m.el).map(function (c) { return c.value; }); if (!ids.length) return C.toast('Kam se kam ek file chunein', true); m.close(); C.shareToCustomer(ds.filter(function (x) { return ids.indexOf(String(x.id)) >= 0; }), { party: { id: q.party_id, title: q.title, mobile: q.mobile }, quote_id: q.id }); }; } });
    }
  });
})();
