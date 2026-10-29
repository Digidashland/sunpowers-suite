/* Tiny dependency-free SVG charts (Round 13) — C.chart.donut / bars / hbars / line / stair / spark.
   Colors come from CSS variables so light/dark themes both work. */
(function () {
  'use strict';
  var C = window.CRM, esc = C.esc;
  var PAL = ['#1e8e3e', '#f2a900', '#2f6fdb', '#d64545', '#7b4fd1', '#12a5a5', '#e0742c', '#6b7a70'];
  function col(i, c) { return c || PAL[i % PAL.length]; }
  function fmt(v) { v = +v || 0; var a = Math.abs(v); if (a >= 1e7) return (v / 1e7).toFixed(2).replace(/\.?0+$/, '') + 'Cr'; if (a >= 1e5) return (v / 1e5).toFixed(2).replace(/\.?0+$/, '') + 'L'; if (a >= 1e3) return (v / 1e3).toFixed(1).replace(/\.0$/, '') + 'k'; return String(Math.round(v * 100) / 100); }
  function empty(h) { return '<div class="ch-empty" style="height:' + (h || 120) + 'px">Abhi data nahi</div>'; }
  var ch = C.chart = { fmt: fmt, PAL: PAL };

  /* donut: parts [{l, v, c}] */
  ch.donut = function (parts, o) {
    o = o || {}; var S = o.size || 150, R = S / 2 - 6, r = R * 0.62, tot = 0, cx = S / 2, cy = S / 2; parts = (parts || []).filter(function (p) { return +p.v > 0; });
    parts.forEach(function (p) { tot += +p.v; });
    if (!tot) return empty(S);
    var a0 = -Math.PI / 2, svg = '<svg viewBox="0 0 ' + S + ' ' + S + '" width="' + S + '" height="' + S + '" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    if (parts.length === 1) svg += '<circle cx="' + cx + '" cy="' + cy + '" r="' + ((R + r) / 2) + '" fill="none" stroke="' + col(0, parts[0].c) + '" stroke-width="' + (R - r) + '"/>';
    else parts.forEach(function (p, i) {
      var a1 = a0 + (+p.v / tot) * Math.PI * 2, large = a1 - a0 > Math.PI ? 1 : 0;
      var x0 = cx + R * Math.cos(a0), y0 = cy + R * Math.sin(a0), x1 = cx + R * Math.cos(a1), y1 = cy + R * Math.sin(a1), x2 = cx + r * Math.cos(a1), y2 = cy + r * Math.sin(a1), x3 = cx + r * Math.cos(a0), y3 = cy + r * Math.sin(a0);
      svg += '<path d="M' + x0 + ' ' + y0 + ' A' + R + ' ' + R + ' 0 ' + large + ' 1 ' + x1 + ' ' + y1 + ' L' + x2 + ' ' + y2 + ' A' + r + ' ' + r + ' 0 ' + large + ' 0 ' + x3 + ' ' + y3 + ' Z" fill="' + col(i, p.c) + '"><title>' + esc(p.l) + ': ' + fmt(p.v) + '</title></path>'; a0 = a1;
    });
    svg += '<text x="' + cx + '" y="' + (cy - 2) + '" text-anchor="middle" class="ch-big">' + esc(o.center != null ? o.center : fmt(tot)) + '</text><text x="' + cx + '" y="' + (cy + 14) + '" text-anchor="middle" class="ch-sm">' + esc(o.sub || '') + '</text></svg>';
    return '<div class="ch-donut">' + svg + '<ul class="ch-leg">' + parts.map(function (p, i) { return '<li><i style="background:' + col(i, p.c) + '"></i><span>' + esc(p.l) + '</span><b>' + fmt(p.v) + '</b></li>'; }).join('') + '</ul></div>';
  };

  /* vertical bars (also stair when o.stair): data [{l, v}] or multi-series: o.series [{n, c}] with data [{l, vs:[..]}] */
  ch.bars = function (data, o) {
    o = o || {}; data = data || []; var W = o.w || 360, H = o.h || 170, pl = 34, pb = 24, pt = 10, n = data.length; if (!n) return empty(H);
    var ser = o.series || [{ n: '', c: o.color }], max = 0; data.forEach(function (d) { var vs = d.vs || [d.v]; vs.forEach(function (v) { max = Math.max(max, +v || 0); }); }); if (!max) max = 1;
    var iw = W - pl - 6, ih = H - pb - pt, gw = iw / n, bw = Math.min(34, gw / (ser.length + 0.6)), svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" class="ch-svg" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    for (var g = 0; g <= 3; g++) { var y = pt + ih - ih * g / 3; svg += '<line x1="' + pl + '" x2="' + (W - 4) + '" y1="' + y + '" y2="' + y + '" class="ch-grid"/><text x="' + (pl - 4) + '" y="' + (y + 3) + '" text-anchor="end" class="ch-ax">' + fmt(max * g / 3) + '</text>'; }
    data.forEach(function (d, i) {
      var vs = d.vs || [d.v], x0 = pl + gw * i + (gw - bw * ser.length) / 2;
      vs.forEach(function (v, k) { var hh = ih * (+v || 0) / max; svg += '<rect x="' + (x0 + bw * k) + '" y="' + (pt + ih - hh) + '" width="' + (bw - 2) + '" height="' + Math.max(hh, 0) + '" rx="3" fill="' + col(k, ser[k] && ser[k].c) + '"><title>' + esc(d.l) + (ser[k] && ser[k].n ? ' · ' + esc(ser[k].n) : '') + ': ' + fmt(v) + '</title></rect>'; });
      svg += '<text x="' + (pl + gw * i + gw / 2) + '" y="' + (H - 8) + '" text-anchor="middle" class="ch-ax">' + esc(String(d.l).slice(0, 7)) + '</text>';
    });
    svg += '</svg>';
    return '<div class="ch-wrap">' + svg + (o.series ? '<ul class="ch-leg row">' + ser.map(function (s, k) { return '<li><i style="background:' + col(k, s.c) + '"></i><span>' + esc(s.n) + '</span></li>'; }).join('') + '</ul>' : '') + '</div>';
  };

  /* stair (step) chart: data [{l, v}] — good for cumulative totals */
  ch.stair = function (data, o) {
    o = o || {}; data = data || []; var W = o.w || 360, H = o.h || 170, pl = 34, pb = 24, pt = 10, n = data.length; if (!n) return empty(H);
    var max = 0; data.forEach(function (d) { max = Math.max(max, +d.v || 0); }); if (!max) max = 1;
    var iw = W - pl - 6, ih = H - pb - pt, gw = iw / n, c = col(0, o.color), pts = '', area = 'M' + pl + ' ' + (pt + ih);
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" class="ch-svg" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    for (var g = 0; g <= 3; g++) { var y = pt + ih - ih * g / 3; svg += '<line x1="' + pl + '" x2="' + (W - 4) + '" y1="' + y + '" y2="' + y + '" class="ch-grid"/><text x="' + (pl - 4) + '" y="' + (y + 3) + '" text-anchor="end" class="ch-ax">' + fmt(max * g / 3) + '</text>'; }
    data.forEach(function (d, i) { var x = pl + gw * i, y = pt + ih - ih * (+d.v || 0) / max; area += ' L' + x + ' ' + y + ' L' + (x + gw) + ' ' + y; pts += (i ? ' L' : 'M') + x + ' ' + y + ' L' + (x + gw) + ' ' + y; svg += '<text x="' + (x + gw / 2) + '" y="' + (H - 8) + '" text-anchor="middle" class="ch-ax">' + esc(String(d.l).slice(0, 7)) + '</text>'; });
    area += ' L' + (pl + gw * n) + ' ' + (pt + ih) + ' Z';
    svg += '<path d="' + area + '" fill="' + c + '" opacity=".14"/><path d="' + pts + '" fill="none" stroke="' + c + '" stroke-width="2.2"/></svg>';
    return '<div class="ch-wrap">' + svg + '</div>';
  };

  /* line chart: data [{l, v}] */
  ch.line = function (data, o) {
    o = o || {}; data = data || []; var W = o.w || 360, H = o.h || 170, pl = 34, pb = 24, pt = 10, n = data.length; if (!n) return empty(H);
    var max = 0; data.forEach(function (d) { max = Math.max(max, +d.v || 0); }); if (!max) max = 1;
    var iw = W - pl - 10, ih = H - pb - pt, st = n > 1 ? iw / (n - 1) : 0, c = col(2, o.color), d0 = '', dots = '';
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" class="ch-svg" role="img" aria-label="' + esc(o.label || 'chart') + '">';
    for (var g = 0; g <= 3; g++) { var y = pt + ih - ih * g / 3; svg += '<line x1="' + pl + '" x2="' + (W - 4) + '" y1="' + y + '" y2="' + y + '" class="ch-grid"/><text x="' + (pl - 4) + '" y="' + (y + 3) + '" text-anchor="end" class="ch-ax">' + fmt(max * g / 3) + '</text>'; }
    data.forEach(function (d, i) { var x = pl + (n > 1 ? st * i : iw / 2), y = pt + ih - ih * (+d.v || 0) / max; d0 += (i ? ' L' : 'M') + x + ' ' + y; dots += '<circle cx="' + x + '" cy="' + y + '" r="3.2" fill="' + c + '"><title>' + esc(d.l) + ': ' + fmt(d.v) + '</title></circle>'; if (n <= 12 || i % Math.ceil(n / 8) === 0) svg += '<text x="' + x + '" y="' + (H - 8) + '" text-anchor="middle" class="ch-ax">' + esc(String(d.l).slice(0, 7)) + '</text>'; });
    svg += '<path d="' + d0 + ' L' + (pl + (n > 1 ? st * (n - 1) : iw / 2)) + ' ' + (pt + ih) + ' L' + pl + ' ' + (pt + ih) + ' Z" fill="' + c + '" opacity=".1"/><path d="' + d0 + '" fill="none" stroke="' + c + '" stroke-width="2.2"/>' + dots + '</svg>';
    return '<div class="ch-wrap">' + svg + '</div>';
  };

  /* horizontal bars: rows [{l, v, c, sub}] */
  ch.hbars = function (rows, o) {
    o = o || {}; rows = (rows || []).slice(0, o.max || 8); if (!rows.length) return empty(80); var max = 0; rows.forEach(function (r) { max = Math.max(max, +r.v || 0); }); if (!max) max = 1;
    return '<div class="ch-hb">' + rows.map(function (r, i) { return '<div class="ch-hr"><span class="ch-hl" title="' + esc(r.l) + '">' + esc(r.l) + '</span><span class="ch-ht"><i style="width:' + Math.max(2, 100 * (+r.v || 0) / max) + '%;background:' + col(i, r.c) + '"></i></span><b>' + (o.money ? C.money(r.v) : fmt(r.v)) + '</b></div>'; }).join('') + '</div>';
  };

  /* progress ring-less bar */
  ch.progress = function (pct, c) { pct = Math.max(0, Math.min(100, +pct || 0)); return '<span class="ch-pg"><i style="width:' + pct + '%;background:' + (c || PAL[0]) + '"></i></span>'; };

  /* tiny sparkline for tiles */
  ch.spark = function (vals, c) { vals = vals || []; if (vals.length < 2) return ''; var W = 80, H = 24, max = Math.max.apply(null, vals) || 1, st = W / (vals.length - 1), d = vals.map(function (v, i) { return (i ? 'L' : 'M') + (i * st) + ' ' + (H - 2 - (H - 4) * v / max); }).join(' '); return '<svg viewBox="0 0 ' + W + ' ' + H + '" class="ch-spark"><path d="' + d + '" fill="none" stroke="' + (c || PAL[0]) + '" stroke-width="2"/></svg>'; };

  /* icon stat tile */
  ch.tile = function (o) { return '<div class="ch-tile' + (o.href ? ' click' : '') + '"' + (o.href ? ' data-href="' + esc(o.href) + '"' : '') + '><span class="ch-ti" style="background:' + (o.c || PAL[0]) + '">' + (o.icon ? C.ic(o.icon) : '') + '</span><span class="ch-tt"><span class="ch-tl">' + esc(o.l) + '</span><b class="ch-tv">' + esc(o.v) + '</b>' + (o.sub ? '<span class="ch-ts">' + esc(o.sub) + '</span>' : '') + '</span>' + (o.spark || '') + '</div>'; };
})();
