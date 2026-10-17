/* Sunpowers Admin — 📊 Dashboards (Round 15): Website + Shop page, Online Store, and a Website-vs-Store comparison.
   One RPC (sp_admin_analytics) feeds everything; charts are small dependency-free SVG helpers.
   SPDASH.mount(host, { kind:'web'|'store'|'compare', rpc, pass, toast, productTitle(id) })                                  */
(function () {
  'use strict';
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var CW = '#2f6fdb', CS = '#e0742c', CP = '#7b4fd1', CG = '#2a9d5c', CR = '#d64545', CT = '#12a5a5', CY = '#d4a017';   /* fixed hues: they must not change with the panel theme */
  var PAL = [CW, CS, CP, CG, CT, CY, CR, '#6b7a70'];
  var RANGES = [[1, 'आज'], [7, '7 दिन'], [30, '30 दिन'], [90, '90 दिन'], [365, '1 साल']];
  var SRC = { direct: 'सीधे (Direct)', google: 'Google', facebook: 'Facebook', instagram: 'Instagram', whatsapp: 'WhatsApp', youtube: 'YouTube', website: 'वेबसाइट से', shop: 'Shop पेज से', other: 'अन्य' };
  var PAGES = { 'index.html': 'होम', 'about.html': 'About', 'services.html': 'Products & Services', 'shop.html': '🛍️ Shop पेज', 'contact.html': 'Contact', 'blueprint.html': 'Blue Print', 'calculator.html': 'Calculator', 'error-detector.html': 'Error Detector', 'subsidy.html': 'Subsidy', 'finance.html': 'Finance', 'faq.html': 'FAQ', 'experts.html': 'Experts', 'solar-maintenance-audit.html': 'Maintenance & Audit',
    home: 'होम', categories: 'कैटेगरी', cart: '🛒 कार्ट', account: 'अकाउंट', help: 'मदद', wishlist: 'पसंद', blueprint: 'Blue Print', done: '✅ ऑर्डर पूरा' };
  function n0(v) { return (Math.round(+v || 0)).toLocaleString('en-IN'); }
  function rs(v) { v = +v || 0; var a = Math.abs(v); if (a >= 1e7) return '₹' + (v / 1e7).toFixed(2).replace(/\.?0+$/, '') + ' Cr'; if (a >= 1e5) return '₹' + (v / 1e5).toFixed(2).replace(/\.?0+$/, '') + ' L'; return '₹' + n0(v); }
  function pct(a, b) { return b > 0 ? Math.round(a / b * 1000) / 10 : 0; }
  function delta(cur, prev) { cur = +cur || 0; prev = +prev || 0; if (!prev && !cur) return { t: '—', c: '' }; if (!prev) return { t: 'नया', c: 'up' }; var d = Math.round((cur - prev) / prev * 100); if (d > 999) return { t: '▲ 999%+', c: 'up' }; return { t: (d > 0 ? '▲ ' : d < 0 ? '▼ ' : '● ') + Math.abs(d) + '%', c: d > 0 ? 'up' : d < 0 ? 'dn' : '' }; }
  function pageName(p) {
    p = String(p || ''); if (PAGES[p]) return PAGES[p];
    if (/^product\//.test(p)) { var id = p.slice(8); var t = SPDASH.productTitle && SPDASH.productTitle(id); return '📦 ' + (t || id); }
    if (/^section\//.test(p)) return '🗂️ सेक्शन ' + p.slice(8); if (/^page\//.test(p)) return '📄 ' + p.slice(5);
    return p.replace(/\.html$/, '').replace(/-/g, ' ');
  }
  function srcName(s) { return SRC[s] || s; }

  /* ---------- charts ---------- */
  function empty(h) { return '<div class="ds-empty" style="height:' + (h || 140) + 'px">अभी डेटा नहीं — आने पर यहाँ दिखेगा</div>'; }
  function niceMax(m) { if (m <= 5) return 5; var p = Math.pow(10, Math.floor(Math.log10(m))), f = m / p; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p; }
  function line(days, series, o) {
    o = o || {}; var W = 640, H = o.h || 200, pl = 40, pr = 10, pt = 12, pb = 26, n = days.length; if (!n) return empty(H);
    var max = 0; series.forEach(function (s) { days.forEach(function (d) { max = Math.max(max, +d[s.k] || 0); }); }); if (!max) return empty(H); max = niceMax(max);
    var iw = W - pl - pr, ih = H - pt - pb, x = function (i) { return pl + (n === 1 ? iw / 2 : iw * i / (n - 1)); }, y = function (v) { return pt + ih - ih * v / max; };
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" class="ds-svg" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    for (var g = 0; g <= 4; g++) { var yy = pt + ih - ih * g / 4; svg += '<line x1="' + pl + '" x2="' + (W - pr) + '" y1="' + yy + '" y2="' + yy + '" class="ds-grid"/><text x="' + (pl - 6) + '" y="' + (yy + 4) + '" text-anchor="end" class="ds-ax">' + (o.money ? rs(max * g / 4) : n0(max * g / 4)) + '</text>'; }
    var step = Math.max(1, Math.ceil(n / 7)); days.forEach(function (d, i) { if (i % step === 0 || i === n - 1) svg += '<text x="' + x(i) + '" y="' + (H - 8) + '" text-anchor="middle" class="ds-ax">' + esc(d.d.slice(5).replace('-', '/')) + '</text>'; });
    series.forEach(function (s, si) {
      var pts = days.map(function (d, i) { return x(i).toFixed(1) + ',' + y(+d[s.k] || 0).toFixed(1); });
      if (si === 0 && n > 1) svg += '<polygon points="' + x(0).toFixed(1) + ',' + (pt + ih) + ' ' + pts.join(' ') + ' ' + x(n - 1).toFixed(1) + ',' + (pt + ih) + '" fill="' + s.c + '" opacity=".1"/>';
      svg += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + s.c + '" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"' + (s.dash ? ' stroke-dasharray="6 4"' : '') + '/>';
      days.forEach(function (d, i) { if (n <= 31 || i === n - 1) svg += '<circle cx="' + x(i).toFixed(1) + '" cy="' + y(+d[s.k] || 0).toFixed(1) + '" r="' + (n <= 14 ? 3.4 : 2.4) + '" fill="#fff" stroke="' + s.c + '" stroke-width="2"><title>' + esc(s.n + ' • ' + d.d + ' • ' + (o.money ? rs(d[s.k]) : n0(d[s.k]))) + '</title></circle>'; });
    });
    return '<div class="ds-chart">' + svg + '</svg>' + legend(series) + '</div>';
  }
  function legend(series) { return '<ul class="ds-leg">' + series.map(function (s) { return '<li><i style="background:' + s.c + '"></i>' + esc(s.n) + '</li>'; }).join('') + '</ul>'; }
  function bars(days, series, o) {
    o = o || {}; var W = 640, H = o.h || 200, pl = 40, pr = 6, pt = 12, pb = 26, n = days.length; if (!n) return empty(H);
    var max = 0; series.forEach(function (s) { days.forEach(function (d) { max = Math.max(max, +d[s.k] || 0); }); }); if (!max) return empty(H); max = niceMax(max);
    var iw = W - pl - pr, ih = H - pt - pb, gw = iw / n, bw = Math.max(2, Math.min(26, gw / (series.length + .5)));
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" class="ds-svg" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    for (var g = 0; g <= 4; g++) { var yy = pt + ih - ih * g / 4; svg += '<line x1="' + pl + '" x2="' + (W - pr) + '" y1="' + yy + '" y2="' + yy + '" class="ds-grid"/><text x="' + (pl - 6) + '" y="' + (yy + 4) + '" text-anchor="end" class="ds-ax">' + (o.money ? rs(max * g / 4) : n0(max * g / 4)) + '</text>'; }
    var step = Math.max(1, Math.ceil(n / 8));
    days.forEach(function (d, i) {
      var x0 = pl + gw * i + (gw - bw * series.length) / 2;
      series.forEach(function (s, k) { var v = +d[s.k] || 0, hh = ih * v / max; svg += '<rect x="' + (x0 + bw * k).toFixed(1) + '" y="' + (pt + ih - hh).toFixed(1) + '" width="' + (bw - 1).toFixed(1) + '" height="' + Math.max(hh, v ? 1.5 : 0).toFixed(1) + '" rx="2" fill="' + s.c + '"><title>' + esc(s.n + ' • ' + (o.lab ? o.lab(d.d) : d.d) + ' • ' + (o.money ? rs(v) : n0(v))) + '</title></rect>'; });
      if (i % step === 0 || i === n - 1) svg += '<text x="' + (pl + gw * i + gw / 2).toFixed(1) + '" y="' + (H - 8) + '" text-anchor="middle" class="ds-ax">' + esc(o.axlab ? o.axlab(d.d) : d.d.slice(5).replace('-', '/')) + '</text>';
    });
    return '<div class="ds-chart">' + svg + '</svg>' + legend(series) + '</div>';
  }
  function hours(hs, series) {
    return bars(hs.map(function (h) { return { d: 'h-' + ('0' + h.h).slice(-2), w: h.w, s: h.s }; }), series, { h: 170, label: 'visits by hour', lab: function (d) { return d.slice(2) + ':00'; }, axlab: function (d) { return d.slice(2); } });
  }
  function donut(parts, o) {
    o = o || {}; parts = (parts || []).filter(function (p) { return +p.v > 0; }); var tot = 0; parts.forEach(function (p) { tot += +p.v; }); if (!tot) return empty(150);
    var S = 150, R = 68, r = 44, cx = 75, cy = 75, a0 = -Math.PI / 2, svg = '<svg viewBox="0 0 ' + S + ' ' + S + '" width="' + S + '" height="' + S + '" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    if (parts.length === 1) svg += '<circle cx="75" cy="75" r="56" fill="none" stroke="' + (parts[0].c || PAL[0]) + '" stroke-width="24"/>';
    else parts.forEach(function (p, i) { var a1 = a0 + (+p.v / tot) * Math.PI * 2, lg = a1 - a0 > Math.PI ? 1 : 0, c = function (a, rr) { return (cx + rr * Math.cos(a)).toFixed(2) + ' ' + (cy + rr * Math.sin(a)).toFixed(2); };
      svg += '<path d="M' + c(a0, R) + ' A' + R + ' ' + R + ' 0 ' + lg + ' 1 ' + c(a1, R) + ' L' + c(a1, r) + ' A' + r + ' ' + r + ' 0 ' + lg + ' 0 ' + c(a0, r) + ' Z" fill="' + (p.c || PAL[i % PAL.length]) + '"><title>' + esc(p.l + ' • ' + n0(p.v) + ' (' + Math.round(p.v / tot * 100) + '%)') + '</title></path>'; a0 = a1; });
    svg += '<text x="75" y="73" text-anchor="middle" class="ds-big">' + n0(tot) + '</text><text x="75" y="89" text-anchor="middle" class="ds-ax">' + esc(o.center || 'कुल') + '</text></svg>';
    return '<div class="ds-donut">' + svg + '<ul class="ds-leg col">' + parts.map(function (p, i) { return '<li><i style="background:' + (p.c || PAL[i % PAL.length]) + '"></i><span>' + esc(p.l) + '</span><b>' + n0(p.v) + ' <small>' + Math.round(p.v / tot * 100) + '%</small></b></li>'; }).join('') + '</ul></div>';
  }
  function funnel(f, c) {
    f = f || {}; var st = [['👥 विज़िट', f.visit], ['🛒 कार्ट में डाला', f.cart], ['💳 चेकआउट', f.checkout], ['✅ ऑर्डर', f.order]], top = Math.max(1, +f.visit || 0, +f.cart || 0);
    if (!(+f.visit)) return empty(150);
    return '<div class="ds-fun">' + st.map(function (x, i) { var v = +x[1] || 0, w = Math.max(4, Math.round(v / top * 100)), prev = i ? (+st[i - 1][1] || 0) : 0;
      return '<div class="ds-fr"><span>' + esc(x[0]) + '</span><div class="ds-fb"><i style="width:' + Math.min(100, w) + '%;background:' + c + '"></i></div><b>' + n0(v) + (i && prev ? ' <small>(' + Math.min(100, Math.round(v / prev * 100)) + '%)</small>' : '') + '</b></div>'; }).join('') + '</div>';
  }
  function table(head, rows, o) {
    o = o || {}; if (!rows.length) return '<div class="ds-empty" style="height:80px">अभी डेटा नहीं</div>';
    return '<div class="ds-tw"><table class="ds-t"><thead><tr>' + head.map(function (h, i) { return '<th' + (i ? ' class="r"' : '') + '>' + (/^<span class="ds-dot"/.test(h) ? h : esc(h)) + '</th>'; }).join('') + '</tr></thead><tbody>' + rows.map(function (r) { return '<tr>' + r.map(function (c, i) { return '<td' + (i ? ' class="r"' : '') + '>' + c + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table></div>';
  }
  function tile(ic, label, val, d, sub, c) { return '<div class="ds-k"><div class="ds-ki" style="background:' + c + '1f;color:' + c + '">' + ic + '</div><div class="ds-kb"><small>' + esc(label) + '</small><b>' + val + '</b>' + (d ? '<span class="ds-d ' + d.c + '">' + d.t + ' <em>पिछले ' + (SPDASH.days || 30) + ' दिन से</em></span>' : '') + (sub ? '<span class="ds-s">' + sub + '</span>' : '') + '</div></div>'; }

  var CSS = '.dsh{display:grid;gap:14px}.dsh .ds-card{background:#fff;border:1px solid var(--line,#dce5da);border-radius:16px;padding:14px;min-width:0}.dsh h3{font-size:15.5px;margin:0 0 10px;display:flex;align-items:center;gap:8px;flex-wrap:wrap}.dsh h3 small{font-weight:500;color:var(--mut,#66756a);font-size:12.5px}' +
    '.ds-bar{display:flex;gap:6px;flex-wrap:wrap;align-items:center}.ds-bar .grow{flex:1}.ds-chip{border:1.5px solid var(--line,#dce5da);background:#fff;border-radius:999px;padding:7px 13px;font:700 13px inherit;cursor:pointer}.ds-chip.on{background:var(--g,#1e8e3e);border-color:var(--g,#1e8e3e);color:#fff}' +
    '.ds-kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(168px,1fr));gap:10px}.ds-k{display:flex;gap:10px;align-items:flex-start;background:#fff;border:1px solid var(--line,#dce5da);border-radius:14px;padding:12px;min-width:0}.ds-ki{width:40px;height:40px;border-radius:12px;display:grid;place-items:center;font-size:20px;flex:none}' +
    '.ds-kb{min-width:0;display:flex;flex-direction:column;gap:2px}.ds-kb small{color:var(--mut,#66756a);font-size:12px}.ds-kb b{font-size:22px;line-height:1.1}.ds-d{font-size:12px;font-weight:800}.ds-d em{font-style:normal;font-weight:500;color:var(--mut,#66756a)}.ds-d.up{color:#1b7f3b}.ds-d.dn{color:#c8372d}.ds-s{font-size:12px;color:var(--mut,#66756a)}' +
    '.ds-g2{display:grid;grid-template-columns:1fr 1fr;gap:14px}.ds-g3{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}@media(max-width:900px){.ds-g3{grid-template-columns:1fr 1fr}}@media(max-width:700px){.ds-g2,.ds-g3{grid-template-columns:1fr}}' +
    '.ds-svg{width:100%;height:auto;display:block}.ds-grid{stroke:var(--line,#e2e9e1);stroke-width:1}.ds-ax{font:11px system-ui,sans-serif;fill:#6b7a70}.ds-big{font:800 22px system-ui,sans-serif;fill:currentColor}.ds-leg{display:flex;gap:14px;flex-wrap:wrap;list-style:none;margin:6px 0 0;padding:0;font-size:12.5px}.ds-leg i{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:6px;vertical-align:-1px}' +
    '.ds-leg.col{flex-direction:column;gap:7px;margin:0;flex:1;min-width:0}.ds-leg.col li{display:flex;align-items:center;gap:0}.ds-leg.col span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.ds-leg.col small{color:var(--mut,#66756a);font-weight:500}' +
    '.ds-donut{display:flex;gap:14px;align-items:center;flex-wrap:wrap}.ds-donut svg{flex:none}.ds-empty{display:grid;place-items:center;color:var(--mut,#66756a);font-size:13px;text-align:center;border:1.5px dashed var(--line,#dce5da);border-radius:12px;padding:10px}' +
    '.ds-fun{display:grid;gap:9px}.ds-fr{display:grid;grid-template-columns:118px 1fr 82px;gap:8px;align-items:center;font-size:13px}.ds-fb{height:20px;background:var(--line,#eef2ed);border-radius:6px;overflow:hidden}.ds-fb i{display:block;height:100%;border-radius:6px}.ds-fr b{text-align:right}.ds-fr small{color:var(--mut,#66756a);font-weight:500}' +
    '.ds-tw{overflow-x:auto}.ds-t{width:100%;border-collapse:collapse;font-size:13.5px}.ds-t th{text-align:left;font-size:12px;color:var(--mut,#66756a);font-weight:700;padding:6px 8px;border-bottom:1.5px solid var(--line,#dce5da);white-space:nowrap}.ds-t td{padding:8px;border-bottom:1px solid var(--line,#eef2ed);vertical-align:middle}.ds-t .r{text-align:right;white-space:nowrap}.ds-t tr:last-child td{border-bottom:0}' +
    '.ds-al{display:flex;gap:8px;flex-wrap:wrap}.ds-a{display:flex;gap:8px;align-items:center;border-radius:12px;padding:9px 12px;font-size:13.5px;border:1px solid}.ds-a.r{background:#fdecea;border-color:#f5c2bd;color:#8a1f17}.ds-a.y{background:#fff8e6;border-color:#ffe08a;color:#7a5a00}.ds-a.g{background:#e8f5e9;border-color:#b9d6c3;color:#14622e}' +
    '.ds-win{display:inline-block;background:#1b7f3b;color:#fff;border-radius:999px;font-size:11px;padding:2px 8px;margin-left:6px;font-weight:700}.ds-v{margin:0;padding-left:18px;display:grid;gap:6px;font-size:14px}.ds-note{font-size:12.5px;color:var(--mut,#66756a);margin-top:8px}' +
    '.ds-dot{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px}@media(max-width:520px){.ds-fr{grid-template-columns:96px 1fr 70px}.ds-kb b{font-size:19px}}';
  function cssOnce() { if (document.getElementById('ds-css')) return; var s = document.createElement('style'); s.id = 'ds-css'; s.textContent = CSS; document.head.appendChild(s); }

  /* ---------- views ---------- */
  function alertItems(D, kind) {
    var a = D.alerts || {}, out = [], cw = D.cur.website || {}, cs = D.cur.store || {}, pw = D.prev.website || {}, ps = D.prev.store || {};
    if (a.orders_new) out.push(['r', '📦 ' + a.orders_new + ' नया ऑर्डर अभी "नया" स्थिति में है' + (a.orders_old ? ' (' + a.orders_old + ' ऑर्डर 24 घंटे से ज़्यादा पुराने!)' : '')]);
    if (a.enquiries_new) out.push([a.enquiries_old ? 'r' : 'y', '📞 ' + a.enquiries_new + ' पूछताछ का जवाब बाकी' + (a.enquiries_old ? ' — ' + a.enquiries_old + ' 24 घंटे से ज़्यादा पुरानी' : '')]);
    function drop(nm, c, p) { if ((+p.visitors || 0) >= 10 && (+c.visitors || 0) < (+p.visitors) * .6) out.push(['y', '📉 ' + nm + ' की विज़िट पिछली अवधि से ' + Math.round((1 - c.visitors / p.visitors) * 100) + '% कम है']); }
    if (kind !== 'store') drop('वेबसाइट', cw, pw); if (kind !== 'web') drop('स्टोर', cs, ps);
    function nosale(nm, c) { if ((+c.visitors || 0) >= 30 && !(+c.orders)) out.push(['y', '🛒 ' + nm + ' पर ' + c.visitors + ' विज़िटर आए पर कोई ऑर्डर नहीं — प्राइस / ऑफ़र जाँचें']); }
    if (kind !== 'store') nosale('वेबसाइट/Shop', cw); if (kind !== 'web') nosale('स्टोर', cs);
    if (!(+a.events_total)) out.push(['y', 'ℹ️ अभी ट्रैकिंग का डेटा नहीं आया — वेबसाइट/स्टोर नए वर्शन पर चलने के बाद विज़िट यहाँ दिखने लगेंगी। (ऑर्डर और पूछताछ पहले से गिने जाते हैं।)']);
    if (!out.length) out.push(['g', '✅ सब ठीक है — कोई अलर्ट नहीं']);
    return out;
  }
  function alerts(D, kind) {
    var out = alertItems(D, kind);
    return '<div class="ds-al">' + out.map(function (x) { return '<div class="ds-a ' + x[0] + '">' + x[1] + '</div>'; }).join('') + '</div>';
  }
  function siteKey(kind) { return kind === 'store' ? 'store' : 'website'; }
  function csv(D, kind) {
    var rows = [['date', 'website_visitors', 'shop_page_views', 'website_orders', 'website_sales', 'store_visitors', 'store_orders', 'store_sales']];
    (D.days || []).forEach(function (d) { rows.push([d.d, d.wv, d.shv, d.wo, d.wsale, d.sv, d.so, d.ssale]); });
    return rows.map(function (r) { return r.join(','); }).join('\n');
  }
  function sections(D, kind) {
    var site = siteKey(kind), cur = D.cur[site] || {}, prev = D.prev[site] || {}, isW = kind === 'web', days = D.days || [];
    var conv = pct(cur.orders, cur.visitors), pconv = pct(prev.orders, prev.visitors), col = isW ? CW : CS;
    var h = '<div class="ds-kpis">' + tile('👥', 'विज़िटर (यूनिक)', n0(cur.visitors), delta(cur.visitors, prev.visitors), '', col) + tile('👁', 'पेज व्यू', n0(cur.views), delta(cur.views, prev.views), '', CP) +
      (isW ? tile('🛍️', 'Shop पेज विज़िटर', n0(cur.shop_visitors), null, n0(cur.shop_views) + ' व्यू', CS) : tile('🛒', 'कार्ट में डाले', n0(cur.carts), null, '', CS)) +
      (isW ? tile('🛒', 'कार्ट में डाले', n0(cur.carts), null, '', CT) : tile('🔎', 'सर्च', n0(cur.searches), null, '', CT)) +
      tile('📞', 'पूछताछ (Enquiry)', n0(cur.enquiries), delta(cur.enquiries, prev.enquiries), '', CY) + tile('📦', 'ऑर्डर', n0(cur.orders), delta(cur.orders, prev.orders), isW ? 'वेबसाइट/Shop से आए' : '', CG) +
      tile('💰', 'सेल (₹)', rs(cur.sales), delta(cur.sales, prev.sales), cur.orders ? 'औसत ' + rs(cur.sales / cur.orders) + ' / ऑर्डर' : '', CG) + tile('🎯', 'कन्वर्ज़न', conv + '%', delta(conv, pconv), 'ऑर्डर ÷ विज़िटर', CR) + tile('📱', 'मोबाइल विज़िटर', cur.visitors ? pct(cur.mobile, cur.visitors) + '%' : '—', null, n0(cur.mobile) + ' मोबाइल', CP) + '</div>';
    var s1 = isW ? [{ k: 'wv', n: 'वेबसाइट विज़िटर', c: CW }, { k: 'shv', n: 'Shop पेज व्यू', c: CP, dash: 1 }] : [{ k: 'sv', n: 'स्टोर विज़िटर', c: CS }];
    var s2 = isW ? [{ k: 'wo', n: 'ऑर्डर', c: CG }] : [{ k: 'so', n: 'ऑर्डर', c: CG }], s3 = isW ? [{ k: 'wsale', n: 'सेल ₹', c: CW }] : [{ k: 'ssale', n: 'सेल ₹', c: CS }];
    h += '<div class="ds-card"><h3>📈 रोज़ के विज़िटर <small>' + (D.range.from + ' से ' + D.range.to) + '</small></h3>' + line(days, s1, { label: 'visitors per day' }) + '</div>';
    h += '<div class="ds-g2"><div class="ds-card"><h3>📦 रोज़ के ऑर्डर</h3>' + bars(days, s2, { h: 170, label: 'orders per day' }) + '</div><div class="ds-card"><h3>💰 रोज़ की सेल</h3>' + bars(days, s3, { h: 170, money: 1, label: 'sales per day' }) + '</div></div>';
    var srcs = (D.sources || []).filter(function (x) { return x.site === site; }).map(function (x, i) { return { l: srcName(x.src), v: x.visitors, c: PAL[i % PAL.length] }; });
    h += '<div class="ds-g2"><div class="ds-card"><h3>🧭 ट्रैफ़िक कहाँ से आया</h3>' + donut(srcs, { center: 'विज़िटर' }) + '</div><div class="ds-card"><h3>🔻 कन्वर्ज़न फ़नल</h3>' + funnel((D.funnel || {})[site], col) + '<p class="ds-note">विज़िट → कार्ट → चेकआउट → ऑर्डर: हर स्टेप पर कितने लोग बचे।</p></div></div>';
    h += '<div class="ds-g2"><div class="ds-card"><h3>🕒 किस घंटे सबसे ज़्यादा विज़िट <small>(IST)</small></h3>' + hours(D.hours || [], isW ? [{ k: 'w', n: 'वेबसाइट', c: CW }] : [{ k: 's', n: 'स्टोर', c: CS }]) + '</div><div class="ds-card"><h3>📱 डिवाइस</h3>' +
      donut([{ l: 'मोबाइल', v: cur.mobile || 0, c: CP }, { l: 'डेस्कटॉप', v: Math.max(0, (cur.visitors || 0) - (cur.mobile || 0)), c: CT }], { center: 'विज़िटर' }) + '</div></div>';
    var pg = (D.pages || []).filter(function (x) { return x.site === site; }).slice(0, 12);
    h += '<div class="ds-g2"><div class="ds-card"><h3>📄 टॉप पेज</h3>' + table(['पेज', 'व्यू', 'विज़िटर'], pg.map(function (x) { return [esc(pageName(x.page)), n0(x.views), n0(x.visitors)]; })) + '</div>';
    var ck = (D.clicks || []).filter(function (x) { return x.site === site; }).slice(0, 12);
    h += '<div class="ds-card"><h3>👆 सबसे ज़्यादा दबे बटन / लिंक</h3>' + table(['बटन', 'पेज', 'क्लिक'], ck.map(function (x) { return [esc(x.label), '<small>' + esc(pageName(x.page)) + '</small>', n0(x.n)]; })) + '</div></div>';
    var se = (D.searches || []).filter(function (x) { return x.site === site; }).slice(0, 10);
    var tp = D.top_products || [];
    h += '<div class="ds-g2"><div class="ds-card"><h3>🔎 लोग क्या खोज रहे हैं</h3>' + table(['शब्द', 'बार'], se.map(function (x) { return [esc(x.label), n0(x.n)]; })) + '</div><div class="ds-card"><h3>🏆 सबसे ज़्यादा बिकने वाले प्रोडक्ट</h3>' + table(['प्रोडक्ट', 'नग', 'रकम'], tp.slice(0, 10).map(function (x) { return [esc(x.title), n0(x.qty), rs(x.amount)]; })) + '<p class="ds-note">(दोनों जगह के ऑर्डर मिलाकर)</p></div></div>';
    var ro = (D.recent_orders || []).filter(function (x) { return x.site === site; });
    h += '<div class="ds-card"><h3>🧾 हाल के ऑर्डर</h3>' + table(['ऑर्डर', 'कब', 'ग्राहक', 'स्थिति', 'रकम'], ro.map(function (x) { return [esc(x.order_no || '#' + x.id), esc(x.at), esc(x.name || ''), esc(x.status), rs(x.total)]; })) + '</div>';
    return h;
  }
  function compare(D) {
    var w = D.cur.website || {}, s = D.cur.store || {}, pw = D.prev.website || {}, ps = D.prev.store || {};
    var rows = [['👥 विज़िटर', w.visitors, s.visitors, n0], ['👁 पेज व्यू', w.views, s.views, n0], ['🛒 कार्ट में डाले', w.carts, s.carts, n0], ['📞 पूछताछ', w.enquiries, s.enquiries, n0], ['📦 ऑर्डर', w.orders, s.orders, n0], ['💰 सेल', w.sales, s.sales, rs], ['🎯 कन्वर्ज़न %', pct(w.orders, w.visitors), pct(s.orders, s.visitors), function (v) { return v + '%'; }], ['🧾 औसत ऑर्डर', w.orders ? w.sales / w.orders : 0, s.orders ? s.sales / s.orders : 0, rs]];
    var h = '<div class="ds-card"><h3>⚔️ वेबसाइट + Shop बनाम ऑनलाइन स्टोर</h3>' + table(['पैमाना', '<span class="ds-dot" style="background:' + CW + '"></span>वेबसाइट + Shop', '<span class="ds-dot" style="background:' + CS + '"></span>स्टोर'], rows.map(function (r) {
      var a = +r[1] || 0, b = +r[2] || 0, f = r[3]; return [r[0], f(a) + (a > b ? '<span class="ds-win">आगे</span>' : ''), f(b) + (b > a ? '<span class="ds-win">आगे</span>' : '')]; })) + '</div>';
    var v = [];
    if ((w.visitors || 0) + (s.visitors || 0) > 0) v.push((w.visitors >= s.visitors ? '👥 <b>वेबसाइट</b>' : '👥 <b>स्टोर</b>') + ' पर ज़्यादा विज़िट आ रही है (' + n0(w.visitors) + ' बनाम ' + n0(s.visitors) + ').');
    if ((w.sales || 0) + (s.sales || 0) > 0) v.push((w.sales >= s.sales ? '💰 <b>वेबसाइट/Shop</b>' : '💰 <b>स्टोर</b>') + ' से ज़्यादा सेल हुई (' + rs(w.sales) + ' बनाम ' + rs(s.sales) + ').');
    var cw = pct(w.orders, w.visitors), cs = pct(s.orders, s.visitors); if (cw || cs) v.push('🎯 विज़िटर को ग्राहक में बदलने में <b>' + (cw >= cs ? 'वेबसाइट' : 'स्टोर') + '</b> बेहतर है (' + cw + '% बनाम ' + cs + '%).');
    if ((w.enquiries || 0) > (s.enquiries || 0)) v.push('📞 पूछताछ ज़्यादातर <b>वेबसाइट</b> से आ रही है — वहाँ फ़ॉलो-अप तेज़ रखें.');
    if (!v.length) v.push('अभी तुलना के लिए डेटा नहीं है — कुछ दिन बाद यहाँ साफ़ दिखेगा.');
    h += '<div class="ds-card"><h3>🧠 निष्कर्ष</h3><ul class="ds-v">' + v.map(function (x) { return '<li>' + x + '</li>'; }).join('') + '</ul><p class="ds-note">नोट: "वेबसाइट/Shop की सेल" = वो ऑर्डर जो वेबसाइट या Shop पेज से स्टोर पर पहुँचकर पूरे हुए।</p></div>';
    h += '<div class="ds-card"><h3>📈 रोज़ के विज़िटर — वेबसाइट बनाम स्टोर</h3>' + line(D.days, [{ k: 'wv', n: 'वेबसाइट', c: CW }, { k: 'sv', n: 'स्टोर', c: CS, dash: 1 }]) + '</div>';
    h += '<div class="ds-g2"><div class="ds-card"><h3>📦 रोज़ के ऑर्डर</h3>' + bars(D.days, [{ k: 'wo', n: 'वेबसाइट/Shop', c: CW }, { k: 'so', n: 'स्टोर', c: CS }], { h: 170 }) + '</div><div class="ds-card"><h3>💰 रोज़ की सेल</h3>' + bars(D.days, [{ k: 'wsale', n: 'वेबसाइट/Shop', c: CW }, { k: 'ssale', n: 'स्टोर', c: CS }], { h: 170, money: 1 }) + '</div></div>';
    h += '<div class="ds-g2"><div class="ds-card"><h3>🔻 वेबसाइट फ़नल</h3>' + funnel((D.funnel || {}).website, CW) + '</div><div class="ds-card"><h3>🔻 स्टोर फ़नल</h3>' + funnel((D.funnel || {}).store, CS) + '</div></div>';
    h += '<div class="ds-g2"><div class="ds-card"><h3>🧭 वेबसाइट का ट्रैफ़िक</h3>' + donut((D.sources || []).filter(function (x) { return x.site === 'website'; }).map(function (x, i) { return { l: srcName(x.src), v: x.visitors, c: PAL[i % PAL.length] }; }), { center: 'विज़िटर' }) + '</div><div class="ds-card"><h3>🧭 स्टोर का ट्रैफ़िक</h3>' + donut((D.sources || []).filter(function (x) { return x.site === 'store'; }).map(function (x, i) { return { l: srcName(x.src), v: x.visitors, c: PAL[i % PAL.length] }; }), { center: 'विज़िटर' }) + '</div></div>';
    return h;
  }

  var SPDASH = window.SPDASH = { days: 30, productTitle: null };
  function mount(host, o) {
    cssOnce(); SPDASH.productTitle = o.productTitle || null; var kind = o.kind || 'web', D = null, busy = false;
    var titles = { web: '🌐 Website Analytics', store: '🛒 Store Analytics', compare: '⚖️ Compare' };
    function rangeLabel() { var r = RANGES.filter(function (x) { return x[0] === SPDASH.days; })[0]; return r ? r[1] : SPDASH.days + ' दिन'; }
    function head() { return '<div class="ds-bar" style="padding:0 2px"><b style="flex:1">' + titles[kind] + '</b><span class="ds-chip on" style="cursor:default">📅 ' + esc(rangeLabel()) + '</span></div>'; }
    function draw(msg) { host.innerHTML = '<div class="dsh">' + head() + (msg ? '<div class="ds-card"><div class="ds-empty">' + msg + '</div></div>' : (D ? (kind === 'compare' ? compare(D) : sections(D, kind)) : '')) + '</div>'; }
    async function load() {
      if (busy) return; busy = true; draw('<span class="spin"></span> लोड हो रहा है…');
      try { D = await o.rpc('sp_admin_analytics', { p_pass: o.pass(), p_days: SPDASH.days }); busy = false; draw(); if (o.onData) o.onData(alertItems(D, kind).map(function (x) { return { c: x[0], t: x[1] }; })); }
      catch (e) { busy = false; draw(/Could not find|PGRST202|schema cache/i.test(e.message) ? '❌ पहले Supabase में <b>phase9-analytics-look.sql</b> चलाएँ (MASTER-UPDATE.sql में शामिल है)।' : '❌ ' + esc(e.message)); }
    }
    function csvDl() { if (!D) return; try { var bl = new Blob([csv(D, kind)], { type: 'text/csv' }), a = document.createElement('a'); a.href = URL.createObjectURL(bl); a.download = 'sunpowers-analytics-' + D.range.from + '_' + D.range.to + '.csv'; document.body.appendChild(a); a.click(); a.remove(); } catch (er) { if (o.toast) o.toast('डाउनलोड नहीं हो पाया', true); } }
    SPDASH.ctl = { set: function (d) { SPDASH.days = +d; load(); }, refresh: load, csv: csvDl, ranges: function () { return RANGES.map(function (r) { return [r[0], r[1], r[0] === SPDASH.days]; }).concat([['ref', '🔄 Refresh'], ['csv', '⬇️ CSV']]); } };
    host.onclick = null;
    load();
  }
  /* small "Visitors / Page views" strip for the top of other admin pages */
  async function strip(host, o) {
    cssOnce(); try { var D = await o.rpc('sp_admin_analytics', { p_pass: o.pass(), p_days: 7 }), k = o.kind === 'store' ? 'store' : 'website', c = D.cur[k] || {}, p = D.prev[k] || {};
      host.innerHTML = '<div class="ds-kpis" style="margin-bottom:12px">' + tile('👥', 'Visitors (7d)', n0(c.visitors), null, '', CW) + tile('👁', 'Page views (7d)', n0(c.views), null, '', CP) + '</div>'; if (o.onData) o.onData(alertItems(D, o.kind || 'web').map(function (x) { return { c: x[0], t: x[1] }; })); }
    catch (e) { host.innerHTML = ''; }
  }
  SPDASH.strip = strip; SPDASH.alertItems = alertItems; SPDASH.mount = mount; SPDASH.sections = sections; SPDASH.compare = compare;
})();
