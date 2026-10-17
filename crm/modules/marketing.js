/* Marketing & Grow — agency / manager, channels (digital + traditional), lead source report, marketing team access */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  C.CH_TYPES = [
    ['facebook', 'Facebook / Instagram Ads', 'd'], ['google', 'Google Ads / Search', 'd'], ['youtube', 'YouTube', 'd'], ['website', 'Website / SEO', 'd'],
    ['whatsapp', 'WhatsApp campaign', 'd'], ['indiamart', 'IndiaMART / JustDial', 'd'], ['api', 'Doosra app (API link)', 'd'],
    ['led', 'LED screen', 't'], ['tv', 'TV ad', 't'], ['radio', 'Radio / FM', 't'], ['podcast', 'Podcast', 't'], ['live', 'Live broadcast', 't'],
    ['newspaper', 'Newspaper', 't'], ['canopy', 'Canopy / stall / camp', 't'], ['hoarding', 'Hoarding / banner', 't'], ['pamphlet', 'Pamphlet / flyer', 't'], ['event', 'Event / exhibition', 't'], ['other', 'Doosra', 't']
  ];
  var TYPE = {}; C.CH_TYPES.forEach(function (x) { TYPE[x[0]] = x; });
  var SCOPE = ['Facebook / Instagram ads', 'Google ads', 'Social media posts', 'Website / SEO', 'LED / TV / Radio', 'Newspaper / print', 'Events / canopy', 'Video shoot'];
  C.mktCache = null;
  C.sourceList = function () { var out = C.SOURCES.slice(), ch = (((C.cache.settings || {}).marketing || {}).channels || (C.mktCache || {}).channels || []); ch.forEach(function (c) { if (c.on !== false && c.name && out.indexOf(c.name) < 0) out.splice(out.length - 1, 0, c.name); }); return out; };
  C.channelName = function (codeOrName) { var v = String(codeOrName || ''), ch = (((C.cache.settings || {}).marketing || {}).channels || []), c = ch.find(function (x) { return x.code && x.code === v.toUpperCase(); }); return c ? c.name : v; };
  C.mktLoad = async function () { try { C.mktCache = await C.call('crm_mkt_get', {}); } catch (e) { C.mktCache = C.mktCache || {}; } return C.mktCache; };

  function code(name, list) { var b = String(name || 'CH').toUpperCase().replace(/[^A-Z0-9]+/g, '').slice(0, 6) || 'CH', c = b, i = 1; while (list.some(function (x) { return x.code === c; })) c = b + (++i); return c; }
  function chLink(c) { var u = C.siteUrl() || C.storeUrl(); if (!u) return ''; return u + (u.indexOf('?') >= 0 ? '&' : '?') + 'src=' + encodeURIComponent(c.code || ''); }
  function daysLeft(c) { if (!c.end) return null; return Math.round((C.pd(c.end) - C.pd(C.today())) / 864e5); }

  async function save(M, keys, msg) { var d = C.clone(M); delete d.keys; delete d.can_manage; delete d.can_leads; await C.run('crm_mkt_save', { data: d, keys: keys }, msg || 'Save ho gaya ✔'); C.mktCache = null; }

  /* --- first question: agency / manager hire? --- */
  function askHire(M, keys) {
    return new Promise(function (res) {
      var m = C.modal({ title: 'Marketing & Grow', size: 'sm', body: '<div style="text-align:center;padding:6px 0 4px"><div style="font-size:40px">📣</div><h3 style="margin:8px 0 6px">Kya aap marketing agency ya marketing manager hire kar rahe hain?</h3><p class="mute sm">Haan kahein to unki jaankari save ho jayegi aur unki CRM ID bhi bana sakte hain.</p></div>',
        foot: '<button class="btn btn-o" data-no>Nahi, khud karenge</button><button class="btn btn-p" data-yes>' + C.ic('check') + ' Haan</button>', onClose: function () { res(false); } });
      $('[data-no]', m.el).onclick = async function () { M.asked = true; M.agency = null; try { await save(M, keys, 'Theek hai — channels khud set karein'); } catch (e) {} m.el.remove(); document.documentElement.style.overflow = ''; res(true); };
      $('[data-yes]', m.el).onclick = async function () { m.el.remove(); document.documentElement.style.overflow = ''; var ok = await agencyForm(M, keys); res(ok); };
    });
  }
  function agencyForm(M, keys) {
    var a = M.agency || {};
    return new Promise(function (res) {
      var body = '<form id="agf" class="fg">' + C.f('Agency / company ka naam', C.inp('agency', a.agency, 'maxlength="120" placeholder="Jaise: ABC Digital"')) + C.f('Manager / contact person ka naam *', C.inp('manager', a.manager, 'maxlength="80"')) +
        C.f('Mobile *', C.inp('mobile', a.mobile, 'inputmode="tel" maxlength="14"')) + C.f('Email', C.inp('email', a.email, 'type="email"')) +
        C.f('Kab se', C.inp('start', a.start || C.today(), 'type="date"')) + C.f('Mahine ki fees / budget (₹)', C.inp('fees', a.fees, 'inputmode="decimal"')) +
        '<div class="f full"><label>Kya-kya kaam karenge</label><div class="chips" id="agsc">' + SCOPE.map(function (x) { return '<button type="button" data-sc="' + esc(x) + '" class="' + ((a.scope || []).indexOf(x) >= 0 ? 'on' : '') + '">' + esc(x) + '</button>'; }).join('') + '</div></div>' +
        C.f('Agreement / note', C.ta('note', a.note, 'rows="2"'), 'full') + (a.manager ? '' : '<div class="f full"><label class="ck"><input type="checkbox" name="mkid" checked> Manager ki CRM login ID bhi banayein (password se, bina OTP)</label></div>') + '</form>';
      var m = C.modal({ title: 'Marketing agency / manager', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(false); } });
      m.el.addEventListener('click', function (e) { var b = e.target.closest('[data-sc]'); if (b) b.classList.toggle('on'); });
      $('[data-ok]', m.el).onclick = async function () {
        var f = $('#agf', m.el), o = C.form(f); if (!C.need(f, ['manager', 'mobile'])) return;
        if (!C.validMob(o.mobile)) { f.mobile.classList.add('bad'); return C.toast('Sahi 10 ank ka mobile likhein', true); }
        var mk = o.mkid; delete o.mkid; o.scope = $$('#agsc .on', m.el).map(function (b) { return b.getAttribute('data-sc'); }); o.mobile = C.mob(o.mobile);
        M.asked = true; M.agency = o;
        try { await save(M, keys, 'Agency / manager save ho gaya ✔'); } catch (e) { return; }
        m.el.remove(); document.documentElement.style.overflow = ''; res(true);
        if (mk && C.canAny('users.manage') ) await mktUserForm(null, { name: o.manager, mobile: o.mobile, email: o.email, agency: o.agency });
      };
    });
  }

  /* --- marketing login IDs (password + security sawal) --- */
  function mktUserForm(u, pre) {
    var isNew = !u; u = u || Object.assign({ status: 'active', meta: {} }, pre ? { name: pre.name, mobile: pre.mobile, email: pre.email, meta: { agency: pre.agency } } : {});
    return new Promise(function (res) {
      var body = '<form id="muf" class="fg">' + C.f('Naam *', C.inp('name', u.name, 'maxlength="80"')) + C.f('Username *' + (isNew ? '' : ' <span class="o">(badal nahi sakte)</span>'), C.inp('username', u.username || (pre && pre.mobile ? 'mkt' + pre.mobile.slice(-4) : ''), isNew ? 'autocomplete="off"' : 'readonly')) +
        C.f('Mobile', C.inp('mobile', u.mobile, 'inputmode="tel"')) + C.f('Email <span class="o">(optional)</span>', C.inp('email', u.email, 'type="email"')) + C.f('Agency', C.inp('agency', (u.meta || {}).agency)) +
        (isNew ? '' : C.f('Status', C.sel('status', [['active', 'Chalu'], ['blocked', 'Band']], u.status))) +
        C.f(isNew ? 'Password * <span class="o">(kam se kam 8 akshar)</span>' : 'Naya password <span class="o">(sirf badalna ho to)</span>', '<input class="inp" name="password" type="text" autocomplete="off" minlength="8">') +
        '<p class="hint full">Login me OTP nahi aata — user ID + password se login karega, pehli baar 2 security sawal set karega. Password bhoolne par woh sawal ke jawab se naya bana sakta hai, warna Admin yahan se reset karega.</p></form>';
      var m = C.modal({ title: isNew ? 'Naya marketing user' : u.name, body: body, foot: (isNew ? '' : '<button class="btn btn-o" data-rq style="margin-right:auto">Security sawal reset</button><button class="btn btn-o" data-ul>Unlock</button>') + '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      var f = $('#muf', m.el);
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (!C.need(f, ['name'].concat(isNew ? ['username', 'password'] : []))) return;
        if (o.password && o.password.length < 8) { f.password.classList.add('bad'); return C.toast('Password kam se kam 8 akshar ka ho', true); }
        if (o.mobile && !C.validMob(o.mobile)) return C.toast('Mobile sahi likhein', true);
        var user = { id: u.id || null, name: o.name, mobile: o.mobile, email: o.email, agency: o.agency, status: o.status || 'active' }; if (o.password) user.password = o.password; if (isNew) user.username = o.username.toLowerCase();
        try {
          await C.run('crm_mkt_user', { user: user }, isNew ? 'Marketing ID ban gayi ✔' : 'Save ho gaya ✔'); C.cache.users = null; m.el.remove(); document.documentElement.style.overflow = ''; res(true);
          if (o.password && o.mobile && await C.confirm('Login detail WhatsApp par bhejein?', 'Haan')) window.open(C.wa(o.mobile, 'Namaste ' + o.name + ' ji, ' + (C.company().name || '') + ' CRM me aapki marketing ID taiyaar hai.\nLink: ' + location.href.split('#')[0] + '\nUser ID: ' + (isNew ? o.username.toLowerCase() : u.username) + '\nPassword: ' + o.password + '\nPehli baar login par 2 security sawal set karein.'), '_blank');
        } catch (e) {}
      };
      var rq = $('[data-rq]', m.el); if (rq) rq.onclick = async function () { if (await C.confirm(u.name + ' ke security sawal hata dein? Agli login par naye set karega.', 'Haan')) { try { await C.run('crm_mkt_user', { action: 'reset_q', user: { id: u.id } }, 'Sawal reset ho gaye ✔'); } catch (e) {} } };
      var ul = $('[data-ul]', m.el); if (ul) ul.onclick = async function () { try { await C.run('crm_mkt_user', { action: 'unlock', user: { id: u.id } }, 'Unlock ho gaya ✔'); } catch (e) {} };
    });
  }

  /* --- channel form --- */
  function chForm(M, keys, c) {
    var isNew = !c, list = M.channels = M.channels || []; c = c ? C.clone(c) : { id: 'ch' + Date.now().toString(36), type: 'facebook', on: true, start: C.today() };
    return new Promise(function (res) {
      var body = '<form id="chf" class="fg">' + C.f('Channel *', '<select class="inp" name="type">' + ['d', 't'].map(function (g) { return '<optgroup label="' + (g === 'd' ? 'Digital / API' : 'Traditional') + '">' + C.CH_TYPES.filter(function (x) { return x[2] === g; }).map(function (x) { return '<option value="' + x[0] + '"' + (c.type === x[0] ? ' selected' : '') + '>' + esc(x[1]) + '</option>'; }).join('') + '</optgroup>'; }).join('') + '</select>') +
        C.f('Naam * <span class="o">(lead ke "Source" me yahi dikhega)</span>', C.inp('name', c.name || '', 'maxlength="60" placeholder="Jaise: LED — Kapoorthala chauraha"')) +
        C.f('Kharcha (₹)', C.inp('cost', c.cost, 'inputmode="decimal"')) + C.f('Kharcha kaisa', C.sel('cost_mode', [['month', 'Har mahine'], ['total', 'Poora campaign']], c.cost_mode || 'month')) +
        C.f('Kab se', C.inp('start', c.start, 'type="date"')) + C.f('Kab tak', C.inp('end', c.end, 'type="date"')) +
        C.f('Tracking code', C.inp('code', c.code || '', 'maxlength="10" style="text-transform:uppercase" placeholder="Apne aap banega"')) + C.f('Kiske paas <span class="o">(vendor / agency)</span>', C.inp('vendor', c.vendor, 'maxlength="80"')) +
        '<div class="f full" data-dig><label>API key / token <span class="o">(sirf Admin / marketing manager dekh sakta hai)</span></label><input class="inp" name="key" type="password" autocomplete="off" value="' + esc((keys || {})[c.id] || '') + '"><span class="hint">Lead form link neeche "Copy" se milega — ad / QR / bio me lagayein, us link se aayi enquiry is channel ke naam se aayegi.</span></div>' +
        C.f('Note', C.ta('note', c.note, 'rows="2"'), 'full') + '<div class="f full"><label class="ck"><input type="checkbox" name="on"' + (c.on !== false ? ' checked' : '') + '> Chalu hai</label></div></form>';
      var m = C.modal({ title: isNew ? 'Naya channel' : c.name, body: body, foot: (isNew ? '' : '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + '</button>') + '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(false); } });
      var f = $('#chf', m.el); function dig() { $('[data-dig]', m.el).hidden = (TYPE[f.type.value] || [])[2] !== 'd'; } dig(); f.type.onchange = function () { dig(); if (!f.name.value) f.name.placeholder = (TYPE[f.type.value] || [])[1] || ''; };
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (!o.name) o.name = (TYPE[o.type] || [])[1] || ''; if (!o.name) { f.name.classList.add('bad'); return; }
        var others = list.filter(function (x) { return x.id !== c.id; });
        if (others.some(function (x) { return x.name.toLowerCase() === o.name.toLowerCase(); })) return C.toast('Is naam ka channel pehle se hai', true);
        var k = o.key; delete o.key; Object.assign(c, o, { cost: C.r2(o.cost || 0), code: (o.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '') || code(o.name, others) });
        keys = Object.assign({}, keys || {}); if ((TYPE[c.type] || [])[2] === 'd' && k) keys[c.id] = k; else delete keys[c.id];
        M.channels = others.concat([c]);
        try { await save(M, keys, 'Channel save ho gaya ✔'); m.el.remove(); document.documentElement.style.overflow = ''; res(true); } catch (e) {}
      };
      var del = $('[data-del]', m.el); if (del) del.onclick = async function () { if (!(await C.confirm(c.name + ' channel hatayein? Purani leads ka source waise hi rahega.', 'Hatao', true))) return; M.channels = list.filter(function (x) { return x.id !== c.id; }); keys = Object.assign({}, keys || {}); delete keys[c.id]; try { await save(M, keys, 'Channel hata diya'); m.el.remove(); document.documentElement.style.overflow = ''; res(true); } catch (e) {} };
    });
  }

  /* --- lead source report (used by Home too) --- */
  C.sourceReport = function (S, M, compact) {
    var src = (S && S.sources) || [], ch = ((M || {}).channels || []), byName = {};
    ch.forEach(function (c) { byName[c.name.toLowerCase()] = c; });
    var tot = src.reduce(function (a, x) { return a + x.leads; }, 0), mon = src.reduce(function (a, x) { return a + x.month; }, 0), won = src.reduce(function (a, x) { return a + x.won; }, 0);
    if (!src.length) return C.empty('megaphone', 'Abhi koi lead nahi', 'Lead jodte samay "Kahan se aayi" (Source) chunein — report yahin banegi.');
    var mx = Math.max.apply(null, src.map(function (x) { return x.leads; }).concat([1]));
    var rows = src.slice(0, compact ? 6 : 100).map(function (x) {
      var c = byName[String(x.source).toLowerCase()], cost = c ? num(c.cost) : 0, cpl = c && cost && x.leads ? cost / x.leads : 0;
      return '<tr><td><b>' + esc(x.source) + '</b>' + (c ? ' ' + C.pill((TYPE[c.type] || [0, 'Channel'])[1], 'g') : '') + '<div class="srcbar"><i style="width:' + Math.round(x.leads * 100 / mx) + '%"></i></div></td><td class="r">' + x.leads + '</td><td class="r">' + x.month + '</td><td class="r">' + x.won + '</td>' + (compact ? '' : '<td class="r">' + x.lost + '</td><td class="r">' + (x.leads ? Math.round(x.won * 100 / x.leads) : 0) + '%</td><td class="r">' + (cpl ? money(cpl) : '—') + '</td>') + '</tr>';
    }).join('');
    return (compact ? '' : '<div class="kpis">' + C.kpi('Kul leads', tot, '', 'gold') + C.kpi('Is mahine', mon) + C.kpi('Jeeti (customer bane)', won) + C.kpi('Conversion', (tot ? Math.round(won * 100 / tot) : 0) + '%') + '</div>') +
      '<div class="tw"><table class="t"><thead><tr><th>Kahan se aayi</th><th class="r">Leads</th><th class="r">Is mahine</th><th class="r">Jeeti</th>' + (compact ? '' : '<th class="r">Haari</th><th class="r">Conversion</th><th class="r">Kharcha / lead</th>') + '</tr></thead><tbody>' + rows + '</tbody></table></div>';
  };

  C.mod('marketing', {
    title: 'Marketing & Grow',
    allowed: function () { return C.canAny('marketing.view', 'marketing.manage', 'marketing.leads'); },
    render: async function (el, params, q) {
      var M = C.clone(await C.mktLoad()), keys = M.keys || {}, man = !!M.can_manage, admin = C.canAny('users.manage');
      M.channels = M.channels || [];
      if (man && !M.asked && !q.tab) { el.innerHTML = C.loading(); var asked = await askHire(M, keys); if (asked) return C.render(); }
      var tab = q.tab || 'overview', tabs = [['overview', 'Overview'], ['channels', 'Channels'], ['platforms', 'Platforms (Auto + Manual)']].concat(man ? [['agency', 'Agency / Manager']] : []).concat(admin ? [['team', 'Team & Access']] : []);
      var h = '<div class="ph"><div><h1>Marketing &amp; Grow</h1><p>Har lead kahan se aayi, kitna kharcha, kitni customer bani — sab ek jagah.</p></div><div class="row">' + (man ? '<button class="btn btn-p" data-act="chadd">' + C.ic('plus') + ' Channel jodein</button>' : '') + '</div></div>' +
        '<div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + t[1] + '</button>'; }).join('') + '</div><div id="mk"></div>';
      el.innerHTML = h; var box = $('#mk', el);
      el.addEventListener('click', function (e) { var t = e.target.closest('[data-tab]'); if (t) C.go('#/marketing?tab=' + t.getAttribute('data-tab')); });
      async function overview() {
        var S = null; if (M.can_leads) { try { S = await C.call('crm_mkt_stats', {}); } catch (e) { C.toast(e.message, true); } }
        var on = M.channels.filter(function (c) { return c.on !== false; }), spend = C.sum(on.filter(function (c) { return c.cost_mode !== 'total'; }), 'cost');
        var a = M.agency;
        box.innerHTML = (a ? '<div class="note g" style="margin-bottom:12px">' + C.ic('megaphone') + ' Marketing: <b>' + esc(a.agency || a.manager) + '</b>' + (a.agency && a.manager ? ' — ' + esc(a.manager) : '') + (a.mobile ? ' · ' + esc(a.mobile) : '') + (num(a.fees) ? ' · ' + money(a.fees) + '/mahina' : '') + '</div>' : '') +
          '<div class="kpis">' + C.kpi('Chalu channels', on.length, M.channels.length + ' kul', '', '#/marketing?tab=channels') + C.kpi('Mahine ka kharcha', money(spend + num(a && a.fees)), a && num(a.fees) ? 'agency fees shamil' : '') + '</div>' +
          (S ? '<div class="card"><div class="hd"><h3>Lead kahan se aayi</h3></div>' + C.sourceReport(S, M) + '</div>' +
            ((S.enquiries || []).length ? '<div class="card" style="margin-top:14px"><div class="hd"><h3>Website / Store enquiry — channel ke hisab se</h3></div><div class="tw"><table class="t"><thead><tr><th>Channel / source</th><th class="r">Enquiry</th></tr></thead><tbody>' + S.enquiries.map(function (x) { var cc = M.channels.find(function (c) { return c.code && c.code === String(x.source).toUpperCase(); }); return '<tr><td>' + esc(cc ? cc.name + ' (' + cc.code + ')' : x.source) + '</td><td class="r">' + x.enquiries + '</td></tr>'; }).join('') + '</tbody></table></div></div>' : '') +
            ((S.months || []).length ? '<div class="card" style="margin-top:14px"><div class="hd"><h3>Mahine ke hisab se</h3></div><div class="tw"><table class="t"><thead><tr><th>Mahina</th><th class="r">Leads</th><th class="r">Jeeti</th></tr></thead><tbody>' + S.months.slice().reverse().map(function (x) { return '<tr><td>' + esc(x.month) + '</td><td class="r">' + x.leads + '</td><td class="r">' + x.won + '</td></tr>'; }).join('') + '</tbody></table></div></div>' : '')
            : '<div class="card">' + C.empty('lock', 'Lead report dekhne ki permission nahi', 'Admin se "Lead kahan se aayi (source report) dekhe" permission maangein') + '</div>');
      }
      function channels() {
        var groups = [['d', 'Digital / API'], ['t', 'Traditional']];
        box.innerHTML = (M.channels.length ? groups.map(function (g) {
          var list = M.channels.filter(function (c) { return ((TYPE[c.type] || [])[2] || 't') === g[0]; }); if (!list.length) return '';
          return '<div class="sec-t">' + g[1] + '</div><div class="list">' + list.map(function (c) {
            var dl = daysLeft(c), lk = chLink(c);
            return '<div class="li' + (man ? ' click' : '') + '"' + (man ? ' data-act="chedit" data-id="' + esc(c.id) + '"' : '') + '><span class="av ' + (c.on === false ? 'g' : g[0] === 'd' ? 'b' : 'o') + '">' + C.ic('megaphone') + '</span><span class="grow"><span class="t">' + esc(c.name) + ' ' + (c.on === false ? C.pill('Band', 'g') : C.pill('Chalu')) + '</span><span class="m"><span>' + esc((TYPE[c.type] || [0, c.type])[1]) + '</span>' + (c.code ? '<span>Code: <b>' + esc(c.code) + '</b></span>' : '') + (num(c.cost) ? '<span>' + money(c.cost) + (c.cost_mode === 'total' ? ' kul' : '/mahina') + '</span>' : '') + (c.vendor ? '<span>' + esc(c.vendor) + '</span>' : '') + (dl != null ? '<span' + (dl < 0 ? ' style="color:var(--red)"' : dl <= 7 ? ' style="color:var(--org,#e8590c)"' : '') + '>' + C.ic('clock') + (dl < 0 ? 'Khatam ' + C.fd(c.end) : dl + ' din baaki') + '</span>' : '') + '</span></span>' +
              (lk ? '<span class="acts"><button class="btn btn-o btn-sm" data-act="chcopy" data-id="' + esc(c.id) + '" title="Lead link copy karein" style="display:inline-flex">' + C.ic('link') + '<span class="desk-only">Link</span></button></span>' : '') + '</div>';
          }).join('') + '</div>';
        }).join('') : '<div class="card">' + C.empty('megaphone', 'Abhi koi channel nahi', man ? 'LED, TV, newspaper, Facebook ads… jo bhi chala rahe hain, "Channel jodein" se jodein. Lead ke Source me yahi naam aayega.' : '') + '</div>');
      }
      function agency() {
        var a = M.agency;
        box.innerHTML = '<div class="card">' + (a ? '<div class="fg">' + [['Agency', a.agency], ['Manager', a.manager], ['Mobile', a.mobile], ['Email', a.email], ['Kab se', C.fd(a.start)], ['Fees / budget', num(a.fees) ? money(a.fees) + '/mahina' : ''], ['Kaam', (a.scope || []).join(', ')], ['Note', a.note]].filter(function (x) { return x[1]; }).map(function (x) { return '<div><div class="xs mute">' + x[0] + '</div><b>' + esc(x[1]) + '</b></div>'; }).join('') + '</div><div class="row wrap" style="margin-top:14px">' + C.callBtns(a.mobile) + '<span class="grow"></span><button class="btn btn-r btn-sm" data-act="agdel">Hatayein</button><button class="btn btn-o" data-act="agedit">' + C.ic('edit') + ' Badlein</button></div>' :
          C.empty('users', 'Koi agency / manager nahi', 'Marketing khud kar rahe hain.', '<button class="btn btn-p" data-act="agedit">' + C.ic('plus') + ' Agency / manager jodein</button>')) + '</div>';
      }
      async function team() {
        var us = (await C.users(true)) || [], mk = us.filter(function (u) { return u.role === 'marketing'; }), staff = us.filter(function (u) { return u.role !== 'marketing' && u.role !== 'consumer' && u.role !== 'admin'; });
        box.innerHTML = '<div class="card"><div class="hd"><h3>Marketing login IDs</h3><button class="btn btn-p btn-sm" data-act="muadd">' + C.ic('plus') + ' Naya marketing user</button></div><p class="mute sm" style="margin-bottom:10px">Inka login <b>bina OTP</b> — User ID + password, aur security sawal. Password Admin yahan se reset kar sakta hai.</p>' +
          (mk.length ? '<div class="list">' + mk.map(function (u) { return '<div class="li click" data-act="muedit" data-id="' + u.id + '"><span class="av">' + esc(C.initials(u.name)) + '</span><span class="grow"><span class="t">' + esc(u.name) + ' ' + (u.status === 'active' ? C.pill('Chalu') : C.pill('Band', 'r')) + '</span><span class="m"><span>ID: ' + esc(u.username) + '</span>' + (u.mobile ? '<span>' + esc(u.mobile) + '</span>' : '') + ((u.meta || {}).agency ? '<span>' + esc(u.meta.agency) + '</span>' : '') + (u.last_seen ? '<span>Aakhri: ' + esc(C.fdt(u.last_seen)) + '</span>' : '') + '</span></span>' + C.ic('right') + '</div>'; }).join('') + '</div>' : C.empty('users', 'Koi marketing user nahi')) + '</div>' +
          '<div class="card" style="margin-top:14px"><div class="hd"><h3>Kaun kya dekh sakta hai</h3><button class="btn btn-p btn-sm" data-act="accsave">' + C.ic('check') + ' Save</button></div><p class="mute sm" style="margin-bottom:10px">Tick = us user ko dikhega. (Role ki default setting: Team → Role permission)</p><div class="tw"><table class="t"><thead><tr><th>User</th><th style="text-align:center">Marketing section</th><th style="text-align:center">Lead source report</th><th style="text-align:center">Channels badle</th></tr></thead><tbody>' +
          mk.concat(staff).map(function (u) { var p = u.perms || {}, rp = (C.me.roleDefs || {})[u.role] || {}; return '<tr><td><b>' + esc(u.name) + '</b> <span class="xs mute">' + esc(C.ROLE[u.role] || u.role) + '</span></td>' + ['marketing.view', 'marketing.leads', 'marketing.manage'].map(function (k) { var v = p[k] != null ? !!p[k] : (u.role === 'marketing' ? k !== 'marketing.manage' : false); return '<td style="text-align:center"><input type="checkbox" data-acc="' + u.id + '|' + k + '"' + (v ? ' checked' : '') + '></td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div></div>';
        box._us = us;
      }

      /* ---- Platforms: each lead source with AUTO (key / bulk) and MANUAL (form) side by side + the platform's login link ---- */
      var PLAT = [
        ['instagram', 'Instagram', 'Instagram', 'https://www.instagram.com/accounts/login/', 'fb_leads'],
        ['facebook', 'Facebook', 'Facebook', 'https://www.facebook.com/login/', 'fb_leads'],
        ['justdial', 'JustDial', 'JustDial', 'https://www.justdial.com/', 'justdial'],
        ['indiamart', 'IndiaMART', 'IndiaMART', 'https://seller.indiamart.com/', 'indiamart'],
        ['tradeindia', 'TradeIndia', 'TradeIndia', 'https://www.tradeindia.com/login/', 'tradeindia'],
        ['sulekha', 'Sulekha', 'Sulekha', 'https://www.sulekha.com/', 'sulekha'],
        ['metaads', 'Meta Ads (Facebook / Instagram)', 'Meta Ads', 'https://business.facebook.com/', 'fb_leads'],
        ['googleads', 'Google Ads', 'Google Ads', 'https://ads.google.com/', 'google_leads'],
        ['youtube', 'YouTube', 'YouTube', 'https://studio.youtube.com/', ''],
        ['whatsapp', 'WhatsApp Business', 'WhatsApp', 'https://business.whatsapp.com/', ''],
        ['website', 'Apni Website / Store', 'Website', '', '']
      ];
      async function platforms() {
        var cfg = {}; try { cfg = await C.call('crm_conn_get', {}); } catch (e) { cfg = null; }
        M.platforms = M.platforms || {};
        var canLead = C.can('leads.create');
        box.innerHTML = '<div class="note g" style="margin-bottom:12px">' + C.ic('key') + ' Har platform ke liye <b>Manual</b> (aap khud lead likhein ya Excel se daalein) aur <b>Auto</b> (key lagane par apne aap) dono hain. Platform ka <b>login link</b> aur apni ID yahin save rakhein — <b>password yahan save nahi hota</b>: login page par browser jab "Password save karein?" poochhe to Yes dabayein, agli baar ek click me login ho jayega. CRM kisi dusri site me khud login nahi kar sakta (unki suraksha ke niyam).</div>' +
          '<div class="grid g2">' + PLAT.map(function (x) {
            var info = M.platforms[x[0]] || {}, url = info.url || x[3], c = cfg && x[4] ? (cfg[x[4]] || {}) : null, keySet = c ? Object.keys(c).some(function (k) { return k !== 'enabled' && c[k] && c[k].set; }) : false;
            return '<div class="card"><div class="hd"><h3>' + esc(x[1]) + '</h3>' + (x[4] ? (cfg === null ? '' : keySet ? C.pill('Auto: key saved', 'o') : C.pill('Auto: key nahi', 'g')) : C.pill('Manual only', 'g')) + '</div>' +
              '<div class="stack">' + (canLead ? '<button class="btn btn-p" data-act="pman" data-id="' + x[0] + '">' + C.ic('plus') + ' Manual lead jodein</button><button class="btn btn-o" data-act="pbulk" data-id="' + x[0] + '">' + C.ic('upload') + ' Auto (Bulk) — Excel / CSV se</button>' : '') +
              (x[4] && C.isAdmin() ? '<a class="btn btn-o" href="#/connections?cat=leads">' + C.ic('link') + ' Auto (key) jodein — Connections</a>' : '') +
              (url ? '<a class="btn btn-o" target="_blank" rel="noopener" href="' + esc(url) + '">' + C.ic('globe') + ' Login kholo</a>' : '') +
              (man ? '<button class="btn btn-g btn-sm" data-act="pinfo" data-id="' + x[0] + '">' + C.ic('edit') + ' Login link / ID / notes</button>' : '') + '</div>' +
              (info.user || info.note ? '<div class="sm mute" style="margin-top:8px">' + (info.user ? 'ID: <b>' + esc(info.user) + '</b>' : '') + (info.note ? '<br>' + esc(info.note) : '') + '</div>' : '') + '</div>';
          }).join('') + '</div>' +
          '<p class="hint" style="margin-top:12px">Auto (key) se real lead-import tabhi chalega jab us platform ki API / approval mil jaye. Tab tak <b>Manual</b> ya <b>Auto (Bulk)</b> se leads daalein — dono me lead par platform ka naam (source) lag jata hai, isliye Growth graph me sahi dikhti hai.</p>';
      }
      async function draw() { if (tab === 'platforms') platforms(); else if (tab === 'channels') channels(); else if (tab === 'agency' && man) agency(); else if (tab === 'team' && admin) await team(); else await overview(); }
      await draw();
      C.bind(el, {
        pman: async function (id) { var x = PLAT.find(function (z) { return z[0] === id; }); var r = await C.leadForm(null, { source: x[2] }); if (r) C.toast('Lead jud gayi — source: ' + x[2]); },
        pbulk: async function (id) { var x = PLAT.find(function (z) { return z[0] === id; }); await C.leadImport(x[2]); },
        pinfo: async function (id) {
          var x = PLAT.find(function (z) { return z[0] === id; }), info = Object.assign({}, M.platforms[id] || {});
          var m2 = C.modal({ title: x[1] + ' — login jaankari', size: 'sm', body: '<form id="pf2" class="stack">' + C.f('Login link', C.inp('url', info.url || x[3], 'placeholder="https://..."')) + C.f('Login ID / email / mobile', C.inp('user', info.user || '', 'maxlength="120"')) + C.f('Notes', C.ta('note', info.note || '', 'rows="2" maxlength="300"')) + '<div class="note g">Password yahan mat likhein. Browser ka "Password save" use karein.</div></form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>' });
          $('[data-ok]', m2.el).onclick = async function () { var o = C.form($('#pf2', m2.el)); if (o.url && !/^https:\/\//i.test(o.url)) return C.toast('Link https:// se shuru hona chahiye', true); M.platforms[id] = { url: o.url, user: o.user, note: o.note }; try { await save(M, keys, 'Save ho gaya ✔'); m2.close(); C.render(); } catch (e) {} };
        },
        chadd: async function () { if (await chForm(M, keys)) C.render(); },
        chedit: async function (id, a, e) { if (e.target.closest('.acts')) return; var c = M.channels.find(function (x) { return x.id === id; }); if (c && await chForm(M, keys, c)) C.render(); },
        chcopy: function (id) { var c = M.channels.find(function (x) { return x.id === id; }); if (c) C.copy(chLink(c), 'Lead link copy ho gaya ✔'); },
        agedit: async function () { if (await agencyForm(M, keys)) C.render(); },
        agdel: async function () { if (!(await C.confirm('Agency / manager ki jaankari hatayein?', 'Hatao', true))) return; M.agency = null; try { await save(M, keys, 'Hata diya'); C.render(); } catch (e) {} },
        muadd: async function () { if (await mktUserForm(null, M.agency ? { name: M.agency.manager, mobile: M.agency.mobile, email: M.agency.email, agency: M.agency.agency } : null)) C.render(); },
        muedit: async function (id) { var u = (box._us || []).find(function (x) { return String(x.id) === id; }); if (u && await mktUserForm(u)) C.render(); },
        accsave: async function () {
          var ch = {}; $$('[data-acc]', box).forEach(function (c) { var a = c.getAttribute('data-acc').split('|'); (ch[a[0]] = ch[a[0]] || {})[a[1]] = c.checked; });
          C.busy(true);
          try { for (var id in ch) { var u = (box._us || []).find(function (x) { return String(x.id) === id; }); if (!u) continue; var p = Object.assign({}, u.perms || {}, ch[id]); if (u.role === 'marketing') await C.call('crm_mkt_user', { user: { id: u.id, perms: p } }); else await C.call('crm_user_save', { user: { id: u.id, perms: p } }); } C.toast('Access save ho gaya ✔'); C.cache.users = null; } catch (e) { C.toast(e.message, true); } finally { C.busy(false); }
          C.render();
        }
      });
    }
  });
})();
