/* Products & Projects — one inventory; products can be sent to Online Store Admin for review */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var STORE = { none: ['', ''], pending: ['Store review me', 'o'], published: ['Store par live', ''], rejected: ['Store ne lautaya', 'r'] };
  C.storePill = function (it) { var s = ((it.data || {}).store || {}).status || 'none', x = STORE[s]; return x && x[0] ? C.pill(x[0], x[1]) : ''; };
  C.UNITS = ['Nos', 'Set', 'kW', 'Watt', 'Mtr', 'Kg', 'Box', 'Pair', 'Ltr', 'Job'];

  C.itemForm = function (rec, type) {
    rec = rec || { data: { type: type || 'product' } }; var d = C.clone(rec.data || {}), isNew = !rec.id, proj = (d.type || 'product') === 'project', cost = C.can('items.cost');
    d.proj_items = d.proj_items || []; d.images = d.images || [];
    return new Promise(function (res) {
      var body = '<form id="itf" class="stack"><div class="fg">' +
        C.f('Item Title <span class="o">(upar chhota heading, jaise "Solar Panel")</span>', C.inp('title', d.title, 'maxlength="80"')) + C.f((proj ? 'Project ka naam' : 'Item Name') + ' *', C.inp('name', d.name || rec.title, 'maxlength="160"')) +
        C.f(proj ? 'Project ki kul keemat (₹, bina GST) *' : 'Bechne ka rate (₹, bina GST) *', C.inp('price', d.price, 'inputmode="decimal"')) + C.f('GST %', C.sel('gst', [['0', '0%'], ['5', '5%'], ['12', '12%'], ['18', '18%'], ['28', '28%']], String(d.gst != null ? d.gst : (proj ? '12' : '18')))) +
        (proj ? '' : C.f('MRP (₹)', C.inp('mrp', d.mrp, 'inputmode="decimal"')) + C.f('Stock <span class="o">(khaali = hisab nahi)</span>', C.inp('stock', d.stock, 'inputmode="decimal"'))) +
        C.f('HSN / SAC', C.inp('hsn', d.hsn, 'maxlength="10"')) + C.f('Unit', C.sel('unit', C.UNITS, d.unit || (proj ? 'Set' : 'Nos'))) +
        (proj ? '' : C.f('Brand', C.inp('brand', d.brand)) + C.f('Category', C.inp('category', d.category, 'list="cats"')) + C.f('SKU / Code', C.inp('sku', d.sku))) +
        (cost ? C.f('Kharid rate (₹) <span class="o">— sirf aapko dikhega</span>', C.inp('cost_price', d.cost_price, 'inputmode="decimal"')) + C.f('Minimum rate (₹) <span class="o">— isse kam me quotation nahi banegi</span>', C.inp('min_price', d.min_price, 'inputmode="decimal"')) : '') +
        C.f('Description <span class="o">(har line alag point — bill me 1. 2. 3. banke chhapega)</span>', C.ta('desc', d.desc, 'rows="5" placeholder="540Wp Mono PERC Bifacial&#10;25 saal performance warranty&#10;BIS / ALMM approved"'), 'full') +
        C.f('More Info <span class="o">(chhota note, italic me)</span>', C.ta('more', d.more, 'rows="2"'), 'full') + '</div>' +
        (proj ? '<div class="sec-t">Project me kya-kya shamil hai</div><div id="pis" class="dl proj"></div><div class="row wrap"><button type="button" class="btn btn-o btn-sm" data-addpi>' + C.ic('box') + ' Product se jodein</button><button type="button" class="btn btn-o btn-sm" data-addcustom>' + C.ic('plus') + ' Apni line likhein</button></div><label class="ck"><input type="checkbox" name="show_prices"' + (d.show_prices ? ' checked' : '') + '> Quotation me andar wale items ka rate bhi dikhayein <span class="hint">(band = sirf kul keemat dikhegi)</span></label>' :
          '<div class="sec-t">Photos (Online Store ke liye, max 3)</div><div class="row wrap" id="imgs"></div><input type="file" accept="image/*" id="imgf" hidden multiple>' +
          '<div class="sec-t">Online Store ke liye</div><div class="fg">' + C.f('Store par chhoti line (tagline)', '<input class="inp" name="s_tagline" value="' + esc((d.store || {}).tagline || '') + '" maxlength="120">') + C.f('Store par offer price (₹, GST sahit)', '<input class="inp" name="s_offer" value="' + esc((d.store || {}).offer || '') + '" inputmode="decimal">') + '</div>') +
        '<label class="ck"><input type="checkbox" name="inactive"' + (rec.status === 'inactive' ? ' checked' : '') + '> Band karein (quotation me nahi dikhega)</label></form><datalist id="cats">' + ['Solar Panel', 'Inverter', 'Battery', 'Structure', 'Cable', 'Accessories', 'Street Light', 'Water Heater', 'Pump'].map(function (x) { return '<option value="' + x + '">'; }).join('') + '</datalist>';
      var m = C.modal({ title: (isNew ? 'Naya ' : '') + (proj ? 'Project' : 'Product') + (isNew ? '' : ' badlein'), size: 'wide', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>', onClose: function () { res(null); } });
      var f = $('#itf', m.el);
      function drawPi() {
        var el = $('#pis', m.el); if (!el) return;
        el.innerHTML = d.proj_items.length ? d.proj_items.map(function (x, i) { return '<div class="pi"><span class="grow"><input class="inp" style="min-height:34px" data-pin="' + i + '" value="' + esc((x.title ? x.title + ' – ' : '') + x.name) + '"></span><input class="inp" style="width:70px;min-height:34px" data-piq="' + i + '" value="' + esc(x.qty) + '" inputmode="decimal" title="Qty"><input class="inp" style="width:100px;min-height:34px" data-pip="' + i + '" value="' + esc(x.price || '') + '" inputmode="decimal" placeholder="Rate" title="Rate (optional)"><button type="button" class="btn btn-g btn-icon btn-sm" data-pid="' + i + '">' + C.ic('x') + '</button></div>'; }).join('') + '<div class="hint" style="margin-top:6px">Andar wale items ka rate sirf hisab ke liye — customer ko tabhi dikhega jab neeche tick ho.</div>' : '<p class="mute sm">Abhi kuch nahi jodha — panel, inverter, structure, wiring, installation…</p>';
      }
      function drawImg() {
        var el = $('#imgs', m.el); if (!el) return;
        el.innerHTML = d.images.map(function (u, i) { return '<div style="position:relative"><img src="' + esc(u) + '" style="width:84px;height:84px;object-fit:cover;border-radius:10px;border:1px solid var(--line)"><button type="button" class="btn btn-r btn-icon btn-sm" style="position:absolute;top:-8px;right:-8px" data-imd="' + i + '">' + C.ic('x') + '</button></div>'; }).join('') + (d.images.length < 3 ? '<button type="button" class="btn btn-o" style="width:84px;height:84px;flex-direction:column" data-imadd>' + C.ic('image') + '<span class="xs">Photo</span></button>' : '');
      }
      drawPi(); drawImg();
      m.el.addEventListener('input', function (e) {
        var t = e.target, i;
        if ((i = t.getAttribute('data-pin')) != null) { d.proj_items[i].name = t.value; d.proj_items[i].title = ''; }
        if ((i = t.getAttribute('data-piq')) != null) d.proj_items[i].qty = t.value;
        if ((i = t.getAttribute('data-pip')) != null) d.proj_items[i].price = t.value;
      });
      m.el.addEventListener('click', async function (e) {
        var b;
        if ((b = e.target.closest('[data-pid]'))) { d.proj_items.splice(+b.getAttribute('data-pid'), 1); drawPi(); }
        else if (e.target.closest('[data-addcustom]')) { d.proj_items.push({ name: '', qty: 1 }); drawPi(); var ins = $$('[data-pin]', m.el); ins[ins.length - 1].focus(); }
        else if (e.target.closest('[data-addpi]')) { var its = await C.itemPick('product', true); its.forEach(function (it) { d.proj_items.push({ item_id: it.id, title: it.data.title || '', name: it.data.name || it.title, desc: it.data.desc || '', qty: 1, price: it.data.price || '' }); }); drawPi(); }
        else if ((b = e.target.closest('[data-imd]'))) { d.images.splice(+b.getAttribute('data-imd'), 1); drawImg(); }
        else if (e.target.closest('[data-imadd]')) $('#imgf', m.el).click();
      });
      var imf = $('#imgf', m.el); if (imf) imf.onchange = async function () { for (var i = 0; i < imf.files.length && d.images.length < 3; i++) { try { var c = await C.compress(imf.files[i], 700, 0.72); d.images.push(await C.toDataUrl(c)); } catch (e) { C.toast(e.message, true); } } imf.value = ''; drawImg(); };
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (!C.need(f, ['name', 'price'])) return;
        var data = Object.assign(d, { type: proj ? 'project' : 'product', title: o.title, name: o.name, price: C.r2(o.price), gst: num(o.gst), hsn: o.hsn, unit: o.unit, desc: o.desc, more: o.more });
        if (!proj) { data.mrp = o.mrp; data.brand = o.brand; data.category = o.category; data.sku = o.sku; if (o.stock === '') delete data.stock; else data.stock = num(o.stock); data.store = Object.assign({}, data.store || {}, { tagline: o.s_tagline, offer: o.s_offer }); delete data.proj_items; }
        else { data.proj_items = d.proj_items.filter(function (x) { return String(x.name || '').trim(); }); data.show_prices = !!o.show_prices; delete data.stock; }
        if (cost) { data.cost_price = o.cost_price; data.min_price = o.min_price; }
        try { var r = await C.save('item', rec.id, data, { status: o.inactive ? 'inactive' : 'active' }); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  };

  /* pick products / projects (multi-select) */
  C.itemPick = function (type, multi) {
    return new Promise(async function (res) {
      var all = [], tp = type || 'product', chosen = {};
      var m = C.modal({ title: multi ? 'Items chunein' : 'Item chunein', size: 'wide', body: '<div class="bar">' + (type ? '' : C.chips([['product', 'Products'], ['project', 'Projects']], tp, 'tp')) + '<input class="inp" id="iq" type="search" placeholder="Item khojein" style="max-width:none;flex:1"></div><div class="list" id="il" style="max-height:55vh;overflow:auto">' + C.loading() + '</div>', foot: multi ? '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Jodein</button>' : false, onClose: function () { res(multi ? [] : null); } });
      function draw() {
        var q = $('#iq', m.el).value.toLowerCase(), list = all.filter(function (x) { return (x.data.type || 'product') === tp && x.status !== 'inactive' && (!q || (x.title + ' ' + (x.data.title || '') + ' ' + (x.data.brand || '') + ' ' + (x.data.sku || '')).toLowerCase().indexOf(q) >= 0); });
        $('#il', m.el).innerHTML = list.length ? list.map(function (x) { return '<label class="li click" style="cursor:pointer"' + (multi ? '' : ' data-one="' + x.id + '"') + '>' + (multi ? '<input type="checkbox" data-ck="' + x.id + '"' + (chosen[x.id] ? ' checked' : '') + '>' : '') + '<span class="av ' + (tp === 'project' ? 'v' : '') + '">' + C.ic(tp === 'project' ? 'plant' : 'box') + '</span><span class="grow"><span class="t">' + (x.data.title ? '<span class="xs mute" style="text-transform:uppercase">' + esc(x.data.title) + '</span>' : '') + esc(x.title) + '</span><span class="m">' + (x.data.stock != null ? '<span>Stock: ' + esc(x.data.stock) + '</span>' : '') + '<span>GST ' + esc(x.data.gst || 0) + '%</span>' + (C.lines(x.data.desc)[0] ? '<span class="ellip">' + esc(C.lines(x.data.desc)[0]) + '</span>' : '') + '</span></span><span class="amt">' + money(x.data.price) + '</span>' + (multi ? '' : '<button type="button" class="btn btn-p btn-sm" data-one="' + x.id + '">Chunein</button>') + '</label>'; }).join('') : C.empty('box', 'Koi item nahi', C.can('items.create') ? 'Products & Projects me jodein' : '');
      }
      try { all = await C.list('item', { limit: 3000 }); } catch (e) { C.toast(e.message, true); }
      draw(); $('#iq', m.el).addEventListener('input', draw);
      m.el.addEventListener('click', function (e) {
        var c = e.target.closest('[data-tp]'); if (c) { tp = c.getAttribute('data-tp'); $$('[data-tp]', m.el).forEach(function (x) { x.classList.toggle('on', x === c); }); draw(); return; }
        var one = e.target.closest('[data-one]'); if (one) { e.preventDefault(); var it = all.find(function (x) { return String(x.id) === one.getAttribute('data-one'); }); m.el.remove(); document.documentElement.style.overflow = ''; res(it); }
      });
      m.el.addEventListener('change', function (e) { var k = e.target.closest('[data-ck]'); if (k) { if (k.checked) chosen[k.getAttribute('data-ck')] = 1; else delete chosen[k.getAttribute('data-ck')]; } });
      var ok = $('[data-ok]', m.el); if (ok) ok.onclick = function () { var out = all.filter(function (x) { return chosen[x.id]; }); m.el.remove(); document.documentElement.style.overflow = ''; res(out); };
    });
  };

  function importItems(done) {
    var m = C.modal({ title: 'Products Excel se jodein', body: '<div class="note g" style="margin-bottom:12px">Columns (pehli line heading): <b>Title, Name, Price, GST, Stock, HSN, Unit, MRP, Brand, Category, Description</b>. Description me har point nayi line me ya "|" se alag.</div><input type="file" class="inp" id="xf" accept=".xlsx,.csv"><p class="sm b" id="xp" style="margin-top:8px"></p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok disabled>Import</button>' }), rows = [];
    $('#xf', m.el).onchange = async function () {
      try {
        var data = await C.readSheet(this.files[0]), head = (data[0] || []).map(function (x) { return String(x || '').toLowerCase().trim(); }), ix = function (re) { return head.findIndex(function (h) { return re.test(h); }); };
        var c = { title: ix(/^title|heading/), name: ix(/^name|item name|naam/), price: ix(/price|rate/), gst: ix(/gst|tax/), stock: ix(/stock|qty/), hsn: ix(/hsn|sac/), unit: ix(/unit/), mrp: ix(/mrp/), brand: ix(/brand/), category: ix(/categ/), desc: ix(/desc|detail/) };
        if (c.name < 0 || c.price < 0) throw new Error('Name aur Price column zaroori hain');
        rows = data.slice(1).filter(function (r) { return String(r[c.name] || '').trim(); }).map(function (r) { var g = function (k) { return c[k] >= 0 ? String(r[c[k]] == null ? '' : r[c[k]]).trim() : ''; }; var o = { type: 'product', title: g('title'), name: g('name'), price: num(g('price')), gst: num(g('gst') || 18), hsn: g('hsn'), unit: g('unit') || 'Nos', mrp: g('mrp'), brand: g('brand'), category: g('category'), desc: g('desc').replace(/\s*\|\s*/g, '\n') }; if (g('stock') !== '') o.stock = num(g('stock')); return o; });
        $('#xp', m.el).textContent = rows.length + ' products milenge'; $('[data-ok]', m.el).disabled = !rows.length;
      } catch (e) { C.toast(e.message || 'File padh nahi paye', true); }
    };
    $('[data-ok]', m.el).onclick = async function () { var ok = 0; C.busy(true); for (var i = 0; i < rows.length; i++) { try { await C.call('crm_save', { kind: 'item', data: rows[i] }); ok++; } catch (e) { C.toast(rows[i].name + ': ' + e.message, true); } } C.busy(false); m.close(); C.toast(ok + ' products jud gaye ✔'); done(); };
  }

  C.mod('items', {
    title: 'Products & Projects',
    allowed: function () { return C.can('items.view'); },
    render: async function (el, params, q) {
      var tp = q.type || 'product', st = q.store || '', all = await C.list('item', { limit: 3000 }), cost = C.can('items.cost');
      var list = all.filter(function (x) { return (x.data.type || 'product') === tp && (!st || ((x.data.store || {}).status || 'none') === st); });
      var nP = all.filter(function (x) { return (x.data.type || 'product') === 'product'; }).length;
      var h = '<div class="ph"><div><h1>Products &amp; Projects</h1><p>Ek hi inventory — quotation, bill aur Online Store sab yahin se.</p></div><div class="row">' +
        (C.can('items.view') ? C.reportBtns('Stock', function () { return { head: ['Prakar', 'Title', 'Naam', 'Rate', 'GST', 'MRP', 'Stock', 'Unit', 'HSN', 'Brand', 'Category'].concat(cost ? ['Kharid rate', 'Stock value'] : []), rows: all.map(function (x) { var d = x.data; return [d.type || 'product', d.title || '', x.title, num(d.price), num(d.gst), d.mrp || '', d.stock != null ? d.stock : '', d.unit || '', d.hsn || '', d.brand || '', d.category || ''].concat(cost ? [num(d.cost_price), d.stock != null ? num(d.stock) * num(d.cost_price || d.price) : ''] : []); }) }; }) : '') +
        (C.can('items.create') ? '<button class="btn btn-o" data-act="imp">' + C.ic('upload') + ' Excel</button><button class="btn btn-p" data-act="add">' + C.ic('plus') + ' ' + (tp === 'project' ? 'Naya project' : 'Naya product') + '</button>' : '') + '</div></div>';
      h += '<div class="tabs"><button data-tp="product" class="' + (tp === 'product' ? 'on' : '') + '">Products (' + nP + ')</button><button data-tp="project" class="' + (tp === 'project' ? 'on' : '') + '">Projects (' + (all.length - nP) + ')</button></div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Item khojein">' + (tp === 'product' ? C.chips([['', 'Sab'], ['none', 'Sirf CRM'], ['pending', 'Store review me'], ['published', 'Store par live'], ['rejected', 'Lautaye']], st, 'store') : '') + '</div>';
      if (tp === 'product' && C.can('items.to_store')) h += '<div class="note g" style="margin-bottom:12px">' + C.ic('shield') + ' Product seedha Online Store par live nahi hota: <b>"Online Store ko bhejein"</b> → Store Admin Google / Meta niyam check karega → wahan se Publish.</div>';
      h += list.length ? '<div class="list" id="itl">' + list.map(function (x) {
        var d = x.data, low = d.stock != null && num(d.stock) <= 0;
        return '<div class="li click" data-act="edit" data-id="' + x.id + '">' + (d.images && d.images[0] ? '<img src="' + esc(d.images[0]) + '" alt="" style="width:44px;height:44px;border-radius:12px;object-fit:cover;flex:none">' : '<span class="av ' + (tp === 'project' ? 'v' : '') + '">' + C.ic(tp === 'project' ? 'plant' : 'box') + '</span>') +
          '<span class="grow"><span class="t">' + (d.title ? '<span class="xs mute" style="text-transform:uppercase;letter-spacing:.04em">' + esc(d.title) + '</span>' : '') + esc(x.title) + (x.status === 'inactive' ? C.pill('Band', 'g') : '') + C.storePill(x) + '</span><span class="m">' + (tp === 'project' ? '<span>' + (d.proj_items || []).length + ' cheezein shamil</span>' : '') + (d.stock != null ? '<span' + (low ? ' style="color:var(--red);font-weight:700"' : '') + '>Stock: ' + esc(d.stock) + ' ' + esc(d.unit || '') + '</span>' : '') + '<span>GST ' + esc(d.gst || 0) + '%</span>' + (d.hsn ? '<span>HSN ' + esc(d.hsn) + '</span>' : '') + (cost && num(d.min_price) ? '<span>Min ' + money(d.min_price) + '</span>' : '') + (d.store && d.store.status === 'rejected' && d.store.note ? '<span style="color:var(--red)">Store Admin: ' + esc(d.store.note) + '</span>' : '') + (d.store && d.store.status === 'published' && d.store.store_id && C.storeUrl() ? '<span><a href="' + esc(C.storeUrl().replace(/\/+$/, '') + '/?p=' + encodeURIComponent(d.store.store_id)) + '" target="_blank" rel="noopener" style="color:var(--leaf-d);font-weight:700">Store par dekhein ↗</a></span>' : '') + '</span></span>' +
          '<span class="amt">' + money(d.price) + (cost && num(d.cost_price) ? '<small>Kharid ' + money(d.cost_price) + '</small>' : '') + '</span><span class="acts">' + (tp === 'product' && C.can('items.to_store') && ['pending'].indexOf((d.store || {}).status) < 0 ? '<button class="btn btn-o btn-sm" data-act="store" data-id="' + x.id + '" style="display:inline-flex" title="Online Store Admin ko bhejein">' + C.ic('store') + '<span class="desk-only">Store ko bhejein</span></button>' : '') + (C.can('items.delete') ? '<button class="btn btn-g btn-icon btn-sm" data-act="del" data-id="' + x.id + '" aria-label="Hatayein">' + C.ic('trash') + '</button>' : '') + '</span></div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('box', 'Koi item nahi', C.can('items.create') ? (tp === 'project' ? 'Project = poora package (jaise 3kW On-grid) — andar ke items ka rate customer ko nahi dikhta' : '"Naya product" dabayein') : '') + '</div>';
      el.innerHTML = h;
      var itl = $('#itl', el); if (itl) C.filterList($('[data-q]', el), itl);
      el.addEventListener('click', function (e) { var t = e.target.closest('[data-tp]'); if (t) C.go('#/items' + C.qs({ type: t.getAttribute('data-tp') === 'product' ? '' : 'project' })); var s = e.target.closest('[data-store]'); if (s) C.go('#/items' + C.qs({ store: s.getAttribute('data-store') })); });
      C.bind(el, {
        add: function () { C.itemForm(null, tp).then(function (r) { if (r) C.render(); }); },
        imp: function () { importItems(function () { C.render(); }); },
        edit: function (id, a, e) { if (e.target.closest('.acts')) return; var x = all.find(function (z) { return String(z.id) === id; }); if (!C.can('items.edit')) return itemInfo(x); C.itemForm(x).then(function (r) { if (r) C.render(); }); },
        store: async function (id) {
          var x = all.find(function (z) { return String(z.id) === id; });
          if (!(x.data.images || []).length && !(await C.confirm('Is product me photo nahi hai — Store par photo zaroori hoti hai. Phir bhi bhejein?', 'Haan, bhejein'))) return;
          if (await C.confirm('"' + x.title + '" Online Store Admin ko review ke liye bhejein? Admin check karke Publish karega.', 'Bhejein')) { try { await C.run('crm_to_store', { id: id }, 'Store Admin ko bhej diya ✔'); C.render(); } catch (e) {} }
        },
        del: async function (id) { var x = all.find(function (z) { return String(z.id) === id; }); if (await C.delWithReason(x, x.title)) C.render(); }
      });
      if (q.open) { var it = all.find(function (z) { return String(z.id) === q.open; }); if (it) setTimeout(function () { C.setQuery({ open: '' }); (C.can('items.edit') ? C.itemForm(it) : itemInfo(it)); }, 30); }
    }
  });
  function itemInfo(x) {
    var d = x.data;
    C.modal({ title: x.title, body: (d.images && d.images.length ? '<div class="row" style="margin-bottom:12px">' + d.images.map(function (u) { return '<img src="' + esc(u) + '" style="width:110px;height:110px;object-fit:cover;border-radius:12px">'; }).join('') + '</div>' : '') + '<div class="row" style="margin-bottom:10px"><b style="font-size:22px">' + money(d.price) + '</b><span class="mute">+ GST ' + esc(d.gst || 0) + '%</span>' + (d.stock != null ? C.pill('Stock: ' + d.stock) : '') + '</div>' + (C.lines(d.desc).length ? '<ol style="margin:0;padding-left:20px">' + C.lines(d.desc).map(function (l) { return '<li>' + esc(l) + '</li>'; }).join('') + '</ol>' : '') + ((d.proj_items || []).length ? '<div class="sec-t">Shamil</div><ul style="margin:0;padding-left:20px">' + d.proj_items.map(function (p) { return '<li>' + esc((p.title ? p.title + ' – ' : '') + p.name) + ' × ' + esc(p.qty) + '</li>'; }).join('') + '</ul>' : '') + (d.more ? '<p class="mute" style="margin-top:10px"><i>' + esc(d.more) + '</i></p>' : '') });
  }
})();
