/* Activity record — who did what, when (Admin) */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, esc = C.esc;
  var ACT = { login: ['Login', 'g'], create: ['Naya', ''], edit: ['Badla', 'b'], delete: ['Hataya', 'r'], status: ['Status', 'v'], convert: ['Bill bana', 'v'], assign: ['Diya', 'o'], import: ['Import', 'o'], export: ['Download', 'o'], upload: ['Upload', ''], open: ['Khola', 'g'], to_store: ['Store ko bheja', 'o'], commission: ['Commission', 'o'], settings: ['Settings', 'b'], register: ['Nayi ID', 'o'], password: ['Password', 'g'], user_create: ['User', ''], user_edit: ['User', 'b'], user_delete: ['User hataya', 'r'], role_edit: ['Permission', 'v'] };
  C.mod('activity', {
    title: 'Activity Record',
    allowed: function () { return C.can('activity.view'); },
    render: async function (el, params, q) {
      var from = q.from || C.addDays(C.today(), -7), to = q.to || '', uid = q.user || '', qq = q.q || '';
      var list = await C.call('crm_activity_list', { from: from, to: to || null, user_id: uid === '' ? null : uid, q: qq, limit: 2000 });
      var h = '<div class="ph"><div><h1>Activity Record</h1><p>Kisne kya kiya, kab kiya — hatane ki wajah ke saath. Ye record koi mita nahi sakta.</p></div><div class="row">' + C.reportBtns('Activity', function () { return { head: ['Samay', 'User', 'Role', 'Kaam', 'Detail'], rows: list.map(function (a) { return [C.fdt(a.at), a.user_name || '', C.ROLE[a.role] || a.role || '', (ACT[a.action] || [a.action])[0], a.summary || '']; }) }; }) + '</div></div>';
      h += '<div class="bar"><input class="inp" type="search" data-q value="' + esc(qq) + '" placeholder="Khojein (naam, kaam)"><span class="xs mute">Se</span><input class="inp" type="date" data-from value="' + esc(from) + '" style="width:auto"><span class="xs mute">Tak</span><input class="inp" type="date" data-to value="' + esc(to) + '" style="width:auto">' + C.userFilter(uid) + '<span class="sp"></span><span class="pill">' + list.length + '</span></div>';
      h += list.length ? '<div class="list">' + list.map(function (a) { var x = ACT[a.action] || [a.action, 'g']; return '<div class="li"><span class="av ' + (a.action === 'delete' ? 'r' : '') + '">' + esc(C.initials(a.user_name)) + '</span><span class="grow"><span class="t">' + esc(a.user_name || '—') + ' ' + C.pill(x[0], x[1]) + '</span><span class="m"><span>' + esc(a.summary || '') + '</span></span></span><span class="xs mute nowrap">' + esc(C.fdt(a.at)) + '</span></div>'; }).join('') + '</div>' : '<div class="card">' + C.empty('activity', 'Is samay me kuch nahi') + '</div>';
      el.innerHTML = h;
      function nav(p) { C.go('#/activity' + C.qs(Object.assign({ from: from, to: to, user: uid, q: qq }, p))); }
      $('[data-from]', el).onchange = function () { nav({ from: this.value }); }; $('[data-to]', el).onchange = function () { nav({ to: this.value }); };
      $('[data-q]', el).addEventListener('change', function () { nav({ q: this.value.trim() }); });
      var us = $('[data-user]', el); if (us) us.onchange = function () { nav({ user: this.value }); };
    }
  });
})();
