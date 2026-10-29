/* Settings — company, bill details, numbering, accountant contacts, notices, privacy toggles, connections */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc;

  /* ---- restore helpers: read backup .zip (stored or deflate) or .json ---- */
  var RS_PARTS = ['crm_records', 'crm_expenses', 'crm_counters', 'crm_services', 'crm_files', 'crm_checkup', 'crm_decl', 'crm_flow_rec', 'crm_consumer_plants', 'crm_staff_hr', 'crm_leave', 'crm_attendance', 'crm_salary_pay', 'crm_staff_adv', 'sp_store', 'sp_orders', 'sp_enquiries', 'sp_design_pay', 'sp_shares', 'sp_sell', 'sp_sell_cfg', 'sp_sub_cfg', 'sp_sub_state', 'sp_pin_areas', 'sp_pin_modes', 'sp_pin_rules', 'sp_ship_rules'];
  var BK_LBL = { crm_auth_admin: 'Admin email / login settings (PIN nahi)', crm_users: 'Team users', crm_records: 'CRM records (customer, lead, quotation, bill, product…)', crm_files: 'Documents ki files', sp_orders: 'Store orders', sp_design_pay: 'Designer payments (₹49)', sp_enquiries: 'Store poochtaachh', crm_activity: 'Activity record', crm_expenses: 'Kharcha', sp_store: 'Store / website data', crm_roles: 'Roles / permission', crm_settings: 'CRM settings', crm_counters: 'Serial numbers', crm_services: 'Services & limits', crm_checkup: 'Plant checkup', crm_decl: 'Declaration', crm_flow_rec: 'Customer flow steps', crm_consumer_plants: 'Consumer plants', crm_staff_hr: 'Staff HR details', crm_leave: 'Chhutti', crm_attendance: 'Attendance', crm_salary_pay: 'Salary', crm_staff_adv: 'Advance', sp_shares: 'Share links', sp_sell: 'Kahan bechna hai', sp_sell_cfg: 'Bechne ki settings', sp_sub_cfg: 'Subsidy settings', sp_sub_state: 'Rajya-wise subsidy', sp_pin_areas: 'Delivery areas', sp_pin_modes: 'Product delivery mode', sp_pin_rules: 'Pincode rules', sp_ship_rules: 'Shipping rules' };
  /* Alag-alag backup: har button apna hissa hi download karta hai (parts = database ke hisse; rows = sp_store me kaun si row) */
  var BK_GRP = {
    website: { l: 'Website + Web Shop page', ic: 'globe', f: 'website-shop', d: 'Website ke shabd, photo, slide, menu, Shop page ki layout', parts: ['sp_store'], rows: { sp_store: function (x) { return x.id === 'web'; } } },
    store: { l: 'Store App', ic: 'store', f: 'store-app', d: 'Products, sections, orders, poochtaachh, share links, designer payment', parts: ['sp_store', 'sp_orders', 'sp_enquiries', 'sp_design_pay', 'sp_shares'], rows: { sp_store: function (x) { return x.id !== 'web'; } } },
    admin: { l: 'Admin & Settings', ic: 'settings', f: 'admin-settings', d: 'Company, CRM settings, roles/permission, services, serial numbers, admin login email', parts: ['crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_services', 'crm_counters'] },
    crm: { l: 'CRM data', ic: 'users', f: 'crm-data', d: 'Customers, leads, quotation, bill, payment, products, documents, kharcha, activity', parts: ['crm_records', 'crm_files', 'crm_expenses', 'crm_checkup', 'crm_decl', 'crm_flow_rec', 'crm_consumer_plants', 'crm_activity'] },
    team: { l: 'Team + HR', ic: 'team', f: 'team-hr', d: 'Team users (bina password), HR details, attendance, chhutti, salary, advance', parts: ['crm_users', 'crm_staff_hr', 'crm_leave', 'crm_attendance', 'crm_salary_pay', 'crm_staff_adv'] },
    delivery: { l: 'Delivery & Subsidy', ic: 'box', f: 'delivery-subsidy', d: 'Delivery areas, pincode rules, shipping, kahan bechna hai, rajya-wise subsidy', parts: ['sp_sell', 'sp_sell_cfg', 'sp_sub_cfg', 'sp_sub_state', 'sp_pin_areas', 'sp_pin_modes', 'sp_pin_rules', 'sp_ship_rules'] }
  };
  var BK_ALL = ['crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_users', 'crm_records', 'crm_files', 'crm_counters', 'crm_activity', 'crm_expenses', 'crm_services', 'crm_checkup', 'crm_decl', 'crm_flow_rec', 'crm_consumer_plants', 'crm_staff_hr', 'crm_leave', 'crm_attendance', 'crm_salary_pay', 'crm_staff_adv', 'sp_store', 'sp_orders', 'sp_enquiries', 'sp_design_pay', 'sp_shares', 'sp_sell', 'sp_sell_cfg', 'sp_sub_cfg', 'sp_sub_state', 'sp_pin_areas', 'sp_pin_modes', 'sp_pin_rules', 'sp_ship_rules'];
  var BK_KINDS = { party: 'Customers', lead: 'Leads', quote: 'Quotations', invoice: 'Bills', payment: 'Payments', purchase: 'Purchase', item: 'Products / Projects', plant: 'Plants', reminder: 'Reminders', earning: 'Commission', doc: 'Documents', folder: 'Folders', note: 'Notes', notice: 'Notices' };
  function partsBox(attr, parts, kindAttr, only) { return '<div class="sec-t" style="margin-top:6px">Kaun-kaun sa data? <span class="o">(jo na chahiye uska tick hata dein)</span></div><div class="row wrap" style="gap:6px 14px;margin-bottom:8px">' + parts.filter(function (k) { return !only || only.indexOf(k) >= 0; }).map(function (k) { return '<label class="ck" style="margin:0"><input type="checkbox" ' + attr + '="' + k + '" checked> ' + esc(BK_LBL[k] || k) + '</label>'; }).join('') + '</div><div class="row wrap" style="gap:6px 14px;margin-bottom:12px"><span class="xs mute">Records me se:</span>' + Object.keys(BK_KINDS).map(function (k) { return '<label class="ck" style="margin:0"><input type="checkbox" ' + kindAttr + '="' + k + '" checked> ' + esc(BK_KINDS[k]) + '</label>'; }).join('') + '</div>'; }
  function picked(root, attr) { return Array.prototype.slice.call(root.querySelectorAll('[' + attr + ']:checked')).map(function (c) { return c.getAttribute(attr); }); }
  function b64of(u) { var s = '', n = 8192; for (var i = 0; i < u.length; i += n) s += String.fromCharCode.apply(null, u.subarray(i, i + n)); return btoa(s); }
  async function inflate(u) {
    if (typeof DecompressionStream === 'undefined') throw new Error('Ye browser compressed zip nahi khol sakta — backup.json alag nikaal kar chunein');
    var ds = new DecompressionStream('deflate-raw'), w = ds.writable.getWriter(); w.write(u); w.close();
    return new Uint8Array(await new Response(ds.readable).arrayBuffer());
  }
  async function readZip(buf) {
    var v = new DataView(buf), u8 = new Uint8Array(buf), e = -1, out = {};
    for (var i = u8.length - 22; i >= Math.max(0, u8.length - 70000); i--) if (v.getUint32(i, true) === 0x06054b50) { e = i; break; }
    if (e < 0) throw new Error('Ye valid .zip nahi hai');
    var n = v.getUint16(e + 10, true), p = v.getUint32(e + 16, true), dec = new TextDecoder();
    for (var k = 0; k < n; k++) {
      if (v.getUint32(p, true) !== 0x02014b50) throw new Error('Zip kharab hai');
      var meth = v.getUint16(p + 10, true), csz = v.getUint32(p + 20, true), nl = v.getUint16(p + 28, true), xl = v.getUint16(p + 30, true), cl = v.getUint16(p + 32, true), lo = v.getUint32(p + 42, true);
      var name = dec.decode(u8.subarray(p + 46, p + 46 + nl)), lnl = v.getUint16(lo + 26, true), lxl = v.getUint16(lo + 28, true), st = lo + 30 + lnl + lxl, raw = u8.subarray(st, st + csz);
      out[name] = meth === 0 ? raw : meth === 8 ? await inflate(raw) : null;
      p += 46 + nl + xl + cl;
    }
    return out;
  }
  async function readBackup(file) {
    var buf = await file.arrayBuffer(), json, files = {};
    if (/\.json$/i.test(file.name)) json = JSON.parse(new TextDecoder().decode(new Uint8Array(buf)));
    else {
      var z = await readZip(buf); if (!z['backup.json']) throw new Error('Is zip me backup.json nahi mila');
      json = JSON.parse(new TextDecoder().decode(z['backup.json']));
      Object.keys(z).forEach(function (nm) { var m = /^files\/(\d+)-rec/.exec(nm); if (m && z[nm]) files[m[1]] = z[nm]; });
    }
    if (!json || typeof json !== 'object' || !RS_PARTS.some(function (k) { return Array.isArray(json[k]); })) throw new Error('Ye Sunpowers ka backup nahi lagta');
    return { json: json, files: files };
  }
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
      var tabs = [['company', 'Company'], ['bill', 'Bill / Quotation'], ['acc', 'Accountant'], ['notices', 'Notice board'], ['tpl', 'Templates'], ['privacy', 'Privacy'], ['conn', 'Connections (API)']].concat(C.isAdmin() ? [['look', 'Colour &amp; Greeting'], ['login', 'Login &amp; Email OTP'], ['backup', 'Backup'], ['storage', 'Storage &amp; Safai'], ['services', 'Services &amp; Limits']] : []);
      var h = '<div class="ph"><div><h1>Settings</h1><p>Company ki jaankari — quotation, bill aur rasid par yahi chhapti hai.</p></div></div><div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + t[1] + '</button>'; }).join('') + '</div><div id="tb"></div>';
      el.innerHTML = h;
      var tb = $('#tb', el), roleDefs = null;
      if (C.isAdmin() && tab !== 'services') C.svcDot($('[data-tab=services]', el));
      var saveBtn = '<div class="row" style="margin-top:16px;justify-content:flex-end"><button class="btn btn-p" data-act="save">' + C.ic('check') + ' Save karein</button></div>';
      function fi(k, l, attrs, cls) { return C.f(l, '<input class="inp" data-c="' + k + '" value="' + esc(co[k] || '') + '" ' + (attrs || '') + '>', cls); }
      function ta(k, l, rows) { return C.f(l, '<textarea class="inp" data-c="' + k + '" rows="' + (rows || 3) + '">' + esc(co[k] || '') + '</textarea>', 'full'); }
      async function draw() {
        if (tab === 'company') tb.innerHTML = '<div class="card"><div class="fg">' + fi('name', 'Company ka naam (chhota)') + fi('legal', 'Poora / legal naam (bill par)') + fi('phone', 'Phone') + fi('email', 'Email', 'type="email"') + fi('website', 'Website') + fi('store_url', 'Online Store link') + fi('gstin', 'GSTIN', 'maxlength="15" style="text-transform:uppercase"') + fi('pan', 'PAN', 'maxlength="10" style="text-transform:uppercase"') + fi('state', 'State') + ta('address', 'Pata', 2) + '</div>' +
          '<div class="sec-t">Customer Profile — bachat ka anumaan</div><p class="hint" style="margin-bottom:8px">Website / Store app me customer ke Profile ke "Savings" card me ye maan lagte hain. Ye sirf anumaan dikhata hai — asli data nahi.</p><div class="fg">' + C.f('Bijli ka daam (₹ / unit)', '<input class="inp" data-hub="tariff" inputmode="decimal" value="' + esc((S.hub || {}).tariff != null ? S.hub.tariff : 7) + '">') + C.f('Roz ki bijli (unit per kW)', '<input class="inp" data-hub="gen" inputmode="decimal" value="' + esc((S.hub || {}).gen != null ? S.hub.gen : 4) + '">') + '</div>' + '<div class="sec-t">Customer ko Profile → Documents me kya dikhe</div><p class="hint" style="margin-bottom:8px">Jo bhi document customer ko link se jaata hai ya aap step 14 me rakhte hain, wo customer ke Documents me apne aap aa jaata hai. Yahan tay karein ki customer ko kaun se dikhein. Tick = dikhega. (Customer ki apni bheji hui file hamesha uske paas rehti hai.)</p><div class="row wrap" style="gap:6px 18px">' +
          [['quotation', 'Final Quotation'], ['bill', 'Bill / Invoice'], ['receipt', 'Rasid (payment receipt)'], ['maintenance', 'Maintenance summary'], ['checkup', 'Routine Checkups'], ['warranty', 'Warranty'], ['files', 'Staff ki upload ki hui files'], ['upload', 'Customer apni file bhej sake']].map(function (x) { return '<label class="ck"><input type="checkbox" data-hd="' + x[0] + '"' + ((((S.hub || {}).docs) || {})[x[0]] === '0' ? '' : ' checked') + '> ' + x[1] + '</label>'; }).join('') +
          '</div><p class="hint" style="margin:8px 0 4px">Staff ki files me se in category ko customer se <b>chhupayein</b> (tick = chhupi rahegi):</p><div class="row wrap" style="gap:6px 18px">' +
          ['Blueprint', 'Plant photo', 'Quotation', 'Bill', 'Certificate', 'Warranty', 'Agreement', 'Other'].map(function (c) { return '<label class="ck"><input type="checkbox" data-hdc="' + c + '"' + (((((S.hub || {}).docs) || {}).hide_cats || []).indexOf(c) >= 0 ? ' checked' : '') + '> ' + c + '</label>'; }).join('') + '</div>' + '<div class="sec-t">Bill / quotation me "Aapko kya milega" (faayde)</div><p class="hint" style="margin-bottom:8px">Bill ke items dekhkar ye section apne aap banta hai (product / service / project ke hisaab se). Upar ka bijli daam aur roz ki unit hi bachat ke anumaan me lagte hain. Yahan har prakaar ka text badal sakte hain — <b>har line = ek point</b>. Khali karke Save karne par wapas standard text chalega. Har quotation me ek tick se ye section band bhi kiya ja sakta hai.</p><details><summary style="cursor:pointer;font-weight:700">Faayde ka text dekhein / badlein</summary><div class="fg" style="margin-top:8px">' +
          (window.SPBEN ? SPBEN.KEYS.map(function (b) { var cur = (((S.hub || {}).ben) || {})[b.k]; return C.f(b.label, '<textarea class="inp" data-ben="' + b.k + '" rows="' + Math.min(6, b.def.length + 1) + '">' + esc((Array.isArray(cur) && cur.length ? cur : b.def).join('\n')) + '</textarea>', 'full'); }).join('') : '') + '</div></details>' + '<div class="sec-t">Logo aur sign</div><div class="grid g2"><div class="stack"><b class="sm">Logo</b><div id="lg">' + (co.logo ? '<img src="' + esc(co.logo) + '" style="max-height:70px;max-width:200px">' : '<p class="mute sm">Logo nahi hai</p>') + '</div><div class="row"><button class="btn btn-o btn-sm" data-act="logo">' + C.ic('upload') + (co.logo ? ' Logo badlein (Replace)' : ' Logo dalein') + '</button>' + (co.logo ? '<button class="btn btn-g btn-sm" data-act="nologo">Hatayein (Delete)</button>' : '') + '</div></div>' +
          '<div class="stack"><b class="sm">Sign / Stamp</b><div id="sgv">' + (co.sign ? '<img src="' + esc(co.sign) + '" style="max-height:60px;max-width:200px">' : '<p class="mute sm">Sign nahi hai</p>') + '</div><div class="row wrap"><button class="btn btn-o btn-sm" data-act="signup">' + C.ic('upload') + (co.sign ? ' Photo badlein (Replace)' : ' Photo') + '</button><button class="btn btn-o btn-sm" data-act="signdraw">' + C.ic('edit') + ' Yahin sign karein</button>' + (co.sign ? '<button class="btn btn-g btn-sm" data-act="nosign">Hatayein (Delete)</button>' : '') + '</div>' + fi('sign_label', 'Sign ke neeche likha', 'placeholder="Authorised Signatory"') + '</div></div></div>' + saveBtn;
        else if (tab === 'bill') tb.innerHTML = '<div class="card"><div class="sec-t" style="margin-top:0">Bank / UPI (bill par chhapega)</div><div class="fg">' + fi('bank_holder', 'Account holder') + fi('bank_name', 'Bank') + fi('bank_acc', 'Account no.') + fi('bank_ifsc', 'IFSC', 'style="text-transform:uppercase"') + fi('upi', 'UPI ID') + '</div><label class="ck" style="margin-top:10px"><input type="checkbox" data-c="quote_show_bank"' + (String(co.quote_show_bank) === '1' ? ' checked' : '') + '> Quotation (PDF) par bhi Bank / UPI ka dabba dikhayein</label><p class="hint">Tax Invoice par Bank details hamesha aayengi. Quotation PDF par band rakhna theek hai — customer link par payment ka dabba alag se aata hai (neeche).</p>' +
          '<div class="sec-t">Customer Disclaimer (order / Accept se pehle tick zaroori)</div><p class="hint" style="margin-bottom:8px">Online Store, Website checkout aur manual quotation link — teeno par customer ko ye dikhta hai. Khali chhodein to Sunpowers ka standard text chalega (product warranty = manufacturer ki; chhat drilling aur site safety = customer / chhat ki sthiti). Apna text daalna ho to <b>har line = ek point</b>. Badlav par purani sahmatiyan waise hi record me rehti hain. Kisi vakil se ek baar text jaanch lein.</p><div class="fg">' + ta('terms_product', 'Product disclaimer (khali = standard)', 6) + ta('terms_install', 'Installation / chhat / site safety disclaimer (khali = standard)', 8) + ta('calamity_text', 'Final bill par prakritik aapda (aandhi / ole / bhookamp) ki line (khali = standard)', 3) + '</div><label class="ck" style="margin-top:8px"><input type="checkbox" data-c="bill_calamity"' + (String(co.bill_calamity) === '0' ? '' : ' checked') + '> Ye line sirf FINAL bill (poora payment aa gaya) par, Project / Service me chhapein</label>' +
          '<div class="sec-t">Customer link par "Pay your bill amount" dabba</div><p class="hint" style="margin-bottom:8px">Bill link par aur quotation Accept hone ke baad: UPI QR + upar ka Bank account + (chahein to) payment link — teeno ek saath. Staff koi alag account nahi bhej sakta; ye details sirf yahin se jaati hain, aur inme badlav Activity me "PAYMENT DETAILS badli" likha jaata hai.</p><div class="fg">' + fi('pay_link', 'Payment link (https://…) — chahein to', 'placeholder="https://" inputmode="url"', 'full') + '</div><label class="ck" style="margin-top:8px"><input type="checkbox" data-c="pay_box"' + (String(co.pay_box) === '0' ? '' : ' checked') + '> Customer link par payment ka dabba dikhayein</label>' +
          '<div class="sec-t">Terms</div><div class="fg">' + ta('terms_quote', 'Quotation ki terms (har nayi quotation me apne aap)', 5) + ta('terms', 'Bill ki terms', 4) + fi('powered', 'Har page ke neeche hari patti ka text (link apne aap banega)', 'placeholder="Powered by: www.digidashland.in"', 'full') + '</div>' +
          '<div class="sec-t">Number series</div><div class="fg g3">' + [['quote', 'Quotation', 'QT'], ['invoice', 'Bill', 'INV'], ['payment', 'Rasid', 'RCPT'], ['purchase', 'Purchase', 'PO'], ['plant', 'Plant', 'PL']].map(function (x) { return C.f(x[1] + ' prefix', '<input class="inp" data-px="' + x[0] + '" value="' + esc(S.prefix[x[0]] || '') + '" placeholder="' + x[2] + '" maxlength="8" style="text-transform:uppercase">'); }).join('') + '</div><p class="hint" style="margin-top:6px">Number aisa banega: QT/26-27/0001 — har financial year (1 April) se naya.</p></div>' +
          '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:6px">Discount aur Online Store hissa</h3><p class="hint" style="margin-bottom:10px">Admin par koi fixed limit nahi (par kharid rate se neeche jaane par chetavni aati hai). Kisi user ki alag limit Team me us user par lagayi ja sakti hai — wo isse upar chalegi.</p><div class="fg g3">' +
          C.f('Manager max discount %', '<input class="inp" data-dd="manager" inputmode="decimal" value="' + esc((S.disc_defaults || {}).manager != null ? S.disc_defaults.manager : 5) + '">') +
          C.f('Staff max discount %', '<input class="inp" data-dd="staff" inputmode="decimal" value="' + esc((S.disc_defaults || {}).staff != null ? S.disc_defaults.staff : 2.5) + '">') +
          C.f('Online Store ke liye default hissa %', '<input class="inp" data-stk="online_pct" inputmode="decimal" value="' + esc((S.stock || {}).online_pct != null ? S.stock.online_pct : 20) + '">') + '</div></div>' + saveBtn;
        else if (tab === 'acc') tb.innerHTML = '<div class="card"><div class="hd"><h3>Accountant / CA contacts</h3><button class="btn btn-o btn-sm" data-act="accadd">' + C.ic('plus') + ' Jodein</button></div><p class="mute sm" style="margin-bottom:12px">Har report par "Download &amp; Share to Accountant" dabane se inhi ko WhatsApp / Email jayega. Hum accounting / GST filing nahi karte — sirf report bhejte hain.</p><div class="stack" id="accl">' + (S.accountants.length ? S.accountants.map(function (a, i) { return '<div class="fg g3" style="align-items:end;border:1px solid var(--line);border-radius:12px;padding:12px"><div class="f"><label>Naam</label><input class="inp" data-acc="' + i + '" data-k="name" value="' + esc(a.name || '') + '"></div><div class="f"><label>WhatsApp mobile</label><input class="inp" data-acc="' + i + '" data-k="mobile" value="' + esc(a.mobile || '') + '" inputmode="tel"></div><div class="f"><label>Email</label><div class="row"><input class="inp" data-acc="' + i + '" data-k="email" value="' + esc(a.email || '') + '" type="email"><button class="btn btn-r btn-icon" data-act="accdel" data-id="' + i + '" aria-label="Hatayein">' + C.ic('trash') + '</button></div></div></div>'; }).join('') : C.empty('user', 'Koi accountant nahi', '"Jodein" dabayein')) + '</div></div>' + saveBtn;
        else if (tab === 'notices') { var ns = await C.list('notice', { limit: 100 }); tb.innerHTML = '<div class="card"><h3 style="margin-bottom:10px">Naya notice (sab users ke Home par dikhega)</h3><div class="stack">' + C.f('Heading', '<input class="inp" id="nt" maxlength="120">') + C.f('Detail', '<textarea class="inp" id="nb" rows="3"></textarea>') + '<div class="row" style="justify-content:flex-end"><button class="btn btn-p" data-act="nadd">' + C.ic('megaphone') + ' Notice lagayein</button></div></div></div><div class="list" style="margin-top:14px">' + (ns.length ? ns.map(function (n) { return '<div class="li"><span class="av o">' + C.ic('megaphone') + '</span><span class="grow"><span class="t">' + esc(n.title) + '</span><span class="m"><span>' + esc(n.data.body || '') + '</span><span>' + esc(C.fd(n.created_at)) + '</span></span></span><button class="btn btn-g btn-icon btn-sm" data-act="ndel" data-id="' + n.id + '">' + C.ic('trash') + '</button></div>'; }).join('') : C.empty('megaphone', 'Koi notice nahi')) + '</div>'; tb._ns = ns; }
        else if (tab === 'tpl') {
          S.templates = S.templates || {};
          tb.innerHTML = '<div class="card"><p class="mute sm" style="margin-bottom:12px">Ye tayyar jawab har jagah button ban kar dikhte hain (hatane ki wajah, baat-cheet note, reject, lead haarne ki wajah). <b>Har line me ek.</b> User inme se chun sakta hai ya apna text likh sakta hai.</p><div class="grid g2">' +
            Object.keys(C.TPL_DEF).map(function (k) { return '<div class="f"><label>' + esc(C.TPL_NAMES[k] || k) + '</label><textarea class="inp" rows="8" data-tplk="' + k + '">' + esc(C.tpl(k).join('\n')) + '</textarea><button type="button" class="btn btn-g btn-sm" data-act="tplreset" data-id="' + k + '" style="margin-top:6px;align-self:flex-start">Default wapas</button></div>'; }).join('') + '</div>' + saveBtn + '</div>';
        }
        else if (tab === 'privacy') {
          if (!C.isAdmin()) { tb.innerHTML = '<div class="card">' + C.empty('lock', 'Sirf Admin badal sakta hai') + '</div>'; return; }
          roleDefs = roleDefs || (await C.call('crm_roles_get', {})).roles || {};
          var R = ['manager', 'staff', 'dealer', 'influencer'];
          tb.innerHTML = '<div class="card"><p class="mute sm" style="margin-bottom:12px">Privacy wali cheezein — tick = dikhega / kar sakta hai. (Baaki saari permission: Team → Role permission)</p><div class="tw"><table class="t"><thead><tr><th>Kya</th>' + R.map(function (r) { return '<th style="text-align:center">' + C.ROLE[r] + '</th>'; }).join('') + '</tr></thead><tbody>' + PRIV.map(function (p) { return '<tr><td>' + esc(p[1]) + '</td>' + R.map(function (r) { return '<td style="text-align:center"><input type="checkbox" style="width:20px;height:20px;accent-color:var(--leaf)" data-pv="' + r + '|' + p[0] + '"' + ((roleDefs[r] || {})[p[0]] ? ' checked' : '') + '></td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div><div class="row" style="margin-top:14px;justify-content:flex-end"><button class="btn btn-p" data-act="psave">' + C.ic('check') + ' Save karein</button></div></div>';
        } else if (tab === 'look') {
          tb.innerHTML = '<div id="lkHost"></div>';
          SPLOOKUI.mount($('#lkHost', tb), { app: 'crm', label: 'CRM', lang: 'en', livePanel: true, toast: C.toast,
            load: function () { return SPLOOK.fetch().then(function (c) { return c || {}; }); },
            save: function (cfg) { return C.call('crm_cfg_save', { data: cfg }); },
            users: function () { return C.call('crm_users_list', {}).then(function (l) { return (l || []).filter(function (u) { return u.status !== 'blocked'; }); }); } });
        } else if (tab === 'login') {
          var A = await C.call('crm_auth_admin_get', {}), au = A.auth || {}, u = au.urls || {};
          tb._A = A;
          tb.innerHTML = '<div class="grid g2"><div class="card"><h3 style="margin-bottom:10px">Admin login email</h3><div class="stack">' + C.f('OTP isi email par jayega (primary)', '<input class="inp" id="lgE1" type="email" value="' + esc(A.email) + '">') + C.f('Backup email <span class="o">(sirf "backup par bhejein" dabane par)</span>', '<input class="inp" id="lgE2" type="email" value="' + esc(A.email2) + '">') +
            C.f('Email kiske naam se jaye (From)', '<input class="inp" id="lgFrom" value="' + esc(au.from || 'Sunpowers <no-reply@sunpowers.in>') + '"><span class="hint">Resend me domain verify hone ke baad: Sunpowers &lt;no-reply@sunpowers.in&gt;</span>') + '</div>' +
            '<div class="sec-t">PIN reset link kis address par khule</div><div class="stack">' + C.f('Online Store (Main App)', '<input class="inp" id="lgU1" value="' + esc(u.store || '') + '">') + C.f('CRM', '<input class="inp" id="lgU2" value="' + esc(u.crm || '') + '">') + C.f('Store Admin', '<input class="inp" id="lgU3" value="' + esc(u.admin || '') + '">') + '</div>' +
            '<div class="sec-t">Resend API key</div><p class="sm" style="margin-bottom:8px">' + (A.key_set ? C.pill('Key set hai ✔') : C.pill('Key nahi hai', 'r')) + ' ' + (A.pg_net ? C.pill('pg_net chalu ✔') : C.pill('pg_net band hai', 'r')) + '</p><input class="inp" id="lgKey" type="password" autocomplete="off" placeholder="Nayi key daalni ho to yahan (re_...) — warna khaali chhodein">' +
            '<div class="row wrap" style="margin-top:16px"><input class="inp" id="lgPin" type="password" inputmode="numeric" maxlength="6" placeholder="Apna PIN" style="max-width:200px"><button class="btn btn-p" data-act="lgsave">' + C.ic('check') + ' Save karein</button></div></div>' +
            '<div class="card"><div class="hd"><h3>Email check</h3><button class="btn btn-o btn-sm" data-act="lgtest">' + C.ic('send') + ' Test email bhejein</button></div><p class="mute sm" style="margin-bottom:10px">Test email primary email par jayega. 5–10 second me status yahan dikhega.</p><div id="lgStat"></div><div class="sec-t">Aakhri 20 email</div>' +
            (A.log.length ? '<div class="list">' + A.log.map(function (l) { return '<div class="li"><span class="grow"><span class="t" style="font-size:14px">' + esc(l.subject) + '</span><span class="m"><span>' + esc(l.to) + '</span><span>' + esc(C.fdt(l.at)) + '</span>' + (l.note ? '<span style="color:var(--red)">' + esc(l.note) + '</span>' : '') + '</span></span>' + (l.request_id ? '<button class="btn btn-g btn-sm" data-act="lgchk" data-id="' + l.request_id + '">Status</button>' : '') + '</div>'; }).join('') + '</div>' : '<p class="mute sm">Abhi koi email nahi gaya.</p>') + '</div></div>';
        } else if (tab === 'services') { tb.innerHTML = ''; await C.svcTab(tb);
        } else if (tab === 'storage') {
          var ST = {}; try { ST = await C.call('crm_storage_stats', {}); } catch (e) { ST = {}; }
          var mb = function (b) { return (b / 1048576).toFixed(1) + ' MB'; };
          tb.innerHTML = '<div class="card"><h3 style="margin-bottom:6px">' + C.ic('folder') + ' Storage kitna bhara hai</h3><div class="kpis" style="margin-bottom:12px">' + C.kpi('Database', mb(ST.db_bytes || 0), 'Supabase free: 500 MB', '', '', 'folder') + C.kpi('Documents', mb(ST.files_bytes || 0), (ST.files_n || 0) + ' files', '', '', 'upload') + C.kpi('Quotation', ST.quotes_n || 0, 'Bills: ' + (ST.invoices_n || 0), '', '', 'quote') + C.kpi('Store enquiry / order', (ST.enquiries_n || 0) + ' / ' + (ST.orders_n || 0), '', '', '', 'cart') + '</div>' +
            '<div class="note g" style="margin-bottom:12px">Bill (invoice), payment aur customer <b>kabhi delete nahi hote</b>. Safai me sirf <b>purani quotation jo bill nahi bani</b> (draft / bheji gayi / mana kiya) aur <b>band ya cancel enquiry</b> jaati hai. Quotation jab chahein dobara bana sakte hain.</div>' +
            '<div class="row wrap"><label class="sm b">Itne din se purani</label><input class="inp" id="pgDays" type="number" min="7" value="90" style="max-width:100px"><button class="btn btn-o" data-act="pgsee">Pehle dekhein</button></div><div id="pgOut" class="sm" style="margin-top:12px"></div></div><div id="goneBox"></div>';
          C.goneList($('#goneBox', tb));
        } else if (tab === 'backup') {
          tb.innerHTML = '<div class="card"><h3 style="margin-bottom:6px">' + C.ic('download') + ' Master backup — sab kuch ek click me</h3><p class="mute sm" style="margin-bottom:12px">Ek click me poora data ek <b>.zip</b> file me: <b>Website, Web Shop page, Store App, Admin &amp; Settings, CRM (customers, leads, quotation, bill, documents), Team + HR, Delivery &amp; Subsidy</b>. Andar <b>backup.json</b> (poora data, wapas lane ke liye) + <b>backup.xlsx</b> (Excel me padhne ke liye) + <b>files/</b> folder.</p>' +
            '<div class="note g" style="margin-bottom:12px">Har hafte ek baar backup lekar Google Drive / pen drive me rakhein. Password, PIN, OTP aur API key backup me <b>nahi</b> jaate (suraksha ke liye). Ye <b>sirf data</b> hai, code nahi. Photos/video jo Supabase Storage me hain unke sirf <b>link</b> aate hain — poora database ke liye Supabase ka apna backup bhi chalu rakhein.</div>' +
            '<div class="row wrap"><input class="inp" id="bkPin" type="password" inputmode="numeric" maxlength="6" placeholder="Apna PIN" style="max-width:200px"><button class="btn btn-p" data-act="bkgo">' + C.ic('download') + ' Master backup download karein</button></div><div id="bkStat" class="sm" style="margin:12px 0"></div>' +
            '<details style="margin-top:6px"><summary class="sm b" style="cursor:pointer">Kya-kya shamil hai? (kuch hatana ho to tick hata dein)</summary>' + partsBox('data-bkp', BK_ALL, 'data-bkk') + '<input type="checkbox" id="bkF" checked hidden></details></div>' +
            '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:6px">' + C.ic('folder') + ' Alag-alag backup</h3><p class="mute sm" style="margin-bottom:12px">Sirf ek hissa chahiye to yahan se lein (upar wala PIN hi chalega). Har file me apna <b>backup.json</b> + <b>backup.xlsx</b> hota hai aur niche ke Restore se wapas bhi aa sakta hai.</p><div class="grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px">' +
              Object.keys(BK_GRP).map(function (k) { var g = BK_GRP[k]; return '<button class="btn btn-o" data-act="bkgrp" data-id="' + k + '" style="display:block;text-align:left;height:auto;padding:10px 12px;white-space:normal"><b>' + C.ic(g.ic) + ' ' + esc(g.l) + '</b><span class="xs mute" style="display:block;margin-top:3px;font-weight:400">' + esc(g.d) + '</span></button>'; }).join('') + '</div></div>' +
            '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:6px">' + C.ic('upload') + ' Backup se data wapas laayein (Restore)</h3><p class="mute sm" style="margin-bottom:12px">Pehle liya hua <b>backup .zip</b> (ya andar ki <b>backup.json</b>) chunein. Backup ka data <b>wapas jud jata hai / usi number par update hota hai</b> — backup ke baad ka naya data <b>delete nahi hota</b>. Settings, team ke login, password aur PIN <b>nahi</b> badalte.</p>' +
            '<div class="row wrap"><input class="inp" id="rsFile" type="file" accept=".zip,.json,application/zip,application/json" style="max-width:320px"></div>' +
            '<div id="rsInfo" class="sm" style="margin:10px 0"></div>' +
            '<div class="row wrap"><input class="inp" id="rsPin" type="password" inputmode="numeric" maxlength="6" placeholder="Apna PIN" style="max-width:200px"><button class="btn btn-p" data-act="rsgo" id="rsGo" disabled>' + C.ic('upload') + ' Wapas laayein</button></div><div id="rsStat" class="sm" style="margin-top:12px"></div></div>';
        } else if (tab === 'conn') tb.innerHTML = '<div class="card"><div class="hd"><h3>Doosre apps se jodein</h3><button class="btn btn-o btn-sm" data-act="cadd">' + C.ic('plus') + ' Connection jodein</button></div><div class="note g" style="margin-bottom:12px">' + C.ic('key') + ' Yahan sirf <b>API key / link</b> daalein — code badalne ki zaroorat nahi. Ye keys sirf Admin dekh sakta hai. Facebook / Instagram / Google ke liye kabhi ID-password na daalein — official "Connect" (Marketing &amp; Grow, Phase 4) se judega.</div><div class="stack" id="cl">' + (S.secrets.connections.length ? S.secrets.connections.map(function (c, i) { return '<div style="border:1px solid var(--line);border-radius:12px;padding:12px"><div class="fg"><div class="f"><label>Naam</label><input class="inp" data-cn="' + i + '" data-k="name" value="' + esc(c.name || '') + '"></div><div class="f"><label>Prakar</label><select class="inp" data-cn="' + i + '" data-k="type">' + C.opts(CONN, c.type) + '</select></div><div class="f"><label>Link / URL</label><input class="inp" data-cn="' + i + '" data-k="url" value="' + esc(c.url || '') + '"></div><div class="f"><label>API key / token</label><input class="inp" data-cn="' + i + '" data-k="key" value="' + esc(c.key || '') + '" type="password" autocomplete="off"></div><div class="f full"><label>Note</label><div class="row"><input class="inp" data-cn="' + i + '" data-k="note" value="' + esc(c.note || '') + '"><label class="ck nowrap"><input type="checkbox" data-cn="' + i + '" data-k="on"' + (c.on !== false ? ' checked' : '') + '> Chalu</label><button class="btn btn-r btn-icon" data-act="cdel" data-id="' + i + '">' + C.ic('trash') + '</button></div></div></div></div>'; }).join('') : C.empty('link', 'Abhi koi connection nahi', 'Jaise: WhatsApp API, SMS, webhook (Zapier / Make / Pabbly)')) + '</div></div>' + saveBtn;
      }
      await draw();
      el.addEventListener('click', function (e) { var t = e.target.closest('[data-tab]'); if (t) C.go('#/settings?tab=' + t.getAttribute('data-tab')); });
      tb.addEventListener('input', function (e) {
        var t = e.target, k;
        if ((k = t.getAttribute('data-c'))) co[k] = t.type === 'checkbox' ? (t.checked ? '1' : '0') : t.value;
        else if ((k = t.getAttribute('data-dd'))) { S.disc_defaults = S.disc_defaults || {}; S.disc_defaults[k] = Math.max(0, Math.min(100, parseFloat(t.value) || 0)); }
        else if ((k = t.getAttribute('data-hd'))) { S.hub = S.hub || {}; S.hub.docs = S.hub.docs || {}; S.hub.docs[k] = t.checked ? '1' : '0'; }
        else if ((k = t.getAttribute('data-hdc'))) { S.hub = S.hub || {}; S.hub.docs = S.hub.docs || {}; var hc = S.hub.docs.hide_cats || []; hc = hc.filter(function (z) { return z !== k; }); if (t.checked) hc.push(k); S.hub.docs.hide_cats = hc; }
        else if ((k = t.getAttribute('data-ben'))) { S.hub = S.hub || {}; S.hub.ben = S.hub.ben || {}; var bl = t.value.split('\n').map(function (x) { return x.trim(); }).filter(Boolean).slice(0, 12); var bd = (window.SPBEN ? SPBEN.KEYS.filter(function (z) { return z.k === k; })[0] : null); if (!bl.length || (bd && bl.join('|') === bd.def.join('|'))) delete S.hub.ben[k]; else S.hub.ben[k] = bl; }
        else if ((k = t.getAttribute('data-hub'))) { S.hub = S.hub || {}; S.hub[k] = Math.max(0, Math.min(k === 'tariff' ? 100 : 12, parseFloat(t.value) || 0)); }
        else if ((k = t.getAttribute('data-stk'))) { S.stock = S.stock || {}; S.stock[k] = Math.max(0, Math.min(100, parseFloat(t.value) || 0)); }
        else if ((k = t.getAttribute('data-px'))) S.prefix[k] = t.value.toUpperCase().replace(/[^A-Z0-9-]/g, '');
        else if (t.hasAttribute('data-acc')) S.accountants[+t.getAttribute('data-acc')][t.getAttribute('data-k')] = t.value;
        else if ((k = t.getAttribute('data-tplk'))) { S.templates = S.templates || {}; S.templates[k] = t.value.split('\n').map(function (x) { return x.trim(); }).filter(Boolean).slice(0, 40); }
        else if (t.hasAttribute('data-cn')) S.secrets.connections[+t.getAttribute('data-cn')][t.getAttribute('data-k')] = t.type === 'checkbox' ? t.checked : t.value;
      });
      tb.addEventListener('change', async function (e) {
        if (e.target.id !== 'rsFile') return;
        var info = $('#rsInfo', tb), go = $('#rsGo', tb), f = e.target.files && e.target.files[0]; tb._bk = null; go.disabled = true; info.textContent = '';
        if (!f) return;
        try {
          info.textContent = 'File padh rahe hain…'; var B = await readBackup(f); tb._bk = B;
          var L = BK_LBL;
          info.innerHTML = C.pill('Backup sahi hai ✔') + ' ' + esc(B.json.at || '') + '<div class="row wrap" style="gap:6px 14px;margin:8px 0">' + RS_PARTS.map(function (k) { var n = k === 'crm_files' ? Object.keys(B.files).length : (B.json[k] || []).length; return n ? '<label class="ck" style="margin:0"><input type="checkbox" data-rsp="' + k + '" checked> ' + esc(L[k]) + ': <b>' + n + '</b></label>' : ''; }).filter(Boolean).join('') + '</div>' + ((B.json.crm_records || []).length ? '<div class="row wrap" style="gap:6px 14px"><span class="xs mute">Records me se:</span>' : '<div hidden>') + Object.keys(BK_KINDS).filter(function (k) { return (B.json.crm_records || []).some(function (x) { return x.kind === k; }); }).map(function (k) { return '<label class="ck" style="margin:0"><input type="checkbox" data-rsk="' + k + '" checked> ' + esc(BK_KINDS[k]) + ' (' + (B.json.crm_records || []).filter(function (x) { return x.kind === k; }).length + ')</label>'; }).join('') + '</div>';
          go.disabled = false;
        } catch (er) { info.innerHTML = '<span style="color:var(--red)">' + esc(er.message) + '</span>'; }
      });
      tb.addEventListener('change', function (e) { var t = e.target; if (t.hasAttribute('data-cn')) S.secrets.connections[+t.getAttribute('data-cn')][t.getAttribute('data-k')] = t.type === 'checkbox' ? t.checked : t.value; });
      async function runBk(wantP, wantK, rowFilt, fname, label) {
        var pin = $('#bkPin', tb).value, st = $('#bkStat', tb);
        if (!/^\d{6}$/.test(pin)) return C.toast('Apna 6 ank ka PIN daalein', true);
        if (!wantP.length) return C.toast('Kam se kam ek hissa chunein', true);
        C.busy(true); st.textContent = 'Shuru…';
        try {
          var meta = await C.call('crm_backup', { pin: pin, part: 'meta' }); if (meta.error) throw new Error(meta.error);
          meta.group = label; var out = { meta: meta }, files = [], cnt = {};
          for (var i = 0; i < meta.parts.length; i++) {
            var part = meta.parts[i]; if (meta.counts[part] == null || wantP.indexOf(part) < 0) continue;
            var off = 0, rows = [];
            while (off != null) {
              st.textContent = label + ' — le rahe hain: ' + (BK_LBL[part] || part) + ' (' + rows.length + ' / ' + meta.counts[part] + ')';
              var r = await C.call('crm_backup', { pin: pin, part: part, offset: off }); if (r.error) throw new Error(r.error);
              rows = rows.concat(r.rows); off = r.next;
            }
            if (part === 'crm_records') rows = rows.filter(function (x) { return wantK.indexOf(x.kind) >= 0; });
            if (rowFilt && rowFilt[part]) rows = rows.filter(rowFilt[part]);
            if (part === 'crm_files') rows.forEach(function (f) { var bin = atob(f.b64), u = new Uint8Array(bin.length); for (var k = 0; k < bin.length; k++) u[k] = bin.charCodeAt(k); var ext = (String(f.mime).split('/')[1] || 'bin').replace(/[^a-z0-9]/gi, '').slice(0, 5); files.push({ name: 'files/' + f.id + '-rec' + f.rec_id + '.' + ext, data: u }); delete f.b64; });
            out[part] = rows; cnt[part] = rows.length;
          }
          meta.counts = cnt;
          st.textContent = 'Zip bana rahe hain…';
          var sheets = [], used = {}, cell = function (v) { v = v == null ? '' : typeof v === 'object' ? JSON.stringify(v) : v; return typeof v === 'string' && v.length > 32000 ? v.slice(0, 32000) : v; };
          function sheet(name, rows) {
            if (!rows || !rows.length) return; name = String(name).replace(/[\[\]:*?\/\\]/g, ' ').slice(0, 28); var nm = name, n = 2; while (used[nm.toLowerCase()]) nm = name.slice(0, 25) + ' ' + (n++); used[nm.toLowerCase()] = 1;
            var ks = []; rows.forEach(function (o) { Object.keys(o).forEach(function (k) { if (ks.indexOf(k) < 0) ks.push(k); }); });
            sheets.push({ name: nm, rows: [ks].concat(rows.map(function (o) { return ks.map(function (k) { return cell(o[k]); }); })), widths: ks.map(function () { return 16; }) });
          }
          var byKind = {}; (out.crm_records || []).forEach(function (x) { (byKind[x.kind] = byKind[x.kind] || []).push(x); });
          Object.keys(byKind).sort().forEach(function (k) { sheet('CRM ' + (BK_KINDS[k] || k), byKind[k]); });
          Object.keys(out).forEach(function (k) { if (k === 'meta' || k === 'crm_records' || k === 'sp_store' || k === 'crm_settings' || k === 'crm_auth_admin') return; sheet(BK_LBL[k] || k, out[k]); });
          var xl = window.XLSXLite.write(sheets.length ? sheets : [{ name: 'Khaali', rows: [['Koi data nahi (ya ye hissa sirf backup.json me hai)']] }]);
          var list = Object.keys(cnt).map(function (k) { return ' - ' + (BK_LBL[k] || k) + ': ' + cnt[k]; }).join('\r\n');
          var zip = window.XLSXLite.zip([{ name: 'backup.json', data: JSON.stringify(out) }, { name: 'backup.xlsx', data: new Uint8Array(await xl.arrayBuffer()) }, { name: 'PADHEIN.txt', data: 'Sunpowers ' + label + ' - ' + meta.at + '\r\nbackup.json = poora data (wapas lane ke liye)\r\nbackup.xlsx = Excel me padhne ke liye\r\nfiles/ = documents\r\nWebsite / Store ka content backup.json me "sp_store" ke andar hai.\r\n\r\n' + list + '\r\n' }].concat(files));
          C.download(zip, 'sunpowers-' + fname + '-backup-' + C.today() + '.zip');
          st.innerHTML = C.pill(label + ' ho gaya ✔') + ' ' + esc(Object.keys(cnt).map(function (k) { return (BK_LBL[k] || k) + ': ' + cnt[k]; }).join(' • '));
          $('#bkPin', tb).value = '';
        } catch (e) { st.innerHTML = '<span style="color:var(--red)">' + esc(e.message) + '</span>'; C.toast(e.message, true); } finally { C.busy(false); }
      }
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
        pgsee: async function () {
          var days = +($('#pgDays', el).value) || 90, r = await C.call('crm_purge', { days: days, run: false });
          $('#pgOut', el).innerHTML = '<div class="note">' + r.quotes + ' purani quotation aur ' + r.enquiries + ' band enquiry mili (' + days + ' din se purani).</div>' + (r.quotes + r.enquiries ? '<button class="btn btn-r" style="margin-top:10px" data-act="pgrun">' + C.ic('trash') + ' Haan, saaf karein</button>' : '');
        },
        pgrun: async function () {
          var days = +($('#pgDays', el).value) || 90; if (!(await C.confirm('Ye purani quotation aur enquiry hamesha ke liye hat jayengi. Bill / payment safe rahenge. Aage badhein?', 'Haan, saaf karein', true))) return;
          var r = await C.run('crm_purge', { days: days, run: true }, null); C.toast(r.quotes + ' quotation + ' + r.enquiries + ' enquiry saaf ho gayi ✔'); C.render();
        },
        rsgo: async function () {
          var pin = $('#rsPin', tb).value, st = $('#rsStat', tb), B = tb._bk;
          if (!B) return C.toast('Pehle backup file chunein', true);
          if (!/^\d{6}$/.test(pin)) return C.toast('Apna 6 ank ka PIN daalein', true);
          var wantP = picked(tb, 'data-rsp'), wantK = picked(tb, 'data-rsk'); if (!wantP.length) return C.toast('Kam se kam ek hissa chunein', true);
          var rowsOf = function (k) { var r0 = B.json[k] || []; return k === 'crm_records' ? r0.filter(function (x) { return wantK.indexOf(x.kind) >= 0; }) : r0; };
          var tot = RS_PARTS.reduce(function (a, k) { return a + (wantP.indexOf(k) >= 0 ? rowsOf(k).length : 0); }, 0);
          if (!(await C.confirm('Backup ke ' + tot + ' record wapas jodein? Jo pehle se hai wo usi number par backup wala ho jayega; naya data safe rahega.', 'Haan, wapas laao'))) return;
          C.busy(true); var done = 0;
          try {
            for (var i = 0; i < RS_PARTS.length; i++) {
              var part = RS_PARTS[i], rows = wantP.indexOf(part) >= 0 ? rowsOf(part) : []; if (!rows.length) continue;
              var chunk = [], size = 0, flush = async function () {
                if (!chunk.length) return;
                st.textContent = 'Wapas la rahe hain: ' + part + ' (' + done + ' / ' + tot + ')';
                var r = await C.call('crm_restore', { pin: pin, part: part, rows: chunk }); if (r.error) throw new Error(r.error);
                done += chunk.length; chunk = []; size = 0;
              };
              for (var j = 0; j < rows.length; j++) {
                var row = rows[j];
                if (part === 'crm_files') { var u = B.files[String(row.id)]; if (!u) continue; row = Object.assign({}, row, { b64: b64of(u) }); }
                var len = JSON.stringify(row).length;
                if (chunk.length && (chunk.length >= (part === 'crm_files' ? 3 : 100) || size + len > 700000)) await flush();
                chunk.push(row); size += len;
              }
              await flush();
            }
            st.innerHTML = C.pill('Restore ho gaya ✔') + ' ' + done + ' record wapas aaye.'; $('#rsPin', tb).value = ''; C.toast('Backup se data wapas aa gaya ✔');
          } catch (e) { st.innerHTML = '<span style="color:var(--red)">' + esc(e.message) + '</span>'; C.toast(e.message, true); } finally { C.busy(false); }
        },
        bkgo: function () { return runBk(picked(tb, 'data-bkp'), picked(tb, 'data-bkk'), null, 'master', 'Master backup'); },
        bkgrp: function (k) { var g = BK_GRP[k]; if (!g) return; return runBk(g.parts, Object.keys(BK_KINDS), g.rows, g.f, g.l); },
        lgchk: async function (id, b) { try { b.outerHTML = await mailStatus(+id); } catch (e) { C.toast(e.message, true); } },
        save: function () { save(); },
        tplreset: function (k) { S.templates = S.templates || {}; delete S.templates[k]; var ta = $('[data-tplk="' + k + '"]', tb); if (ta) ta.value = (C.TPL_DEF[k] || []).join('\n'); },
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
