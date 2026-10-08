/* Team — users, ID approval, role permission templates (tick / untick), per-user overrides, performance */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var ROLES = ['manager', 'staff', 'dealer', 'influencer'];
  var STS = { active: ['Chalu', ''], pending: ['Verify baaki', 'o'], blocked: ['Band', 'r'] };
  function groups(cat) { var g = {}; cat.forEach(function (p) { (g[p.g] = g[p.g] || []).push(p); }); return g; }

  async function userForm(u, roleDefs) {
    var isNew = !u; u = u || { role: 'staff', status: 'active', perms: {}, meta: {} };
    var meta = Object.assign({ commission: {} }, u.meta || {}), cat = C.me.catalog || [], g = groups(cat), admin = C.isAdmin();
    var roleOpts = (admin ? ['admin'] : []).concat(ROLES).map(function (r) { return [r, C.ROLE[r]]; });
    function permHtml(role) {
      var def = (roleDefs || {})[role] || {};
      return Object.keys(g).map(function (k) { return '<div class="perm-g"><h5>' + esc(k) + '</h5>' + g[k].map(function (p) { var v = u.perms && u.perms[p.k] != null ? (u.perms[p.k] ? 'allow' : 'deny') : ''; return '<div class="tri"><span class="grow">' + esc(p.l) + '</span><select class="inp" data-pk="' + p.k + '"><option value="">Role jaisa (' + (def[p.k] ? '✔' : '✖') + ')</option><option value="allow"' + (v === 'allow' ? ' selected' : '') + '>✔ Haan</option><option value="deny"' + (v === 'deny' ? ' selected' : '') + '>✖ Nahi</option></select></div>'; }).join('') + '</div>'; }).join('');
    }
    var body = '<form id="uf" class="stack"><div class="fg">' + C.f('Naam *', C.inp('name', u.name)) + C.f('Username *' + (isNew ? '' : ' <span class="o">(badal nahi sakte)</span>'), C.inp('username', u.username, isNew ? 'autocomplete="off"' : 'readonly')) +
      C.f('Mobile', C.inp('mobile', u.mobile, 'inputmode="tel"')) + C.f('Email * <span class="o">(login OTP isi par)</span>', C.inp('email', u.email, 'type="email"')) +
      C.f('Role', C.sel('role', roleOpts, u.role)) + C.f('Status', C.sel('status', Object.keys(STS).map(function (s) { return [s, STS[s][0]]; }), u.status)) +
      (!isNew ? C.f('Login', '<button type="button" class="btn btn-o" data-lreset>' + C.ic('refresh') + ' Login reset (PIN + phone hatayein)</button>') : C.f('Login', '<p class="hint" style="margin:6px 0 0">User pehli baar Email OTP se login karke apna 4 ank ka PIN banayega.</p>')) + (u.ref_code ? C.f('Referral code', '<input class="inp" value="' + esc(u.ref_code) + '" readonly>') : '') + '</div>' +
      '<div class="sec-t">Commission, limit aur target</div><div class="fg g3">' + C.f('Commission kaise', C.sel('c_mode', [['', 'Koi nahi'], ['per_kw', '₹ per kW'], ['fixed', '₹ fixed per plant'], ['percent', '% deal value']], meta.commission.mode || '')) + C.f('Commission value', C.inp('c_value', meta.commission.value, 'inputmode="decimal"')) + C.f('Max discount % (quotation)', C.inp('max_discount_pct', meta.max_discount_pct, 'inputmode="decimal"')) + C.f('Mahine ka target (₹)', C.inp('target_monthly', meta.target_monthly, 'inputmode="decimal"')) + '</div>' +
      '<details style="margin-top:6px"><summary class="b" style="cursor:pointer;color:var(--leaf-d)">' + C.ic('key') + ' Is user ki alag permission (tick / untick)</summary><p class="hint" style="margin:8px 0">"Role jaisa" = role ki default setting. Sirf is user ke liye badalna ho to Haan / Nahi chunein.</p><div class="perm-grid" id="pg">' + permHtml(u.role) + '</div></details></form>';
    return new Promise(function (res) {
      var m = C.modal({ title: isNew ? 'Naya user' : u.name, size: 'wide', body: body, foot: (!isNew ? '<button class="btn btn-r" data-del style="margin-right:auto">' + C.ic('trash') + ' Hatayein</button>' : '') + '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      var f = $('#uf', m.el);
      f.role.onchange = function () { $$('[data-pk]', m.el).forEach(function (s) { if (s.value) u.perms[s.getAttribute('data-pk')] = s.value === 'allow'; else delete u.perms[s.getAttribute('data-pk')]; }); $('#pg', m.el).innerHTML = permHtml(f.role.value); };
      var lr = $('[data-lreset]', m.el); if (lr) lr.onclick = async function () { if (!(await C.confirm(u.name + ' ka PIN aur saare phone hata dein? Agli baar Email OTP se naya PIN banayega.', 'Reset karein', true))) return; try { await C.run('crm_auth_user_reset', { id: u.id }, 'Login reset ho gaya ✔'); } catch (e) {} };
      var del = $('[data-del]', m.el); if (del) del.onclick = async function () {
        var others = (C.cache.users || []).filter(function (x) { return x.id !== u.id && x.status === 'active' && x.role !== 'consumer'; });
        var mm = C.modal({ title: u.name + ' ko hatayein', size: 'sm', body: '<p style="margin-bottom:10px">Iske customers, leads, quotation kisko dein?</p><select class="inp" id="tto"><option value="">Company / Admin</option>' + others.map(function (x) { return '<option value="' + x.id + '">' + esc(x.name) + ' — ' + esc(C.ROLE[x.role]) + '</option>'; }).join('') + '</select><p class="hint" style="margin-top:8px">Login band ho jayega. Commission record user ke naam par hi rahega.</p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-r" data-ok>Hatayein</button>' });
        $('[data-ok]', mm.el).onclick = async function () { try { await C.run('crm_user_delete', { id: u.id, transfer_to: $('#tto', mm.el).value || null }, 'User hata diya'); mm.close(); m.el.remove(); document.documentElement.style.overflow = ''; res({ deleted: true }); } catch (e) {} };
      };
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (!C.need(f, ['name', 'email'].concat(isNew ? ['username'] : []))) return;
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(o.email)) { f.email.classList.add('bad'); return C.toast('Sahi email likhein — login OTP isi par jayega', true); }
        if (o.mobile && !C.validMob(o.mobile)) return C.toast('Mobile sahi likhein', true);
        var perms = Object.assign({}, u.perms || {}); $$('[data-pk]', m.el).forEach(function (s) { var k = s.getAttribute('data-pk'); if (s.value) perms[k] = s.value === 'allow'; else delete perms[k]; });
        var mt = Object.assign({}, u.meta || {}, { commission: { mode: o.c_mode, value: num(o.c_value) }, max_discount_pct: num(o.max_discount_pct), target_monthly: num(o.target_monthly) });
        var user = { id: u.id || null, name: o.name, mobile: o.mobile, email: o.email, role: o.role, status: o.status, perms: perms, meta: mt };
        if (isNew) user.username = o.username.toLowerCase();
        try { var r = await C.run('crm_user_save', { user: user }, 'User save ho gaya ✔'); m.el.remove(); document.documentElement.style.overflow = ''; res(r); if (isNew && o.mobile && await C.confirm('Login detail WhatsApp par bhejein?', 'Haan')) window.open(C.wa(o.mobile, 'Namaste ' + o.name + ' ji, aapki ' + (C.company().name || '') + ' CRM ID taiyaar hai.\nLink: ' + location.href.split('#')[0] + '\nLogin: ' + o.mobile + ' (ya ' + o.email + ')\nPehli baar email par OTP aayega, phir apna 4 ank ka PIN banayein.'), '_blank'); } catch (e) {}
      };
    });
  }

  C.mod('team', {
    title: 'Team & Permission',
    allowed: function () { return C.canAny('users.manage', 'team.stats'); },
    render: async function (el, params, q) {
      var mgU = C.can('users.manage'), tab = q.tab || (mgU ? 'users' : 'perf'), users = mgU ? await C.users(true) : (C.cache.users || []), roleDefs = null;
      if (mgU) { try { roleDefs = (await C.call('crm_roles_get', {})).roles; } catch (e) { roleDefs = {}; } }
      var pend = users.filter(function (u) { return u.status === 'pending'; });
      var tabs = (mgU ? [['users', 'Users (' + users.filter(function (u) { return u.role !== 'consumer'; }).length + ')'], ['pending', 'Verify baaki (' + pend.length + ')']] : []).concat(C.isAdmin() ? [['roles', 'Role permission']] : []).concat(C.can('team.stats') ? [['perf', 'Kaam ka hisab']] : []);
      var h = '<div class="ph"><div><h1>Team &amp; Permission</h1><p>Kaun kya dekhe aur kya kare — sab aapke haath me (tick / untick).</p></div><div class="row">' + (mgU ? '<button class="btn btn-p" data-act="add">' + C.ic('plus') + ' Naya user</button>' : '') + '</div></div>';
      h += '<div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + t[1] + '</button>'; }).join('') + '</div><div id="tb"></div>';
      el.innerHTML = h;
      var tb = $('#tb', el);
      function urow(u) { var s = STS[u.status] || [u.status, 'g'], c = (u.meta || {}).commission || {}; return '<div class="li click" data-act="edit" data-id="' + u.id + '"><span class="av ' + (u.role === 'dealer' ? 'o' : u.role === 'influencer' ? 'v' : u.role === 'manager' ? 'b' : '') + '">' + esc(C.initials(u.name)) + '</span><span class="grow"><span class="t">' + esc(u.name) + ' ' + C.pill(C.ROLE[u.role] || u.role, 'g') + (u.status !== 'active' ? C.pill(s[0], s[1]) : '') + (Object.keys(u.perms || {}).length ? C.pill('Alag permission', 'v') : '') + '</span><span class="m"><span>@' + esc(u.username) + '</span>' + (u.mobile ? '<span>' + esc(u.mobile) + '</span>' : '') + (u.ref_code ? '<span>' + esc(u.ref_code) + '</span>' : '') + (c.mode ? '<span>' + (c.mode === 'per_kw' ? money(c.value) + '/kW' : c.mode === 'fixed' ? money(c.value) + '/plant' : c.value + '%') + '</span>' : '') + '<span>' + (u.last_seen ? 'Aakhri baar ' + esc(C.ago(u.last_seen)) : 'Kabhi login nahi') + '</span></span></span>' + (u.status === 'pending' ? '<span class="acts"><button class="btn btn-p btn-sm" data-act="approve" data-id="' + u.id + '">' + C.ic('check') + ' Chalu karein</button><button class="btn btn-r btn-sm" data-act="block" data-id="' + u.id + '">Mana</button></span>' : '') + '</div>'; }
      async function draw() {
        if (tab === 'users') { var rf = q.role || '', us = users.filter(function (u) { return u.role !== 'consumer' && (!rf || u.role === rf); }); tb.innerHTML = '<div class="bar">' + C.chips([['', 'Sab']].concat(ROLES.map(function (r) { return [r, C.ROLE[r]]; })), rf, 'rf') + '<input class="inp" type="search" data-q placeholder="Khojein"></div>' + (us.length ? '<div class="list" id="ul">' + us.map(urow).join('') + '</div>' : '<div class="card">' + C.empty('users', 'Abhi koi user nahi', 'Manager, Staff, Dealer, Influencer ki ID yahan banayein') + '</div>'); var ul = $('#ul', tb); if (ul) C.filterList($('[data-q]', tb), ul); }
        else if (tab === 'pending') tb.innerHTML = pend.length ? '<div class="note" style="margin-bottom:12px">Dealer / Influencer ne khud ID banayi hai — check karke chalu karein. Commission rate bhi set kar dein.</div><div class="list">' + pend.map(urow).join('') + '</div>' : '<div class="card">' + C.empty('check', 'Koi ID verify ke liye baaki nahi') + '</div>';
        else if (tab === 'roles') {
          var role = q.r || 'manager', cat = C.me.catalog || [], g = groups(cat), def = (roleDefs || {})[role] || {};
          tb.innerHTML = '<div class="bar">' + C.chips(ROLES.map(function (r) { return [r, C.ROLE[r]]; }), role, 'r') + '<span class="sp"></span><button class="btn btn-o btn-sm" data-act="all">Sab tick</button><button class="btn btn-o btn-sm" data-act="none">Sab untick</button><button class="btn btn-p" data-act="rsave">' + C.ic('check') + ' Save</button></div><div class="note g" style="margin-bottom:12px">Ye <b>' + C.ROLE[role] + '</b> role ki default permission hai — is role ke sabhi users par lagegi. Kisi ek user ke liye alag chahiye to Users → user kholein → "alag permission".</div><div class="perm-grid">' +
            Object.keys(g).map(function (k) { return '<div class="perm-g"><h5>' + esc(k) + '</h5>' + g[k].map(function (p) { return '<label class="ck" style="padding:4px 0"><input type="checkbox" data-rk="' + p.k + '"' + (def[p.k] ? ' checked' : '') + '> ' + esc(p.l) + '</label>'; }).join('') + '</div>'; }).join('') + '</div>';
        } else if (tab === 'perf') {
          var from = q.from || C.addDays(C.today(), -30), st = await C.call('crm_team_stats', { from: from });
          tb.innerHTML = '<div class="bar"><span class="sm b">Kab se:</span><input class="inp" type="date" data-from value="' + esc(from) + '" style="width:auto"><span class="sp"></span>' + C.reportBtns('Team performance', function () { return { head: ['Naam', 'Role', 'Aakhri login', 'Khule kaam', 'Overdue', 'Poore', 'Late poore', 'Leads', 'Jeeti', 'Quotation', 'Sale', 'Plants'], rows: st.map(function (s) { return [s.name, C.ROLE[s.role] || s.role, s.last_seen ? C.fdt(s.last_seen) : '', s.open, s.overdue, s.done, s.late, s.leads, s.won, s.quotes, num(s.sales), s.plants]; }) }; }) + '</div>' +
            '<div class="note" style="margin-bottom:12px">' + C.ic('alert') + ' Laal = time par kaam nahi kar rahe (overdue zyada ya late poore). Ek click me WhatsApp par yaad dilayein.</div>' +
            '<div class="tw"><table class="t"><thead><tr><th>Naam</th><th>Aakhri login</th><th class="r">Khule</th><th class="r">Overdue</th><th class="r">Poore</th><th class="r">Late</th><th class="r">Leads / Jeeti</th><th class="r">Quotation</th><th class="r">Sale</th><th class="r">Plants</th><th></th></tr></thead><tbody>' +
            st.map(function (s) { var bad = s.overdue >= 3 || (s.done && s.late * 2 > s.done), u = users.find(function (x) { return x.id === s.id; }); return '<tr' + (bad ? ' style="background:#fff8f7"' : '') + '><td><b>' + esc(s.name) + '</b>' + (bad ? ' ' + C.pill('Dhyan dein', 'r') : '') + '<div class="xs mute">' + esc(C.ROLE[s.role] || s.role) + '</div></td><td class="xs">' + (s.last_seen ? esc(C.ago(s.last_seen)) : '—') + '</td><td class="r">' + s.open + '</td><td class="r' + (s.overdue ? ' bad' : '') + '">' + s.overdue + '</td><td class="r">' + s.done + '</td><td class="r' + (s.late ? ' bad' : '') + '">' + s.late + '</td><td class="r">' + s.leads + ' / ' + s.won + '</td><td class="r">' + s.quotes + '</td><td class="r">' + money(s.sales) + '</td><td class="r">' + s.plants + '</td><td><a class="btn btn-g btn-sm" href="#/today?user=' + s.id + '">Kaam</a>' + (u && u.mobile && s.overdue ? '<a class="btn btn-wa btn-icon btn-sm" target="_blank" rel="noopener" href="' + C.wa(u.mobile, 'Namaste ' + s.name + ' ji, CRM me aapke ' + s.overdue + ' kaam overdue hain — aaj poore kar dein. Dhanyavaad') + '">' + C.ic('wa') + '</a>' : '') + '</td></tr>'; }).join('') + '</tbody></table></div>';
          $('[data-from]', tb).onchange = function () { C.go('#/team' + C.qs({ tab: 'perf', from: this.value })); };
        }
      }
      await draw();
      el.addEventListener('click', function (e) {
        var t = e.target.closest('[data-tab]'); if (t) { C.go('#/team?tab=' + t.getAttribute('data-tab')); return; }
        var r = e.target.closest('[data-r]'); if (r) { C.go('#/team?tab=roles&r=' + r.getAttribute('data-r')); return; }
        var rf = e.target.closest('[data-rf]'); if (rf) C.go('#/team' + C.qs({ tab: 'users', role: rf.getAttribute('data-rf') }));
      });
      function U(id) { return users.find(function (u) { return String(u.id) === String(id); }); }
      C.bind(el, {
        add: function () { userForm(null, roleDefs).then(function (r) { if (r) { C.users(true); C.render(); } }); },
        edit: function (id, a, e) { if (e.target.closest('button')) return; userForm(C.clone(U(id)), roleDefs).then(function (r) { if (r) { C.users(true); C.render(); } }); },
        approve: async function (id) { var u = C.clone(U(id)); u.status = 'active'; var x = await userForm(u, roleDefs); if (x) { C.users(true); C.render(); var nu = U(id); if (nu && nu.mobile && await C.confirm('User ko WhatsApp par batayein ki ID chalu ho gayi?', 'Haan')) window.open(C.wa(nu.mobile, 'Namaste ' + nu.name + ' ji, aapki ' + (C.company().name || '') + ' ' + C.ROLE[nu.role] + ' ID chalu ho gayi hai. Login: ' + location.href.split('#')[0] + ' (Username: ' + nu.username + ')'), '_blank'); } },
        block: async function (id) { if (!(await C.confirm('Ye ID mana (band) karein?', 'Band karein', true))) return; try { await C.run('crm_user_save', { user: { id: +id, status: 'blocked' } }, 'Band kar diya'); C.render(); } catch (e) {} },
        all: function () { $$('[data-rk]', el).forEach(function (c) { c.checked = true; }); }, none: function () { $$('[data-rk]', el).forEach(function (c) { c.checked = false; }); },
        rsave: async function () { var role = q.r || 'manager', perms = {}; $$('[data-rk]', el).forEach(function (c) { if (c.checked) perms[c.getAttribute('data-rk')] = true; }); try { await C.run('crm_role_save', { role: role, perms: perms }, C.ROLE[role] + ' ki permission save ✔'); C.render(); } catch (e) {} }
      });
    }
  });
})();
