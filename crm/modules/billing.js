/* Quotation → Bill (GST invoice) → Payments; Purchase orders; sales reports for the accountant */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var QST = { draft: ['Draft', 'g'], sent: ['Bhej di', 'b'], accepted: ['Maan li', ''], rejected: ['Mana kiya', 'r'], expired: ['Expire', 'o'], converted: ['Bill bana', 'v'] };
  var IST = { due: ['Baaki', 'r'], partial: ['Aadha mila', 'o'], paid: ['Poora mila', ''] };
  var PST = { open: ['Open', 'o'], received: ['Maal aa gaya', ''], cancelled: ['Cancel', 'g'] };
  var MODES = ['Cash', 'UPI', 'Bank Transfer', 'Cheque', 'Card', 'Finance / Loan', 'Other'];
  C.billPill = function (x) { var m = x.kind === 'invoice' ? IST : x.kind === 'purchase' ? PST : QST, s = m[x.status] || [x.status, 'g']; return C.pill(s[0], s[1]); };
  var T = { quote: 'Quotation', invoice: 'Bill', purchase: 'Purchase order' };
  function snap(p) { var d = p.data || {}; return { name: p.title, mobile: p.mobile || '', email: d.email || '', address: d.address || '', city: d.city || '', district: d.district || '', state: d.state || '', country: d.country || '', pincode: d.pincode || '', gstin: d.gstin || '' }; }
  function calc(lines, disc) { var sub = 0, g = 0; lines.forEach(function (l) { var a = num(l.qty) * num(l.price); sub += a; g += a * num(l.gst) / 100; }); sub = C.r2(sub); g = C.r2(g); return { subtotal: sub, gst_total: g, discount: C.r2(disc), grand: C.r2(sub + g - num(disc)) }; }
  function lineFromItem(it, type) {
    var d = it.data || {}, l = { kind: d.type === 'project' ? 'project' : 'product', item_id: it.id, title: d.title || '', name: d.name || it.title, desc: d.desc || '', more: d.more || '', hsn: d.hsn || '', unit: d.unit || '', qty: 1, price: num(type === 'purchase' && num(d.cost_price) ? d.cost_price : d.price), gst: num(d.gst), min: num(d.min_price) };
    if (l.kind === 'project') { l.proj_items = C.clone(d.proj_items || []); l.show_prices = !!d.show_prices; }
    return l;
  }

  /* quotation ki lines → Products & Templates me naya "Template" (dobara use ke liye) */
  async function saveAsProject(x) {
    if (!x.lines.length) return C.toast('Pehle items jodein', true);
    var t = calc(x.lines, 0), pi = [];
    x.lines.forEach(function (l) {
      if ((l.kind || 'product') === 'project' && (l.proj_items || []).length) l.proj_items.forEach(function (p) { pi.push({ item_id: p.item_id || null, title: p.title || '', name: p.name, desc: p.desc || '', qty: C.r2(num(p.qty) * (num(l.qty) || 1)), price: p.price || '' }); });
      else pi.push({ item_id: l.item_id || null, title: l.title || '', name: l.name, desc: l.desc || '', qty: num(l.qty), price: C.r2(l.price) });
    });
    var g = x.lines.length === 1 ? num(x.lines[0].gst) : (function () { var c = {}; x.lines.forEach(function (l) { var k = num(l.gst); c[k] = (c[k] || 0) + num(l.qty) * num(l.price); }); return +Object.keys(c).sort(function (a, b) { return c[b] - c[a]; })[0]; })();
    var projs = []; try { projs = (await C.list('item', { limit: 3000 })).filter(function (i) { return (i.data.type || 'product') === 'project' && i.status !== 'inactive'; }); } catch (e) {}
    var targetSel = projs.length ? C.f('Kahan save karein?', C.sel('target', [['', 'Naya project banayein']].concat(projs.map(function (i) { return [String(i.id), 'Update: ' + i.title]; })), ''), 'full') : '';
    var m = C.modal({ title: 'Add in Template list', body: '<p class="mute sm" style="margin-bottom:10px">Ye quotation ki saari lines ek <b>Template</b> ban jayengi — agli baar "Product / Template jodein" se ek click me.</p><form id="tpf" class="fg">' + targetSel +
      C.f('Template ka naam *', C.inp('name', x.lines.length === 1 ? x.lines[0].name : '', 'maxlength="160" placeholder="Jaise: 3 kW On-grid Residential"'), 'full') + C.f('Category', C.inp('category', 'Residential', 'list="pcats"')) +
      C.f('Kul keemat (₹, bina GST) *', C.inp('price', C.r2(t.subtotal), 'inputmode="decimal"')) + C.f('GST %', C.sel('gst', [['0', '0%'], ['5', '5%'], ['12', '12%'], ['18', '18%'], ['28', '28%']], String(g || 12))) +
      '<div class="f full"><label class="ck"><input type="checkbox" name="show_prices"> Quotation me andar wale items ka rate bhi dikhayein</label></div><div class="full xs mute">' + pi.length + ' cheezein shamil hongi: ' + esc(pi.map(function (p) { return p.name + ' × ' + p.qty; }).join(', ')) + '</div></form><datalist id="pcats"><option value="Residential"><option value="Commercial"><option value="Industrial"><option value="VFD / Pump"></datalist>',
      foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save project</button>' });
    $('[data-ok]', m.el).onclick = async function () {
      var f = $('#tpf', m.el), o = C.form(f); if (!C.need(f, ['name', 'price'])) return;
      var ex = o.target ? projs.filter(function (i) { return String(i.id) === String(o.target); })[0] : null;
      try {
        if (ex) { await C.save('item', ex.id, Object.assign({}, ex.data, { type: 'project', name: o.name, category: o.category, price: C.r2(o.price), gst: num(o.gst), proj_items: pi, show_prices: !!o.show_prices }), { status: ex.status || 'active' }, 'Template update ho gaya ✔'); }
        else await C.save('item', null, { type: 'project', name: o.name, title: '', category: o.category, price: C.r2(o.price), gst: num(o.gst), unit: 'Set', proj_items: pi, show_prices: !!o.show_prices, desc: '' }, { status: 'active' }, 'Template list me save ho gaya ✔');
        m.close();
      } catch (e) {}
    };
  }

  /* ================================================================ editor (quotation / bill / purchase) */
  async function editor(el, type, rec, q) {
    var isNew = !rec, d = rec ? C.clone(rec.data || {}) : { date: C.today(), lines: [], discount: 0 }, party = null;
    if (isNew && type === 'quote') { d.valid_till = C.addDays(C.today(), 15); d.send_on = ''; d.qtitle = ''; d.show_item_prices = false; }
    if (q.copy) { try { var src = await C.get(q.copy); d = C.clone(src.data); delete d.invoice_id; delete d.invoice_ref; delete d.pre_expire; delete d.expired_on; delete d.renewals; d.date = C.today(); d.valid_till = C.addDays(C.today(), 15); party = await C.get(src.party_id); } catch (e) {} }
    if (rec && rec.party_id) { try { party = await C.get(rec.party_id); } catch (e) { party = { id: rec.party_id, title: rec.party_name || d.party && d.party.name, data: {} }; } }
    if (!party && q.party) { try { party = await C.get(q.party); } catch (e) {} }
    d.lines = d.lines || [];
    if (isNew && type === 'quote' && q.pre) {
      try {
        var pre = JSON.parse(sessionStorage.getItem('crm_qt_pre') || 'null'); sessionStorage.removeItem('crm_qt_pre');
        if (pre && pre.lines) {
          var allIt = await C.list('item', { limit: 3000 });
          pre.lines.forEach(function (pl) { var it = allIt.find(function (x) { return x.id === pl.item_id; }); if (it) { var ln = lineFromItem(it, 'quote'); ln.qty = pl.qty || 1; d.lines.push(ln); } });
          d.notes = (d.notes ? d.notes + '\n' : '') + 'Store order ' + pre.order_no + ' ke hisab se'; d.order_no = pre.order_no; d.order_id = pre.order_id;
          if (pre.miss && pre.miss.length) setTimeout(function () { C.toast('Inventory me nahi mile (jodein): ' + pre.miss.join(', '), true); }, 600);
        }
      } catch (e) {}
    }
    var co = C.company(), lim = num((C.me.meta || {}).max_discount_pct), canAny = C.can('quotes.discount_any') || C.isAdmin();
    var shipSame = d.ship_same != null ? !!d.ship_same : !String(d.ship || '').trim(), shipInit = {};
    if (d.ship_addr) Object.keys(d.ship_addr).forEach(function (k) { shipInit['ship_' + k] = d.ship_addr[k]; }); else if (d.ship) shipInit.ship_address = d.ship;
    var canProj = type !== 'purchase' && C.can('items.create');
    if (isNew && !d.notes && type === 'quote' && co.terms_quote) d.notes = co.terms_quote;
    el.innerHTML = '<div class="crumb"><a href="#/' + (type === 'quote' ? 'quotes' : 'billing' + (type === 'purchase' ? '?tab=purchase' : '')) + '">' + T[type] + '</a>' + C.ic('right') + '<span>' + (isNew ? 'Nayi' : esc(rec.ref)) + '</span></div>' +
      '<div class="ph"><div><h1>' + (isNew ? (type === 'purchase' ? 'Naya purchase order' : 'Nayi quotation') : T[type] + ' badlein — ' + esc(rec.ref)) + '</h1></div></div>' +
      '<div class="grid" style="grid-template-columns:minmax(0,1fr) 340px;align-items:start" id="edg"><div class="stack">' +
      (type === 'quote' ? '<div class="card qtcard"><div class="f"><label>Quotation ka Title * <span class="o">(list me customer ke saath dikhega)</span></label><input class="inp" data-k="qtitle" maxlength="120" value="' + esc(d.qtitle || '') + '" placeholder="Jaise: 5 kW Rooftop On-grid — Sharma ji"></div><div class="f" style="margin-top:10px"><label>Customer type * <span class="o">(bhejne se pehle zaroori — Subsidy sirf Residential me)</span></label><select class="inp" data-k="ctype"><option value="">— chunein —</option>' + C.CTYPES.map(function (t) { return '<option' + (d.ctype === t ? ' selected' : '') + '>' + t + '</option>'; }).join('') + '</select></div><div class="f" style="margin-top:10px"><label>Plant capacity (kW) * <span class="o">(Plant / project customer ke liye zaroori — Items only me nahi)</span></label><input class="inp" data-k="kw" inputmode="decimal" maxlength="8" value="' + esc(d.kw || '') + '" placeholder="Jaise: 5"></div></div>' : '') + '<div class="card"><div class="hd"><h3>' + (type === 'purchase' ? 'Supplier' : 'Customer') + '</h3><button class="btn btn-o btn-sm" data-act="party" id="pbtn">' + C.ic('users') + ' ' + (party ? 'Badlein' : 'Sab ' + (type === 'purchase' ? 'suppliers' : 'customers')) + '</button></div><div id="pbox"></div></div>' +
      '<div class="card"><div class="hd"><h3>Items</h3><div class="row wrap"><button class="btn btn-p btn-sm" data-act="add">' + C.ic('box') + ' Product / Template jodein</button><button class="btn btn-o btn-sm" data-act="newitem">' + C.ic('plus') + ' Inventory me naya item</button></div></div><div class="doc-lines" id="lines"></div></div>' +
      '<div class="card"><div class="fg">' + C.f('Tareekh', '<input class="inp" type="date" data-k="date" value="' + esc(d.date || C.today()) + '">') +
      (type === 'quote' ? C.f('Kab tak valid', '<input class="inp" type="date" data-k="valid_till" value="' + esc(d.valid_till || '') + '">') + C.f('Bhejne ki yaad (reminder)', '<input class="inp" type="date" data-k="send_on" value="' + esc(d.send_on || '') + '"><span class="hint">Is din "Aaj ke kaam" me aayegi</span>') : '') +
      (type === 'invoice' ? C.f('Payment ki aakhri tareekh', '<input class="inp" type="date" data-k="due_date" value="' + esc(d.due_date || '') + '">') : '') +
      (type === 'purchase' ? C.f('Ship to / Site address <span class="o">(alag ho to)</span>', '<textarea class="inp" rows="2" data-k="ship">' + esc(d.ship || '') + '</textarea>', 'full') :
        '<div class="f full"><label class="ck"><input type="checkbox" id="shipSame"' + (shipSame ? ' checked' : '') + '> Shipping / site address billing address jaisa hi hai</label><div id="shipBox" style="margin-top:10px"' + (shipSame ? ' hidden' : '') + '>' + C.addrFields('ship_', shipInit, { defState: C.company().state || 'Uttar Pradesh' }) + '</div></div>') +
      C.f('Terms &amp; Notes', '<textarea class="inp" rows="4" data-k="notes">' + esc(d.notes || '') + '</textarea>', 'full') + '</div></div></div>' +
      '<div class="card" style="position:sticky;top:80px"><h3 style="margin-bottom:12px">Hisab</h3><div class="totals" id="tot" style="width:100%"></div>' + (type === 'quote' && !canAny ? '<p class="hint" style="margin-top:8px">Aapki discount limit: ' + lim + '%</p>' : '') + (type === 'quote' ? '<label class="ck" style="margin-top:10px"><input type="checkbox" id="sip"' + (d.show_item_prices === false ? '' : ' checked') + '> Quotation me har item ka alag rate dikhayein</label><p class="hint">Band rakhne par customer ko sirf item, qty aur kul total dikhega.</p>' : '') + '<div class="stack" style="margin-top:14px"><button class="btn btn-p btn-block" data-act="save">' + C.ic('check') + ' Save karein</button><button class="btn btn-o btn-block" data-act="prev">' + C.ic('eye') + ' Preview</button>' + (type === 'quote' ? '<button class="btn btn-wa btn-block" data-act="savesend">' + C.ic('wa') + ' Save quotation and send</button>' : '') + (canProj ? '<button class="btn btn-o btn-block" data-act="toproj">' + C.ic('plant') + ' Add in Template list</button>' : '') + '<a class="btn btn-g btn-block" href="' + (isNew ? '#/' + (type === 'quote' ? 'quotes' : 'billing') : '#/' + type + '/' + rec.id) + '">Cancel</a></div></div></div>';
    if (window.innerWidth <= 1000) $('#edg', el).style.gridTemplateColumns = '1fr';
    el.classList.add('has-savebar'); el.insertAdjacentHTML('beforeend', '<div class="savebar"><span class="grow"><span class="xs" style="color:var(--on-dark-mute)">Kul</span><br><b id="sbt">₹0</b></span><button class="btn btn-o btn-sm" data-act="prev" style="background:transparent;color:#fff;border-color:rgba(255,255,255,.3)">' + C.ic('eye') + '</button>' + (canProj ? '<button class="btn btn-o btn-sm" data-act="toproj" title="Template list me save karein" style="background:transparent;color:#fff;border-color:rgba(255,255,255,.3)">' + C.ic('plant') + '</button>' : '') + '<button class="btn btn-s" data-act="save">' + C.ic('check') + ' Save</button></div>');
    function drawParty() {
      var pb = $('#pbtn', el); if (pb) pb.innerHTML = C.ic('users') + ' ' + (party ? 'Badlein' : 'Sab ' + (type === 'purchase' ? 'suppliers' : 'customers'));
      if (!party && type !== 'purchase') { C.partyInline($('#pbox', el), {}, function (p) { party = p; drawParty(); C.toast(p.title + ' chun liya ✔'); }); return; }
      $('#pbox', el).innerHTML = party ? '<div class="li" style="padding:0;border:0"><span class="av">' + esc(C.initials(party.title)) + '</span><span class="grow"><span class="t">' + esc(party.title) + '</span><span class="m"><span>' + esc(party.mobile || '') + '</span>' + ((party.data || {}).city ? '<span>' + esc(party.data.city) + '</span>' : '') + ((party.data || {}).gstin ? '<span>GSTIN ' + esc(party.data.gstin) + '</span>' : '') + '</span></span></div>' : '<p class="mute">Pehle ' + (type === 'purchase' ? 'supplier' : 'customer') + ' chunein</p>';
      var pa = party && party.data ? C.addrText(party.data) : ''; if (pa) $('#pbox', el).insertAdjacentHTML('beforeend', '<div class="xs mute" style="margin-top:6px;white-space:pre-line"><b>Billing:</b> ' + esc(pa) + '</div>');
    }
    function drawTot() { var t = calc(d.lines, d.discount); $('#sbt', el).textContent = money(t.grand); $('#tot', el).innerHTML = '<div><span>Subtotal</span><b>' + money(t.subtotal, 1) + '</b></div><div><span>GST</span><b>' + money(t.gst_total, 1) + '</b></div><div><span>Discount (₹)</span><input class="inp" data-k="discount" inputmode="decimal" value="' + esc(d.discount || '') + '" placeholder="0"></div><div class="gt"><span>Kul</span><span>' + money(t.grand, 1) + '</span></div><div class="xs mute">' + esc(C.words(t.grand)) + '</div>'; }
    function updTot() { var t = calc(d.lines, d.discount), g = $('#tot .gt span:last-child', el); if (!g) return drawTot(); $$('#tot b', el)[0].textContent = money(t.subtotal, 1); $$('#tot b', el)[1].textContent = money(t.gst_total, 1); g.textContent = money(t.grand, 1); $('#sbt', el).textContent = money(t.grand); $('#tot .xs', el).textContent = C.words(t.grand); }
    function lineHtml(l, i) {
      var proj = l.kind === 'project', amt = num(l.qty) * num(l.price) * (1 + num(l.gst) / 100);
      return '<div class="dl' + (proj ? ' proj' : '') + '" data-i="' + i + '"><div class="dh">' + C.pill(proj ? 'Template' : 'Product', proj ? 'v' : '') + '<input class="inp" style="min-height:34px;max-width:200px" data-f="title" value="' + esc(l.title || '') + '" placeholder="Title (optional)"><span class="grow"></span>' + (i > 0 ? '<button class="btn btn-g btn-icon btn-sm" data-up="' + i + '" aria-label="Upar">↑</button>' : '') + '<button class="btn btn-g btn-icon btn-sm" data-rm="' + i + '" aria-label="Hatayein">' + C.ic('trash') + '</button></div>' +
        '<input class="inp" data-f="name" value="' + esc(l.name || '') + '" placeholder="Item ka naam" style="font-weight:700;margin-bottom:8px">' +
        '<div class="nums"><div class="f"><label>Qty</label><div class="qstep"><button type="button" class="btn btn-o btn-icon btn-sm" data-qm aria-label="Kam karein">−</button><input class="inp" data-f="qty" inputmode="decimal" value="' + esc(l.qty) + '"><button type="button" class="btn btn-o btn-icon btn-sm" data-qp aria-label="Badhayein">+</button></div></div><div class="f"><label>Rate (₹, bina GST)</label><input class="inp" data-f="price" inputmode="decimal" value="' + esc(l.price) + '"></div><div class="f"><label>GST %</label><input class="inp" data-f="gst" inputmode="decimal" value="' + esc(l.gst) + '"></div><div class="f"><label>Amount (GST sahit)</label><input class="inp" data-amt readonly value="' + esc(C.r2(amt)) + '" style="background:var(--paper);font-weight:700"></div></div>' +
        '<p class="stk xs mute" style="margin-top:6px" hidden></p><p class="err minw" style="margin-top:6px"' + (l.min && num(l.price) < l.min ? '' : ' hidden') + '>Rate minimum (' + money(l.min || 0) + ') se kam hai</p>' +
        (proj ? '<div class="sec-t" style="margin-top:12px">Shamil cheezein</div>' + (l.proj_items || []).map(function (x, j) { return '<div class="pi"><span class="grow">' + esc((x.title ? x.title + ' – ' : '') + x.name) + '</span><input class="inp" style="width:70px;min-height:32px" data-pq="' + j + '" value="' + esc(x.qty) + '" inputmode="decimal"><button class="btn btn-g btn-icon btn-sm" data-prm="' + j + '">' + C.ic('x') + '</button></div>'; }).join('') + '<label class="ck" style="margin-top:8px"><input type="checkbox" data-f="show_prices"' + (l.show_prices ? ' checked' : '') + '> Andar ke items ka rate dikhayein</label>' : '') +
        '<details style="margin-top:8px"' + (l.desc || l.more ? ' open' : '') + '><summary class="sm b" style="cursor:pointer;color:var(--leaf-d)">Details / HSN</summary><div class="fg" style="margin-top:8px"><div class="f full"><label>Description (har line ek point)</label><textarea class="inp" rows="3" data-f="desc">' + esc(l.desc || '') + '</textarea></div><div class="f"><label>More info</label><input class="inp" data-f="more" value="' + esc(l.more || '') + '"></div><div class="f"><label>HSN / SAC</label><input class="inp" data-f="hsn" value="' + esc(l.hsn || '') + '"></div></div></details></div>';
    }
    var stk = {}; if (type === 'quote' && C.can('items.view')) { C.call('crm_stock_report', {}).then(function (rp) { (rp.rows || []).forEach(function (x) { stk[x.id] = x; }); stkHints(); }).catch(function () {}); }
    function ownQty(id) { var n = 0; if (rec && ['draft', 'sent', 'accepted'].indexOf(rec.status) >= 0) (rec.data.lines || []).forEach(function (l) { if ((l.kind || 'product') === 'project') (l.proj_items || []).forEach(function (x) { if (String(x.item_id) === String(id)) n += num(x.qty) * (num(l.qty) || 1); }); else if (String(l.item_id) === String(id)) n += num(l.qty); }); return n; }
    function stkHints() {
      $$('.dl', el).forEach(function (box) {
        var l = d.lines[+box.getAttribute('data-i')], h = $('.stk', box); if (!h || !l) return; var s0 = stk[l.item_id];
        if ((l.kind || 'product') === 'project' || !s0) { h.hidden = true; return; }
        var free = s0.free_offline + ownQty(l.item_id), bad = num(l.qty) > free; h.hidden = false; h.className = 'stk xs ' + (bad ? 'err' : 'mute'); h.textContent = bad ? 'Stock kam hai: offline ke liye sirf ' + free + ' bacha (20% online ke liye surakshit)' : 'Offline ke liye bacha: ' + free + ' ' + (s0.unit || '');
      });
    }
    function drawLines() { $('#lines', el).innerHTML = d.lines.length ? d.lines.map(lineHtml).join('') : C.empty('box', 'Abhi koi item nahi', 'Upar "Product / Template jodein" dabayein'); drawTot(); stkHints(); }
    drawParty(); drawLines(); C.addrBind(el);
    var ss = $('#shipSame', el); if (ss) ss.addEventListener('change', function () { shipSame = ss.checked; $('#shipBox', el).hidden = shipSame; });
    el.addEventListener('input', function (e) {
      var t = e.target, k = t.getAttribute('data-k'); if (k) { d[k] = t.value; if (k === 'discount') updTot(); return; }
      var box = t.closest('[data-i]'); if (!box) return; var l = d.lines[+box.getAttribute('data-i')], f = t.getAttribute('data-f'), pq = t.getAttribute('data-pq');
      if (pq != null) { l.proj_items[+pq].qty = t.value; return; }
      if (!f) return; l[f] = t.type === 'checkbox' ? t.checked : t.value;
      if (f === 'qty' || f === 'price' || f === 'gst') { $('[data-amt]', box).value = C.r2(num(l.qty) * num(l.price) * (1 + num(l.gst) / 100)); updTot(); if (f === 'qty') stkHints(); }
    });
    el.addEventListener('change', function (e) { var t = e.target; if (t.id === 'sip') d.show_item_prices = t.checked; if (t.getAttribute('data-f') === 'show_prices') d.lines[+t.closest('[data-i]').getAttribute('data-i')].show_prices = t.checked; if (t.getAttribute('data-f') === 'price') { var bx = t.closest('[data-i]'), ln = d.lines[+bx.getAttribute('data-i')], w = $('.minw', bx); if (w) w.hidden = !(ln.min && num(ln.price) < ln.min); } });
    el.addEventListener('click', function (e) {
      var b;
      if ((b = e.target.closest('[data-qm],[data-qp]'))) {
        var bx0 = b.closest('[data-i]'), ln0 = d.lines[+bx0.getAttribute('data-i')], q0 = num(ln0.qty) || 0; q0 = b.hasAttribute('data-qp') ? q0 + 1 : Math.max(1, q0 - 1); ln0.qty = q0;
        $('[data-f=qty]', bx0).value = q0; $('[data-amt]', bx0).value = C.r2(q0 * num(ln0.price) * (1 + num(ln0.gst) / 100)); updTot(); stkHints();
      }
      else if ((b = e.target.closest('[data-rm]'))) { d.lines.splice(+b.getAttribute('data-rm'), 1); drawLines(); }
      else if ((b = e.target.closest('[data-up]'))) { var i = +b.getAttribute('data-up'), x = d.lines[i]; d.lines[i] = d.lines[i - 1]; d.lines[i - 1] = x; drawLines(); }
      else if ((b = e.target.closest('[data-prm]'))) { d.lines[+b.closest('[data-i]').getAttribute('data-i')].proj_items.splice(+b.getAttribute('data-prm'), 1); drawLines(); }
    });
    function payload() {
      var lines = d.lines.filter(function (l) { return String(l.name || '').trim(); }).map(function (l) { var o = Object.assign({}, l); o.qty = num(o.qty); o.price = C.r2(o.price); o.gst = num(o.gst); delete o.min; return o; });
      var out = Object.assign({}, d, { lines: lines, discount: C.r2(d.discount), party: party ? snap(party) : d.party });
      if (type !== 'purchase') { out.ship_same = shipSame; if (shipSame) { out.ship = ''; delete out.ship_addr; } else { var so = C.form($('#shipBox', el)), sa = C.addrRead(so, 'ship_'); out.ship_addr = sa; out.ship = C.addrText(sa); } }
      return out;
    }
    async function doSave(send) {
      if (!party) return C.toast('Pehle ' + (type === 'purchase' ? 'supplier' : 'customer') + ' chunein', true);
      var x = payload(); if (type === 'quote' && (isNew || x.qtitle) && String(x.qtitle || '').trim().length < 2) { var ti = $('[data-k=qtitle]', el); if (ti) { ti.classList.add('bad'); ti.focus(); } return C.toast('Pehle quotation ka Title likhein', true); }
      if (!x.lines.length) return C.toast('Kam se kam 1 item jodein', true);
      if (x.lines.some(function (l) { return num(l.qty) <= 0; })) return C.toast('Har item ki Qty likhein', true);
      try { var r = await C.run('crm_save', { kind: type, id: rec ? rec.id : null, party_id: party.id, data: x }, 'Save ho gaya ✔'); C.go('#/' + type + '/' + r.id + (send ? '?send=1' : '')); } catch (e) {}
    }
    C.bind(el, {
      party: async function () { if (type !== 'purchase') { party = null; drawParty(); var q0 = $('#pbox [data-piq]', el); if (q0) q0.focus(); return; } var p = await C.partyPick({ type: 'supplier', title: 'Supplier chunein', prefill: { type: 'supplier' } }); if (p) { party = p; drawParty(); } },
      toproj: function () { saveAsProject(payload()); },
      add: async function () { var its = await C.itemPick(type === 'purchase' ? 'product' : null, true); its.forEach(function (it) { d.lines.push(lineFromItem(it, type)); }); drawLines(); },
      newitem: async function () { var r = await C.itemForm(null, 'product'); if (r) { C.cache.items = null; d.lines.push(lineFromItem(r, type)); drawLines(); } },
      prev: function () { var x = payload(), t = calc(x.lines, x.discount); Object.assign(x, t); C.modal({ title: 'Preview', size: 'wide', body: '<div class="preview">' + C.billHtml({ ref: rec ? rec.ref : '(Save ke baad number)', data: x, created_at: new Date().toISOString(), title: party ? party.title : '' }, type) + '</div>' }); },
      save: function () { doSave(false); },
      savesend: function () { doSave(true); }
    });
  }

  /* expired quotation → Renew (default 15 din) */
  function renewDlg(r) {
    return new Promise(function (res) {
      var m = C.modal({ title: 'Quotation Renew', size: 'sm', body: '<p style="margin-bottom:12px">' + esc(r.ref) + (r.data.qtitle ? ' — ' + esc(r.data.qtitle) : '') + '</p>' + C.f('Aaj se kitne din valid?', '<input class="inp" type="number" min="1" max="365" id="rnd" value="15">') + '<p class="hint" style="margin-top:8px">Pehle jo status tha wahi wapas aayega. Stock kam hua to renew nahi hoga.</p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Renew karein</button>' });
      $('[data-ok]', m.el).onclick = async function () { try { var x = await C.run('crm_quote_renew', { id: r.id, days: +$('#rnd', m.el).value || 15 }, 'Renew ho gayi ✔'); m.close(); res(x); } catch (e) {} };
    });
  }

  /* ================================================================ view (quotation / bill / purchase) */
  function shareText(r, type) {
    var co = C.company(), d = r.data || {}, nm = (d.party || {}).name || r.title;
    if (type === 'quote') return 'Namaste ' + nm + ' ji 🙏\n' + (co.name || '') + ' ki taraf se aapki quotation *' + r.ref + '*\nKul: *' + money(r.amount) + '*' + (d.valid_till ? '\nValid: ' + C.fd(d.valid_till) + ' tak' : '') + '\n\nKoi sawal ho to isi number par message karein.' + (co.phone ? '\n📞 ' + co.phone : '');
    if (type === 'invoice') return 'Namaste ' + nm + ' ji 🙏\nAapka bill *' + r.ref + '* — Kul ' + money(r.amount) + (num(d.balance) > 0 ? '\nBaaki: *' + money(d.balance) + '*' + (co.upi ? '\nUPI: ' + co.upi : '') : '\nPoora payment mil gaya — dhanyavaad!') + '\n' + (co.name || '');
    return 'Namaste ' + nm + ' ji, ' + (co.name || '') + ' ka purchase order *' + r.ref + '* — kul ' + money(r.amount) + '. Kripya maal bhejein.';
  }
  async function view(el, type, id, q) {
    var r = await C.get(id), d = r.data || {}, pays = [];
    if (type === 'invoice') { pays = (await C.list('payment', { party_id: r.party_id }).catch(function () { return []; })).filter(function (p) { return String(p.data.invoice_id) === String(r.id); }); r.payments = pays.slice().reverse(); }
    var phone = (d.party || {}).mobile || r.mobile, acts = [];
    acts.push('<button class="btn btn-wa" data-act="share">' + C.ic('wa') + ' PDF WhatsApp</button><button class="btn btn-o" data-act="print">' + C.ic('printer') + ' Print</button>');
    if (type === 'quote') {
      if (r.status === 'expired' && C.can('quotes.edit')) acts.push('<button class="btn btn-p" data-act="renew">' + C.ic('clock') + ' Renew (nayi validity)</button>');
      if (r.status !== 'converted' && r.status !== 'expired' && C.can('quotes.edit')) acts.push('<a class="btn btn-o" href="#/quote/' + r.id + '/edit">' + C.ic('edit') + ' Badlein</a>');
      if (C.can('quotes.create')) acts.push('<a class="btn btn-o" href="#/quote/new?copy=' + r.id + '">' + C.ic('copy') + ' Copy</a>');
      if (r.status !== 'converted' && r.status !== 'expired' && C.can('invoices.create')) acts.push('<button class="btn btn-p" data-act="convert">' + C.ic('bill') + ' Bill banayein</button>');
      if (d.invoice_id) acts.push('<a class="btn btn-p" href="#/invoice/' + d.invoice_id + '">' + C.ic('bill') + ' Bill ' + esc(d.invoice_ref || '') + '</a>');
      if (C.can('quotes.delete') && r.status !== 'converted') acts.push('<button class="btn btn-r btn-icon" data-act="del" aria-label="Hatayein">' + C.ic('trash') + '</button>');
    } else if (type === 'invoice') {
      if (C.can('payments.record') && r.status !== 'paid') acts.push('<button class="btn btn-p" data-act="pay">' + C.ic('rupee') + ' Payment jodein</button>');
      if (C.can('invoices.edit')) acts.push('<a class="btn btn-o" href="#/invoice/' + r.id + '/edit">' + C.ic('edit') + ' Badlein</a>');
      if (d.quote_id) acts.push('<a class="btn btn-o" href="#/quote/' + d.quote_id + '">' + C.ic('quote') + ' ' + esc(d.quote_ref || 'Quotation') + '</a>');
      if (C.can('invoices.delete')) acts.push('<button class="btn btn-r btn-icon" data-act="del" aria-label="Hatayein">' + C.ic('trash') + '</button>');
    } else {
      if (r.status === 'open') acts.push('<a class="btn btn-o" href="#/purchase/' + r.id + '/edit">' + C.ic('edit') + ' Badlein</a><button class="btn btn-p" data-act="recv">' + C.ic('check') + ' Maal aa gaya</button>');
      if (r.status === 'open') acts.push('<button class="btn btn-r btn-icon" data-act="del" aria-label="Hatayein">' + C.ic('trash') + '</button>');
    }
    var h = '<div class="crumb"><a href="#/' + (type === 'quote' ? 'quotes' : 'billing' + (type === 'purchase' ? '?tab=purchase' : '')) + '">' + T[type] + '</a>' + C.ic('right') + '<span>' + esc(r.ref) + '</span></div>' +
      '<div class="ph"><div><h1>' + esc(r.ref) + ' ' + C.billPill(r) + '</h1>' + (type === 'quote' && d.qtitle ? '<p class="qtt">' + esc(d.qtitle) + '</p>' : '') + '<p><a href="#/customer/' + r.party_id + '" style="color:var(--leaf-d);font-weight:700">' + esc(r.party_name || r.title) + '</a> · ' + money(r.amount) + ' · ' + esc(r.owner_name || '') + '</p></div><div class="row wrap">' + acts.join('') + '</div></div>';
    if (type === 'quote' && r.status === 'expired') h += '<div class="note o" style="margin-bottom:12px">' + C.ic('clock') + ' Ye quotation ' + esc(C.fd(d.expired_on || d.valid_till)) + ' ko expire ho gayi — stock ka reserve chhod diya gaya hai. Dobara chalane ke liye <b>Renew</b> karein' + (d.renewals ? ' (pehle ' + num(d.renewals) + ' bar renew ho chuki)' : '') + '.</div>';
    if (type === 'quote' && r.status !== 'converted' && r.status !== 'expired' && C.can('quotes.edit')) h += '<div class="bar"><span class="sm b">Status:</span>' + C.chips(['draft', 'sent', 'accepted', 'rejected'].map(function (s) { return [s, QST[s][0]]; }), r.status, 'qs') + '</div>';
    if (type === 'invoice') h += '<div class="kpis">' + C.kpi('Kul bill', money(r.amount)) + C.kpi('Mila', money(d.paid || 0)) + C.kpi('Baaki', money(d.balance != null ? d.balance : r.amount), d.due_date ? 'Aakhri tareekh ' + C.fd(d.due_date) : '', num(d.balance) > 0 ? 'warn' : '') + '</div>' + (pays.length ? '<div class="list" style="margin-bottom:14px">' + pays.map(function (p) { return C.payRow(p, true); }).join('') + '</div>' : '');
    if (type === 'quote') h += '<div id="wfq"></div>';
    h += '<div class="preview">' + C.billHtml(r, type) + '</div>';
    el.innerHTML = h;
    if (type === 'quote' && C.wfCard) C.wfCard($('#wfq', el), { quote_id: r.id, upto: 7, title: 'Customer ka process (Apply Process tak)', onChange: function () { C.render(); } });
    var fname = (type === 'quote' ? 'Quotation-' : type === 'invoice' ? 'Bill-' : 'PO-') + String(r.ref).replace(/\//g, '-') + '.pdf';
    el.addEventListener('click', function (e) { var c = e.target.closest('[data-qs]'); if (c && c.getAttribute('data-qs') !== r.status) C.setStatus(r.id, c.getAttribute('data-qs')).then(function () { C.render(); }).catch(function () {}); });
    if (q && q.send) { C.setQuery({ send: '' }); setTimeout(function () { var b = $('[data-act=share]', el); if (b) b.click(); }, 50); }
    C.bind(el, {
      share: async function () { await C.sharePdf(C.billHtml(r, type), fname, shareText(r, type), phone); if (type === 'quote' && r.status === 'draft' && C.can('quotes.edit')) { try { await C.call('crm_status', { id: r.id, status: 'sent' }); C.render(); } catch (e) {} } },
      print: function () { C.printHtml(C.billHtml(r, type), r.ref); },
      convert: async function () {
        var m = C.modal({ title: 'Quotation se Bill banayein', size: 'sm', body: '<p style="margin-bottom:12px">' + esc(r.ref) + ' — ' + money(r.amount) + '</p>' + C.f('Payment ki aakhri tareekh (optional)', '<input class="inp" type="date" id="dd" value="' + C.addDays(C.today(), 7) + '">') + '<p class="hint" style="margin-top:8px">Bill banne par stock apne aap ghat jayega.</p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Bill banayein</button>' });
        $('[data-ok]', m.el).onclick = async function () { try { var inv = await C.run('crm_convert', { id: r.id, due_date: $('#dd', m.el).value }, 'Bill ban gaya ✔'); m.close(); C.go('#/invoice/' + inv.id); } catch (e) {} };
      },
      renew: function () { renewDlg(r).then(function (x) { if (x) C.render(); }); },
      pay: function () { C.payForm({ invoice: r }).then(function (x) { if (x) C.render(); }); },
      recv: async function () { if (await C.confirm('Maal aa gaya? Stock badh jayega.', 'Haan')) { try { await C.setStatus(r.id, 'received'); C.render(); } catch (e) {} } },
      del: async function () { if (await C.delWithReason(r, r.ref)) C.go(type === 'quote' ? '#/quotes' : '#/billing' + (type === 'purchase' ? '?tab=purchase' : '')); },
      rshare: function (pid) { var p = pays.find(function (x) { return String(x.id) === pid; }); C.receipt(p, 'share'); },
      pdel: async function (pid) { var p = pays.find(function (x) { return String(x.id) === pid; }); if (await C.delWithReason(p, 'Payment ' + p.ref)) C.render(); }
    });
  }

  /* ================================================================ payments */
  C.payRow = function (p, withActs) {
    return '<div class="li"><span class="av">' + C.ic('rupee') + '</span><span class="grow"><span class="t">' + esc(p.ref) + ' — ' + esc(p.title) + '</span><span class="m"><span>' + esc(C.fd(p.due_at)) + '</span><span>' + esc(p.data.mode || '') + '</span>' + (p.data.utr ? '<span>' + esc(p.data.utr) + '</span>' : '') + (p.data.invoice_ref ? '<span>' + esc(p.data.invoice_ref) + '</span>' : '') + '<span>' + esc(p.owner_name || '') + '</span></span></span><span class="amt">' + money(p.amount) + '</span>' + (withActs ? '<span class="acts"><button class="btn btn-wa btn-icon btn-sm" data-act="rshare" data-id="' + p.id + '" title="Rasid bhejein">' + C.ic('share') + '</button>' + (C.can('payments.delete') ? '<button class="btn btn-g btn-icon btn-sm" data-act="pdel" data-id="' + p.id + '">' + C.ic('trash') + '</button>' : '') + '</span>' : '') + '</div>';
  };
  C.receiptHtml = function (p) {
    var co = C.company();
    return '<style>' + C.BILL_CSS + '</style><div class="bill" data-noi18n><div class="hdw"><table class="hd"><tr><td><h1>' + esc(co.legal || co.name || '') + '</h1><div class="sm">' + esc(co.address || '') + (co.phone ? '<br>Ph: ' + esc(co.phone) : '') + (co.gstin ? '<br>GSTIN: ' + esc(co.gstin) : '') + '</div></td><td><div class="ttl">PAYMENT RECEIPT</div><div class="sm r">No: ' + esc(p.ref) + '<br>Date: ' + C.fd(p.due_at) + '</div></td></tr></table></div>' +
      '<p style="font-size:14px;line-height:1.9">Received with thanks from <b>' + esc(p.title) + '</b> (' + esc(p.mobile || '') + ') the sum of <b>' + money(p.amount, 1) + '</b> (' + C.words(p.amount) + ') by <b>' + esc(p.data.mode || '') + '</b>' + (p.data.utr ? ' (Ref: ' + esc(p.data.utr) + ')' : '') + (p.data.invoice_ref ? ' against Bill <b>' + esc(p.data.invoice_ref) + '</b>' : '') + '.</p>' + (p.data.note ? '<p class="sm">' + esc(p.data.note) + '</p>' : '') +
      '<table style="margin-top:40px"><tr><td></td><td class="sm r">For <b>' + esc(co.legal || co.name || '') + '</b><br>' + (co.sign ? '<img src="' + esc(co.sign) + '" style="max-height:48px;display:inline-block"><br>' : '<br><br>') + esc(co.sign_label || 'Authorised Signatory') + '</td></tr></table>' + C.pstrip() + '</div>';
  };
  C.receipt = function (p, mode) { var html = C.receiptHtml(p); if (mode === 'print') return C.printHtml(html, p.ref); C.sharePdf(html, 'Receipt-' + String(p.ref).replace(/\//g, '-') + '.pdf', 'Namaste ' + p.title + ' ji, aapka ' + money(p.amount) + ' ka payment mil gaya. Rasid ' + p.ref + ' — dhanyavaad 🙏', p.mobile); };
  C.payForm = function (o) {
    o = o || {}; var inv = o.invoice, party = o.party;
    return new Promise(async function (res) {
      var pid = inv ? inv.party_id : party ? party.id : null, invs = [];
      if (pid) { try { invs = (await C.list('invoice', { party_id: pid })).filter(function (x) { return x.status !== 'paid'; }); } catch (e) {} }
      var bal = inv ? num(inv.data.balance != null ? inv.data.balance : inv.amount) : '';
      var body = '<form id="pyf" class="fg">' + (inv ? '' : C.f('Customer', '<button type="button" class="btn btn-o" data-pp style="justify-content:flex-start">' + C.ic('users') + '<span class="ellip">' + esc(party ? party.title : 'Chunein') + '</span></button>', 'full') + C.f('Kis bill ka?', '<select class="inp" name="invoice_id" id="pinv">' + invOpts() + '</select>', 'full')) +
        C.f('Amount (₹) *', C.inp('amount', bal || '', 'inputmode="decimal"')) + C.f('Tareekh', C.inp('date', C.today(), 'type="date"')) + C.f('Kaise mila', C.sel('mode', MODES, 'UPI')) + C.f('UTR / Cheque no.', C.inp('utr', '')) + C.f('Note', C.inp('note', ''), 'full') + '</form>';
      function invOpts() { return '<option value="">— Advance / bina bill —</option>' + invs.map(function (x) { return '<option value="' + x.id + '">' + esc(x.ref) + ' — baaki ' + money(x.data.balance != null ? x.data.balance : x.amount) + '</option>'; }).join(''); }
      var m = C.modal({ title: 'Payment jodein' + (inv ? ' — ' + inv.ref : ''), body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } }), f = $('#pyf', m.el);
      var pp = $('[data-pp]', m.el); if (pp) pp.onclick = async function () { var p = await C.partyPick(); if (!p) return; pid = p.id; party = p; $('span', pp).textContent = p.title; try { invs = (await C.list('invoice', { party_id: pid })).filter(function (x) { return x.status !== 'paid'; }); } catch (e) { invs = []; } $('#pinv', m.el).innerHTML = invOpts(); };
      var pi = $('#pinv', m.el); if (pi) pi.onchange = function () { var x = invs.find(function (z) { return String(z.id) === pi.value; }); if (x) f.amount.value = num(x.data.balance != null ? x.data.balance : x.amount); };
      $('[data-ok]', m.el).onclick = async function () {
        var v = C.form(f); if (num(v.amount) <= 0) { f.amount.classList.add('bad'); return C.toast('Amount likhein', true); }
        if (!pid) return C.toast('Customer chunein', true);
        var iid = inv ? inv.id : v.invoice_id, ix = inv || invs.find(function (z) { return String(z.id) === String(iid); });
        if (ix && num(v.amount) > num(ix.data.balance != null ? ix.data.balance : ix.amount) + 0.01 && !(await C.confirm('Amount bill ke baaki se zyada hai. Phir bhi save karein?', 'Haan'))) return;
        try {
          var r = await C.run('crm_save', { kind: 'payment', party_id: pid, data: { amount: C.r2(v.amount), date: v.date, mode: v.mode, utr: v.utr, note: v.note, invoice_id: iid ? String(iid) : '', invoice_ref: ix ? ix.ref : '' } }, 'Payment jud gaya ✔');
          m.el.remove(); document.documentElement.style.overflow = ''; res(r);
          if (await C.confirm('Customer ko rasid (receipt) WhatsApp par bhejein?', 'Haan, bhejein')) C.receipt(r, 'share');
        } catch (e) {}
      };
    });
  };

  /* ================================================================ routes */
  C.mod('quote', { title: 'Quotation', nav: 'quotes', routes: ['quote'], render: async function (el, params, q) { if (params[0] === 'new') { if (!C.can('quotes.create')) throw new Error('Aapko quotation banane ki permission nahi hai'); return editor(el, 'quote', null, q); } if (params[1] === 'edit') return editor(el, 'quote', await C.get(params[0]), q); return view(el, 'quote', params[0], q); } });
  C.mod('invoice', { title: 'Bill', nav: 'billing', routes: ['invoice'], render: async function (el, params, q) { if (params[1] === 'edit') return editor(el, 'invoice', await C.get(params[0]), q); return view(el, 'invoice', params[0]); } });
  C.mod('purchase', { title: 'Purchase', nav: 'billing', routes: ['purchase'], allowed: function () { return C.can('purchase.manage'); }, render: async function (el, params, q) { if (params[0] === 'new') return editor(el, 'purchase', null, q); if (params[1] === 'edit') return editor(el, 'purchase', await C.get(params[0]), q); return view(el, 'purchase', params[0]); } });

  function qpTabs(tab, nProj) {
    return '<div class="tabs"><button data-goto="#/quotes" class="' + (tab !== 'projects' ? 'on' : '') + '">Quotations</button><button data-goto="#/quotes?tab=projects" class="' + (tab === 'projects' ? 'on' : '') + '">Templates' + (nProj != null ? ' (' + nProj + ')' : '') + '</button></div>';
  }
  C.mod('quotes', {
    title: 'Quotations & Templates',
    allowed: function () { return C.canAny('quotes.create', 'quotes.view_all', 'items.view'); },
    render: async function (el, params, q) {
      if (q.tab === 'projects') { if (!C.can('items.view')) throw new Error('Templates dekhne ki permission nahi hai'); return C.itemsPage(el, q, { route: '#/quotes', extra: { tab: 'projects' }, tp: 'project', tabs: function (n) { return qpTabs('projects', n); } }); }
      if (!C.canAny('quotes.create', 'quotes.view_all')) return C.go('#/quotes?tab=projects');
      var st = q.st || '', uid = q.user || '', all = await C.list('quote', { limit: 3000, user_id: uid || null }), cnt = {};
      var isClosed = function (x) { return x.data.closed === true; }, isItems = function (x) { return x.data.ctype === 'Items only' && ['accepted', 'converted'].indexOf(x.status) >= 0; };
      var act = all.filter(function (x) { return !isClosed(x) && !isItems(x); }), nPend = all.filter(function (x) { return x.data.bill_state === 'pending'; }).length, nItems = all.filter(isItems).length, nClosed = all.filter(isClosed).length;
      act.forEach(function (x) { cnt[x.status] = (cnt[x.status] || 0) + 1; });
      var list = st === 'pend' ? all.filter(function (x) { return x.data.bill_state === 'pending'; }) : st === 'items' ? all.filter(isItems) : st === 'closed' ? all.filter(isClosed) : act.filter(function (x) { return !st || x.status === st; });
      var h = '<div class="ph"><div><h1>Quotations &amp; Templates</h1><p>Customer chunein → items jodein → PDF WhatsApp par. Maan li to ek click me Bill.</p></div><div class="row">' + C.reportBtns('Quotations', function () { return { head: ['No', 'Tareekh', 'Customer', 'Title', 'Mobile', 'Amount', 'Status', 'Banane wala'], rows: list.map(function (x) { return [x.ref, C.fd(x.data.date || x.created_at), x.title, x.data.qtitle || '', x.mobile || '', num(x.amount), (QST[x.status] || [x.status])[0], x.owner_name || '']; }) }; }) + (C.can('quotes.create') ? '<a class="btn btn-p" href="#/quote/new">' + C.ic('plus') + ' Nayi quotation</a>' : '') + '</div></div>';
      h += qpTabs('quotes', C.can('items.view') ? ((C.cache.items || []).filter(function (x) { return x.data.type === 'project'; }).length || null) : null) + '<div class="bar">' + C.chips([['', 'Sab', act.length]].concat(Object.keys(QST).map(function (s) { return [s, QST[s][0], cnt[s] || 0]; })).concat([['pend', 'Pending bill', nPend], ['items', 'Items (confirmed)', nItems], ['closed', 'Bill clear', nClosed]]), st, 'st') + '</div><div class="bar"><input class="inp" type="search" data-q placeholder="No / customer khojein">' + (C.can('quotes.view_all') ? C.userFilter(uid) : '') + '<span class="sp"></span><span class="b">' + money(C.sum(list, 'amount')) + '</span></div>';
      h += list.length ? '<div class="list" id="ql">' + list.map(function (x) { return '<a class="li" href="#/quote/' + x.id + '"><span class="av b">' + C.ic('quote') + '</span><span class="grow"><span class="t">' + esc(x.title) + (x.data.qtitle ? ' <span class="qt">' + esc(x.data.qtitle) + '</span>' : '') + ' ' + C.billPill(x) + (x.data.ctype ? ' ' + C.pill(x.data.ctype, 'v') : '') + (x.data.bill_state === 'pending' ? C.ribbon('Pending bill', 'o') : '') + (x.data.closed ? C.ribbon('Bill clear', 'g') : '') + '</span><span class="m"><span>' + esc(x.ref) + '</span><span>' + esc(C.fd(x.data.date || x.created_at)) + '</span>' + (x.data.valid_till && ['draft', 'sent', 'accepted', 'expired'].indexOf(x.status) >= 0 ? '<span>' + C.ic('clock') + (x.status === 'expired' ? 'Expire: ' : 'Valid: ') + esc(C.fd(x.data.valid_till)) + '</span>' : '') + (x.due_at && x.status === 'draft' ? '<span>' + C.ic('clock') + 'Bhejna: ' + esc(C.fd(x.due_at)) + '</span>' : '') + '<span>' + esc(x.owner_name || '') + '</span></span></span>' + (x.status === 'expired' && C.can('quotes.edit') ? '<button class="btn btn-o btn-sm" data-renew="' + x.id + '">Renew</button>' : '') + '<span class="amt">' + money(x.amount) + '</span></a>'; }).join('') + '</div>' : '<div class="card">' + C.empty('quote', 'Koi quotation nahi', '') + '</div>';
      el.innerHTML = h;
      var ql = $('#ql', el); if (ql) C.filterList($('[data-q]', el), ql);
      el.addEventListener('click', function (e) { var gt = e.target.closest('[data-goto]'); if (gt) return C.go(gt.getAttribute('data-goto')); var rn = e.target.closest('[data-renew]'); if (rn) { e.preventDefault(); var rr = all.find(function (z) { return String(z.id) === rn.getAttribute('data-renew'); }); renewDlg(rr).then(function (x) { if (x) C.render(); }); return; } var c = e.target.closest('[data-st]'); if (c) C.go('#/quotes' + C.qs({ st: c.getAttribute('data-st'), user: uid })); });
      var us = $('[data-user]', el); if (us) us.onchange = function () { C.go('#/quotes' + C.qs({ st: st, user: this.value })); };
    }
  });

  C.mod('billing', {
    title: 'Billing',
    allowed: function () { return C.canAny('invoices.create', 'invoices.view_all', 'payments.record', 'purchase.manage') || C.isPartner(); },
    render: async function (el, params, q) {
      var tab = q.tab || 'bills', from = q.from || '', to = q.to || '';
      var tabs = [['bills', 'Bill'], ['due', 'Baaki payment'], ['payments', 'Payments']];
      if (C.can('purchase.manage')) tabs.push(['purchase', 'Purchase']);
      if (C.canAny('reports.view', 'invoices.view_all')) tabs.push(['reports', 'Reports']);
      var h = '<div class="ph"><div><h1>Billing</h1><p>GST bill quotation se banta hai — payment jodte hi baaki apne aap update.</p></div><div class="row">' + (C.can('payments.record') ? '<button class="btn btn-o" data-act="pay">' + C.ic('rupee') + ' Payment jodein</button>' : '') + (tab === 'purchase' ? '<a class="btn btn-p" href="#/purchase/new">' + C.ic('plus') + ' Purchase order</a>' : C.can('quotes.create') ? '<a class="btn btn-p" href="#/quote/new">' + C.ic('plus') + ' Nayi quotation</a>' : '') + '</div></div>';
      h += '<div class="tabs">' + tabs.map(function (t) { return '<button data-tab="' + t[0] + '" class="' + (tab === t[0] ? 'on' : '') + '">' + t[1] + '</button>'; }).join('') + '</div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Khojein"><span class="xs mute">Se</span><input class="inp" type="date" data-from value="' + esc(from) + '" style="width:auto"><span class="xs mute">Tak</span><input class="inp" type="date" data-to value="' + esc(to) + '" style="width:auto"><span class="sp"></span><span id="rbx"></span></div><div id="bl"></div>';
      el.innerHTML = h;
      var opt = { limit: 3000, from: from || null, to: to || null }, body = '', rep = null;
      if (tab === 'bills' || tab === 'due') {
        var inv = await C.list('invoice', tab === 'due' ? { limit: 3000 } : opt); if (tab === 'due') inv = inv.filter(function (x) { return x.status !== 'paid'; });
        var tot = C.sum(inv, 'amount'), bal = C.sum(inv, function (x) { return x.data.balance != null ? x.data.balance : x.amount; });
        body = '<div class="kpis">' + C.kpi(tab === 'due' ? 'Kul baaki' : 'Kul bill', money(tab === 'due' ? bal : tot), inv.length + ' bill', tab === 'due' ? 'warn' : '') + (tab === 'bills' ? C.kpi('Baaki', money(bal), '', bal > 0 ? 'warn' : '') : '') + '</div>' +
          (inv.length ? '<div class="list" id="ll">' + inv.map(function (x) { var od = x.status !== 'paid' && x.due_at && x.due_at < C.today(); return '<div class="li click' + (od ? ' over' : '') + '" data-href="#/invoice/' + x.id + '"><span class="av o">' + C.ic('bill') + '</span><span class="grow"><span class="t">' + esc(x.title) + ' ' + C.billPill(x) + (x.status !== 'paid' ? C.ribbon('Pending', 'o') : '') + '</span><span class="m"><span>' + esc(x.ref) + '</span><span>' + esc(C.fd(x.data.date || x.created_at)) + '</span>' + (x.due_at && x.status !== 'paid' ? '<span>' + C.ic('clock') + esc(C.fd(x.due_at)) + '</span>' : '') + '<span>' + esc(x.owner_name || '') + '</span></span></span><span class="amt">' + money(x.amount) + (x.status !== 'paid' ? '<small>Baaki ' + money(x.data.balance != null ? x.data.balance : x.amount) + '</small>' : '') + '</span>' + (tab === 'due' ? '<span class="acts">' + C.callBtns(x.mobile, shareText(x, 'invoice')) + '</span>' : '') + '</div>'; }).join('') + '</div>' : '<div class="card">' + C.empty('bill', tab === 'due' ? 'Koi payment baaki nahi 🎉' : 'Koi bill nahi', 'Bill quotation se banta hai: Quotation → "Bill banayein"') + '</div>');
        rep = function () { return { head: ['Bill No', 'Tareekh', 'Customer', 'Mobile', 'GSTIN', 'Taxable', 'GST', 'Discount', 'Kul', 'Mila', 'Baaki', 'Status'], rows: inv.map(function (x) { var d = x.data; return [x.ref, C.fd(d.date || x.created_at), x.title, x.mobile || '', (d.party || {}).gstin || '', num(d.subtotal), num(d.gst_total), num(d.discount), num(x.amount), num(d.paid), num(d.balance != null ? d.balance : x.amount), (IST[x.status] || [x.status])[0]]; }), text: tab === 'due' ? 'Baaki payment list' : 'Sales register' }; };
      } else if (tab === 'payments') {
        var pays = await C.list('payment', opt);
        body = '<div class="kpis">' + C.kpi('Kul mila', money(C.sum(pays, 'amount')), pays.length + ' payment', 'gold') + MODES.map(function (md) { var s = C.sum(pays.filter(function (p) { return p.data.mode === md; }), 'amount'); return s ? C.kpi(md, money(s)) : ''; }).join('') + '</div>' + (pays.length ? '<div class="list" id="ll">' + pays.map(function (p) { return C.payRow(p, true); }).join('') + '</div>' : '<div class="card">' + C.empty('rupee', 'Koi payment nahi') + '</div>');
        rep = function () { return { head: ['Rasid No', 'Tareekh', 'Customer', 'Mobile', 'Mode', 'UTR', 'Bill', 'Amount', 'Note'], rows: pays.map(function (p) { return [p.ref, C.fd(p.due_at), p.title, p.mobile || '', p.data.mode || '', p.data.utr || '', p.data.invoice_ref || '', num(p.amount), p.data.note || '']; }), text: 'Payment register' }; };
        C.bind(el, { rshare: function (id) { C.receipt(pays.find(function (x) { return String(x.id) === id; }), 'share'); }, pdel: async function (id) { var p = pays.find(function (x) { return String(x.id) === id; }); if (await C.delWithReason(p, 'Payment ' + p.ref)) C.render(); } });
      } else if (tab === 'purchase') {
        var po = await C.list('purchase', opt);
        body = po.length ? '<div class="list" id="ll">' + po.map(function (x) { return '<a class="li" href="#/purchase/' + x.id + '"><span class="av b">' + C.ic('cart') + '</span><span class="grow"><span class="t">' + esc(x.title) + ' ' + C.billPill(x) + '</span><span class="m"><span>' + esc(x.ref) + '</span><span>' + esc(C.fd(x.data.date || x.created_at)) + '</span></span></span><span class="amt">' + money(x.amount) + '</span></a>'; }).join('') + '</div>' : '<div class="card">' + C.empty('cart', 'Koi purchase order nahi', 'Supplier se maal mangane ke liye banayein — "Maal aa gaya" dabane par stock badhega') + '</div>';
        rep = function () { return { head: ['PO No', 'Tareekh', 'Supplier', 'GSTIN', 'Taxable', 'GST', 'Kul', 'Status'], rows: po.map(function (x) { var d = x.data; return [x.ref, C.fd(d.date || x.created_at), x.title, (d.party || {}).gstin || '', num(d.subtotal), num(d.gst_total), num(x.amount), (PST[x.status] || [x.status])[0]]; }), text: 'Purchase register' }; };
      } else if (tab === 'reports') {
        var res = await Promise.all([C.list('invoice', opt), C.list('payment', opt), C.can('purchase.manage') ? C.list('purchase', opt) : []]), iv = res[0], py = res[1], pu = res[2].filter(function (x) { return x.status === 'received'; });
        var gstRates = {}; iv.forEach(function (x) { (x.data.lines || []).forEach(function (l) { var k = num(l.gst) + '%', a = num(l.qty) * num(l.price); gstRates[k] = gstRates[k] || [0, 0]; gstRates[k][0] += a; gstRates[k][1] += a * num(l.gst) / 100; }); });
        var mon = {}; iv.forEach(function (x) { var k = String(x.data.date || x.created_at).slice(0, 7); mon[k] = mon[k] || [0, 0]; mon[k][0] += num(x.amount); }); py.forEach(function (p) { var k = String(p.due_at).slice(0, 7); mon[k] = mon[k] || [0, 0]; mon[k][1] += num(p.amount); });
        body = '<div class="note g" style="margin-bottom:14px">' + C.ic('shield') + ' Hum accounting / GST filing nahi karte — har report <b>Download</b> karein ya <b>Download &amp; Share to Accountant</b> se seedha CA ko WhatsApp / Email karein.</div>' +
          '<div class="kpis">' + C.kpi('Sale (GST sahit)', money(C.sum(iv, 'amount')), iv.length + ' bill', 'gold') + C.kpi('Taxable', money(C.sum(iv, function (x) { return x.data.subtotal; }))) + C.kpi('GST (output)', money(C.sum(iv, function (x) { return x.data.gst_total; }))) + C.kpi('Payment mila', money(C.sum(py, 'amount'))) + (C.can('purchase.manage') ? C.kpi('Purchase (GST input)', money(C.sum(pu, function (x) { return x.data.gst_total; })), money(C.sum(pu, 'amount')) + ' kul') : '') + '</div>' +
          '<div class="grid g2"><div class="card"><div class="hd"><h3>GST rate ke hisab se</h3>' + C.reportBtns('GST summary', function () { return { head: ['GST rate', 'Taxable', 'GST', 'CGST', 'SGST'], rows: Object.keys(gstRates).map(function (k) { var v = gstRates[k]; return [k, C.r2(v[0]), C.r2(v[1]), C.r2(v[1] / 2), C.r2(v[1] / 2)]; }), text: 'GST summary' }; }) + '</div><div class="tw"><table class="t"><thead><tr><th>Rate</th><th class="r">Taxable</th><th class="r">GST</th></tr></thead><tbody>' + Object.keys(gstRates).map(function (k) { return '<tr><td>' + k + '</td><td class="r">' + money(gstRates[k][0]) + '</td><td class="r">' + money(gstRates[k][1]) + '</td></tr>'; }).join('') + '</tbody></table></div></div>' +
          '<div class="card"><div class="hd"><h3>Mahine ke hisab se</h3>' + C.reportBtns('Monthly summary', function () { return { head: ['Mahina', 'Sale', 'Payment mila'], rows: Object.keys(mon).sort().map(function (k) { return [k, C.r2(mon[k][0]), C.r2(mon[k][1])]; }), text: 'Monthly summary' }; }) + '</div><div class="tw"><table class="t"><thead><tr><th>Mahina</th><th class="r">Sale</th><th class="r">Mila</th></tr></thead><tbody>' + Object.keys(mon).sort().reverse().map(function (k) { return '<tr><td>' + k + '</td><td class="r">' + money(mon[k][0]) + '</td><td class="r">' + money(mon[k][1]) + '</td></tr>'; }).join('') + '</tbody></table></div></div></div>' +
          '<div class="card" style="margin-top:14px"><div class="hd"><h3>Item-wise sale (HSN)</h3>' + C.reportBtns('HSN summary', function () { var hs = {}; iv.forEach(function (x) { (x.data.lines || []).forEach(function (l) { var k = (l.hsn || '-') + '|' + num(l.gst); hs[k] = hs[k] || { hsn: l.hsn || '', name: l.name, gst: num(l.gst), qty: 0, val: 0 }; hs[k].qty += num(l.qty); hs[k].val += num(l.qty) * num(l.price); }); }); return { head: ['HSN', 'Item', 'GST %', 'Qty', 'Taxable', 'GST'], rows: Object.keys(hs).map(function (k) { var v = hs[k]; return [v.hsn, v.name, v.gst, v.qty, C.r2(v.val), C.r2(v.val * v.gst / 100)]; }), text: 'HSN summary' }; }) + '</div><p class="mute sm">GSTR-1 ke liye CA ko HSN-wise data.</p></div>';
        rep = function () { return { head: ['Bill No', 'Tareekh', 'Customer', 'GSTIN', 'Taxable', 'GST', 'Kul'], rows: iv.map(function (x) { return [x.ref, C.fd(x.data.date || x.created_at), x.title, (x.data.party || {}).gstin || '', num(x.data.subtotal), num(x.data.gst_total), num(x.amount)]; }), text: 'Sales register' }; };
      }
      $('#bl', el).innerHTML = body;
      if (rep) $('#rbx', el).innerHTML = C.reportBtns(tab === 'payments' ? 'Payments' : tab === 'purchase' ? 'Purchase' : tab === 'due' ? 'Baaki payment' : 'Sales register', rep);
      var ll = $('#ll', el); if (ll) C.filterList($('[data-q]', el), ll); else $('[data-q]', el).hidden = tab === 'reports';
      var nav = function (p) { C.go('#/billing' + C.qs(Object.assign({ tab: tab === 'bills' ? '' : tab, from: from, to: to }, p))); };
      el.addEventListener('click', function (e) { var t = e.target.closest('[data-tab]'); if (t) nav({ tab: t.getAttribute('data-tab') === 'bills' ? '' : t.getAttribute('data-tab') }); });
      $('[data-from]', el).onchange = function () { nav({ from: this.value }); }; $('[data-to]', el).onchange = function () { nav({ to: this.value }); };
      C.bind(el, { pay: function () { C.payForm({}).then(function (r) { if (r) C.render(); }); } });
      if (q.open) { C.setQuery({ open: '' }); try { var pr = await C.get(q.open); C.modal({ title: 'Payment ' + pr.ref, body: '<div class="list">' + C.payRow(pr) + '</div>', foot: '<button class="btn btn-o" data-close>Band</button><button class="btn btn-wa" id="rsh">' + C.ic('share') + ' Rasid bhejein</button>' }); $('#rsh').onclick = function () { C.receipt(pr, 'share'); }; } catch (e) {} }
    }
  });
})();
