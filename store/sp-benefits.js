/* Round 62 — "Aapko kya milega" : bill / quotation ke saath item-wise faayde (product / service / project).
   Ye engine bill ke selected items padhta hai aur apne aap section banata hai. Koi database nahi, koi AI nahi — seedhe templates.
   Admin (CRM > Settings > Company) se har template ka text badla ja sakta hai (ov). Bachat sirf ANUMAN hai, bill ki rakam kabhi nahi badalta. */
(function (root) {
  'use strict';
  var PROJ = ['Residential', 'Commercial', 'Industrial', 'VFD'], SERV = ['Service', 'AMC only', 'Site visit only'];

  /* ---------- templates: key -> {label, bul[], how} ---------- */
  var T = {
    p_on: { label: 'Project — On-Grid (ghar)', bul: [
      'Din me banayi bijli seedhe ghar ke kaam aati hai, isliye bijli bill me seedhi kami',
      'Zyada bani bijli meter ke zariye grid ko jaati hai (net metering ke niyam ke anusaar)',
      'Battery nahi lagti, isliye shuruaati kharch aur dekhbhaal kam',
      'Solar panel lambe samay (lagbhag 25 saal) tak bijli dete hain'],
      how: 'Solar panel dhoop se DC bijli banate hain, inverter use ghar ki AC bijli me badalta hai. Grid band hone par suraksha ke liye On-Grid system bhi band ho jata hai.' },
    p_hy: { label: 'Project — Hybrid (ghar)', bul: [
      'Din me solar se bijli, aur battery me store hokar light jaane par bhi zaroori load chalte hain',
      'Bijli bill me kami ke saath backup ki suvidha',
      'Grid ke saath jud kar chalta hai; net metering State ERC ke niyam par nirbhar',
      'Alag inverter + UPS ki zaroorat kam'],
      how: 'Solar se bani bijli pehle ghar ke load aur battery ko jaati hai; bachi hui grid ko. Grid na ho to battery se zaroori load chalte hain.' },
    p_off: { label: 'Project — Off-Grid', bul: [
      'Grid ke bina bhi bijli — dur-daraaz ya bar-bar light jaane wali jagah ke liye',
      'Battery me store hokar raat ko bhi bijli',
      'Generator / diesel ka kharch kam'],
      how: 'Solar panel se bani bijli charge controller/inverter ke zariye battery me store hoti hai aur zaroorat par load ko milti hai.' },
    p_comm: { label: 'Project — Commercial (dukaan / office)', bul: [
      'Din ke samay ka bijli bill kam — commercial daam zyada hote hain, isliye bachat bhi zyada',
      'Business chalte hue bijli ka kharch tay (predictable) rehta hai',
      'Business ke liye depreciation jaise kar-laabh mil sakte hain — apne CA se poochhein',
      'Green image — grahak aur partners ke liye achha sanket'],
      how: 'Din me chalne wale load (AC, light, machine) solar se chalte hain, isliye grid se kam bijli leni padti hai.' },
    p_ind: { label: 'Project — Industrial', bul: [
      'Din ke bhaari load solar se chalte hain, isliye energy charge me kami',
      'Lambe samay me bijli ke badhte daam se suraksha',
      'Depreciation jaise kar-laabh mil sakte hain — apne CA se poochhein',
      'Sahi design se bhavishya me capacity badhana aasaan'],
      how: 'Plant ki chhat/zameen par lage panel din me bijli banate hain, jo factory ke load ko seedhe milti hai; baaki grid se.' },
    p_vfd: { label: 'Project — Solar pump / VFD', bul: [
      'Diesel ya grid ke bina pump chalta hai — sinchai ka kharch kam',
      'VFD se motor dheere shuru hoti hai aur speed dhoop ke hisaab se badalti hai, isliye motor ko kam nuksan',
      'Din me jab sinchai ki zaroorat hoti hai usi samay sabse zyada bijli milti hai'],
      how: 'Solar panel se bani DC bijli VFD me jaati hai, jo pump motor ko dhoop ke hisaab se chalata hai.' },
    s_amc: { label: 'Service — AMC', bul: [
      'Saal bhar niyamit safai aur jaanch',
      'Chhoti kharabi pehle hi pakad me aati hai, badi kharabi se bachav',
      'Plant ki generation achhi bani rehti hai',
      'Complaint par tay visit aur team ka support'],
      how: 'Plan ke hisaab se tay tareekhon par technician aakar panel, wiring, inverter aur earthing ki jaanch aur safai karta hai.' },
    s_visit: { label: 'Service — Site visit', bul: [
      'Chhat ki sahi naap aur chhaya (shading) ki jaanch',
      'Aapke load ke hisaab se sahi system size ki salah',
      'Final quotation andaze par nahi, asli jaankari par'],
      how: 'Hamari team aapki site par aakar naap, shading, wiring aur meter ki sthiti dekhti hai, phir final quotation banti hai.' },
    s_clean: { label: 'Service — Panel safai', bul: [
      'Dhool-mitti jamne se generation ghat sakti hai — safai se bijli banna sahi rehta hai',
      'Panel ki surface aur wiring ki bhi saath me nazar se jaanch',
      'Sahi tareeke se safai, panel ko nuksan ke bina'],
      how: 'Saaf pani aur surakshit samagri se panel dhoye jaate hain; saath me ek chhoti jaanch hoti hai.' },
    s_inst: { label: 'Service — Installation / shifting', bul: [
      'Anubhavi team ke haath se surakshit installation',
      'Sahi wiring, earthing aur protection ke saath kaam',
      'Kaam ke baad chalu karke dikhana aur support'],
      how: 'Pehle site aur sthiti dekhi jaati hai, phir mount, wiring aur testing ke baad system chalu kiya jaata hai.' },
    s_nm: { label: 'Service — Net metering', bul: [
      'Bijli company ki file aur meter ki kaagzi karwai me madad',
      'Net metering se bani bijli ka hisaab bill me judta hai',
      'Sahi kaagaz — baad me pareshani nahi'],
      how: 'Kaagaz taiyaar karke DISCOM me jama kiye jaate hain; manzoori ke baad net meter lagta hai.' },
    s_gen: { label: 'Service — Anya (general)', bul: [
      'Anubhavi technician se kaam',
      'Kaam ke baad support aur sampark'],
      how: '' },
    c_panel: { label: 'Product — Solar Panel', bul: [
      'Dhoop se bijli banate hain; aapke bijli bill me kami',
      'Lambi umar aur kam dekhbhaal',
      'Warranty manufacturer ke niyam anusaar (warranty card dekhein)'], how: '' },
    c_inverter: { label: 'Product — Solar Inverter', bul: [
      'Solar ki DC bijli ko ghar ki AC bijli me badalta hai',
      'Ghar ke load sahi tareeke se chalte hain',
      'Over load aur short circuit se protection',
      'Warranty manufacturer ke niyam anusaar'], how: '' },
    c_battery: { label: 'Product — Battery', bul: [
      'Bijli store karke light jaane par bhi kaam chalta hai',
      'Raat ko solar bijli ka istemal',
      'Sahi sthaan, hawa aur dekhbhaal se lambi umar',
      'Warranty manufacturer ke niyam anusaar'], how: '' },
    c_structure: { label: 'Product — Solar Structure', bul: [
      'Panel ko mazbooti se thamta hai, tez hawa me bhi',
      'Galvanised (GI / HDGI) structure zang se bachav karta hai',
      'Sahi jhukaav se zyada dhoop mil sakti hai'], how: '' },
    c_dbx: { label: 'Product — ACDB / DCDB', bul: [
      'Bijli ke surge aur over load se system ki suraksha',
      'Solar system ko jodne aur kaatne ka surakshit tareeka'], how: '' },
    c_earth: { label: 'Product — Earthing / Lightning Arrester', bul: [
      'Bijli girne aur leakage se system aur logo ki suraksha',
      'Sahi earthing se system ki lambi umar'], how: '' },
    c_light: { label: 'Product — Solar Light', bul: [
      'Bijli bill ke bina roshni, solar se chalti hai',
      'Wiring ki zaroorat kam, aasaan installation',
      'Sadak, bagiche aur deewar ke liye upyogi'], how: '' },
    c_camera: { label: 'Product — Solar Camera', bul: [
      'Bijli ya wiring ke bina nigrani',
      'Dur-daraaz jagah par bhi lagaya ja sakta hai'], how: '' },
    c_home: { label: 'Product — Home Inverter / Battery', bul: [
      'Light jaane par ghar ke zaroori kaam chalte rehte hain',
      'Aasaan installation aur use',
      'Warranty manufacturer ke niyam anusaar'], how: '' },
    c_bos: { label: 'Product — BOS (cable, connector, protection)', bul: [
      'System ko surakshit aur sahi tareeke se jodta hai',
      'Achhe cable aur connector se bijli ka nuksan kam',
      'Solar ke liye bane (UV, mausam sahne wale) saaman'], how: '' },
    c_maint: { label: 'Product — Maintenance / Package', bul: [
      'System ki dekhbhaal aasaan aur sahi samay par',
      'Plant ki generation bani rehti hai'], how: '' }
  };
  var KEYS = Object.keys(T).map(function (k) { return { k: k, label: T[k].label, def: T[k].bul.slice() }; });

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function num(n) { n = parseFloat(n); return isFinite(n) ? n : 0; }
  function inr(n) { return '₹' + Math.round(num(n)).toLocaleString('en-IN'); }

  function catKey(l) {
    var c = String(l.category || '').toLowerCase(), sc = String(l.subcategory || '').toLowerCase(), nm = String(l.name || l.title || '').toLowerCase(), s = c + ' ' + sc + ' ' + nm;
    if (/panel|module/.test(c) || (!c && /panel|module|mono|topcon|bifacial/.test(nm))) return 'c_panel';
    if (/home appliance|home inverter|home batter/.test(c + ' ' + sc)) return 'c_home';
    if (/inverter/.test(c) || (!c && /inverter|pcu/.test(nm))) return 'c_inverter';
    if (/batter/.test(c) || (!c && /battery|batteries/.test(nm))) return 'c_battery';
    if (/structure/.test(c) || (!c && /structure|stand/.test(nm))) return 'c_structure';
    if (/acdb|dcdb/.test(c) || (!c && /acdb|dcdb/.test(nm))) return 'c_dbx';
    if (/earth|arrest|\bla\b/.test(c) || (!c && /earthing|arrester/.test(nm))) return 'c_earth';
    if (/camera/.test(c) || (!c && /camera/.test(nm))) return 'c_camera';
    if (/light/.test(c) || (!c && /street light|garden light|wall light|solar light/.test(nm))) return 'c_light';
    if (/bos/.test(c) || /cable|mc4|connector|conduit|mcb|spd|isolator|fuse|lug/.test(s)) return 'c_bos';
    if (/maintenance|package/.test(c)) return 'c_maint';
    return 'c_gen'; /* pehchaan nahi hui: card nahi banta (galat jankari se behtar kuch na dikhana) */
  }
  function servKeys(o) {
    var s = (o.lines || []).map(function (l) { return String(l.name || l.title || '') + ' ' + String(l.desc || ''); }).join(' ').toLowerCase() + ' ' + String(o.ctype || '').toLowerCase(), out = [];
    if (/amc|annual maint|maintenance contract/.test(s)) out.push('s_amc');
    if (/site visit|survey|inspection/.test(s)) out.push('s_visit');
    if (/clean|wash|safai/.test(s)) out.push('s_clean');
    if (/install|shift|erection|commission/.test(s)) out.push('s_inst');
    if (/net ?meter|discom/.test(s)) out.push('s_nm');
    if (!out.length) out.push('s_gen');
    return out.slice(0, 3);
  }
  function projKey(ctype, sys) {
    if (ctype === 'Commercial') return 'p_comm';
    if (ctype === 'Industrial') return 'p_ind';
    if (ctype === 'VFD') return 'p_vfd';
    return sys === 'off' ? 'p_off' : sys === 'hy' ? 'p_hy' : 'p_on';
  }
  function pick(k, ov) { var t = T[k], b = ov && ov[k]; b = Array.isArray(b) ? b.filter(function (x) { return String(x || '').trim(); }) : null; return { bul: (b && b.length ? b : t.bul).map(String), how: t.how, label: t.label }; }

  /* o = { lines, ctype, kw, sys, tariff, gen, grand, subsidy, ov } -> { cards:[...] } */
  function build(o) {
    o = o || {}; var lines = Array.isArray(o.lines) ? o.lines : [], ov = o.ov || {}, ct = o.ctype || '', cards = [];
    var isProj = PROJ.indexOf(ct) >= 0, isServ = SERV.indexOf(ct) >= 0;
    var pl = lines.filter(function (l) { return (l.kind || 'product') === 'project'; })[0];
    if (isProj || pl) {
      var kw = num((pl && pl.kw) || o.kw), sys = (pl && pl.sys) || o.sys || 'on', k = projKey(isProj ? ct : 'Residential', sys), t = pick(k, ov);
      var c = { k: 'project', key: k, title: 'Aapka solar project' + (kw > 0 ? ' — ' + kw + ' kW' : ''), name: pl ? (pl.name || '') : '', bullets: t.bul, how: t.how, calc: null };
      if (kw > 0) {
        var gen = num(o.gen) > 0 ? num(o.gen) : 4, tar = num(o.tariff) > 0 ? num(o.tariff) : 7, uy = kw * gen * 365, ry = uy * tar, net = Math.max(0, num(o.grand) - num(o.subsidy));
        c.calc = { kw: kw, units_day: kw * gen, units_year: Math.round(uy), save_month: Math.round(ry / 12), save_year: Math.round(ry), co2_t: Math.round(uy * 0.82 / 100) / 10,
          payback: num(o.grand) > 0 && ry > 0 ? Math.round(net / ry * 10) / 10 : null, gen: gen, tariff: tar, subsidy_in: num(o.subsidy) > 0 };
      }
      cards.push(c);
    } else if (isServ) {
      servKeys(o).forEach(function (k) { var t = pick(k, ov); cards.push({ k: 'service', key: k, title: t.label.replace(/^Service — /, ''), bullets: t.bul, how: t.how }); });
    } else {
      var by = {}, ord = [];
      lines.forEach(function (l) { if (!(l.name || l.title)) return; var k = catKey(l); if (!by[k]) { by[k] = []; ord.push(k); } by[k].push(String(l.name || l.title)); });
      ord.filter(function (k) { return k !== 'c_gen'; }).slice(0, 6).forEach(function (k) { var t = pick(k, ov); cards.push({ k: 'product', key: k, title: t.label.replace(/^Product — /, ''), items: by[k].slice(0, 4), bullets: t.bul, how: t.how }); });
    }
    return { cards: cards };
  }

  /* inline-styled html (CRM bill + customer print dono me chalta hai) */
  function html(res, opt) {
    opt = opt || {}; var cards = (res && res.cards) || []; if (!cards.length) return '';
    var h = '<div style="margin:12px 0 6px;font-size:13px"><b>Aapko kya milega</b> <span style="color:#555;font-size:10.5px">(jankari — bill ki rakam par koi asar nahi)</span></div>';
    cards.forEach(function (c) {
      h += '<div class="pg" style="margin:6px 0;padding:8px 10px;border:1px solid #d7e4da;background:#fafdfb;border-radius:6px;font-size:12px;line-height:1.4">' +
        '<b>' + esc(c.title) + '</b>' + (c.items && c.items.length ? '<div style="color:#555;font-size:11px">' + c.items.map(esc).join(' · ') + '</div>' : '') +
        '<ul style="margin:4px 0 0 16px;padding:0">' + c.bullets.map(function (b) { return '<li>' + esc(b) + '</li>'; }).join('') + '</ul>' +
        (c.how ? '<div style="margin-top:4px;color:#333"><b>Kaise kaam karta hai:</b> ' + esc(c.how) + '</div>' : '');
      if (c.calc) {
        var k = c.calc;
        h += '<table style="margin-top:6px;width:100%;border-collapse:collapse;font-size:12px">' +
          '<tr><td>Roz lagbhag bijli</td><td style="text-align:right"><b>' + (Math.round(k.units_day * 10) / 10) + ' unit</b></td></tr>' +
          '<tr><td>Saal me lagbhag bijli</td><td style="text-align:right"><b>' + k.units_year.toLocaleString('en-IN') + ' unit</b></td></tr>' +
          '<tr><td>Mahine ki anumanit bachat</td><td style="text-align:right"><b>' + inr(k.save_month) + '</b></td></tr>' +
          '<tr><td>Saal ki anumanit bachat</td><td style="text-align:right"><b>' + inr(k.save_year) + '</b></td></tr>' +
          (k.payback != null ? '<tr><td>Kharch wapas aane me lagbhag' + (k.subsidy_in ? ' (subsidy ke baad ke kharch par)' : '') + '</td><td style="text-align:right"><b>' + k.payback + ' saal</b></td></tr>' : '') +
          '<tr><td>CO₂ me kami (saal)</td><td style="text-align:right"><b>~' + k.co2_t + ' ton</b></td></tr></table>' +
          '<div style="margin-top:3px;color:#666;font-size:10.5px">Anumaan: ' + k.gen + ' unit/kW/din aur ₹' + k.tariff + '/unit ke hisaab se. Asli bachat dhoop, mausam, chhat ki disha aur bijli tariff par nirbhar hai — ye pakka wada nahi hai.</div>';
      }
      h += '</div>';
    });
    return h;
  }

  var API = { build: build, html: html, KEYS: KEYS, PROJ: PROJ, SERV: SERV, catKey: catKey };
  if (typeof module !== 'undefined' && module.exports) module.exports = API; else root.SPBEN = API;
})(typeof window !== 'undefined' ? window : this);
