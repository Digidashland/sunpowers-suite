/* Round 47: customer flow ke Step 14 – 18 ke asli panel.
   Step 14 Documents bheje · 15 Loan · 16 Referral · 17 AMC · 18 Complaint · (Round 48) 22 Warranty + khud-lagane ki ghoshna · 23 Job Done + kaam-poora ki ghoshna.
   Data server me (crm_flow_rec, crm_fr_*) — yahan sirf dikhana aur bhejna. Har cheez usi job (quotation) se bandhi hai. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var X = C.FLOWX = C.FLOWX || {};

  function hist(r) {
    var h = (r.hist || []).slice().reverse();
    if (!h.length) return '';
    return '<div class="xs mute" style="margin-top:6px">' + h.slice(0, 6).map(function (x) { return '• ' + esc(C.dt(x.at) || '') + ' — ' + esc(x.by || '') + (x.status ? ' · ' + esc(x.status) : '') + (x.note ? ' · ' + esc(x.note) : ''); }).join('<br>') + '</div>';
  }
  function lockNote(s) { return s.can_edit ? '' : '<div class="note">Is step ko badalne ki permission nahi hai — sirf dekh sakte hain.</div>'; }
  function need(g) { return g.quote_id ? '' : '<div class="note">Pehle quotation banayein.</div>'; }
  function confirmNote(g) {
    var st = (g.steps || []).filter(function (x) { return x.n === 6; })[0];
    return st && !st.done ? '<div class="note">Pehle quotation <b>Confirm</b> karein (Step 6) — uske baad hi ye bhara ja sakta hai.</div>' : '';
  }
  function bindForm(host) { return function (id, fn) { var b = $('[data-act="' + id + '"]', host); if (b) b.onclick = fn; }; }
  function users(sel, blank) { return C.userOpts(sel || '', blank || '— Chunein —'); }

  /* ============================== 14 · Customer Documents (Round 49) ==============================
     Is kaam ke customer ke apne documents: bill, quotation, blueprint, plant ki photo, certificate… Customer apne Profile → Documents me sirf dekh / download karta hai.
     Upload · badlo (replace) · category badlo · delete yahin se. Company ka "Documents & Gallery" alag hai. */
  var CDC = ['Blueprint', 'Plant photo', 'Quotation', 'Bill', 'Certificate', 'Warranty', 'Agreement', 'Other'];
  var CDI = { 'Blueprint': 'grid', 'Plant photo': 'image', 'Quotation': 'quote', 'Bill': 'rupee', 'Certificate': 'shield', 'Warranty': 'shield', 'Agreement': 'folder', 'Other': 'folder' };
  function cdocOpts(cat) { return cat === 'Blueprint' ? { max: 2000, q: 0.85, target: 700 * 1024 } : { max: 1600, q: 0.8, target: 450 * 1024 }; }
  async function cdocSend(file, quoteId, cat, replaceId, nm) {
    var o = cdocOpts(cat), f = /^image\//.test(file.type || '') ? await C.compress(file, o.max, o.q, o.target) : file;
    if (f.size > 3 * 1024 * 1024) throw new Error(file.name + ': 3 MB se badi file — chhoti karke dalein');
    var name = (nm || file.name || 'file').replace(/\.(png|webp|jpeg)$/i, '.jpg').replace(/\.jpg\.jpg$/, '.jpg');
    return C.call('crm_cdoc_save', { quote_id: quoteId, replace_id: replaceId || null, name: name, mime: f.type || 'application/octet-stream', b64: await C.toB64(f), cat: cat });
  }
  X[14] = {
    render: async function (host, g, s, reopen, m) {
      var q = g.quote_id, p = g.party_id, up = C.can('docs.upload'), del = C.can('docs.delete');
      var ds = (await C.list('doc', { party_id: p, limit: 500 }).catch(function () { return []; })).filter(function (x) { return String(x.data.shared_quote) === String(q); });
      var by = {}, order = [];
      ds.forEach(function (x) { var c = x.data.cat || 'Other'; if (!by[c]) { by[c] = []; order.push(c); } by[c].push(x); });
      order.sort(function (a, b) { return CDC.indexOf(a) - CDC.indexOf(b); });
      var h = need(g) + '<div class="note g">' + C.ic('shield') + ' Yahan jo files rakhi jayengi, customer unhe apne <b>Profile → Documents</b> me dekh aur download kar sakta hai; quotation, bill aur rasid wahan apne aap aate hain. Customer apni file (ID, bijli bill, photo) khud bhejta hai to wo yahin <b>"Customer ne bheja"</b> me dikhti hai. Kya dikhana hai: <a data-fxgo href="#/settings?tab=company">Settings → Company</a>. Company ke "Documents &amp; Gallery" se iska koi lena-dena nahi.</div>';
      if (q && up) h += '<div class="card" style="padding:12px;margin:10px 0"><div class="sec-t" style="margin-top:0">Nayi file jodein</div><div class="row wrap" style="gap:8px;align-items:flex-end"><span class="grow" style="min-width:160px">' + C.f('Category', C.sel('cdcat', CDC, 'Blueprint')) + '</span><button class="btn btn-p" data-act="upl">' + C.ic('upload') + ' File chunkar upload karein</button></div><div class="xs mute" style="margin-top:6px">Photo apne aap chhoti ho jati hai (storage bachti hai). PDF / file max 3 MB.</div></div>';
      h += '<div class="sec-t">Customer ke Documents (' + ds.length + ')</div>';
      if (!ds.length) h += '<div class="note">Abhi is kaam me customer ka koi document nahi hai.</div>';
      order.forEach(function (c) {
        h += '<div class="xs mute" style="margin:10px 0 4px;font-weight:700;text-transform:uppercase;letter-spacing:.04em">' + esc(c) + ' (' + by[c].length + ')</div><div class="list">' + by[c].map(function (x) {
          return '<div class="li"><span class="av o">' + C.ic(CDI[c] || (C.mimeIcon ? C.mimeIcon(x.data.mime) : 'file')) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + esc(C.dt(x.data.replaced_at || x.data.shared_at) || '') + '</span><span>' + esc(x.data.replaced_by || x.data.shared_by || '') + '</span>' + (x.data.size ? '<span>' + C.fsize(x.data.size) + '</span>' : '') + (x.data.replaced_at ? '<span>badli gayi</span>' : '') + '</span></span>' +
            '<button class="btn btn-o btn-sm" data-act="open" data-id="' + x.id + '">Kholein</button> ' + C.dlMenu([['download', 'Download', 'data-act="dl" data-id="' + x.id + '"'], ['share', 'Customer ko bhejein', 'data-act="share" data-id="' + x.id + '"']].concat(up ? [['upload', 'File badlein (Replace)', 'data-act="rep" data-id="' + x.id + '" data-cat="' + esc(c) + '"'], ['edit', 'Category badlein', 'data-act="cat" data-id="' + x.id + '" data-cat="' + esc(c) + '" data-name="' + esc(x.title) + '"']] : []).concat(del ? [['trash', 'Delete', 'data-act="del" data-id="' + x.id + '" data-name="' + esc(x.title) + '"']] : []), { sm: true }) + '</div>';
        }).join('') + '</div>';
      });
      if (q) h += '<div class="xs mute" style="margin-top:12px">Company ki purani file bhejni ho to: <a data-fxgo href="#/docs?party=' + p + '&cq=' + q + '&cf=' + p + '">Documents &amp; Gallery se chunein</a>.</div>';
      host.innerHTML = h;
      function pick(multi, cb) { var i = document.createElement('input'); i.type = 'file'; i.multiple = !!multi; i.accept = 'image/*,.pdf,.doc,.docx,.xls,.xlsx'; i.onchange = function () { if (i.files && i.files.length) cb(i.files); }; i.click(); }
      C.bind(host, {
        open: function (id) { C.openFile(id); }, dl: function (id) { C.openFile(id, 'download'); }, share: function (id) { C.openFile(id, 'share'); },
        upl: function () {
          var cat = ($('[name="cdcat"]', host) || {}).value || 'Other';
          pick(true, async function (files) {
            var ok = 0; C.busy(true);
            try { for (var i = 0; i < files.length; i++) { try { await cdocSend(files[i], q, cat); ok++; } catch (e) { C.toast(e.message, true); } } } finally { C.busy(false); }
            if (ok) { C.toast(ok + ' file customer ke Documents me jud gayi ✔'); reopen(); }
          });
        },
        rep: function (id, el) {
          var cat = el && el.getAttribute('data-cat') || 'Other';
          pick(false, async function (files) { C.busy(true); try { await cdocSend(files[0], q, cat, id); C.toast('File badal di gayi ✔'); reopen(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); } });
        },
        cat: function (id, el) {
          var cur = el.getAttribute('data-cat') || 'Other', nm = el.getAttribute('data-name') || '';
          var mm = C.modal({ title: 'Category badlein', size: 'sm', body: C.f('Category', C.sel('ncat', CDC, cur)), foot: '<button class="btn btn-o" data-close>Nahi</button><button class="btn btn-p" data-ok>Save</button>' });
          $('[data-ok]', mm.el).onclick = async function () {
            var v = $('[name="ncat"]', mm.el).value; mm.close(); if (!v || v === cur) return;
            try { await C.run('crm_cdoc_save', { quote_id: q, replace_id: id, name: nm, cat: v }, 'Category badal di ✔'); reopen(); } catch (e) {}
          };
        },
        del: async function (id, el) {
          if (!(await C.confirm('"' + (el.getAttribute('data-name') || 'File') + '" customer ke Documents se hata dein? Customer ko ye file dikhni band ho jayegi.', 'Delete', true))) return;
          try { await C.run('crm_cdoc_delete', { id: id }, 'File hata di gayi ✔'); reopen(); } catch (e) {}
        }
      });
      var a = $('[data-fxgo]', host); if (a) a.onclick = function () { m.close(); };
    }
  };

  /* ============================== 15 · Loan / Finance ============================== */
  X[15] = {
    only: true,
    render: async function (host, g, s, reopen, m) {
      var rows = await C.call('crm_fr_list', { quote_id: g.quote_id, kind: 'loan' }), r = rows[0] || null, d = r ? r.data : {}, can = s.can_edit;
      var h = need(g) + confirmNote(g) + lockNote(s);
      if (r) h += '<div class="note g">Abhi: <b>' + esc(d.pay_mode || '') + '</b>' + (r.status && r.status !== 'cash' ? ' · ' + esc(r.status) : '') + (d.bank ? ' · ' + esc(d.bank) : '') + (d.loan_amount ? ' · ' + money(d.loan_amount) : '') + '</div>';
      h += '<div class="fg" id="fxf" style="margin-top:8px">' +
        C.f('Payment kaise hoga *', C.sel('pay_mode', ['Cash', 'Loan', 'Mixed'], d.pay_mode || '', '— Chunein —', can ? '' : 'disabled')) +
        '<span id="fxloan" class="fg full" style="grid-column:1/-1">' +
        C.f('Bank / Finance company *', C.inp('bank', d.bank, can ? '' : 'disabled')) + C.f('Loan amount (₹) *', C.inp('loan_amount', d.loan_amount || '', 'inputmode="decimal"' + (can ? '' : ' disabled'))) +
        C.f('Apply ki tareekh', C.inp('apply_date', d.apply_date || '', 'type="date"' + (can ? '' : ' disabled'))) + C.f('Stage *', C.sel('status', ['Applied', 'Sanctioned', 'Disbursed', 'Rejected'], r && r.status !== 'cash' ? r.status : '', '— Chunein —', can ? '' : 'disabled')) +
        C.f('Sanction hui rakam (₹)', C.inp('sanction_amount', d.sanction_amount || '', 'inputmode="decimal"' + (can ? '' : ' disabled'))) + C.f('Loan / file number', C.inp('loan_ref', d.loan_ref, can ? '' : 'disabled')) +
        C.f('Disburse hui rakam (₹)', C.inp('disbursed_amount', d.disbursed_amount || '', 'inputmode="decimal"' + (can ? '' : ' disabled'))) + C.f('Disburse ki tareekh', C.inp('disbursed_on', d.disbursed_on || '', 'type="date"' + (can ? '' : ' disabled'))) +
        '</span>' + C.f('Note', C.inp('note', '', 'maxlength="300" placeholder="Jaise: documents bank me jama"'), 'full') + '</div>';
      if (r) h += hist(r);
      h += '<div class="row" style="margin-top:12px;gap:8px;flex-wrap:wrap">' + (can ? '<button class="btn btn-p" data-act="save">' + C.ic('check') + ' Save</button>' : '') +
        (r && r.status === 'Disbursed' && g.invoice_id && !d.payment_id ? '<button class="btn btn-o" data-act="pay">' + C.ic('rupee') + ' Bill me payment jodein</button>' : '') +
        (r && d.payment_id ? '<span class="pill">Bill me payment jud chuka</span>' : '') + '</div>' +
        (r && r.status === 'Disbursed' && !g.invoice_id ? '<div class="xs mute" style="margin-top:6px">Bill banne ke baad yahin se disburse hui rakam payment me jod sakte hain.</div>' : '');
      host.innerHTML = h;
      var f = $('#fxf', host), lo = $('#fxloan', host), pm = f.pay_mode || $('[name="pay_mode"]', f);
      function tog() { lo.style.display = pm.value === 'Cash' || !pm.value ? 'none' : ''; }
      pm.onchange = tog; tog();
      function payload() { var v = C.form(f); return { id: r ? r.id : undefined, quote_id: g.quote_id, kind: 'loan', status: v.status, note: v.note, data: v }; }
      C.bind(host, {
        save: async function () {
          var v = C.form(f); if (!v.pay_mode) { pm.classList.add('bad'); return C.toast('Payment tarika chunein', true); }
          try { await C.run('crm_fr_save', payload(), 'Loan jaankari save ✔'); reopen(); } catch (e) {}
        },
        pay: async function () {
          var inv = null; try { inv = await C.get(g.invoice_id); } catch (e) {}
          if (!inv) return C.toast('Bill nahi mila', true);
          var pay = await C.payForm({ invoice: inv, amount: num(d.disbursed_amount), mode: 'Finance / Loan', note: 'Loan disburse — ' + (d.bank || '') + (d.loan_ref ? ' · ' + d.loan_ref : '') });
          if (!pay) return;
          try { var pl = payload(); pl.data.payment_id = String(pay.id); pl.status = 'Disbursed'; await C.run('crm_fr_save', pl, 'Loan ki rakam bill me jud gayi ✔'); reopen(); } catch (e) {}
        }
      });
    }
  };

  /* ============================== 16 · Referral ============================== */
  X[16] = {
    only: true,
    render: async function (host, g, s, reopen, m) {
      var rows = await C.call('crm_fr_list', { quote_id: g.quote_id, kind: 'referral' }), can = s.can_edit, canPay = C.can('earnings.manage');
      var leads = {};
      await Promise.all(rows.filter(function (r) { return r.data.lead_id; }).map(function (r) { return C.get(r.data.lead_id).then(function (l) { leads[r.id] = l; }).catch(function () {}); }));
      var h = need(g) + confirmNote(g) + lockNote(s);
      h += '<div class="sec-t">Refer kiye gaye log (' + rows.length + ')</div>';
      h += rows.length ? '<div class="list">' + rows.map(function (r) {
        var d = r.data, l = leads[r.id];
        return '<div class="li" style="align-items:flex-start"><span class="grow"><span class="t">' + esc(d.referred_name) + ' · ' + esc(d.referred_mobile) + '</span>' +
          '<span class="m"><span>Refer kiya: ' + esc(d.referrer_name) + (d.referrer_mobile ? ' (' + esc(d.referrer_mobile) + ')' : '') + '</span><span>' + esc(d.ref_type === 'customer' ? 'Customer' : d.ref_type === 'partner' ? 'Partner' : 'Anya') + '</span></span>' +
          '<span class="m">' + (l ? '<span>Lead: ' + C.pill(l.status || 'open', 'b') + '</span>' : d.lead_error ? '<span class="pill r">Lead nahi bani: ' + esc(d.lead_error) + '</span>' : '') +
          (num(d.reward_amount) > 0 ? '<span>Reward ' + money(d.reward_amount) + ' ' + C.pill(d.earning_id ? 'Commission me jud gaya' : r.status === 'paid' ? 'Mil gaya' : 'Baaki', d.earning_id || r.status === 'paid' ? '' : 'o') + '</span>' : '') + '</span>' + hist(r) + '</span>' +
          '<span class="col" style="gap:6px">' + (can && canPay && !d.earning_id && num(d.reward_amount) > 0 ? '<button class="btn btn-o btn-sm" data-act="reward" data-id="' + r.id + '">Commission me jodein</button>' : '') +
          (can ? '<button class="btn btn-o btn-sm" data-act="del" data-id="' + r.id + '">Hatayein</button>' : '') + '</span></div>';
      }).join('') + '</div>' : '<div class="note">Abhi koi referral nahi.</div>';
      var pty = null; try { pty = await C.get(g.party_id); } catch (e) {}
      if (can && g.quote_id) {
        h += '<div class="sec-t" style="margin-top:12px">Naya referral</div><div class="fg" id="fxf">' +
          C.f('Kisne refer kiya', C.sel('ref_type', [['customer', 'Customer'], ['partner', 'Partner'], ['other', 'Anya']], 'customer')) + C.f('Refer karne wale ka naam *', C.inp('referrer_name', pty ? pty.title : '')) +
          C.f('Unka mobile', C.inp('referrer_mobile', pty ? (pty.mobile || '') : '', 'inputmode="numeric" maxlength="10"')) + C.f('Jisko refer kiya — naam *', C.inp('referred_name', '')) +
          C.f('Unka mobile *', C.inp('referred_mobile', '', 'inputmode="numeric" maxlength="10"')) + C.f('Reward / commission (₹)', C.inp('reward_amount', '', 'inputmode="decimal"')) +
          C.f('Note', C.inp('referred_note', '', 'maxlength="200" placeholder="Jaise: 3 kW ke liye puch rahe hain"'), 'full') + '</div>' +
          '<div class="xs mute" style="margin-top:6px">Save karte hi naya <b>Lead</b> (source: Referral) apne aap ban jayega.</div>' +
          '<div style="margin-top:10px"><button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Referral save karein</button></div>';
      }
      host.innerHTML = h;
      C.bind(host, {
        add: async function () {
          var f = $('#fxf', host), v = C.form(f);
          if (!C.need(f, ['referrer_name', 'referred_name', 'referred_mobile'])) return;
          try { await C.run('crm_fr_save', { quote_id: g.quote_id, kind: 'referral', data: v, note: '' }, 'Referral save ✔ — lead ban gayi'); reopen(); } catch (e) {}
        },
        del: async function (id) {
          var why = await C.ask('Hatane ki wajah', 'Is referral ko kyun hata rahe hain?', { min: 3, danger: true, ok: 'Hatao' }); if (why == null) return;
          try { await C.run('crm_fr_del', { id: +id, reason: why }, 'Hata diya'); reopen(); } catch (e) {}
        },
        reward: function (id) {
          var mm = C.modal({ title: 'Commission me jodein', size: 'sm', body: C.f('Ye reward kis staff ko milega?', '<select class="inp" id="fxu">' + users('', '— User chunein —') + '</select>') + '<div class="xs mute">Ye Commission / Earnings me aayega, wahan se salary me judega.</div>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Jodein</button>' });
          $('[data-ok]', mm.el).onclick = async function () {
            var u = $('#fxu', mm.el).value; if (!u) return C.toast('User chunein', true);
            try { await C.run('crm_fr_reward', { id: +id, user_id: +u }, 'Commission me jud gaya ✔'); mm.close(); reopen(); } catch (e) {}
          };
        }
      });
    }
  };

  /* ============================== 17 · AMC / Maintenance ============================== */
  X[17] = {
    only: true,
    render: async function (host, g, s, reopen, m) {
      var A = await C.amcOf(g.party_id), rem = (await C.list('reminder', { party_id: g.party_id, limit: 200 }).catch(function () { return []; })).filter(function (x) { return x.status === 'open' && x.data && String(x.data.amc_renewal) === 'true'; });
      var h = need(g) + lockNote(s) + '<div class="sec-t">AMC / Maintenance plan (' + A.G.length + ')</div>';
      h += A.G.length ? '<div class="list">' + A.G.map(function (c, i) {
        var cls = c.status === 'overdue' ? 'r' : c.status === 'soon' ? 'o' : c.status === 'complete' ? '' : 'b';
        return '<div class="li"><span class="grow"><span class="t">' + esc(c.plan) + ' ' + C.pill(c.status === 'complete' ? 'Poora' : c.status === 'overdue' ? 'Late' : c.status === 'soon' ? 'Jaldi' : 'Aane wala', cls) + '</span>' +
          '<span class="m"><span>' + c.done.length + '/' + c.total + ' visit hui</span>' + (c.last ? '<span>Pichli service: ' + esc(C.fd(c.last)) + '</span>' : '') + (c.next ? '<span>Agli: <b>' + esc(C.fd(c.next.due_at)) + '</b></span>' : '') + '</span></span>' +
          '<button class="btn btn-o btn-sm" data-act="view" data-id="' + i + '">Dekhein</button></div>';
      }).join('') + '</div>' : '<div class="note">Is customer ka abhi koi AMC plan nahi.</div>';
      if (rem.length) h += '<div class="note" style="margin-top:8px">🔔 Renewal yaad-dihani: ' + rem.map(function (x) { return esc(C.fd(x.due_at)); }).join(', ') + ' (Aaj ke kaam me aayegi)</div>';
      if (s.can_edit) h += '<div style="margin-top:10px"><button class="btn btn-p" data-act="new">' + C.ic('plus') + ' Naya plan / Renewal</button></div>';
      host.innerHTML = h;
      C.bind(host, {
        fin: async function () { try { await C.run('crm_wf_set', { id: g.quote_id, step: 17, done: true, note: 'AMC plan: ' + A.G.map(function (c) { return c.plan; }).join(', ') }, 'AMC step ✔'); reopen(); } catch (e) {} },
        view: function (i) { m.close(); A.G[+i] && C.amcView(A.G[+i], A.P, A.K); },
        new: async function () {
          var party = null; try { party = await C.get(g.party_id); } catch (e) {}
          if (!party) return C.toast('Customer nahi mila', true);
          m.close(); C.amcForm(party, A.P, A.K, null, async function () { if (!s.done && g.quote_id) { try { await C.call('crm_wf_set', { id: g.quote_id, step: 17, done: true, note: 'AMC plan bana' }); } catch (e) {} } reopen(); });
        }
      });
      if (A.G.length && !s.done && s.can_edit && g.quote_id) host.insertAdjacentHTML('beforeend', '<div style="margin-top:10px"><button class="btn btn-p" data-act="fin">' + C.ic('check') + ' AMC step poora hua</button></div>');
    }
  };

  /* ============================== 18 · Complaint / Warranty ticket ============================== */
  X[18] = {
    only: true,
    render: async function (host, g, s, reopen, m) {
      var rows = await C.call('crm_fr_list', { quote_id: g.quote_id, kind: 'complaint' }), can = s.can_edit;
      var h = need(g) + confirmNote(g) + lockNote(s) + '<div class="sec-t">Complaint tickets (' + rows.length + ')</div>';
      h += rows.length ? '<div class="list">' + rows.map(function (r) {
        var d = r.data, cls = r.status === 'Resolved' ? '' : r.status === 'In progress' ? 'b' : 'o';
        return '<div class="li" style="align-items:flex-start"><span class="grow"><span class="t">' + esc(r.no) + ' ' + C.pill(r.status, cls) + (d.priority === 'Urgent' ? ' ' + C.pill('Urgent', 'r') : '') + '</span>' +
          '<span class="m"><span>' + esc(d.issue) + '</span></span><span class="m"><span>' + esc(C.fd(d.c_date)) + '</span>' + (d.brand ? '<span>' + esc(d.brand) + '</span>' : '') + (d.serial ? '<span>Serial ' + esc(d.serial) + '</span>' : '') + '<span>' + esc(d.handler || '') + '</span>' + (d.ticket_ref ? '<span>Ref ' + esc(d.ticket_ref) + '</span>' : '') + '</span>' +
          (d.resolution ? '<span class="m"><span>Hal: ' + esc(d.resolution) + '</span></span>' : '') + hist(r) + '</span>' +
          '<span class="col" style="gap:6px">' + (can ? '<button class="btn btn-o btn-sm" data-act="upd" data-id="' + r.id + '">Update</button><button class="btn btn-o btn-sm" data-act="del" data-id="' + r.id + '">Hatayein</button>' : '') + '</span></div>';
      }).join('') + '</div>' : '<div class="note">Abhi koi complaint nahi.</div>';
      if (can && g.quote_id) {
        h += '<div class="sec-t" style="margin-top:12px">Nayi complaint</div><div class="fg" id="fxf">' + C.f('Samasya kya hai *', C.ta('issue', '', 'rows="2" maxlength="300"'), 'full') +
          C.f('Brand', C.inp('brand', '')) + C.f('Serial number', C.inp('serial', '')) + C.f('Kaun dekhega', C.sel('handler', ['Installer', 'Dealer', 'Manufacturer'], 'Installer')) + C.f('Priority', C.sel('priority', ['Normal', 'Urgent'], 'Normal')) +
          C.f('Tareekh', C.inp('c_date', C.today(), 'type="date"')) + C.f('Kis staff ko', '<select class="inp" name="assigned_to">' + users('', '— Chunein —') + '</select>') + C.f('Company ticket no. (agar ho)', C.inp('ticket_ref', '')) + '</div>' +
          '<div class="xs mute" style="margin-top:6px">Save karte hi ticket number banega aur "Aaj ke kaam" me yaad-dihani aayegi. Sab ticket solve hone par step ✓ ho jayega.</div>' +
          '<div style="margin-top:10px"><button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Ticket banayein</button></div>';
      }
      host.innerHTML = h;
      C.bind(host, {
        add: async function () {
          var f = $('#fxf', host), v = C.form(f); if (!C.need(f, ['issue'])) return;
          try { await C.run('crm_fr_save', { quote_id: g.quote_id, kind: 'complaint', status: 'Open', data: v, note: '' }, 'Ticket ban gaya ✔'); reopen(); } catch (e) {}
        },
        del: async function (id) {
          var why = await C.ask('Hatane ki wajah', 'Is ticket ko kyun hata rahe hain?', { min: 3, danger: true, ok: 'Hatao' }); if (why == null) return;
          try { await C.run('crm_fr_del', { id: +id, reason: why }, 'Hata diya'); reopen(); } catch (e) {}
        },
        upd: function (id) {
          var r = rows.filter(function (x) { return String(x.id) === String(id); })[0]; if (!r) return;
          var mm = C.modal({ title: 'Ticket ' + r.no, size: 'sm', body: '<div class="fg" id="fxu">' + C.f('Status', C.sel('status', ['Open', 'In progress', 'Resolved'], r.status), 'full') + C.f('Hal (Resolved ke liye zaroori)', C.ta('resolution', r.data.resolution || '', 'rows="2" maxlength="300"'), 'full') + C.f('Note', C.inp('note', '', 'maxlength="300"'), 'full') + '</div>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>' });
          $('[data-ok]', mm.el).onclick = async function () {
            var v = C.form($('#fxu', mm.el)), d = Object.assign({}, r.data, { resolution: v.resolution });
            try { await C.run('crm_fr_save', { id: r.id, quote_id: g.quote_id, kind: 'complaint', status: v.status, data: d, note: v.note }, 'Ticket update ✔'); mm.close(); reopen(); } catch (e) {}
          };
        }
      });
    }
  };

  /* ============================== Round 48 · customer ki ghoshna (declaration) — 22 aur 23 ============================== */
  var DSTAT = { pending: ['Customer ke jawab ka intezar', 'o'], accepted: ['Customer ne manzoor kiya', 'g'], auto: ['48 ghante baad apne aap manzoor', 'g'], issue: ['Customer ne dikkat batayi', 'r'] };
  var DTXT = {
    job: { t: 'Kaam poora hua — customer ki ghoshna', btn: 'Customer ko confirmation link banayein', ask: 'Link customer ko bhejein. Wo "Sab theek hai" dabaye to kaam poora maana jayega; 48 ghante me kuch na kare to apne aap manzoor ho jayega. Dikkat batayi to complaint ticket ban jayega.',
      wa: function (n, u) { return 'Namaste ' + n + ', Sunpowers ka kaam poora ho gaya hai. Kripya yahan dekhkar confirm karein: ' + u; } },
    self: { t: 'Khud lagane ki ghoshna', btn: 'Ghoshna link banayein', ask: 'Jo customer product khud lagayega (video dekhkar), usse ye ghoshna lein: "Maine install video dekhi, main khud lagaunga". Link bhejein.',
      wa: function (n, u) { return 'Namaste ' + n + ', product khud lagane ki ghoshna yahan bharein: ' + u; } }
  };
  function declUrl(tok) {
    var cfg = window.CRM_CONFIG || {}, live = ['sunpowers.in', 'www.sunpowers.in', 'store.sunpowers.in', 'admin.sunpowers.in', 'crm.sunpowers.in'].indexOf(location.hostname) >= 0;
    var b = (!live && cfg.SITE_URL_STAGING) || cfg.SITE_URL || C.siteUrl() || location.origin;
    return String(b).replace(/\/+$/, '') + '/job-confirm.html?t=' + tok + (live ? '' : '&e=s');   /* staging se bana link staging database padhta hai */
  }
  async function declBlock(host, g, s, reopen, kind) {
    var T = DTXT[kind], rows = await C.call('crm_decl_list', { quote_id: g.quote_id }).catch(function () { return []; });
    rows = rows.filter(function (r) { return r.kind === kind; });
    var party = null; try { party = await C.get(g.party_id); } catch (e) {}
    var can = s.can_edit, pend = rows.filter(function (r) { return r.status === 'pending'; })[0];
    var h = '<div class="sec-t">' + esc(T.t) + '</div>';
    if (!s.done && kind === 'job') h += '<div class="note">Pehle neeche kaam ka saar bharkar "Ye step poora hua" karein, phir customer ko link bhejein.</div>';
    h += rows.length ? '<div class="list">' + rows.map(function (r) {
      var st = DSTAT[r.status] || [r.status, ''];
      return '<div class="li" style="align-items:flex-start"><span class="grow"><span class="t">' + C.pill(st[0], st[1]) + '</span>' +
        '<span class="m"><span>' + esc(C.dt(r.created_at) || '') + '</span>' + (r.signer ? '<span>' + esc(r.signer) + '</span>' : '') + (r.status === 'pending' ? '<span>Auto: ' + esc(C.dt(r.due_at) || '') + '</span>' : '') + '</span>' +
        (r.issue ? '<span class="m"><span>Dikkat: ' + esc(r.issue) + '</span></span>' : '') + '</span></li>';
    }).join('') + '</div>' : '<div class="xs mute">Abhi koi ghoshna nahi bheji gayi.</div>';
    if (pend) {
      var u = declUrl(pend.token);
      h += '<div class="note" style="margin-top:8px;word-break:break-all">Link: <b>' + esc(u) + '</b></div><div class="row" style="gap:8px;flex-wrap:wrap;margin-top:6px">' +
        '<button class="btn btn-o btn-sm" data-act="dcopy">' + C.ic('copy') + ' Link copy</button>' +
        (party && party.mobile ? '<a class="btn btn-o btn-sm" target="_blank" rel="noopener" href="' + esc(C.wa(party.mobile, T.wa(party.title || '', u))) + '">' + C.ic('send') + ' WhatsApp</a>' : '') +
        (can ? '<button class="btn btn-o btn-sm" data-act="dmark">Phone par bataya — manzoor karein</button>' : '') + '</div>';
    } else if (can && (kind === 'self' || s.done)) {
      h += '<div class="xs mute" style="margin-top:8px">' + esc(T.ask) + '</div><div style="margin-top:8px"><button class="btn btn-p btn-sm" data-act="dnew">' + C.ic('send') + ' ' + esc(T.btn) + '</button></div>';
    }
    var box = document.createElement('div'); box.id = 'fxdecl'; box.innerHTML = h; host.appendChild(box);
    C.bind(box, {
      dnew: async function () { try { await C.run('crm_decl_new', { quote_id: g.quote_id, kind: kind }, 'Link ban gaya ✔'); reopen(); } catch (e) {} },
      dcopy: function () { C.copy(declUrl(pend.token), 'Link copy ho gaya ✔'); },
      dmark: async function () {
        var who = await C.ask('Manzoor karein', 'Customer ka naam (jisne phone par bataya)', { min: 2, ok: 'Manzoor' }); if (who == null) return;
        try { await C.run('crm_decl_mark', { id: pend.id, signer: who }, 'Manzoor ✔'); reopen(); } catch (e) {}
      }
    });
  }
  X[23] = { render: function (host, g, s, reopen) { return declBlock(host, g, s, reopen, 'job'); } };
  X[22] = { render: function (host, g, s, reopen) { return declBlock(host, g, s, reopen, 'self'); } };
})();
