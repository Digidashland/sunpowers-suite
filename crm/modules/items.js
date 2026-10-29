/* Products & Templates — one inventory; products can be sent to Online Store Admin for review */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc, money = C.money, num = C.num;
  var STORE = { none: ['', ''], pending: ['Store review me', 'o'], published: ['Store par live', ''], rejected: ['Store ne lautaya', 'r'] };
  C.storePill = function (it) { var s = ((it.data || {}).store || {}).status || 'none', x = STORE[s]; return x && x[0] ? C.pill(x[0], x[1]) : ''; };
  C.UNITS = ['Nos', 'Set', 'kW', 'Watt', 'Mtr', 'Kg', 'Box', 'Pair', 'Ltr', 'Job'];

  C.CAT_DEF = { project: ['Residential', 'Commercial', 'Industrial', 'VFD / Pump'] };
  /* Round 13: catalog (11 categories + sub-categories) — data file is loaded only when needed */
  C.catLoad = function () {
    if (window.CRM_CAT) return Promise.resolve();
    if (C._catP) return C._catP;
    C._catP = new Promise(function (res) { var sc = document.createElement('script'); sc.src = 'modules/catalog-data.js?v=3'; sc.onload = res; sc.onerror = res; document.head.appendChild(sc); });
    return C._catP;
  };
  C.catalog = async function (force) {
    if (C.cache.catalog && !force) return C.cache.catalog;
    await C.catLoad(); var cats = (window.CRM_CAT || {}).cats || [];
    try { var r = await C.call('crm_catalog_get', {}); if (r && r.catalog) cats = r.catalog; } catch (e) {}
    C.cache.catalog = cats; return cats;
  };
  C.itemCats = async function (type) {
    var all = C.cache.items; if (!all) { try { all = await C.list('item', { limit: 3000 }); } catch (e) { all = []; } }
    var set = {}; if (type === 'project') (C.CAT_DEF.project || []).forEach(function (c) { set[c] = 1; }); else (await C.catalog()).forEach(function (c) { set[c.name] = 1; });
    all.forEach(function (x) { if ((x.data.type || 'product') === type) { if (x.data.category) set[String(x.data.category).trim()] = 1; } });
    var cat = type === 'project' ? null : await C.catalog(), order = cat ? cat.map(function (c) { return c.name; }) : [];
    return Object.keys(set).filter(Boolean).sort(function (a, b) { var ia = order.indexOf(a), ib = order.indexOf(b); if (ia >= 0 || ib >= 0) return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib); return a.localeCompare(b); });
  };
  C.itemInCat = function (x, cat) { return (x.data || {}).category === cat; };
  /* Round 63: ek item = ek baar bharna. Sab jagah (quotation, bill, Online Store, website) isi se chalta hai.
     Core fields hamesha ek jaise; specification sirf chuni hui category ke mukhya fields (baaki "Aur technical details" me). */
  var LEGACY_W = ['Product warranty (yrs)', 'Warranty (yrs)', 'Warranty'];
  C.itemForm = async function (rec, type) {
    rec = rec || { data: { type: type || 'product' } }; var d = C.clone(rec.data || {}), isNew = !rec.id, proj = (d.type || 'product') === 'project', cost = C.can('items.cost');
    d.proj_items = d.proj_items || [];
    var CATS = proj ? [] : await C.catalog(), canCat = C.can('items.categories') && !proj, cats = await C.itemCats(proj ? 'project' : 'product'); if (d.category && cats.indexOf(d.category) < 0) cats.push(d.category);
    await C.catLoad();
    /* purana data ek hi jagah le aao: warranty (specification me alag thi), "More Info" (description me) */
    var specVals = {}; Object.keys(d.specs || {}).forEach(function (k) { if (k.charAt(0) !== '_') specVals[k] = d.specs[k]; });
    LEGACY_W.forEach(function (k) { if (specVals[k] != null) { if (!String(d.warranty || '').trim() && String(specVals[k]).trim()) d.warranty = /^[0-9.]+$/.test(String(specVals[k]).trim()) ? specVals[k] + ' yrs' : specVals[k]; delete specVals[k]; } });
    if (String(d.more || '').trim() && String(d.desc || '').indexOf(String(d.more).trim()) < 0) d.desc = (d.desc ? String(d.desc).replace(/\s+$/, '') + '\n' : '') + String(d.more).trim();
    return new Promise(function (res) {
      var body = '<form id="itf" class="stack">' + (!isNew && d.sku ? '<div class="hint">SKU <b style="letter-spacing:.03em">' + esc(d.sku) + '</b> (apne-aap banta hai)</div>' : '') + '<div class="fg">' +
        C.f('Category *', '<select class="inp" name="category" id="itCat">' + C.opts(cats, d.category || '', '— Pehle category chunein —') + (canCat ? '<option value="__new">+ Nayi category banayein</option>' : '') + '</select><input class="inp" name="category_new" id="itCatN" placeholder="Nayi category ka naam" maxlength="60" hidden style="margin-top:8px">') +
        (proj ? '<div class="f"></div>' : C.f('Sub-category', '<select class="inp" name="subcategory" id="itSub"></select><input class="inp" name="sub_new" id="itSubN" placeholder="Nayi sub-category ka naam" maxlength="60" hidden style="margin-top:8px">')) +
        C.f((proj ? 'Template ka naam' : 'Item ka naam') + ' *', C.inp('name', d.name || rec.title, 'maxlength="160"'), 'full') +
        (proj ? '' : C.f('Brand', C.inp('brand', d.brand, 'list="brandl" autocomplete="off"') + '<datalist id="brandl"></datalist>') + C.f('Model / Part no. <span class="o">(supplier ka code)</span>', C.inp('mpn', d.mpn, 'maxlength="60"'))) +
        C.f(proj ? 'Template ki kul keemat (₹, bina GST) *' : 'Bechne ka rate (₹, bina GST) *', C.inp('price', d.price, 'inputmode="decimal"')) + C.f('GST %', C.sel('gst', [['0', '0%'], ['5', '5%'], ['12', '12%'], ['18', '18%'], ['28', '28%']], String(d.gst != null ? d.gst : (proj ? '12' : '18')))) +
        C.f('HSN / SAC <span class="o">(category se apne-aap)</span>', C.inp('hsn', d.hsn, 'maxlength="10"')) + C.f('Unit', C.sel('unit', C.UNITS, d.unit || (proj ? 'Set' : 'Nos'))) +
        (cost && !proj ? C.f('Kharid rate / Purchase price (₹) *', C.inp('cost_price', d.cost_price, 'inputmode="decimal" placeholder="jis rate par khareeda"')) : '') +
        (cost ? C.f('Minimum rate (₹) <span class="o">— isse kam me quotation nahi banegi</span>', C.inp('min_price', d.min_price, 'inputmode="decimal"')) : '') +
        (proj ? '' : C.f('Stock <span class="o">(khaali = hisab nahi)</span>', C.inp('stock', d.stock, 'inputmode="decimal"')) + C.f('Warranty <span class="o">(jaise 12 yrs)</span>', C.inp('warranty', d.warranty, 'maxlength="60"')) + C.f('MRP (₹, GST sahit) <span class="o">(optional — kata hua rate dikhane ke liye)</span>', C.inp('mrp', d.mrp, 'inputmode="decimal"')) + C.f('Weight (kg) <span class="o">(delivery charge ke liye)</span>', C.inp('weight', d.weight, 'inputmode="decimal" maxlength="6"'))) +
        (proj ? C.f('System size (kW)', C.inp('kw', d.kw, 'inputmode="decimal" maxlength="6"')) + C.f('System type <span class="o">(subsidy sirf On-Grid / Hybrid par)</span>', C.sel('sys', [['on', 'On-Grid'], ['hy', 'Hybrid (battery + grid)'], ['off', 'Off-Grid (subsidy nahi)']], d.sys || 'on')) : '') +
        '</div>' + (proj ? '' : '<div class="sec-t">Specification <span class="o">(category ke hisaab se mukhya fields)</span></div><div class="fg" id="specs"></div><details class="moreopt" id="specMoreD" style="margin-top:8px" hidden><summary style="cursor:pointer;font-weight:700;padding:6px 0">Aur technical details <span class="o">(optional)</span></summary><div class="fg" id="specsMore" style="margin-top:8px"></div></details>') +
        '<div class="fg" style="margin-top:12px">' + C.f((proj ? 'Package ki jankari' : 'Khaas baatein') + ' <span class="o">(' + (proj ? 'optional' : '3–5 chhote point, har line alag — online page par dikhte hain') + ')</span>', C.ta('desc', d.desc, 'rows="4" placeholder="' + (proj ? 'Is package me kya milta hai, kis ghar ke liye' : '25 saal performance warranty&#10;BIS / ALMM approved&#10;Bifacial — peeche se bhi bijli') + '"'), 'full') + '</div>' +
        (proj ? '<div class="sec-t">Template me kya-kya shamil hai</div><div id="pis" class="dl proj"></div><div class="row wrap"><button type="button" class="btn btn-o btn-sm" data-addpi>' + C.ic('box') + ' Product se jodein</button><button type="button" class="btn btn-o btn-sm" data-addcustom>' + C.ic('plus') + ' Apni line likhein</button></div><div class="row wrap" style="margin-top:6px"><button type="button" class="btn btn-o btn-sm" data-ptotal>' + C.ic('check') + ' Items ka total ➜ kul keemat</button><span class="hint" id="ptotH"></span></div><label class="ck"><input type="checkbox" name="show_prices"' + (d.show_prices ? ' checked' : '') + '> Quotation me andar wale items ka rate bhi dikhayein <span class="hint">(band = sirf kul keemat dikhegi)</span></label>' : '') +
        '<div class="sec-t">Online Store ke liye</div><div class="fg">' + C.f('Card par chhoti line <span class="o">(optional — khaali ho to brand dikhega)</span>', '<input class="inp" name="s_tagline" value="' + esc((d.store || {}).tagline || '') + '" maxlength="120">', 'full') + '</div>' +
        '<div class="hint">Photo / video, kahan dikhana hai (section), delivery aur subsidy — Store Admin me. Naam, rate, brand, model, warranty, baatein aur specification wahan apne-aap aate hain — dobara nahi bharna.</div>' +
        '<label class="ck"><input type="checkbox" name="inactive"' + (rec.status === 'inactive' ? ' checked' : '') + '> Band karein (quotation me nahi dikhega)</label></form>';
      var m = C.modal({ title: (isNew ? 'Naya ' : '') + (proj ? 'Template' : 'Product') + (isNew ? '' : ' badlein'), size: 'wide', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + (proj ? ' Save project' : ' Save') + '</button>', onClose: function () { res(null); } });
      var f = $('#itf', m.el), cs = $('#itCat', m.el), cn = $('#itCatN', m.el);
      var sb = $('#itSub', m.el), sn = $('#itSubN', m.el), spBox = $('#specs', m.el), spMore = $('#specsMore', m.el), SPD = window.CRM_CAT || {}, autoHsn = isNew ? '' : (d.hsn || '');
      function curCat() { return CATS.filter(function (c) { return c.name === cs.value; })[0] || null; }
      function drawSub() {
        if (!sb) return; var c = curCat(), subs = c ? c.subs.map(function (x) { return x.name; }) : [], cur = sb.value || d.subcategory || '';
        if (cur && subs.indexOf(cur) < 0 && cs.value === (d.category || '')) subs.push(cur);
        sb.innerHTML = C.opts(subs, cur, subs.length || cs.value === '__new' ? '— Sub-category chunein —' : '— (is category me sub-category nahi) —') + (canCat && c ? '<option value="__new">+ Nayi sub-category banayein</option>' : '');
        sb.value = subs.indexOf(cur) >= 0 ? cur : ''; sn.hidden = true;
      }
      /* category ke mukhya fields pehle; baaki purane fields "Aur technical details" me — kuch delete nahi hota */
      function specFields() {
        var c = curCat(), code = c ? c.code : '', known = !!cs.value && cs.value !== '__new', own = (SPD.specs || {})[code];
        var all = (own || (known ? SPD.generic_spec : null) || []).filter(function (k) { return LEGACY_W.indexOf(k) < 0; }), key = ((SPD.key || {})[code] || (known && !own ? SPD.generic_key : null) || []).filter(function (k) { return all.indexOf(k) >= 0; });
        var more = all.filter(function (k) { return key.indexOf(k) < 0; });
        Object.keys(specVals).forEach(function (k) { if (all.indexOf(k) < 0 && String(specVals[k] == null ? '' : specVals[k]).trim()) more.push(k); });
        return { key: key, more: more, known: known };
      }
      function readSpecs() { $$('[data-spec]', f).forEach(function (e) { specVals[e.getAttribute('data-spec')] = e.value; }); }
      function specIn(k) { return C.f(esc(k), '<input class="inp" data-spec="' + esc(k) + '" value="' + esc(specVals[k] == null ? '' : specVals[k]) + '" maxlength="120">'); }
      function drawSpecs() {
        if (!spBox) return; readSpecs(); var sf = specFields();
        spBox.innerHTML = sf.key.length ? sf.key.map(specIn).join('') : (sf.known ? '' : '<p class="mute sm">Pehle category chunein — us category ke specification columns yahan aayenge.</p>');
        var md = $('#specMoreD', m.el); spMore.innerHTML = sf.more.map(specIn).join(''); md.hidden = !sf.more.length;
        var code = (curCat() || {}).code, bl = $('#brandl', m.el); if (bl) bl.innerHTML = ((SPD.brands || {})[code] || []).map(function (b) { return '<option value="' + esc(b) + '">'; }).join('');
        if (md && !md.hidden) { var filled = $$('[data-spec]', spMore).some(function (e) { return e.value.trim(); }); if (filled && !md._seen) { md.open = true; md._seen = 1; } }
      }
      function catDefaults() {
        var c = curCat(), df = c && (SPD.def || {})[c.code]; if (!df) return;
        var h = $('input[name=hsn]', f), g = $('select[name=gst]', f);
        if (h && (!h.value.trim() || h.value.trim() === autoHsn)) { h.value = df[1]; autoHsn = df[1]; }
        if (isNew && g && !g._touched) g.value = String(df[0]);
      }
      var gsel = $('select[name=gst]', f); if (gsel) gsel.addEventListener('change', function () { gsel._touched = true; });
      if (sb) { drawSub(); sb.addEventListener('change', function () { sn.hidden = sb.value !== '__new'; if (!sn.hidden) sn.focus(); }); }
      drawSpecs();
      cs.addEventListener('change', function () { cn.hidden = cs.value !== '__new'; if (!cn.hidden) cn.focus(); cs.classList.remove('bad'); if (sb) { sb.value = ''; drawSub(); } drawSpecs(); catDefaults(); });
      function drawPi() {
        var el = $('#pis', m.el); if (!el) return;
        el.innerHTML = d.proj_items.length ? d.proj_items.map(function (x, i) { return '<div class="pi"><span class="grow"><input class="inp" style="min-height:34px" data-pin="' + i + '" value="' + esc((x.title ? x.title + ' – ' : '') + x.name) + '"></span><input class="inp" style="width:70px;min-height:34px" data-piq="' + i + '" value="' + esc(x.qty) + '" inputmode="decimal" title="Qty"><input class="inp" style="width:100px;min-height:34px" data-pip="' + i + '" value="' + esc(x.price || '') + '" inputmode="decimal" placeholder="Rate" title="Rate (optional)"><button type="button" class="btn btn-g btn-icon btn-sm" data-pid="' + i + '">' + C.ic('x') + '</button></div>'; }).join('') + '<div class="hint" style="margin-top:6px">Andar wale items ka rate sirf hisab ke liye — customer ko tabhi dikhega jab neeche tick ho.</div>' : '<p class="mute sm">Abhi kuch nahi jodha — panel, inverter, structure, wiring, installation…</p>';
      }
      drawPi();
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
        else if (e.target.closest('[data-addpi]')) { var its = await C.itemPick('product', true); its.forEach(function (it) { d.proj_items.push({ item_id: it.id, name: it.data.name || it.title, spec: C.specLine(it.data), qty: 1, price: it.data.price || '' }); }); drawPi(); }
        else if (e.target.closest('[data-ptotal]')) {
          var tot = 0, miss = 0; d.proj_items.forEach(function (x) { if (!String(x.name || '').trim()) return; var pr = num(x.price), q = num(x.qty) || 1; if (pr > 0) tot += pr * q; else miss++; });
          if (tot <= 0) return C.toast('Items me rate nahi hai — pehle "Product se jodein" se items jodein', true);
          var pf = $('input[name=price]', m.el); pf.value = C.r2(tot); pf.dispatchEvent(new Event('input', { bubbles: true }));
          $('#ptotH', m.el).textContent = 'Total ₹' + C.r2(tot) + ' (bina GST)' + (miss ? ' — ' + miss + ' line me rate nahi, wo jodi nahi gayi' : '');
        }
      });
      $('[data-ok]', m.el).onclick = async function () {
        var o = C.form(f); if (!C.need(f, ['category', 'name', 'price'])) return;
        if (cost && !proj && !(num(o.cost_price) > 0)) { var cpf = $('input[name=cost_price]', f); if (cpf) { cpf.classList.add('bad'); cpf.focus(); } return C.toast('Kharid rate (purchase price) zaroori hai', true); }
        var cat0 = o.category;
        if (o.category === '__new') { o.category = (o.category_new || '').trim(); if (!o.category) { cn.classList.add('bad'); cn.focus(); return C.toast('Nayi category ka naam likhein', true); } }
        delete o.category_new; C.cache.items = null;
        if (!proj && canCat) {
          try {
            if (cat0 === '__new') { var r1 = await C.call('crm_catalog_save', { op: 'add_cat', name: o.category }); C.cache.catalog = r1.catalog; CATS = r1.catalog; }
            if (o.subcategory === '__new') { var nm2 = (o.sub_new || '').trim(); if (!nm2) { sn.classList.add('bad'); sn.focus(); return C.toast('Nayi sub-category ka naam likhein', true); } var cc2 = CATS.filter(function (c) { return c.name === o.category; })[0]; var r2 = await C.call('crm_catalog_save', { op: 'add_sub', cat: cc2 && cc2.code, name: nm2 }); C.cache.catalog = r2.catalog; CATS = r2.catalog; o.subcategory = nm2; }
          } catch (e) { return C.toast(e.message, true); }
        } else if (o.subcategory === '__new') o.subcategory = '';
        var data = Object.assign(d, { type: proj ? 'project' : 'product', category: o.category, subcategory: proj ? '' : (o.subcategory || ''), name: o.name, price: C.r2(o.price), gst: num(o.gst), hsn: o.hsn, unit: o.unit, desc: o.desc });
        ['title', 'more', 'image_link', 'categories'].forEach(function (k) { delete data[k]; });   /* purani double jagahen hat gayin */
        if (!proj) { data.mrp = o.mrp; data.brand = o.brand; data.mpn = o.mpn || ''; data.warranty = o.warranty || ''; if (num(o.weight) > 0) data.weight = num(o.weight); else delete data.weight; if (o.stock === '') delete data.stock; else data.stock = num(o.stock); delete data.proj_items; }
        else { data.proj_items = d.proj_items.filter(function (x) { return String(x.name || '').trim(); }); data.show_prices = !!o.show_prices; data.kw = String(o.kw || '').trim(); data.sys = ['on', 'hy', 'off'].indexOf(o.sys) >= 0 ? o.sys : 'on'; delete data.stock; }
        if (!proj) {
          readSpecs(); var sf = specFields(), order = sf.key.concat(sf.more).filter(function (k) { return String(specVals[k] == null ? '' : specVals[k]).trim(); }), sp = {};
          order.forEach(function (k) { sp[k] = String(specVals[k]).trim(); });
          if (order.length) { sp._o = order; sp._n = order.filter(function (k) { return sf.key.indexOf(k) >= 0; }).length; data.specs = sp; } else delete data.specs;
        }
        data.store = Object.assign({}, data.store || {}, { tagline: o.s_tagline }); delete data.store.offer;
        if (cost) { if (!proj) data.cost_price = num(o.cost_price); data.min_price = o.min_price; }
        try { var r = await C.save('item', rec.id, data, { status: o.inactive ? 'inactive' : 'active' }); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  };

  /* pick products / projects (multi-select) */
  C.itemPick = function (type, multi) {
    return new Promise(async function (res) {
      var all = [], tp = type || 'product', chosen = {};
      var m = C.modal({ title: multi ? 'Items chunein' : 'Item chunein', size: 'wide', body: '<div class="bar">' + (type ? '' : C.chips([['product', 'Products'], ['project', 'Templates'], ['maintenance', 'Maintenance']], tp, 'tp')) + '<input class="inp" id="iq" type="search" placeholder="Item khojein" style="max-width:none;flex:1"></div><div class="list" id="il" style="max-height:55vh;overflow:auto">' + C.loading() + '</div>', foot: multi ? '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Jodein</button>' : false, onClose: function () { res(multi ? [] : null); } });
      function draw() {
        var q = $('#iq', m.el).value.toLowerCase(), list = all.filter(function (x) { return (x.data.type || 'product') === tp && x.status !== 'inactive' && (!q || (x.title + ' ' + (x.data.mpn || '') + ' ' + (x.data.brand || '') + ' ' + (x.data.sku || '')).toLowerCase().indexOf(q) >= 0); });
        $('#il', m.el).innerHTML = list.length ? list.map(function (x) { return '<label class="li click" style="cursor:pointer"' + (multi ? '' : ' data-one="' + x.id + '"') + '>' + (multi ? '<input type="checkbox" data-ck="' + x.id + '"' + (chosen[x.id] ? ' checked' : '') + '>' : '') + '<span class="av ' + (tp === 'project' ? 'v' : '') + '">' + C.ic(tp === 'project' ? 'plant' : 'box') + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m">' + (x.data.stock != null ? '<span>Stock: ' + esc(x.data.stock) + '</span>' : '') + '<span>GST ' + esc(x.data.gst || 0) + '%</span>' + (C.specLine(x.data) ? '<span class="ellip">' + esc(C.specLine(x.data)) + '</span>' : '') + '</span></span><span class="amt">' + money(x.data.price) + '</span>' + (multi ? '' : '<button type="button" class="btn btn-p btn-sm" data-one="' + x.id + '">Chunein</button>') + '</label>'; }).join('') : C.empty('box', 'Koi item nahi', C.can('items.create') ? 'Products & Templates me jodein' : '');
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

  /* ---------- categories manager (add / rename category + sub-category) ---------- */
  async function catManage(done) {
    var cats = await C.catalog(true);
    function body() { return '<div class="note g" style="margin-bottom:10px">Ye categories sirf company ke andar dikhti hain — customer ko quotation / Store / website par nahi. Rename karne par us category ke saare items ka naam bhi badal jata hai. <b>SKU code kabhi nahi badalta.</b></div>' +
      '<div class="list" style="max-height:48vh;overflow:auto">' + cats.map(function (c) { return '<div class="li"><span class="grow"><span class="t">' + esc(c.name) + ' <span class="xs mute">' + c.code + '</span></span><span class="m">' + c.subs.map(function (x) { return '<span>' + esc(x.name) + ' <span class="xs mute">' + x.code + '</span> <a data-rs="' + c.code + '|' + x.code + '" style="cursor:pointer">✎</a></span>'; }).join('') + '</span></span><span class="acts"><button class="btn btn-o btn-sm" data-rc="' + c.code + '">Rename</button><button class="btn btn-o btn-sm" data-as="' + c.code + '">+ Sub-category</button></span></div>'; }).join('') + '</div><div class="row" style="margin-top:10px"><input class="inp" id="ncat" placeholder="Nayi category ka naam" style="flex:1" maxlength="60"><button class="btn btn-p" data-ac>+ Category</button></div>'; }
    var m = C.modal({ title: 'Categories & Sub-categories', size: 'wide', body: body(), foot: '<button class="btn btn-p" data-close>Done</button>', onClose: function () { done(); } });
    async function op(o, msg) { try { var r = await C.run('crm_catalog_save', o, msg); cats = r.catalog; C.cache.catalog = cats; C.cache.items = null; var mb = $('.mb', m.el); if (mb) mb.innerHTML = body(); } catch (e) {} }
    m.el.addEventListener('click', async function (e) {
      var b;
      if (e.target.closest('[data-ac]')) { var n = $('#ncat', m.el).value.trim(); if (n) await op({ op: 'add_cat', name: n }, 'Category jud gayi ✔'); }
      else if ((b = e.target.closest('[data-as]'))) { var t = await C.ask('Nayi sub-category', 'Naam likhein', { ok: 'Jodein' }); if (t && t.trim()) await op({ op: 'add_sub', cat: b.getAttribute('data-as'), name: t.trim() }, 'Sub-category jud gayi ✔'); }
      else if ((b = e.target.closest('[data-rc]'))) { var c0 = cats.filter(function (c) { return c.code === b.getAttribute('data-rc'); })[0], t2 = await C.ask('Category ka naya naam', 'Naam', { ok: 'Save', value: c0.name }); if (t2 && t2.trim() && t2.trim() !== c0.name) await op({ op: 'rename_cat', code: c0.code, name: t2.trim() }, 'Naam badal gaya ✔'); }
      else if ((b = e.target.closest('[data-rs]'))) { var pr = b.getAttribute('data-rs').split('|'), c1 = cats.filter(function (c) { return c.code === pr[0]; })[0], s1 = c1.subs.filter(function (x) { return x.code === pr[1]; })[0], t3 = await C.ask('Sub-category ka naya naam', 'Naam', { ok: 'Save', value: s1.name }); if (t3 && t3.trim() && t3.trim() !== s1.name) await op({ op: 'rename_sub', cat: pr[0], code: pr[1], name: t3.trim() }, 'Naam badal gaya ✔'); }
    });
  }

  /* ---------- starter catalog: ready-made items with indicative average prices (edit before going live) ---------- */
  async function seedCatalog(done) {
    await C.catLoad(); var CD = window.CRM_CAT; if (!CD) return C.toast('Catalog data load nahi hua', true);
    var by = {}; CD.seed.forEach(function (x) { by[x.category] = (by[x.category] || 0) + 1; });
    var m = C.modal({ title: 'Starter catalog load karein', size: 'wide', body: '<div class="note o" style="margin-bottom:10px">' + CD.seed.length + ' ready items — brand, specification columns, GST/HSN aur <b>average (indicative) rate</b> ke saath. Rate / MRP market ka andaza hai (Oct 2026) — <b>live karne se pehle apne rate se badal lein</b>; GST bhi apne CA se confirm karein. Image link khaali hai. Dobara dabane par duplicate nahi banenge.</div><div class="stack">' +
      Object.keys(by).map(function (k) { return '<label class="ck"><input type="checkbox" data-sc="' + esc(k) + '" checked> ' + esc(k) + ' <span class="mute">(' + by[k] + ')</span></label>'; }).join('') + '</div><p class="sm b" id="sp"></p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Load karein</button>' });
    $('[data-ok]', m.el).onclick = async function () {
      var on = {}; $$('[data-sc]:checked', m.el).forEach(function (c) { on[c.getAttribute('data-sc')] = 1; });
      var rows = CD.seed.filter(function (x) { return on[x.category]; }); if (!rows.length) return C.toast('Koi category chuni nahi', true);
      C.busy(true); var added = 0, skipped = 0, failed = [];
      try { for (var i = 0; i < rows.length; i += 60) { var r = await C.call('crm_items_bulk_add', { rows: rows.slice(i, i + 60) }); added += r.added; skipped += r.skipped; failed = failed.concat(r.failed || []); } }
      catch (e) { C.busy(false); return C.toast(e.message, true); }
      C.busy(false); C.cache.items = null; m.close(); C.toast(added + ' items jud gaye' + (skipped ? ' · ' + skipped + ' pehle se the' : '') + (failed.length ? ' · ' + failed.length + ' fail (' + failed[0] + ')' : '') + ' ✔', !!failed.length); done();
    };
  }

  function importItems(done) {

    var m = C.modal({ title: 'Products Excel se jodein', body: '<div class="note g" style="margin-bottom:12px">Columns (pehli line heading): <b>Name, Price, GST, Stock, HSN, Unit, MRP, Brand, Category, Sub-category, Model, Warranty, Khaas baatein</b>. SKU apne-aap banega. Khaas baatein me har point nayi line me ya "|" se alag.</div><input type="file" class="inp" id="xf" accept=".xlsx,.csv"><p class="sm b" id="xp" style="margin-top:8px"></p>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok disabled>Import</button>' }), rows = [];
    $('#xf', m.el).onchange = async function () {
      try {
        var data = await C.readSheet(this.files[0]), head = (data[0] || []).map(function (x) { return String(x || '').toLowerCase().trim(); }), ix = function (re) { return head.findIndex(function (h) { return re.test(h); }); };
        var c = { name: ix(/^name|item name|naam/), price: ix(/price|rate/), gst: ix(/gst|tax/), stock: ix(/stock|qty/), hsn: ix(/hsn|sac/), unit: ix(/unit/), mrp: ix(/mrp/), brand: ix(/brand/), category: ix(/^categ/), subcategory: ix(/^sub/), mpn: ix(/^(sku|model|part|mpn)/), warranty: ix(/warrant/), desc: ix(/desc|detail|baat/) };
        if (c.name < 0 || c.price < 0) throw new Error('Name aur Price column zaroori hain');
        rows = data.slice(1).filter(function (r) { return String(r[c.name] || '').trim(); }).map(function (r) { var g = function (k) { return c[k] >= 0 ? String(r[c[k]] == null ? '' : r[c[k]]).trim() : ''; }; var o = { type: 'product', name: g('name'), price: num(g('price')), gst: num(g('gst') || 18), hsn: g('hsn'), unit: g('unit') || 'Nos', mrp: g('mrp'), brand: g('brand'), category: g('category'), subcategory: g('subcategory'), mpn: g('mpn'), warranty: g('warranty'), desc: g('desc').replace(/\s*\|\s*/g, '\n') }; if (g('stock') !== '') o.stock = num(g('stock')); return o; });
        $('#xp', m.el).textContent = rows.length + ' products milenge'; $('[data-ok]', m.el).disabled = !rows.length;
      } catch (e) { C.toast(e.message || 'File padh nahi paye', true); }
    };
    $('[data-ok]', m.el).onclick = async function () { var ok = 0; C.busy(true); for (var i = 0; i < rows.length; i++) { try { await C.call('crm_save', { kind: 'item', data: rows[i] }); ok++; } catch (e) { C.toast(rows[i].name + ': ' + e.message, true); } } C.busy(false); m.close(); C.toast(ok + ' products jud gaye ✔'); done(); };
  }

  /* One page used twice: Inventory/Stock (products) and Quotation/Templates → Templates tab */
  async function itemsPage(el, q, host) {
    {
      var NAV = function (o) { return host.route + C.qs(Object.assign({}, host.extra, o)); };
      var tp = host.tp || 'product', st = q.store || '', all = await C.list('item', { limit: 3000 }), cost = C.can('items.cost'); C.cache.items = all;
      var fcat = q.cat || '', fsub = q.sub || '', CATL = tp === 'project' ? [] : await C.catalog();
      var list = all.filter(function (x) { return (x.data.type || 'product') === tp && (!st || ((x.data.store || {}).status || 'none') === st) && (!fcat || C.itemInCat(x, fcat)) && (!fsub || x.data.subcategory === fsub); });
      var nP = all.filter(function (x) { return (x.data.type || 'product') === 'product'; }).length;
      var h = '<div class="ph"><div><h1>' + (host.tp === 'project' ? 'Templates' : 'Inventory / Stock') + '</h1><p>' + (host.tp === 'project' ? 'Ready packages (jaise 3 kW On-grid) — ek click me quotation me. Click karne par Edit / Delete / Online sale ke liye Admin ko bhejein.' : 'Ek hi inventory — quotation, bill aur Online Store sab yahin se. Har item ka SKU apne aap banta hai.') + '</p></div><div class="row">' +
        (C.can('items.export') ? C.reportBtns('Stock', function () { return { head: ['Prakar', 'Naam', 'Rate', 'GST', 'MRP', 'Stock', 'Unit', 'HSN', 'Brand', 'Category'].concat(cost ? ['Kharid rate', 'Stock value'] : []), rows: all.map(function (x) { var d = x.data; return [d.type || 'product', x.title, num(d.price), num(d.gst), d.mrp || '', d.stock != null ? d.stock : '', d.unit || '', d.hsn || '', d.brand || '', d.category || ''].concat(cost ? [num(d.cost_price), d.stock != null ? num(d.stock) * num(d.cost_price || d.price) : ''] : []); }) }; }) : '') +
        (C.can('items.edit') && C.can('sheets.download') ? '<button class="btn btn-o" data-act="sheetdl">' + C.ic('download') + ' Download sheet for edit</button>' : '') + (C.can('items.edit') && C.can('sheets.upload') ? '<button class="btn btn-o" data-act="sheetup">' + C.ic('upload') + ' Upload edited sheet</button>' : '') + (C.can('items.delete') && list.length ? '<button class="btn btn-r" data-act="delcat">' + C.ic('trash') + ' Delete category-wise</button><button class="btn btn-r" data-act="delall">' + C.ic('trash') + ' Delete all</button>' : '') + (C.can('items.categories') && tp !== 'project' ? '<button class="btn btn-o" data-act="cats">' + C.ic('folder') + ' Categories</button>' : '') + (C.can('items.create') && tp !== 'project' ? '<button class="btn btn-o" data-act="seed">' + C.ic('box') + ' Starter catalog</button>' : '') + (C.can('items.create') ? '<button class="btn btn-o" data-act="imp">' + C.ic('upload') + ' Excel</button><button class="btn btn-p" data-act="add">' + C.ic('plus') + ' ' + (tp === 'project' ? 'Naya project' : 'Naya product') + '</button>' : '') + '</div></div>';
      if (host.tabs) h += host.tabs(all.filter(function (x) { return x.data.type === 'project'; }).length);
      else h += '<div class="tabs"><button data-tp="product" class="' + (tp === 'product' ? 'on' : '') + '">Products (' + nP + ')</button>' + (C.can('stock.view') ? '<button data-goto="#/items?tab=stock">Stock dashboard</button>' : '') + '<button data-goto="#/items?tab=online">Online list</button></div>';
      var fcObj = CATL.filter(function (c) { return c.name === fcat; })[0], cnt = {};
      all.forEach(function (x) { if ((x.data.type || 'product') === tp) { var k = x.data.category || ''; cnt[k] = (cnt[k] || 0) + 1; } });
      var catNames = tp === 'project' ? C.CAT_DEF.project.slice() : CATL.map(function (c) { return c.name; });
      Object.keys(cnt).forEach(function (k) { if (k && catNames.indexOf(k) < 0) catNames.push(k); });
      h += '<div class="bar" id="fbar"><select class="inp" data-fcat style="max-width:260px"><option value="">Saari categories</option>' + catNames.map(function (n) { return '<option value="' + esc(n) + '"' + (n === fcat ? ' selected' : '') + '>' + esc(n) + (cnt[n] ? ' (' + cnt[n] + ')' : '') + '</option>'; }).join('') + '</select>' +
        (fcObj && fcObj.subs.length ? '<select class="inp" data-fsub style="max-width:260px"><option value="">Saari sub-categories</option>' + fcObj.subs.map(function (x) { return '<option value="' + esc(x.name) + '"' + (x.name === fsub ? ' selected' : '') + '>' + esc(x.name) + '</option>'; }).join('') + '</select>' : '') +
        (fcat || fsub ? '<button class="btn btn-g btn-sm" data-fclr>Filter hatayein</button>' : '') + '<span class="sm mute">' + list.length + ' items</span></div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Item / SKU / brand khojein">' + C.chips([['', 'Sab'], ['none', 'Sirf CRM'], ['pending', 'Store review me'], ['published', 'Store par live'], ['rejected', 'Lautaye']], st, 'store') + '</div>';
      if (C.can('items.to_store')) h += '<div class="note g" style="margin-bottom:12px">' + C.ic('shield') + ' Product seedha Online Store par live nahi hota: <b>"Online Store ko bhejein"</b> → Store Admin Google / Meta niyam check karega → wahan se Publish.</div>';
      var canSend = C.can('items.to_store') && (tp === 'product' || tp === 'project') && list.length > 0;
      if (canSend) h += '<div class="bar" id="bsel" style="align-items:center;gap:10px;flex-wrap:wrap"><label class="ck" style="margin:0"><input type="checkbox" id="selAll" style="accent-color:var(--leaf)"> Sab chunein</label><button class="btn btn-o btn-sm" type="button" data-act="selnew">Sirf naye (Store par nahi bheje)</button><span class="grow"></span><span class="sm mute" id="selCnt">0 chune hue</span><button class="btn btn-p btn-sm" type="button" data-act="bulkstore" id="selGo" disabled>' + C.ic('store') + ' Chune hue Store ko bhejein</button></div>';
      h += list.length ? '<div class="list" id="itl">' + list.map(function (x) {
        var d = x.data, low = d.stock != null && num(d.stock) <= 0;
        return '<div class="li click" data-act="edit" data-id="' + x.id + '" data-stt="' + esc((d.store || {}).status || 'none') + '">' + (canSend && ['pending', 'published'].indexOf((d.store || {}).status) < 0 ? '<input type="checkbox" class="selbox" data-sel="' + x.id + '" aria-label="Chunein" style="width:20px;height:20px;flex:none;margin-right:2px;accent-color:var(--leaf)">' : '') + '<span class="av ' + (tp === 'project' ? 'v' : '') + '">' + C.ic(tp === 'project' ? 'plant' : 'box') + '</span>' +
          '<span class="grow"><span class="t">' + esc(x.title) + (d.type === 'project' && d.kw ? C.pill(d.kw + ' kW', 'g') : '') + (d.type === 'project' && d.sys && d.sys !== 'on' ? C.pill(d.sys === 'hy' ? 'Hybrid' : 'Off-Grid', 'o') : '') + (x.status === 'inactive' ? C.pill('Band', 'g') : '') + C.storePill(x) + '</span><span class="m">' + (d.sku ? '<span style="font-weight:700;letter-spacing:.03em">' + esc(d.sku) + '</span>' : '') + (d.category ? '<span>' + esc(d.category) + (d.subcategory ? ' › ' + esc(d.subcategory) : '') + '</span>' : '') + (d.brand ? '<span>' + esc(d.brand) + '</span>' : '') + (tp === 'project' ? '<span>' + (d.proj_items || []).length + ' cheezein shamil</span>' : '') + (d.stock != null ? '<span' + (low ? ' style="color:var(--red);font-weight:700"' : '') + '>Stock: ' + esc(d.stock) + ' ' + esc(d.unit || '') + '</span>' : '') + '<span>GST ' + esc(d.gst || 0) + '%</span>' + (d.hsn ? '<span>HSN ' + esc(d.hsn) + '</span>' : '') + (cost && num(d.min_price) ? '<span>Min ' + money(d.min_price) + '</span>' : '') + (cost && tp === 'product' && !(num(d.cost_price) > 0) ? '<span style="color:var(--red);font-weight:700">⚠ Kharid rate nahi</span>' : '') + (d.store && d.store.status === 'rejected' && d.store.note ? '<span style="color:var(--red)">Store Admin: ' + esc(d.store.note) + '</span>' : '') + (d.store && d.store.status === 'published' && d.store.store_id && C.storeUrl() ? '<span><a href="' + esc(C.storeUrl().replace(/\/+$/, '') + '/?p=' + encodeURIComponent(d.store.store_id)) + '" target="_blank" rel="noopener" style="color:var(--leaf-d);font-weight:700">Store par dekhein ↗</a></span>' : '') + '</span></span>' +
          '<span class="amt">' + money(d.price) + (cost && num(d.cost_price) ? '<small>Kharid ' + money(d.cost_price) + '</small>' : '') + '</span><span class="acts">' + (C.can('items.to_store') && ['pending'].indexOf((d.store || {}).status) < 0 ? '<button class="btn btn-o btn-sm" data-act="store" data-id="' + x.id + '" style="display:inline-flex" title="Online Store Admin ko bhejein">' + C.ic('store') + '<span class="desk-only">Store ko bhejein</span></button>' : '') + (C.can('items.delete') ? '<button class="btn btn-g btn-icon btn-sm" data-act="del" data-id="' + x.id + '" aria-label="Hatayein">' + C.ic('trash') + '</button>' : '') + '</span></div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('box', 'Koi item nahi', C.can('items.create') ? (tp === 'project' ? 'Template = poora package (jaise 3kW On-grid) — andar ke items ka rate customer ko nahi dikhta' : '"Naya product" dabayein') : '') + '</div>';
      el.innerHTML = h;
      var itl = $('#itl', el); if (itl) C.filterList($('[data-q]', el), itl);
      el.addEventListener('change', function (e) {
        var fc = e.target.closest('[data-fcat]'), fs = e.target.closest('[data-fsub]'), base = { store: st };
        if (fc) C.go(NAV(Object.assign(base, { cat: fc.value, sub: '' })));
        else if (fs) C.go(NAV(Object.assign(base, { cat: fcat, sub: fs.value })));
      });
      el.addEventListener('click', function (e) { if (e.target.closest('[data-fclr]')) C.go(NAV({ store: st })); });
      el.addEventListener('click', function (e) { var t = e.target.closest('[data-tp]'); if (t) { C.go(t.getAttribute('data-tp') === 'product' ? '#/items' : '#/items?type=project'); } var g = e.target.closest('[data-goto]'); if (g) return C.go(g.getAttribute('data-goto')); var s = e.target.closest('[data-store]'); if (s) C.go(NAV({ store: s.getAttribute('data-store') })); });
      el.addEventListener('click', function (e) { if (e.target.closest && e.target.closest('.selbox')) e.stopPropagation(); }, true); /* C.bind() preventDefault()s clicks inside [data-act] rows — that would stop the tick box from toggling */
      C.bind(el, {
        add: function () { C.itemForm(null, tp).then(function (r) { if (r) C.render(); }); },
        imp: function () { importItems(function () { C.render(); }); },
        cats: function () { catManage(function () { C.render(); }); },
        seed: function () { seedCatalog(function () { C.render(); }); },
        sheetdl: function () { sheetDownloadDlg(all, tp, cost); },
        sheetup: function () { sheetUpload(tp, cost, function () { C.render(); }); },
        delcat: function () { deleteByCategory(all, tp, cost, function () { C.render(); }); },
        delall: function () { deleteAll(list, tp, cost, function () { C.render(); }); },
        edit: function (id, a, e) { if (e.target.closest('.acts,.selbox')) return; var x = all.find(function (z) { return String(z.id) === id; }); if (x.data.type === 'project') return projectSheet(x, function () { C.render(); }); if (!C.can('items.edit')) return itemInfo(x); C.itemForm(x).then(function (r) { if (r) C.render(); }); },
        store: async function (id) {
          var x = all.find(function (z) { return String(z.id) === id; });
          if (await C.confirm('"' + x.title + '" Online Store Admin ko review ke liye bhejein? Admin check karke Publish karega.', 'Bhejein')) { var oq1 = await askOnlineQty([x]); if (oq1) { try { await C.run('crm_to_store', { id: id, web: (oq1[x.id] || {}).web || 0, app: (oq1[x.id] || {}).app || 0 }, 'Store Admin ko bhej diya ✔'); C.render(); } catch (e) {} } }
        },
        del: async function (id) { var x = all.find(function (z) { return String(z.id) === id; }); if (await C.delWithReason(x, x.title)) C.render(); },
        selnew: function () { $$('#itl .li', el).forEach(function (r) { var cb = $('.selbox', r); if (cb && r.offsetParent !== null) cb.checked = ['none', 'rejected'].indexOf(r.getAttribute('data-stt')) >= 0; }); syncSel(); },
        bulkstore: function () { bulkToStore(all, chosenIds(), function () { C.render(); }); }
      });
      function chosenIds() { return $$('#itl .selbox:checked', el).map(function (c) { return c.getAttribute('data-sel'); }); }
      function syncSel() {
        var ids = chosenIds(), cnt = $('#selCnt', el), go = $('#selGo', el), all0 = $('#selAll', el), vis = $$('#itl .selbox', el).filter(function (c) { return c.closest('.li').offsetParent !== null; });
        if (cnt) cnt.textContent = ids.length + ' chune hue'; if (go) go.disabled = !ids.length;
        if (all0) all0.checked = vis.length > 0 && vis.every(function (c) { return c.checked; });
      }
      el.addEventListener('change', function (e) {
        if (e.target.id === 'selAll') { $$('#itl .selbox', el).forEach(function (c) { if (c.closest('.li').offsetParent !== null) c.checked = e.target.checked; }); syncSel(); }
        else if (e.target.classList && e.target.classList.contains('selbox')) syncSel();
      });
      if (q.open) { var it = all.find(function (z) { return String(z.id) === q.open; }); if (it) setTimeout(function () { C.setQuery({ open: '' }); (C.can('items.edit') ? C.itemForm(it) : itemInfo(it)); }, 30); }
    }
  }
  C.itemsPage = itemsPage;
  C.mod('items', {
    title: 'Inventory / Stock',
    allowed: function () { return C.can('items.view'); },
    render: function (el, params, q) {
      if (q.tab === 'stock') return C.can('stock.view') ? stockPage(el, q) : (el.innerHTML = '<div class="card">' + C.empty('lock', 'Stock dashboard ki permission nahi hai') + '</div>');
      if (q.tab === 'online') return C.onlineView(el, params, q); /* Round 45: Online list = Inventory ka tab */
      return itemsPage(el, q, { route: '#/items', extra: q.type === 'project' ? { type: 'project' } : {}, tp: q.type === 'project' ? 'project' : 'product' });
    }
  });

  /* ================================================================ Stock dashboard (Inventory / Stock → Stock dashboard) */
  var LV = { ok: ['Theek', ''], low: ['Kam (20% niyam)', 'o'], out: ['Khatam', 'r'] };
  async function stockPage(el, q) {
    var rp = await C.call('crm_stock_report', {}), rows = rp.rows || [], pct = rp.pct || 20, fcat = q.cat || '', fsub = q.sub || '', flv = q.lv || '', cost = C.can('items.cost');
    var catSet = {}; rows.forEach(function (r) { if (r.category) catSet[r.category] = 1; });
    var subs = {}; rows.forEach(function (r) { if (!fcat || r.category === fcat) if (r.subcategory) subs[r.subcategory] = 1; });
    var list = rows.filter(function (r) { return (!fcat || r.category === fcat) && (!fsub || r.subcategory === fsub) && (!flv || r.level === flv); });
    var sum = function (k, a) { return (a || list).reduce(function (t, r) { return t + num(r[k]); }, 0); };
    var tot = sum('total'), sold = sum('sold'), rem = sum('on_hand'), resv = sum('reserved_quote') + sum('hold_offline') + sum('hold_online');
    var cLow = list.filter(function (r) { return r.level === 'low'; }).length, cOut = list.filter(function (r) { return r.level === 'out'; }).length, cOk = list.length - cLow - cOut;
    var h = '<div class="ph"><div><h1>Inventory / Stock</h1><p>Kitna maal aaya, bika, bacha aur kiske liye reserve hai — ek jagah.</p></div><div class="row">' + C.reportBtns('Stock-dashboard', function () { return { head: ['SKU', 'Item', 'Category', 'Sub-category', 'Brand', 'Total', 'Sold', 'Remaining', 'Quotation reserve', 'Direct/Other hold', 'Online hold', 'Offline ke liye bacha', 'Online share bacha %', 'Status'], rows: list.map(function (r) { return [r.sku || '', r.name, r.category || '', r.subcategory || '', r.brand || '', r.total, r.sold, r.on_hand, r.reserved_quote, r.hold_offline, r.hold_online, r.free_offline, r.online_left_pct, (LV[r.level] || [r.level])[0]]; }), text: 'Stock dashboard' }; }) + '</div></div>';
    h += '<div class="tabs"><button data-goto="#/items">Products</button><button class="on">Stock dashboard</button></div>';
    if (rp.alerts) h += '<div class="note r" style="margin-bottom:12px">' + C.ic('alert') + ' <b>' + rp.alerts + ' item</b> par dhyan dein — online store ke liye ' + pct + '% hissa surakshit rakhna hai. Neeche "Kam" / "Khatam" dekhein aur naya maal mangwayein.</div>';
    h += '<div class="ch-tiles">' + [
      { l: 'Kul maal (aaya)', v: tot, icon: 'box', c: '#1e8e3e', sub: list.length + ' items' },
      { l: 'Bika', v: sold, icon: 'cart', c: '#2f6fdb', sub: 'bill ban chuke' },
      { l: 'Bacha (godown me)', v: rem, icon: 'check', c: '#12a5a5' },
      { l: 'Reserved', v: resv, icon: 'clock', c: '#f2a900', sub: 'quotation + hold' },
      { l: 'Alert', v: cLow + cOut, icon: 'alert', c: (cLow + cOut) ? '#d64545' : '#6b7a70', sub: cOut + ' khatam · ' + cLow + ' kam' },
      { l: 'Stock track nahi', v: rp.untracked || 0, icon: 'filter', c: '#7b4fd1', sub: 'stock ginti nahi bhari' }
    ].map(C.chart.tile).join('') + '</div>';
    var byCat = {}; list.forEach(function (r) { var k = r.category || 'Other'; var b = byCat[k] = byCat[k] || { l: k.replace(/^Solar /, ''), vs: [0, 0, 0] }; b.vs[0] += num(r.on_hand); b.vs[1] += num(r.reserved_quote) + num(r.hold_offline) + num(r.hold_online); b.vs[2] += num(r.sold); });
    var topRes = list.slice().sort(function (a, b) { return (num(b.reserved_quote) + num(b.hold_offline) + num(b.hold_online)) - (num(a.reserved_quote) + num(a.hold_offline) + num(a.hold_online)); }).filter(function (r) { return num(r.reserved_quote) + num(r.hold_offline) + num(r.hold_online) > 0; }).map(function (r) { return { l: r.name, v: num(r.reserved_quote) + num(r.hold_offline) + num(r.hold_online) }; });
    h += '<div class="ch-grid2"><div class="card"><div class="hd"><h3>Stock ki sehat</h3></div>' + C.chart.donut([{ l: 'Theek', v: cOk, c: '#1e8e3e' }, { l: 'Kam (<' + pct + '% online share)', v: cLow, c: '#f2a900' }, { l: 'Khatam', v: cOut, c: '#d64545' }], { center: list.length, sub: 'items' }) + '</div>' +
      '<div class="card"><div class="hd"><h3>Category-wise</h3></div>' + C.chart.bars(Object.keys(byCat).map(function (k) { return byCat[k]; }), { series: [{ n: 'Bacha', c: '#1e8e3e' }, { n: 'Reserved', c: '#f2a900' }, { n: 'Bika', c: '#2f6fdb' }], h: 190 }) + '</div>' +
      '<div class="card"><div class="hd"><h3>Sabse zyada reserved</h3></div>' + C.chart.hbars(topRes) + '</div></div>';
    h += '<div class="bar" id="fbar"><select class="inp" data-fcat style="max-width:240px"><option value="">Saari categories</option>' + Object.keys(catSet).sort().map(function (n) { return '<option' + (n === fcat ? ' selected' : '') + '>' + esc(n) + '</option>'; }).join('') + '</select>' +
      '<select class="inp" data-fsub style="max-width:240px"><option value="">Saari sub-categories</option>' + Object.keys(subs).sort().map(function (n) { return '<option' + (n === fsub ? ' selected' : '') + '>' + esc(n) + '</option>'; }).join('') + '</select>' +
      '<select class="inp" data-flv style="max-width:200px"><option value="">Saari halat</option><option value="low"' + (flv === 'low' ? ' selected' : '') + '>Kam</option><option value="out"' + (flv === 'out' ? ' selected' : '') + '>Khatam</option><option value="ok"' + (flv === 'ok' ? ' selected' : '') + '>Theek</option></select>' +
      '<input class="inp" type="search" data-q placeholder="SKU / item khojein"><span class="sm mute">' + list.length + ' items</span></div>';
    h += list.length ? '<div class="card"><div class="tw"><table class="t" id="stt"><thead><tr><th>Item</th><th class="r">Kul</th><th class="r">Bika</th><th class="r">Bacha</th><th class="r">Reserved</th><th class="r">Offline ke liye</th><th class="r">Online share</th><th>Status</th><th></th></tr></thead><tbody>' + list.map(function (r) {
      var rs = num(r.reserved_quote) + num(r.hold_offline) + num(r.hold_online), fr = r['for'] || [];
      return '<tr data-row="' + r.id + '"><td><b>' + esc(r.name) + '</b><div class="xs mute">' + esc(r.sku || '') + (r.category ? ' · ' + esc(r.category) + (r.subcategory ? ' › ' + esc(r.subcategory) : '') : '') + '</div>' + (num(r.reserved_tpl) ? '<div class="xs" style="color:var(--leaf-d)">Template reserve: ' + r.reserved_tpl + ' · baaki (templates ke baad): ' + r.free_after_tpl + '</div>' : '') + (num(r.online_qty) ? '<div class="xs mute">Online ke liye alag: ' + r.online_qty + '</div>' : '') + (r.cost_missing && cost ? '<div class="xs" style="color:var(--red)">⚠ Kharid rate nahi likha</div>' : '') + '</td><td class="r">' + r.total + '</td><td class="r">' + r.sold + '</td><td class="r"><b>' + r.on_hand + '</b> <span class="xs mute">' + esc(r.unit) + '</span></td><td class="r">' + rs + '</td><td class="r">' + r.free_offline + '</td><td class="r">' + C.chart.progress(r.online_left_pct, r.level === 'ok' ? '#1e8e3e' : r.level === 'low' ? '#f2a900' : '#d64545') + '<span class="xs">' + r.online_left_pct + '%</span></td><td>' + C.pill(LV[r.level][0], LV[r.level][1]) + '</td><td class="r nw">' + (fr.length ? '<button class="btn btn-g btn-sm" data-for="' + r.id + '">Kiske liye (' + fr.length + ')</button>' : '') + (C.can('stock.reserve') ? '<button class="btn btn-o btn-sm" data-res="' + r.id + '">Reserve</button>' : '') + '</td></tr>';
    }).join('') + '</tbody></table></div></div>' : '<div class="card">' + C.empty('box', 'Koi item nahi', 'Pehle Products me item jodein aur "Stock" bharein — tabhi ginti yahan dikhegi.') + '</div>';
    var pj = rp.projects || [];
    if (pj.length) h += '<div class="card" style="margin-top:14px"><div class="hd"><h3>Templates — kitne ban sakte hain</h3></div><div class="list">' + pj.map(function (x) { return '<div class="li"><span class="av v">' + C.ic('plant') + '</span><span class="grow"><span class="t">' + esc(x.name) + (x.live ? C.pill('Store par live', '') : '') + '</span><span class="m"><span>' + esc(x.sku || '') + '</span>' + ((x.risky || []).length ? '<span style="color:var(--red);font-weight:700">Kam stock: ' + esc(x.risky.join(', ')) + '</span>' : '') + '</span></span><span class="amt">' + (x.buildable == null ? '—' : x.buildable + ' set') + '</span></div>'; }).join('') + '</div></div>';
    el.innerHTML = h;
    var tb = $('#stt tbody', el); if (tb) C.filterList($('[data-q]', el), tb, 'tr');
    el.addEventListener('change', function (e) {
      var go = function (o) { C.go('#/items' + C.qs(Object.assign({ tab: 'stock', cat: fcat, sub: fsub, lv: flv }, o))); };
      if (e.target.matches('[data-fcat]')) go({ cat: e.target.value, sub: '' }); else if (e.target.matches('[data-fsub]')) go({ sub: e.target.value }); else if (e.target.matches('[data-flv]')) go({ lv: e.target.value });
    });
    el.addEventListener('click', function (e) {
      var g = e.target.closest('[data-goto]'); if (g) return C.go(g.getAttribute('data-goto'));
      var t = e.target.closest('[data-tp]'); if (t) return C.go('#/maintenance?tab=plans');
      var f = e.target.closest('[data-for]'); if (f) return forWhom(rows.find(function (z) { return String(z.id) === f.getAttribute('data-for'); }), function () { C.render(); });
      var r = e.target.closest('[data-res]'); if (r) return holdForm(rows.find(function (z) { return String(z.id) === r.getAttribute('data-res'); }), function () { C.render(); });
    });
  }
  function forWhom(r, done) {
    var fr = r['for'] || [], pct = 0;
    var body = fr.length ? '<div class="list">' + fr.map(function (x) {
      return x.t === 'tpl' ? '<div class="li"><span class="av v">' + C.ic('plant') + '</span><span class="grow"><span class="t">' + esc(x.who || '') + ' ' + C.pill('Project Template', 'g') + '</span><span class="m"><span>Template ke hisaab se alag se gina gaya (quotation se alag)</span></span></span><span class="amt">' + x.qty + '</span></div>'
        : x.t === 'quote' ? '<a class="li" href="#/quote/' + x.qid + '" data-close><span class="av b">' + C.ic('quote') + '</span><span class="grow"><span class="t">' + esc(x.who || '') + (x.title ? ' <span class="qt">' + esc(x.title) + '</span>' : '') + '</span><span class="m"><span>' + esc(x.ref || '') + '</span><span>Valid: ' + esc(C.fd(x.till)) + '</span></span></span><span class="amt">' + x.qty + '</span></a>'
        : '<div class="li"><span class="av o">' + C.ic('clock') + '</span><span class="grow"><span class="t">' + esc(x.who) + ' ' + C.pill({ direct: 'Direct', online: 'Online', other: 'Anya' }[x.type] || x.type, 'b') + '</span><span class="m">' + (x.till ? '<span>Tak: ' + esc(C.fd(x.till)) + '</span>' : '') + (x.note ? '<span>' + esc(x.note) + '</span>' : '') + '</span></span><span class="amt">' + x.qty + '</span>' + (String(x.hid || '').indexOf('auto-') === 0 ? '<a class="btn btn-g btn-sm" href="#/items?tab=online" data-close>Online list</a>' : (C.can('stock.reserve') ? '<button class="btn btn-g btn-sm" data-rel="' + esc(x.hid) + '">Chhodein</button>' : '')) + '</div>';
    }).join('') + '</div>' : C.empty('box', 'Koi reserve nahi', '');
    var m = C.modal({ title: 'Kiske liye reserve — ' + esc(r.name), body: body, foot: '<button class="btn btn-o" data-close>Band</button>' });
    m.el.addEventListener('click', async function (e) { var b = e.target.closest('[data-rel]'); if (!b) return; try { await C.run('crm_stock_hold', { op: 'release', item_id: r.id, hold_id: b.getAttribute('data-rel') }, 'Reserve hat gaya ✔'); m.close(); done(); } catch (er) {} });
  }
  function holdForm(r, done) {
    var m = C.modal({ title: 'Stock reserve — ' + esc(r.name), size: 'sm', body: '<p class="sm mute" style="margin-bottom:10px">Abhi free: <b>' + r.free_total + ' ' + esc(r.unit) + '</b></p><form id="hf" class="fg">' + C.f('Kitna *', C.inp('qty', '', 'inputmode="decimal"')) + C.f('Kis liye', C.sel('type', [['direct', 'Direct bikri'], ['online', 'Online store'], ['other', 'Anya']], 'direct')) + C.f('Kiske liye (naam) *', C.inp('for', '', 'maxlength="120" placeholder="Jaise: Verma ji walk-in"'), 'full') + C.f('Kab tak', '<input class="inp" type="date" name="until">') + C.f('Note', C.inp('note', '', 'maxlength="200"')) + '</form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Reserve karein</button>' });
    $('[data-ok]', m.el).onclick = async function () { var f = $('#hf', m.el), o = C.form(f); if (!C.need(f, ['qty', 'for'])) return; try { await C.run('crm_stock_hold', { op: 'add', item_id: r.id, qty: num(o.qty), type: o.type, 'for': o['for'], until: o.until, note: o.note }, 'Reserve ho gaya ✔'); m.close(); done(); } catch (e) {} };
  }

  /* project row click → only: Edit / Delete (permission based) / send to Admin for online-sale review */
  function projectSheet(x, done) {
    var d = x.data, st = (d.store || {}).status || 'none', acts = '';
    if (C.can('quotes.create')) acts += '<button class="btn btn-p btn-block" data-ps="quote">' + C.ic('quote') + ' Is template se Quotation banayein</button>';
    if (C.can('items.edit')) acts += '<button class="btn btn-o btn-block" data-ps="rename">' + C.ic('edit') + ' Template ka naam badlein</button>';
    if (C.can('items.edit')) acts += '<button class="btn btn-o btn-block" data-ps="edit">' + C.ic('edit') + ' Edit</button>';
    if (C.can('items.to_store') && st !== 'pending') acts += '<button class="btn btn-o btn-block" data-ps="store">' + C.ic('store') + ' Online sale ke liye Admin ko bhejein</button>';
    if (st === 'pending') acts += '<p class="hint">Ye project Store Admin ke review me hai.</p>';
    if (C.can('items.delete')) acts += '<button class="btn btn-r btn-block" data-ps="del">' + C.ic('trash') + ' Delete</button>';
    if (!acts) { return itemInfo(x); }
    var m = C.modal({ title: esc(x.title), size: 'sm', body: '<p class="sm mute" style="margin-bottom:12px">' + esc(d.sku || '') + ' · ' + money(d.price) + ' · ' + (d.proj_items || []).length + ' cheezein</p><div class="stack">' + acts + '</div>', foot: '<button class="btn btn-o" data-close>Band</button>' });
    m.el.addEventListener('click', async function (e) {
      var b = e.target.closest('[data-ps]'); if (!b) return; var a = b.getAttribute('data-ps'); m.close();
      if (a === 'edit') { var r = await C.itemForm(x); if (r) done(); }
      else if (a === 'quote') { var pty = await C.partyPick({ title: 'Kis customer ke liye quotation? (naya bhi bana sakte hain)' }); if (pty) C.go('#/quote/new' + C.qs({ party: pty.id, tpl: x.id })); }
      else if (a === 'rename') { var nn = await C.ask('Template ka naam badlein', 'Naya naam (customer ka naam na likhein)', { value: x.data.name || x.title, min: 2, hint: 'Online ho tab bhi naam badal sakte hain; items / qty / rate nahi.' }); if (nn != null && nn !== (x.data.name || x.title)) { try { await C.save('item', x.id, Object.assign({}, x.data, { name: nn }), { status: x.status }, 'Naam badal diya ✔'); done(); } catch (er) {} } }
      else if (a === 'store') { if (await C.confirm('"' + x.title + '" Online Store Admin ko review ke liye bhejein? Admin check karke Publish karega.', 'Bhejein')) { var oq2 = await askOnlineQty([x]); if (oq2) { try { await C.run('crm_to_store', { id: x.id, web: (oq2[x.id] || {}).web || 0, app: (oq2[x.id] || {}).app || 0 }, 'Store Admin ko bhej diya ✔'); done(); } catch (er) {} } } }
      else if (a === 'del') { if (await C.delWithReason(x, x.title)) done(); }
    });
  }

  /* ---------- bulk: many items -> Online Store Admin review in one go ---------- */
  /* Round 44: online ke liye qty — Web Shop aur Store App alag. Returns {id: {web, app}} ya null (cancel).
     Jo item pehle se online pool me hai uska qty yahan nahi poochte (Online list se badalta hai). */
  function askOnlineQty(rows) {
    return new Promise(function (res) {
      var pct = num(((C.cache.settings || {}).stock || {}).online_pct) || 20;
      var tr = rows.filter(function (x) { var s = x.data.store || {}; return !s.online && (x.data.type === 'project' || (x.data.stock != null && String(x.data.stock) !== '')); });
      if (!tr.length) return res({});
      var body = '<p class="hint" style="margin-bottom:10px">Online ke liye kitna maal alag rakhna hai? Web Shop aur Store App ka alag likhein — dono ek hi pool se katenge, isliye double selling nahi hogi. Itna maal offline quotation me nahi bechenge. Baad me "Online list" se aur jod sakte hain.</p>' + tr.map(function (x) {
        var proj = x.data.type === 'project', st = num(x.data.stock), pool = proj ? 0 : Math.min(st, Math.floor(st * pct / 100)), w = Math.ceil(pool * 0.7), a = pool - w;
        return '<div class="card" style="margin-bottom:10px;padding:10px"><b>' + esc(x.title) + '</b> <span class="xs mute">' + (proj ? 'Template — kitne set' : 'stock ' + esc(st) + ' ' + esc(x.data.unit || '')) + '</span><div class="fg" style="margin-top:6px">' +
          '<div class="f"><label>Web Shop</label><input class="inp" data-ow="' + x.id + '" inputmode="numeric" value="' + w + '"></div><div class="f"><label>Store App</label><input class="inp" data-oa="' + x.id + '" inputmode="numeric" value="' + a + '"></div></div></div>';
      }).join('');
      var m = C.modal({ title: 'Online ke liye qty', size: 'sm', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Aage badhein</button>', onClose: function () { res(null); } });
      $('[data-ok]', m.el).onclick = function () {
        var out = {}, bad = '';
        tr.forEach(function (x) {
          var w = num($('[data-ow="' + x.id + '"]', m.el).value), a = num($('[data-oa="' + x.id + '"]', m.el).value), proj = x.data.type === 'project';
          if (w < 0 || a < 0 || w + a <= 0 || w !== Math.floor(w) || a !== Math.floor(a)) bad = x.title + ': qty poori sankhya me likhein (Web ya App me kam se kam 1)';
          else if (!proj && w + a > num(x.data.stock)) bad = x.title + ': qty stock (' + x.data.stock + ') se zyada hai';
          else out[x.id] = { web: w, app: a };
        });
        if (bad) return C.toast(bad, true);
        m.el.remove(); document.documentElement.style.overflow = ''; res(out);
      };
    });
  }
  async function bulkToStore(all, ids, done) {
    var rows = ids.map(function (id) { return all.find(function (z) { return String(z.id) === String(id); }); }).filter(Boolean);
    if (!rows.length) return C.toast('Pehle items chunein', true);
    var already = rows.filter(function (x) { return ((x.data.store || {}).status) === 'pending'; }), send = rows.filter(function (x) { return ((x.data.store || {}).status) !== 'pending'; });
    if (!send.length) return C.toast('Chune hue sab items pehle se Store review me hain', true);
    var upd = send.filter(function (x) { return ((x.data.store || {}).status) === 'published'; }).length, nProj = send.filter(function (x) { return x.data.type === 'project'; }).length;
    var msg = send.length + ' item Online Store Admin ko review ke liye bhejein?' + (nProj ? ' (' + (send.length - nProj) + ' product + ' + nProj + ' project)' : '') +
      (upd ? ' • ' + upd + ' pehle se live hain — unka update review me jayega.' : '') + (already.length ? ' • ' + already.length + ' pehle se review me hain — skip honge.' : '') +
      ' • Store ki photo/video Admin se daali jaati hai (CRM ki photo store par nahi jaati).' + ' Admin check karke Publish karega; seedha live kuch nahi hota.';
    if (!(await C.confirm(msg, 'Haan, bhejein'))) return;
    var oq = await askOnlineQty(send); if (!oq) return;
    C.busy(true); var ok = 0, bad = [];
    try {
      for (var i = 0; i < send.length; i += 4) {
        await Promise.all(send.slice(i, i + 4).map(function (x) { return C.call('crm_to_store', { id: x.id, web: (oq[x.id] || {}).web || 0, app: (oq[x.id] || {}).app || 0 }).then(function () { ok++; }, function (e) { bad.push((x.title || x.id) + ': ' + (e.message || e)); }); }));
      }
    } finally { C.busy(false); }
    C.cache.items = null;
    C.toast(ok + ' item Store Admin ko bhej diye ✔' + (bad.length ? ' · ' + bad.length + ' nahi gaye (' + bad[0] + ')' : ''), !!bad.length);
    done();
  }

  /* ---------- sheet: download for edit / upload edited (updates existing only) ---------- */
  var SH = [['id', 'ID (do not change)'], ['name', 'Name'], ['category', 'Category'], ['price', 'Price'], ['gst', 'GST %'], ['mrp', 'MRP'], ['stock', 'Stock'], ['unit', 'Unit'], ['hsn', 'HSN'], ['brand', 'Brand'], ['sku', 'SKU (do not change)'], ['mpn', 'Model / Part No'], ['subcategory', 'Sub-category'], ['warranty', 'Warranty'], ['desc', 'Khaas baatein']];
  function sheetCols(tp, cost) {
    var c = SH.filter(function (x) { return tp === 'project' ? ['mrp', 'stock', 'brand', 'mpn', 'subcategory', 'warranty'].indexOf(x[0]) < 0 : true; });
    if (cost) c = c.concat([['cost_price', 'Kharid rate'], ['min_price', 'Minimum rate']]); return c;
  }
  /* plain backup sheet (used before bulk delete) — no upload code, so it can never be pushed back by a non-admin */
  function sheetDownload(items, tp, cost, name) {
    if (!window.XLSXLite) return C.toast('Excel tool load nahi hua', true);
    var cols = sheetCols(tp, cost), rows = items.map(function (x) { var d = x.data || {}; return cols.map(function (c) { return c[0] === 'id' ? x.id : c[0] === 'name' ? (d.name || x.title) : (d[c[0]] == null ? '' : d[c[0]]); }); });
    C.download(window.XLSXLite.write([{ name: 'Products', rows: [cols.map(function (c) { return c[1]; })].concat(rows), widths: cols.map(function (c) { return c[0] === 'desc' ? 40 : c[0] === 'name' ? 34 : 16; }) }]), name.toLowerCase() + '-' + C.today() + '.xlsx');
  }
  var COLW = { desc: 40, name: 34, more: 30 };
  function specOf(catName) { var cs = ((window.CRM_CAT || {}).cats || []).filter(function (c) { return c.name === catName; })[0]; return cs ? ((window.CRM_CAT.specs || {})[cs.code] || []) : []; }
  /* "Download sheet for edit": choose filters + columns first → the server remembers exactly which rows/columns were given out */
  async function sheetDownloadDlg(all, tp, cost) {
    if (!window.XLSXLite) return C.toast('Excel tool load nahi hua', true);
    await C.catLoad();
    var base = all.filter(function (x) { return (x.data.type || 'product') === tp; }), cols = sheetCols(tp, cost).filter(function (c) { return c[0] !== 'id' && c[0] !== 'sku'; });
    var cats = {}, brands = {}; base.forEach(function (x) { if (x.data.category) cats[x.data.category] = 1; if (x.data.brand) brands[x.data.brand] = 1; });
    var m = C.modal({ title: 'Download sheet for edit', size: 'wide', body: '<div class="note g" style="margin-bottom:12px">' + C.ic('shield') + ' Sirf utni hi rows aur columns sheet me jayenge jo aap chunenge. Ye sheet kisi ko bhi de sakte hain — wapas upload par sirf <b>yahi rows</b> aur <b>yahi columns</b> badlenge, baaki sab server rok dega. <b>ID aur SKU na badlein.</b> <b data-cnt></b></div><div class="fg">' +
      C.f('Category', '<select class="inp" data-s="cat"><option value="">Saari categories</option>' + Object.keys(cats).sort().map(function (k) { return '<option>' + esc(k) + '</option>'; }).join('') + '</select>') + C.f('Sub-category', '<select class="inp" data-s="sub"><option value="">Saari</option></select>') +
      C.f('Brand', '<select class="inp" data-s="brand"><option value="">Saare brands</option>' + Object.keys(brands).sort().map(function (k) { return '<option>' + esc(k) + '</option>'; }).join('') + '</select>') + C.f('Store status', '<select class="inp" data-s="store"><option value="">Sab</option><option value="none">Sirf CRM</option><option value="pending">Store review me</option><option value="published">Store par live</option><option value="rejected">Lautaye</option></select>') +
      C.f('Stock', '<select class="inp" data-s="stock"><option value="">Sab</option><option value="out">Khatam (0)</option><option value="low">Kam (5 se kam)</option><option value="has">Stock hai</option><option value="none">Stock track nahi</option></select>') + C.f('Status', '<select class="inp" data-s="st"><option value="">Sab</option><option value="active">Chalu</option><option value="inactive">Band</option></select>') +
      C.f('Khojein', '<input class="inp" type="search" data-s="q" placeholder="naam / SKU / brand">', 'full') + '</div><div class="sec-t" style="margin-top:12px">Kaun se columns badalne hain? <span class="o">(ID aur SKU hamesha rahenge)</span></div><div class="row wrap" id="colb" style="gap:6px 14px">' + cols.map(function (c) { return '<label class="ck" style="margin:0"><input type="checkbox" data-c="' + c[0] + '"' + (['name', 'price', 'gst', 'mrp', 'stock', 'brand', 'subcategory', 'category', 'mpn', 'hsn', 'unit', 'desc', 'warranty'].indexOf(c[0]) >= 0 ? ' checked' : '') + '> ' + esc(c[1]) + '</label>'; }).join('') + '</div><div id="specb"></div>',
      foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('download') + ' Download sheet</button>' });
    function pick() {
      var g = function (k) { return $('[data-s=' + k + ']', m.el).value; }, q = g('q').toLowerCase().trim(), cat = g('cat'), sub = g('sub'), br = g('brand'), stt = g('store'), sk = g('stock'), st = g('st');
      return base.filter(function (x) {
        var d = x.data, n = d.stock == null ? null : num(d.stock);
        return (!cat || C.itemInCat(x, cat)) && (!sub || d.subcategory === sub) && (!br || d.brand === br) && (!stt || ((d.store || {}).status || 'none') === stt) && (!st || (x.status || 'active') === st) &&
          (!sk || (sk === 'none' ? n == null : sk === 'has' ? n != null && n > 0 : sk === 'out' ? n != null && n <= 0 : n != null && n > 0 && n < 5)) && (!q || (x.title + ' ' + (d.sku || '') + ' ' + (d.brand || '') + ' ' + (d.mpn || '')).toLowerCase().indexOf(q) >= 0);
      });
    }
    function refresh() {
      var cat = $('[data-s=cat]', m.el).value, sb = $('[data-s=sub]', m.el), cur = sb.value, subs = {}; base.forEach(function (x) { if ((!cat || C.itemInCat(x, cat)) && x.data.subcategory) subs[x.data.subcategory] = 1; });
      if (sb.getAttribute('data-for') !== cat) { sb.innerHTML = '<option value="">Saari</option>' + Object.keys(subs).sort().map(function (k) { return '<option>' + esc(k) + '</option>'; }).join(''); sb.setAttribute('data-for', cat); sb.value = ''; }
      var sp = tp === 'project' || !cat ? [] : specOf(cat), box = $('#specb', m.el);
      if (box.getAttribute('data-for') !== cat) { box.setAttribute('data-for', cat); box.innerHTML = sp.length ? '<div class="sec-t" style="margin-top:12px">Specification columns — ' + esc(cat) + '</div><div class="row wrap" style="gap:6px 14px">' + sp.map(function (k) { return '<label class="ck" style="margin:0"><input type="checkbox" data-c="spec:' + esc(k) + '" checked> ' + esc(k) + '</label>'; }).join('') + '</div>' : (cat ? '' : '<p class="hint" style="margin-top:8px">Specification columns ke liye ek category chunein.</p>'); }
      var n = pick().length; $('[data-cnt]', m.el).textContent = n + ' rows'; $('[data-ok]', m.el).disabled = !n || !$$('[data-c]:checked', m.el).length;
    }
    m.el.addEventListener('input', refresh); m.el.addEventListener('change', refresh); refresh();
    $('[data-ok]', m.el).onclick = async function () {
      var rows = pick(), ck = $$('[data-c]:checked', m.el).map(function (c) { return c.getAttribute('data-c'); }); if (!rows.length || !ck.length) return;
      var fd = []; ['cat', 'sub', 'brand', 'store', 'stock', 'st', 'q'].forEach(function (k) { var v = $('[data-s=' + k + ']', m.el).value; if (v) fd.push(k + '=' + v); });
      try {
        var iss = await C.run('crm_sheet_issue', { kind: 'item', ids: rows.map(function (x) { return x.id; }), cols: ck, filt: { f: fd }, fdesc: fd.join(', ') }, null);
        var head = ['ID (do not change)', 'SKU (do not change)'], keys = ck.slice(); cols.forEach(function (c) { if (ck.indexOf(c[0]) >= 0) head.push(c[1]); }); var ord = cols.map(function (c) { return c[0]; }).filter(function (k) { return ck.indexOf(k) >= 0; }); keys = ord.concat(ck.filter(function (k) { return /^spec:/.test(k); }));
        keys.filter(function (k) { return /^spec:/.test(k); }).forEach(function (k) { head.push('Spec: ' + k.slice(5)); });
        var data = rows.map(function (x) { var d = x.data || {}; return [x.id, d.sku || ''].concat(keys.map(function (k) { return /^spec:/.test(k) ? ((d.specs || {})[k.slice(5)] || '') : k === 'name' ? (d.name || x.title) : (d[k] == null ? '' : d[k]); })); });
        var meta = [['SPSHEET', iss.code], ['kind', 'item'], ['rows', iss.n], ['columns', keys.join(' | ')], ['expires', String(iss.expires_at).slice(0, 10)], ['note', 'Ye sheet "Upload edited sheet" se hi wapas jayegi. ID/SKU na badlein. Sirf upar ki rows aur columns badlenge.']];
        C.download(window.XLSXLite.write([{ name: 'Products', rows: [head].concat(data), widths: head.map(function (h, i) { return i > 1 && /Khaas baatein/.test(h) ? 40 : /Name/.test(h) ? 34 : 16; }) }, { name: '_sp', rows: meta, widths: [14, 60] }]), 'products-for-edit-' + C.today() + '.xlsx');
        m.close(); C.toast(rows.length + ' rows ki sheet ban gayi ✔ (code ' + iss.code + ', 30 din tak chalegi)');
      } catch (e) {}
    };
  }
  async function sheetListDlg() {
    var ls = await C.call('crm_sheet_list', {});
    var m = C.modal({ title: 'Download ki hui sheets', size: 'wide', body: ls.length ? '<div class="list">' + ls.map(function (z) { return '<div class="li"><span class="av ' + (z.live ? '' : 'g') + '">' + C.ic('download') + '</span><span class="grow"><span class="t">' + esc(z.code) + ' ' + C.pill(z.live ? 'Chalu' : (z.revoked ? 'Band' : 'Expire'), z.live ? '' : 'g') + '</span><span class="m"><span>' + z.n + ' rows</span><span>' + esc(z.issuer || '') + '</span><span>' + esc(C.fdt(z.created_at)) + '</span><span>Upload: ' + z.uses + ' bar</span>' + (z.filt && z.filt.f && z.filt.f.length ? '<span>' + esc(z.filt.f.join(', ')) + '</span>' : '') + '</span></span>' + (z.live ? '<button class="btn btn-r btn-sm" data-rv="' + esc(z.code) + '">Band karein</button>' : '') + '</div>'; }).join('') + '</div>' : C.empty('download', 'Abhi koi sheet nahi', ''), foot: '<button class="btn btn-o" data-close>Band</button>' });
    m.el.addEventListener('click', async function (e) { var b = e.target.closest('[data-rv]'); if (!b) return; if (!(await C.confirm('Ye sheet band kar dein? Phir ye upload nahi ho paegi.', 'Haan, band karein', true))) return; try { await C.run('crm_sheet_revoke', { code: b.getAttribute('data-rv') }, 'Sheet band ho gayi ✔'); m.close(); sheetListDlg(); } catch (er) {} });
  }
  function sheetUpload(tp, cost, done) {
    var m = C.modal({ title: 'Upload edited sheet', body: '<div class="note g" style="margin-bottom:12px">' + C.ic('shield') + ' Sirf wahi sheet chalegi jo <b>"Download sheet for edit"</b> se bani ho (usme secret code hota hai). Sirf <b>pehle se maujood</b> products badlenge — sheet ke bahar ki row ya column server rok dega. Khaali cell = purani value rahegi.</div><input type="file" class="inp" id="xf" accept=".xlsx"><p class="sm b" id="xp" style="margin-top:8px"></p><button class="btn btn-g btn-sm" type="button" data-lst>' + C.ic('clock') + ' Download ki hui sheets / band karein</button>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok disabled>Update products</button>' }), rows = [], unknown = 0, code = '';
    $('[data-lst]', m.el).onclick = function () { sheetListDlg(); };
    $('#xf', m.el).onchange = async function () {
      try {
        var f = this.files[0]; if (!f) return; if (!/\.xlsx$/i.test(f.name)) throw new Error('Sirf .xlsx sheet chalegi (jo Download sheet for edit se mili ho)');
        var wb = await window.XLSXLite.read(await f.arrayBuffer()), meta = wb._sp || [], data = wb.Products || wb[Object.keys(wb)[0]] || [];
        code = ''; (meta || []).forEach(function (r) { if (String(r[0]) === 'SPSHEET') code = String(r[1] || '').trim(); });
        if (!code) throw new Error('Is sheet me secret code nahi hai — pehle "Download sheet for edit" se file lein');
        var head = (data[0] || []).map(function (x) { return String(x || '').toLowerCase().trim(); }), cols = sheetCols(tp, cost), ix = {}, sx = {};
        cols.forEach(function (c) { ix[c[0]] = head.indexOf(c[1].toLowerCase()); if (ix[c[0]] < 0) ix[c[0]] = head.indexOf(c[0]); });
        head.forEach(function (h, i) { if (/^spec: /.test(h)) sx[(data[0][i] + '').trim().slice(6)] = i; });
        if (ix.id < 0) throw new Error('ID column nahi mila — pehle "Download sheet for edit" se file lein');
        rows = []; unknown = 0; var seen = {}, have = {}; (C.cache.items || []).forEach(function (x) { have[x.id] = 1; });
        data.slice(1).forEach(function (r) {
          var id = String(r[ix.id] == null ? '' : r[ix.id]).trim(); if (!id) return; if (seen[id] || !have[id]) { unknown++; return; } seen[id] = 1;
          var set = {}; cols.forEach(function (c) { var k = c[0]; if (k === 'id' || k === 'sku' || ix[k] < 0) return; var v = r[ix[k]]; if (v == null || String(v).trim() === '') return; v = String(v).trim();
            if (['price', 'gst', 'mrp', 'stock', 'cost_price', 'min_price'].indexOf(k) >= 0) { if (isNaN(parseFloat(v))) return; v = num(v); } set[k] = v; });
          var sp = {}; Object.keys(sx).forEach(function (k) { var v = r[sx[k]]; if (v != null && String(v).trim() !== '') sp[k] = String(v).trim(); }); if (Object.keys(sp).length) set.specs = sp;
          if (Object.keys(set).length) rows.push({ id: id, set: set });
        });
        $('#xp', m.el).innerHTML = rows.length + ' products update honge (code ' + esc(code) + ')' + (unknown ? ' · <span style="color:var(--red)">' + unknown + ' row skip (ID list me nahi / dohri — nayi row add nahi hoti)</span>' : ''); $('[data-ok]', m.el).disabled = !rows.length;
      } catch (e) { rows = []; $('[data-ok]', m.el).disabled = true; $('#xp', m.el).innerHTML = '<span style="color:var(--red)">' + esc(e.message || 'File padh nahi paye') + '</span>'; C.toast(e.message || 'File padh nahi paye', true); }
    };
    $('[data-ok]', m.el).onclick = async function () {
      var upd = 0, skip = unknown, outside = 0, blocked = 0; C.busy(true);
      try { for (var i = 0; i < rows.length; i += 400) { var r = await C.call('crm_items_bulk_update', { code: code, rows: rows.slice(i, i + 400) }); upd += r.updated; skip += (r.skipped || []).length; outside += r.outside || 0; blocked += r.blocked || 0; } } catch (e) { C.busy(false); return C.toast(e.message, true); }
      C.busy(false); C.cache.items = null; m.close(); C.toast(upd + ' products update ho gaye' + (skip ? ' · ' + skip + ' skip' : '') + (outside ? ' · ' + outside + ' row sheet ke bahar (roki gayi)' : '') + (blocked ? ' · ' + blocked + ' cell roke gaye' : '') + ' ✔'); done();
    };
  }
  /* ---------- bulk delete: always saves a backup sheet first ---------- */
  async function deleteByCategory(all, tp, cost, done) {
    var items = all.filter(function (x) { return (x.data.type || 'product') === tp; }), cnt = {};
    items.forEach(function (x) { var c = x.data.category; if (c) cnt[c] = (cnt[c] || 0) + 1; });
    var names = Object.keys(cnt).sort(); if (!names.length) return C.toast('Koi category nahi hai', true);
    var m = C.modal({ title: 'Delete category-wise', body: '<div class="note r" style="margin-bottom:12px">Chuni hui category ke saare ' + (tp === 'project' ? 'projects' : 'products') + ' hat jayenge. Pehle backup sheet apne aap download hogi.</div>' + C.f('Category', '<select class="inp" id="dc">' + names.map(function (n) { return '<option value="' + esc(n) + '">' + esc(n) + ' (' + cnt[n] + ')</option>'; }).join('') + '</select>'), foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-r" data-ok>' + C.ic('trash') + ' Delete</button>' });
    $('[data-ok]', m.el).onclick = async function () {
      var cat = $('#dc', m.el).value, sel = items.filter(function (x) { return C.itemInCat(x, cat); }); if (!(await C.confirm('"' + cat + '" ke ' + sel.length + ' items delete karein?', 'Haan, delete', true))) return;
      sheetDownload(sel, tp, cost, 'backup-' + cat.replace(/[^A-Za-z0-9]+/g, '-'));
      try { var r = await C.run('crm_items_bulk_delete', { scope: 'category', category: cat, type: tp }, null); C.cache.items = null; m.close(); C.toast(r.deleted + ' items delete ho gaye ✔'); done(); } catch (e) {}
    };
  }
  async function deleteAll(list, tp, cost, done) {
    if (!(await C.confirm('Saare ' + list.length + ' ' + (tp === 'project' ? 'projects' : 'products') + ' delete karein? Pehle backup sheet download hogi.', 'Aage badhein', true))) return;
    var t = await C.ask('Delete all', 'Confirm karne ke liye DELETE likhein', { ok: 'Delete all' }); if (t == null) return;
    if (String(t).trim() !== 'DELETE') return C.toast('DELETE sahi likhein', true);
    sheetDownload(list, tp, cost, 'backup-all-' + tp);
    try { var r = await C.run('crm_items_bulk_delete', { scope: 'all', type: tp }, null); C.cache.items = null; C.toast(r.deleted + ' items delete ho gaye ✔'); done(); } catch (e) {}
  }
  function itemInfo(x) {
    var d = x.data, sp = C.specPairs(d.specs);
    C.modal({ title: x.title, body: '<div class="row" style="margin-bottom:10px"><b style="font-size:22px">' + money(d.price) + '</b><span class="mute">+ GST ' + esc(d.gst || 0) + '%</span>' + (d.stock != null ? C.pill('Stock: ' + d.stock) : '') + '</div>' + (C.specLine(d) ? '<p class="mute" style="margin:0 0 8px">' + esc(C.specLine(d)) + '</p>' : '') + (C.lines(d.desc).length ? '<ol style="margin:0;padding-left:20px">' + C.lines(d.desc).map(function (l) { return '<li>' + esc(l) + '</li>'; }).join('') + '</ol>' : '') + (sp.length ? '<table class="kv" style="margin-top:10px;width:100%">' + sp.map(function (p) { return '<tr><td>' + esc(p[0]) + '</td><td><b>' + esc(p[1]) + '</b></td></tr>'; }).join('') + '</table>' : '') + ((d.proj_items || []).length ? '<div class="sec-t">Shamil</div><ul style="margin:0;padding-left:20px">' + d.proj_items.map(function (p) { return '<li>' + esc((p.title ? p.title + ' – ' : '') + p.name) + ' × ' + esc(p.qty) + '</li>'; }).join('') + '</ul>' : '') });
  }
})();
