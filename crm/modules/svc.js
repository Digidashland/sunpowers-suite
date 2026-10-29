/* Round 51 — (1) Settings > Services & Limits (sirf Admin)   (2) Customer Chhupayein / Hamesha ke liye hatayein (sirf Admin; bill kabhi nahi chhute) */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc;
  var AUTO = [['', 'Manual (main bharunga)'], ['db_mb', 'Auto: Supabase database size (MB)'], ['files_mb', 'Auto: CRM files + storage (MB)'], ['mail_day', 'Auto: Email aaj (CRM ke bheje)'], ['mail_month', 'Auto: Email is mahine (CRM ke bheje)']];
  var STALE_DAYS = 35;

  function nf(n) { if (n == null || n === '') return '—'; n = +n; return n >= 1000 ? n.toLocaleString('en-IN', { maximumFractionDigits: 1 }) : String(Math.round(n * 10) / 10); }
  function ago(d) { if (!d) return null; var t = new Date(d + 'T00:00:00'), n = new Date(); return Math.floor((n - t) / 864e5); }
  function fdate(d) { return d ? d.split('-').reverse().join('-') : ''; }

  /* ---------- local state machine for the tab ---------- */
  C.svcTab = async function (tb) {
    var SV, DEF, edit = {}, dirty = false;
    async function load() { C.busy(true); try { var r = await C.call('crm_services_get', {}); SV = r.services; DEF = r.defaults; dirty = false; } finally { C.busy(false); } }
    try { await load(); } catch (e) { tb.innerHTML = '<div class="card"><div class="note r">Ye hissa abhi database me nahi laga (Round 51 SQL chalayein): ' + esc(e.message) + '</div></div>'; return; }
    function recalc(m) { /* instant feedback while typing (server recomputes on save) */
      if (m.type === 'date') { var d = m.used ? Math.floor((new Date(m.used + 'T00:00:00') - new Date(new Date().toDateString())) / 864e5) : null; m.days_left = d; m.state = d == null ? 'none' : d <= 0 ? 'over' : d <= 30 ? 'warn' : 'ok'; return; }
      if (!m.auto) m.val = m.used === '' || m.used == null ? null : +m.used;
      m.pct = m.val != null && +m.limit > 0 ? Math.round(m.val * 1000 / m.limit) / 10 : null;
      m.state = m.pct == null ? 'none' : m.pct >= 100 ? 'over' : m.pct >= 80 ? 'warn' : 'ok';
    }
    function bar(m) {
      if (m.type === 'date') {
        if (m.days_left == null) return '<span class="mute sm">Date bharein</span>';
        return '<b class="sv-' + m.state + '">' + (m.days_left <= 0 ? 'Expire ho chuka (' + fdate(m.used) + ')' : fdate(m.used) + ' — ' + m.days_left + ' din baaki') + '</b>';
      }
      var p = m.pct == null ? 0 : Math.min(100, m.pct);
      return '<div class="svbar"><i class="sv-' + m.state + '" style="width:' + p + '%"></i></div><div class="svnum"><b>' + nf(m.val) + '</b> / ' + nf(m.limit) + ' ' + esc(m.unit || '') + (m.pct != null ? ' · <b class="sv-' + m.state + '">' + m.pct + '%</b>' : '') + '</div>';
    }
    function mrow(si, mi, m) {
      var isAuto = !!m.auto, st = m.state === 'over' ? C.pill('Limit paar', 'r') : m.state === 'warn' ? C.pill('Paas aa gaya', 'o') : m.state === 'ok' ? C.pill('Theek', '') : C.pill('Bhara nahi', 'g');
      var meta = isAuto ? '<span class="pill b">Auto</span>' : (m.used ? '<span class="xs mute">Aapne bhara: ' + fdate(m.at) + '</span>' : '');
      var a = ago(m.at); if (!isAuto && m.used && a != null && a > STALE_DAYS) meta += ' <span class="pill o">⏰ ' + a + ' din purana — dobara check karein</span>';
      var input = isAuto ? '' : (m.type === 'date' ? '<input class="inp svin" type="date" data-sm="' + si + '|' + mi + '|used" data-chg value="' + esc(m.used || '') + '">' : '<input class="inp svin" inputmode="decimal" placeholder="Abhi kitna use hua" data-sm="' + si + '|' + mi + '|used" data-chg value="' + esc(m.used == null ? '' : m.used) + '">');
      return '<div class="svm"><div class="svh"><span class="grow"><b>' + esc(m.label) + '</b>' + (m.hint ? '<span class="xs mute" style="display:block">' + esc(m.hint) + '</span>' : '') + '</span>' + st + '</div>' + bar(m) + '<div class="row wrap" style="margin-top:6px;gap:8px">' + input + meta + '</div></div>';
    }
    function editMetric(si, mi, m) {
      return '<div class="svm svedit"><div class="fg">' + C.f('Naam', '<input class="inp" data-sm="' + si + '|' + mi + '|label" value="' + esc(m.label || '') + '">') + C.f('Unit', '<input class="inp" data-sm="' + si + '|' + mi + '|unit" value="' + esc(m.unit || '') + '" placeholder="GB / MB / emails">') +
        (m.type === 'date' ? '' : C.f('Free limit', '<input class="inp" inputmode="decimal" data-sm="' + si + '|' + mi + '|limit" value="' + esc(m.limit == null ? '' : m.limit) + '">')) +
        C.f('Kaise bhare', '<select class="inp" data-sm="' + si + '|' + mi + '|auto" data-chg>' + AUTO.map(function (o) { return '<option value="' + o[0] + '"' + ((m.auto || '') === o[0] ? ' selected' : '') + (m.type === 'date' && o[0] ? ' disabled' : '') + '>' + o[1] + '</option>'; }).join('') + '</select>') +
        C.f('Type', '<select class="inp" data-sm="' + si + '|' + mi + '|type" data-chg><option value="num"' + (m.type === 'date' ? '' : ' selected') + '>Number (limit ke saath)</option><option value="date"' + (m.type === 'date' ? ' selected' : '') + '>Date (expiry / renewal)</option></select>') +
        C.f('Madad ka note', '<input class="inp" data-sm="' + si + '|' + mi + '|hint" value="' + esc(m.hint || '') + '">', 'full') + '</div>' +
        '<div class="row" style="justify-content:flex-end"><button class="btn btn-g btn-sm" data-act="mdel" data-id="' + si + '|' + mi + '">' + C.ic('trash') + ' Ye line hatayein</button></div></div>';
    }
    function card(s, si) {
      var ed = edit[si], top = '<div class="hd"><h3>' + esc(s.name) + (s.plan ? ' <span class="pill g">' + esc(s.plan) + '</span>' : '') + '</h3><div class="row wrap">' + (ed ? '<button class="btn btn-o btn-sm" data-act="sdone" data-id="' + si + '">' + C.ic('check') + ' Edit band</button><button class="btn btn-g btn-sm" data-act="sdel" data-id="' + si + '">' + C.ic('trash') + ' Poori service hatayein</button>' : '<button class="btn btn-o btn-sm" data-act="sedit" data-id="' + si + '">' + C.ic('edit') + ' Edit</button>') + '</div></div>';
      var links = (s.links || []).map(function (l) { return '<a class="btn btn-o btn-sm" target="_blank" rel="noopener noreferrer" href="' + esc(l.u) + '">' + C.ic('link') + ' ' + esc(l.t) + '</a>'; }).join('');
      var body;
      if (ed) {
        body = '<div class="fg">' + C.f('Service ka naam', '<input class="inp" data-sv="' + si + '|name" value="' + esc(s.name || '') + '">') + C.f('Plan', '<input class="inp" data-sv="' + si + '|plan" value="' + esc(s.plan || '') + '" placeholder="Free / Pro">') + C.f('Kis kaam ke liye', '<input class="inp" data-sv="' + si + '|what" value="' + esc(s.what || '') + '">', 'full') + C.f('Note (koi password / API key nahi)', '<input class="inp" data-sv="' + si + '|note" value="' + esc(s.note || '') + '">', 'full') + '</div>' +
          '<div class="sec-t">Official links (sirf https://)</div>' + (s.links || []).map(function (l, li) { return '<div class="row" style="gap:8px;margin-bottom:6px"><input class="inp" style="max-width:150px" placeholder="Naam" data-sl="' + si + '|' + li + '|t" value="' + esc(l.t) + '"><input class="inp" placeholder="https://…" data-sl="' + si + '|' + li + '|u" value="' + esc(l.u) + '"><button class="btn btn-g btn-sm" data-act="ldel" data-id="' + si + '|' + li + '">' + C.ic('x') + '</button></div>'; }).join('') + '<button class="btn btn-o btn-sm" data-act="ladd" data-id="' + si + '">' + C.ic('plus') + ' Link jodein</button>' +
          '<div class="sec-t" style="margin-top:12px">Kya-kya naapna hai</div>' + (s.metrics || []).map(function (m, mi) { return editMetric(si, mi, m); }).join('') + '<button class="btn btn-o btn-sm" data-act="madd" data-id="' + si + '">' + C.ic('plus') + ' Naya naapne ki line (limit)</button>';
      } else {
        body = (s.what ? '<p class="mute sm" style="margin-bottom:8px">' + esc(s.what) + '</p>' : '') + (links ? '<div class="row wrap" style="gap:6px;margin-bottom:10px">' + links + '</div>' : '') + (s.metrics || []).map(function (m, mi) { return mrow(si, mi, m); }).join('') + (s.note ? '<p class="xs mute" style="margin-top:8px">' + esc(s.note) + '</p>' : '');
        if (!(s.metrics || []).length) body += '<p class="mute sm">Abhi koi limit nahi judi — Edit dabakar jodein.</p>';
      }
      return '<div class="card svc">' + top + body + '</div>';
    }
    function alerts() { var n = 0; SV.forEach(function (s) { (s.metrics || []).forEach(function (m) { if (m.state === 'warn' || m.state === 'over') n++; }); }); return n; }
    function draw() {
      var n = alerts();
      tb.innerHTML = '<div class="card"><div class="hd"><h3>' + C.ic('activity') + ' Services &amp; Limits</h3><div class="row wrap"><button class="btn btn-o btn-sm" data-act="sreload">' + C.ic('refresh') + ' Taaza karein</button><button class="btn btn-o btn-sm" data-act="sadd">' + C.ic('plus') + ' Nayi service jodein</button><button class="btn btn-o btn-sm" data-act="sreset">Default limits wapas</button><button class="btn btn-p btn-sm" data-act="ssave"' + (dirty ? '' : '') + '>' + C.ic('check') + ' Save karein' + (dirty ? ' •' : '') + '</button></div></div>' +
        '<p class="mute sm" style="margin-bottom:10px">Aapke system me kaun-kaun si service judi hai, uski official link, free limit aur ab tak kitna use hua — sab ek jagah. Limit <b>80%</b> par pahunchte hi (ya domain expiry se 30 din pehle) yahan aur 🔔 bell me Admin ko dikhega.</p>' +
        (n ? '<div class="note o" style="margin-bottom:10px"><b>' + n + ' cheez dhyan maangti hai</b> — laal / peeli patti dekhein.</div>' : '<div class="note g" style="margin-bottom:10px">Abhi sab theek hai ✔</div>') +
        '<div class="note" style="margin-bottom:0"><b>Kaun apne aap, kaun aap bharenge:</b> <span class="pill b">Auto</span> = Supabase database, CRM files, Email ginti — system khud naapta hai. Vercel, Cloudinary, Supabase egress jaise ka use browser se surakshit tareeke se nahi nikalta (uske liye unki secret API key chahiye, jo yahan rakhna theek nahi) — us service ki link se dashboard khol kar number yahan bhar dein; <b>bharte hi</b> bar aur alert chalu. <b>Yahan kabhi password / API key na likhein.</b> Free limits company ki official site ke hisaab se bhari hain, badal sakte hain — aap kabhi bhi edit karein.</div></div>' +
        SV.map(card).join('') + (SV.length ? '' : '<div class="card">' + C.empty('activity', 'Koi service nahi', '"Default limits wapas" ya "Nayi service jodein" dabayein') + '</div>');
    }
    function sv(i) { return SV[+i]; }
    function setPath(o, path, v) { o[path] = v; }
    draw();
    tb.addEventListener('input', function (e) {
      var t = e.target, a;
      if ((a = t.getAttribute('data-sv'))) { a = a.split('|'); sv(a[0])[a[1]] = t.value; dirty = true; }
      else if ((a = t.getAttribute('data-sl'))) { a = a.split('|'); sv(a[0]).links[+a[1]][a[2]] = t.value; dirty = true; }
      else if ((a = t.getAttribute('data-sm')) && !t.hasAttribute('data-chg')) { a = a.split('|'); var m = sv(a[0]).metrics[+a[1]]; m[a[2]] = t.value; dirty = true; }
    });
    tb.addEventListener('change', function (e) {
      var t = e.target, a = t.getAttribute('data-sm'); if (!a || !t.hasAttribute('data-chg')) return;
      a = a.split('|'); var m = sv(a[0]).metrics[+a[1]];
      if (a[2] === 'type') { m.type = t.value === 'date' ? 'date' : undefined; if (m.type === 'date') m.auto = ''; m.used = ''; }
      else if (a[2] === 'auto') { m.auto = t.value; if (m.auto) m.used = ''; }
      else m[a[2]] = t.value;
      recalc(m); dirty = true; draw();
    });
    C.bind(tb, {
      sedit: function (i) { edit[i] = true; draw(); },
      sdone: function (i) { delete edit[i]; (sv(i).metrics || []).forEach(recalc); draw(); },
      sdel: async function (i) { if (!(await C.confirm('"' + sv(i).name + '" poori hata dein? (Save karne par pakka hoga)', 'Hatao', true))) return; SV.splice(+i, 1); edit = {}; dirty = true; draw(); },
      sadd: function () { SV.push({ id: '', name: 'Nayi service', plan: '', what: '', links: [], metrics: [{ k: 'm1', label: 'Storage', unit: 'GB', limit: 10, used: '' }] }); edit[SV.length - 1] = true; dirty = true; draw(); },
      ladd: function (i) { sv(i).links = sv(i).links || []; sv(i).links.push({ t: '', u: 'https://' }); dirty = true; draw(); },
      ldel: function (id) { var a = id.split('|'); sv(a[0]).links.splice(+a[1], 1); dirty = true; draw(); },
      madd: function (i) { sv(i).metrics = sv(i).metrics || []; sv(i).metrics.push({ k: 'm' + (sv(i).metrics.length + 1) + Math.floor(Math.random() * 99), label: '', unit: '', limit: '', used: '' }); dirty = true; draw(); },
      mdel: function (id) { var a = id.split('|'); sv(a[0]).metrics.splice(+a[1], 1); dirty = true; draw(); },
      sreload: async function () { if (dirty && !(await C.confirm('Bina save kiye badlav jaa sakte hain. Taaza karein?', 'Haan taaza karo'))) return; edit = {}; await load(); draw(); },
      sreset: async function () { if (!(await C.confirm('Saari services ko company ki default free limits par wapas laayein? (Aapke bhare hue numbers mit jayenge; Save karne par pakka hoga)', 'Haan wapas karo', true))) return; SV = JSON.parse(JSON.stringify(DEF)); SV.forEach(function (s) { (s.metrics || []).forEach(function (m) { m.state = 'none'; }); }); edit = {}; dirty = true; draw(); },
      ssave: async function () {
        var bad = SV.find(function (s) { return !String(s.name || '').trim() || String(s.name).trim().length < 2; }); if (bad) return C.toast('Har service ka naam likhein', true);
        var payload = SV.map(function (s) { return { id: s.id, name: s.name, what: s.what, plan: s.plan, note: s.note, links: (s.links || []).filter(function (l) { return l.t && /^https:\/\//i.test(l.u || ''); }), metrics: (s.metrics || []).map(function (m) { return { k: m.k, label: m.label || m.k, unit: m.unit, type: m.type, limit: m.limit, auto: m.auto || '', hint: m.hint, used: m.auto ? '' : (m.used == null ? '' : String(m.used)) }; }) }; });
        C.busy(true); try { var r = await C.call('crm_services_save', { services: payload }); SV = r.services; edit = {}; dirty = false; C.toast('Services & Limits save ✔'); draw(); if (C.pulseNow) C.pulseNow(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
      }
    });
  };
  /* tab par laal bindi (sirf Admin, chup-chap) */
  C.svcDot = async function (btn) { try { var r = await C.call('crm_services_get', {}), n = 0; (r.services || []).forEach(function (s) { (s.metrics || []).forEach(function (m) { if (m.state === 'warn' || m.state === 'over') n++; }); }); if (n && btn) btn.insertAdjacentHTML('beforeend', ' <span class="svdot" title="' + n + ' cheez dhyan maangti hai">' + n + '</span>'); } catch (e) {} };

  /* ---------- Hidden / erased customers list (Settings > Storage & Safai) ---------- */
  C.goneList = async function (box) {
    var L = []; try { L = await C.call('crm_cust_gone_list', {}); } catch (e) { box.innerHTML = ''; return; }
    box.innerHTML = '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:6px">' + C.ic('eye') + ' Chhupaye / hataye hue customers (' + L.length + ')</h3><p class="mute sm" style="margin-bottom:10px">Customer page par (sirf Admin ko) <b>Chhupayein</b> ya <b>Hamesha ke liye hatayein</b> milta hai. Dono me unke <b>bill aur payment kabhi nahi hatte</b> — All Bills me pehle jaise rehte hain.</p>' +
      (L.length ? '<div class="list">' + L.map(function (x) { return '<div class="li"><span class="grow"><span class="t">' + esc(x.name) + ' ' + (x.mode === 'erased' ? C.pill('Hamesha ke liye hata', 'r') : C.pill('Chhupa hua', 'o')) + '</span><span class="m"><span>' + esc(x.mobile || '') + '</span><span>' + esc(x.cust_id || '') + '</span><span>' + (x.bills || 0) + ' bill rakhe</span><span>' + esc(C.fd(x.at)) + (x.by ? ' · ' + esc(x.by) : '') + '</span></span>' + (x.reason ? '<span class="xs mute">' + esc(x.reason.replace(/^(HIDDEN|ERASED):\s*/, '')) + '</span>' : '') + '</span>' + (x.mode === 'hidden' ? '<button class="btn btn-o btn-sm" data-act="unhide" data-id="' + x.id + '">Wapas dikhayein</button>' : '') + '</div>'; }).join('') + '</div>' : '<p class="mute sm">Abhi koi nahi.</p>') + '</div>';
    box.onclick = async function (e) { var b = e.target.closest('[data-act=unhide]'); if (!b) return; if (!(await C.confirm('Ye customer wapas Customers list me dikhayein?', 'Haan dikhao'))) return; try { await C.run('crm_cust_unhide', { id: +b.getAttribute('data-id') }, 'Customer wapas aa gaya ✔'); C.goneList(box); } catch (er) {} };
  };

  /* ---------- Customer: Chhupayein / Hamesha ke liye hatayein ---------- */
  C.custGone = async function (p) {
    var P; C.busy(true); try { P = await C.call('crm_cust_erase_preview', { id: p.id }); } catch (e) { C.toast(e.message, true); return; } finally { C.busy(false); }
    var backed = false;
    var cnt = [['Leads', P.leads], ['Quotation', P.quotes], ['Documents (files)', P.docs + (P.files_bytes ? ' · ' + (P.files_bytes / 1048576).toFixed(1) + ' MB' : '')], ['Plant', P.plants], ['Reminder / notes', P.reminders], ['Flow (loan, complaint…)', P.flows], ['Declaration', P.decls], ['Checkup', P.checkups], ['Customer ka Store login', P.logins], ['Store enquiry', P.enquiries]].filter(function (x) { return +String(x[1]).split(' ')[0] > 0; });
    var body = '<div class="note g" style="margin-bottom:10px"><b>Bill nahi chhuyenge:</b> ' + P.bills + ' bill (' + C.money(P.bill_amount) + ') aur ' + P.payments + ' payment jaise hain waise rahenge — All Bills / Payments me dikhte rahenge' + (P.quotes_kept ? ' (bill wali ' + P.quotes_kept + ' quotation bhi bill ke saath rahegi)' : '') + '. Customer ka sirf <b>naam, mobile, pata, GST</b> rakha jata hai taaki bill par chhape.</div>' +
      '<div class="sec-t">Do raaste</div>' +
      '<label class="li click" style="cursor:pointer"><input type="radio" name="cgm" value="hide" checked style="margin-right:8px"><span class="grow"><b>Chhupayein (wapas aa sakta hai)</b><span class="m"><span>Customers list se hat jata hai, uska Store login band, data safe rehta hai. Settings → Storage &amp; Safai se kabhi wapas dikha sakte hain.</span></span></span></label>' +
      '<label class="li click" style="cursor:pointer"><input type="radio" name="cgm" value="erase" style="margin-right:8px"><span class="grow"><b style="color:var(--red)">Hamesha ke liye hatayein (wapas nahi aayega)</b><span class="m"><span>Neeche ka sab data permanent delete — storage khaali hota hai.</span></span></span></label>' +
      '<div id="cgHide" style="margin-top:10px">' + C.f('Wajah (zaroori nahi)', '<input class="inp" id="cgWhyH" placeholder="jaise: ab hamse kuch nahi lena chahte">') + '</div>' +
      '<div id="cgErase" hidden style="margin-top:10px"><div class="note r" style="margin-bottom:8px"><b>Ye delete hoga:</b>' + (cnt.length ? '<ul style="margin:6px 0 0 18px">' + cnt.map(function (x) { return '<li>' + esc(x[0]) + ': <b>' + esc(String(x[1])) + '</b></li>'; }).join('') + '</ul>' : ' (leads / documents jaisa kuch nahi mila)') + '</div>' +
      '<div class="row wrap" style="gap:8px;margin-bottom:8px"><button class="btn btn-o" id="cgBk">' + C.ic('download') + ' 1) Pehle backup download karein</button><span id="cgBkS" class="sm mute">Backup ke bina delete nahi hoga.</span></div>' +
      C.f('2) Wajah (zaroori)', '<input class="inp" id="cgWhyE" placeholder="jaise: customer ne kaam cancel kiya, data hatane ko kaha">') +
      C.f('3) Customer ka naam likhein: <b>' + esc(p.title) + '</b>', '<input class="inp" id="cgName" autocomplete="off">') +
      C.f('4) Apna Admin PIN', '<input class="inp" id="cgPin" type="password" inputmode="numeric" maxlength="6" autocomplete="off">') + '</div>';
    var m = C.modal({ title: 'Customer hatayein — ' + p.title, body: body, foot: '<button class="btn btn-o" data-close>Rehne dein</button><button class="btn btn-p" id="cgGo">Chhupayein</button>' });
    var go = $('#cgGo', m.el);
    function mode() { return ($('input[name=cgm]:checked', m.el) || {}).value || 'hide'; }
    function sync() {
      var er = mode() === 'erase'; $('#cgHide', m.el).hidden = er; $('#cgErase', m.el).hidden = !er;
      go.textContent = er ? 'Hamesha ke liye hatao' : 'Chhupayein'; go.className = 'btn ' + (er ? 'btn-r' : 'btn-p');
      go.disabled = er && !(backed && $('#cgWhyE', m.el).value.trim().length >= 3 && $('#cgName', m.el).value.trim().toLowerCase() === String(p.title).trim().toLowerCase() && /^\d{6}$/.test($('#cgPin', m.el).value));
    }
    m.el.addEventListener('input', sync); m.el.addEventListener('change', sync); sync();
    $('#cgBk', m.el).onclick = async function () {
      C.busy(true); try { var b = await C.call('crm_cust_erase_backup', { id: p.id }); C.download(new Blob([JSON.stringify(b)], { type: 'application/json' }), 'customer-backup-' + String(p.title).replace(/[^A-Za-z0-9]+/g, '-') + '-' + C.today() + '.json'); backed = true; $('#cgBkS', m.el).innerHTML = C.pill('Backup download ho gaya ✔') + (b.files_skipped ? ' <span class="xs" style="color:var(--red)">' + esc(b.files_note) + '</span>' : ''); sync(); } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
    };
    go.onclick = async function () {
      var er = mode() === 'erase';
      if (er && !(await C.confirm('"' + p.title + '" ka data hamesha ke liye delete hoga. Wapas nahi aayega. Pakka?', 'Haan, hamesha ke liye hatao', true))) return;
      C.busy(true);
      try {
        if (!er) { await C.call('crm_cust_hide', { id: p.id, reason: $('#cgWhyH', m.el).value.trim() }); C.toast('Customer chhupa diya ✔'); }
        else { var r = await C.call('crm_cust_erase', { id: p.id, reason: $('#cgWhyE', m.el).value.trim(), confirm_name: $('#cgName', m.el).value.trim(), pin: $('#cgPin', m.el).value, backup_done: backed }); if (r && r.error) { C.toast(r.error, true); $('#cgPin', m.el).value = ''; sync(); return; } C.toast('Customer ka data hata diya — bill safe hain ✔'); }
        m.close(); C.go('#/customers');
      } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
    };
  };
})();
