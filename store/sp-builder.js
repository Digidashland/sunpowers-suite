/* ============================================================================
   Sunpowers Page Builder — shared engine
   Used by: Online Store (app), website Shop page, and the Admin live preview.
   Data lives inside the store JSON (sp_store.main):
     builder = { v:1, on:{store,shop}, ctr:{type:n}, comps:{ fixedName:{ type,name,nameEn,show,lock,pages:{store,shop},cfg } },
                 order:{ store:[fixedName…], shop:[fixedName…] } }
   If builder.on[page] is false (or nothing is there) the host keeps showing its OLD layout — nothing old is changed.
   Product placement = the existing product.sections[] (a "Raw Category" box and every product row is bound to a section).
   No keys, no network: images / links are plain data entered by the admin.
   ============================================================================ */
(function (root) {
  'use strict';
  var B = root.SPBLD = {};
  function isO(o) { return o && typeof o === 'object' && !Array.isArray(o); }
  function num(x) { x = parseFloat(x); return isFinite(x) ? x : 0; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function isImg(s) { return !!s && /^(https?:\/\/|data:image\/|\/|\.\/)/i.test(String(s).trim()); }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function safeUrl(u) {
    u = String(u || '').trim();
    if (root.SP && root.SP.safeUrl) return root.SP.safeUrl(u);
    if (/^(https?:\/\/|tel:|mailto:|\/|\.\/|\?|#)/i.test(u)) return u;
    return /^[\w.-]+\.[a-z]{2,}(\/|$)/i.test(u) ? 'https://' + u : '';
  }
  B.esc = esc; B.isImg = isImg;

  /* ---------------- component types ---------------- */
  var RAILDEF = { rule: 'manual', sec: '', limit: 8, layout: 'scroll', cols: 0, btns: ['buy'] };
  var TYPES = B.TYPES = {
    search_bar:       { label: 'Search Bar', icon: '🔍', multi: 1, name: 'Search', def: { ph: '' } },
    slideshow_banner: { label: 'Slideshow Banner', icon: '🖼️', multi: 1, name: 'Main Banner', def: { height: 190, interval: 4, autoplay: true, slides: [] } },
    raw_category:     { label: 'Raw Category Row (boxes)', icon: '🧩', multi: 1, name: 'Shop by Category', def: { cols: 3, bctr: 0, boxes: [] } },
    category_1:       { label: 'Deals of the Day', icon: '🔥', fixed: 1, name: 'Deals of the Day', def: Object.assign({}, RAILDEF, { rule: 'discount' }) },
    category_2:       { label: 'Recommended for You', icon: '💝', fixed: 1, name: 'Recommended for You', def: Object.assign({}, RAILDEF) },
    category_3:       { label: 'Best Sellers', icon: '⭐', fixed: 1, name: 'Best Sellers', def: Object.assign({}, RAILDEF) },
    category_4:       { label: 'New Arrivals', icon: '✨', fixed: 1, name: 'New Arrivals', def: Object.assign({}, RAILDEF, { rule: 'newest' }) },
    product_row:      { label: 'Product Row (any section)', icon: '🛒', multi: 1, name: 'Products', def: Object.assign({}, RAILDEF) },
    video_section:    { label: 'Video Section 16:9', icon: '🎬', multi: 1, name: 'Our Video', def: { url: '', poster: '', btns: [] } },
    youtube_section:  { label: 'YouTube Section', icon: '▶️', multi: 1, name: 'Our YouTube', def: { channel: '', vids: [] } },
    delivery_bar:     { label: 'Delivery Bar', icon: '🚚', multi: 1, name: 'Delivery', def: { text: '', pin: true } },
    offer_strip:      { label: 'Offer Strip', icon: '🏷️', multi: 1, name: 'Offer', def: { text: '', linkType: 'none', link: '', bg: '#1b5e20', fg: '#ffffff', ticker: true } },
    custom_section:   { label: 'Custom Section', icon: '🧱', multi: 1, name: 'Custom', def: { title: '', text: '', img: '', btn: '', linkType: 'none', link: '', bg: '#f1f7f2' } }
  };
  B.ORDER = ['search_bar', 'slideshow_banner', 'raw_category', 'category_1', 'category_2', 'category_3', 'category_4', 'product_row', 'video_section', 'youtube_section', 'delivery_bar', 'offer_strip', 'custom_section'];
  B.PRESETS = { tl: [4, 8], tc: [50, 8], tr: [96, 8], cl: [4, 50], cc: [50, 50], cr: [96, 50], bl: [4, 90], bc: [50, 90], br: [96, 90] };

  /* ---------------- normalise ---------------- */
  function normComp(id, c) {
    var T = TYPES[c.type]; if (!T) return null;
    var o = { id: id, type: c.type, name: String(c.name || T.name).slice(0, 80), nameEn: String(c.nameEn || '').slice(0, 80), show: c.show !== false, lock: c.lock === true, demo: c.demo === true,
      pages: { store: !c.pages || c.pages.store !== false, shop: !c.pages || c.pages.shop !== false }, cfg: clone(T.def) };
    if (isO(c.cfg)) for (var k in c.cfg) o.cfg[k] = c.cfg[k];
    var g = o.cfg;
    ['slides', 'boxes', 'btns', 'vids'].forEach(function (k) { if (k in g && !Array.isArray(g[k])) g[k] = []; });
    if (c.type === 'slideshow_banner') { g.height = Math.max(100, Math.min(600, num(g.height) || 190)); g.interval = Math.max(1, Math.min(60, num(g.interval) || 4)); g.slides = g.slides.filter(isO); g.slides.forEach(function (s) { if (!Array.isArray(s.btns)) s.btns = []; s.btns = s.btns.filter(isO); if (!s.id) s.id = 'sl' + Math.random().toString(36).slice(2, 7); }); }
    if (c.type === 'raw_category') { g.cols = Math.max(2, Math.min(4, Math.round(num(g.cols)) || 3)); g.boxes = g.boxes.filter(isO); var mx = 0; g.boxes.forEach(function (b) { var m = /^box_(\d+)$/.exec(b.id || ''); if (m) mx = Math.max(mx, +m[1]); }); g.bctr = Math.max(Math.round(num(g.bctr)), mx); }
    if (c.type === 'video_section') g.btns = g.btns.filter(isO);
    if (T.def.rule !== undefined) { g.cols = [0, 2, 3, 4].indexOf(Math.round(num(g.cols))) >= 0 ? Math.round(num(g.cols)) : 0; g.btns = Array.isArray(g.btns) ? g.btns.filter(function (k) { return ['buy', 'wa', 'view'].indexOf(k) >= 0; }) : ['buy']; g.limit = Math.max(1, Math.min(40, Math.round(num(g.limit)) || 8)); if (['manual', 'discount', 'newest', 'all'].indexOf(g.rule) < 0) g.rule = 'manual'; }
    return o;
  }
  B.norm = function (raw) {
    raw = isO(raw) ? raw : {};
    var o = { v: 1, on: { store: !!(raw.on && raw.on.store), shop: !!(raw.on && raw.on.shop) }, ctr: {}, comps: {}, order: { store: [], shop: [] } };
    var rc = isO(raw.comps) ? raw.comps : {};
    Object.keys(rc).forEach(function (id) { var c = rc[id]; if (!isO(c) || !/^[a-z_]+_?\d*$/.test(id)) return; var n = normComp(id, c); if (n) o.comps[id] = n; });
    var rcnt = isO(raw.ctr) ? raw.ctr : {};
    Object.keys(TYPES).forEach(function (t) { if (!TYPES[t].multi) return; var mx = Math.max(0, Math.round(num(rcnt[t]))); Object.keys(o.comps).forEach(function (id) { var m = new RegExp('^' + t + '_(\\d+)$').exec(id); if (m) mx = Math.max(mx, +m[1]); }); o.ctr[t] = mx; });
    ['store', 'shop'].forEach(function (pg) {
      var seen = {}, ord = (raw.order && Array.isArray(raw.order[pg]) ? raw.order[pg] : []).filter(function (id) { if (seen[id] || !o.comps[id] || !o.comps[id].pages[pg]) return false; seen[id] = 1; return true; });
      Object.keys(o.comps).forEach(function (id) { if (!seen[id] && o.comps[id].pages[pg]) ord.push(id); });
      o.order[pg] = ord;
    });
    return o;
  };
  /* next fixed internal name: search_bar_1 → search_bar_2 (numbers are never re-used) */
  B.add = function (cfg, type) {
    var T = TYPES[type]; if (!T) return null;
    var id;
    if (T.fixed) { if (cfg.comps[type]) return null; id = type; }
    else { cfg.ctr[type] = (cfg.ctr[type] || 0) + 1; id = type + '_' + cfg.ctr[type]; }
    var c = normComp(id, { type: type }); cfg.comps[id] = c; ['store', 'shop'].forEach(function (pg) { if (c.pages[pg]) cfg.order[pg].push(id); });
    return c;
  };
  /* Duplicate: an exact copy right below the original (same settings, same pages). A fixed block (Deals of the Day …) is copied as a "Product Row" because it can exist only once. */
  B.dup = function (cfg, id) {
    var o = cfg.comps[id]; if (!o) return null; var type = TYPES[o.type] && TYPES[o.type].fixed ? 'product_row' : o.type;
    cfg.ctr[type] = (cfg.ctr[type] || 0) + 1; var nid = type + '_' + cfg.ctr[type];
    var c = normComp(nid, { type: type, name: (o.name || '') + ' (कॉपी)', nameEn: o.nameEn ? o.nameEn + ' (copy)' : '', show: o.show, pages: clone(o.pages), cfg: clone(o.cfg) });
    c.lock = false; cfg.comps[nid] = c;
    ['store', 'shop'].forEach(function (pg) { var ord = cfg.order[pg], i = ord.indexOf(id); if (i >= 0) ord.splice(i + 1, 0, nid); else if (c.pages[pg]) ord.push(nid); });
    return c;
  };
  B.remove = function (cfg, id) { delete cfg.comps[id]; ['store', 'shop'].forEach(function (pg) { cfg.order[pg] = cfg.order[pg].filter(function (x) { return x !== id; }); }); };
  B.list = function (cfg, page, all) { return (cfg.order[page] || []).map(function (id) { return cfg.comps[id]; }).filter(function (c) { return c && (all || c.show !== false); }); };
  B.isOn = function (cfg, page) { return !!(cfg && cfg.on && cfg.on[page] && B.list(cfg, page).length); };
  B.nextBox = function (c) { c.cfg.bctr = (c.cfg.bctr || 0) + 1; return 'box_' + c.cfg.bctr; };
  B.parseVideo = function (u) {
    u = String(u || '').trim(); var m;
    if ((m = /(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/))([\w-]{11})/i.exec(u))) return { kind: 'yt', id: m[1] };
    if (/^https?:\/\/.+\.(mp4|webm)(\?.*)?$/i.test(u) || /^https?:\/\/res\.cloudinary\.com\/.+\/video\//i.test(u)) return { kind: 'file', url: u };
    return null;
  };

  /* ---------------- product picking ---------------- */
  function disc(p, ctx) { if (ctx && ctx.disc) return ctx.disc(p); var m = num(p.mrp), o = num(p.offer); return m > 0 && o > 0 && o < m ? Math.round((m - o) / m * 100) : 0; }
  B.products = function (c, ctx) {
    var S = ctx.S, g = c.cfg, list = (S.products || []).filter(function (p) { return p.visible !== false && (ctx.page !== 'shop' || p.web !== false); });
    if (g.rule === 'manual') list = g.sec ? list.filter(function (p) { return (p.sections || []).indexOf(g.sec) >= 0; }) : [];
    else if (g.sec) list = list.filter(function (p) { return (p.sections || []).indexOf(g.sec) >= 0; });
    if (g.rule === 'discount') list = list.filter(function (p) { return disc(p, ctx) > 0 && p.stock !== 'out'; }).sort(function (a, b) { return disc(b, ctx) - disc(a, ctx); });
    else list = list.slice().sort(function (a, b) { return (p0(a) - p0(b)); });
    return list.slice(0, g.limit);
  };
  function p0(p) { return num(p.sort) + (p.stock === 'out' ? 1e6 : 0); }

  /* ---------------- text / link helpers ---------------- */
  function tx(o, k, ctx) { var en = ctx && ctx.lang && ctx.lang() === 'en'; return en ? (o[k + 'En'] || o[k] || '') : (o[k] || o[k + 'En'] || ''); }
  function lnkAttr(o) { var lt = o.linkType && o.linkType !== 'none' ? o.linkType : ''; return lt ? ' data-lt="' + esc(lt) + '" data-l="' + esc(o.link || '') + '"' : ''; }
  function btnPos(b) { var p = B.PRESETS[b.pos]; var x = p ? p[0] : (b.x == null || b.x === '' ? 50 : num(b.x)), y = p ? p[1] : (b.y == null || b.y === '' ? 90 : num(b.y)); x = Math.max(0, Math.min(100, x)); y = Math.max(0, Math.min(100, y)); return 'left:' + x + '%;top:' + y + '%;transform:translate(-' + x + '%,-' + y + '%)'; }
  function btnsHtml(btns) {
    return (btns || []).filter(function (b) { return b && String(b.label || '').trim() && b.linkType && b.linkType !== 'none'; }).map(function (b) {
      return '<button type="button" class="bld-bb' + (b.style === 'light' ? ' lt' : '') + '" data-bb' + lnkAttr(b) + ' data-subj="' + esc(b.label) + '" style="' + btnPos(b) + '">' + esc(b.label) + '</button>';
    }).join('');
  }
  function noItems(ctx, msg) { return ctx.admin ? '<div class="bld-ph">' + esc(msg) + '</div>' : ''; }
  function head(c, ctx) { var n = tx(c, 'name', ctx); return n ? '<div class="bld-h"><h2>' + esc(n) + '</h2></div>' : ''; }

  /* ---------------- renderers ---------------- */
  var R = {};
  R.search_bar = function (c, ctx) {
    return '<form class="bld-search" data-bsearch role="search"><span aria-hidden="true">🔍</span><input type="search" name="q" autocomplete="off" maxlength="80" placeholder="' + esc(c.cfg.ph || (ctx.t ? ctx.t('search') : 'Search products…')) + '" aria-label="Search"><button type="submit" aria-label="Search">→</button></form>';
  };
  R.slideshow_banner = function (c, ctx) {
    var g = c.cfg, slides = g.slides.filter(function (s) { return s.visible !== false; });
    if (!slides.length) return noItems(ctx, 'Banner: abhi koi slide nahi — settings me slide jodein');
    return '<div class="bld-ss" data-bss data-iv="' + esc(g.interval) + '" data-ap="' + (g.autoplay === false ? 0 : 1) + '" style="--h:' + Math.round(g.height) + 'px"><div class="bld-track">' + slides.map(function (s, i) {
      var img = isImg(s.image), txt = s.title || s.sub;
      return '<div class="bld-sl' + (txt ? ' tx' : '') + '"' + lnkAttr(s) + ' data-subj="' + esc(s.title || '') + '" style="--c:' + esc(/^#[0-9a-f]{3,8}$/i.test(s.bg || '') ? s.bg : '#1b5e20') + '">' +
        (img ? '<img class="bg" src="' + esc(s.image) + '" alt="" ' + (i ? 'loading="lazy" ' : '') + 'decoding="async" onerror="this.remove()">' : (s.emoji ? '<span class="em">' + esc(s.emoji) + '</span>' : '')) +
        (txt ? '<div class="in">' + (s.title ? '<h3>' + esc(s.title) + '</h3>' : '') + (s.sub ? '<p>' + esc(s.sub) + '</p>' : '') + '</div>' : '') + btnsHtml(s.btns) + '</div>';
    }).join('') + '</div>' + (slides.length > 1 ? '<button type="button" class="bld-arr l" data-barr="-1" aria-label="Previous">‹</button><button type="button" class="bld-arr r" data-barr="1" aria-label="Next">›</button><div class="bld-dots">' + slides.map(function (_, i) { return '<i' + (i ? '' : ' class="on"') + '></i>'; }).join('') + '</div>' : '') + '</div>';
  };
  R.raw_category = function (c, ctx) {
    var g = c.cfg, boxes = g.boxes.filter(function (b) { return b.visible !== false; });
    if (!boxes.length) return noItems(ctx, 'Raw Category: abhi koi box nahi — "Add Box" dabayein');
    return head(c, ctx) + '<div class="bld-rc" style="--cols:' + g.cols + '">' + boxes.map(function (b) {
      var lt = b.sec ? 'section' : (b.linkType && b.linkType !== 'none' ? b.linkType : ''), l = b.sec || b.link || '', nm = tx(b, 'name', ctx);
      return '<button type="button" class="bld-bx"' + (lt ? ' data-lt="' + esc(lt) + '" data-l="' + esc(l) + '"' : '') + ' data-subj="' + esc(nm) + '"><span class="pic" style="background:' + esc(/^#[0-9a-f]{3,8}$/i.test(b.bg || '') ? b.bg : '#eaf4ec') + '">' + (isImg(b.image) ? '<img src="' + esc(b.image) + '" alt="" loading="lazy" onerror="this.remove()">' : '<em>' + esc(b.emoji || '☀️') + '</em>') + '</span><b>' + esc(nm) + '</b></button>';
    }).join('') + '</div>';
  };
  function rail(c, ctx) {
    var list = B.products(c, ctx), g = c.cfg;
    if (!list.length) return noItems(ctx, (tx(c, 'name', ctx) || 'Product row') + (g.rule === 'manual' && !g.sec ? ': section chunein' : ': is rule me abhi koi product nahi'));
    var o = { title: tx(c, 'name', ctx), icon: TYPES[c.type].icon, products: list, layout: g.layout, cols: g.cols || 0, btns: g.btns || [], viewAll: g.rule === 'manual' && g.sec ? { linkType: 'section', link: g.sec } : (g.sec ? { linkType: 'section', link: g.sec } : null), id: c.id };
    if (ctx.rail) return ctx.rail(o);
    return head(c, ctx) + '<div class="bld-rl ' + (g.layout === 'grid' ? 'grid' : 'hsx') + '"' + (g.cols ? ' style="--cols:' + g.cols + '"' : '') + '>' + list.map(function (p) { return ctx.card(p, { btns: g.btns || [] }); }).join('') + '</div>';
  }
  ['category_1', 'category_2', 'category_3', 'category_4', 'product_row'].forEach(function (t) { R[t] = rail; });
  function vidBox(c, ctx) {
    var g = c.cfg, v = B.parseVideo(g.url);
    if (!v) return noItems(ctx, 'Video: YouTube ya .mp4 ka link daalein');
    var poster = isImg(g.poster) ? g.poster : (v.kind === 'yt' ? 'https://img.youtube.com/vi/' + v.id + '/hqdefault.jpg' : '');
    if (v.kind === 'file') return '<div class="bld-vid"><video src="' + esc(v.url) + '" controls playsinline preload="metadata"' + (poster ? ' poster="' + esc(poster) + '"' : '') + '></video>' + btnsHtml(g.btns) + '</div>';
    return '<div class="bld-vid" data-vid="' + esc(v.id) + '"><img src="' + esc(poster) + '" alt="" loading="lazy" onerror="this.remove()"><button type="button" class="bld-play" data-bplay aria-label="Play">▶</button>' + btnsHtml(g.btns) + '</div>';
  }
  R.video_section = function (c, ctx) { var h = vidBox(c, ctx); return h ? head(c, ctx) + h : ''; };
  R.youtube_section = function (c, ctx) {
    var g = c.cfg, items = (g.vids || []).map(function (x) { var s = typeof x === 'string' ? x : (x && x.url) || '', parts = String(s).split('|'), v = B.parseVideo(parts[0]); return v && v.kind === 'yt' ? { id: v.id, title: (parts[1] || '').trim() } : null; }).filter(Boolean);
    if (!items.length) return noItems(ctx, 'YouTube: video ke link daalein (har line me ek)');
    var ch = safeUrl(g.channel);
    return head(c, ctx) + '<div class="bld-yt"><button type="button" class="bld-arr l" data-yarr="-1" aria-label="Left">‹</button><div class="bld-ys" data-ys>' + items.map(function (v) {
      return '<a class="bld-yv" href="https://www.youtube.com/watch?v=' + esc(v.id) + '" target="_blank" rel="noopener"><span class="th"><img src="https://img.youtube.com/vi/' + esc(v.id) + '/mqdefault.jpg" alt="" loading="lazy" onerror="this.remove()"><i>▶</i></span>' + (v.title ? '<b>' + esc(v.title) + '</b>' : '') + '</a>';
    }).join('') + '</div><button type="button" class="bld-arr r" data-yarr="1" aria-label="Right">›</button></div>' + (/^https?:/i.test(ch) ? '<p class="bld-yc"><a href="' + esc(ch) + '" target="_blank" rel="noopener">▶ YouTube channel →</a></p>' : '');
  };
  R.delivery_bar = function (c, ctx) {
    var g = c.cfg, pin = g.pin !== false && ctx.pinChip ? ctx.pinChip() : '';
    if (!g.text && !pin) return noItems(ctx, 'Delivery bar: text likhein');
    return '<div class="bld-del"><span>🚚 ' + esc(g.text || '') + '</span>' + pin + '</div>';
  };
  R.offer_strip = function (c, ctx) {
    var g = c.cfg; if (!String(g.text || '').trim()) return noItems(ctx, 'Offer strip: text likhein');
    var col = function (v, d) { return /^#[0-9a-f]{3,8}$/i.test(v || '') ? v : d; };
    return '<div class="bld-off' + (g.ticker !== false ? ' tk' : '') + '"' + lnkAttr(g) + ' data-subj="' + esc(g.text) + '" style="background:' + col(g.bg, '#1b5e20') + ';color:' + col(g.fg, '#ffffff') + '"><span>' + esc(g.text) + '</span></div>';
  };
  R.custom_section = function (c, ctx) {
    var g = c.cfg; if (!g.title && !g.text && !isImg(g.img)) return noItems(ctx, 'Custom section: title / text daalein');
    var col = /^#[0-9a-f]{3,8}$/i.test(g.bg || '') ? g.bg : '#f1f7f2';
    return '<div class="bld-cs" style="background:' + col + '">' + (isImg(g.img) ? '<img src="' + esc(g.img) + '" alt="" loading="lazy" onerror="this.remove()">' : '') + '<div class="tx">' + (g.title ? '<h3>' + esc(g.title) + '</h3>' : '') +
      String(g.text || '').split('\n').filter(function (x) { return x.trim(); }).map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('') +
      (g.btn && g.linkType && g.linkType !== 'none' ? '<button type="button" class="bld-cb"' + lnkAttr(g) + ' data-subj="' + esc(g.btn) + '">' + esc(g.btn) + '</button>' : '') + '</div></div>';
  };

  /* html for all components of a page (public: only the ones switched ON) */
  B.render = function (cfg, page, ctx) {
    ctx = ctx || {}; ctx.page = page; B.css();
    return B.list(cfg, page, !!ctx.admin).map(function (c) {
      var fn = R[c.type], h = ''; try { h = fn ? fn(c, ctx) : ''; } catch (e) { if (root.console) console.error('builder', c.id, e); }
      if (!h) return '';
      return '<section class="bld-b bld-' + esc(c.type) + (c.show === false ? ' off' : '') + '" data-bid="' + esc(c.id) + '">' + h + '</section>';
    }).join('');
  };
  B.renderOne = function (c, page, ctx) { ctx = ctx || {}; ctx.page = page; var fn = R[c.type]; return fn ? fn(c, ctx) : ''; };

  /* ---------------- behaviour ---------------- */
  function go(ctx, lt, l, subj) {
    l = String(l || '').trim();
    if (lt === 'whatsapp' && /^\+?[\d\s-]{10,15}$/.test(l)) { var d = l.replace(/\D/g, ''); if (d.length === 10) d = '91' + d; root.open('https://wa.me/' + d, '_blank', 'noopener'); return; }
    if (lt === 'call' && /^\+?[\d\s-]{6,15}$/.test(l)) { root.location.href = 'tel:' + l.replace(/[^\d+]/g, ''); return; }
    if (lt === 'url') { var u = safeUrl(l); if (!u) return; if (/^https?:/i.test(u) && u.indexOf(root.location.origin) !== 0) root.open(u, '_blank', 'noopener'); else root.location.href = u; return; }
    if (ctx.link) ctx.link(lt, l, subj);
  }
  B.mount = function (host, ctx) {
    if (!host) return;
    host.__bctx = ctx;
    var stop = function (t) { if (ctx.timer) ctx.timer(t); else (host.__tm = host.__tm || []).push(t); };
    Array.prototype.forEach.call(host.querySelectorAll('[data-bss]'), function (el) {
      var track = el.querySelector('.bld-track'), n = track.children.length, dots = el.querySelectorAll('.bld-dots i'), i = 0, paused = false;
      function show(k) { i = (k + n) % n; track.style.transform = 'translateX(' + (-100 * i) + '%)'; Array.prototype.forEach.call(dots, function (d, j) { d.classList.toggle('on', j === i); }); }
      el.__bshow = function (d) { show(i + d); };
      if (n > 1 && el.getAttribute('data-ap') !== '0') stop(setInterval(function () { if (!paused && !document.hidden && el.offsetParent !== null) show(i + 1); }, Math.max(1, num(el.getAttribute('data-iv')) || 4) * 1000));
      el.addEventListener('mouseenter', function () { paused = true; }); el.addEventListener('mouseleave', function () { paused = false; });
      var x0 = null, y0 = null;
      el.addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; paused = true; }, { passive: true });
      el.addEventListener('touchend', function (e) { paused = false; if (x0 === null) return; var dx = e.changedTouches[0].clientX - x0, dy = e.changedTouches[0].clientY - y0; if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) { el.__moved = true; show(dx < 0 ? i + 1 : i - 1); } x0 = null; }, { passive: true });
    });
    if (host.__bound) return; host.__bound = true;
    host.addEventListener('click', function (e) {
      var cx = host.__bctx || ctx, t = e.target, b;
      if (cx.admin) { if (t.closest('a,button,[data-lt]')) e.preventDefault(); }
      if ((b = t.closest('[data-barr]'))) { var ss = b.closest('[data-bss]'); if (ss && ss.__bshow) ss.__bshow(+b.getAttribute('data-barr')); return; }
      if ((b = t.closest('[data-yarr]'))) { var ys = b.parentNode.querySelector('[data-ys]'); if (ys) ys.scrollBy({ left: +b.getAttribute('data-yarr') * Math.max(160, ys.clientWidth * 0.8), behavior: 'smooth' }); return; }
      if ((b = t.closest('[data-bplay]'))) { var v = b.closest('[data-vid]'); if (v && !cx.admin) { v.innerHTML = '<iframe src="https://www.youtube-nocookie.com/embed/' + encodeURIComponent(v.getAttribute('data-vid')) + '?autoplay=1&rel=0" title="Video" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>'; } return; }
      if (cx.admin) return;
      if ((b = t.closest('[data-bb]'))) { e.stopPropagation(); go(cx, b.getAttribute('data-lt'), b.getAttribute('data-l'), b.getAttribute('data-subj')); return; }
      var ssw = t.closest('[data-bss]'); if (ssw && ssw.__moved) { ssw.__moved = false; return; }
      if ((b = t.closest('[data-lt]'))) go(cx, b.getAttribute('data-lt'), b.getAttribute('data-l'), b.getAttribute('data-subj'));
    });
    host.addEventListener('submit', function (e) {
      var f = e.target.closest && e.target.closest('[data-bsearch]'); if (!f) return; e.preventDefault();
      var cx = host.__bctx || ctx; if (cx.admin) return; var q = (f.querySelector('input').value || '').trim(); if (q && cx.search) cx.search(q);
    });
  };
  B.stop = function (host) { (host.__tm || []).forEach(clearInterval); host.__tm = []; };

  /* ---------------- styles (injected once) ---------------- */
  B.css = function () {
    if (!root.document || root.document.getElementById('bld-css')) return;
    var s = root.document.createElement('style'); s.id = 'bld-css';
    s.textContent = [
      '.bld-b{margin:0 0 16px;--ba:var(--leaf,#1b6b3a);--bt:var(--tx,#14231a);--bl:#e3ebe3}',
      '.bld-h h2{margin:0 0 8px;font-size:18px;color:var(--bt)}',
      '.bld-ph{border:2px dashed #c9d6cb;border-radius:14px;padding:18px;text-align:center;color:#6b7c70;font-size:13px;background:#fafcfa}',
      '.bld-search{display:flex;align-items:center;gap:8px;background:#fff;border:1.5px solid var(--bl);border-radius:14px;padding:4px 6px 4px 12px}.bld-search input{flex:1;min-width:0;border:0;outline:0;font:inherit;font-size:15px;padding:9px 2px;background:transparent;color:var(--bt)}.bld-search button{border:0;background:var(--ba);color:#fff;border-radius:10px;width:36px;height:34px;font-size:16px;cursor:pointer}',
      '.bld-ss{position:relative;overflow:hidden;border-radius:16px;height:var(--h,190px);background:#0b2e1f;touch-action:pan-y}.bld-track{display:flex;height:100%;transition:transform .45s ease}',
      '.bld-sl{flex:0 0 100%;position:relative;height:100%;background:var(--c,#1b5e20);color:#fff;cursor:pointer;overflow:hidden}.bld-sl:not([data-lt]){cursor:default}.bld-sl .bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}.bld-sl .em{position:absolute;right:14px;top:50%;transform:translateY(-50%);font-size:64px;opacity:.9}',
      '.bld-sl.tx::after{content:"";position:absolute;inset:0;background:linear-gradient(90deg,rgba(0,0,0,.55),rgba(0,0,0,0) 70%);pointer-events:none}.bld-sl .in{position:absolute;left:16px;top:50%;transform:translateY(-50%);max-width:70%;z-index:1;pointer-events:none}.bld-sl h3{margin:0 0 4px;font-size:21px;line-height:1.15}.bld-sl p{margin:0;font-size:13px;opacity:.95}',
      '.bld-bb{position:absolute;z-index:3;border:0;border-radius:999px;background:var(--ba,#1b6b3a);color:#fff;font:inherit;font-weight:700;font-size:13px;padding:8px 16px;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.3);white-space:nowrap}.bld-bb.lt{background:#fff;color:#14231a}',
      '.bld-arr{position:absolute;top:50%;transform:translateY(-50%);z-index:4;width:32px;height:32px;border:0;border-radius:50%;background:rgba(0,0,0,.45);color:#fff;font-size:20px;line-height:1;cursor:pointer}.bld-arr.l{left:8px}.bld-arr.r{right:8px}',
      '.bld-dots{position:absolute;left:0;right:0;bottom:8px;display:flex;justify-content:center;gap:5px;z-index:4;pointer-events:none}.bld-dots i{width:7px;height:7px;border-radius:50%;background:rgba(255,255,255,.5)}.bld-dots i.on{background:#fff;width:18px;border-radius:5px}',
      '.bld-rc{display:grid;grid-template-columns:repeat(var(--cols,3),minmax(0,1fr));gap:10px;max-width:calc(var(--cols,3)*170px)}.bld-bx{border:0;background:none;padding:0;text-align:center;cursor:pointer;font:inherit;color:var(--bt)}.bld-bx:not([data-lt]){cursor:default}.bld-bx .pic{display:grid;place-items:center;aspect-ratio:1;border-radius:16px;overflow:hidden;border:1px solid var(--bl)}.bld-bx .pic img{width:100%;height:100%;object-fit:cover}.bld-bx .pic em{font-style:normal;font-size:34px}.bld-bx b{display:block;margin-top:6px;font-size:13px;line-height:1.2}',
      '.bld-rl.hsx{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x proximity;padding-bottom:6px}.bld-rl.hsx>*{flex:0 0 150px;scroll-snap-align:start}.bld-rl.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}@media(min-width:700px){.bld-rl.grid{grid-template-columns:repeat(auto-fill,minmax(170px,1fr))}.bld-rl.grid[style*="--cols"]{grid-template-columns:repeat(var(--cols),minmax(0,1fr))}}',
      '.bld-vid{position:relative;aspect-ratio:16/9;border-radius:16px;overflow:hidden;background:#000}.bld-vid video,.bld-vid iframe,.bld-vid>img{position:absolute;inset:0;width:100%;height:100%;border:0;object-fit:cover}.bld-play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:58px;height:58px;border-radius:50%;border:0;background:rgba(255,255,255,.92);color:#c00;font-size:22px;cursor:pointer;z-index:2}',
      '.bld-yt{position:relative}.bld-ys{display:flex;gap:10px;overflow-x:auto;scroll-behavior:smooth;scrollbar-width:none;padding-bottom:4px}.bld-ys::-webkit-scrollbar{display:none}.bld-yv{flex:0 0 200px;text-decoration:none;color:var(--bt)}.bld-yv .th{position:relative;display:block;aspect-ratio:16/9;border-radius:12px;overflow:hidden;background:#111}.bld-yv .th img{width:100%;height:100%;object-fit:cover}.bld-yv .th i{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font-style:normal;background:rgba(255,0,0,.9);color:#fff;border-radius:10px;padding:3px 10px;font-size:14px}.bld-yv b{display:block;margin-top:5px;font-size:12.5px;line-height:1.25}.bld-yc{margin:6px 0 0;font-size:13px}.bld-yc a{color:var(--ba);font-weight:700}',
      '.bld-del{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;background:#eef7f0;border:1px solid var(--bl);border-radius:12px;padding:9px 12px;font-size:13.5px;color:var(--bt)}',
      '.bld-off{border-radius:12px;padding:9px 14px;font-weight:700;font-size:14px;text-align:center;overflow:hidden;white-space:nowrap}.bld-off[data-lt]{cursor:pointer}.bld-off.tk span{display:inline-block;padding-left:100%;animation:bldtk 14s linear infinite}@keyframes bldtk{to{transform:translateX(-100%)}}@media (prefers-reduced-motion:reduce){.bld-off.tk span{animation:none;padding-left:0}}',
      '.bld-cs{display:flex;gap:12px;align-items:center;border-radius:16px;padding:14px;border:1px solid var(--bl)}.bld-cs>img{width:34%;max-width:150px;aspect-ratio:1;object-fit:cover;border-radius:12px;flex:none}.bld-cs h3{margin:0 0 6px;font-size:17px;color:var(--bt)}.bld-cs p{margin:0 0 6px;font-size:13.5px;color:#41544a}.bld-cb{border:0;border-radius:999px;background:var(--ba);color:#fff;font:inherit;font-weight:700;font-size:13px;padding:8px 16px;cursor:pointer;margin-top:4px}',
      '.bld-b.off{opacity:.45}'
    ].join('');
    root.document.head.appendChild(s);
  };
})(window);
