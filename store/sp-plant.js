/* Sunpowers "My Plant" — customer section right under the header (website, shop page, store).
   A logged-in customer enters one or many Plant IDs (= confirmed quotation number). Only IDs on their own mobile are accepted (server checks).
   Config: SPPlant.init({ getToken:()=>token|null, rpc:(fn,p)=>Promise, after:()=>element (section goes right after it) }) */
(function () {
  'use strict';
  var CS = document.currentScript, BASE = CS && CS.src ? CS.src.replace(/[^\/]*$/, '') : '';
  function withShare(cb, fail) { if (window.SPSHARE) return cb(); var e = document.createElement('script'); e.src = BASE + 'sp-share.js?v=3'; e.onload = cb; e.onerror = fail; document.head.appendChild(e); }
  var P = window.SPPlant = {}, cfg = null, host = null, plants = [], prof = null, sec = '', cur = 0, open = false, dlOpen = false, busy = false, msg = '', loaded = false;
  var CSS = '.spp{max-width:1100px;margin:10px auto 0;padding:0 14px;font-family:inherit;color:#1c2a22;box-sizing:border-box}.spp *{box-sizing:border-box}' +
    '.spp-bar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;background:#f1f8f3;border:1px solid #cfe5d6;border-radius:14px;padding:8px 12px}' +
    '.spp-bar b{font-size:15px}.spp-bar .sp{flex:1}.spp-tab{border:1px solid #cfe5d6;background:#fff;border-radius:999px;padding:5px 12px;font-size:13px;cursor:pointer;color:inherit}.spp-tab.on{background:#1f8a4c;color:#fff;border-color:#1f8a4c}' +
    '.spp-btn{border:0;background:#1f8a4c;color:#fff;border-radius:10px;padding:8px 14px;font-size:14px;cursor:pointer;font-weight:600}.spp-btn.ghost{background:#fff;color:#1f6b3f;border:1px solid #cfe5d6}.spp-btn.sm{padding:5px 10px;font-size:13px}' +
    '.spp-add{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}.spp-add input{flex:1;min-width:180px;border:1px solid #bcd7c6;border-radius:10px;padding:9px 12px;font-size:15px;text-transform:uppercase}' +
    '.spp-err{color:#b3261e;font-size:13px;margin-top:6px}.spp-ok{color:#1a7a3e}' +
    '.spp-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-top:10px}@media(max-width:820px){.spp-cards{grid-template-columns:repeat(2,1fr)}}@media(max-width:420px){.spp-cards{grid-template-columns:1fr}}' +
    '.spp-c{background:#fff;border:1px solid #dbe9e0;border-radius:16px;padding:12px 14px;min-height:118px;position:relative}.spp-c h4{margin:0 0 6px;font-size:12px;letter-spacing:.04em;text-transform:uppercase;color:#5d7466}' +
    '.spp-c .big{font-size:24px;font-weight:700;line-height:1.1}.spp-c small{display:block;color:#5d7466;margin-top:3px;font-size:13px}.spp-c.g{border-color:#9bd3ae;background:#f2fbf5}.spp-c.w{border-color:#f0d9a0;background:#fffaf0}' +
    '.spp-tick{display:inline-flex;width:26px;height:26px;border-radius:50%;background:#1f8a4c;color:#fff;align-items:center;justify-content:center;font-size:16px;margin-right:6px;vertical-align:middle}' +
    '.spp-dl{margin-top:6px;display:flex;flex-direction:column;gap:5px}.spp-dl button{text-align:left;border:1px solid #cfe5d6;background:#fff;border-radius:9px;padding:6px 9px;font-size:13px;cursor:pointer;color:inherit}.spp-dl button:hover{background:#f1f8f3}' +
    '.spp-tl{margin-top:12px;background:#fff;border:1px solid #dbe9e0;border-radius:16px;padding:12px 14px}.spp-tl h4{margin:0 0 8px;font-size:14px}' +
    '.spp-steps{display:flex;flex-wrap:wrap;gap:8px}.spp-st{display:flex;align-items:center;gap:7px;border-radius:999px;padding:5px 11px 5px 6px;background:#eef1ef;color:#5d7466;font-size:13px}' +
    '.spp-st i{font-style:normal;width:22px;height:22px;border-radius:50%;background:#cfd8d2;color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:12px}' +
    '.spp-st.d{background:#e6f6ec;color:#17613a}.spp-st.d i{background:#1f8a4c}.spp-st small{color:#6b8576;font-size:11px}' +
    '.spp-fin{margin-top:10px;display:flex;gap:8px;flex-wrap:wrap}.spp-pill{border-radius:999px;padding:6px 14px;font-weight:700;font-size:13px;background:#eef1ef;color:#5d7466}.spp-pill.g{background:#1f8a4c;color:#fff}' +
    '.spp-id{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:8px}.spp-id .cid{font-size:19px;font-weight:800;letter-spacing:.03em;color:#17613a}.spp-id .st{border-radius:999px;padding:3px 11px;font-size:12px;font-weight:700;background:#fff3d6;color:#8a5a00}.spp-id .st.g{background:#e6f6ec;color:#17613a}' +
    '.spp-li{background:#fff;border:1px solid #dbe9e0;border-radius:14px;padding:11px 14px;margin-top:8px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}.spp-li b{font-size:15px}.spp-li .m{flex:1;min-width:180px;color:#5d7466;font-size:13px}.spp-li .w{border-radius:999px;background:#e6f6ec;color:#17613a;padding:3px 10px;font-size:12px;font-weight:700}.spp-li .w.n{background:#eef1ef;color:#5d7466}';
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function tok() { try { return cfg && cfg.getToken && cfg.getToken(); } catch (e) { return null; } }
  function call(fn, p) { p = p || {}; p.token = tok(); return cfg.rpc(fn, p); }
  function fd(s) { if (!s) return '—'; var d = new Date(String(s).length <= 10 ? s + 'T00:00:00' : s); if (isNaN(d)) return esc(String(s).slice(0, 10)); return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }); }
  function money(n) { return '₹' + Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 }); }
  function ensureHost() {
    if (!document.getElementById('spp-css')) { var st = document.createElement('style'); st.id = 'spp-css'; st.textContent = CSS; document.head.appendChild(st); }
    if (host && document.body.contains(host)) return host;
    var a = cfg.after && cfg.after(); if (!a || !a.parentNode) return null;
    host = document.createElement('section'); host.className = 'spp'; host.id = 'sp-plant'; host.setAttribute('data-noi18n', ''); a.parentNode.insertBefore(host, a.nextSibling); return host;
  }
  function load() {
    if (!tok()) { plants = []; prof = null; loaded = false; render(); return Promise.resolve(); }
    return call('crm_consumer_profile').then(function (r) {
      prof = r || null; plants = (prof && prof.projects) || []; loaded = true; if (cur >= plants.length) cur = 0;
      if (!sec || !secOk(sec)) sec = (prof && (prof.bills || []).some(function (b) { return b.state === 'pending'; })) ? 'bill' : plants.length ? 'proj' : (prof && prof.products && prof.products.length ? 'prod' : (prof && prof.services && prof.services.length ? 'serv' : (prof && prof.inquiries && prof.inquiries.length ? 'inq' : 'proj')));
      render();
    }, function () { loaded = true; plants = []; prof = null; render(); });
  }
  function secOk(k) { return !!prof && ((k === 'proj') || (k === 'prod') || (k === 'serv') || (k === 'inq')); }
  function addForm() {
    return '<div class="spp-add"><input id="sppId" placeholder="Plant ID (jaise QT/26-27/0001)" autocomplete="off"><button class="spp-btn" id="sppGo" type="button">' + (busy ? 'Jaanch rahe…' : 'Jodein') + '</button></div>' + (msg ? '<div class="spp-err">' + esc(msg) + '</div>' : '') +
      '<div style="font-size:12px;color:#5d7466;margin-top:5px">Plant ID aapki confirmed quotation ka number hai. Sirf aapke mobile number se juda Plant ID hi judta hai.</div>';
  }
  function cards(p) {
    var m = p.maintenance || {}, pay = p.payment || {}, c4 = '';
    var c1 = '<div class="spp-c"><h4>☀️ Aapka Plant</h4><div class="big">' + (p.kw ? esc(p.kw) + ' kW' : esc(p.ctype || 'Plant')) + '</div><small>Plant ID: <b>' + esc(p.plant_id) + '</b></small><small>' + esc(p.customer) + '</small><small>Install: ' + (p.installed ? fd(p.install_date) : 'Abhi baaki') + '</small></div>';
    var c2 = '<div class="spp-c"><h4>🛠️ Maintenance</h4><div class="big">' + (m.next_due ? fd(m.next_due) : '—') + '</div><small>' + (m.next_due ? 'Agli maintenance due' : (p.installed ? 'Koi maintenance due nahi' : 'Install ke baad shuru hoga')) + '</small>' + (m.last_done ? '<small>Pichli: ' + fd(m.last_done) + '</small>' : '') + '</div>';
    var c3;
    if (pay.state === 'paid') c3 = '<div class="spp-c g"><h4>💳 Payment</h4><div class="big"><span class="spp-tick">✓</span>Poora bhugtan</div><small>Bill ' + esc(pay.bill) + ' · ' + money(pay.amount) + '</small></div>';
    else if (pay.state === 'due') c3 = '<div class="spp-c w"><h4>💳 Payment</h4><div class="big">' + money(pay.balance) + '</div><small>Baaki — agli due date: ' + fd(pay.due_date) + '</small><small>Bill ' + esc(pay.bill) + '</small><small>Non-refundable</small></div>';
    else c3 = '<div class="spp-c"><h4>💳 Payment</h4><div class="big" style="font-size:19px">Bill ka intezaar</div><small>Pehla bill banne par yahan dikhega</small></div>';
    var files = p.files || [];
    c4 = '<div class="spp-c"><h4>⬇️ Downloads</h4><button class="spp-btn ghost sm" id="sppDl" type="button">' + (dlOpen ? 'Band karein' : 'Documents dekhein') + '</button>';
    if (dlOpen) {
      c4 += '<div class="spp-dl"><button data-doc="quotation" type="button">📄 Final Quotation</button>' + (p.has_bill ? '<button data-doc="bill" type="button">🧾 Bill</button>' : '') + '<button data-doc="maintenance" type="button">🛠️ Maintenance summary</button>';
      files.forEach(function (f) { c4 += '<button data-file="' + esc(f.id) + '" type="button">📎 ' + esc(f.name) + '</button>'; });
      c4 += '</div>';
    }
    return '<div class="spp-cards">' + c1 + c2 + c3 + c4 + '</div>';
  }
  function timeline(p) {
    var resid = p.ctype === 'Residential', h = '<div class="spp-tl"><h4>📍 Kaam kahan tak pahuncha</h4><div class="spp-steps">';
    (p.timeline || []).forEach(function (s) {
      if (s.n === 13 && !resid) return;
      h += '<div class="spp-st' + (s.done ? ' d' : '') + '"><i>' + (s.done ? '✓' : s.n) + '</i><span>' + esc(s.name) + (s.done && s.at ? '<small> · ' + fd(s.at) + '</small>' : '') + '</span></div>';
    });
    h += '</div><div class="spp-fin"><span class="spp-pill' + (p.finished ? ' g' : '') + '">' + (p.finished ? '✓ ' : '') + 'Finish Work</span>' + (resid ? '<span class="spp-pill' + (p.subsidy_done ? ' g' : '') + '">' + (p.subsidy_done ? '✓ ' : '') + 'Subsidy</span>' : '') + '</div></div>';
    return h;
  }
  function warrantyBlock(p) {
    var w = p.warranty || []; if (!w.length) return '';
    return '<div class="spp-tl"><h4>🛡️ Warranty</h4>' + w.map(function (x) { return '<div class="spp-li"><b>' + esc(x.name) + '</b><span class="m"></span><span class="w">' + esc(x.warranty) + '</span></div>'; }).join('') + '</div>';
  }
  function amcBlock(p) {
    var v = (p.maintenance && p.maintenance.visits) || []; if (!v.length) return '';
    return '<div class="spp-tl"><h4>🛠️ AMC / Maintenance visits</h4>' + v.map(function (x) { return '<div class="spp-li"><b>Visit ' + esc(x.visit || '') + '</b><span class="m">' + esc(x.plan || '') + ' · ' + fd(x.due) + '</span><span class="w' + (x.done ? '' : ' n') + '">' + (x.done ? '✓ ' + fd(x.done_on) : 'Baaki') + '</span></div>'; }).join('') + '</div>';
  }
  function secProj(h) {
    if (!plants.length) return '<div class="spp-tl"><h4>Abhi koi project nahi</h4><div style="color:#5d7466;font-size:13px">Quotation confirm hote hi aapka project yahan dikhega.</div></div>';
    var t = '<div class="spp-bar">'; plants.forEach(function (p, i) { t += '<button class="spp-tab' + (i === cur ? ' on' : '') + '" data-i="' + i + '" type="button">' + esc(p.title || p.plant_id) + '</button>'; }); t += '</div>';
    return t + cards(plants[cur]) + timeline(plants[cur]) + warrantyBlock(plants[cur]) + amcBlock(plants[cur]);
  }
  function secProd() {
    var a = (prof && prof.products) || []; if (!a.length) return '<div class="spp-tl"><h4>Abhi koi product nahi</h4><div style="color:#5d7466;font-size:13px">Bill banne ke baad kharide hue products, bill aur warranty yahan dikhengi.</div></div>';
    return a.map(function (x) { return '<div class="spp-li"><b>' + esc(x.name) + (x.qty ? ' × ' + esc(x.qty) : '') + '</b><span class="m">' + (x.brand ? esc(x.brand) + ' · ' : '') + 'Bill ' + esc(x.bill || '') + (x.date ? ' · ' + fd(x.date) : '') + (x.paid ? ' · ✓ Paid' : ' · Payment baaki') + '</span><span class="w' + (x.warranty ? '' : ' n') + '">' + (x.warranty ? '🛡️ ' + esc(x.warranty) : 'Warranty: —') + '</span></div>'; }).join('');
  }
  function secServ() {
    var a = (prof && prof.services) || []; if (!a.length) return '<div class="spp-tl"><h4>Abhi koi service nahi</h4><div style="color:#5d7466;font-size:13px">Cleaning, AMC, repair, site visit jaisi service lene par uska status yahan dikhega.</div></div>';
    return a.map(function (p) {
      var done = (p.timeline || []).filter(function (s) { return s.done; }).length, tot = (p.timeline || []).length;
      return '<div class="spp-tl"><h4>🧰 ' + esc(p.title || p.ctype) + ' <span style="font-weight:400;color:#5d7466">(' + esc(p.plant_id || '') + ')</span></h4><div class="spp-fin"><span class="spp-pill' + (p.job_status === 'Poora hua' ? ' g' : '') + '">' + esc(p.job_status || '') + '</span><span class="spp-pill">' + done + '/' + tot + ' step</span></div>' + timelineSteps(p) + amcBlock(p).replace('<div class="spp-tl">', '<div style="margin-top:8px">') + '</div>';
    }).join('');
  }
  function secBills() {
    var a = (prof && prof.bills) || []; if (!a.length) return '<div class="spp-tl"><h4>Abhi koi bill nahi</h4><div style="color:#5d7466;font-size:13px">Quotation confirm hone par bill banega aur yahan "Pending bill" ke roop me dikhega.</div></div>';
    var ord = { pending: 0, paid: 1, cancelled: 2 }; a = a.slice().sort(function (x, y) { return (ord[x.state] - ord[y.state]) || (y.id - x.id); });
    return a.map(function (x) {
      var tag = x.state === 'pending' ? '<span class="w n" style="background:#fff3d6;color:#8a5a00">Pending</span>' : x.state === 'paid' ? '<span class="w">✓ Poora bhugtan</span>' : '<span class="w n" style="background:#fde8e6;color:#b3261e">Cancelled – non refundable</span>';
      return '<div class="spp-li"><b>' + esc(x.title || x.ref) + '</b><span class="m">Bill ' + esc(x.ref || '') + (x.date ? ' · ' + fd(x.date) : '') + '<br>Kul ' + money(x.amount) + ' · Mila ' + money(x.paid) + (x.state === 'pending' ? ' · <b>Baaki ' + money(x.balance) + '</b>' + (x.due_date ? ' (due ' + fd(x.due_date) + ')' : '') : '') + (x.nonrefundable ? '<br><small>Non-refundable — jama paisa wapas nahi hota</small>' : '') + '</span>' + tag + '</div>';
    }).join('');
  }
  function secInq() {
    var a = (prof && prof.inquiries) || []; if (!a.length) return '<div class="spp-tl"><h4>Koi pending quotation nahi</h4></div>';
    return a.map(function (x) { return '<div class="spp-li"><b>' + esc(x.title || x.ref) + '</b><span class="m">' + esc(x.ref || '') + '</span><span class="w n">' + esc(x.status) + '</span></div>'; }).join('');
  }
  function timelineSteps(p) {
    return '<div class="spp-steps" style="margin-top:8px">' + (p.timeline || []).map(function (s) { return '<div class="spp-st' + (s.done ? ' d' : '') + '"><i>' + (s.done ? '✓' : s.n) + '</i><span>' + esc(s.name) + (s.done && s.at ? '<small> · ' + fd(s.at) + '</small>' : '') + '</span></div>'; }).join('') + '</div>';
  }
  function render() {
    var h = ensureHost(); if (!h) return;
    if (!tok()) { h.innerHTML = ''; h.style.display = 'none'; return; }
    h.style.display = '';
    if (!loaded || !prof) { h.innerHTML = '<div class="spp-bar"><b>☀️ Meri Profile</b></div>'; return; }
    var cnt = { proj: plants.length, prod: (prof.products || []).length, serv: (prof.services || []).length, inq: (prof.inquiries || []).length, bill: ((prof.bills || []).filter(function (b) { return b.state === 'pending'; })).length };
    var top = '<div class="spp-id"><span>🆔 Customer ID</span><span class="cid">' + esc(prof.cust_id || '—') + '</span><span class="st' + (prof.stage === 'customer' ? ' g' : '') + '">' + (prof.stage === 'customer' ? 'Customer' : prof.stage === 'inquiry' ? 'Pending Inquiry' : 'Naya') + '</span><span style="color:#5d7466;font-size:13px">' + esc(prof.name || '') + '</span></div>';
    var tabs = '<div class="spp-bar">'; [['proj', '☀️ Projects'], ['prod', '📦 Products'], ['serv', '🧰 Services'], ['bill', '🧾 Pending bills'], ['inq', '📝 Quotations']].forEach(function (t) { tabs += '<button class="spp-tab' + (sec === t[0] ? ' on' : '') + '" data-sec="' + t[0] + '" type="button">' + t[1] + ' (' + cnt[t[0]] + ')</button>'; }); tabs += '</div>';
    var body = sec === 'bill' ? secBills() : sec === 'prod' ? secProd() : sec === 'serv' ? secServ() : sec === 'inq' ? secInq() : secProj();
    h.innerHTML = top + tabs + body;
    bind(h);
  }
  function bind(h) {
    Array.prototype.forEach.call(h.querySelectorAll('.spp-tab[data-i]'), function (b) { b.onclick = function () { cur = +b.getAttribute('data-i'); dlOpen = false; render(); }; });
    Array.prototype.forEach.call(h.querySelectorAll('.spp-tab[data-sec]'), function (b) { b.onclick = function () { sec = b.getAttribute('data-sec'); dlOpen = false; render(); }; });
    var a = h.querySelector('#sppAdd'); if (a) a.onclick = function () { open = !open; msg = ''; render(); };
    var d = h.querySelector('#sppDl'); if (d) d.onclick = function () { dlOpen = !dlOpen; render(); };
    var go = h.querySelector('#sppGo'), inp = h.querySelector('#sppId');
    function add() {
      var v = (inp.value || '').trim(); if (!v || busy) return; busy = true; msg = ''; render();
      call('crm_consumer_link_plant', { plant_id: v }).then(function (r) {
        busy = false;
        if (r && r.error) { msg = r.error; render(); return; }
        var i = plants.findIndex(function (x) { return x.id === r.id; }); if (i < 0) { plants.push(r); i = plants.length - 1; } else plants[i] = r;
        cur = i; open = false; msg = ''; render();
      }, function (e) { busy = false; msg = (e && e.message) || 'Dobara koshish karein'; render(); });
    }
    if (go) go.onclick = add; if (inp) inp.onkeydown = function (e) { if (e.key === 'Enter') add(); };
    Array.prototype.forEach.call(h.querySelectorAll('[data-doc]'), function (b) { b.onclick = function () { printDoc(b.getAttribute('data-doc')); }; });
    Array.prototype.forEach.call(h.querySelectorAll('[data-send]'), function (b) { b.onclick = function () { sendDoc(b.getAttribute('data-send')); }; });
    Array.prototype.forEach.call(h.querySelectorAll('[data-sendf]'), function (b) { b.onclick = function () { sendFile(b.getAttribute('data-sendf')); }; });
    Array.prototype.forEach.call(h.querySelectorAll('[data-file]'), function (b) { b.onclick = function () { getFile(b.getAttribute('data-file')); }; });
  }
  function save(blob, name) {
    var u = URL.createObjectURL(blob), a = document.createElement('a'); a.href = u; a.download = name; document.body.appendChild(a); a.click(); setTimeout(function () { a.remove(); URL.revokeObjectURL(u); }, 3000);
  }
  function getFile(id) {
    call('crm_consumer_file', { id: id }).then(function (r) {
      var bin = atob(r.b64), arr = new Uint8Array(bin.length); for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      save(new Blob([arr], { type: r.mime || 'application/octet-stream' }), r.name || 'file');
    }, function (e) { msg = (e && e.message) || 'File nahi mili'; render(); });
  }
  function docHtml(d) {
    var co = d.company || {}, cu = d.customer || {}, bill = d.kind === 'bill', mt = d.kind === 'maintenance', t = mt ? 'Maintenance Summary' : (bill ? 'Bill / Invoice' : 'Quotation');
    var rows = (d.lines || []).map(function (l, i) { var q = Number(l.qty || 0), pr = Number(l.price || 0); return '<tr><td>' + (i + 1) + '</td><td>' + esc(l.name) + '</td><td style="text-align:right">' + q + '</td><td style="text-align:right">' + money(pr) + '</td><td style="text-align:right">' + (l.gst != null ? esc(l.gst) + '%' : '') + '</td><td style="text-align:right">' + money(q * pr) + '</td></tr>'; }).join('');
    var h = '<!doctype html><meta charset="utf-8"><title>' + esc(t + ' ' + (d.ref || '')) + '</title><style>body{font:14px Arial,sans-serif;color:#111;margin:24px}h1{margin:0;font-size:22px}table{width:100%;border-collapse:collapse;margin-top:12px}td,th{border:1px solid #bbb;padding:6px 8px;text-align:left}th{background:#eef5f0}.r{text-align:right}.b{display:flex;justify-content:space-between;gap:20px}small{color:#555}</style>' +
      '<div class="b"><div><h1>' + esc(co.name || 'Sunpowers') + '</h1><small>' + esc(co.address || '') + '<br>' + (co.gstin ? 'GSTIN: ' + esc(co.gstin) + ' · ' : '') + esc(co.phone || '') + '</small></div><div style="text-align:right"><h1>' + t + '</h1><b>' + esc(d.ref || '') + '</b><br><small>' + fd(d.date) + '</small></div></div>' +
      '<p><b>Customer:</b> ' + esc(cu.name) + '<br><small>' + esc(cu.address || '') + ' ' + esc(cu.city || '') + ' · ' + esc(cu.mobile || '') + '</small></p>';
    if (mt) {
      var v = (d.maintenance && d.maintenance.visits) || [];
      h += '<table><tr><th>Visit</th><th>Plan</th><th>Due</th><th>Status</th></tr>' + (v.length ? v.map(function (x) { return '<tr><td>' + esc(x.visit || '') + '</td><td>' + esc(x.plan || '') + '</td><td>' + fd(x.due) + '</td><td>' + (x.done ? 'Done ' + fd(x.done_on) : 'Baaki') + '</td></tr>'; }).join('') : '<tr><td colspan="4">Abhi koi visit schedule nahi hai</td></tr>') + '</table>';
    } else {
      h += '<table><tr><th>#</th><th>Item</th><th class="r">Qty</th><th class="r">Rate</th><th class="r">GST</th><th class="r">Amount</th></tr>' + rows + '</table>' +
        '<p class="r">' + (d.discount ? 'Discount: ' + money(d.discount) + '<br>' : '') + (d.gst_total != null ? 'GST: ' + money(d.gst_total) + '<br>' : '') + '<b style="font-size:16px">Total: ' + money(d.grand) + '</b>' + (bill ? '<br>Jama: ' + money(d.paid) + ' · Baaki: ' + money(d.balance) : '') + '</p>';
      if (d.notes) h += '<p><small>' + esc(d.notes) + '</small></p>';
    }
    return h + '<p style="margin-top:30px"><small>Computer-generated copy · ' + esc(co.name || 'Sunpowers') + '</small></p>';
  }
  /* Round 32: Send (link page / real file) for plant documents and uploaded files */
  function sendFile(id) {
    call('crm_consumer_file', { id: id }).then(function (r) {
      var bin = atob(r.b64), arr = new Uint8Array(bin.length); for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      var blob = new Blob([arr], { type: r.mime || 'application/octet-stream' });
      withShare(function () { SPSHARE.open({ kind: 'doc', title: r.name || 'Document', name: r.name || 'file', blob: blob, details: [['File', r.name || 'file']], phone: '' }); }, function () { save(blob, r.name || 'file'); });
    }, function (e) { msg = (e && e.message) || 'File nahi mili'; render(); });
  }
  function sendDoc(kind) {
    var p = plants[cur]; if (!p) return;
    call('crm_consumer_plant_doc', { id: p.id, kind: kind }).then(function (d) {
      var co = d.company || {}, cu = d.customer || {}, nm = kind === 'bill' ? 'Bill' : (kind === 'maintenance' ? 'Maintenance summary' : 'Quotation');
      var det = [[nm + ' no', d.ref || ''], ['Customer', cu.name || '']]; if (d.grand != null) det.push(['Total', '\u20B9' + Math.round(Number(d.grand) || 0).toLocaleString('en-IN')]); if (kind === 'bill' && d.balance != null) det.push(['Baaki', '\u20B9' + Math.round(Number(d.balance) || 0).toLocaleString('en-IN')]);
      var html = docHtml(d);
      withShare(function () { SPSHARE.open({ kind: kind === 'bill' ? 'bill' : (kind === 'maintenance' ? 'service' : 'quote'), title: nm + ' ' + (d.ref || ''), subtitle: co.name || 'Sunpowers', amount: kind === 'maintenance' ? null : d.grand, name: (nm + '-' + (d.ref || 'plant')).replace(/[^\w-]+/g, '-') + '.pdf', html: html, details: det, brand: co.name, brandPhone: co.phone, print: function () { printDoc(kind); }, phone: '' }); }, function () { printDoc(kind); });
    }, function (e) { msg = (e && e.message) || 'Document nahi bana'; render(); });
  }
  function printDoc(kind) {
    var p = plants[cur]; if (!p) return;
    call('crm_consumer_plant_doc', { id: p.id, kind: kind }).then(function (d) {
      var w = window.open(URL.createObjectURL(new Blob([docHtml(d)], { type: 'text/html' })), '_blank');
      if (!w) save(new Blob([docHtml(d)], { type: 'text/html' }), (kind + '-' + (d.ref || 'plant')).replace(/[\/\\ ]/g, '-') + '.html');
    }, function (e) { msg = (e && e.message) || 'Document nahi bana'; render(); });
  }
  P.init = function (c) { cfg = c; P.refresh(); document.addEventListener('sp-auth', function () { cur = 0; open = false; dlOpen = false; P.refresh(); }); };
  P.refresh = function () { return load(); };
  P.plants = function () { return plants; };
})();
