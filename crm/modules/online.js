/* Round 44b — Online list: CRM ke jo products / templates online (Web Shop + Store App) par gaye hain, ek jagah.
   Pool = Web qty + App qty. Left = allocation - open orders - bika hua. "+ Qty" free inventory se hi jodta hai. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var STL = { published: ['Live', ''], pending: ['Review me', 'o'], rejected: ['Lauta diya', 'r'], none: ['Bheja nahi', 'g'] };

  function stateOf(x) { var o = x.online; if (!o) return { none: true }; return o; }
  function isOut(x) { var o = x.online; return !!o && num(o.left_total) <= 0; }

  /* Round 45: Online list ab Inventory / Stock ka ek tab hai (#/items?tab=online). Purana #/online wahin bhejta hai. */
  C.onlineView = async function (el, params, q) {
      var rp = await C.call('crm_online_list', {}), rows = rp.rows || [], f = q.f || '', canEdit = C.can('items.to_store');
      var cnt = { all: rows.length, live: 0, rev: 0, out: 0, rej: 0 };
      rows.forEach(function (x) { if (x.status === 'published') cnt.live++; if (x.status === 'pending') cnt.rev++; if (x.status === 'rejected') cnt.rej++; if (isOut(x)) cnt.out++; });
      var list = rows.filter(function (x) { return !f || (f === 'live' && x.status === 'published') || (f === 'rev' && x.status === 'pending') || (f === 'rej' && x.status === 'rejected') || (f === 'out' && isOut(x)); });
      var chips = [['', 'Sab (' + cnt.all + ')'], ['live', 'Live (' + cnt.live + ')'], ['rev', 'Review me (' + cnt.rev + ')'], ['out', 'Out of stock (' + cnt.out + ')'], ['rej', 'Lauta diye (' + cnt.rej + ')']];
      var h = '<div class="ph"><div><h1>Inventory / Stock</h1></div></div><div class="tabs"><button data-goto="#/items">Products</button><button data-goto="#/items?type=project">Templates</button>' + (C.can('stock.view') ? '<button data-goto="#/items?tab=stock">Stock dashboard</button>' : '') + '<button class="on">Online</button></div>' +
        '<div class="ph" style="margin-top:10px"><div><h1>Online list</h1><p>Web Shop aur Store App par gaye sab products aur templates — kitna alag rakha, kitna bika, kitna bacha.</p></div></div>' +
        '<div class="note" style="margin-bottom:12px"><b>Kaise kaam karta hai:</b> har item ka ek online pool hota hai (Web + App ki qty). Dono jagah se order isi pool se katta hai, isliye ek hi maal do jagah nahi bik sakta. Pool Inventory ke free stock se hi banta hai. Photo / video / link Online Admin me hi daalte hain — qty badhane par kuch dobara nahi bharna.</div>' +
        '<div class="row wrap" style="margin-bottom:12px;gap:6px">' + chips.map(function (c) { return '<a class="btn btn-sm ' + (c[0] === f ? 'btn-p' : 'btn-o') + '" href="#/items?tab=online' + (c[0] ? '&f=' + c[0] : '') + '">' + esc(c[1]) + '</a>'; }).join('') + '</div>';
      h += list.length ? '<div class="list" id="onl">' + list.map(function (x) {
        var o = stateOf(x), st = STL[x.status] || [x.status, 'g'], out = isOut(x), proj = x.type === 'project';
        var qline = o.none ? '<span style="color:var(--red);font-weight:700">⚠ Online qty set nahi hai</span>' :
          '<span>Web: <b>' + o.left_web + '</b> bacha / ' + o.web + '</span><span>App: <b>' + o.left_app + '</b> bacha / ' + o.app + '</span><span>Bika: ' + o.sold + '</span>' + (num(o.open_web) + num(o.open_app) ? '<span>Order me: ' + (num(o.open_web) + num(o.open_app)) + '</span>' : '');
        return '<div class="li" data-id="' + x.id + '" style="flex-wrap:wrap;align-items:flex-start"><span class="av ' + (proj ? 'v' : '') + '">' + C.ic(proj ? 'plant' : 'box') + '</span>' +
          '<span class="grow" style="min-width:200px"><span class="t">' + esc(x.name) + (proj ? C.pill(x.kw ? x.kw + ' kW Project' : 'Project', 'g') : '') + C.pill(st[0], st[1]) + (out ? C.pill('Out of stock', 'r') : '') + (x.inactive ? C.pill('Band', 'g') : '') + '</span>' +
          '<span class="m">' + (x.sku ? '<span style="font-weight:700">' + esc(x.sku) + '</span>' : '') + '<span>' + money(x.price) + ' + GST ' + esc(x.gst) + '%</span>' + (x.free != null ? '<span>Inventory me free: <b>' + esc(x.free) + '</b>' + (proj ? ' set' : '') + '</span>' : '') + (x.cost_missing ? '<span style="color:var(--red)">⚠ Kharid rate nahi</span>' : '') + '</span>' +
          '<span class="m">' + qline + '</span></span>' +
          (canEdit ? '<span class="acts" style="flex-wrap:wrap;gap:6px">' +
            '<button class="btn ' + (out ? 'btn-p' : 'btn-o') + ' btn-sm" data-act="add" data-id="' + x.id + '">' + C.ic('plus') + ' ' + (o.none ? 'Qty set karein' : 'Add more quantity') + '</button>' +
            (!o.none ? '<button class="btn btn-o btn-sm" data-act="move" data-id="' + x.id + '">Web ⇄ App</button><button class="btn btn-g btn-sm" data-act="off" data-id="' + x.id + '">Online se hatayein</button>' : '') + '</span>' : '') + '</div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('store', 'Abhi koi item online nahi gaya', 'Inventory ya Template list se "Store ko bhejein" dabayein — qty yahin dikhegi.') + '</div>';
      el.innerHTML = h;
      var byId = {}; rows.forEach(function (x) { byId[x.id] = x; });

      function qtyModal(x, mode) {
        var o = x.online, first = !o;
        var free = x.free == null ? '—' : x.free, unit = x.type === 'project' ? 'set' : 'piece';
        var body = '<p class="hint" style="margin-bottom:10px">Inventory me abhi free: <b>' + esc(free) + ' ' + unit + '</b>. ' + (first ? 'Kitna Web Shop ko aur kitna Store App ko dena hai?' : 'Jitna aur jodna hai utna likhein — pehle wala maal, photo, review sab waise hi rahega.') + '</p>' +
          '<div class="fg">' + C.f('Web Shop (' + unit + ')', '<input class="inp" id="qw" inputmode="numeric" value="' + (first ? '' : '0') + '">') + C.f('Store App (' + unit + ')', '<input class="inp" id="qa" inputmode="numeric" value="' + (first ? '' : '0') + '">') + '</div>' +
          '<p class="err" id="qe" style="margin-top:8px" hidden></p>';
        var m = C.modal({ title: (first ? 'Online qty — ' : 'Add more quantity — ') + x.name, size: 'sm', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + (first ? 'Set karein' : 'Jodein') + '</button>' });
        $('[data-ok]', m.el).onclick = async function () {
          var w = num($('#qw', m.el).value), a = num($('#qa', m.el).value), er = $('#qe', m.el);
          if (w < 0 || a < 0 || (w + a) <= 0) { er.hidden = false; er.textContent = 'Web ya App ke liye qty likhein'; return; }
          try { await C.run('crm_online_set', { id: x.id, op: first ? 'set' : 'add', web: w, app: a }, 'Online qty ho gayi ✔ — dobara review nahi chahiye'); m.el.remove(); document.documentElement.style.overflow = ''; C.render(); }
          catch (e) { er.hidden = false; er.innerHTML = esc(e.message) + (/free stock|Inventory/.test(e.message) ? ' <a href="#/items" data-close>Inventory me stock badhayein →</a>' : ''); }
        };
      }
      function moveModal(x) {
        var o = x.online;
        var body = '<p class="hint" style="margin-bottom:10px">Abhi bacha: Web <b>' + o.left_web + '</b>, App <b>' + o.left_app + '</b>. Sirf bacha hua hissa ek se doosre me ja sakta hai; total pool nahi badlega.</p>' +
          '<div class="fg">' + C.f('Kahan se', '<select class="inp" id="mf"><option value="web">Web Shop se</option><option value="app">Store App se</option></select>') + C.f('Kitna', '<input class="inp" id="mq" inputmode="numeric">') + '</div><p class="err" id="me" hidden></p>';
        var m = C.modal({ title: 'Web ⇄ App — ' + x.name, size: 'sm', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Badlein</button>' });
        $('[data-ok]', m.el).onclick = async function () {
          var er = $('#me', m.el);
          try { await C.run('crm_online_set', { id: x.id, op: 'move', from: $('#mf', m.el).value, qty: num($('#mq', m.el).value) }, 'Hissa badal gaya ✔'); m.el.remove(); document.documentElement.style.overflow = ''; C.render(); }
          catch (e) { er.hidden = false; er.textContent = e.message; }
        };
      }
      C.bind(el, {
        add: function (id) { qtyModal(byId[id]); },
        move: function (id) { moveModal(byId[id]); },
        off: async function (id) { var x = byId[id]; if (await C.confirm('"' + x.name + '" ko Online pool se hatayein? Alag rakha hua maal Inventory me wapas free ho jayega. (Store par jo page live hai wo Admin se alag hatana padega.)', 'Haan, hatayein', true)) { try { await C.run('crm_online_set', { id: id, op: 'off' }, 'Online pool se hat gaya'); C.render(); } catch (e) {} } }
      });
    };
  C.mod('online', { title: 'Online list', allowed: function () { return C.canAny('items.to_store', 'items.view'); }, render: function () { C.go('#/items?tab=online'); } });
})();
