/* Settings — company, bill details, numbering, accountant contacts, notices, privacy toggles, connections */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc;
  var PRIV = [['privacy.see_mobile', 'Doosron ke customer ka poora mobile number dekhe'], ['items.cost', 'Kharid rate / minimum rate dekhe'], ['customers.export', 'Customers ki Excel nikale'], ['leads.export', 'Leads ki Excel nikale'], ['customers.view_all', 'Sabke customers dekhe'], ['quotes.discount_any', 'Discount limit se upar de sake'], ['activity.view', 'Activity record dekhe']];
  var CONN = [['webhook', 'Webhook (koi bhi app)'], ['whatsapp', 'WhatsApp Business API'], ['sms', 'SMS (DLT)'], ['email', 'Email (SMTP / API)'], ['meta', 'Facebook / Instagram'], ['google', 'Google Business / Ads'], ['payment', 'Payment gateway'], ['other', 'Doosra']];

  function imgData(file, max) {
    return new Promise(function (res, rej) {
      var u = URL.createObjectURL(file), img = new Image();
      img.onload = function () { var s = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight)), c = document.createElement('canvas'); c.width = Math.round(img.naturalWidth * s); c.height = Math.round(img.naturalHeight * s); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(u); res(c.toDataURL('image/png')); };
      img.onerror = function () { rej(new Error('Photo padh nahi paye')); }; img.src = u;
    });
  }
  function signPad() {
    return new Promise(function (res) {
      var m = C.modal({ title: 'Sign karein', body: '<canvas class="sig" id="sg"></canvas><p class="hint" style="margin-top:6px">Ungli ya mouse se sign karein.</p>', foot: '<button class="btn btn-o" data-clr>Saaf karein</button><button class="btn btn-p" data-ok>Use karein</button>', onClose: function () { res(null); }, noFocus: true });
      var cv = $('#sg', m.el), r = cv.getBoundingClientRect(); cv.width = r.width * 2; cv.height = r.height * 2; var x = cv.getContext('2d'); x.scale(2, 2); x.lineWidth = 2.2; x.lineCap = 'round'; x.strokeStyle = '#0b2e1f';
      var dn = false, any = false; function pt(e) { var b = cv.getBoundingClientRect(); return [e.clientX - b.left, e.clientY - b.top]; }
      cv.addEventListener('pointerdown', function (e) { dn = true; any = true; var p = pt(e); x.beginPath(); x.moveTo(p[0], p[1]); cv.setPointerCapture(e.pointerId); });
      cv.addEventListener('pointermove', function (e) { if (!dn) return; var p = pt(e); x.lineTo(p[0], p[1]); x.stroke(); });
      cv.addEventListener('pointerup', function () { dn = false; });
      $('[data-clr]', m.el).onclick = function () { x.clearRect(0, 0, cv.width, cv.height); any = false; };
      $('[data-ok]', m.el).onclick = function () { if (!any) return C.toast('Pehle sign karein', true); var u = cv.toDataURL('image/png'); m.el.remove(); document.documentElement.style.overflow = ''; res(u); };
    });
  }

  C.mod('settings', {
    title: 'Settings',
    allowed: function () { return C.can('settings.manage'); },
    render: async function (el, params, q) {
      var S = C.clone(await C.settings(true)), co = S.company = S.company || {}, tab = q.tab || 'company';
      S.prefix = S.prefix || {}; S.accountants = S.accountants || []; S.secrets = S.secrets || {}; S.secrets.connections = S.secrets.connections || [];
      var tabs = [['company', 'Company'], ['bill', 'Bill / Quotation'], ['acc', 'Accountant'], ['notices', 'Notice board'], ['privacy', 'Privacy'], ['conn', 'Connections (API)']].concat(C.isAdmin() ? [['login', 'Login &amp; Email OTP'], ['backup', 'Backup']] : []);
      var h = '<div class="ph"><div><h1>Settings</h1><p>Company ki jaankari — quotation, bill aur rasid par yahi chhapti hai.</p></div></div><div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + t[1] + '</button>'; }).join('') + '</div><div id="tb"></div>';
      el.innerHTML = h;
      var tb = $('#tb', el), roleDefs = null;
      var saveBtn = '<div class="row" style="margin-top:16px;justify-content:flex-end"><button class="btn btn-p" data-act="save">' + C.ic('check') + ' Save karein</button></div>';
      function fi(k, l, attrs, cls) { return C.f(l, '<input class="inp" data-c="' + k + '" value="' + esc(co[k] || '') + '" ' + (attrs || '') + '>', cls); }
      function ta(k, l, rows) { return C.f(l, '<textarea class="inp" data-c="' + k + '" rows="' + (rows || 3) + '">' + esc(co[k] || '') + '</textarea>', 'full'); }
      async function draw() {
        if (tab === 'company') tb.innerHTML = '<div class="card"><div class="fg">' + fi('name', 'Company ka naam (chhota)') + fi('legal', 'Poora / legal naam (bill par)') + fi('phone', 'Phone') + fi('email', 'Email', 'type="email"') + fi('website', 'Website') + fi('store_url', 'Online Store link') + fi('gstin', 'GSTIN', 'maxlength="15" style="text-transform:uppercase"') + fi('pan', 'PAN', 'maxlength="10" style="text-transform:uppercase"') + fi('state', 'State') + ta('address', 'Pata', 2) + '</div>' +
          '<div class="sec-t">Logo aur sign</div><div class="grid g2"><div class="stack"><b class="sm">Logo</b><div id="lg">' + (co.logo ? '<img src="' + esc(co.logo) + '" style="max-height:70px;max-width:200px">' : '<p class="mute sm">Logo nahi hai</p>') + '</div><div class="row"><button class="btn btn-o btn-sm" data-act="logo">' + C.ic('upload') + ' Logo dalein</button>' + (co.logo ? '<button class="btn btn-g btn-sm" data-act="nologo">Hatayein</button>' : '') + '</div></div>' +
          '<div class="stack"><b class="sm">Sign / Stamp</b><div id="sgv">' + (co.sign ? '<img src="' + esc(co.sign) + '" style="max-height:60px;max-width:200px">' : '<p class="mute sm">Sign nahi hai</p>') + '</div><div class="row wrap"><button class="btn btn-o btn-sm" data-act="signup">' + C.ic('upload') + ' Photo</button><button class="btn btn-o btn-sm" data-act="signdraw">' + C.ic('edit') + ' Yahin sign karein</button>' + (co.sign ? '<button class="btn btn-g btn-sm" data-act="nosign">Hatayein</button>' : '') + '</div>' + fi('sign_label', 'Sign ke neeche likha', 'placeholder="Authorised Signatory"') + '</div></div></div>' + saveBtn;
        else if (tab === 'bill') tb.innerHTML = '<div class="card"><div class="sec-t" style="margin-top:0">Bank / UPI (bill par chhapega)</div><div class="fg">' + fi('bank_holder', 'Account holder') + fi('bank_name', 'Bank') + fi('bank_acc', 'Account no.') + fi('bank_ifsc', 'IFSC', 'style="text-transform:uppercase"') + fi('upi', 'UPI ID') + '</div>' +
          '<div class="sec-t">Terms</div><div class="fg">' + ta('terms_quote', 'Quotation ki terms (har nayi quotation me apne aap)', 5) + ta('terms', 'Bill ki terms', 4) + fi('powered', 'Sabse neeche chhota text', 'placeholder="Powered by : www.digidashland.in"', 'full') + '</div>' +
          '<div class="sec-t">Number series</div><div class="fg g3">' + [['quote', 'Quotation', 'QT'], ['invoice', 'Bill', 'INV'], ['payment', 'Rasid', 'RCPT'], ['purchase', 'Purchase', 'PO'], ['plant', 'Plant', 'PL']].map(function (x) { return C.f(x[1] + ' prefix', '<input class="inp" data-px="' + x[0] + '" value="' + esc(S.prefix[x[0]] || '') + '" placeholder="' + x[2] + '" maxlength="8" style="text-transform:uppercase">'); }).join('') + '</div><p class="hint" style="margin-top:6px">Number aisa banega: QT/26-27/0001 — har financial year (1 April) se naya.</p></div>' + saveBtn;
        else if (tab === 'acc') tb.innerHTML = '<div class="card"><div class="hd"><h3>Accountant / CA contacts</h3><button class="btn btn-o btn-sm" data-act="accadd">' + C.ic('plus') + ' Jodein</button></div><p class="mute sm" style="margin-bottom:12px">Har report par "Download &amp; Share to Accountant" dabane se inhi ko WhatsApp / Email jayega. Hum accounting / GST filing nahi karte — sirf report bhejte hain.</p><div class="stack" id="accl">' + (S.accountants.length ? S.accountants.map(function (a, i) { return '<div class="fg g3" style="align-items:end;border:1px solid var(--line);border-radius:12px;padding:12px"><div class="f"><label>Naam</label><input class="inp" data-acc="' + i + '" data-k="name" value="' + esc(a.name || '') + '"></div><div class="f"><label>WhatsApp mobile</label><input class="inp" data-acc="' + i + '" data-k="mobile" value="' + esc(a.mobile || '') + '" inputmode="tel"></div><div class="f"><label>Email</label><div class="row"><input class="inp" data-acc="' + i + '" data-k="email" value="' + esc(a.email || '') + '" type="email"><button class="btn btn-r btn-icon" data-act="accdel" data-id="' + i + '" aria-label="Hatayein">' + C.ic('trash') + '</button></div></div></div>'; }).join('') : C.empty('user', 'Koi accountant nahi', '"Jodein" dabayein')) + '</div></div>' + saveBtn;
        else if (tab === 'notices') { var ns = await C.list('notice', { limit: 100 }); tb.innerHTML = '<div class="card"><h3 style="margin-bottom:10px">Naya notice (sab users ke Home par dikhega)</h3><div class="stack">' + C.f('Heading', '<input class="inp" id="nt" maxlength="120">') + C.f('Detail', '<textarea class="inp" id="nb" rows="3"></textarea>') + '<div class="row" style="justify-content:flex-end"><button class="btn btn-p" data-act="nadd">' + C.ic('megaphone') + ' Notice lagayein</button></div></div></div><div class="list" style="margin-top:14px">' + (ns.length ? ns.map(function (n) { return '<div class="li"><span class="av o">' + C.ic('megaphone') + '</span><span class="grow"><span class="t">' + esc(n.title) + '</span><span class="m"><span>' + esc(n.data.body || '') + '</span><span>' + esc(C.fd(n.created_at)) + '</span></span></span><button class="btn btn-g btn-icon btn-sm" data-act="ndel" data-id="' + n.id + '">' + C.ic('trash') + '</button></div>'; }).join('') : C.empty('megaphone', 'Koi notice nahi')) + '</div>'; tb._ns = ns; }
        else if (tab === 'privacy') {
          if (!C.isAdmin()) { tb.innerHTML = '<div class="card">' + C.empty('lock', 'Sirf Admin badal sakta hai') + '</div>'; return; }
          roleDefs = roleDefs || (await C.call('crm_roles_get', {})).roles || {};
          var R = ['manager', 'staff', 'dealer', 'influencer'];
          tb.innerHTML = '<div class="card"><p class="mute sm" style="margin-bottom:12px">Privacy wali cheezein — tick = dikhega / kar sakta hai. (Baaki saari permission: Team → Role permission)</p><div class="tw"><table class="t"><thead><tr><th>Kya</th>' + R.map(function (r) { return '<th style="text-align:center">' + C.ROLE[r] + '</th>'; }).join('') + '</tr></thead><tbody>' + PRIV.map(function (p) { return '<tr><td>' + esc(p[1]) + '</td>' + R.map(function (r) { return '<td style="text-align:center"><input type="checkbox" style="width:20px;height:20px;accent-color:var(--leaf)" data-pv="' + r + '|' + p[0] + '"' + ((roleDefs[r] || {})[p[0]] ? ' checked' : '') + '></td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div><div class="row" style="margin-top:14px;justify-content:flex-end"><button class="btn btn-p" data-act="psave">' + C.ic('check') + ' Save karein</button></div></div>';
        } else if (tab === 'login') {
          var A = await C.call('crm_auth_admin_get', {}), au = A.auth || {}, u = au.urls || {};
          tb._A = A;
          tb.innerHTML = '<div class="grid g2"><div class="card"><h3 style="margin-bottom:10px">Admin login email</h3><div class="stack">' + C.f('OTP isi email par jayega (primary)', '<input class="inp" id="lgE1" type="email" value="' + esc(A.email) + '">') + C.f('Backup email <span class="o">(sirf "backup par bhejein" dabane par)</span>', '<input class="inp" id="lgE2" type="email" value="' + esc(A.email2) + '">') +
            C.f('Email kiske naam se jaye (From)', '<input class="inp" id="lgFrom" value="' + esc(au.from || 'Sunpowers <no-reply@sunpowers.in>') + '"><span class="hint">Resend me domain verify hone ke baad: Sunpowers &lt;no-reply@sunpowers.in&gt;</span>') + '</div>' +
            '<div class="sec-t">PIN reset link kis address par khule</div><div class="stack">' + C.f('Online Store (Main App)', '<input class="inp" id="lgU1" value="' + esc(u.store || '') + '">') + C.f('CRM', '<input class="inp" id="lgU2" value="' + esc(u.crm || '') + '">') + C.f('Store Admin', '<input class="inp" id="lgU3" value="' + esc(u.admin || '') + '">') + '</div>' +
            '<div class="sec-t">Resend API key</div><p class="sm" style="margin-bottom:8px">' + (A.key_set ? C.pill('Key set hai ✔') : C.pill('Key nahi hai', 'r')) + ' ' + (A.pg_net ? C.pill('pg_net chalu ✔') : C.pill('pg_net band hai', 'r')) + '</p><input class="inp" id="lgKey" type="password" autocomplete="off" placeholder="Nayi key daalni ho to yahan (re_...) — warna khaali chhodein">' +
            '<div class="row wrap" style="margin-top:16px"><input class="inp" id="lgPin" type="password" inputmode="numeric" maxlength="6" placeholder="Apna 6 ank ka PIN" style="max-width:200px"><button class="btn btn-p" data-act="lgsave">' + C.ic('check') + ' Save karein</button></div></div>' +
            '<div class="card"><div class="hd"><h3>Email check</h3><button class="btn btn-o btn-sm" data-act="lgtest">' + C.ic('send') + ' Test email bhejein</button></div><p class="mute sm" style="margin-bottom:10px">Test email primary email par jayega. 5–10 second me status yahan dikhega.</p><div id="lgStat"></div><div class="sec-t">Aakhri 20 email</div>' +
            (A.log.length ? '<div class="list">' + A.log.map(function (l) { return '<div class="li"><span class="grow"><span class="t" style="font-size:14px">' + esc(l.subject) + '</span><span class="m"><span>' + esc(l.to) + '</span><span>' + esc(C.fdt(l.at)) + '</span>' + (l.note ? '<span style="color:var(--red)">' + esc(l.note) + '</span>' : '') + '</span></span>' + (l.request_id ? '<button class="btn btn-g btn-sm" data-act="lgchk" data-id="' + l.request_id + '">Status</button>' : '') + '</div>'; }).join('') + '</div>' : '<p class="mute sm">Abhi koi email nahi gaya.</p>') + '</div></div>';
        } else if (tab === 'backup') {
          tb.innerHTML = '<div class="card"><h3 style="margin-bottom:6px">' + C.ic('download') + ' Poora backup</h3><p class="mute sm" style="margin-bottom:12px">Ek click me saara data ek <b>.zip</b> file me: customers, leads, quotation, bill, payment, products, team, documents (files), Online Store ke orders, poochtaachh aur store ki settings. Andar <b>backup.json</b> (poora data) + <b>backup.xlsx</b> (Excel me padhne ke liye) + <b>files/</b> folder.</p>' +
            '<div class="note g" style="margin-bottom:12px">Har hafte ek baar backup lekar Google Drive / pen drive me rakhein. Password, PIN aur API key backup me <b>nahi</b> jaate (suraksha ke liye).</div>' +
            '<label class="row" style="gap:8px;margin-bottom:12px"><input type="checkbox" id="bkF" checked> Documents ki files bhi (badi ho sakti hai)</label>' +
            '<div class="row wrap"><input class="inp" id="bkPin" type="password" inputmode="numeric" maxlength="6" placeholder="Apna 6 ank ka PIN" style="max-width:200px"><button class="btn btn-p" data-act="bkgo">' + C.ic('download') + ' Backup download karein</button></div><div id="bkStat" class="sm" style="margin-top:12px"></div></div>';
        } else if (tab === 'conn') tb.innerHTML = '<div class="card"><div class="hd"><h3>Doosre apps se jodein</h3><button class="btn btn-o btn-sm" data-act="cadd">' + C.ic('plus') + ' Connection jodein</button></div><div class="note g" style="margin-bottom:12px">' + C.ic('key') + ' Yahan sirf <b>API key / link</b> daalein — code badalne ki zaroorat nahi. Ye keys sirf Admin dekh sakta hai. Facebook / Instagram / Google ke liye kabhi ID-password na daalein — official "Connect" (Marketing &amp; Grow, Phase 4) se judega.</div><div class="stack" id="cl">' + (S.secrets.connections.length ? S.secrets.connections.map(function (c, i) { return '<div style="border:1px solid var(--line);border-radius:12px;padding:12px"><div class="fg"><div class="f"><label>Naam</label><input class="inp" data-cn="' + i + '" data-k="name" value="' + esc(c.name || '') + '"></div><div class="f"><label>Prakar</label><select class="inp" data-cn="' + i + '" data-k="type">' + C.opts(CONN, c.type) + '</select></div><div class="f"><label>Link / URL</label><input class="inp" data-cn="' + i + '" data-k="url" value="' + esc(c.url || '') + '"></div><div class="f"><label>API key / token</label><input class="inp" data-cn="' + i + '" data-k="key" value="' + esc(c.key || '') + '" type="password" autocomplete="off"></div><div class="f full"><label>Note</label><div class="row"><input class="inp" data-cn="' + i + '" data-k="note" value="' + esc(c.note || '') + '"><label class="ck nowrap"><input type="checkbox" data-cn="' + i + '" data-k="on"' + (c.on !== false ? ' checked' : '') + '> Chalu</label><button class="btn btn-r btn-icon" data-act="cdel" data-id="' + i + '">' + C.ic('trash') + '</button></div></div></div></div>'; }).join('') : C.empty('link', 'Abhi koi connection nahi', 'Jaise: WhatsApp API, SMS, webhook (Zapier / Make / Pabbly)')) + '</div></div>' + saveBtn;
      }
      await draw();
      el.addEventListener('click', function (e) { var t = e.target.closest('[data-tab]'); if (t) C.go('#/settings?tab=' + t.getAttribute('data-tab')); });
      tb.addEventListener('input', function (e) {
        var t = e.target, k;
        if ((k = t.getAttribute('data-c'))) co[k] = t.value;
        else if ((k = t.getAttribute('data-px'))) S.prefix[k] = t.value.toUpperCase().replace(/[^A-Z0-9-]/g, '');
        else if (t.hasAttribute('data-acc')) S.accountants[+t.getAttribute('data-acc')][t.getAttribute('data-k')] = t.value;
        else if (t.hasAttribute('data-cn')) S.secrets.connections[+t.getAttribute('data-cn')][t.getAttribute('data-k')] = t.type === 'checkbox' ? t.checked : t.value;
      });
      tb.addEventListener('change', function (e) { var t = e.target; if (t.hasAttribute('data-cn')) S.secrets.connections[+t.getAttribute('data-cn')][t.getAttribute('data-k')] = t.type === 'checkbox' ? t.checked : t.value; });
      function pick(cb) { var i = document.createElement('input'); i.type = 'file'; i.accept = 'image/*'; i.onchange = async function () { try { cb(await imgData(i.files[0], 420)); } catch (e) { C.toast(e.message, true); } }; i.click(); }
      async function save(msg) {
        if (co.gstin) co.gstin = co.gstin.toUpperCase(); if (co.pan) co.pan = co.pan.toUpperCase();
        S.accountants = S.accountants.filter(function (a) { return (a.name || a.mobile || a.email); });
        for (var i = 0; i < S.accountants.length; i++) if (S.accountants[i].mobile && !C.validMob(S.accountants[i].mobile)) return C.toast('Accountant ka mobile sahi likhein', true);
        try { await C.run('crm_settings_save', { data: S }, msg || 'Settings save ho gayi ✔'); C.cache.settings = C.clone(S); draw(); } catch (e) {}
      }
      async function mailStatus(id) { var x = await C.call('crm_auth_mail_status', { request_id: id }); var ok = x.status_code >= 200 && x.status_code < 300; return x.pending ? C.pill('Bhej rahe hain…', 'o') : ok ? C.pill('Pahunch gaya ✔ (' + x.status_code + ')') : C.pill('Fail ' + (x.status_code || '') , 'r') + ' <span class="xs mute">' + esc(x.error_msg || x.content || '') + '</span>'; }
      C.bind(el, {
        lgsave: async function () { var pin = $('#lgPin', tb).value; if (pin.length !== 6) return C.toast('Apna 6 ank ka PIN daalein', true); C.busy(true); try { var r = await C.call('crm_auth_admin_save', { pin: pin, email: $('#lgE1', tb).value, email2: $('#lgE2', tb).value, resend_key: $('#lgKey', tb).value, auth: { from: $('#lgFrom', tb).value, urls: { store: $('#lgU1', tb).value.trim(), crm: $('#lgU2', tb).value.trim(), admin: $('#lgU3', tb).value.trim() } } }); if (r && r.error) throw new Error(r.error); C.toast('Login settings save ✔'); draw(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); } },
        lgtest: async function () { try { var r = await C.run('crm_auth_test_mail', {}, 'Test email bheja'); var box = $('#lgStat', tb); box.innerHTML = C.pill('Bhej rahe hain…', 'o'); setTimeout(async function () { try { box.innerHTML = await mailStatus(r.request_id); } catch (e) { box.textContent = e.message; } }, 4000); } catch (e) {} },
        bkgo: async function () {
          var pin = $('#bkPin', tb).value, st = $('#bkStat', tb), withF = $('#bkF', tb).checked;
          if (!/^\d{6}$/.test(pin)) return C.toast('Apna 6 ank ka PIN daalein', true);
          C.busy(true); st.textContent = 'Shuru…';
          try {
            var meta = await C.call('crm_backup', { pin: pin, part: 'meta' }); if (meta.error) throw new Error(meta.error);
            var out = { meta: meta }, files = [];
            for (var i = 0; i < meta.parts.length; i++) {
              var part = meta.parts[i]; if (meta.counts[part] == null) continue; if (part === 'crm_files' && !withF) continue;
              var off = 0, rows = [];
              while (off != null) {
                st.textContent = 'Le rahe hain: ' + part + ' (' + rows.length + ' / ' + meta.counts[part] + ')';
                var r = await C.call('crm_backup', { pin: pin, part: part, offset: off }); if (r.error) throw new Error(r.error);
                rows = rows.concat(r.rows); off = r.next;
              }
              if (part === 'crm_files') rows.forEach(function (f) { var bin = atob(f.b64), u = new Uint8Array(bin.length); for (var k = 0; k < bin.length; k++) u[k] = bin.charCodeAt(k); var ext = (String(f.mime).split('/')[1] || 'bin').replace(/[^a-z0-9]/gi, '').slice(0, 5); files.push({ name: 'files/' + f.id + '-rec' + f.rec_id + '.' + ext, data: u }); delete f.b64; });
              out[part] = rows;
            }
            st.textContent = 'Zip bana rahe hain…';
            var sheets = [], cell = function (v) { return v == null ? '' : typeof v === 'object' ? JSON.stringify(v) : v; };
            function sheet(name, rows) { if (!rows || !rows.length) return; var ks = []; rows.forEach(function (o) { Object.keys(o).forEach(function (k) { if (ks.indexOf(k) < 0) ks.push(k); }); }); sheets.push({ name: name.slice(0, 30), rows: [ks].concat(rows.map(function (o) { return ks.map(function (k) { return cell(o[k]); }); })), widths: ks.map(function () { return 16; }) }); }
            var byKind = {}; (out.crm_records || []).forEach(function (x) { (byKind[x.kind] = byKind[x.kind] || []).push(x); });
            sheet('Team users', out.crm_users); Object.keys(byKind).sort().forEach(function (k) { sheet('CRM ' + k, byKind[k]); });
            sheet('Store orders', out.sp_orders); sheet('Store enquiries', out.sp_enquiries); sheet('Activity', out.crm_activity); sheet('Files list', out.crm_files);
            var xl = window.XLSXLite.write(sheets.length ? sheets : [{ name: 'Khaali', rows: [['Koi data nahi']] }]);
            var zip = window.XLSXLite.zip([{ name: 'backup.json', data: JSON.stringify(out) }, { name: 'backup.xlsx', data: new Uint8Array(await xl.arrayBuffer()) }, { name: 'PADHEIN.txt', data: 'Sunpowers backup ' + meta.at + '\r\nbackup.json = poora data (wapas lane ke liye)\r\nbackup.xlsx = Excel me padhne ke liye\r\nfiles/ = documents\r\n' }].concat(files));
            C.download(zip, 'sunpowers-backup-' + C.today() + '.zip');
            st.innerHTML = C.pill('Backup ho gaya ✔') + ' ' + esc(Object.keys(meta.counts).map(function (k) { return k + ': ' + meta.counts[k]; }).join(' • '));
            $('#bkPin', tb).value = '';
          } catch (e) { st.innerHTML = '<span style="color:var(--red)">' + esc(e.message) + '</span>'; C.toast(e.message, true); } finally { C.busy(false); }
        },
        lgchk: async function (id, b) { try { b.outerHTML = await mailStatus(+id); } catch (e) { C.toast(e.message, true); } },
        save: function () { save(); },
        logo: function () { pick(function (u) { co.logo = u; draw(); }); }, nologo: function () { co.logo = ''; draw(); },
        signup: function () { pick(function (u) { co.sign = u; draw(); }); }, signdraw: async function () { var u = await signPad(); if (u) { co.sign = u; draw(); } }, nosign: function () { co.sign = ''; draw(); },
        accadd: function () { S.accountants.push({ name: '', mobile: '', email: '' }); draw(); var x = $$('[data-acc][data-k=name]', tb); if (x.length) x[x.length - 1].focus(); },
        accdel: function (i) { S.accountants.splice(+i, 1); draw(); },
        cadd: function () { S.secrets.connections.push({ name: '', type: 'webhook', url: '', key: '', note: '', on: true }); draw(); },
        cdel: function (i) { S.secrets.connections.splice(+i, 1); draw(); },
        nadd: async function () { var t = $('#nt', tb).value.trim(), b = $('#nb', tb).value.trim(); if (!t) return C.toast('Heading likhein', true); try { await C.save('notice', null, { title: t, body: b }, {}, 'Notice lag gaya ✔'); draw(); } catch (e) {} },
        ndel: async function (id) { var n = (tb._ns || []).find(function (x) { return String(x.id) === id; }); if (n && await C.delWithReason(n, 'Notice')) draw(); },
        psave: async function () {
          var R = {}; $$('[data-pv]', tb).forEach(function (c) { var a = c.getAttribute('data-pv').split('|'); R[a[0]] = R[a[0]] || Object.assign({}, roleDefs[a[0]] || {}); if (c.checked) R[a[0]][a[1]] = true; else delete R[a[0]][a[1]]; });
          C.busy(true); try { for (var r in R) await C.call('crm_role_save', { role: r, perms: R[r] }); C.toast('Privacy save ho gayi ✔'); roleDefs = null; await draw(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
        }
      });
    }
  });
})();
